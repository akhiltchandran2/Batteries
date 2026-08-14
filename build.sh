#!/bin/bash
# Builds PowerDeck.app into ./build — the canonical, publishable build.
#
# This is the script QStore runs to publish, so it MUST read the version from
# the environment and produce the Sparkle-embedded, versioned, signed app.
# (There is deliberately only one build script: QStore always runs build.sh,
# so build.sh has to be the real thing.)
set -euo pipefail
cd "$(dirname "$0")"

# Publisher passes these in; both have safe defaults. BUILD is a counter that
# must always increase — defaulting to a timestamp guarantees that with no
# bookkeeping.
VERSION="${APP_VERSION:-1.4}"
BUILD="${APP_BUILD:-$(date +%y%m%d%H%M)}"

echo "Building PowerDeck $VERSION ($BUILD)…"

# SwiftPM product is named "BatteriesQStore" (internal target name); the
# packaged app and its executable are branded "PowerDeck".
swift build -c release --product BatteriesQStore

APP="build/PowerDeck.app"
rm -rf "build"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp ".build/release/BatteriesQStore" "$APP/Contents/MacOS/PowerDeck"

# Info-QStore.plist carries the Sparkle keys and __APP_VERSION__/__APP_BUILD__
# placeholders substituted here, so the two version numbers come from the env.
sed -e "s/__APP_VERSION__/$VERSION/g" -e "s/__APP_BUILD__/$BUILD/g" \
    "Resources/Info-QStore.plist" > "$APP/Contents/Info.plist"

cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "Resources/AirPodsArt" "$APP/Contents/Resources/AirPodsArt"

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

# Store card copy + release notes, next to the app so the publisher doesn't
# retype them.
cp "STORE.md" "build/STORE.md" 2>/dev/null || true
cp "CHANGELOG.md" "build/CHANGELOG.md" 2>/dev/null || true

echo "✅ Built $APP  (version $VERSION, build $BUILD)"
echo "   Run it with:  open '$PWD/$APP'"
