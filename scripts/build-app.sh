#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Le .app de travail reste hors du projet : sinon Spotlight en montre deux.
STAGE="$(mktemp -d)"
APP="$STAGE/SwissTransfer.app"
"$(dirname "$0")/assemble-app.sh" "$APP"

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
