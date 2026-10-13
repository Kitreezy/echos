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
gate=false
if [ "${1:-}" = "--gate" ]; then
  gate=true
  shift
fi

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

# Машинный блок просится только с --gate: человеку он не нужен, а модель,
# которой велели выдать JSON, пишет прозу короче. Текст — отдельным файлом:
# в нём тройные обратные кавычки, и в шелле они живут плохо.
machine=""
if $gate; then
  machine=$(cat "$root/scripts/gate-prompt.txt")
fi

cd "$workdir"

# Код возврата самого claude отделяется от вердикта. Иначе сбой вызова —
# нет сети, кончились лимиты, модель не ответила — приходит кодом 1 и
# превращается в «блокирующее замечание», то есть этап начинает
# останавливать работу из-за собственной поломки.
set +e
answer=$(claude -p \
  --allowedTools "Read,Grep,Glob" \
  --output-format text \
  "Проект echos, iOS, Swift 6. Сделай ревью diff по чек-листу ниже.

Правила ответа. Пройди по пунктам чек-листа по порядку, по каждому — либо
«чисто», либо замечания: файл, строка, что не так и почему это подпадает
под пункт. Замечание без файла и строки не пиши. Если сомневаешься —
загляни в код рядом через Read, не гадай по diff. Не пересказывай diff, не
хвали, не предлагай стиль и именование — их в чек-листе нет. В конце одна
фраза: стоит ли вливать как есть.
$machine
Чек-лист:

$checklist

Diff:

$diff")
called=$?
set -e

if [ $called -ne 0 ]; then
  echo "ревью не состоялось: claude вернул $called" >&2
  if ! $gate; then
    exit 2
  fi
  # С --gate молчать нельзя: вызывающему нужен комментарий о том, что
  # проверка не прошла, и нулевой код — чтобы не блокировать.
  mkdir -p "$root/build"
  printf 'вызов claude вернул %s\n' "$called" > "$root/build/review.md"
  python3 "$root/scripts/gate.py" /nonexistent "${TESTS_RESULT:-}"
  exit 0
fi

if ! $gate; then
  printf '%s\n' "$answer"
  exit 0
fi

# Ответ сохраняется: при разборе вердикта нужно видеть, что именно сказала
# модель, а не только решение.
mkdir -p "$root/build"
printf '%s\n' "$answer" > "$root/build/review.md"

python3 "$root/scripts/gate.py" "$root/build/review.md" "${TESTS_RESULT:-}"
