#!/usr/bin/env python3
"""Упавшие тесты из .xcresult — имя, сообщение, и ничего лишнего.

    xcrun xcresulttool get test-results tests --path X.xcresult | scripts/failures.py

Один и тот же разбор нужен и check.sh, и CI; лог xcodebuild для этого не
годится — в нём десятки тысяч строк и падения размазаны по ним.
"""

import json
import sys


def messages(node, argument=""):
    """Сообщения о падении теста. У параметризованного теста Swift Testing
    они лежат не под самим тестом, а под узлом упавшего аргумента — и
    тогда важно сказать, на каком аргументе упало."""
    for child in node.get("children", []):
        kind = child.get("nodeType")
        if kind == "Failure Message":
            yield argument, child.get("name", "")
        elif kind == "Arguments" and child.get("result") == "Failed":
            yield from messages(child, child.get("name", ""))


def walk(node, path):
    name = node.get("name", "")
    if node.get("nodeType") == "Test Case" and node.get("result") == "Failed":
        for argument, message in messages(node):
            where = f"{'/'.join(path)}/{name}" + (f" [{argument}]" if argument else "")
            print(f"{where}\n    {message}")
    for child in node.get("children", []):
        walk(child, path + [name] if name else path)


def main():
    for root in json.load(sys.stdin).get("testNodes", []):
        walk(root, [])


if __name__ == "__main__":
    main()
