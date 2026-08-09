#!/bin/bash
# Rebuild SourceKit-LSP's flag database from a build log. Run by the VS Code build task; also the
# one-time editor setup, since it is what creates buildServer.json. See docs/development.md.
#
# `xcode-build-server parse` with no `-o` is deliberate: that is the only spelling that also writes
# buildServer.json, and it writes it as `kind: manual`. The `kind: xcode` alternative ignores .compile
# entirely and reads a cache scraped from .xcactivitylog instead — which silently freezes the moment
# LogStoreManifest.plist stops updating, pinning the editor to a source list from an old build.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

LOG=${1:-}
if [ -z "$LOG" ] || [ ! -f "$LOG" ]; then
    echo "usage: $0 <xcodebuild-log>" >&2
    exit 2
fi
command -v xcode-build-server >/dev/null || { echo "xcode-build-server not installed; skipping." >&2; exit 0; }

# A build that compiled no Swift emits no compile commands, and parsing it would replace .compile with
# an empty database — every file loses its flags. Keep the previous one in that case.
backup="${TMPDIR:-/tmp}/tinycast-compile.bak"
[ -f .compile ] && cp .compile "$backup"

xcode-build-server parse < "$LOG" >/dev/null 2>&1

if [ ! -s .compile ] || ! grep -q '"command"' .compile 2>/dev/null; then
    if [ -f "$backup" ]; then
        cp "$backup" .compile
        echo "no compile commands in log; kept the previous .compile" >&2
    fi
fi
rm -f "$backup"

./Scripts/run-tests.sh --index
