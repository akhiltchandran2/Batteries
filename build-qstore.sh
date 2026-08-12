#!/bin/bash
# Builds PowerDeck.app for QStore: versioned from the environment, with
# Sparkle embedded for automatic updates, ad-hoc signed. Output goes to
# ./build-qstore/PowerDeck.app — this is separate from build.sh's plain
# ./build/PowerDeck.app, which has no Sparkle dependency at all.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${APP_VERSION:-1.0.0}"
BUILD="${APP_BUILD:-$(date +%y%m%d%H%M)}"

echo "Building PowerDeck $VERSION ($BUILD) for QStore…"

# SwiftPM product is still named "BatteriesQStore" (internal target name);
# the packaged app and its executable are branded "PowerDeck".
swift build -c release --product BatteriesQStore

APP="build-qstore/PowerDeck.app"
rm -rf "build-qstore"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp ".build/release/BatteriesQStore" "$APP/Contents/MacOS/PowerDeck"

sed -e "s/__APP_VERSION__/$VERSION/g" -e "s/__APP_BUILD__/$BUILD/g" \
    "Resources/Info-QStore.plist" > "$APP/Contents/Info.plist"

cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Locate the Sparkle.framework SwiftPM fetched and built against — this is
# the one already on the linker's rpath-relative search, so it's the one
# that must end up in Contents/Frameworks. ditto (not cp -R) to preserve
# the internal Versions/Current symlinks a versioned framework relies on.
SPARKLE_SRC=$(find .build -type d -name "Sparkle.framework" -path "*/release/*" | head -1)
if [ -z "$SPARKLE_SRC" ]; then
  echo "❌ Could not locate a built Sparkle.framework under .build/*/release/" >&2
  exit 1
fi
ditto "$SPARKLE_SRC" "$APP/Contents/Frameworks/Sparkle.framework"

# Sign nested code inside Sparkle.framework first, deepest first — its XPC
# services, its Updater.app, and its Autoupdate helper each need their own
# signature, and --deep does not do this reliably. Ad-hoc only: no
# --options runtime, since hardened runtime requires embedded frameworks to
# share the app's team identity, which an ad-hoc signature does not have —
# the app would die at launch with "Library not loaded".
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
# Resolve the current versioned dir (e.g. Versions/B) rather than hardcoding,
# so a future Sparkle that bumps its version letter still signs correctly.
CURRENT=$(/usr/bin/readlink "$SPARKLE/Versions/Current" 2>/dev/null || echo "Current")
VERSIONED="$SPARKLE/Versions/$CURRENT"

for xpc in "$VERSIONED/XPCServices/Downloader.xpc" "$VERSIONED/XPCServices/Installer.xpc"; do
  if [ -e "$xpc" ]; then
    codesign --force --sign - "$xpc"
  fi
done
if [ -e "$VERSIONED/Updater.app" ]; then
  codesign --force --sign - "$VERSIONED/Updater.app"
fi
if [ -f "$VERSIONED/Autoupdate" ]; then
  codesign --force --sign - "$VERSIONED/Autoupdate"
fi
codesign --force --sign - "$SPARKLE"
codesign --force --sign - "$APP"

cp "STORE.md" "build-qstore/STORE.md" 2>/dev/null || true
cp "CHANGELOG.md" "build-qstore/CHANGELOG.md" 2>/dev/null || true

echo "✅ Built $APP  (version $VERSION, build $BUILD)"
echo "   Run it with:  open '$PWD/$APP'"
