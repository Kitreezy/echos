#!/usr/bin/env python3
"""Упавшие тесты из .xcresult — имя, сообщение, и ничего лишнего.

    xcrun xcresulttool get test-results tests --path X.xcresult | scripts/failures.py

Один и тот же разбор нужен и check.sh, и CI; лог xcodebuild для этого не
годится — в нём десятки тысяч строк и падения размазаны по ним.
"""

import json
import sys


def walk(node, path):
    name = node.get("name", "")
    if node.get("nodeType") == "Test Case" and node.get("result") == "Failed":
        for child in node.get("children", []):
            if child.get("nodeType") == "Failure Message":
                print(f"{'/'.join(path)}/{name}\n    {child.get('name', '')}")
    for child in node.get("children", []):
        walk(child, path + [name] if name else path)


for root in json.load(sys.stdin).get("testNodes", []):
    walk(root, [])
