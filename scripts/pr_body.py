#!/usr/bin/env python3
"""Куда положить сгенерированное описание, не затерев написанного человеком.

    pr_body.py BODY_FILE DESCRIPTION_FILE   печатает решение и новый текст

Описание живёт между метками — HTML-комментариями, на странице PR их не
видно. Правило одно: текст человека не трогается.

- пусто → описание целиком, между метками;
- метки есть → заменяется только то, что между ними; написанное до и после
  остаётся — так описание обновляется на каждый новый коммит;
- текст без меток → его написал человек: тело не трогаем, описание идёт
  комментарием, как предложение.

Первая строка вывода — решение: `edit` или `comment`, дальше — текст.
"""

import sys
from pathlib import Path

START = "<!-- describe:start -->"
END = "<!-- describe:end -->"


def merge(body: str, description: str) -> tuple[str, str]:
    block = f"{START}\n{description.strip()}\n{END}"
    if not body.strip():
        return "edit", block
    if START in body and END in body and body.index(START) < body.index(END):
        before = body[:body.index(START)]
        after = body[body.index(END) + len(END):]
        return "edit", before + block + after
    return "comment", description.strip()


def main() -> int:
    body = Path(sys.argv[1]).read_text(encoding="utf-8") if Path(sys.argv[1]).exists() else ""
    description = Path(sys.argv[2]).read_text(encoding="utf-8")
    decision, text = merge(body, description)
    print(decision)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
