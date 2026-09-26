#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product SwissTransfer

# Le .app de travail reste hors du projet : sinon Spotlight en montre deux.
STAGE="$(mktemp -d)"
APP="$STAGE/SwissTransfer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "build/icon.iconset"

cp ".build/release/SwissTransfer" "$APP/Contents/MacOS/SwissTransfer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/wallpaper.jpg "$APP/Contents/Resources/wallpaper.jpg"
cp Resources/swiss-transfer-logo.png "$APP/Contents/Resources/swiss-transfer-logo.png"

sips -z 1024 1024 Resources/swiss-transfer-logo.png --out build/icon-1024.png >/dev/null
sips -z 16 16 build/icon-1024.png --out build/icon.iconset/icon_16x16.png >/dev/null
sips -z 32 32 build/icon-1024.png --out build/icon.iconset/icon_16x16@2x.png >/dev/null
sips -z 32 32 build/icon-1024.png --out build/icon.iconset/icon_32x32.png >/dev/null
sips -z 64 64 build/icon-1024.png --out build/icon.iconset/icon_32x32@2x.png >/dev/null
sips -z 128 128 build/icon-1024.png --out build/icon.iconset/icon_128x128.png >/dev/null
sips -z 256 256 build/icon-1024.png --out build/icon.iconset/icon_128x128@2x.png >/dev/null
sips -z 256 256 build/icon-1024.png --out build/icon.iconset/icon_256x256.png >/dev/null
sips -z 512 512 build/icon-1024.png --out build/icon.iconset/icon_256x256@2x.png >/dev/null
sips -z 512 512 build/icon-1024.png --out build/icon.iconset/icon_512x512.png >/dev/null
sips -z 1024 1024 build/icon-1024.png --out build/icon.iconset/icon_512x512@2x.png >/dev/null
iconutil -c icns build/icon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"

mkdir -p "$HOME/Applications"
osascript -e 'quit app "SwissTransfer"' >/dev/null 2>&1 || true
sleep 0.4
rm -rf "$HOME/Applications/SwissTransfer.app"
ditto "$APP" "$HOME/Applications/SwissTransfer.app"
codesign --force --sign - "$HOME/Applications/SwissTransfer.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -d "build/SwissTransfer.app" ]]; then
  "$LSREGISTER" -u "build/SwissTransfer.app" || true
  rm -rf "build/SwissTransfer.app"
fi
"$LSREGISTER" -f "$HOME/Applications/SwissTransfer.app"
rm -rf "$STAGE"
echo "Installed $HOME/Applications/SwissTransfer.app"
