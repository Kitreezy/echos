#!/usr/bin/env python3
"""Журнал изменений и заметки к релизу — из истории коммитов.

    scripts/changelog.py notes [--from REF] [--to REF]   заметки к релизу
    scripts/changelog.py file [--release vX.Y.Z]         CHANGELOG.md целиком
    scripts/changelog.py next-version                    какой версией выпускать
    scripts/changelog.py check RANGE                     формат коммитов в диапазоне
    scripts/changelog.py check-message FILE              формат одного сообщения

Источник один — заголовки коммитов в формате Conventional Commits:
`тип(область): Описание`. Отсюда же и требование к формату: журнал из
истории собирается ровно настолько, насколько история аккуратна, поэтому
`check` стоит в CI на каждый pull request, а `check-message` — в хуке
commit-msg.

В журнал попадает то, что видно пользователю: feat, fix, perf и всё
несовместимое. ci, test, docs и прочее внутреннее в журнал не идёт, а в
заметках к релизу свёрнуто под отдельный заголовок — его читают те, кто
приложение собирает, а не те, кто им пользуется.
"""

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import date

TYPES = ["feat", "fix", "perf", "refactor", "docs", "test", "ci", "build", "chore", "style", "revert"]

NOTHING_VISIBLE = "Без изменений, заметных снаружи."

# Заголовки разделов — в порядке, в котором их читают.
VISIBLE = {"feat": "Новое", "fix": "Исправлено", "perf": "Быстрее"}

SUBJECT = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^()\s][^()]*)\))?(?P<bang>!)?: (?P<text>\S.*)$")
BREAKING_FOOTER = re.compile(r"^BREAKING[ -]CHANGE: (?P<text>.+)$", re.MULTILINE)
PR_MERGE = re.compile(r"^Merge pull request #(?P<number>\d+) from \S+?/(?P<branch>\S+)")
# Слияние develop в main — выпуск, а не изменение: его коммиты уже
# принадлежат своим pull request'ам.
RELEASE_BRANCHES = {"develop", "main"}
PR_SQUASH = re.compile(r" \(#(?P<number>\d+)\)$")
VERSION_TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")

# Сообщения, которые git пишет сам: проверять в них нечего.
GENERATED = re.compile(r"^(Merge |Revert \"|fixup! |squash! |amend! )")


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


@dataclass
class Commit:
    sha: str
    type: str
    scope: str | None
    text: str
    breaking: str | None
    pull: int | None


# MARK: - Разбор

def parse_subject(subject: str) -> re.Match | None:
    match = SUBJECT.match(subject)
    if match and match["type"] in TYPES:
        return match
    return None


def pull_requests(to: str) -> dict[str, int]:
    """Какой коммит пришёл каким pull request'ом.

    Коммиты PR — линия первого родителя его ветки, до точки, где она
    отошла от базы. Именно первого: если ветка подтягивала в себя develop
    или main, пришедшие так коммиты лежат на вторых родителях, и без
    --first-parent PR присвоил бы себе чужое. При squash номер стоит в
    заголовке самого коммита, это разбирается в `commits`."""
    owners: dict[str, int] = {}
    for line in git("log", "--merges", "--format=%H %P%x1f%s", to).splitlines():
        heads, subject = line.split("\x1f", 1)
        match = PR_MERGE.match(subject)
        parents = heads.split()[1:]
        if not match or len(parents) != 2 or match["branch"] in RELEASE_BRANCHES:
            continue
        for sha in git("rev-list", "--first-parent", "--no-merges", f"{parents[0]}..{parents[1]}").split():
            # Коммит мог попасть в историю и через более поздний PR — первым
            # его принёс самый ранний, а log идёт от новых к старым.
            owners[sha] = int(match["number"])
    return owners


def commits(revisions: str, owners: dict[str, int]) -> tuple[list[Commit], list[str]]:
    """Коммиты диапазона: разобранные и те, что не в формате."""
    parsed, skipped = [], []
    raw = git("log", "--no-merges", "--format=%H%x1f%s%x1f%b%x1e", revisions)
    for record in filter(None, (r.strip("\n") for r in raw.split("\x1e"))):
        sha, subject, body = record.split("\x1f", 2)
        match = parse_subject(subject)
        if not match:
            skipped.append(f"{sha[:7]} {subject}")
            continue
        text = match["text"]
        squash = PR_SQUASH.search(text)
        pull = owners.get(sha)
        if squash:
            text = text[:squash.start()]
            pull = pull or int(squash["number"])
        footer = BREAKING_FOOTER.search(body)
        breaking = footer["text"].strip() if footer else (text if match["bang"] else None)
        parsed.append(Commit(sha, match["type"], match["scope"], text, breaking, pull))
    return parsed, skipped


# MARK: - Ссылки

def repository_url() -> str | None:
    try:
        url = git("remote", "get-url", "origin").strip()
    except subprocess.CalledProcessError:
        return None
    match = re.match(r"^(?:https://github\.com/|git@github\.com:)(?P<path>[^/]+/[^/]+?)(?:\.git)?$", url)
    return f"https://github.com/{match['path']}" if match else None


def reference(commit: Commit, repo: str | None) -> str:
    if commit.pull:
        return f"[#{commit.pull}]({repo}/pull/{commit.pull})" if repo else f"#{commit.pull}"
    short = commit.sha[:7]
    return f"[{short}]({repo}/commit/{commit.sha})" if repo else short


def entry(commit: Commit, repo: str | None, text: str | None = None) -> str:
    scope = f"**{commit.scope}:** " if commit.scope else ""
    return f"- {scope}{text or commit.text} ({reference(commit, repo)})"


# MARK: - Разделы

