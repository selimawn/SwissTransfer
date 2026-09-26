#!/bin/bash
# Build dist/SwissTransfer.zip for GitHub Releases. Does not install the app.
set -euo pipefail
cd "$(dirname "$0")/.."

STAGE="$(mktemp -d)"
APP="$STAGE/SwissTransfer.app"
"$(dirname "$0")/assemble-app.sh" "$APP"

mkdir -p dist
rm -f dist/SwissTransfer.zip
ditto -c -k --keepParent "$APP" dist/SwissTransfer.zip
rm -rf "$STAGE"
echo "Wrote dist/SwissTransfer.zip"
