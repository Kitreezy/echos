#!/usr/bin/env python3
"""Описание pull request'а по коммитам и diff.

    scripts/describe.py                  ветка к origin/develop
    scripts/describe.py --base main      к другой базе
    scripts/describe.py --head feat/x    другая ветка, не переключаясь на неё
    scripts/describe.py --pr 27          уже открытый или влитый PR — через gh;
                                         так описания проверяются на старых PR
    --diff-only                          без сообщений коммитов: видно, что
                                         модель понимает из самого кода

Пишет в стиле scripts/describe-prompt.txt — там правила и три описания из
истории проекта. Модель — Claude через `claude -p`, без инструментов: всё
нужное в промпте. Код возврата 2 — описания нет, причина в stderr.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROMPT = ROOT / "scripts" / "describe-prompt.txt"

# Шум: машинные файлы, которые меняются сами и ничего не говорят ревьюеру.
NOISE = re.compile(r"(\.pbxproj|Package\.resolved|Gemfile\.lock|\.xcuserstate|\.png|\.jpg|\.pdf)$")
FILE_LIMIT = 15_000
TOTAL_LIMIT = 150_000


def run(*args: str) -> str:
    done = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit(f"{' '.join(args[:3])}…: {done.stderr.strip()[:300]}")
    return done.stdout


def from_branch(base: str, head: str = "HEAD") -> tuple[str, list[str], str]:
    log = run("git", "log", "--reverse", "--format=%s%n%n%b%x1e", f"{base}..{head}")
    commits = [c.strip() for c in log.split("\x1e") if c.strip()]
    # Заголовка у ветки нет. Последний коммит на эту роль не годится — он
    # про последнее, а не про главное; имя ветки хотя бы говорит, о чём она.
    name = run("git", "rev-parse", "--abbrev-ref", head).strip()
    return f"не задан, ветка {name}", commits, run("git", "diff", f"{base}...{head}")


def from_pr(number: int) -> tuple[str, list[str], str]:
    data = json.loads(run("gh", "pr", "view", str(number), "--json", "title,commits"))
    commits = [f"{c['messageHeadline']}\n\n{c.get('messageBody', '')}".strip() for c in data["commits"]]
    # Слияния base в ветку — не изменения ветки, а их шум.
    commits = [c for c in commits if not c.startswith("Merge ")]
    return data["title"], commits, run("gh", "pr", "diff", str(number))


def trim(diff: str) -> tuple[str, list[str]]:
    """Diff без шума и не длиннее предела. Обрезанное — названо: модель
    должна знать, что видит не всё, иначе выдумает про то, чего не видела."""
    kept, dropped, total = [], [], 0
    for block in re.split(r"(?=^diff --git )", diff, flags=re.M):
        if not block.strip():
            continue
        name = re.match(r"diff --git a/(\S+)", block)
        path = name.group(1) if name else "?"
        if NOISE.search(path):
            dropped.append(f"{path} (машинный файл)")
            continue
        if len(block) > FILE_LIMIT:
            block = block[:FILE_LIMIT] + f"\n… файл обрезан, показано {FILE_LIMIT} знаков из {len(block)}\n"
        if total + len(block) > TOTAL_LIMIT:
            dropped.append(f"{path} (не влез)")
            continue
        kept.append(block)
        total += len(block)
    return "".join(kept), dropped


def stats(diff: str) -> str:
    """Файлы и сколько в них изменилось — карта перед самим diff."""
    lines = []
    for block in re.split(r"(?=^diff --git )", diff, flags=re.M):
        if m := re.match(r"diff --git a/(\S+)", block):
            added = len(re.findall(r"^\+(?!\+\+)", block, re.M))
            removed = len(re.findall(r"^-(?!--)", block, re.M))
            lines.append(f"{m.group(1)}  +{added} −{removed}")
    return "\n".join(lines)


def describe(title: str, commits: list[str], diff: str, with_commits: bool = True) -> str:
    body, dropped = trim(diff)
    parts = [f"Заголовок PR: {title}"]
    if with_commits:
        parts.append("Коммиты по порядку:\n\n" + "\n\n---\n\n".join(commits))
    parts.append("Изменённые файлы:\n" + stats(diff))
    if dropped:
        parts.append("Не показано в diff: " + ", ".join(dropped))
    parts.append("Diff:\n" + body)

    done = subprocess.run(
        ["claude", "-p", "--output-format", "text", "--system-prompt", PROMPT.read_text(encoding="utf-8"),
         "--disallowedTools", "Bash", "Edit", "Write", "Read", "Glob", "Grep", "WebFetch", "WebSearch", "Task"],
        input="\n\n".join(parts), capture_output=True, text=True, timeout=900)
    if done.returncode != 0:
        reason = (done.stderr.strip() or done.stdout.strip())[-300:]
        raise RuntimeError(f"claude вернул {done.returncode}: {reason}")
    return clean(done.stdout)


def clean(text: str) -> str:
    """Подпись генератора — не часть описания. Модели велено её не ставить,
    но проверка дешевле, чем вера."""
    lines = [l for l in text.strip().splitlines()
             if not re.search(r"Generated with|Co-Authored-By|🤖", l, re.I)]
    return "\n".join(lines).strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="origin/develop")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--pr", type=int)
    parser.add_argument("--diff-only", action="store_true")
    args = parser.parse_args()

    title, commits, diff = from_pr(args.pr) if args.pr else from_branch(args.base, args.head)
    if not diff.strip():
        print("diff пуст — описывать нечего", file=sys.stderr)
        return 2
    try:
        print(describe(title, commits, diff, with_commits=not args.diff_only))
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(f"описания нет: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
