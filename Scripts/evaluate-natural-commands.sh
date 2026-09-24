#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

evaluation_dir=$(mktemp -d)
trap 'rm -rf "$evaluation_dir"' EXIT

swiftc -swift-version 6 -o "$evaluation_dir/evaluate" \
    Scripts/evaluate-natural-commands.swift \
    Tinycast/Features/NaturalCommands/Model/NaturalCommand.swift \
    Tinycast/Features/NaturalCommands/Model/NaturalCommandWindowMeaning.swift \
    Tinycast/Features/NaturalCommands/Service/NaturalCommandClient.swift \
    Tinycast/Features/WindowManagement/Model/WindowCommand.swift \
    Tinycast/Features/SystemActions/Model/SystemAction.swift

"$evaluation_dir/evaluate" "$@"
