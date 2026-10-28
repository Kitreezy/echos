#!/usr/bin/env bash
#
# Ставит SwiftLint и SwiftFormat закреплённых версий в build/tools.
#
# Версии закреплены, а не берутся из brew: у brew на каждой машине своя, и
# новое правило в свежем релизе роняет CI на коде, который никто не трогал.
# Те же бинарники ставит и CI — «у меня проходит» значит «в CI пройдёт».
#
# Скачанный архив сверяется с sha256 из релиза на GitHub. Обновить версию —
# поменять версию и сумму здесь, одним коммитом, и прогнать scripts/lint.sh.

set -euo pipefail

SWIFTLINT_VERSION=0.65.1
SWIFTLINT_SHA256=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0

SWIFTFORMAT_VERSION=0.63.1
SWIFTFORMAT_SHA256=385ef1a263ba28685157b98c5536b9c9105e124518f28b7ef8a2bee4b167eaeb

root=$(cd "$(dirname "$0")/.." && pwd)
tools=$root/build/tools

install() {
  local name=$1 version=$2 sha=$3 url=$4
  local dir=$tools/$name-$version

  if [ -x "$dir/$name" ]; then
    return
  fi

  local tmp
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  echo "── $name $version"
  curl -fsSL -o "$tmp/$name.zip" "$url"
  echo "$sha  $tmp/$name.zip" | shasum -a 256 -c --quiet
  mkdir -p "$dir"
  unzip -qo "$tmp/$name.zip" -d "$dir"
  chmod +x "$dir/$name"
}

install swiftlint "$SWIFTLINT_VERSION" "$SWIFTLINT_SHA256" \
  "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/portable_swiftlint.zip"

install swiftformat "$SWIFTFORMAT_VERSION" "$SWIFTFORMAT_SHA256" \
  "https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/swiftformat.zip"

# Пути — для того, кто вызвал: lint.sh берёт инструменты отсюда.
echo "SWIFTLINT=$tools/swiftlint-$SWIFTLINT_VERSION/swiftlint"
echo "SWIFTFORMAT=$tools/swiftformat-$SWIFTFORMAT_VERSION/swiftformat"
