#!/bin/bash
# Build a signed Tinycast.app into build/Tinycast-<version>[-<arch>].dmg.
# Usage: ./Scripts/build-dmg.sh [version] [arch] — arch: universal (default) | arm64 | x86_64
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IDENTITY="Tinycast Self-Signed"
DERIVED="build/DerivedData"

if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "✗ '$IDENTITY' code-signing identity not found — create it once (docs/signing.md)." >&2
    exit 1
fi

case "${2:-universal}" in
    universal)
        ARCHS="arm64 x86_64"
        ARCH_TAG=""
        ;;
    arm64)
        ARCHS="arm64"
        ARCH_TAG="-arm64"
        ;;
    x86_64)
        ARCHS="x86_64"
        ARCH_TAG="-x86_64"
        ;;
    *)
        echo "✗ unknown arch '$2' (expected universal, arm64 or x86_64)." >&2
        exit 1
        ;;
esac

echo "▸ Building signed Tinycast.app (Release, ${ARCHS})…"
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
    ${1:+MARKETING_VERSION="$1"} \
    build

APP="$DERIVED/Build/Products/Release/Tinycast.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/Tinycast-${VERSION}${ARCH_TAG}.dmg"

echo "▸ Packaging ${DMG}"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
diskutil image create from "$STAGE" --format UDZO --volumeName "Tinycast" "$DMG" > /dev/null
rm -rf "$STAGE"

echo "✓ $DMG"
