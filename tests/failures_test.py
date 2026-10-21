#!/usr/bin/env python3
"""Разбор упавших тестов из .xcresult: XCTest и Swift Testing.

Запуск: python3 tests/failures_test.py
"""

import json
import subprocess
import sys
import unittest
from pathlib import Path

FAILURES = Path(__file__).resolve().parent.parent / "scripts" / "failures.py"


def run(nodes: list[dict]) -> str:
    done = subprocess.run([sys.executable, str(FAILURES)], input=json.dumps({"testNodes": nodes}),
                          capture_output=True, text=True)
    return done.stdout


def case(name, children, result="Failed"):
    return {"nodeType": "Test Case", "name": name, "result": result, "children": children}


def failure(text):
    return {"nodeType": "Failure Message", "name": text}


class FailuresTests(unittest.TestCase):

    def test_plain_failure_is_reported(self):
        out = run([{"nodeType": "Test Suite", "name": "Peers", "children": [
            case("isActive()", [failure("Expectation failed: peer.isActive")])]}])

        self.assertIn("Peers/isActive()", out)
        self.assertIn("Expectation failed: peer.isActive", out)

    def test_failed_argument_is_named(self):
        out = run([{"nodeType": "Test Suite", "name": "Fingerprint", "children": [
            case("somethingElse_isLeftAlone(_:)", [
                {"nodeType": "Arguments", "name": '"bob-address"', "result": "Passed", "children": []},
                {"nodeType": "Arguments", "name": '"Борис"', "result": "Failed",
                 "children": [failure("Expectation failed: display == address")]},
            ])]}])

        self.assertIn('somethingElse_isLeftAlone(_:) ["Борис"]', out, "Видно, на каком аргументе упало")
        self.assertIn("display == address", out)
        self.assertNotIn("bob-address", out, "Прошедшие аргументы — не падения")

    def test_passed_tests_are_silent(self):
        self.assertEqual(run([case("ok()", [], result="Passed")]), "")


if __name__ == "__main__":
    unittest.main()
