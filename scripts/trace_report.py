#!/usr/bin/env python3
"""Сводка по трассе Instruments — текстом, без открытия Instruments.

    scripts/trace_report.py build/profile/Leaks-….trace
    scripts/trace_report.py build/profile/Time-Profiler-….trace [--top 20]

Time Profiler: зависания главного потока и функции приложения, на которые
ушло больше всего его времени. Leaks: найденные утечки и, отдельно, сколько
экземпляров каждого класса приложения создано и сколько осталось живыми к
концу записи. Второе важнее, чем кажется: Leaks видит только память, на
которую никто не ссылается, а экран, который держит живая Task или
подписка, достижим — и утечкой для него не считается.

Сравнивать трассы «до» и «после» можно только на одном сценарии и одной
сборке: scripts/profile.sh даёт и то и другое.
"""

import argparse
import collections
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

# В Debug код приложения лежит в echos.debug.dylib, в Release — в echos.
APP_BINARIES = {"echos", "echos.debug.dylib"}
APP_CLASS = re.compile(r"^echos\.\w+$")
# Точка входа есть в каждом стеке главного потока и ничего не говорит.
ENTRY_POINTS = ("$main()", "UIApplicationDelegate.main()", "__debug_main_executable_dylib_entry_point")


def export(trace: str, xpath: str) -> ET.Element:
    out = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath],
                         check=True, capture_output=True, text=True).stdout
    return ET.fromstring(out)


def toc(trace: str) -> str:
    return subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--toc"],
                          check=True, capture_output=True, text=True).stdout


class Refs:
    """xctrace сжимает повторы: элемент с id встречается один раз, дальше —
    ссылки ref на него."""

    def __init__(self):
        self.by_id = {}

    def walk(self, element: ET.Element) -> None:
        if element.get("id") is not None:
            self.by_id[element.get("id")] = element
        for child in element:
            self.walk(child)

    def __call__(self, element: ET.Element | None) -> ET.Element | None:
        if element is None:
            return None
        return self.by_id[element.get("ref")] if element.get("ref") else element


# MARK: - Time Profiler

def hangs(trace: str) -> list[str]:
    table = export(trace, '/trace-toc/run[@number="1"]/data/table[@schema="potential-hangs"]')
    out = []
    for row in table.iter("row"):
        cells = {child.tag: child.get("fmt", "") for child in row}
        out.append(f"{cells.get('start-time', '?')}  {cells.get('duration', '?')}  {cells.get('hang-type', '')}")
    return out


def main_thread_functions(trace: str, focus: str | None = None
                          ) -> tuple[int, collections.Counter, collections.Counter, collections.Counter]:
    table = export(trace, '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]')
    ref = Refs()
    inclusive, leaf, callees = collections.Counter(), collections.Counter(), collections.Counter()
    samples = 0
    for row in table.iter("row"):
        ref.walk(row)
        thread = ref(row.find("thread"))
        if thread is None or "Main Thread" not in thread.get("fmt", ""):
            continue
        # Не `or`: элемент без детей в ElementTree ложен.
        backtrace = row.find("tagged-backtrace")
        if backtrace is None:
            backtrace = row.find("backtrace")
        backtrace = ref(backtrace)
        if backtrace is None:
            continue
        samples += 1
        app, names = [], []
        for frame in backtrace.iter("frame"):
            frame = ref(frame)
            binary = ref(frame.find("binary"))
            names.append(frame.get("name", "?"))
            if binary is not None and binary.get("name") in APP_BINARIES:
                app.append(frame.get("name", "?"))
        # Стек идёт от листа к корню: вызванное функцией лежит перед ней.
        if focus:
            hit = next((i for i, name in enumerate(names) if name.startswith(focus)), None)
            if hit:
                callees[names[hit - 1]] += 1
        app = [name for name in app if not name.endswith(ENTRY_POINTS)]
        if app:
            leaf[app[0]] += 1
            for name in set(app):
                inclusive[name] += 1
    return samples, inclusive, leaf, callees


def time_profiler(trace: str, top: int, focus: str | None) -> None:
    found = hangs(trace)
    print(f"Зависания главного потока: {len(found) or 'нет'}")
    for line in found:
        print(f"  {line}")

    samples, inclusive, leaf, callees = main_thread_functions(trace, focus)
    print(f"\nГлавный поток: {samples} мс работы (сэмпл — 1 мс)")
    print("\nФункции приложения, включая то, что они вызвали:")
    for name, ms in inclusive.most_common(top):
        print(f"  {ms:6d} мс  {name[:120]}")
    print("\nГде приложение было верхним в стеке:")
    for name, ms in leaf.most_common(top):
        print(f"  {ms:6d} мс  {name[:120]}")
    if focus:
        print(f"\nЧто вызывала {focus} — {sum(callees.values())} мс:")
        for name, ms in callees.most_common(top):
            print(f"  {ms:6d} мс  {name[:120]}")


# MARK: - Leaks

def leaks(trace: str) -> None:
    table = export(trace, '/trace-toc/run[@number="1"]/tracks/track[@name="Leaks"]/details/detail[@name="Leaks"]')
    rows = list(table.iter("row"))
    print(f"Утечки (недостижимая память): {len(rows) or 'нет'}")
    for row in rows[:20]:
        print("  " + " ".join(f"{k}={v}" for k, v in row.attrib.items()))

    stats = export(trace, '/trace-toc/run[@number="1"]/tracks/track[@name="Allocations"]/details/detail[@name="Statistics"]')
    classes = {}
    for row in stats.iter("row"):
        name = row.get("category", "")
        if APP_CLASS.match(name) and name not in classes:
            classes[name] = (int(row.get("count-persistent", 0)), int(row.get("count-total", 0)))
    print("\nКлассы приложения: живых к концу записи / создано за запись")
    for name, (alive, total) in sorted(classes.items(), key=lambda item: (-item[1][0], item[0])):
        mark = "  ← не освободились" if alive and alive == total and total > 1 else ""
        print(f"  {name:40} {alive:4d} / {total}{mark}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace")
    parser.add_argument("--top", type=int, default=15)
    parser.add_argument("--focus", help="функция, чьи вызовы разложить: начало имени, как в стеке")
    args = parser.parse_args()

    contents = toc(args.trace)
    if 'name="Leaks"' in contents:
        leaks(args.trace)
    elif 'schema="time-profile"' in contents:
        time_profiler(args.trace, args.top, args.focus)
    else:
        print("Сводка умеет Leaks и Time Profiler; эту трассу открой в Instruments.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
