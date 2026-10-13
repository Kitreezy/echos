#!/usr/bin/env python3
"""Проверки решения этапа: на чём блокируем, на чём нет.

Запуск: python3 tests/gate_test.py

Юнит-тесты на Python, а не на Swift: проверяется скрипт CI, а не
приложение, и гонять ради него симулятор не нужно.
"""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

GATE = Path(__file__).resolve().parent.parent / "scripts" / "gate.py"


def decide(answer: str, tests: str = "success") -> tuple[int, str]:
    """Прогон скрипта как в CI: файл на входе, код возврата и текст наружу."""
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as handle:
        handle.write(answer)
        path = handle.name
    result = subprocess.run(
        [sys.executable, str(GATE), path, tests],
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout


def answer_with(findings: list[dict]) -> str:
    return "Посмотрел diff.\n\n```json\n" + json.dumps(
        {"findings": findings}, ensure_ascii=False) + "\n```\n"


BLOCKER = {
    "file": "echos/Persistence/PersistenceController.swift",
    "line": 62,
    "severity": "blocker",
    "rule": "7",
    "what": "атрибуты добавлены в единственную версию модели: установленная сборка не откроет хранилище",
}

ADVISORY = {
    "file": "echos/ViewModels/ChatViewModel.swift",
    "line": 545,
    "severity": "advisory",
    "rule": "5",
    "what": "ветка «сообщение не на экране» без теста",
}


class GateTests(unittest.TestCase):

    # MARK: - Решение

    def test_без_замечаний_пускает(self):
        code, out = decide(answer_with([]))

        self.assertEqual(code, 0)
        self.assertIn("Замечаний нет", out)

    def test_блокирующее_останавливает(self):
        code, out = decide(answer_with([BLOCKER]))

        self.assertEqual(code, 1)
        self.assertIn("Блокирует: 1", out)
        self.assertIn("PersistenceController.swift:62", out)

    def test_совещательное_не_останавливает(self):
        # Отсутствующий тест и расхождение комментария — по делу, но
        # вливание из-за них держать неправильно: такой этап отключат.
        code, out = decide(answer_with([ADVISORY, ADVISORY]))

        self.assertEqual(code, 0)
        self.assertIn("К прочтению: 2", out)

    def test_смешанное_останавливает_и_показывает_оба_списка(self):
        code, out = decide(answer_with([ADVISORY, BLOCKER]))

        self.assertEqual(code, 1)
        self.assertIn("Блокирует: 1", out)
        self.assertIn("К прочтению: 1", out)

    def test_незнакомая_серьёзность_не_блокирует(self):
        # Модель придумала свою градацию — это не повод останавливать работу.
        code, _ = decide(answer_with([{**BLOCKER, "severity": "critical"}]))

        self.assertEqual(code, 0)

    # MARK: - Сбои самой проверки

    def test_пустой_ответ_не_блокирует(self):
        code, out = decide("")

        self.assertEqual(code, 0)
        self.assertIn("не состоялась", out)

    def test_ответ_без_json_не_блокирует(self):
        # Модель ответила прозой вместо формата: виноват этап, не автор PR.
        code, out = decide("Выглядит хорошо, вливайте.")

        self.assertEqual(code, 0)
        self.assertIn("не состоялась", out)

    def test_сломанный_json_не_блокирует(self):
        code, out = decide("```json\n{\"findings\": [ {\"file\":\n```")

        self.assertEqual(code, 0)
        self.assertIn("не состоялась", out)

    def test_отсутствующий_файл_не_блокирует(self):
        result = subprocess.run(
            [sys.executable, str(GATE), "/nonexistent/answer.md", "success"],
            capture_output=True, text=True)

        self.assertEqual(result.returncode, 0)
        self.assertIn("не состоялась", result.stdout)

    # MARK: - Форма ответа модели

    def test_берётся_последний_блок_а_не_пример_формата(self):
        # Модель часто показывает пример формата перед настоящим ответом.
        answer = (
            "Отвечу так:\n\n```json\n"
            + json.dumps({"findings": [BLOCKER]}, ensure_ascii=False)
            + "\n```\n\nА вот результат:\n\n```json\n"
            + json.dumps({"findings": []}, ensure_ascii=False)
            + "\n```\n"
        )
        code, out = decide(answer)

        self.assertEqual(code, 0)
        self.assertIn("Замечаний нет", out)

    def test_список_без_обёртки_тоже_читается(self):
        code, out = decide("```json\n" + json.dumps([BLOCKER], ensure_ascii=False) + "\n```")

        self.assertEqual(code, 1)
        self.assertIn("Блокирует: 1", out)

    def test_замечание_без_строки_показывается_файлом(self):
        code, out = decide(answer_with([{k: v for k, v in BLOCKER.items() if k != "line"}]))

        self.assertEqual(code, 1)
        self.assertIn("PersistenceController.swift`", out)

    # MARK: - Падение тестов

    def test_красные_тесты_упоминаются_в_комментарии(self):
        code, out = decide(answer_with([]), tests="failure")

        self.assertEqual(code, 0, "сами тесты роняет свой job, а не этот")
        self.assertIn("failure", out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
