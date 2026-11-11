#!/bin/bash
# The test suite: each harness compiles the shipped sources it guards. See docs/testing.md.

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
    : > "$BIN/$name.running"
    trap 'rm -f "$BIN/$name.running" "$BIN/$name.time"' EXIT
    fail() {
        printf '\033[31mFAIL\033[0m  %-25s %s\n' "$name" "$1"
        : > "$BIN/$name.failed"
        exit 0
    }
    TIMEFORMAT=%1R
    if ! compiled=$( { time swiftc -swift-version 6 "$opt" "$@" "Tests/$name.swift" -o "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2>&1 ); then
        fail "did not compile"
    fi
    { time "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2> "$BIN/$name.time" &
    pid=$!
    # macOS ships no `timeout`, so the worker polls; a wedged harness must fail, not stall.
    ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge $((TINYCAST_TEST_TIMEOUT * 5)) ]; then
            { pkill -KILL -P "$pid"; kill -KILL "$pid"; wait "$pid"; } 2>/dev/null
            printf '\n[run-tests] killed after %ss without finishing\n' "$TINYCAST_TEST_TIMEOUT" >> "$BIN/$name.log"
            fail "timed out after ${TINYCAST_TEST_TIMEOUT}s"
        fi
        ticks=$((ticks + 1))
        sleep 0.2
    done
    wait "$pid"
    status=$?
    took=$(< "$BIN/$name.time")
    if [ "$status" -gt 128 ]; then fail "crashed (signal $((status - 128))) after ${took}s"; fi
    if [ "$status" -ne 0 ]; then fail "assertion failed after ${took}s"; fi
    printf '\033[32mok\033[0m    %-25s %5ss  \033[2m(compile %ss)\033[0m\n' "$name" "$took" "$compiled"
    exit 0
fi

failed=()
ran=0
only="${1:-}"

# `--index` feeds harness compile commands to .compile, as xcodebuild never compiles Tests/.
emit_db=0
DB="${TMPDIR:-/tmp}/tinycast-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

QUEUE="$BIN/queue"
# `--index` queues nothing, so it must never reset the state of a suite already running.
if [ "$emit_db" -eq 0 ]; then
    # Queue, logs and verdicts are shared by path, so a second suite in this $TMPDIR waits its turn.
    if [ -z "${TINYCAST_SUITE_LOCKED:-}" ]; then
        export TINYCAST_SUITE_LOCKED=1
        lockf -k -t 0 "$BIN/suite.lock" true 2>/dev/null || echo "Waiting for the suite already running…" >&2
        exec lockf -k "$BIN/suite.lock" "$SELF" "$@"
    fi
    : > "$QUEUE"
    rm -f "$BIN"/*.failed "$BIN"/*.running
fi

# `slow` dispatches in the first wave; `index` only claims editor flags for a hand-run harness.
run() {
    local opt=-Onone pri=1 index_only=0
    while :; do
        case "$1" in
            slow)  pri=0; shift;;
            -O)    opt=-O; shift;;
            index) index_only=1; shift;;
            *)     break;;
        esac
    done
    local name=$1
    shift
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    if [ "$index_only" -eq 1 ] && [ "$emit_db" -eq 0 ]; then return 0; fi
    ran=$((ran + 1))

    # Absolute paths: sourcekit-lsp ignores `directory` for relative arguments and indexes nothing.
    if [ "$emit_db" -eq 1 ]; then
        local sources=()
        for source in "$@" "Tests/$name.swift"; do sources+=("$PWD/$source"); done
        [ "$ran" -gt 1 ] && printf ',' >> "$DB"
        printf '{"directory":"%s","command":"swiftc -swift-version 6 -sdk %s' \
            "$PWD" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        # Only `Tests/` files: `.compile` is last-wins, so a shipped source keeps the app's command.
        local claimed=""
        for source in "${sources[@]}"; do
            case "$source" in *"/Tests/"*) claimed="$claimed${claimed:+,}\"$source\"";; esac
        done
        printf '","files":[%s]}' "$claimed" >> "$DB"
        return 0
    fi

    # xargs splits the queue on whitespace, so no harness source path may contain a space.
    printf '%s %s %s %s\n' "$pri" "$name" "$opt" "$*" >> "$QUEUE"
}

L=Tinycast/Features/Launcher/Model
run slow -O FuzzTests      $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift
FS=Tinycast/Features/FileSearch
FILE_INDEX="$FS/Service/FileIndex.swift $FS/Service/FileIndexSnapshot.swift $FS/Service/FileIndexCrawler.swift"
run FileSearchTests        $FS/Model/*.swift
run FileIndexTests         $FS/Model/*.swift $FILE_INDEX
run FileSearchSessionTests $FS/Model/*.swift $FS/Service/FileSearchSession.swift $FILE_INDEX
run MenuSearchTests        $L/SearchRelevance.swift \
                           Tinycast/Features/MenuSearch/Model/*.swift \
                           Tinycast/Features/MenuSearch/Service/*.swift
run WindowSwitchTests      $L/SearchRelevance.swift \
                           Tinycast/Features/WindowSwitcher/Model/*.swift
run index FileSearchPerformanceTests $FS/Model/*.swift $FILE_INDEX
run RankingTests           $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/LauncherRankingStore.swift
run ScopesTests            $L/SearchScopes.swift
run AppNameTests           Tinycast/Platform/AppDisplayName.swift \
                           Tinycast/Platform/BundleLocalization.swift \
                           $L/SearchRelevance.swift
run FavoritesTests         $L/FavoriteSlots.swift
run AppInstallationTests   $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift $L/SearchScopes.swift \
                           Tinycast/Features/Launcher/Service/AppIndex.swift \
                           Tinycast/Features/Launcher/Service/AppLauncher.swift \
                           Tinycast/Features/Launcher/Service/RunningAppsMonitor.swift \
                           Tinycast/Features/Launcher/Service/FavoritesStore.swift \
                           $FS/Model/FileSearchResult.swift \
                           Tinycast/Features/Launcher/Service/AliasStore.swift \
                           Tinycast/Features/Launcher/Service/VisibilityStore.swift \
                           Tinycast/Features/Launcher/Service/BundleNameCache.swift \
                           Tinycast/Platform/AppDisplayName.swift Tinycast/Platform/BundleLocalization.swift \
                           Tinycast/Platform/SystemLanguages.swift \
                           Tinycast/Platform/Images/FileIconStamp.swift Tinycast/Platform/Memo.swift \
                           Tinycast/Platform/Signposts.swift Tinycast/Platform/NotificationToken.swift \
                           Tinycast/Platform/LocalizedResource.swift
run LauncherFileTests      $L/LauncherFileFormat.swift \
                           Tinycast/Features/Settings/Model/SettingsFileJSON.swift
run LauncherSettingsFileTests \
                           $L/LauncherFileFormat.swift $L/CommandID.swift $L/CommandCatalog.swift \
                           Tinycast/Features/Launcher/Service/LauncherSettingsFile.swift \
                           Tinycast/Features/Launcher/Service/AliasStore.swift \
                           Tinycast/Features/Launcher/Service/VisibilityStore.swift \
                           Tinycast/Features/Settings/SettingsTab.swift \
                           Tinycast/Features/Settings/Model/*.swift \
                           Tinycast/Features/HotKeys/Service/HotKeySettingsFile.swift \
                           Tinycast/Features/HotKeys/Service/KeyShortcut.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyAction.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Tinycast/Features/HotKeys/Model/HotKeySpelling.swift \
                           Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Tinycast/Features/HotKeys/Model/ModifierKey.swift \
                           Tinycast/Features/HotKeys/Model/HyperKey.swift \
                           Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Tinycast/Platform/ASCIIKeyboardLayout.swift \
                           Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/SystemActions/Model/SystemAction.swift \
                           Tinycast/Features/WindowManagement/Model/WindowCommand.swift \
                           Tinycast/Features/Snippets/Model/Snippet.swift \
                           Tinycast/Platform/LocalizedResource.swift
run AppleShortcutTests     Tinycast/Features/AppleShortcuts/Model/*.swift
run CalcTests              Tinycast/Features/Calculator/Model/*.swift
run index CalcPerformanceTests Tinycast/Features/Calculator/Model/*.swift
run CalendarTests          Tinycast/Features/Calendar/Model/*.swift \
                           Tinycast/Features/Calendar/UI/EventEditorSession.swift
run ClipboardTests         Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
                           Tinycast/Platform/Images/ImageDerivative.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Tinycast/Features/Clipboard/Model/ColorValue.swift \
                           Tinycast/Features/Clipboard/Model/ColorFormat.swift \
                           Tinycast/Features/Clipboard/Model/ColorSpaces.swift
run ClipboardCoordinatorTests Tinycast/Features/Clipboard/UI/ClipboardCoordinator.swift \
                           Tinycast/Features/Clipboard/Model/*.swift \
                           Tinycast/Platform/Images/ImageDerivative.swift \
                           Tinycast/Palette/PaletteState.swift Tinycast/Palette/PaletteMode.swift \
                           Tinycast/Palette/HoverArming.swift \
                           Tinycast/Features/Emoji/Model/EmojiCatalog.swift \
                           Tinycast/Features/FileSearch/Model/FileSearchFilter.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/CustomCommands/Model/CustomCommand.swift
run ClipboardThumbnailTests Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
                           Tinycast/Platform/Images/ImageDerivative.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Tinycast/Features/Clipboard/Model/ColorValue.swift \
                           Tinycast/Features/Clipboard/Model/ColorFormat.swift \
                           Tinycast/Features/Clipboard/Model/ColorSpaces.swift \
                           Tinycast/Platform/ProcessExit.swift \
                           Tinycast/Platform/Images/ImageThumbnail.swift \
                           Tinycast/Platform/Images/ThumbnailCache.swift
# `Q` is the URL detector a drag payload builds its link with, rather than a second one.
Q=Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift
run ClipboardSearchTests   Tinycast/Features/Clipboard/Model/*.swift Tinycast/Platform/Images/ImageDerivative.swift $Q
run PasteSequenceTests     Tinycast/Features/Clipboard/Model/*.swift Tinycast/Platform/Images/ImageDerivative.swift $Q
run ClipboardTextTests     Tinycast/Features/Clipboard/Model/*.swift Tinycast/Platform/Images/ImageDerivative.swift $Q \
                           Tinycast/Features/Clipboard/Service/ClipboardTextExtractor.swift \
                           Tinycast/Features/Clipboard/Service/ClipboardTextIndexer.swift \
                           Tinycast/Features/Clipboard/Service/ClipboardTextWorker.swift \
                           Tinycast/Platform/ProcessExit.swift
run PasteboardTests        Tinycast/Platform/PasteboardFiles.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
                           Tinycast/Platform/Images/ImageDerivative.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Tinycast/Features/Clipboard/Model/ColorValue.swift \
                           Tinycast/Features/Clipboard/Model/ColorFormat.swift \
                           Tinycast/Features/Clipboard/Model/ColorSpaces.swift \
                           Tinycast/Features/Clipboard/Service/ClipboardManager.swift \
                           Tinycast/Features/Clipboard/Service/Paster.swift
run index ClipboardFilePerformanceTests \
                           Tinycast/Platform/PasteboardFiles.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
                           Tinycast/Platform/Images/ImageDerivative.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Tinycast/Features/Clipboard/Model/ColorValue.swift \
                           Tinycast/Features/Clipboard/Model/ColorFormat.swift \
                           Tinycast/Features/Clipboard/Model/ColorSpaces.swift \
                           Tinycast/Features/Clipboard/Service/ClipboardManager.swift
run index ClipboardThumbnailPerformanceTests \
                           Tinycast/Platform/ProcessExit.swift \
                           Tinycast/Platform/Images/ImageThumbnail.swift \
                           Tinycast/Platform/Images/ImageDerivative.swift \
                           Tinycast/Platform/Images/ThumbnailCache.swift
run EmojiTests             Tinycast/Features/Emoji/Model/EmojiCatalog.swift \
                           Tinycast/Features/Emoji/Model/EmojiGridGeometry.swift \
                           Tinycast/Features/Emoji/Model/EmojiData.generated.swift
run EmojiSearchTests       Tinycast/Features/Emoji/Model/EmojiCatalog.swift \
                           Tinycast/Features/Emoji/Model/EmojiData.generated.swift \
                           Tinycast/Features/Emoji/Service/EmojiIndex.swift \
                           Tinycast/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Tinycast/Features/Emoji/Service/PinnedEmojiStore.swift \
                           Tinycast/Features/Launcher/Model/SearchRelevance.swift \
                           Tinycast/Platform/AppPaths.swift Tinycast/Platform/Memo.swift
run index EmojiSearchPerformanceTests \
                           Tinycast/Features/Emoji/Model/EmojiCatalog.swift \
                           Tinycast/Features/Emoji/Model/EmojiData.generated.swift \
                           Tinycast/Features/Emoji/Service/EmojiIndex.swift \
                           Tinycast/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Tinycast/Features/Launcher/Model/SearchRelevance.swift \
                           Tinycast/Platform/AppPaths.swift Tinycast/Platform/Memo.swift
run PaletteSelectionTests  Tinycast/Features/PaletteRowIndex.swift \
                           Tinycast/Features/Emoji/Model/EmojiGridGeometry.swift
run AppearanceTests        Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/DesignSystem/InterfaceMetrics.swift \
                           Tinycast/Features/Settings/AppAppearance.swift
run LanguageTests          Tinycast/Features/Settings/AppLanguage.swift
run LocalizedResourceTests Tinycast/Platform/LocalizedResource.swift
run RelaunchTests          Tinycast/App/AppDelegate.swift Tinycast/Platform/RelaunchRunner.swift
run InterfaceSizeTests     Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/DesignSystem/InterfaceMetrics.swift \
                           Tinycast/Features/Settings/InterfaceSize.swift \
                           Tinycast/Features/Extensions/Model/ExtensionFormMetrics.swift
run PalettePlacementTests  Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/DesignSystem/InterfaceMetrics.swift \
                           Tinycast/Features/Settings/InterfaceSize.swift \
                           Tinycast/Palette/PalettePlacement.swift
run PaletteMenuClickTests  Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/Platform/WindowLevel.swift \
                           Tinycast/Platform/NotificationToken.swift \
                           Tinycast/DesignSystem/Interaction/KeyboardFocus.swift \
                           Tinycast/DesignSystem/Interaction/Motion.swift \
                           Tinycast/DesignSystem/Interaction/AnimatedPanel.swift \
                           Tinycast/Palette/PalettePanel.swift
run FormInputTests         Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/DesignSystem/InterfaceMetrics.swift \
                           Tinycast/DesignSystem/FormTextInput.swift \
                           Tinycast/DesignSystem/FormTextArea.swift
run ScrollRevealTests      Tinycast/DesignSystem/Scrolling/SelectionReveal.swift
run RedactionTests         Tinycast/DesignSystem/RedactedPlaceholder.swift
run KeyboardFocusTests     Tinycast/DesignSystem/Interaction/KeyboardFocus.swift
run CommandEscapeTapTests  Tinycast/Palette/CommandEscapeTap.swift
run PaletteEscapeTests     Tinycast/Palette/PaletteMode.swift \
                           Tinycast/Palette/PaletteEscapeAction.swift \
                           Tinycast/Palette/CommandEscapeTap.swift \
                           Tinycast/Features/Settings/EscapeKeyBehavior.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/CustomCommands/Model/CustomCommand.swift
run PaletteNavigationTests Tinycast/Palette/PaletteState.swift \
                           Tinycast/Palette/PaletteMode.swift \
                           Tinycast/Palette/HoverArming.swift \
                           Tinycast/Features/Emoji/Model/EmojiCatalog.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
                           Tinycast/Platform/Images/ImageDerivative.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Tinycast/Features/FileSearch/Model/FileSearchFilter.swift \
                           Tinycast/Features/Clipboard/Model/ColorValue.swift \
                           Tinycast/Features/Clipboard/Model/ColorFormat.swift \
                           Tinycast/Features/Clipboard/Model/ColorSpaces.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/CustomCommands/Model/CustomCommand.swift
run PaletteFilterTests     Tinycast/Palette/PaletteMode.swift \
                           Tinycast/Palette/PaletteFilterAction.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/CustomCommands/Model/CustomCommand.swift
run ActionMenuSearchTests  Tinycast/Palette/ActionMenuSearchQuery.swift \
                            Tinycast/Features/Launcher/Model/SearchRelevance.swift
run PaletteShortcutTests   Tinycast/Palette/PaletteShortcut.swift
run ASCIILayoutTests       Tinycast/Platform/ASCIIKeyboardLayout.swift
run PaletteTabTests        Tinycast/Palette/PaletteMode.swift \
                           Tinycast/Palette/PaletteTabAction.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/CustomCommands/Model/CustomCommand.swift
run CompactBarTests        Tinycast/Features/Launcher/Model/CompactBarSelection.swift \
                           Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/Settings/Model/*.swift \
                           Tinycast/Features/Launcher/Model/CommandID.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyAction.swift \
                           Tinycast/Features/QuickActions/Model/QuickAction.swift \
                           Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Tinycast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/SystemActions/Model/SystemAction.swift \
                           Tinycast/Features/WindowManagement/Model/WindowCommand.swift \
                           Tinycast/Features/Snippets/Model/Snippet.swift \
                           Tinycast/Platform/LocalizedResource.swift
run FallbackTests          Tinycast/Features/Launcher/Model/Fallback.swift \
                           Tinycast/Features/Launcher/Model/CommandID.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyAction.swift \
                           Tinycast/Features/QuickActions/Model/QuickAction.swift \
                           Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Tinycast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/SystemActions/Model/SystemAction.swift \
                           Tinycast/Features/WindowManagement/Model/WindowCommand.swift \
                           Tinycast/Features/Snippets/Model/Snippet.swift \
                           Tinycast/Platform/LocalizedResource.swift
run DictionaryTests        Tinycast/Features/Dictionary/Model/DictionaryEntry.swift \
                           Tinycast/Features/Dictionary/Model/DictionaryMarkup.swift
run DictationTests         Tinycast/Features/Dictation/Model/DictationModel.swift Tinycast/Features/Dictation/Model/DictationIdleRelease.swift Tinycast/Features/Dictation/Model/DictationLanguage.swift Tinycast/Features/Dictation/Model/DictationTextFormatter.swift
run DictationCueTests      Tinycast/Features/Dictation/Service/DictationCueRunner.swift
run DictationFieldTests    Tinycast/Features/Dictation/Model/DictationModel.swift \
                           Tinycast/Features/Dictation/Model/DictationAudioChunks.swift \
                           Tinycast/Features/Dictation/Model/DictationMode.swift \
                           Tinycast/Features/Dictation/Model/DictationDestination.swift \
                           Tinycast/Features/Dictation/Model/DictationTextFormatter.swift \
                           Tinycast/Features/Dictation/Service/DictationCoordinator.swift \
                           Tinycast/Features/Dictation/Service/DictationInsertionContext.swift \
                           Tinycast/Features/AI/UI/ChatComposerTextView.swift \
                           Tinycast/Features/TextInjection/Service/*.swift \
                           Tinycast/Features/Snippets/Model/*.swift \
                           Tinycast/Platform/AccessibilityText.swift \
                           Tinycast/Platform/PasteboardFiles.swift \
                           Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
run DictationVolumeTests   Tinycast/Features/Dictation/Model/DictationVolumeSnapshot.swift \
                           Tinycast/Features/Dictation/Service/DictationAudioDucker.swift \
                           Tinycast/Platform/AppPaths.swift
run index -O DictationPerformanceTests Tinycast/Platform/ProcessExit.swift \
                           Tinycast/Features/Dictation/Model/DictationModel.swift \
                           Tinycast/Features/Dictation/Service/DictationWire.swift
run DictationInferenceTests Tinycast/Features/Dictation/Model/DictationAudioChunks.swift \
    Tinycast/Features/Dictation/Service/DictationSpectrum.swift \
    Tinycast/Features/Dictation/Helper/DictationTensor.swift Tinycast/Features/Dictation/Helper/DictationTokenizer.swift \
    Tinycast/Features/Dictation/Helper/DictationMel.swift
run DictationWorkerTests   Tinycast/Features/Dictation/Model/DictationModel.swift \
                           Tinycast/Features/Dictation/Model/DictationIdleRelease.swift \
                           Tinycast/Features/Dictation/Service/DictationWire.swift \
                           Tinycast/Features/Dictation/Service/DictationWorker.swift \
                           Tinycast/Features/Dictation/Service/DictationModelStore.swift \
                           Tinycast/Features/Dictation/Service/DictationModelDownloader.swift \
                           Tinycast/Platform/ProcessExit.swift Tinycast/Platform/AppPaths.swift
run HotKeyTests            Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Tinycast/Features/HotKeys/Model/ModifierKey.swift \
                           Tinycast/Features/HotKeys/Model/ModifierKeyDetector.swift \
                           Tinycast/Features/HotKeys/Model/DoubleTapDetector.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Tinycast/Features/HotKeys/Model/HotKeySpelling.swift \
                           Tinycast/Features/HotKeys/Model/HyperKey.swift \
                           Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Tinycast/Platform/ASCIIKeyboardLayout.swift \
                           Tinycast/Features/HotKeys/Service/KeyShortcut.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyAction.swift \
                           Tinycast/Features/QuickActions/Model/QuickAction.swift \
                           Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Tinycast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Tinycast/Features/Launcher/Model/CommandID.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/SystemActions/Model/SystemAction.swift \
                           Tinycast/Features/WindowManagement/Model/WindowCommand.swift \
                           Tinycast/Features/Snippets/Model/Snippet.swift \
                           Tinycast/Platform/LocalizedResource.swift
run CalloutTests           Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/DesignSystem/InterfaceMetrics.swift \
                           Tinycast/Features/HotKeys/UI/CalloutPlacement.swift
run IconCacheTests         Tinycast/Platform/Appearance.swift \
                           Tinycast/Platform/Images/IconCache.swift
run EntryIconTests         Tinycast/Platform/Appearance.swift \
                           Tinycast/Platform/Images/IconCache.swift \
                           Tinycast/Platform/Images/FileIconStamp.swift
run ExtensionIconTests     Tinycast/Platform/Appearance.swift \
                           Tinycast/Platform/AppDisplayName.swift \
                           Tinycast/Platform/Images/IconCache.swift \
                           Tinycast/Platform/Compression/Zlib.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/DesignSystem/InterfaceMetrics.swift \
                           Tinycast/Features/Extensions/Model/ExtensionBootConfig.swift \
                           Tinycast/Features/Extensions/Model/ExtensionLaunchType.swift \
                           Tinycast/Features/Extensions/Model/ExtensionManifest.swift \
                           Tinycast/Features/Extensions/Model/ExtensionRefreshPolicy.swift \
                           Tinycast/Features/Extensions/Model/ExtensionRefreshState.swift \
                           Tinycast/Features/Extensions/Model/RenderNode.swift \
                           Tinycast/Features/Extensions/Service/ExtensionCatalog.swift \
                           Tinycast/Features/Extensions/Service/ExtensionFetcher.swift \
                           Tinycast/Platform/ProcessExit.swift \
                           Tinycast/Features/Extensions/Service/ExtensionNodeShims.swift \
                           Tinycast/Features/Extensions/Service/ExtensionRuntime.swift \
                           Tinycast/Features/Extensions/Service/ExtensionIconCache.swift \
                           Tinycast/Features/Extensions/UI/ExtensionAnimatedImage.swift \
                           Tinycast/Features/Extensions/UI/ExtensionImage.swift \
                           Tinycast/Features/Clipboard/Model/ColorValue.swift \
                           Tinycast/Features/Clipboard/Model/ColorSpaces.swift
run SystemActionTests      Tinycast/Features/SystemActions/Model/SystemAction.swift \
                           Tinycast/Platform/LocalizedResource.swift
run MicrophoneMuteTests    Tinycast/Features/SystemActions/Service/SystemActionFailure.swift \
                           Tinycast/Features/SystemActions/Service/SystemActionRunner+Microphone.swift
run VolumeTests            Tinycast/Features/SystemActions/Model/VolumeLevel.swift
run WindowCommandTests     Tinycast/Features/WindowManagement/Model/WindowCommand.swift \
                           Tinycast/Features/WindowManagement/Model/WindowCycle.swift \
                           Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Tinycast/Features/WindowManagement/Model/WindowActionMemory.swift \
                           Tinycast/Platform/LocalizedResource.swift
run WindowPresetTests      Tinycast/Features/WindowManagement/Model/WindowCommand.swift \
                           Tinycast/Features/WindowManagement/Model/WindowShortcutPreset.swift \
                           Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Tinycast/Features/HotKeys/Model/ModifierKey.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Tinycast/Features/HotKeys/Model/HyperKey.swift \
                           Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Tinycast/Platform/ASCIIKeyboardLayout.swift \
                           Tinycast/Features/HotKeys/Service/KeyShortcut.swift \
                           Tinycast/Platform/LocalizedResource.swift
run SpaceGestureTests      Tinycast/Features/WindowManagement/Model/WindowCommand.swift \
                           Tinycast/Features/WindowManagement/Model/SpaceGesture.swift \
                           Tinycast/Platform/LocalizedResource.swift
run WindowLayoutTests      Tinycast/Features/WindowManagement/Model/WindowCommand.swift \
                           Tinycast/Features/WindowManagement/Model/WindowCycle.swift \
                           Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayout.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutStore.swift \
                           Tinycast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Tinycast/Features/WindowManagement/Model/CustomWindowSizeStore.swift \
                           Tinycast/Platform/LocalizedResource.swift
run DeepLinkTests          Tinycast/Features/DeepLinks/Model/DeepLink.swift \
                           Tinycast/Features/DeepLinks/Model/DeepLinkInput.swift \
                           Tinycast/Features/DeepLinks/Model/DeepLinkConsentPolicy.swift \
                           Tinycast/Features/DeepLinks/Model/DeepLinkSource.swift \
                           Tinycast/Features/DeepLinks/Model/CustomWindowSize+DeepLink.swift \
                           Tinycast/Features/Settings/SettingsTab.swift \
                           Tinycast/Features/Launcher/Model/CommandID.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyAction.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift \
                           Tinycast/Features/QuickActions/Model/QuickAction.swift \
                           Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Tinycast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/SystemActions/Model/SystemAction.swift \
                           Tinycast/Features/CustomCommands/Model/CustomCommand.swift \
                           Tinycast/Features/AppleShortcuts/Model/AppleShortcut.swift \
                           Tinycast/Features/Snippets/Model/Snippet.swift \
                           Tinycast/Features/WindowManagement/Model/WindowCommand.swift \
                           Tinycast/Features/WindowManagement/Model/WindowCycle.swift \
                           Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayout.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Tinycast/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Tinycast/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Tinycast/Features/WindowManagement/Model/RoomGrid.swift \
                           Tinycast/Features/WindowManagement/Model/RoomWindow.swift \
                           Tinycast/Features/WindowManagement/Model/Room.swift \
                           Tinycast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Tinycast/Platform/LocalizedResource.swift
run WindowRoomTests        Tinycast/Features/WindowManagement/Model/WindowCommand.swift \
                           Tinycast/Features/WindowManagement/Model/WindowCycle.swift \
                           Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayout.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           Tinycast/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Tinycast/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Tinycast/Features/WindowManagement/Model/RoomGrid.swift \
                           Tinycast/Features/WindowManagement/Model/RoomWindow.swift \
                           Tinycast/Features/WindowManagement/Model/Room.swift \
                           Tinycast/Features/WindowManagement/Model/RoomWindowMatcher.swift \
                           Tinycast/Features/WindowManagement/Model/RoomParking.swift \
                           Tinycast/Features/WindowManagement/Model/RoomPlan.swift \
                           Tinycast/Features/WindowManagement/Model/RoomArrangement.swift \
                           Tinycast/Features/WindowManagement/Model/RoomStore.swift \
                           Tinycast/Features/WindowManagement/Model/RoomMinimumSizeStore.swift \
                           Tinycast/Features/WindowManagement/Model/RoomParkingLedger.swift \
                           Tinycast/Platform/LocalizedResource.swift
run WindowFileTests        Tinycast/Features/WindowManagement/Model/WindowCommand.swift \
                           Tinycast/Features/WindowManagement/Model/WindowCycle.swift \
                           Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayout.swift \
                           Tinycast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Tinycast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Tinycast/Features/WindowManagement/Model/Room.swift \
                           Tinycast/Features/WindowManagement/Model/RoomWindow.swift \
                           Tinycast/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Tinycast/Features/WindowManagement/Model/RoomGrid.swift \
                           Tinycast/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Tinycast/Features/WindowManagement/Model/WindowManagementFileFormat.swift \
                           Tinycast/Features/Settings/Model/SettingsFileJSON.swift \
                           Tinycast/Features/Settings/Model/SettingsFileIdentity.swift \
                           Tinycast/Platform/LocalizedResource.swift
run CustomCommandTests     Tinycast/Platform/PseudoTerminal.swift \
                           Tinycast/Platform/ProcessExit.swift \
                           Tinycast/Features/CustomCommands/Model/CustomCommand.swift \
                           Tinycast/Features/CustomCommands/Model/RaycastScriptImport.swift \
                           Tinycast/Features/CustomCommands/UI/CustomCommandEditorSession.swift \
                           Tinycast/Features/CustomCommands/Service/ShellCommandRunner.swift
run CustomCommandListTests Tinycast/Features/CustomCommands/Model/CustomCommand.swift \
                             Tinycast/Features/CustomCommands/UI/CustomCommandListScreen.swift
run UninstallCoordinatorTests Tinycast/Features/Uninstall/Model/*.swift \
                           Tinycast/Features/Uninstall/UI/UninstallCoordinator.swift
run UninstallTests         Tinycast/Features/Uninstall/Model/UninstallTarget.swift \
                           Tinycast/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           Tinycast/Features/Uninstall/Model/UninstallRules.swift \
                           Tinycast/Features/Uninstall/Model/UninstallProtection.swift \
                           Tinycast/Features/Uninstall/Model/UninstallPlan.swift
run QuicklinkTests         Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Tinycast/Features/Quicklinks/Model/RaycastQuicklinkImport.swift \
                           Tinycast/Features/Quicklinks/UI/QuicklinkEditorSession.swift
run QuicklinkCoordinatorTests Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Tinycast/Features/Quicklinks/UI/QuicklinkCoordinator.swift \
                           Tinycast/Features/Quicklinks/UI/QuicklinkEditorSession.swift \
                           Tinycast/Features/Quicklinks/UI/QuicklinkArgumentsAccessory.swift \
                           Tinycast/Features/Snippets/Model/Snippet.swift \
                           Tinycast/Features/Snippets/Model/SnippetTemplateEngine.swift
run slow SnippetsTests     Tinycast/Platform/NotificationToken.swift \
                           Tinycast/Platform/HealthTicker.swift \
                           Tinycast/Platform/AccessibilityText.swift \
                           Tinycast/Features/Snippets/Model/*.swift \
                           Tinycast/Features/Snippets/Service/*.swift \
                           Tinycast/Features/Snippets/UI/SnippetEditorSession.swift \
                           Tinycast/Features/TextInjection/Service/*.swift
run NotesTests             Tinycast/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Tinycast/Features/Notes/Model/*.swift \
                           Tinycast/Features/Notes/Service/*.swift
run NotesEditorTests       Tinycast/Platform/Signposts.swift \
                           Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/DesignSystem/InterfaceMetrics.swift \
                           Tinycast/Platform/NotificationToken.swift \
                           Tinycast/Features/TextInjection/Service/InjectableTextView.swift \
                           Tinycast/Features/Notes/Model/NoteDocument.swift \
                           Tinycast/Features/Notes/Model/NoteTitle.swift \
                           Tinycast/Features/Notes/Model/NoteMarkdown.swift \
                           Tinycast/Features/Notes/Model/NoteMarkdownParser.swift \
                           Tinycast/Features/Notes/Model/NoteInlineScanner.swift \
                           Tinycast/Features/Notes/Model/NoteEditPlan.swift \
                           Tinycast/Features/Notes/Model/NoteEditAction.swift \
                           Tinycast/Features/Notes/Model/NoteFormatting.swift \
                           Tinycast/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Tinycast/Features/Notes/Model/NoteRevealPolicy.swift \
                           Tinycast/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Tinycast/Features/Notes/UI/NoteBlockDecoration.swift \
                           Tinycast/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Tinycast/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Tinycast/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Tinycast/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Tinycast/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Tinycast/Features/Notes/UI/NoteTextViewEditing.swift \
                           Tinycast/Features/Notes/UI/NoteTextView.swift \
                           Tinycast/Features/Notes/UI/NoteEditorView.swift
run -O index NotesEditorPerformanceTests \
                           Tinycast/Platform/Signposts.swift \
                           Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/DesignSystem/InterfaceMetrics.swift \
                           Tinycast/Platform/NotificationToken.swift \
                           Tinycast/Features/TextInjection/Service/InjectableTextView.swift \
                           Tinycast/Features/Notes/Model/NoteDocument.swift \
                           Tinycast/Features/Notes/Model/NoteTitle.swift \
                           Tinycast/Features/Notes/Model/NoteMarkdown.swift \
                           Tinycast/Features/Notes/Model/NoteMarkdownParser.swift \
                           Tinycast/Features/Notes/Model/NoteInlineScanner.swift \
                           Tinycast/Features/Notes/Model/NoteEditPlan.swift \
                           Tinycast/Features/Notes/Model/NoteEditAction.swift \
                           Tinycast/Features/Notes/Model/NoteFormatting.swift \
                           Tinycast/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Tinycast/Features/Notes/Model/NoteRevealPolicy.swift \
                           Tinycast/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Tinycast/Features/Notes/UI/NoteBlockDecoration.swift \
                           Tinycast/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Tinycast/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Tinycast/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Tinycast/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Tinycast/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Tinycast/Features/Notes/UI/NoteTextViewEditing.swift \
                           Tinycast/Features/Notes/UI/NoteTextView.swift \
                           Tinycast/Features/Notes/UI/NoteEditorView.swift
run slow -O RaycastTests   Tinycast/Features/Backup/Model/RaycastImportError.swift \
                           Tinycast/Features/Backup/Service/RaycastDecoder.swift \
                           Tinycast/Features/Backup/Service/Scrypt.swift \
                           Tinycast/Platform/Compression/Zlib.swift \
                           Tinycast/Features/Clipboard/Model/RaycastClipboardImport.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
                           Tinycast/Platform/Images/ImageDerivative.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Tinycast/Features/Clipboard/Model/ColorValue.swift \
                           Tinycast/Features/Clipboard/Model/ColorFormat.swift \
                           Tinycast/Features/Clipboard/Model/ColorSpaces.swift
run SettingsBackupTests    Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift
run HyperKeyEngineTests    Tinycast/Features/HotKeys/Model/HyperKeyEngine.swift \
                           Tinycast/Features/HotKeys/Model/HyperKey.swift \
                           Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Tinycast/Features/HotKeys/Model/ModifierKey.swift \
                           Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Tinycast/Features/HotKeys/Service/KeyShortcut.swift \
                           Tinycast/Platform/ASCIIKeyboardLayout.swift
run HyperKeyTests          Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Tinycast/Features/HotKeys/Model/HyperKeyConflictPolicy.swift \
                           Tinycast/Features/HotKeys/Service/KeyboardRemapper.swift \
                           Tinycast/Features/HotKeys/Service/RemapInstanceLock.swift \
                           Tests/HyperKeyFixtures.swift
run DictationKeyTests      Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Tinycast/Features/HotKeys/Model/HyperKeyConflictPolicy.swift \
                           Tinycast/Features/HotKeys/Service/KeyboardRemapper.swift \
                           Tinycast/Features/HotKeys/Service/RemapInstanceLock.swift \
                           Tinycast/Features/HotKeys/Service/DictationKeyManager.swift \
                           Tinycast/Platform/HealthTicker.swift \
                           Tinycast/Platform/NotificationToken.swift \
                           Tests/HyperKeyFixtures.swift \
                           Tests/DictationKeyFixtures.swift
run HotKeyDispatchTests    Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Tinycast/Features/HotKeys/Model/ModifierKey.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Tinycast/Features/HotKeys/Model/HyperKey.swift \
                           Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyAction.swift \
                           Tinycast/Features/HotKeys/Service/KeyShortcut.swift \
                           Tinycast/Features/HotKeys/Service/HotKeyManager.swift \
                           Tinycast/Platform/ASCIIKeyboardLayout.swift \
                           Tests/HotKeyDispatchFixtures.swift
run SettingsFileTests      Tinycast/Features/Settings/Model/*.swift \
                           Tinycast/Features/Settings/Service/SettingsFileMonitor.swift \
                           Tinycast/Features/Settings/Service/SettingsFileRepository.swift \
                           Tinycast/Platform/AppPaths.swift
run BackupArchiveTests     Tinycast/Platform/AppPaths.swift \
                           Tinycast/Features/Backup/Model/BackupArchive.swift \
                           Tinycast/Features/Backup/Model/BackupBundle.swift \
                           Tinycast/Features/Backup/Model/BackupCategory.swift \
                           Tinycast/Features/Backup/Model/BackupClipboardItem.swift \
                           Tinycast/Features/Backup/Model/BackupManifest.swift \
                           Tinycast/Features/Backup/Service/BackupStaging.swift
E=Tinycast/Features/Extensions
run SymbolsTests           $E/Service/SymbolCatalog.swift
run ExtensionCleanupTests  $E/Service/ExtensionCleanup.swift \
                           $E/Service/ExtensionCatalog.swift \
                           Tinycast/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ExtensionRefreshTests  $E/Model/ExtensionManifest.swift \
                           Tinycast/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ExtensionMetadataTests $E/Model/ExtensionCommandMetadata.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift
run ExtensionVersionTests  $E/Model/ExtensionListing.swift \
                           $E/Service/ExtensionVersionStore.swift
run ExtensionStoreTests    $E/Model/ExtensionGitHubSource.swift \
                           $E/Model/ExtensionListing.swift \
                           $E/Model/ExtensionPackageManager.swift \
                           $E/Model/ExtensionStoreResponse.swift
run ExtensionFormTests     $E/Model/ExtensionFormMetrics.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/UI/ExtensionFormKey.swift \
                           $E/Model/ExtensionDateExpression.swift \
                           $E/UI/ExtensionListKey.swift \
                           Tests/ExtensionListKeyTests.swift
run ExtensionImageSizeTests $E/Model/ExtensionImageSize.swift
run ExtensionSignInTests   $E/Service/ExtensionSignInSession.swift
run ExtensionAccessoryTests $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionStorage.swift
run slow ExtensionTests    -parse-as-library \
                           Tests/ExtensionTests+MenuBar.swift \
                           Tests/ExtensionFetchTests.swift \
                           $E/Model/ExtensionLaunchError.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           $E/Service/ExtensionStorage.swift \
                           $E/Service/ExtensionMenuBarManager.swift \
                           $E/Model/ExtensionCommandMetadata.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift \
                           $E/UI/ExtensionMenuBarController.swift \
                           $E/UI/ExtensionMenuBarImage.swift \
                           Tinycast/Platform/Appearance.swift \
                           Tinycast/Platform/AppDisplayName.swift \
                           Tinycast/Platform/Images/IconCache.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/DesignSystem/InterfaceMetrics.swift \
                           $E/Model/ExtensionBootConfig.swift \
                           $E/Model/ExtensionDeepLink.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/Model/ExtensionGridLayout.swift \
                           $E/Model/ExtensionSearchState.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift \
                           $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Service/ExtensionFetcher.swift \
                           Tinycast/Platform/ProcessExit.swift \
                           $E/Service/ExtensionIconCache.swift \
                           $E/Service/ExtensionNodeShims.swift \
                           $E/Service/ExtensionRuntime.swift \
                           $E/Service/ExtensionNameResolver.swift \
                           $E/Service/ExtensionWebSocketBridge.swift \
                           $E/UI/ExtensionAnimatedImage.swift \
                           $E/UI/ExtensionImage.swift \
                           $E/UI/ExtensionScreen.swift \
                           $L/SearchRelevance.swift \
                           Tinycast/Platform/Compression/Zlib.swift \
                           Tinycast/Features/Clipboard/Model/ColorValue.swift \
                           Tinycast/Features/Clipboard/Model/ColorSpaces.swift
run SettingsHistoryTests   Tinycast/Features/Settings/SettingsTab.swift \
                           Tinycast/Features/Settings/SettingsHistory.swift \
                           Tinycast/Features/Settings/SettingsAnchor.swift \
                           Tinycast/Features/Settings/SettingsNavigationState.swift \
                           Tinycast/Features/Settings/SettingsSearchCatalog.swift \
                           $L/SearchRelevance.swift \
                           Tinycast/Platform/LocalizedResource.swift
run UpdatesTests           Tinycast/Features/Updates/Model/*.swift \
                           Tinycast/Features/Updates/Service/BundleSignature.swift \
                           Tinycast/Features/Updates/Service/UpdateSignature.swift
run UpdateCheckTests       Tinycast/Features/Updates/Model/*.swift \
                           Tinycast/Features/Updates/Service/UpdateCheckStore.swift \
                           Tinycast/Platform/AppPaths.swift
run SupportTests           Tinycast/Features/Support/Model/*.swift
run AIProviderTests        Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/AI/Model/*.swift \
                           Tinycast/Features/AI/Settings/AISettingsStore.swift \
                           Tinycast/Features/AI/Service/CodexAppServerClient.swift \
                           Tinycast/Features/AI/Service/InstalledAIProbe.swift \
                           Tinycast/Platform/ExecutableLocator.swift Tinycast/Platform/ProcessExit.swift
run OpenCodeMCPTests       Tinycast/Features/AI/Model/*.swift \
                           Tinycast/Platform/ExecutableLocator.swift Tinycast/Platform/ProcessExit.swift \
                           Tinycast/Features/AI/Service/AIProvider.swift \
                           Tinycast/Features/AI/Service/AIToolLoopProvider.swift \
                           Tinycast/Features/AI/Service/InstalledCLIProvider.swift \
                           Tinycast/Features/AI/Service/OpenCodeMCPBridge.swift
run AIChatTests            Tinycast/Features/AI/Model/AIRequest.swift \
                           Tinycast/Features/AI/Model/AIConnection.swift \
                           Tinycast/Features/AI/Model/AIConversationOpenPolicy.swift \
                           Tinycast/Features/AI/Model/AppleIntelligence.swift \
                           Tinycast/Features/AI/Model/AIAttachmentPolicy.swift \
                           Tinycast/Features/AI/Model/AIRetention.swift \
                           Tinycast/Features/AI/Model/AITool.swift \
                           Tinycast/Features/AI/Model/JSONValue.swift \
                           Tinycast/Features/AI/Model/ChatMessage.swift \
                           Tinycast/Features/AI/Model/ChatSession.swift \
                           Tinycast/Features/AI/Model/ChatPreset.swift \
                           Tinycast/Features/AI/Model/ChatChoices.swift \
                           Tinycast/Features/AI/Model/ChatReferences.swift \
                           Tinycast/Features/AI/Model/ChatTitle.swift \
                           Tinycast/Features/AI/Model/ChatFind.swift \
                           Tinycast/Features/AI/Model/ChatCitations.swift \
                           Tinycast/Features/AI/Model/ChatToolScope.swift \
                           Tinycast/Features/AI/Model/MarkdownBlock.swift \
                           Tinycast/Features/AI/Model/MarkdownMath.swift \
                           Tinycast/Features/AI/Model/MathFormula.swift \
                           Tinycast/Features/AI/Model/MathNode.swift \
                           Tinycast/Features/AI/Model/MathSymbolCatalog.swift \
                           Tinycast/Features/AI/Service/AIProvider.swift \
                           Tinycast/Features/AI/Service/ChatHistoryStore.swift \
                           Tinycast/Features/AI/Service/AIToolLoopProvider.swift \
                           Tinycast/Features/AI/UI/AIChatState.swift \
                           Tinycast/Features/AI/UI/AIChatSurfacesState.swift \
                           Tinycast/Features/AI/UI/ChatFindState.swift
run AIResponsesTests       Tinycast/Features/AI/Model/AIConnection.swift \
                           Tinycast/Features/AI/Model/AppleIntelligence.swift \
                           Tinycast/Features/AI/Model/AIModelDiscovery.swift \
                           Tinycast/Features/AI/Model/AIRequest.swift \
                           Tinycast/Features/AI/Model/AIRequestBody.swift \
                           Tinycast/Features/AI/Model/AIStreamDecoder.swift \
                           Tinycast/Features/AI/Model/AIResponsesDecoder.swift \
                           Tinycast/Features/AI/Model/AIThinkTagDecoder.swift \
                           Tinycast/Features/AI/Model/AIProviderFailure.swift \
                           Tinycast/Features/AI/Model/AITool.swift \
                           Tinycast/Features/AI/Model/JSONValue.swift \
                           Tinycast/Features/AI/Service/AIProvider.swift \
                           Tinycast/Features/AI/Service/AIToolLoopProvider.swift
run ChatMarkdownTests      Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/DesignSystem/InterfaceMetrics.swift \
                           Tinycast/Features/Settings/InterfaceSize.swift \
                           Tinycast/Features/AI/Model/AIRequest.swift \
                           Tinycast/Features/AI/Model/AITool.swift \
                           Tinycast/Features/AI/Model/JSONValue.swift \
                           Tinycast/Features/AI/Model/ChatMessage.swift \
                           Tinycast/Features/AI/Model/ChatChoices.swift \
                           Tinycast/Features/AI/Model/ChatReferences.swift \
                           Tinycast/Features/AI/Model/ChatCitations.swift \
                           Tinycast/Features/AI/Model/ChatFind.swift \
                           Tinycast/Features/AI/Model/MarkdownBlock.swift \
                           Tinycast/Features/AI/Model/MarkdownMath.swift \
                           Tinycast/Features/AI/Model/MathFormula.swift \
                           Tinycast/Features/AI/Model/MathNode.swift \
                           Tinycast/Features/AI/Model/MathSymbolCatalog.swift \
                           Tinycast/Features/AI/Model/SyntaxGrammar.swift \
                           Tinycast/Features/AI/Model/SyntaxHighlighter.swift \
                           Tinycast/Features/AI/Model/SyntaxStructuredLexers.swift \
                           Tinycast/Features/AI/UI/ChatTextHighlight.swift \
                           Tinycast/Features/AI/UI/ChatMarkdownRenderer.swift \
                           Tinycast/Features/AI/UI/MathAttachmentCell.swift \
                           Tinycast/Features/AI/UI/MathBox.swift \
                           Tinycast/Features/AI/UI/MathFont.swift \
                           Tinycast/Features/AI/UI/MathLayoutEngine.swift
run SyntaxHighlightTests   Tinycast/Features/AI/Model/SyntaxGrammar.swift \
                           Tinycast/Features/AI/Model/SyntaxHighlighter.swift \
                           Tinycast/Features/AI/Model/SyntaxStructuredLexers.swift
run MCPTests               Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/AI/Model/AIConnection.swift \
                           Tinycast/Features/AI/Model/AppleIntelligence.swift \
                           Tinycast/Features/AI/Model/AITool.swift \
                           Tinycast/Features/AI/Model/AIToolServer.swift \
                           Tinycast/Features/AI/Model/JSONValue.swift \
                           Tinycast/Features/MCP/Model/*.swift \
                           Tinycast/Features/MCP/Settings/MCPSettingsStore.swift
run -O TextDiffTests       Tinycast/Features/QuickActions/Model/TextDiffEngine.swift
run index TextDiffPerformanceTests Tinycast/Features/QuickActions/Model/TextDiffEngine.swift
run QuickActionTests       Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/AI/Model/AIConnection.swift \
                           Tinycast/Features/AI/Model/AppleIntelligence.swift \
                           Tinycast/Features/AI/Model/ChatGPTSubscription.swift \
                           Tinycast/Features/AI/Model/InstalledAI.swift \
                           Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Tinycast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Tinycast/Features/QuickActions/Model/CustomQuickActionStore.swift \
                           Tinycast/Features/QuickActions/Model/QuickAction.swift \
                           Tinycast/Features/QuickActions/Model/QuickActionFailure.swift \
                           Tinycast/Features/QuickActions/Model/QuickActionPrompt.swift \
                           Tinycast/Features/QuickActions/Model/QuickActionSettings.swift \
                           Tinycast/Features/QuickActions/Settings/QuickActionSettingsStore.swift \
                           Tinycast/Platform/LocalizedResource.swift
run AppleIntelligenceTests Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/AI/Model/*.swift \
                           Tinycast/Features/AI/Service/AIProvider.swift \
                           Tinycast/Features/AI/Service/AppleIntelligenceProvider.swift
run MCPOAuthTests          Tinycast/Platform/ExecutableLocator.swift \
                           Tinycast/Platform/ProcessExit.swift \
                           Tinycast/Platform/KeychainSecretStore.swift \
                           Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/AI/Model/AIConnection.swift \
                           Tinycast/Features/AI/Model/AppleIntelligence.swift \
                           Tinycast/Features/AI/Model/AITool.swift \
                           Tinycast/Features/AI/Model/AIToolServer.swift \
                           Tinycast/Features/AI/Model/AIStreamDecoder.swift \
                           Tinycast/Features/AI/Model/AIResponsesDecoder.swift \
                           Tinycast/Features/AI/Model/AIProviderFailure.swift \
                           Tinycast/Features/AI/Model/AIThinkTagDecoder.swift \
                           Tinycast/Features/AI/Model/AIRequest.swift \
                           Tinycast/Features/AI/Model/JSONValue.swift \
                           Tinycast/Features/MCP/Model/*.swift \
                           Tinycast/Features/MCP/Service/*.swift
run slow MCPStdioTests     Tinycast/Platform/ExecutableLocator.swift \
                           Tinycast/Platform/ProcessExit.swift \
                           Tinycast/Platform/KeychainSecretStore.swift \
                           Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/AI/Model/AIConnection.swift \
                           Tinycast/Features/AI/Model/AppleIntelligence.swift \
                           Tinycast/Features/AI/Model/AITool.swift \
                           Tinycast/Features/AI/Model/AIToolServer.swift \
                           Tinycast/Features/AI/Model/AIStreamDecoder.swift \
                           Tinycast/Features/AI/Model/AIResponsesDecoder.swift \
                           Tinycast/Features/AI/Model/AIProviderFailure.swift \
                           Tinycast/Features/AI/Model/AIThinkTagDecoder.swift \
                           Tinycast/Features/AI/Model/AIRequest.swift \
                           Tinycast/Features/AI/Model/JSONValue.swift \
                           Tinycast/Features/MCP/Model/*.swift \
                           Tinycast/Features/MCP/Service/*.swift

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
JOBS="${TINYCAST_TEST_JOBS:-4}"
export TINYCAST_TEST_TIMEOUT="${TINYCAST_TEST_TIMEOUT:-300}"
started=$SECONDS

# Numbers each result, and names what is still running whenever the output goes quiet.
report() {
    local finished=0 line asked running file
    while :; do
        asked=$SECONDS
        if IFS= read -r -t 15 line; then
            case "$line" in
                "dispatch "*)
                    [ "$finished" -eq "$ran" ] || return 1
                    return "${line#dispatch }";;
            esac
            finished=$((finished + 1))
            printf '[%*d/%d] %s\n' "${#ran}" "$finished" "$ran" "$line"
            continue
        fi
        # Bash 3.2 returns the same status for a timeout and EOF; only EOF comes back at once.
        if [ $((SECONDS - asked)) -lt 10 ]; then return 1; fi
        running=""
        for file in "$BIN"/*.running; do
            [ -e "$file" ] && running="$running $(basename "$file" .running)"
        done
        printf '        \033[2mstill running after %ds:%s\033[0m\n' $((SECONDS - started)) "$running"
    done
}

dispatch() {
    [ -s "$1" ] || return 0
    sort -s -k1,1n "$1" | cut -d' ' -f2- | xargs -P "$2" -L1 "$SELF" --exec
}

# Without this the suite reports "all passed" whenever dispatch itself dies and no harness ran.
if ! {
    dispatch "$QUEUE" "$JOBS"
    echo "dispatch $?"
} | report; then
    echo "harness dispatch failed; no result below can be trusted" >&2
    exit 1
fi
elapsed=$((SECONDS - started))

# A compiler diagnostic is far longer than PIPE_BUF, so the workers log it and it is replayed here.
while read -r _ name _; do
    if [ -f "$BIN/$name.failed" ]; then failed+=("$name"); fi
done < "$QUEUE"

if [ ${#failed[@]} -gt 0 ]; then
    for name in "${failed[@]}"; do
        printf '\n\033[31m--- %s ---\033[0m\n' "$name"
        cat "$BIN/$name.log"
    done
    printf '\n\033[31mFAILED\033[0m  %d of %d harness(es) failed in %ds: %s\n' \
        "${#failed[@]}" "$ran" "$elapsed" "${failed[*]}" >&2
    exit 1
fi
printf '\n\033[32mPASSED\033[0m  All %d harness(es) passed in %ds.\n' "$ran" "$elapsed"
