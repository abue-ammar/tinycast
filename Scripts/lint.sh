#!/bin/bash
# Lint the whole project. `--fix` auto-corrects the mechanical subset first.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

command -v swiftlint >/dev/null || {
    echo "✗ swiftlint not found. Install it with:  brew install swiftlint" >&2
    exit 2
}

[ "${1:-}" = "--fix" ] && swiftlint --fix --quiet

if ! swiftlint lint --quiet; then
    echo
    echo "Lint errors above. Warnings do not block; errors do." >&2
    exit 1
fi
# An unclaimed settings anchor or unmarked row fails silently, and nothing else catches it.
if ! node Scripts/check-settings-search.js; then
    exit 1
fi

echo "✓ lint-clean"
