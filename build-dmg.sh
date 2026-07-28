#!/bin/bash
# Build a signed Smallcast.app and pack it into build/Smallcast-<version>.dmg. Usage: ./build-dmg.sh [version]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"; cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IDENTITY="Smallcast Self-Signed"
DERIVED="build/DerivedData"

if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "✗ '$IDENTITY' code-signing identity not found — create it once (docs/signing.md)." >&2
    exit 1
fi

echo "▸ Building signed Smallcast.app (Release)…"
xcodebuild -project Smallcast.xcodeproj -scheme Smallcast -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    ${1:+MARKETING_VERSION="$1"} \
    build

APP="$DERIVED/Build/Products/Release/Smallcast.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/Smallcast-${VERSION}.dmg"

echo "▸ Packaging ${DMG}"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
diskutil image create from "$STAGE" --format UDZO --volumeName "Smallcast" "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ $DMG"