#!/usr/bin/env python3
"""Порог покрытия: что идёт в счёт и когда CI красный.

Запуск: python3 tests/coverage_test.py
"""

import json
import subprocess
import sys
import unittest
from pathlib import Path

COVERAGE = Path(__file__).resolve().parent.parent / "scripts" / "coverage.py"
ROOT = "/Users/runner/work/echos/echos/echos"


def run(files: list[dict], *args: str) -> subprocess.CompletedProcess:
    report = {"targets": [{"name": "echos.app", "files": files},
                          {"name": "echosTests.xctest", "files": []}]}
    return subprocess.run([sys.executable, str(COVERAGE), *args], input=json.dumps(report),
                          capture_output=True, text=True)


def file(path: str, covered: int, total: int) -> dict:
    return {"path": f"{ROOT}/{path}", "coveredLines": covered, "executableLines": total}


class CoverageTests(unittest.TestCase):

    def test_above_threshold_passes(self):
        done = run([file("Services/A.swift", 8, 10)], "--min", "70")

        self.assertEqual(done.returncode, 0)
        self.assertIn("80.0%", done.stdout)

    def test_below_threshold_fails(self):
        done = run([file("Services/A.swift", 6, 10)], "--min", "70")

        self.assertEqual(done.returncode, 1)
        self.assertIn("ниже порога", done.stdout)

    def test_views_are_left_out_of_the_threshold(self):
        done = run([file("Services/A.swift", 9, 10), file("Views/Big.swift", 0, 1000)], "--min", "80")

        self.assertEqual(done.returncode, 0, "Экраны проверяют UI-тесты, не этот прогон")
        self.assertIn("Views (не в пороге)", done.stdout)

    def test_excluded_folders_are_configurable(self):
        done = run([file("Services/A.swift", 0, 10), file("Models/B.swift", 10, 10)],
                   "--min", "90", "--exclude", "Services")

        self.assertEqual(done.returncode, 0)

    def test_folder_named_like_the_repository_is_not_confused(self):
        # Репозиторий и папка исходников называются одинаково — echos/echos.
        done = run([file("Models/B.swift", 1, 2)], "--min", "0")

        self.assertIn("| Models |", done.stdout)

    def test_missing_app_target_is_an_error_not_a_pass(self):
        report = {"targets": [{"name": "echosTests.xctest", "files": []}]}
        done = subprocess.run([sys.executable, str(COVERAGE), "--min", "0"], input=json.dumps(report),
                              capture_output=True, text=True)

        self.assertNotEqual(done.returncode, 0, "Нет покрытия — нет и зелёного")


if __name__ == "__main__":
    unittest.main()
