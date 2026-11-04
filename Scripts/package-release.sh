#!/bin/bash
# Notarize a release DMG and zip the stapled app. Usage: package-release.sh <app> <dmg> <zip>
set -euo pipefail

APP="${1:?usage: package-release.sh <app> <dmg> <zip>}" DMG="${2:?}" ZIP="${3:?}"
: "${SIGNING_IDENTITY:?}" "${NOTARY_KEY_P8_BASE64:?}" "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER_ID:?}"
KEY="$(mktemp)" STAGE="$(mktemp -d)"
trap 'rm -rf "$KEY" "$STAGE"' EXIT
base64 --decode <<< "$NOTARY_KEY_P8_BASE64" > "$KEY"
AUTH=(--key "$KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")

ditto "$APP" "$STAGE/${APP##*/}"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$(dirname "$DMG")" "$(dirname "$ZIP")"
diskutil image create from "$STAGE" --format UDZO --volumeName "$(basename "$APP" .app)" "$DMG"
codesign -s "$SIGNING_IDENTITY" --timestamp "$DMG"

RESULT="$(xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait --timeout 2h --output-format json)" || true
echo "$RESULT"
if [ "$(jq -r '.status // empty' <<< "$RESULT")" != Accepted ]; then
    xcrun notarytool log "$(jq -r '.id // empty' <<< "$RESULT")" "${AUTH[@]}" || true
    exit 1
fi

# The DMG's ticket covers the app inside it, so the updater's zip carries one too.
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"
# Only `ditto` keeps the signature verifiable; plain `zip` drops symlinks and the seal.
ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"
