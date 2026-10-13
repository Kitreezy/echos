#!/usr/bin/env bash
#
# Подписывает неподписанный echos.app из архива вручную — теми же шагами,
# которые Xcode делает молча, когда стоит галочка Automatic.
#
#   scripts/sign.sh [путь/к/echos.xcarchive]
#
# По умолчанию берёт build/echos.xcarchive — то, что оставляет
# `fastlane package`. Профиль и сертификат ищет сам по bundle id
# приложения; переопределить можно через PROFILE=<путь.mobileprovision>.
# Результат — build/echos-<версия>-signed.ipa.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
archive=${1:-$root/build/echos.xcarchive}
work=$root/build/signing

app_src=$(find "$archive/Products/Applications" -maxdepth 1 -name '*.app' | head -1)
[ -n "$app_src" ] || { echo "в $archive нет .app — сначала fastlane package" >&2; exit 1; }

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }

bundle_id=$(plist "$app_src/Info.plist" CFBundleIdentifier)
version=$(plist "$app_src/Info.plist" CFBundleShortVersionString)
echo "Приложение: $bundle_id $version"

# --- 1. Профиль -----------------------------------------------------------
# Профиль — это plist, завёрнутый в CMS-подпись Apple. Внутри: для какого
# app id он выписан, какая команда, список устройств, срок и entitlements,
# которые разрешено просить. Xcode 16+ складывает их в UserData, старые
# версии — в MobileDevice; смотрим оба места.

decode() { security cms -D -i "$1" 2>/dev/null; }

if [ -z "${PROFILE:-}" ]; then
  best_exp=""
  for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
           ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision; do
    [ -f "$f" ] || continue
    decoded=$(decode "$f") || continue
    app_id=$(echo "$decoded" | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null) || continue
    [ "${app_id#*.}" = "$bundle_id" ] || continue
    exp=$(echo "$decoded" | plutil -extract ExpirationDate raw -o - -)
    if [[ "$exp" > "$best_exp" ]]; then best_exp=$exp; PROFILE=$f; fi
  done
fi
[ -n "${PROFILE:-}" ] || { echo "профиля для $bundle_id нет — запусти приложение на телефоне из Xcode, он создаст" >&2; exit 1; }

mkdir -p "$work"
decode "$PROFILE" > "$work/profile.plist"

echo "Профиль:    $(plist "$work/profile.plist" Name)"
echo "Команда:    $(plist "$work/profile.plist" TeamIdentifier:0)"
echo "Годен до:   $(plist "$work/profile.plist" ExpirationDate)"
echo "Устройств:  $(plist "$work/profile.plist" ProvisionedDevices | grep -c '^\s')"

if [[ "$(plist "$work/profile.plist" ExpirationDate)" < "$(date -u +%Y-%m-%dT%H:%M:%SZ)" ]]; then
  echo "профиль просрочен — на бесплатном аккаунте он живёт 7 дней и обновляется только запуском из Xcode" >&2
  exit 1
fi

# --- 2. Entitlements ------------------------------------------------------
# Приложение подписывается не «просто так», а с конкретным набором прав.
# Их источник — профиль: iOS сверит подпись бинаря с тем, что разрешено
# в профиле, и при расхождении откажет в установке.

plutil -extract Entitlements xml1 -o "$work/entitlements.plist" "$work/profile.plist"
echo "Entitlements:"
sed -n '/<dict>/,/<\/dict>/p' "$work/entitlements.plist" | grep -E '<key>|<string>|<true/>|<false/>' | sed 's/^[[:space:]]*/    /'

# --- 3. Сертификат --------------------------------------------------------
# Профиль сам говорит, каким сертификатом можно подписывать: он лежит
# внутри в DER. Считаем его отпечаток и найдём в keychain — подписывать
# будем по отпечатку, а не по имени: имя может совпасть у двух сертификатов.

plist "$work/profile.plist" DeveloperCertificates:0 > "$work/cert.der" 2>/dev/null \
  || plutil -extract DeveloperCertificates.0 raw -o - "$work/profile.plist" | base64 -d > "$work/cert.der"
fingerprint=$(openssl x509 -inform DER -in "$work/cert.der" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')
subject=$(openssl x509 -inform DER -in "$work/cert.der" -noout -subject | sed 's/.*CN=\([^,]*\).*/\1/')

if ! security find-identity -v -p codesigning | grep -q "$fingerprint"; then
  echo "сертификата «$subject» нет в keychain, а приватного ключа без него не бывает" >&2
  exit 1
fi
echo "Сертификат: $subject"
echo "Отпечаток:  $fingerprint"

# --- 4. Подпись -----------------------------------------------------------
# Копия .app, внутрь кладётся профиль под именем embedded.mobileprovision —
# именно оттуда iOS при установке узнаёт, кому и на какие устройства это
# можно. Подпись идёт изнутри наружу: сначала вложенные фреймворки и
# расширения, потом само приложение, иначе внешняя подпись не сойдётся с
# содержимым.

app=$work/$(basename "$app_src")
rm -rf "$app"
cp -R "$app_src" "$app"
cp "$PROFILE" "$app/embedded.mobileprovision"

sign() { codesign --force --sign "$fingerprint" --timestamp=none "$@"; }

find "$app" -depth \( -name '*.framework' -o -name '*.dylib' -o -name '*.appex' \) -print0 \
  | while IFS= read -r -d '' nested; do
      echo "  подпись: ${nested#$app/}"
      sign "$nested"
    done

echo "  подпись: $(basename "$app")"
sign --entitlements "$work/entitlements.plist" "$app"

# --- 5. Проверка ----------------------------------------------------------
# --strict проверяет то, что проверит и устройство. Отдельно смотрим,
# какие entitlements реально легли в подпись и кто её выдал.

codesign --verify --deep --strict --verbose=2 "$app"
echo "Подпись:"
codesign -dvv "$app" 2>&1 | grep -E '^(Authority|TeamIdentifier|Identifier)=' | sed 's/^/    /'
echo "В подписи:"
codesign -d --entitlements :- "$app" 2>/dev/null | plutil -p - | sed 's/^/    /'

# --- 6. Упаковка ----------------------------------------------------------

ipa=$root/build/echos-$version-signed.ipa
rm -rf "$work/Payload" "$ipa"
mkdir "$work/Payload"
cp -R "$app" "$work/Payload/"
(cd "$work" && zip -qry "$ipa" Payload)
rm -rf "$work/Payload"

echo
echo "Готово: ${ipa#$root/}"
echo "Поставить: xcrun devicectl device install app --device <id> \"$ipa\""
echo "Список id:  xcrun devicectl list devices"
