#!/usr/bin/env bash
#
# Запись трассы Instruments на сценарии ProfilingScenarioTests.
#
#   scripts/profile.sh                 Leaks
#   scripts/profile.sh "Time Profiler" главный поток и зависания
#   scripts/profile.sh Allocations     рост памяти по кругам
#
# Сценарий — UI-тест: он ходит по экранам туда и обратно, а xctrace
# подключается к запущенному им приложению. Руками то же самое не
# повторить одинаково дважды, а сравнивать трассы «до» и «после» можно
# только на одинаковом сценарии.
#
# Сборка — Debug: демо-переписка (DemoTransport) есть только в ней. Для
# утечек это неважно, а время в Debug завышено — сравнивать его можно
# только с такой же Debug-трассой.
#
# Трасса Leaks пишет историю всех выделений памяти и весит гигабайты —
# build/profile стоит чистить.
#
# Шаблон App Launch на симуляторе не работает: приложение остаётся
# остановленным, и запись не кончается. Время запуска меряет
# LaunchPerformanceTests.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
template=${1:-Leaks}
out=$root/build/profile
derived=$out/DerivedData
mkdir -p "$out"

simulator=${SIMULATOR:-$(xcrun simctl list devices booted -j \
  | python3 -c 'import json,sys
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if "iPhone" in d.get("deviceTypeIdentifier", ""):
            print(d["udid"]); raise SystemExit
')}
[ -n "$simulator" ] || { echo "нет запущенного симулятора iPhone — запусти его или задай SIMULATOR=<id>" >&2; exit 2; }

echo "── сборка"
LANG=en_US.UTF-8 xcodebuild build-for-testing -project "$root/echos.xcodeproj" -scheme echos \
  -testPlan Profiling -destination "id=$simulator" -derivedDataPath "$derived" -quiet

echo "── сценарий"
LANG=en_US.UTF-8 xcodebuild test-without-building -project "$root/echos.xcodeproj" -scheme echos \
  -testPlan Profiling -only-testing:echosUITests/ProfilingScenarioTests \
  -destination "id=$simulator" -derivedDataPath "$derived" \
  > "$out/scenario.log" 2>&1 &
scenario=$!
trap 'kill $scenario 2>/dev/null || true' EXIT

# Приложение, а не раннер тестов: у раннера свой процесс с другим именем.
pid=""
for _ in $(seq 1 120); do
  pid=$(pgrep -f '/echos\.app/echos .*-UITests' | head -1 || true)
  [ -n "$pid" ] && break
  kill -0 $scenario 2>/dev/null || { echo "сценарий завершился, не запустив приложение — $out/scenario.log" >&2; exit 1; }
  sleep 0.5
done
[ -n "$pid" ] || { echo "приложение не появилось за минуту — $out/scenario.log" >&2; exit 1; }

trace=$out/$(echo "$template" | tr ' ' '-')-$(date +%Y%m%d-%H%M%S).trace
echo "── запись: $template, pid $pid"
# Запись кончается вместе с приложением; предел — на случай, если нет.
# --device обязателен: без него xctrace ищет pid среди процессов Mac.
xcrun xctrace record --template "$template" --device "$simulator" --attach "$pid" --time-limit 300s \
  --output "$trace" > "$out/xctrace.log" 2>&1 || true

wait $scenario || echo "сценарий упал — $out/scenario.log" >&2
trap - EXIT

[ -d "$trace" ] || { echo "трасса не записалась — $out/xctrace.log" >&2; exit 1; }
echo "── готово: $trace"
echo "   открыть: open \"$trace\""
echo
python3 "$root/scripts/trace_report.py" "$trace" || true
