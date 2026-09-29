#!/bin/bash
# Збирає ClaudeUsage.app з main.swift. Потрібні лише Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="ClaudeUsage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

echo "→ Компіляція…"
swiftc -O -parse-as-library main.swift \
  -framework Cocoa -framework Security -framework ServiceManagement -framework UserNotifications \
  -o "$APP/Contents/MacOS/ClaudeUsage"

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
  <key>LSUIElement</key>              <true/>
</dict>
</plist>
PLIST

echo "→ Локальний підпис…"
codesign --force --sign - "$APP"

echo "✓ Готово: $(pwd)/$APP"
echo "  Перенесіть його в /Applications і запустіть."
