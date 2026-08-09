#!/bin/bash
# Format the whole project with swift-format. `--check` reports instead of writing, for CI.
# Read docs/decisions.md entry 26 first: this restructures code, it does not merely lay it out.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# The Xcode toolchain's swift-format, the same binary sourcekit-lsp formats with — not a brew package,
# so the editor's ⌘S and this script can never disagree.
FORMAT=$(xcrun --find swift-format 2>/dev/null)
[ -x "${FORMAT:-}" ] || {
    echo "✗ swift-format not found in the Xcode toolchain. Check 'xcode-select -p'." >&2
    exit 2
}

# Generated files are never hand-edited, and formatting one is exactly that — the next
# `node Scripts/gen-emoji.js` would revert it.
# Built with a read loop rather than `mapfile`, which is bash 4 — macOS ships bash 3.2.
files=()
while IFS= read -r f; do files+=("$f"); done < <(
    find Tinycast Tests -name '*.swift' ! -name '*.generated.swift' | sort
)

if [ "${1:-}" = "--check" ]; then
    dirty=()
    for f in "${files[@]}"; do
        "$FORMAT" --configuration .swift-format "$f" 2>/dev/null | diff -q - "$f" >/dev/null 2>&1 || dirty+=("$f")
    done
    if [ ${#dirty[@]} -gt 0 ]; then
        printf '%s\n' "${dirty[@]}"
        echo
        echo "${#dirty[@]} file(s) need formatting. Run ./Scripts/format.sh" >&2
        exit 1
    fi
    echo "✓ format-clean (${#files[@]} files)"
    exit 0
fi

failed=()
for f in "${files[@]}"; do
    "$FORMAT" --configuration .swift-format --in-place "$f" || failed+=("$f")
done

# swift-format refuses a file that does not parse, so a failure here is a syntax error, not a bug.
if [ ${#failed[@]} -gt 0 ]; then
    printf '\n%d file(s) could not be formatted (they do not parse):\n' "${#failed[@]}" >&2
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi
echo "✓ formatted ${#files[@]} files"
