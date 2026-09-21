#!/usr/bin/env bash
#
# Ревью по чек-листу — до PR, за минуту, без CI.
#
#   scripts/review.sh              diff рабочей копии и ветки к origin/develop
#   scripts/review.sh main         к другой базе
#   scripts/review.sh A..B         произвольный диапазон — так прогоняются
#                                  старые PR для калибровки чек-листа
#
# Чек-лист — docs/review-checklist.md, тот же, что читает job review в CI.
# Ответ строго по пунктам: номер, «чисто» или замечание с файлом и строкой.
# Модель код не меняет — только читает.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
range=${1:-origin/develop}
workdir=$root

case $range in
  *..*)
    diff=$(git -C "$root" diff "$range")
    # Модель заглядывает в код через Read, и он обязан быть той версии,
    # чей diff она смотрит, — иначе она найдёт в текущей ветке то, чего в
    # той не было, и наоборот. Для диапазона — временная копия на его
    # верхнем коммите.
    tip=${range##*..}
    workdir=$(mktemp -d "${TMPDIR:-/tmp}/echos-review.XXXXXX")
    git -C "$root" worktree add -q --detach "$workdir" "$tip"
    trap 'git -C "$root" worktree remove --force "$workdir" >/dev/null 2>&1' EXIT
    ;;
  *)
    diff=$(git -C "$root" diff "$range"...HEAD; git -C "$root" diff)
    ;;
esac

if [ -z "$diff" ]; then
  echo "diff пуст — смотреть нечего"
  exit 0
fi

# Слишком большой diff модель прочитает хуже, чем никакой: режем и говорим.
limit=200000
if [ ${#diff} -gt $limit ]; then
  echo "── diff ${#diff} байт, обрезан до $limit; ревью неполное" >&2
  diff=${diff:0:$limit}
fi

checklist=$(cat "$root/docs/review-checklist.md")

cd "$workdir"
claude -p \
  --allowedTools "Read,Grep,Glob" \
  --output-format text \
  "Проект echos, iOS, Swift 6. Сделай ревью diff по чек-листу ниже.

Правила ответа. Пройди по пунктам чек-листа по порядку, по каждому — либо
«чисто», либо замечания: файл, строка, что не так и почему это подпадает
под пункт. Замечание без файла и строки не пиши. Если сомневаешься —
загляни в код рядом через Read, не гадай по diff. Не пересказывай diff, не
хвали, не предлагай стиль и именование — их в чек-листе нет. В конце одна
фраза: стоит ли вливать как есть.

Чек-лист:

$checklist

Diff:

$diff"
