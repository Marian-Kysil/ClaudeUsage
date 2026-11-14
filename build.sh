#!/bin/bash
# Збирає ClaudeUsage.app з main.swift. Потрібні лише Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="ClaudeUsage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ Компіляція…"
swiftc -O -parse-as-library main.swift \
  -framework Cocoa -framework Security -framework ServiceManagement -framework UserNotifications \
  -o "$APP/Contents/MacOS/ClaudeUsage"

echo "→ Іконки…"
# assets/ — іконки з Figma. AppIcon.icns збирається з 1024px PNG; MenuBarIcon — template-гліф для рядка меню.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz assets/AppIcon-1024.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) assets/AppIcon-1024.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"
cp assets/MenuBarIcon.png assets/MenuBarIcon@2x.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>             <string>ClaudeUsage</string>
  <key>CFBundleIdentifier</key>       <string>local.claudeusage</string>
  <key>CFBundleExecutable</key>       <string>ClaudeUsage</string>
  <key>CFBundlePackageType</key>      <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key>   <string>14.0</string>
  <key>CFBundleIconFile</key>         <string>AppIcon</string>
  <key>LSUIElement</key>              <true/>
</dict>
</plist>
PLIST

echo "→ Локальний підпис…"
# Стабільний самопідписаний сертифікат: ідентичність застосунку не змінюється між збірками,
# тож «Завжди дозволяти» для Keychain зберігається. Ad-hoc підпис міняв би її щоразу.
CERT="ClaudeUsage Local"
if ! security find-identity -p codesigning | grep -q "$CERT"; then
  echo "  Створюю сертифікат «${CERT}» (одноразово)…"
  TMP="$(mktemp -d)"
  cat > "$TMP/openssl.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ClaudeUsage Local
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CNF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass:claudeusage 2>/dev/null
  security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P claudeusage -T /usr/bin/codesign >/dev/null
  rm -rf "$TMP"
fi

if security find-identity -p codesigning | grep -q "$CERT"; then
  codesign --force --sign "$CERT" --identifier local.claudeusage "$APP"
else
  echo "  ⚠︎ Сертифікат недоступний — підписую ad-hoc (пароль проситиме після кожної збірки)."
  codesign --force --sign - "$APP"
fi

echo "✓ Готово: $(pwd)/$APP"
echo "  Перенесіть його в /Applications і запустіть."
