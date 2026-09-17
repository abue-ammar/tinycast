#!/bin/bash
# Mirror website/media/ into the R2 bucket behind cdn.tinycast.dev. Usage: upload-website-media.sh
set -euo pipefail

BUCKET="tinycast-cdn"
WEBSITE="$(cd "$(dirname "$0")/../website" && pwd)"

shopt -s nullglob
FILES=("$WEBSITE"/media/*)
if [ ${#FILES[@]} -eq 0 ]; then
    echo "No media in $WEBSITE/media — nothing to upload."
    exit 0
fi

cd "$WEBSITE"
for FILE in "${FILES[@]}"; do
    NAME="$(basename "$FILE")"
    # An unknown extension is a hard stop: R2 would serve it as octet-stream and the tag would break.
    case "$NAME" in
        *.mp4) TYPE="video/mp4" ;;
        *.webm) TYPE="video/webm" ;;
        *.mov) TYPE="video/quicktime" ;;
        *.png) TYPE="image/png" ;;
        *.jpg | *.jpeg) TYPE="image/jpeg" ;;
        *) echo "::error::$NAME: add its content type to Scripts/upload-website-media.sh first."; exit 1 ;;
    esac
    printf '▸ %s (%s, %s)\n' "$NAME" "$TYPE" "$(du -h "$FILE" | cut -f1)"
    npx wrangler r2 object put "${BUCKET}/${NAME}" --file "$FILE" --content-type "$TYPE" --remote
done

echo "✓ ${#FILES[@]} file(s) on https://cdn.tinycast.dev/"