def sections(items: list[Commit], repo: str | None, internal: bool) -> str:
    """Тело раздела одной версии. Пусто — значит, пользователю нечего сказать."""
    out = []
    breaking = [c for c in items if c.breaking]
    if breaking:
        out.append("### Несовместимые изменения\n")
        out += [entry(c, repo, c.breaking) for c in breaking]
        out.append("")
    for kind, title in VISIBLE.items():
        group = [c for c in items if c.type == kind]
        if group:
            out.append(f"### {title}\n")
            out += [entry(c, repo) for c in group]
            out.append("")
    rest = [c for c in items if c.type not in VISIBLE and not c.breaking]
    if internal and rest:
        if not out:
            out.append(f"{NOTHING_VISIBLE}\n")
        out.append(f"<details><summary>Внутреннее — {len(rest)}</summary>\n")
        out += [f"- `{c.type}` " + entry(c, repo)[2:] for c in rest]
        out.append("\n</details>\n")
    return "\n".join(out).strip()


def tags(to: str = "HEAD") -> list[str]:
    """Теги версий, достижимые из `to`, от новых к старым."""
    found = [t for t in git("tag", "--list", "v*", "--merged", to).split() if VERSION_TAG.match(t)]
    return sorted(found, key=lambda t: tuple(map(int, VERSION_TAG.match(t).groups())), reverse=True)


def tag_date(tag: str) -> str:
    return git("log", "-1", "--format=%ad", "--date=short", tag).strip()


def changelog_file(release: str | None) -> str:
    repo = repository_url()
    owners = pull_requests("HEAD")
    versions = tags()
    out = ["# Журнал изменений",
           "",
           "Собирается из заголовков коммитов (`scripts/changelog.py file`).",
           "Правка руками пропадёт при следующей сборке.",
           ""]

    head_range = f"{versions[0]}..HEAD" if versions else "HEAD"
    unreleased = sections(commits(head_range, owners)[0], repo, internal=False)
    if release:
        title = f"## [{release.removeprefix('v')}] — {date.today().isoformat()}"
        out += [title, "", unreleased or NOTHING_VISIBLE, ""]
    elif unreleased:
        out += ["## Не выпущено", "", unreleased, ""]

    for index, tag in enumerate(versions):
        previous = versions[index + 1] if index + 1 < len(versions) else None
        span = f"{previous}..{tag}" if previous else tag
        body = sections(commits(span, owners)[0], repo, internal=False)
        out += [f"## [{tag.removeprefix('v')}] — {tag_date(tag)}", "",
                body or NOTHING_VISIBLE, ""]

    return "\n".join(out).rstrip() + "\n"


def release_notes(start: str | None, end: str) -> str:
    if start is None:
        previous = [t for t in tags(end) if git("rev-parse", f"{t}^{{commit}}").strip()
                    != git("rev-parse", f"{end}^{{commit}}").strip()]
        start = previous[0] if previous else None
    span = f"{start}..{end}" if start else end
    items, _ = commits(span, pull_requests(end))
    body = sections(items, repository_url(), internal=True)
    return (body or NOTHING_VISIBLE) + "\n"


def next_version() -> str:
    versions = tags()
    major, minor, patch = map(int, VERSION_TAG.match(versions[0]).groups()) if versions else (0, 0, 0)
    items, _ = commits(f"{versions[0]}..HEAD" if versions else "HEAD", {})
    if any(c.breaking for c in items):
        # До 1.0 несовместимое поднимает минорную: так принято в semver для 0.x.
        major, minor, patch = (major + 1, 0, 0) if major > 0 else (0, minor + 1, 0)
    elif any(c.type == "feat" for c in items) or not versions:
        minor, patch = minor + 1, 0
    else:
        patch += 1
    return f"v{major}.{minor}.{patch}"


# MARK: - Проверка формата

def problem(subject: str) -> str | None:
    if GENERATED.match(subject):
        return None
    match = SUBJECT.match(subject)
    if not match:
        return "нужен вид «тип(область): Описание»"
    if match["type"] not in TYPES:
        return f"неизвестный тип «{match['type']}», допустимы: {', '.join(TYPES)}"
    return None


def check(revisions: str) -> int:
    bad = []
    for line in git("log", "--no-merges", "--format=%h%x1f%s", revisions).splitlines():
        sha, subject = line.split("\x1f", 1)
        reason = problem(subject)
        if reason:
            bad.append(f"{sha} «{subject}» — {reason}")
    for line in bad:
        print(line)
    if bad:
        print("\nЖурнал собирается из заголовков коммитов, поэтому формат обязателен.\n"
              "Поправить: git rebase -i, reword у нужных коммитов.")
    return 1 if bad else 0


def check_message(path: str) -> int:
    with open(path, encoding="utf-8") as file:
        subject = next((line.rstrip("\n") for line in file if line.strip() and not line.startswith("#")), "")
    reason = problem(subject)
    if reason:
        print(f"«{subject}» — {reason}", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    notes = sub.add_parser("notes")
    notes.add_argument("--from", dest="start")
    notes.add_argument("--to", dest="end", default="HEAD")
    file = sub.add_parser("file")
    file.add_argument("--release")
    sub.add_parser("next-version")
    rng = sub.add_parser("check")
    rng.add_argument("range")
    msg = sub.add_parser("check-message")
    msg.add_argument("path")
    args = parser.parse_args()

    if args.command == "notes":
        print(release_notes(args.start, args.end), end="")
    elif args.command == "file":
        print(changelog_file(args.release), end="")
    elif args.command == "next-version":
        print(next_version())
    elif args.command == "check":
        return check(args.range)
    elif args.command == "check-message":
        return check_message(args.path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
