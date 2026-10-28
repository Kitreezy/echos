#!/usr/bin/env bash
#
# Форматирование и линтер — те же, что в CI.
#
#   scripts/lint.sh         проверить; есть замечания — код возврата 1
#   scripts/lint.sh --fix   поправить то, что правится само, и проверить
#
# SwiftFormat отвечает за вид кода: пробелы, пустые строки. SwiftLint — за
# содержание: имена, размеры, опасные конструкции. Правила форматирования в
# SwiftLint выключены, иначе два инструмента спорят об одних и тех же
# пробелах. Конфиги — .swiftformat и .swiftlint.yml в корне.
#
# Инструменты ставит scripts/install-tools.sh закреплённых версий. Свои
# можно подсунуть через SWIFTLINT=… и SWIFTFORMAT=…, но тогда расхождение
# с CI — ваше.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

fix=false
case ${1:-} in
  --fix) fix=true ;;
  "") ;;
  *) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
esac

if [ -z "${SWIFTLINT:-}" ] || [ -z "${SWIFTFORMAT:-}" ]; then
  eval "$("$root/scripts/install-tools.sh" | grep -E '^SWIFT(LINT|FORMAT)=')"
fi

# В CI замечания идут аннотациями прямо в diff pull request'а.
#
# Пустой массив под set -u в bash 3.2, который стоит на маке, — «unbound
# variable». Отсюда конструкция ${a[@]+"${a[@]}"} ниже.
format_reporter=()
lint_reporter=()
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  format_reporter=(--reporter github-actions-log)
  lint_reporter=(--reporter github-actions-logging)
fi

status=0

if $fix; then
  "$SWIFTFORMAT" . --quiet
  "$SWIFTLINT" --fix --quiet
fi

echo "── SwiftFormat $("$SWIFTFORMAT" --version)"
"$SWIFTFORMAT" . --lint ${format_reporter[@]+"${format_reporter[@]}"} || status=1

echo "── SwiftLint $("$SWIFTLINT" version)"
# --strict: предупреждение — тоже провал. Иначе предупреждения копятся,
# их перестают читать, и через месяц их сотни.
"$SWIFTLINT" lint --strict --quiet ${lint_reporter[@]+"${lint_reporter[@]}"} || status=1

if [ $status -ne 0 ] && ! $fix; then
  echo "── есть замечания. Пробелы и пустые строки поправит scripts/lint.sh --fix" >&2
fi
exit $status
