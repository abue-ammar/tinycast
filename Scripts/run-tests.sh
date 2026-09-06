#!/bin/bash
# The test suite. There is no XCTest target: each harness compiles the shipped sources it guards,
# so a harness that stops compiling means a decision leaked out of a pure layer. See docs/testing.md.
#
# Never join a compile and its run with `&&`: `set -e` ignores a failure in a non-final AND-OR list
# member, which is how CI reported success over a harness that had not compiled since phase 10.

set -uo pipefail

# Absolute: the workers re-enter this script after the cd, where a relative $0 would not resolve.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/tinycast-harness"
mkdir -p "$BIN"

# `--exec` is the worker half: xargs re-enters here once per queued harness.
if [ "${1:-}" = "--exec" ]; then
    shift
    name=$1 opt=$2
    shift 2
    if ! swiftc -swift-version 6 "$opt" "$@" "Tests/$name.swift" -o "$BIN/$name" > "$BIN/$name.log" 2>&1; then
        printf '\033[31mFAIL\033[0m  %-22s did not compile\n' "$name"
        : > "$BIN/$name.failed"
        exit 0
    fi
    if ! "$BIN/$name" > "$BIN/$name.log" 2>&1; then
        printf '\033[31mFAIL\033[0m  %-22s assertion failed\n' "$name"
        : > "$BIN/$name.failed"
        exit 0
    fi
    printf '\033[32mok\033[0m    %-22s\n' "$name"
    exit 0
fi

