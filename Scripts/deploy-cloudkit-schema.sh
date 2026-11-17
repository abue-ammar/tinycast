#!/bin/bash
# Validate and import Config/CloudKit/schema.ckdb into one container's environment.
# Usage: deploy-cloudkit-schema.sh <development|production> <container-id>
# The token comes from CLOUDKIT_MANAGEMENT_TOKEN, else from `xcrun cktool save-token`.
set -euo pipefail

ENVIRONMENT="${1:?usage: deploy-cloudkit-schema.sh <development|production> <container-id>}"
CONTAINER="${2:?usage: deploy-cloudkit-schema.sh <development|production> <container-id>}"
SCHEMA="$(cd "$(dirname "$0")/.." && pwd)/Config/CloudKit/schema.ckdb"
TEAM_ID="J656U8XZ93"

case "$ENVIRONMENT" in
    development | production) ;;
    *) echo "environment must be development or production" >&2; exit 1 ;;
esac

TOKEN=()
[ -n "${CLOUDKIT_MANAGEMENT_TOKEN:-}" ] && TOKEN=(--token "$CLOUDKIT_MANAGEMENT_TOKEN")
ARGS=(--team-id "$TEAM_ID" --container-id "$CONTAINER" --environment "$ENVIRONMENT")

xcrun cktool import-schema ${TOKEN[@]+"${TOKEN[@]}"} "${ARGS[@]}" --validate --file "$SCHEMA"
echo "✓ $CONTAINER ($ENVIRONMENT) has the iCloud Sync schema"
