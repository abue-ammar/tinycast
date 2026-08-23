#!/bin/bash
# The test suite. There is no XCTest target: each harness compiles the shipped sources it guards,
# so a harness that stops compiling means a decision leaked out of a pure layer. See docs/testing.md.
#
# Never join a compile and its run with `&&`: `set -e` ignores a failure in a non-final AND-OR list
# member, which is how CI reported success over a harness that had not compiled since phase 10.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/tinycast-harness"
mkdir -p "$BIN"

failed=()
ran=0
only="${1:-}"

# `--index` merges each harness's compile command into .compile instead of running anything.
# xcodebuild never compiles the harnesses, so without this nothing in Tests/ resolves in an editor.
# The source lists below are the only copy, which is why this lives here rather than in its own script.
emit_db=0
DB="${TMPDIR:-/tmp}/tinycast-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

# run <name> <source...> — compile the harness and run it, recording either kind of failure.
run() {
    local name=$1
    shift
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    ran=$((ran + 1))

    # Absolute paths throughout: sourcekit-lsp resolves the command itself and does not apply
    # `directory` to relative arguments, so a relative path there silently yields no index.
    if [ "$emit_db" -eq 1 ]; then
        local sources=()
        for source in "$@" "Tests/$name.swift"; do sources+=("$PWD/$source"); done
        [ "$ran" -gt 1 ] && printf ',' >> "$DB"
        printf '{"directory":"%s","command":"swiftc -swift-version 6 -sdk %s' \
            "$PWD" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        # Claim only the harness itself. The command still lists every shipped source it compiles, so
        # symbols resolve inside the harness — but claiming those sources here would hand them this
        # 3-file command instead of the app's, and `.compile` is last-wins.
        printf '","files":["%s/Tests/%s.swift"]}' "$PWD" "$name" >> "$DB"
        return 0
    fi

    if ! swiftc -swift-version 6 "$@" "Tests/$name.swift" -o "$BIN/$name" 2>&1; then
        printf '\033[31mFAIL\033[0m  %-22s did not compile\n' "$name"
        failed+=("$name")
        return 0
    fi
    if ! "$BIN/$name"; then
        printf '\033[31mFAIL\033[0m  %-22s assertion failed\n' "$name"
        failed+=("$name")
        return 0
    fi
    printf '\033[32mok\033[0m    %-22s\n' "$name"
}

