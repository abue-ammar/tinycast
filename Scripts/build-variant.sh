#!/bin/bash
usage() {
    cat <<'USAGE'
Usage: Scripts/build-variant.sh [--without ai,extensions,dictation] [options]

  --without LIST     features to compile out; none builds the full app
  --check            build and verify every combination, install nothing
  --no-install       build, verify and test, but leave /Applications alone
  --generate-only    write Tinycast-<variant>.xcodeproj and stop
  --skip-tests       skip Scripts/run-tests.sh
  --configuration    Debug (default) or Release

See Variants/README.md.
USAGE
}

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

KNOWN=(dictation extensions ai)
without=""
mode=install
skip_tests=0
configuration=Debug

while [ $# -gt 0 ]; do
    case "$1" in
        --without) without=$2; shift 2;;
        --without=*) without=${1#*=}; shift;;
        --check) mode=check; shift;;
        --no-install) mode=build; shift;;
        --generate-only) mode=generate; shift;;
        --skip-tests) skip_tests=1; shift;;
        --configuration) configuration=$2; shift 2;;
        -h|--help) usage; exit 0;;
        *) echo "build-variant: unknown option $1" >&2; usage >&2; exit 2;;
    esac
done

die() { echo "build-variant: $*" >&2; exit 1; }
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# Canonical order, so `ai,dictation` and `dictation,ai` are the same variant.
canonical() {
    local requested=" ${1//,/ } " out=()
    for word in ${1//,/ }; do
        [[ " ${KNOWN[*]} " == *" $word "* ]] || die "unknown feature '$word' (known: ${KNOWN[*]})"
    done
    for name in "${KNOWN[@]}"; do [[ $requested == *" $name "* ]] && out+=("$name"); done
    echo "${out[*]:-}"
}

variant_name() { [ -z "$1" ] && echo full || echo "no-${1// /-}"; }

developer_dir() {
    local current
    current=$(xcode-select -p 2>/dev/null || true)
    if [ -d "$current/Platforms/MacOSX.platform" ]; then echo "$current"; return; fi
    for app in /Applications/Xcode.app /Applications/Xcode-beta.app /Applications/Xcode*.app; do
        [ -d "$app/Contents/Developer/Platforms/MacOSX.platform" ] && { echo "$app/Contents/Developer"; return; }
    done
    die "Xcode is not installed (xcode-select points at '$current'); the SwiftUI macros need Xcode."
}

# Beside project.yml, since SOURCE_ROOT paths resolve from the project's own folder.
project_path() { echo "$ROOT/Tinycast-$1.xcodeproj"; }

generate() {
    local features=$1 dir=$2 name=$3
    command -v xcodegen > /dev/null || die "xcodegen is missing: brew install xcodegen"
    command -v node > /dev/null || die "node is missing"
    mkdir -p "$dir"
    local exclude
    exclude=$(git rev-parse --git-path info/exclude)
    grep -qxF '/Tinycast-*.xcodeproj/' "$exclude" 2> /dev/null || echo '/Tinycast-*.xcodeproj/' >> "$exclude"
    xcodegen dump --quiet --type json --spec project.yml --file "$dir/dumped.json"
    # shellcheck disable=SC2086
    node Scripts/variant/make-spec.mjs "$dir/dumped.json" "$dir" "Tinycast-$name" $features
    xcodegen generate --quiet --spec "$dir/project.json" --project-root "$ROOT" --project "$ROOT"
}

build() {
    local name=$1 derived=$2 log=$3
    # Xcode never deletes what a variant stopped producing, so an old helper or resource survives.
    rm -rf "$(product_path "$derived")"
    DEVELOPER_DIR=$DEVELOPER_DIR xcodebuild -project "$(project_path "$name")" -scheme Tinycast \
        -configuration "$configuration" -derivedDataPath "$derived" build > "$log" 2>&1 || {
        grep -E 'error:' "$log" | sort -u | head -40 >&2
        die "build failed; full log: $log"
    }
    local warnings
    warnings=$(grep -E ': warning:' "$log" | grep -v '^ld: warning' | sort -u || true)
    if [ -n "$warnings" ]; then
        echo "$warnings" | sed "s#$ROOT/##" | head -40
        echo "$(echo "$warnings" | wc -l | tr -d ' ') warning(s); full log: $log"
    else
        echo "no warnings"
    fi
}

product_path() {
    local derived=$1 name
    name=$([ "$configuration" = Debug ] && echo "Tinycast Dev" || echo "Tinycast")
    echo "$derived/Build/Products/$configuration/$name.app"
}

verify() {
    local features=$1 app=$2 failed=0 name
    [ -d "$app" ] || die "no product at $app"
    local entitlements plist
    entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || echo '{}')
    plist=$(plutil -convert json -o - "$app/Contents/Info.plist")
    for name in $features; do
        while IFS= read -r path; do
            [ -z "$path" ] && continue
            path=${path//Tinycast Dev/$(basename "$app" .app)}
            if [ -e "$app/$path" ]; then echo "  still bundled: $path"; failed=1; fi
        done < <(node -e 'for (const p of require(process.argv[1])[process.argv[2]].absentFromBundle) console.log(p)' \
            "$ROOT/Variants/features.json" "$name")
        while IFS= read -r key; do
            [ -z "$key" ] && continue
            if echo "$entitlements" | grep -q "\"$key\""; then echo "  still entitled: $key"; failed=1; fi
        done < <(node -e 'for (const k of require(process.argv[1])[process.argv[2]].entitlements.deleteKeys) console.log(k)' \
            "$ROOT/Variants/features.json" "$name")
        while IFS= read -r scheme; do
            [ -z "$scheme" ] && continue
            if echo "$plist" | grep -q "\"$scheme\""; then echo "  still claims scheme: $scheme"; failed=1; fi
        done < <(node -e 'for (const s of require(process.argv[1])[process.argv[2]].infoPlist.removeURLSchemes) console.log(s)' \
            "$ROOT/Variants/features.json" "$name")
    done
    if [[ " $features " == *" extensions "* ]] && otool -L "$app/Contents/MacOS/"* 2>/dev/null | grep -q JavaScriptCore; then
        echo "  still links JavaScriptCore"; failed=1
    fi
    [ $failed -eq 0 ] || die "bundle verification failed for $app"
    echo "bundle verified: $(du -sh "$app" | cut -f1 | tr -d " ") total, code $(du -sh "$app/Contents/MacOS" | cut -f1 | tr -d " ")"
}

# A registered fuller copy would answer raycast:// with the installed app's prefs.
forget_bundle() {
    "$LSREGISTER" -u "$1" 2> /dev/null || true
    rm -rf "$1"
}

claim_url_schemes() {
    local target=$1 stale
    while IFS= read -r stale; do
        "$LSREGISTER" -u "$stale" 2> /dev/null || true
    done < <(find "$ROOT/build" -name "$(basename "$target")" -type d -prune 2> /dev/null)
    "$LSREGISTER" -f "$target"
}

install_app() {
    local features=$1 name=$2 app=$3 tests=$4
    local target="/Applications/$(basename "$app")"
    local stamp sha previous_commit=unknown backup record
    stamp=$(date +%Y%m%d-%H%M%S)
    sha=$(git rev-parse HEAD)
    local last
    last=$(ls -t build/install-records/*.txt 2>/dev/null | head -1 || true)
    if [ -n "$last" ]; then
        previous_commit=$(grep -E '^(Installed commit|Commit):' "$last" | head -1 | awk '{print $NF}' | cut -c1-8)
    fi
    if pgrep -xq "$(basename "$app" .app)"; then
        osascript -e "quit app \"$(basename "$app" .app)\"" || true
        for _ in $(seq 1 50); do pgrep -xq "$(basename "$app" .app)" || break; sleep 0.2; done
    fi
    if [ -d "$target" ]; then
        backup="build/install-backups/$stamp-$previous_commit"
        mkdir -p "$backup"
        ditto "$target" "$backup/$(basename "$target")"
        rm -rf "$target"
    fi
    ditto "$app" "$target"
    mkdir -p build/install-records
    record="build/install-records/$stamp-${sha:0:8}-$name.txt"
    {
        echo "Installed at: $(date -Iseconds)"
        echo "App: $target"
        echo "Configuration: $configuration"
        echo "Variant: $name"
        echo "Excluded features: ${features:-none}"
        echo "Signing: Tinycast Self-Signed, leaf $(codesign -d -r- "$target" 2>&1 | grep -oE 'leaf = H"[0-9a-f]+"' | cut -d'"' -f2)"
        echo "Commit: $sha"
        [ -n "${backup:-}" ] && echo "Previous app: $ROOT/$backup/$(basename "$target")"
        echo "Validation: build succeeded; bundle verified; $tests."
        echo
        echo "Changes:"
        if [ "$previous_commit" != unknown ] && git cat-file -e "$previous_commit" 2>/dev/null; then
            git log --oneline --no-merges "$previous_commit..$sha"
        fi
    } > "$record"
    claim_url_schemes "$target"
    open "$target"
    echo "installed $target; record $record"
}

DEVELOPER_DIR=""
case $mode in
    check)
        DEVELOPER_DIR=$(developer_dir)
        failures=()
        for mask in $(seq 0 $(( (1 << ${#KNOWN[@]}) - 1 ))); do
            set=()
            for i in "${!KNOWN[@]}"; do (( mask & (1 << i) )) && set+=("${KNOWN[$i]}"); done
            features="${set[*]:-}"
            name=$(variant_name "$features")
            dir="build/variant/check/$name"
            step "$name"
            generate "$features" "$dir" "$name"
            product=$(product_path "$dir/DerivedData")
            if ( build "$name" "$dir/DerivedData" "$dir/build.log" && verify "$features" "$product" ); then
                forget_bundle "$product"
            else
                failures+=("$name")
            fi
        done
        [ ${#failures[@]} -eq 0 ] || die "failed: ${failures[*]}"
        step "all $(( 1 << ${#KNOWN[@]} )) combinations build"
        ;;
    *)
        features=$(canonical "$without")
        name=$(variant_name "$features")
        dir="build/variant/$name"
        step "generating $name"
        generate "$features" "$dir" "$name"
        project_path "$name"
        [ $mode = generate ] && exit 0
        DEVELOPER_DIR=$(developer_dir)
        step "building $name ($configuration)"
        build "$name" build/DerivedData "$dir/build.log"
        app=$(product_path build/DerivedData)
        step "verifying bundle"
        verify "$features" "$app"
        tests="harnesses skipped"
        if [ $skip_tests -eq 0 ]; then
            step "running harnesses"
            DEVELOPER_DIR=$DEVELOPER_DIR ./Scripts/run-tests.sh | tail -3
            tests="Scripts/run-tests.sh passed"
        fi
        [ $mode = build ] && { echo "built $app"; exit 0; }
        step "installing"
        install_app "$features" "$name" "$app" "$tests"
        ;;
esac
