#!/usr/bin/env python3
"""Покрытие приложения тестами — и порог, ниже которого CI красный.

    xcrun xccov view --report --json X.xcresult | scripts/coverage.py --min 68

Считается по строкам таргета echos.app, кроме папок из --exclude (по
умолчанию Views). Интерфейс проверяют UI-тесты плана Accessibility, в этот
прогон они не входят. С Views в знаменателе цифра падала бы от любого нового
экрана и ничего не говорила бы о логике, где ошибки дороже.

Порог — храповик: он поднимается вслед за покрытием и не опускается. Поднять
его — поменять число в .github/workflows/ci.yml. Опускать — только с
объяснением в описании pull request'а, почему тестов стало меньше.

Печатает таблицу по папкам; в CI она же уходит в сводку прогона.
"""

import argparse
import json
import os
import sys
from collections import defaultdict
from pathlib import PurePosixPath

APP_TARGET = "echos.app"


def folder(path: str) -> str:
    """Папка внутри исходников приложения: echos/Services/X.swift → Services."""
    parts = PurePosixPath(path).parts
    # Исходники лежат в <репозиторий>/echos/, и сам репозиторий называется
    # так же, поэтому берётся последнее вхождение.
    inside = len(parts) - 1 - parts[::-1].index("echos") if "echos" in parts else 0
    rest = parts[inside + 1:]
    return rest[0] if len(rest) > 1 else "(корень)"


def summarize(report: dict, exclude: set[str]) -> tuple[dict, int, int]:
    target = next((t for t in report.get("targets", []) if t.get("name") == APP_TARGET), None)
    if target is None:
        raise SystemExit(f"В отчёте нет таргета {APP_TARGET} — покрытие не собиралось?")

    folders = defaultdict(lambda: [0, 0])
    for file in target.get("files", []):
        counts = folders[folder(file["path"])]
        counts[0] += file.get("coveredLines", 0)
        counts[1] += file.get("executableLines", 0)

    covered = sum(c for name, (c, _) in folders.items() if name not in exclude)
    total = sum(t for name, (_, t) in folders.items() if name not in exclude)
    return folders, covered, total


def percent(covered: int, total: int) -> float:
    return 100.0 * covered / total if total else 100.0


def table(folders: dict, exclude: set[str]) -> str:
    rows = ["| Папка | Покрытие | Строк |", "|---|---:|---:|"]
    for name, (covered, total) in sorted(folders.items(), key=lambda item: -item[1][1]):
        note = " (не в пороге)" if name in exclude else ""
        rows.append(f"| {name}{note} | {percent(covered, total):.1f}% | {covered}/{total} |")
    return "\n".join(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--min", type=float, required=True, help="порог, проценты")
    parser.add_argument("--exclude", action="append", default=None,
                        help="папка, которая не идёт в порог; можно несколько раз")
    args = parser.parse_args()
    exclude = set(args.exclude or ["Views"])

    folders, covered, total = summarize(json.load(sys.stdin), exclude)
    value = percent(covered, total)
    passed = value >= args.min

    verdict = (f"Покрытие {value:.1f}% при пороге {args.min:.1f}%"
               + ("" if passed else " — ниже порога"))
    report = f"{verdict}\n\n{table(folders, exclude)}\n"
    print(report)

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as out:
            out.write(f"### Покрытие\n\n{report}\n")

    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