QUEUE="$BIN/queue"
: > "$QUEUE"
rm -f "$BIN"/*.failed

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

# run [slow] [-O] <name> <source...> — queue the harness. `slow` dispatches it in the first wave.
run() {
    local opt=-Onone pri=1
    while :; do
        case "$1" in
            slow) pri=0; shift;;
            -O)   opt=-O; shift;;
            *)    break;;
        esac
    done
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

    # xargs splits the queue on whitespace, so no harness source path may contain a space.
    printf '%s %s %s %s\n' "$pri" "$name" "$opt" "$*" >> "$QUEUE"
}

L=Tinycast/Features/Launcher/Model
run slow -O fuzz-test      $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/EntryNaming.swift $L/LauncherOrder.swift
run slow -O corpus-test    $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift
run file-search-test       $L/SearchRelevance.swift \
                           Tinycast/Features/FileSearch/Model/*.swift
run file-search-session-test Tinycast/Platform/Signposts.swift \
                             $L/SearchRelevance.swift \
                             Tinycast/Features/FileSearch/Model/*.swift \
                             Tinycast/Features/FileSearch/Service/*.swift
run ranking-test           $L/SearchRelevance.swift $L/LauncherRankingStore.swift
run scopes-test            $L/SearchScopes.swift
run app-name-test          Tinycast/Platform/AppDisplayName.swift
run favorites-test         $L/FavoriteSlots.swift
run calc-test              Tinycast/Features/Calculator/Model/*.swift
run calendar-test          Tinycast/Features/Calendar/Model/*.swift
run clipboard-test         Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Tinycast/Features/Clipboard/Model/ColorValue.swift \
                           Tinycast/Features/Clipboard/Model/ColorFormat.swift \
                           Tinycast/Features/Clipboard/Model/ColorSpaces.swift
run pasteboard-test        Tinycast/Platform/PasteboardFiles.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Tinycast/Features/Clipboard/Model/ColorValue.swift \
                           Tinycast/Features/Clipboard/Model/ColorFormat.swift \
                           Tinycast/Features/Clipboard/Model/ColorSpaces.swift \
                           Tinycast/Features/Clipboard/Service/ClipboardManager.swift \
                           Tinycast/Features/Clipboard/Service/Paster.swift
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
run redaction-test         Tinycast/DesignSystem/RedactedPlaceholder.swift
run ai-instructions-test   Tinycast/Features/AI/Model/AIInstructions.swift \
                           Tinycast/Features/AI/Model/AIPreamble.swift
run hover-arming-test      Tinycast/Palette/HoverArming.swift \
                           Tinycast/Palette/PaletteState.swift \
                           Tinycast/Palette/PaletteMode.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Tinycast/Features/Clipboard/Model/ColorValue.swift \
                           Tinycast/Features/Clipboard/Model/ColorFormat.swift \
                           Tinycast/Features/Clipboard/Model/ColorSpaces.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/CustomCommands/Model/CustomCommand.swift
run palette-escape-test    Tinycast/Palette/PaletteMode.swift \
                           Tinycast/Palette/PaletteEscapeAction.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/CustomCommands/Model/CustomCommand.swift
run palette-tab-test       Tinycast/Palette/PaletteMode.swift \
                           Tinycast/Palette/PaletteTabAction.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/CustomCommands/Model/CustomCommand.swift
run fallback-test          Tinycast/Features/Launcher/Model/Fallback.swift \
                           Tinycast/Features/Launcher/Model/CommandID.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyAction.swift \
                           Tinycast/Features/QuickActions/Model/QuickAction.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/SystemActions/Model/SystemAction.swift \
                           Tinycast/Features/WindowManagement/WindowCommand.swift
run hotkey-test            Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Tinycast/Features/HotKeys/Model/DoubleTapDetector.swift \
                           Tinycast/Features/HotKeys/Model/HyperKey.swift \
                           Tinycast/Platform/ASCIIKeyboardLayout.swift \
                           Tinycast/Features/HotKeys/Service/KeyShortcut.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyAction.swift \
                           Tinycast/Features/QuickActions/Model/QuickAction.swift \
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
                           Tinycast/Platform/Images/IconCache.swift \
                           Tinycast/Platform/Images/FileIconStamp.swift
run ext-icon-test          Tinycast/Platform/Appearance.swift \
                           Tinycast/Platform/Images/IconCache.swift \
                           Tinycast/Platform/Compression/Zlib.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/Features/Extensions/Model/ExtensionBootConfig.swift \
                           Tinycast/Features/Extensions/Model/ExtensionManifest.swift \
                           Tinycast/Features/Extensions/Model/RenderNode.swift \
                           Tinycast/Features/Extensions/Service/ExtensionCatalog.swift \
                           Tinycast/Features/Extensions/Service/ExtensionFetcher.swift \
                           Tinycast/Features/Extensions/Service/ExtensionNodeShims.swift \
                           Tinycast/Features/Extensions/Service/ExtensionOAuthKeychain.swift \
                           Tinycast/Features/Extensions/Service/ExtensionOAuthSession.swift \
                           Tinycast/Features/Extensions/Service/ExtensionRuntime.swift \
                           Tinycast/Features/Extensions/Service/ExtensionIconCache.swift \
                           Tinycast/Features/Extensions/UI/ExtensionAnimatedImage.swift \
                           Tinycast/Features/Extensions/UI/ExtensionImage.swift
run system-action-test     Tinycast/Features/SystemActions/Model/SystemAction.swift
run volume-test            Tinycast/Features/SystemActions/Model/VolumeLevel.swift
run window-command-test    Tinycast/Features/WindowManagement/WindowCommand.swift \
                           Tinycast/Features/WindowManagement/WindowLayout.swift \
                           Tinycast/Features/WindowManagement/WindowActionMemory.swift
run space-gesture-test     Tinycast/Features/WindowManagement/WindowCommand.swift \
                           Tinycast/Features/WindowManagement/SpaceGesture.swift
run custom-command-test    Tinycast/Platform/PseudoTerminal.swift \
                           Tinycast/Features/CustomCommands/Model/CustomCommand.swift \
                           Tinycast/Features/CustomCommands/Service/ShellCommandRunner.swift \
                           Tinycast/Features/CustomCommands/Service/CustomCommandArgumentSession.swift
run uninstall-test         Tinycast/Features/Uninstall/Model/UninstallTarget.swift \
                           Tinycast/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           Tinycast/Features/Uninstall/Model/UninstallRules.swift \
                           Tinycast/Features/Uninstall/Model/UninstallProtection.swift \
                           Tinycast/Features/Uninstall/Model/UninstallPlan.swift
run quicklink-test         Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkArchive.swift
run slow snippets-test     Tinycast/Platform/NotificationToken.swift \
                           Tinycast/Platform/HealthTicker.swift \
                           Tinycast/Platform/AccessibilityText.swift \
                           Tinycast/Features/Snippets/Model/*.swift \
                           Tinycast/Features/Snippets/Service/*.swift \
                           Tinycast/Features/TextInjection/Service/*.swift
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
run slow -O raycast-test   Tinycast/Features/Backup/Model/RaycastImportError.swift \
                           Tinycast/Features/Backup/Service/RaycastDecoder.swift \
                           Tinycast/Features/Backup/Service/Scrypt.swift \
                           Tinycast/Platform/Compression/Zlib.swift
run settings-backup-test   Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift
run backup-archive-test    Tinycast/Platform/AppPaths.swift \
                           Tinycast/Features/Backup/Model/BackupArchive.swift \
                           Tinycast/Features/Backup/Model/BackupBundle.swift \
                           Tinycast/Features/Backup/Model/BackupCategory.swift \
                           Tinycast/Features/Backup/Model/BackupClipboardItem.swift \
                           Tinycast/Features/Backup/Model/BackupManifest.swift \
                           Tinycast/Features/Backup/Service/BackupStaging.swift
E=Tinycast/Features/Extensions
run symbols-test           $E/Service/SymbolCatalog.swift
run ext-cleanup-test       $E/Service/ExtensionCleanup.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Model/ExtensionManifest.swift
run ext-store-test         $E/Model/ExtensionRegistry.swift \
                           $E/Model/ExtensionPackageManager.swift \
                           $E/Model/ExtensionStoreResponse.swift
run slow ext-test          -parse-as-library \
                           Tinycast/Platform/Appearance.swift \
                           Tinycast/Platform/Images/IconCache.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           $E/Model/ExtensionBootConfig.swift \
                           $E/Model/ExtensionGridLayout.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/RenderNode.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Service/ExtensionFetcher.swift \
                           $E/Service/ExtensionIconCache.swift \
                           $E/Service/ExtensionNodeShims.swift \
                           $E/Service/ExtensionOAuthKeychain.swift \
                           $E/Service/ExtensionOAuthSession.swift \
                           $E/Service/ExtensionRuntime.swift \
                           $E/UI/ExtensionAnimatedImage.swift \
                           $E/UI/ExtensionImage.swift \
                           $E/UI/ExtensionScreen.swift \
                           $L/SearchRelevance.swift \
                           Tinycast/Platform/Compression/Zlib.swift
run settings-history-test  Tinycast/Features/Settings/SettingsTab.swift \
                           Tinycast/Features/Settings/SettingsHistory.swift \
                           Tinycast/Features/Settings/SettingsAnchor.swift \
                           Tinycast/Features/Settings/SettingsNavigationState.swift \
                           Tinycast/Features/Settings/SettingsSearchCatalog.swift \
                           $L/SearchRelevance.swift
run updates-test           Tinycast/Features/Updates/Model/*.swift
run support-test           Tinycast/Features/Support/Model/*.swift
run ai-provider-test       Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/AI/Model/*.swift \
                           Tinycast/Features/AI/Settings/AISettingsStore.swift
run ai-chat-test           Tinycast/Features/AI/Model/AIRequest.swift \
                           Tinycast/Features/AI/Model/AIAttachmentPolicy.swift \
                           Tinycast/Features/AI/Model/AIRetention.swift \
                           Tinycast/Features/AI/Model/AITool.swift \
                           Tinycast/Features/AI/Model/JSONValue.swift \
                           Tinycast/Features/AI/Model/ChatMessage.swift \
                           Tinycast/Features/AI/Model/ChatSession.swift \
                           Tinycast/Features/AI/Model/MarkdownBlock.swift \
                           Tinycast/Features/AI/Service/AIProvider.swift \
                           Tinycast/Features/AI/Service/ChatHistoryStore.swift \
                           Tinycast/Features/AI/Service/AIToolLoopProvider.swift \
                           Tinycast/Features/AI/UI/AIChatState.swift
run mcp-test               Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/AI/Model/AIConnection.swift \
                           Tinycast/Features/AI/Model/AppleIntelligence.swift \
                           Tinycast/Features/AI/Model/AITool.swift \
                           Tinycast/Features/AI/Model/JSONValue.swift \
                           Tinycast/Features/MCP/Model/*.swift \
                           Tinycast/Features/MCP/Settings/MCPSettingsStore.swift
run quick-action-test      Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/AI/Model/AIConnection.swift \
                           Tinycast/Features/AI/Model/AppleIntelligence.swift \
                           Tinycast/Features/AI/Model/ChatGPTSubscription.swift \
                           Tinycast/Features/AI/Model/InstalledAI.swift \
                           Tinycast/Features/QuickActions/Model/*.swift \
                           Tinycast/Features/QuickActions/Settings/QuickActionSettingsStore.swift
run apple-intelligence-test Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/AI/Model/*.swift \
                           Tinycast/Features/AI/Service/AIProvider.swift \
                           Tinycast/Features/AI/Service/AppleIntelligenceProvider.swift
run slow mcp-stdio-test    Tinycast/Platform/ExecutableLocator.swift \
                           Tinycast/Platform/KeychainSecretStore.swift \
                           Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/AI/Model/AIConnection.swift \
                           Tinycast/Features/AI/Model/AppleIntelligence.swift \
                           Tinycast/Features/AI/Model/AITool.swift \
                           Tinycast/Features/AI/Model/AIStreamDecoder.swift \
                           Tinycast/Features/AI/Model/AIRequest.swift \
                           Tinycast/Features/AI/Model/JSONValue.swift \
                           Tinycast/Features/MCP/Model/*.swift \
                           Tinycast/Features/MCP/Service/*.swift
run slow codex-turn-test   Tinycast/Platform/AppPaths.swift \
                           Tinycast/Features/AI/Model/*.swift \
                           Tinycast/Features/AI/Service/AIProvider.swift \
                           Tinycast/Features/AI/Service/ChatGPTSubscriptionManager.swift \
                           Tinycast/Features/AI/Service/CodexAppServerClient.swift \
                           Tinycast/Platform/ExecutableLocator.swift \
                           Tinycast/Features/AI/Service/CodexTurnRunner.swift
run installed-ai-test     Tinycast/Features/AI/Model/*.swift \
                          Tinycast/Features/AI/Service/AIProvider.swift \
                          Tinycast/Platform/ExecutableLocator.swift \
                          Tinycast/Features/AI/Service/InstalledCLIProvider.swift

if [ "$emit_db" -eq 1 ]; then
    printf ']\n' >> "$DB"
    [ -f .compile ] || echo '[]' > .compile
    node -e '
const fs = require("node:fs");
const [comp, db] = process.argv.slice(1);
const existing = JSON.parse(fs.readFileSync(comp, "utf8"));
const harnesses = JSON.parse(fs.readFileSync(db, "utf8"));
const kept = existing.filter((e) => !(e.files || []).some((f) => f.includes("/Tests/")));
fs.writeFileSync(comp, JSON.stringify([...kept, ...harnesses], null, 1));
console.log(harnesses.length + " harness entries indexed into .compile");
' .compile "$DB"
    exit 0
fi

if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi

# `sort -s` is stable, so the slow harnesses lead and everything else keeps its declaration order.
JOBS="${TINYCAST_TEST_JOBS:-$(sysctl -n hw.ncpu)}"
# Without this the suite reports "all passed" whenever dispatch itself dies and no harness ran.
if ! sort -s -k1,1n "$QUEUE" | cut -d' ' -f2- | xargs -P "$JOBS" -L1 "$SELF" --exec; then
    echo "harness dispatch failed; no result below can be trusted" >&2
    exit 1
fi

# A compiler diagnostic is far longer than PIPE_BUF, so the workers log it and it is replayed here.
while read -r _ name _; do
    if [ -f "$BIN/$name.failed" ]; then failed+=("$name"); fi
done < "$QUEUE"

if [ ${#failed[@]} -gt 0 ]; then
    for name in "${failed[@]}"; do
        printf '\n\033[31m--- %s ---\033[0m\n' "$name"
        cat "$BIN/$name.log"
    done
    printf '\n%d harness(es) failed: %s\n' "${#failed[@]}" "${failed[*]}" >&2
    exit 1
fi
echo
if [ -n "$only" ]; then echo "$only passed."; else echo "All $ran harnesses passed."; fi
