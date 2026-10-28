#!/usr/bin/env python3
"""Журнал из истории: разделы, ссылки на PR, версии и проверка формата.

Каждый тест строит свой репозиторий во временной папке — с настоящими
коммитами, слияниями и тегами, — потому что разбирает скрипт именно git.

Запуск: python3 tests/changelog_test.py
"""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

CHANGELOG = Path(__file__).resolve().parent.parent / "scripts" / "changelog.py"

# Своё имя автора и никакого глобального конфига: тест не должен зависеть
# от машины и не должен её трогать.
ENV = {**os.environ,
       "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
       "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com",
       "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}


class Repo:

    def __init__(self, path: Path):
        self.path = path
        self.git("init", "-q", "-b", "main")
        self.git("remote", "add", "origin", "https://github.com/acme/app.git")

    def git(self, *args: str) -> str:
        return subprocess.run(["git", *args], cwd=self.path, env=ENV, check=True,
                              capture_output=True, text=True).stdout

    def commit(self, message: str) -> str:
        self.git("commit", "-q", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD").strip()

    def merge_pull(self, number: int, branch: str, *messages: str) -> None:
        self.git("checkout", "-q", "-b", branch)
        for message in messages:
            self.commit(message)
        self.git("checkout", "-q", "main")
        self.git("merge", "-q", "--no-ff", branch, "-m", f"Merge pull request #{number} from acme/{branch}")

    def run(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(CHANGELOG), *args], cwd=self.path, env=ENV,
                              capture_output=True, text=True)


class ChangelogTests(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Repo(Path(self.tmp.name))
        self.repo.commit("chore: Начало")

    def tearDown(self):
        self.tmp.cleanup()

    # MARK: - Разделы

    def test_user_facing_changes_are_grouped(self):
        self.repo.commit("feat(chat): Реакции")
        self.repo.commit("fix(chat): Время по-русски")
        self.repo.commit("ci(cache): Кэш пакетов")

        notes = self.repo.run("notes").stdout

        self.assertIn("### Новое\n\n- **chat:** Реакции", notes)
        self.assertIn("### Исправлено\n\n- **chat:** Время по-русски", notes)
        self.assertLess(notes.index("### Новое"), notes.index("### Исправлено"))

    def test_internal_changes_are_folded_in_notes_and_absent_from_the_file(self):
        self.repo.commit("feat: Видимое")
        self.repo.commit("ci(cache): Кэш пакетов")

        notes = self.repo.run("notes").stdout
        changelog = self.repo.run("file").stdout

        self.assertIn("<details><summary>Внутреннее — 2</summary>", notes)
        self.assertIn("`ci` **cache:** Кэш пакетов", notes)
        self.assertNotIn("Кэш пакетов", changelog, "Журнал — для тех, кто приложением пользуется")

    def test_breaking_change_comes_first_with_its_own_text(self):
        self.repo.commit("feat(sync): Новый протокол\n\nBREAKING CHANGE: старые клиенты не увидят сообщений")
        self.repo.commit("feat(api)!: Адрес вместо имени")

        notes = self.repo.run("notes").stdout

        self.assertTrue(notes.startswith("### Несовместимые изменения"))
        self.assertIn("**sync:** старые клиенты не увидят сообщений", notes)
        self.assertIn("**api:** Адрес вместо имени", notes)

    def test_nothing_visible_says_so(self):
        self.repo.commit("ci: Только CI")

        self.assertIn("Без изменений, заметных снаружи.", self.repo.run("notes", "--from", "HEAD~1").stdout)

    # MARK: - Ссылки

    def test_commit_from_pull_request_links_the_pull_request(self):
        self.repo.merge_pull(7, "feature", "feat(wall): Стена")

        self.assertIn("**wall:** Стена ([#7](https://github.com/acme/app/pull/7))", self.repo.run("notes").stdout)

    def test_squashed_pull_request_number_moves_out_of_the_text(self):
        self.repo.commit("fix(chat): Прокрутка (#12)")

        self.assertIn("**chat:** Прокрутка ([#12](https://github.com/acme/app/pull/12))",
                      self.repo.run("notes").stdout)

    def test_direct_commit_links_the_commit(self):
        sha = self.repo.commit("feat: Напрямую")

        self.assertIn(f"([{sha[:7]}](https://github.com/acme/app/commit/{sha}))", self.repo.run("notes").stdout)

    def test_base_merged_into_branch_is_not_claimed_by_the_pull_request(self):
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.commit("feat: Своё")
        self.repo.git("checkout", "-q", "main")
        direct = self.repo.commit("feat: Чужое, прямо в main")
        self.repo.git("checkout", "-q", "feature")
        self.repo.git("merge", "-q", "--no-ff", "main", "-m", "Merge branch 'main' into feature")
        self.repo.git("checkout", "-q", "main")
        self.repo.git("merge", "-q", "--no-ff", "feature", "-m", "Merge pull request #9 from acme/feature")

        notes = self.repo.run("notes").stdout

        self.assertIn("Своё ([#9]", notes)
        self.assertIn(f"Чужое, прямо в main ([{direct[:7]}]", notes)

    def test_release_merge_does_not_swallow_its_commits(self):
        self.repo.git("checkout", "-q", "-b", "develop")
        sha = self.repo.commit("feat: Прямо в develop")
        self.repo.git("checkout", "-q", "main")
        self.repo.git("merge", "-q", "--no-ff", "develop", "-m", "Merge pull request #20 from acme/develop")

        self.assertIn(f"Прямо в develop ([{sha[:7]}]", self.repo.run("notes").stdout)

    # MARK: - Версии

    def test_notes_cover_only_the_range_since_the_previous_tag(self):
        self.repo.commit("feat: Старое")
        self.repo.git("tag", "v0.1.0")
        self.repo.commit("feat: Новое")
        self.repo.git("tag", "v0.2.0")

        notes = self.repo.run("notes").stdout

        self.assertIn("Новое", notes)
        self.assertNotIn("Старое", notes)

    def test_file_has_unreleased_and_every_version(self):
        self.repo.commit("feat: Первое")
        self.repo.git("tag", "v0.1.0")
        self.repo.commit("fix: Второе")
        self.repo.git("tag", "v0.1.1")
        self.repo.commit("feat: Третье")

        changelog = self.repo.run("file").stdout

        unreleased, v011, v010 = (changelog.index(h) for h in ("## Не выпущено", "## [0.1.1]", "## [0.1.0]"))
        self.assertLess(unreleased, v011)
        self.assertLess(v011, v010)
        self.assertLess(changelog.index("Третье"), v011)
        self.assertLess(v011, changelog.index("Второе"))
        self.assertLess(v010, changelog.index("Первое"))

    def test_release_turns_unreleased_into_a_version(self):
        self.repo.commit("feat: Готово")

        changelog = self.repo.run("file", "--release", "v1.4.0").stdout

        self.assertIn("## [1.4.0] — ", changelog)
        self.assertNotIn("Не выпущено", changelog)

    def test_next_version_follows_the_most_significant_change(self):
        self.repo.git("tag", "v1.2.3")
        cases = [("fix: Мелочь", "v1.2.4"), ("feat: Возможность", "v1.3.0"), ("feat!: Несовместимо", "v2.0.0")]
        for message, expected in cases:
            with self.subTest(message):
                self.repo.commit(message)
                self.assertEqual(self.repo.run("next-version").stdout.strip(), expected)

    def test_breaking_change_before_one_point_oh_bumps_minor(self):
        self.repo.git("tag", "v0.4.1")
        self.repo.commit("feat!: Несовместимо")

        self.assertEqual(self.repo.run("next-version").stdout.strip(), "v0.5.0")

    # MARK: - Формат

    def test_check_names_every_bad_commit(self):
        base = self.repo.git("rev-parse", "HEAD").strip()
        self.repo.commit("feat(chat): Хорошо")
        self.repo.commit("Update README.md")
        self.repo.commit("feat(): Пустая область")
        self.repo.commit("feature: Не тот тип")

        done = self.repo.run("check", f"{base}..HEAD")

        self.assertEqual(done.returncode, 1)
        self.assertIn("Update README.md", done.stdout)
        self.assertIn("Пустая область", done.stdout)
        self.assertIn("неизвестный тип «feature»", done.stdout)
        self.assertNotIn("Хорошо", done.stdout)

    def test_check_ignores_merges(self):
        base = self.repo.git("rev-parse", "HEAD").strip()
        self.repo.merge_pull(3, "feature", "fix: Норма")

        self.assertEqual(self.repo.run("check", f"{base}..HEAD").returncode, 0)

    def test_check_message_reads_the_subject_and_skips_comments(self):
        message = Path(self.tmp.name) / "MSG"
        message.write_text("# комментарий git\n\nfix(chat): Норма\n\nТело\n", encoding="utf-8")
        self.assertEqual(self.repo.run("check-message", str(message)).returncode, 0)

        message.write_text("починил\n", encoding="utf-8")
        self.assertEqual(self.repo.run("check-message", str(message)).returncode, 1)


if __name__ == "__main__":
    unittest.main()
