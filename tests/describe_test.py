#!/usr/bin/env python3
"""Проверки описания PR: что пишется в тело, а что идёт комментарием, и
что подпись генератора в описание не попадает.

Запуск: python3 tests/describe_test.py
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import describe  # noqa: E402
from pr_body import END, START, merge  # noqa: E402


class MergeTests(unittest.TestCase):

    def test_empty_body_gets_the_description(self):
        decision, body = merge("", "Реакции на сообщения.")

        self.assertEqual(decision, "edit")
        self.assertEqual(body, f"{START}\nРеакции на сообщения.\n{END}")

    def test_new_commit_replaces_only_the_block(self):
        old = f"Человек написал сверху.\n\n{START}\nСтарое описание.\n{END}\n\nИ снизу."

        decision, body = merge(old, "Новое описание.")

        self.assertEqual(decision, "edit")
        self.assertIn("Человек написал сверху.", body)
        self.assertIn("И снизу.", body)
        self.assertIn("Новое описание.", body)
        self.assertNotIn("Старое описание.", body)

    def test_human_text_is_never_overwritten(self):
        decision, text = merge("Написал сам, без меток.", "Сгенерированное.")

        self.assertEqual(decision, "comment", "Чужой текст не трогаем — предлагаем рядом")
        self.assertEqual(text, "Сгенерированное.")

    def test_broken_markers_count_as_human_text(self):
        decision, _ = merge(f"{END}\nчто-то\n{START}", "Новое.")

        self.assertEqual(decision, "comment")


class DiffTests(unittest.TestCase):

    def test_machine_files_are_dropped_and_named(self):
        diff = ("diff --git a/echos.xcodeproj/project.pbxproj b/echos.xcodeproj/project.pbxproj\n+шум\n"
                "diff --git a/echos/Chat.swift b/echos/Chat.swift\n+код\n")

        kept, dropped = describe.trim(diff)

        self.assertNotIn("шум", kept)
        self.assertIn("+код", kept)
        self.assertEqual(dropped, ["echos.xcodeproj/project.pbxproj (машинный файл)"])

    def test_huge_file_is_cut_with_a_note(self):
        diff = "diff --git a/big.swift b/big.swift\n" + "+x\n" * 20_000

        kept, _ = describe.trim(diff)

        self.assertLessEqual(len(kept), describe.FILE_LIMIT + 200)
        self.assertIn("файл обрезан", kept, "Модель должна знать, что видит не всё")

    def test_signature_is_removed(self):
        text = "Описание.\n\n🤖 Generated with something\nCo-Authored-By: someone"

        self.assertEqual(describe.clean(text), "Описание.")


if __name__ == "__main__":
    unittest.main()