L=Tinycast/Features/Launcher/Model
run fuzz-test              $L/SearchRelevance.swift
run file-search-test       $L/SearchRelevance.swift \
                           Tinycast/Features/FileSearch/Model/*.swift
run file-search-session-test Tinycast/Platform/Signposts.swift \
                             $L/SearchRelevance.swift \
                             Tinycast/Features/FileSearch/Model/*.swift \
                             Tinycast/Features/FileSearch/Service/*.swift
run ranking-test           $L/SearchRelevance.swift $L/LauncherRankingStore.swift
run scopes-test            $L/SearchScopes.swift
run favorites-test         $L/FavoriteSlots.swift
run calc-test              Tinycast/Features/Calculator/Model/*.swift
run calendar-test          Tinycast/Features/Calendar/Model/*.swift
run clipboard-test         Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFilter.swift
run emoji-test             Tinycast/Features/Emoji/Model/EmojiCatalog.swift \
                           Tinycast/Features/Emoji/Model/EmojiGridGeometry.swift \
                           Tinycast/Features/Emoji/Model/EmojiData.generated.swift
run palette-selection-test Tinycast/Features/PaletteRowIndex.swift \
                           Tinycast/Features/Emoji/Model/EmojiGridGeometry.swift
run appearance-test        Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/Features/Settings/AppAppearance.swift
run palette-placement-test Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/Palette/PalettePlacement.swift
run scroll-reveal-test     Tinycast/DesignSystem/Scrolling/SelectionReveal.swift
run hover-arming-test      Tinycast/Palette/HoverArming.swift \
                           Tinycast/Palette/PaletteState.swift \
                           Tinycast/Palette/PaletteMode.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift
run hotkey-test            Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Tinycast/Features/HotKeys/Model/DoubleTapDetector.swift \
                           Tinycast/Features/HotKeys/Model/HyperKey.swift \
                           Tinycast/Features/HotKeys/Service/KeyShortcut.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyAction.swift \
                           Tinycast/Features/Launcher/Model/CommandID.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/SystemActions/Model/SystemAction.swift \
                           Tinycast/Features/WindowManagement/WindowCommand.swift
run callout-test           Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/Features/HotKeys/UI/CalloutPlacement.swift
run icon-cache-test        Tinycast/Platform/Appearance.swift \
                           Tinycast/Platform/Images/IconCache.swift
run entry-icon-test        Tinycast/Platform/Appearance.swift \
                           Tinycast/Platform/Images/IconCache.swift
run ext-icon-test          Tinycast/Platform/Appearance.swift \
                           Tinycast/Platform/Images/IconCache.swift \
                           Tinycast/Features/Extensions/Service/ExtensionIconCache.swift
run system-action-test     Tinycast/Features/SystemActions/Model/SystemAction.swift
run volume-test            Tinycast/Features/SystemActions/Model/VolumeLevel.swift
run window-command-test    Tinycast/Features/WindowManagement/WindowCommand.swift \
                           Tinycast/Features/WindowManagement/WindowLayout.swift \
                           Tinycast/Features/WindowManagement/WindowActionMemory.swift
run space-gesture-test     Tinycast/Features/WindowManagement/WindowCommand.swift \
                           Tinycast/Features/WindowManagement/SpaceGesture.swift
run custom-command-test    Tinycast/Features/CustomCommands/Model/CustomCommand.swift \
                           Tinycast/Features/CustomCommands/Service/ShellCommandRunner.swift
run uninstall-test         Tinycast/Features/Uninstall/Model/UninstallTarget.swift \
                           Tinycast/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           Tinycast/Features/Uninstall/Model/UninstallRules.swift \
                           Tinycast/Features/Uninstall/Model/UninstallProtection.swift \
                           Tinycast/Features/Uninstall/Model/UninstallPlan.swift
run quicklink-test         Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkArchive.swift
run snippets-test          Tinycast/Platform/NotificationToken.swift \
                           Tinycast/Platform/HealthTicker.swift \
                           Tinycast/Platform/AccessibilityText.swift \
                           Tinycast/Features/Snippets/Model/*.swift \
                           Tinycast/Features/Snippets/Service/*.swift
run notes-test             Tinycast/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Tinycast/Features/Notes/Model/*.swift \
                           Tinycast/Features/Notes/Service/*.swift
run notes-editor-test      Tinycast/Platform/Signposts.swift \
                           Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/Features/Notes/Model/NoteDocument.swift \
                           Tinycast/Features/Notes/UI/NoteTextView.swift \
                           Tinycast/Features/Notes/UI/NoteEditorView.swift
run raycast-test           Tinycast/Features/Backup/Model/RaycastFormat.swift \
                           Tinycast/Features/Backup/Model/RaycastV1Decoder.swift \
                           Tinycast/Platform/Hex.swift \
                           Tinycast/Features/Backup/Service/RaycastV3Decoder.swift \
                           Tinycast/Features/Backup/Service/Scrypt.swift \
                           Tinycast/Platform/Compression/Zlib.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFilter.swift
run settings-backup-test   Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift
E=Tinycast/Features/Extensions
run symbols-test           $E/Service/SymbolCatalog.swift
run ext-cleanup-test       $E/Service/ExtensionCleanup.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Model/ExtensionManifest.swift
run ext-store-test         $E/Model/ExtensionRegistry.swift \
                           $E/Model/ExtensionPackageManager.swift \
                           $E/Model/ExtensionStoreResponse.swift
run ext-test               -parse-as-library \
                           $E/Model/ExtensionBootConfig.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/RenderNode.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Service/ExtensionFetcher.swift \
                           $E/Service/ExtensionNodeShims.swift \
                           $E/Service/ExtensionRuntime.swift \
                           $E/UI/ExtensionScreen.swift \
                           $L/SearchRelevance.swift \
                           Tinycast/Platform/Compression/Zlib.swift
run settings-history-test  Tinycast/Features/Settings/SettingsTab.swift \
                           Tinycast/Features/Settings/SettingsHistory.swift
run updates-test           Tinycast/Features/Updates/Model/*.swift

if [ "$emit_db" -eq 1 ]; then
    printf ']\n' >> "$DB"
    [ -f .compile ] || echo '[]' > .compile
    python3 - .compile "$DB" <<'PY'
import json, sys

compile_path, harness_path = sys.argv[1], sys.argv[2]
existing = json.load(open(compile_path))
harnesses = json.load(open(harness_path))
kept = [e for e in existing if not any("/Tests/" in f for f in e.get("files") or [])]
json.dump(kept + harnesses, open(compile_path, "w"), indent=1)
print(f"{len(harnesses)} harness entries indexed into .compile")
PY
    exit 0
fi

if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi

if [ ${#failed[@]} -gt 0 ]; then
    printf '\n%d harness(es) failed: %s\n' "${#failed[@]}" "${failed[*]}" >&2
    exit 1
fi
echo
if [ -n "$only" ]; then echo "$only passed."; else echo "All $ran harnesses passed."; fi
