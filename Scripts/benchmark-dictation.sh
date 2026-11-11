#!/bin/bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if (( $# < 1 || $# > 4 )); then
    printf 'Usage: %s AUDIO [HELPER_APP] [MODEL_DIRECTORY] [MODEL]\n' "${0##*/}" >&2
    exit 2
fi
helper=${2:-"$repo/build/DerivedData/Build/Products/Debug/Tinycast Dev.app/Contents/Helpers/Tinycast Dev Dictation.app"}
models=${3:-"$HOME/Library/Caches/com.tinycast.app.dev/Dictation"}
binary=$(mktemp /tmp/tinycast-dictation-benchmark.XXXXXX)
trap 'rm -f "$binary"' EXIT
swiftc -O -swift-version 6 -target "$(uname -m)-apple-macos26.0" \
    "$repo/Tests/DictationPerformanceTests.swift" \
    "$repo/Tinycast/Platform/ProcessExit.swift" \
    "$repo/Tinycast/Features/Dictation/Model/DictationModel.swift" \
    "$repo/Tinycast/Features/Dictation/Service/DictationWire.swift" -o "$binary"
"$binary" "$1" "$helper" "$models" "${4:-all}"
