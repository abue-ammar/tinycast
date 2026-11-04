#!/bin/bash
# Import the release signing identity into a throwaway keychain. CI only.
set -euo pipefail

: "${P12_BASE64:?}" "${P12_PASSWORD:?}" "${RUNNER_TEMP:?}"
KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
P12="$RUNNER_TEMP/signing.p12"
CA="$RUNNER_TEMP/DeveloperIDG2CA.cer"
KPW="$(openssl rand -base64 24)"
trap 'rm -f "$P12" "$CA"' EXIT

base64 --decode <<< "$P12_BASE64" > "$P12"
# macOS ships only the G1 intermediate; without G2, codesign cannot build the certificate chain.
curl -fsSL https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer -o "$CA"
security create-keychain -p "$KPW" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KPW" "$KEYCHAIN"
security import "$CA" -k "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -A -T /usr/bin/codesign
# Let codesign use the key without an interactive prompt.
security set-key-partition-list -S apple-tool:,apple: -s -k "$KPW" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | sed 's/"//g')
