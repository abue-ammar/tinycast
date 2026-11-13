#!/bin/bash
# Wrap the stapled app in the old-bundle-id handoff, then notarize, zip and sign it.
# Usage: package-handoff.sh <handoff.app> <app> <zip>
set -euo pipefail

HANDOFF="${1:?usage: package-handoff.sh <handoff.app> <app> <zip>}" APP="${2:?}" ZIP="${3:?}"
: "${SIGNING_IDENTITY:?}" "${NOTARY_KEY_P8_BASE64:?}" "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER_ID:?}"
: "${UPDATE_SIGNING_KEY:?}"
KEY="$(mktemp)" STAGE="$(mktemp -d)"
trap 'rm -rf "$KEY" "$STAGE"' EXIT
base64 --decode <<< "$NOTARY_KEY_P8_BASE64" > "$KEY"
AUTH=(--key "$KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")

"$(dirname "$0")/wrap-handoff.sh" "$HANDOFF" "$APP"

ditto -c -k --keepParent "$HANDOFF" "$STAGE/submission.zip"
RESULT="$(xcrun notarytool submit "$STAGE/submission.zip" "${AUTH[@]}" --wait --timeout 2h --output-format json)" || true
echo "$RESULT"
if [ "$(jq -r '.status // empty' <<< "$RESULT")" != Accepted ]; then
    xcrun notarytool log "$(jq -r '.id // empty' <<< "$RESULT")" "${AUTH[@]}" || true
    exit 1
fi

xcrun stapler staple "$HANDOFF"
mkdir -p "$(dirname "$ZIP")"
ditto -c -k --keepParent --sequesterRsrc "$HANDOFF" "$ZIP"
"$(dirname "$0")/sign-update.swift" "$APP" "$ZIP"
