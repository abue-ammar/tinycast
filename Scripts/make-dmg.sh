#!/bin/bash
# Pack an app into a compressed DMG that opens as the installer window. Usage: make-dmg.sh <app> <dmg>
set -euo pipefail

APP="${1:?usage: make-dmg.sh <app> <dmg>}" DMG="${2:?}"
NAME="$(basename "$APP")"
WORK="$(mktemp -d)" DEVICE=""
trap '[ -z "$DEVICE" ] || diskutil eject "$DEVICE" >/dev/null 2>&1; rm -rf "$WORK"' EXIT

mkdir "$WORK/stage"
ditto "$APP" "$WORK/stage/$NAME"
ln -s /Applications "$WORK/stage/Applications"
diskutil image create from "$WORK/stage" --format RAW --volumeName "${NAME%.app}" "$WORK/layout.dmg" >/dev/null

# Laid out while mounted, so the background bookmark names the image's own volume.
DEVICE="$(diskutil image attach --nobrowse --mountPoint "$WORK/volume" "$WORK/layout.dmg" | awk 'NR == 1 { print $1 }')"
"$(dirname "$0")/dmg-layout.swift" "$WORK/volume" "$NAME"
diskutil eject "$DEVICE" >/dev/null
DEVICE=""

mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"
diskutil image create from "$WORK/layout.dmg" --format UDZO "$DMG" >/dev/null
