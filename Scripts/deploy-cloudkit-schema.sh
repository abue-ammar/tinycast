#!/bin/bash
# Usage: deploy-cloudkit-schema.sh <container-id>
# cktool imports only into Development; the CloudKit Console deploys it to Production.
set -euo pipefail

CONTAINER="${1:?usage: deploy-cloudkit-schema.sh <container-id>}"
SCHEMA="$(cd "$(dirname "$0")/.." && pwd)/Config/CloudKit/schema.ckdb"

xcrun cktool import-schema --team-id J656U8XZ93 --container-id "$CONTAINER" --environment development \
    --validate --file "$SCHEMA"
echo "✓ $CONTAINER (development) has the iCloud Sync schema; deploy it to Production in the CloudKit Console"
