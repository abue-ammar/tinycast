#!/bin/bash
# Usage: install-provisioning-profile.sh <file>, so Xcode's manual signing finds it by name.
set -euo pipefail

PROFILE="${1:?usage: install-provisioning-profile.sh <file>}"
DESTINATION="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
UUID="$(security cms -D -i "$PROFILE" | plutil -extract UUID raw -o - -)"

mkdir -p "$DESTINATION"
cp "$PROFILE" "$DESTINATION/$UUID.provisionprofile"
echo "✓ Installed $(security cms -D -i "$PROFILE" | plutil -extract Name raw -o - -) ($UUID)"
