#!/bin/bash
# Builds PowerDeck.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

# SwiftPM product is still named "Batteries" (internal target name); the
# packaged app and its executable are branded "PowerDeck".
swift build -c release --product Batteries

APP="build/PowerDeck.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/Batteries" "$APP/Contents/MacOS/PowerDeck"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so notifications and launch-at-login work.
codesign --force --sign - "$APP"

echo "✅ Built $APP"
echo "   Run it with:  open '$PWD/$APP'"
