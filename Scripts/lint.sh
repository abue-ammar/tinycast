#!/bin/bash
# Lint the whole project. `--fix` auto-corrects the mechanical subset first.
# Formatting is a separate tool with its own caveats — ./Scripts/format.sh, docs/decisions.md entry 26.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

command -v swiftlint >/dev/null || {
    echo "✗ swiftlint not found. Install it with:  brew install swiftlint" >&2
    exit 2
}

[ "${1:-}" = "--fix" ] && swiftlint --fix --quiet

# CI sets SWIFTLINT_REPORTER=github-actions-logging so violations land inline on the PR diff.
if ! swiftlint lint --quiet ${SWIFTLINT_REPORTER:+--reporter "$SWIFTLINT_REPORTER"}; then
    echo
    echo "Lint errors above. Warnings do not block; errors do." >&2
    exit 1
fi
echo "✓ lint-clean"
