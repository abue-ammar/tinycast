#!/bin/sh
set -eu

fixture=${0%/*}
staged="$fixture/staged-copy"
cp "$2" "$staged"
if [ -p "$fixture/release" ]; then
    : > "$fixture/started"
    read -r line < "$fixture/release"
fi
mkdir -p "${3%/*}"
mv "$staged" "$3"
