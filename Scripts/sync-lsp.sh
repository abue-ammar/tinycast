#!/bin/bash
# Rebuild SourceKit-LSP's flag database from a build log. See docs/development.md.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

LOG=${1:-}
if [ -z "$LOG" ] || [ ! -f "$LOG" ]; then
    echo "usage: $0 <xcodebuild-log>" >&2
    exit 2
fi
command -v xcode-build-server >/dev/null || { echo "xcode-build-server not installed; skipping." >&2; exit 0; }

# A build that compiled no Swift would replace .compile with an empty database, so keep the old one.
backup="${TMPDIR:-/tmp}/tinycast-compile.bak"
[ -f .compile ] && cp .compile "$backup"

# No `-o` on purpose: only this spelling also writes buildServer.json, as `kind: manual`.
xcode-build-server parse < "$LOG" >/dev/null 2>&1

if [ ! -s .compile ] || ! grep -q '"command"' .compile 2>/dev/null; then
    if [ -f "$backup" ]; then
        cp "$backup" .compile
        echo "no compile commands in log; kept the previous .compile" >&2
    fi
fi
rm -f "$backup"

./Scripts/run-tests.sh --index
