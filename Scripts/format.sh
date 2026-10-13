#!/bin/bash
# Format the project with swift-format (`--check` only reports). It restructures, not just lays out.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# The toolchain's swift-format, not brew's, so this and the editor's ⌘S can never disagree.
FORMAT=$(xcrun --find swift-format 2>/dev/null)
[ -x "${FORMAT:-}" ] || {
    echo "✗ swift-format not found in the Xcode toolchain. Check 'xcode-select -p'." >&2
    exit 2
}

# A read loop rather than `mapfile`, which is bash 4 — macOS ships bash 3.2.
files=()
while IFS= read -r f; do files+=("$f"); done < <(
    find Tinycast Tests -name '*.swift' ! -name '*.generated.swift' \
        ! -path 'Tinycast/DesignSystem/Scrolling/EdgeDissolve.swift' \
        ! -path 'Tinycast/DesignSystem/Scrolling/ThinScrollbar.swift' | sort
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
