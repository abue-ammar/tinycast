#!/bin/bash
# Fails once a stable release has shipped a migration, so it is deleted instead of kept for ages.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

shopt -s nullglob
files=(Tinycast/Migrations/*.swift)
[ ${#files[@]} -eq 0 ] && exit 0

# A shallow clone has no tags to compare against, so every migration would pass.
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
    echo "✗ check-migrations needs full history: git fetch --unshallow" >&2
    exit 1
fi

status=0
for file in "${files[@]}"; do
    name=$(basename "$file" .swift)
    if ! grep -q "\`$name\`" docs/migrations.md; then
        echo "✗ $name has no row in docs/migrations.md" >&2
        status=1
    fi
    added=$(git log --no-renames --diff-filter=A --format=%H -1 -- "$file")
    [ -n "$added" ] || continue
    shipped=$(git tag --contains "$added" --sort=v:refname | grep -Em1 '^v[0-9]+\.[0-9]+\.[0-9]+$')
    if [ -n "$shipped" ]; then
        echo "✗ $name shipped in $shipped: delete what its row in docs/migrations.md lists" >&2
        status=1
    fi
done
exit $status
