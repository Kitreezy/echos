#!/usr/bin/env bash
#
# Замер холодного запуска числом через XCTApplicationLaunchMetric.
#
#   scripts/launch_time.sh
#   SIMULATOR=<udid> scripts/launch_time.sh
#
# Тест делает пять запусков, первый прогревает кэш и в статистику не идёт.
# В журнале XCTest смотрят среднее и разброс LaunchPerformanceTests/test_launch.
#
# Это не заменяет Instruments: signpost-интервалы LaunchTrace смотрятся
# отдельно в Points of Interest, а полный pre-main — в шаблоне App Launch на
# устройстве или через DYLD_PRINT_STATISTICS.
#
# Сравнивать имеет смысл только одинаковые устройство, схему и сборку:
# Release на устройстве сильно быстрее Debug-симулятора.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out=$root/build/launch
derived=$out/DerivedData
mkdir -p "$out"

simulator=${SIMULATOR:-$(xcrun simctl list devices booted -j \
  | python3 -c 'import json,sys
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if "iPhone" in d.get("deviceTypeIdentifier", ""):
            print(d["udid"]); raise SystemExit
')}
[ -n "$simulator" ] || {
  echo "нет запущенного симулятора iPhone — запусти его или задай SIMULATOR=<id>" >&2
  exit 2
}

echo "── сборка"
LANG=en_US.UTF-8 xcodebuild build-for-testing -project "$root/echos.xcodeproj" -scheme echos \
  -testPlan Profiling -destination "id=$simulator" -derivedDataPath "$derived" -quiet

echo "── пять запусков приложения"
LANG=en_US.UTF-8 xcodebuild test-without-building -project "$root/echos.xcodeproj" -scheme echos \
  -testPlan Profiling -only-testing:echosUITests/LaunchPerformanceTests/test_launch \
  -destination "id=$simulator" -derivedDataPath "$derived" \
  > "$out/launch.log" 2>&1 || {
    tail -n 80 "$out/launch.log" >&2
    echo "замер запуска упал — полный журнал: $out/launch.log" >&2
    exit 1
  }

echo "── готово: $out/launch.log"
grep -E "Test Case|passed|failed" "$out/launch.log" | tail -n 20 || true
