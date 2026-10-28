#!/usr/bin/env bash
#
# Подготовка выпуска: собрать CHANGELOG.md и сказать, что делать дальше.
#
#   scripts/release.sh            версия — по коммитам с прошлого тега
#   scripts/release.sh v1.2.0     версия явно
#
# Коммит и тег скрипт не делает — только печатает команды. Выпуск — момент,
# когда человек смотрит на журнал глазами, прежде чем его увидят другие.
# Дальше всё сделает .github/workflows/release.yml по тегу.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

version=${1:-$(python3 scripts/changelog.py next-version)}

if [[ ! $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "версия — в виде v1.2.3, а не «$version»" >&2
  exit 2
fi
if git rev-parse -q --verify "refs/tags/$version" > /dev/null; then
  echo "тег $version уже есть" >&2
  exit 1
fi
# Журнал собирается из истории, и всё, что не закоммичено, в него не попадёт.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "в рабочей копии незакоммиченное — сначала закоммитить или убрать" >&2
  exit 1
fi

python3 scripts/changelog.py file --release "$version" > CHANGELOG.md

echo "CHANGELOG.md собран для $version. Посмотреть и выпустить:"
echo
echo "  git diff CHANGELOG.md"
echo "  git add CHANGELOG.md"
echo "  git commit -m \"docs(changelog): $version\""
echo "  git tag -a $version -m $version"
echo "  git push origin HEAD $version"
