#!/bin/bash
# Usage: check-cloudkit-schema.sh <container-id> [environment]; fails on a missing SyncItem field.
set -euo pipefail

CONTAINER="${1:?usage: check-cloudkit-schema.sh <container-id> [environment]}"
ENVIRONMENT="${2:-production}"
SCHEMA="$(cd "$(dirname "$0")/.." && pwd)/Config/CloudKit/schema.ckdb"

TOKEN=()
[ -n "${CLOUDKIT_MANAGEMENT_TOKEN:-}" ] && TOKEN=(--token "$CLOUDKIT_MANAGEMENT_TOKEN")

fields() {
    sed -n '/RECORD TYPE SyncItem/,/);/p' | awk '$1 !~ /^(RECORD|GRANT|\)|")/ { sub(/,$/, ""); $1 = $1; print }' | sort
}

LIVE="$(xcrun cktool export-schema ${TOKEN[@]+"${TOKEN[@]}"} --team-id J656U8XZ93 \
    --container-id "$CONTAINER" --environment "$ENVIRONMENT")"
MISSING="$(comm -23 <(fields < "$SCHEMA") <(fields <<< "$LIVE"))"
if [ -n "$MISSING" ]; then
    echo "✗ $CONTAINER ($ENVIRONMENT) lacks these SyncItem fields:" >&2
    echo "$MISSING" | sed 's/^/    /' >&2
    echo "  Run ./Scripts/deploy-cloudkit-schema.sh $CONTAINER, then Deploy Schema Changes in the CloudKit Console." >&2
    exit 1
fi
echo "✓ $CONTAINER ($ENVIRONMENT) has the iCloud Sync schema"
