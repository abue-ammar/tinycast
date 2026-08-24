#!/bin/bash
# Compose a release body from GitHub's generated notes. Usage: ./Scripts/release-notes.sh <body.md> <discord.md>
# The changelog goes above the install marker; the app shows only that half. See docs/release.md.
set -euo pipefail

BODY_OUT="${1:?usage: release-notes.sh <body.md> <discord.md>}"
DISCORD_OUT="${2:?usage: release-notes.sh <body.md> <discord.md>}"

REPO="${REPO:-abue-ammar/tinycast}"
CHANNEL="${CHANNEL:?CHANNEL is required (beta|stable)}"
TAG="${TAG:?TAG is required, e.g. v0.9.13-beta.61}"
SHA="${SHA:-$(git rev-parse HEAD)}"
VERSION="${VERSION:-${TAG#v}}"
DISPLAY_NAME="${DISPLAY_NAME:-Tinycast}"
BUNDLE_ID="${BUNDLE_ID:-com.tinycast.app}"
CASK="${CASK:-tinycast}"

# Everything below this line is for the download page; the update window cuts here.
MARKER="<!-- tinycast:install -->"
# Discord rejects a component over 4000 characters, and a wall of bullets reads worse than a taste.
DISCORD_BUDGET=1200
DISCORD_BULLETS=15

# Beta and stable tags interleave on main — the same commit carries both — so "the previous release"
# is only ever right per channel.
if [ "$CHANNEL" = "stable" ]; then
    CHANNEL_FILTER='test("-beta\\.") | not'
else
    CHANNEL_FILTER='test("-beta\\.")'
fi
PREVIOUS="$(gh release list --repo "$REPO" --limit 200 --json tagName,isDraft --jq \
    "[.[] | select(.isDraft | not) | .tagName
      | select(test(\"-sequoia\") | not) | select(. != \"${TAG}\") | select(${CHANNEL_FILTER})] | first // empty")"

# The tag does not exist yet — this runs before `gh release create` makes it.
NOTES_ARGS=(-f "tag_name=${TAG}" -f "target_commitish=${SHA}")
if [ -n "$PREVIOUS" ]; then NOTES_ARGS+=(-f "previous_tag_name=${PREVIOUS}"); fi
echo "▸ Generating notes for ${TAG}${PREVIOUS:+ since ${PREVIOUS}}"
GENERATED="$(gh api "repos/${REPO}/releases/generate-notes" "${NOTES_ARGS[@]}" --jq .body)"

COMPARE_URL="$(printf '%s\n' "$GENERATED" | sed -n 's|^\*\*Full Changelog\*\*: \(.*\)$|\1|p' | tail -n1)"

# A bare `#304` still autolinks on the web and fits the 460pt update window; the full URL does neither.
CHANGELOG="$(printf '%s\n' "$GENERATED" | sed -E \
    -e '/^\*\*Full Changelog\*\*:/d' \
    -e "s|https://github\.com/${REPO}/pull/([0-9]+)|#\1|g")"
[ -n "$(printf '%s' "$CHANGELOG" | tr -d '[:space:]')" ] || CHANGELOG="Maintenance and internal changes."

{
    printf '%s\n\n' "$CHANGELOG"
    printf '%s\n\n' "$MARKER"
    printf '**Channel:** %s · **Version:** %s · **Bundle ID:** `%s`\n' "$CHANNEL" "$VERSION" "$BUNDLE_ID"
    printf 'Built from %s.' "$SHA"
    if [ -n "$COMPARE_URL" ]; then printf ' [Full changelog](%s)' "$COMPARE_URL"; fi
    printf '\n\n'
    printf '%s\n' "**Recommended:** install via Homebrew — it clears the quarantine flag automatically on every install and update, so there's nothing to run by hand:"
    printf '```sh\nbrew trust --tap abue-ammar/tinycast\nbrew install --cask abue-ammar/tinycast/%s\n```\n' "$CASK"
    printf '%s\n' "This build is self-signed. If you download the DMG directly instead of using Homebrew, macOS will refuse to open it until you clear the quarantine flag once:"
    printf '```sh\nxattr -dr com.apple.quarantine "/Applications/%s.app"\n```\n' "$DISPLAY_NAME"
} > "$BODY_OUT"

printf '%s\n' "$CHANGELOG" | awk -v budget="$DISCORD_BUDGET" -v bullets="$DISCORD_BULLETS" '
    { line = $0 }
    /^[*-] / { seen++ }
    { used += length(line) + 1 }
    used > budget || seen > bullets { print "…and more — see the release page."; exit }
    { print line }
' > "$DISCORD_OUT"

echo "✓ ${BODY_OUT}"
