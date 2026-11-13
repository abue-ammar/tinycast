#!/bin/bash
# Put the app inside the handoff and re-seal it, checking what an old copy's updater checks.
# Usage: wrap-handoff.sh <handoff.app> <app>
set -euo pipefail

HANDOFF="${1:?usage: wrap-handoff.sh <handoff.app> <app>}" APP="${2:?}"
: "${SIGNING_IDENTITY:?}"

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }
fail() {
    echo "✗ $1" >&2
    exit 1
}

APP_ID="$(plist "$APP" CFBundleIdentifier)"
case "$APP_ID" in
    com.abueammar.tinycast | com.abueammar.tinycast.*) LEGACY_ID="com.tinycast.app${APP_ID#com.abueammar.tinycast}" ;;
    *) fail "$APP_ID has no bundle id from before the move" ;;
esac
[ "$(plist "$HANDOFF" CFBundleIdentifier)" = "$LEGACY_ID" ] ||
    fail "the handoff is not $LEGACY_ID, the only id an old copy installs"
[ "$(plist "$HANDOFF" CFBundleShortVersionString)" = "$(plist "$APP" CFBundleShortVersionString)" ] ||
    fail "the handoff's version is not the release's, so an old copy would refuse it"

rm -rf "$HANDOFF/Contents/Helpers"
mkdir -p "$HANDOFF/Contents/Helpers"
ditto "$APP" "$HANDOFF/Contents/Helpers/${APP##*/}"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$HANDOFF"
codesign --verify --deep --strict "$HANDOFF" || fail "${HANDOFF##*/}: the seal does not verify"
echo "✓ ${HANDOFF##*/} carries $APP_ID under $LEGACY_ID"
