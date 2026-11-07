#!/bin/bash
# Compose a release body from GitHub's generated notes. See docs/release.md.
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

# Beta and stable tags share commits on main, so "the previous release" is only right per channel.
if [ "$CHANNEL" = "stable" ]; then
    CHANNEL_FILTER='test("-beta\\.") | not'
else
    CHANNEL_FILTER='test("-beta\\.")'
fi
PREVIOUS="$(gh release list --repo "$REPO" --limit 200 --json tagName,isDraft --jq \
    "[.[] | select(.isDraft | not) | .tagName
      | select(. != \"${TAG}\") | select(${CHANNEL_FILTER})] | first // empty")"

# The tag does not exist yet — this runs before `gh release create` makes it.
NOTES_ARGS=(-f "tag_name=${TAG}" -f "target_commitish=${SHA}")
if [ -n "$PREVIOUS" ]; then NOTES_ARGS+=(-f "previous_tag_name=${PREVIOUS}"); fi
echo "▸ Generating notes for ${TAG}${PREVIOUS:+ since ${PREVIOUS}}"
GENERATED="$(gh api "repos/${REPO}/releases/generate-notes" "${NOTES_ARGS[@]}" --jq .body)"

COMPARE_URL="$(printf '%s\n' "$GENERATED" | sed -n 's|^\*\*Full Changelog\*\*: \(.*\)$|\1|p' | tail -n1)"

# A bare `#304` autolinks on the web and fits the 460pt update window; the full URL does neither.
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
    printf 'Install via Homebrew, or open the DMG below and drag %s to Applications:\n' "$DISPLAY_NAME"
    printf '```sh\nbrew install --cask %s\n```\n' "$CASK"
} > "$BODY_OUT"

printf '%s\n' "$CHANGELOG" | awk -v budget="$DISCORD_BUDGET" -v bullets="$DISCORD_BULLETS" '
    { line = $0 }
    /^[*-] / { seen++ }
    { used += length(line) + 1 }
    used > budget || seen > bullets { print "…and more — see the release page."; exit }
    { print line }
' > "$DISCORD_OUT"

echo "✓ ${BODY_OUT}"
