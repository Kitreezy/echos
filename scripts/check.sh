#!/usr/bin/env bash
#
# Сборка → тесты → разбор. Запускать перед PR или из pre-push.
#
#   scripts/check.sh            собрать, прогнать тесты; упало — объяснить
#   scripts/check.sh --fix      то же, но модели разрешено править код,
#                               и после правки тесты идут снова — до трёх
#                               кругов
#   scripts/check.sh --rounds 5 сколько кругов с --fix
#
# Сборка и тесты — детерминированные, их делает xcodebuild. Модель
# подключается только к тому, что требует чтения: к упавшим тестам. Зелёный
# прогон до неё не доходит вовсе. Три круга, а не бесконечность: если за три
# попытки не починилось, чинить надо человеку, и скрипт обязан это сказать,
# а не крутиться.
#
# Нужен Claude Code в PATH (`claude`) и вход в аккаунт.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out=$root/build/check
fix=false
rounds=3

while [ $# -gt 0 ]; do
  case $1 in
    --fix) fix=true ;;
    --rounds) rounds=$2; shift ;;
    *) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
  esac
  shift
done

# --- Симулятор -------------------------------------------------------------
# Первый доступный iPhone — по типу устройства, не по имени: симулятор
# может называться как угодно. Переопределяется SIMULATOR=<id>.

simulator=${SIMULATOR:-$(xcrun simctl list devices available -j \
  | python3 -c 'import json,sys
for runtime, devs in json.load(sys.stdin)["devices"].items():
    if "iOS" not in runtime:
        continue
    for d in devs:
        if d["isAvailable"] and "iPhone" in d.get("deviceTypeIdentifier", ""):
            print(d["udid"]); raise SystemExit
' )}
[ -n "$simulator" ] || { echo "нет доступного симулятора iPhone" >&2; exit 2; }

# --- Прогон ----------------------------------------------------------------
# Возвращает 0, если всё зелёное; иначе пишет падения в $failures.

run_tests() {
  local bundle=$1 log=$2
  rm -rf "$bundle"
  set +e
  LANG=en_US.UTF-8 xcodebuild test \
    -project "$root/echos.xcodeproj" -scheme echos \
    -destination "platform=iOS Simulator,id=$simulator" \
    -resultBundlePath "$bundle" \
    -quiet > "$log" 2>&1
  local status=$?
  set -e
  return $status
}

# Падения в виде, который можно прочитать: имя теста, сообщение, файл и
# строка. Из .xcresult, а не из лога — лог на десятки тысяч строк.
failures_of() {
  local bundle=$1 log=$2 since=$3
  if [ -d "$bundle" ]; then
    xcrun xcresulttool get test-results tests --path "$bundle" 2>/dev/null \
      | python3 "$root/scripts/failures.py"
  fi
  # Ошибки компиляции до тестов не доходят — они в логе.
  grep -E "^.*error: " "$log" | grep -v "CHHaptic" | sort -u | head -40 || true
  # Если упал сам хост, в .xcresult ничего нет, а всё — в крэш-репортах.
  # Пути отдаются как есть: модель прочитает их сама.
  local reports
  reports=$(find ~/Library/Logs/DiagnosticReports -name 'echos-*.ips' -newer "$since" 2>/dev/null | head -5)
  if [ -n "$reports" ]; then
    echo "Крэш-репорты этого прогона:"
    echo "$reports" | sed 's/^/    /'
  fi
}

# --- Разбор ----------------------------------------------------------------

explain() {
  local failures=$1 allow_edit=$2
  local tools="Read,Grep,Glob"
  local mode="default"
  if $allow_edit; then
    tools="Read,Grep,Glob,Edit,MultiEdit"
    mode="acceptEdits"
  fi

  local task
  if $allow_edit; then
    task="Найди причину и исправь минимальной правкой в коде под тестом или в тесте — смотря что на самом деле неверно. Не ослабляй тест, чтобы он прошёл. После правки коротко скажи, что и почему изменил."
  else
    task="Найди причину и предложи правку. Код не меняй — только объясни, что сломано, в каком файле и что стоит сделать. Коротко, прозой, без списков там, где хватит абзаца."
  fi

  claude -p \
    --allowedTools "$tools" \
    --permission-mode "$mode" \
    --output-format text \
    "Проект echos, iOS, Swift 6. Упали тесты или сборка. Вот что упало:

$failures

$task"
}

# --- Цикл ------------------------------------------------------------------

mkdir -p "$out"
round=1
while :; do
  bundle=$out/round-$round.xcresult
  log=$out/round-$round.log
  started=$out/round-$round.started
  touch "$started"
  echo "── круг $round: сборка и тесты"

  if run_tests "$bundle" "$log"; then
    echo "── зелёно"
    exit 0
  fi

  failures=$(failures_of "$bundle" "$log" "$started")
  if [ -z "$failures" ]; then
    echo "── xcodebuild вернул ошибку, но падений не видно — смотри $log" >&2
    exit 1
  fi

  echo "── упало:"
  echo "$failures" | sed 's/^/   /'
  echo

  if ! $fix; then
    echo "── разбор:"
    explain "$failures" false
    exit 1
  fi

  if [ "$round" -ge "$rounds" ]; then
    echo "── $rounds круга, всё ещё красное. Дальше — руками." >&2
    exit 1
  fi

  echo "── правка:"
  explain "$failures" true
  echo
  round=$((round + 1))
done
