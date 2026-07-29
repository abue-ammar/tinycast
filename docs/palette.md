# Palette

The command palette is a borderless floating `NSPanel` hosting SwiftUI; see
[architecture.md](architecture.md) for window ownership.

## State flow

`PaletteViewModel` (mode / query / selection / `focusToken`) is the bridge between the panel and
`AppCore`. Showing the palette calls `prepare(mode:)`, which resets state and bumps `focusToken` (a
UUID) so the SwiftUI search field re-focuses. `RootPaletteView` switches its content on `mode`:

- `.launcher` → `LauncherList`
- `.clipboard` → `ClipboardList` + preview
- `.calculatorHistory` → `CalculatorHistoryList`

Clipboard and Calculator History are sub-screens reached from the launcher (Tab, a command, or a
hotkey) and back out to it.

The flat `selection` index is the single source of truth for highlight / activation and **must always
match the visible row order**, including the inline calculator card at index 0 when present (see
[calculator.md](calculator.md)).

## Window placement

`PaletteWindowController` resolves an anchor (left edge + top edge) **once per summon** and reuses it
for every compact↔expanded resize, so only the height changes and the top edge never drifts. The
anchor is dropped on hide, so the next summon re-resolves for wherever the user is then.

Which display it anchors to depends on the **Follow the cursor across displays** setting
(`AppSettings.openOnCursorScreen`, on by default):

- **On** — the screen holding `NSEvent.mouseLocation`, i.e. the display under the pointer.
- **Off** — `NSScreen.main`.

`NSScreen.main` alone can't implement the follow-the-cursor case: Tinycast is an accessory app with no
key window on the display the user is looking at, so `main` resolves to the menu-bar display and the
palette would always open there regardless of which screen the pointer is on.

The hit test is `CGRect.containsMouseLocation`, **not** `CGRect.contains`. A mouse location is the
CoreGraphics cursor position flipped about the primary display's height, so a screen's pixel rows land
in `(minY, maxY]`: the topmost row is exactly `maxY`, which `contains` excludes (a pointer parked at the
top of a display would fall through to `NSScreen.main`), while `minY` is the topmost row of the display
stacked below, which `contains` would wrongly claim.

## Menu-open input freeze

While a footer popover menu (⌘K Actions / app menu) is open the search field reads as inert but
**never resigns first responder** — resigning makes the `NSTextField` swap between its field-editor
and cell rendering, shifting the text / placeholder a point or two, so focus stays put. Input is
frozen instead:

- `RootPaletteView` mirrors the open state into `PaletteViewModel.menuOpen`, whose `didSet` fires
  `onMenuOpenChanged`.
- `PalettePanel.sendEvent` then swallows text-editing keystrokes while `menuOpen` (letting ⌘/⌥ chords
  and menu-nav keys through to SwiftUI `onKeyPress`).
- The caret is hidden by clearing SwiftUI's **own** live field editor's `insertionPointColor`. SwiftUI
  force-casts its field editor to a private subclass, so vending a custom one crashes — only the
  existing one can be tuned.

## Focus restoration (load-bearing)

`PaletteWindowController` records `previousApp` (the frontmost app) on show. Paste then targets that
app:

- `Paster.paste` activates it and posts a synthetic ⌘V via `CGEvent`.
- `Paster.pasteInPlace` posts ⌘V straight to the app's PID _without_ activating it, so the palette can
  stay open and frontmost (used by "paste keeping window open").

Both require the Accessibility permission (`Permissions.ensureAccessibility()`).

The same show also mirrors that app into `PaletteViewModel.pasteTarget` (a `PasteTarget`: localized
name + bundle path), so Clipboard and Emoji can name it — the footer pill reads "Paste to Notes" and
the ⌘K paste rows carry the app's icon. Resolved once per summon, never per render, and deliberately
not cleared by `prepare` (pop-to-root resets the screen, not the target).
