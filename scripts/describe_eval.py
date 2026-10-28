#!/usr/bin/env python3
"""Насколько описания describe.py близки к тем, что написал автор.

    scripts/describe_eval.py            все PR из набора
    scripts/describe_eval.py 26 22      только эти

Набор — влитые PR с описаниями, написанными руками. Три других PR служат
образцами стиля в describe-prompt.txt и в набор не входят: на них модель
просто повторила бы образец.

Для каждого PR — два описания: по коммитам и diff и только по diff, без
сообщений коммитов. Второе показывает, что модель понимает из самого кода:
сообщения коммитов в echos подробные, и описание по ним может оказаться
пересказом. Каждое сравнивает с авторским проверяющий вызов модели:

- полнота — доля утверждений автора (что изменилось и почему), которые есть
  в сгенерированном;
- выдумки — утверждения, которых нет ни в коммитах, ни в diff;
- стиль — заголовки, оценки, перечень файлов, подпись генератора.

Проверяющий — модель того же семейства, и это слабее человека. Поэтому все
тексты лежат в build/describe-eval/ — их стоит прочитать, а не только цифры.
"""

import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import describe

EVAL_SET = [26, 22, 21, 19, 18, 17, 13, 12, 11, 10]
OUT = describe.ROOT / "build" / "describe-eval"

JUDGE = """Ты проверяешь сгенерированное описание pull request'а, сравнивая его с описанием, которое написал автор.

1. Выпиши из авторского описания все утверждения о сделанном — что изменилось и почему, — каждое коротко,
   своими словами. Для каждого реши, есть ли оно по смыслу в сгенерированном (covered: true/false).
2. Выпиши утверждения сгенерированного описания, которые не подтверждаются коммитами и diff или противоречат
   коду, — выдумки. Сверяйся с коммитами и diff, а не с авторским описанием: подробность, которой нет у автора,
   но есть в коде, — не выдумка. Подтвердилось — в список не пиши; список только из настоящих выдумок.
3. Выпиши нарушения стиля сгенерированного: заголовки, оценочные слова («удобно», «надёжно», «значительно»),
   перечисление файлов, упоминание того, кто написал описание.

Ответ — только один блок ```json:
{"points": [{"fact": "...", "covered": true}], "invented": ["..."], "style": ["..."]}
"""


def ask(system: str, prompt: str) -> str:
    done = subprocess.run(
        ["claude", "-p", "--output-format", "text", "--system-prompt", system,
         "--disallowedTools", "Bash", "Edit", "Write", "Read", "Glob", "Grep", "WebFetch", "WebSearch", "Task"],
        input=prompt, capture_output=True, text=True, timeout=900)
    if done.returncode != 0:
        raise RuntimeError((done.stderr.strip() or done.stdout.strip())[-300:])
    return done.stdout


def judge(author: str, generated: str, commits: list[str], diff: str) -> dict:
    body, _ = describe.trim(diff)
    prompt = (f"Описание автора:\n\n{author}\n\n===\n\nСгенерированное описание:\n\n{generated}\n\n===\n\n"
              "Коммиты:\n\n" + "\n\n---\n\n".join(commits) + f"\n\n===\n\nDiff:\n{body}")
    answer = ask(JUDGE, prompt)
    blocks = re.findall(r"```(?:json)?\s*\n(.*?)```", answer, re.S)
    return json.loads(blocks[-1])


def evaluate(number: int) -> dict:
    data = json.loads(describe.run("gh", "pr", "view", str(number), "--json", "title,body"))
    title, commits, diff = describe.from_pr(number)
    result = {"pr": number, "title": data["title"]}
    folder = OUT / str(number)
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "author.md").write_text(data["body"], encoding="utf-8")
    for mode, with_commits in (("commits", True), ("diff", False)):
        # Готовое не пересчитывается: прогон — сорок вызовов модели, и
        # оборванный лимитом продолжается с места обрыва.
        text_file, verdict_file = folder / f"{mode}.md", folder / f"{mode}.json"
        if text_file.exists() and verdict_file.exists():
            generated = text_file.read_text(encoding="utf-8")
            verdict = json.loads(verdict_file.read_text(encoding="utf-8"))
        else:
            generated = describe.describe(title, commits, diff, with_commits=with_commits)
            text_file.write_text(generated, encoding="utf-8")
            verdict = judge(data["body"], generated, commits, diff)
            verdict_file.write_text(json.dumps(verdict, ensure_ascii=False, indent=2), encoding="utf-8")
        points = verdict.get("points", [])
        result[mode] = {
            "covered": sum(bool(p.get("covered")) for p in points),
            "points": len(points),
            "invented": verdict.get("invented", []),
            "style": verdict.get("style", []),
            "length": len(generated),
        }
    result["author_length"] = len(data["body"])
    return result


def main() -> int:
    numbers = [int(a) for a in sys.argv[1:]] or EVAL_SET
    # Четыре PR одновременно: каждый — четыре вызова модели по полминуты.
    def safe(number: int) -> dict | None:
        # Сбой одного PR — лимит, сеть — не роняет остальные.
        try:
            return evaluate(number)
        except (RuntimeError, ValueError, KeyError, subprocess.TimeoutExpired, SystemExit) as error:
            print(f"#{number}: не вышло — {error}", file=sys.stderr)
            return None

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = [r for r in pool.map(safe, numbers) if r]
    if not results:
        return 1
    (OUT / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"{'PR':<5}{'полнота (коммиты)':<20}{'полнота (diff)':<17}{'выдумки к/d':<14}{'стиль к/d':<12}длина авт./к/d")
    totals = {m: [0, 0, 0, 0] for m in ("commits", "diff")}
    for r in results:
        c, d = r["commits"], r["diff"]
        for mode in ("commits", "diff"):
            t = totals[mode]
            t[0] += r[mode]["covered"]; t[1] += r[mode]["points"]
            t[2] += len(r[mode]["invented"]); t[3] += len(r[mode]["style"])
        print(f"#{r['pr']:<4}{c['covered']}/{c['points']:<17}{d['covered']}/{d['points']:<14}"
              f"{len(c['invented'])}/{len(d['invented']):<12}{len(c['style'])}/{len(d['style']):<10}"
              f"{r['author_length']}/{c['length']}/{d['length']}")
    for mode, label in (("commits", "по коммитам и diff"), ("diff", "только по diff")):
        covered, points, invented, style = totals[mode]
        print(f"\n{label}: полнота {covered}/{points} ({covered / max(points, 1):.0%}), выдумок {invented}, нарушений стиля {style}")
    print(f"\nТексты и разборы — {OUT.relative_to(describe.ROOT)}/<номер PR>/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
