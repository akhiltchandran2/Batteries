#!/bin/bash
# Builds Batteries.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Batteries.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/Batteries" "$APP/Contents/MacOS/Batteries"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc sign so notifications and launch-at-login work.
codesign --force --sign - "$APP"

echo "✅ Built $APP"
echo "   Run it with:  open '$PWD/$APP'"
