#!/usr/bin/env python3
"""Решение этапа CI по ответу модели.

На вход — файл с ответом ревью, в котором где-то лежит блок ```json с
замечаниями. На выход — markdown-комментарий для PR в stdout и код
возврата: 0 — пускаем, 1 — блокируем.

Почему разбор отдельным файлом, а не строчкой в workflow: решение «пускать
или нет» — это логика, и её надо читать и чинить, не трогая YAML. Заодно
проверяемо: tests/gate_test.py гоняет её на готовых ответах.

Главное правило — любая неясность трактуется в пользу «пускаем».
Непрочитанный ответ, пустой файл, сломанный JSON, незнакомая серьёзность:
этап обязан сказать, что не состоялся, и не останавливать работу. Этап,
который падает на своих же сбоях, отключают через неделю, и тогда не
работает ничего.
"""

import json
import re
import sys

# Серьёзности, на которых останавливаем. Остальное — к прочтению.
BLOCKING = {"blocker"}

VERDICT_PASS = 0
VERDICT_BLOCK = 1


def findings_of(answer: str) -> tuple[list[dict], str | None]:
    """Замечания из ответа модели и причина, если прочитать не удалось."""
    blocks = re.findall(r"```(?:json)?\s*\n(.*?)```", answer, re.S)
    if not blocks:
        return [], "в ответе нет блока json"

    # Берётся последний блок: модель иногда показывает пример формата перед
    # настоящим ответом, и выигрывать должен ответ, а не пример.
    for block in reversed(blocks):
        try:
            parsed = json.loads(block)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            parsed = parsed.get("findings", [])
        if isinstance(parsed, list):
            return [item for item in parsed if isinstance(item, dict)], None

    return [], "блок json не разобрался"


def comment(findings: list[dict], failure: str | None, tests: str) -> str:
    lines = ["## Проверка кода", ""]

    if failure:
        lines += [
            f"Проверка не состоялась: {failure}. Этап не блокирует — "
            "разбирать нужно сам этап, а не этот pull request.",
            "",
        ]
        return "\n".join(lines)

    if tests not in ("success", ""):
        lines += [f"Тесты: **{tests}**. Разбор падения ниже.", ""]

    blocking = [f for f in findings if f.get("severity") in BLOCKING]
    advisory = [f for f in findings if f.get("severity") not in BLOCKING]

    if not findings:
        lines += ["Замечаний нет."]
        return "\n".join(lines)

    if blocking:
        lines += [f"**Блокирует: {len(blocking)}.** Это ломается у человека, "
                  "а не вопрос вкуса.", ""]
        lines += [_item(f) for f in blocking]
        lines.append("")

    if advisory:
        lines += [f"К прочтению: {len(advisory)}. Вливание не задерживают.", ""]
        lines += [_item(f) for f in advisory]

    return "\n".join(lines)


def _item(finding: dict) -> str:
    where = finding.get("file", "?")
    line = finding.get("line")
    if line:
        where = f"{where}:{line}"
    rule = finding.get("rule")
    tail = f" _(пункт {rule})_" if rule else ""
    return f"- `{where}` — {finding.get('what', 'без описания')}{tail}"


def main() -> int:
    if len(sys.argv) < 2:
        print("использование: gate.py <файл с ответом> [результат тестов]", file=sys.stderr)
        return VERDICT_PASS

    tests = sys.argv[2] if len(sys.argv) > 2 else ""

    try:
        with open(sys.argv[1], encoding="utf-8") as handle:
            answer = handle.read()
    except OSError as error:
        print(comment([], f"ответ не прочитался ({error.strerror})", tests))
        return VERDICT_PASS

    if not answer.strip():
        print(comment([], "ответ пустой", tests))
        return VERDICT_PASS

    findings, failure = findings_of(answer)
    print(comment(findings, failure, tests))

    if failure:
        return VERDICT_PASS

    blocking = [f for f in findings if f.get("severity") in BLOCKING]
    return VERDICT_BLOCK if blocking else VERDICT_PASS


if __name__ == "__main__":
    sys.exit(main())
