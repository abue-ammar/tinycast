# UI & Design System

The design system for Tinycast's UI, written so an agent restyling or extending it stays consistent
with what's already there. This documents **Tinycast as built** — every rule here maps to code in
`Tinycast/`. `Core/Theme.swift` is the single design-token source.

Read this before touching any view body, `Theme` value, or the panel chrome.

---

## The look, in one paragraph

Tinycast is a **Raycast-style dark command palette**: a borderless floating panel whose surface is
just the OS behind-window blur under a 40% black scrim — there is no gray chrome. Everything on that
surface is white at a fixed alpha ramp. The header and bottom bar **float over the list as fully
transparent overlays**; there are no hard-edged bars, strips, or dividers. Rows don't clip under the
bars, they **dissolve**: a scroll-driven gradient mask ghosts them as they pass beneath. Floating
controls (the action pill, the menu circle, popover menus) are **Liquid Glass**. The whole app is
locked to dark mode because the glass material is tuned for a deep dark surface.

Five load-bearing ideas, in priority order:

1. **Surface = 40% black over behind-window blur.** No solid backgrounds. Depth comes from the desktop showing through.
2. **White-alpha ramp, never grays.** Text and surfaces are `Color.white.opacity(…)` at fixed stops.
3. **Floating bars, not chrome.** Header/footer are transparent overlays; the list fills the whole panel.
4. **Edges dissolve, they don't clip.** Scroll-driven mask, no separators between list and bars.
5. **Glass only on floating controls.** The main surface is never glass; pills/menus/circles are.

---

## Non-negotiable invariants

These are the things that quietly break the look if changed. Preserve them unless the task is explicitly to change them.

- **Forced dark.** `AppCore.start()` sets `NSApp.appearance = .darkAqua`. All colors are literal white/black alphas, not adaptive `Color`s. Don't introduce semantic/adaptive colors or a light variant.
- **No grays, no opaque fills on the surface.** Reach for `Theme.Colors.*` (white-alpha) instead of `.gray`, `NSColor.windowBackground`, etc.
- **No hard dividers between the list and the bars.** The header and bottom bar are `safeAreaInset` overlays with no background; separation comes from `edgeDissolve()`, nothing else. (One deliberate exception: the vertical hairline between the clipboard list and its preview pane.)
- **The panel corner is clipped once, at the root.** `RootPaletteView.body` ends with `.background(black 40%) → .background(VisualEffectView()) → .clipShape(RoundedRectangle(26, .continuous))`. Keep that order; the scrim goes _over_ the vibrancy, and the clip is last.
- **Don't use the native scroll edge effect.** Inside a transparent panel it renders a hard-bounded rectangle. Use `edgeDissolve()`.
- **Test over a light desktop.** Transparency and corner masking bugs only show over bright wallpaper. Dark wallpaper hides them.
- **No `NSAlert`, no `NSSlider`, no system popovers.** Every confirmation, failure report, value prompt and transient readout is Tinycast's own SwiftUI surface (see "Modals & HUD"). An Aqua alert on a white-alpha-over-vibrancy app reads as a different product, and its `runModal` run loop keeps Carbon hotkeys firing underneath.

---

## Tokens — `Tinycast/Core/Theme.swift`

`Theme` is the single source of truth. **Never hardcode a spacing/radius/size/color that has a token.**
Add a token rather than a magic number when introducing a new value.

### Spacing (`Theme.Spacing`)

`xxs 2` · `xs 4` · `sm 6` · `md 8` · `lg 10` · `xl 12` · `xxl 20`

`xxs` is the tight gap between adjacent keycap chips (used everywhere keycaps sit side by side).

Row content insets are `md`; list horizontal inset is `md`; the search icon aligns with rows via `md * 2`.

Section-header rhythm has two dedicated tokens: `sectionHeaderBottom` (header → first row) and
`sectionSpacing` (gap above every header **except the list's first**, which reads as the previous
section's closing padding). See "Section headers" below.

### Radius (`Theme.Radius`)

`panel 26` · `row 10` · `card 10` · `modal 20` · `menuPanel 16` · `menu 6` · `menuRow 10` · `thumbnail 6` · `keyCap 6` · `recorderKeyCap 4`

`modal` sits between `menuPanel` and `panel` so a dialog reads as a smaller sibling of the palette, not a second palette.

`menu` is the shared small-control corner (sidebar tiles, About link pills); `menuRow` is the slightly rounder hover highlight behind popover-menu rows.

Always `RoundedRectangle(cornerRadius:, style: .continuous)` — continuous corners everywhere, never `.circular`.

### Size (`Theme.Size`)

`panelWidth 750` · `panelHeight 475` · `headerHeight 44` · `bottomBarHeight 52` · `rowIcon 24` ·
`keyCap 18` · `recorderKeyCap 16` · `menuButton 36` · `clipboardListWidth 290` · `menuWidth 276` · `menuIcon 16` ·
`settingsSidebar 184` · `settingsRowIcon 20` · `modalWidth 420` · `modalIcon 26` · `hudWidth 200` ·
`hudHeight 92` · `volumeTrackHeight 6` · `volumeKnob 16`

`keyCap` sizes the palette's keycap chips; `recorderKeyCap` (both size and radius) is the intentionally-smaller Settings shortcut-recorder chip.

### Typography (`Theme.Typography`)

System fonts only — **no fixed point sizes in views** (honors Dynamic Type). `searchField` is the one
explicit size (20pt regular). Use `rowTitle` (`.body`), `sectionHeader` (`.subheadline.medium`),
`rowTrailing`/`bar`/`menuRow`/`keyCap` etc. as named.

### Colors (`Theme.Colors`) — the white-alpha ramp

| Token            | Value          | Use                                              |
| ---------------- | -------------- | ------------------------------------------------ |
| `panelDimming`   | black **0.40** | the panel scrim over vibrancy                    |
| `selection`      | white 0.10     | selected row fill (keyboard/active selection)    |
| `rowHover`       | white 0.05     | mouse-hover fill (always fainter than selection) |
| `menuHover`      | white 0.10     | popover-menu row hover                           |
| `separator`      | white 0.10     | the clipboard list↔preview hairline              |
| `controlSurface` | white 0.10     | filled keycaps, glyph tiles                      |
| `border`         | white 0.20     | outlined keycap borders                          |
| `textSecondary`  | white 0.60     | secondary labels                                 |
| `textTertiary`   | white 0.40     | placeholders, trailing kind labels               |
| `cardFill`       | white 0.05     | settings/calc card fill                          |
| `cardStroke`     | white 0.10     | settings/calc card border + inset dividers       |
| `glassFrost`     | white 0.01     | whitish tint layered into the floating glass     |

Beyond these, `.secondary`/`.tertiary` foreground styles are fine for SF Symbols (they resolve against
the forced-dark environment). **Selection always beats hover** when a row is both.

---

## Panel structure — `Core/PalettePanel.swift`, `Features/RootPaletteView.swift`

- **`PalettePanel`** is a borderless `NSPanel`: `isOpaque = false`, `backgroundColor = .clear`, `.floating` level, `hasShadow`, `animationBehavior = .none`. It hosts SwiftUI via `NSHostingView`. `PaletteWindowController` centers it slightly above screen center (`+8%`) and dismisses it on `windowDidResignKey`.
- **The results layer fills the whole panel.** The header and bottom bar attach via `.safeAreaInset(edge: .top/.bottom)` as transparent overlays that float _over_ the list. The list underlaps them and dissolves at the edges.
- **Header** (`headerHeight 44`): a back-chevron _or_ mode glyph, then the plain `TextField` (no border/background). Sub-screens (Clipboard, Calculator History) show the back chevron; the launcher shows a magnifying glass. The search icon aligns horizontally with row content.
- **Compact keyboard entry:** pressing `↓` in the collapsed launcher expands the results and selects the first row without replacing or defocusing the shared search field.
- **Bottom bar** (`bottomBarHeight 52`): a menu circle on the left, the action group on the right — both floating glass, no bar background. The action group is one glass `Capsule` holding the primary-action pill (label + `↵`) and the Actions toggle (`⌘K`).

---

## The edge dissolve — `Core/EdgeDissolve.swift`

The signature effect. A scroll-driven `LinearGradient` mask on each list so rows soften as they approach
a floating bar, ghost beneath it, and vanish only at the window edge. Attach with `.edgeDissolve()` on
the `ScrollView`, **before `.thinScrollbar()`** (so the scrollbar overlay stays unmasked).

- Fade bands: top = `headerHeight + headerPadding + 32`, bottom = `bottomBarHeight + 28` — each overshoots its bar into the visible list, so the ramp finishes ~32/28px _past_ the bar rather than cliffing at its edge.
- Alpha floors mid-scroll (not to 0): **top 0.15, bottom 0.25**, eased by how much content is hidden past the edge (`1 − (1 − floor)·clamp(dist/band, 0, 1)`).
- Only masks when the list is scrollable; the edge stop stays transparent so rubber-band bounces still dissolve. A list that fits gets no mask.
- The mask spans the scroll view's **full** frame (`.ignoresSafeArea()`) — otherwise the bars' safe-area insets shift the gradient onto at-rest rows.

---

## Rows, selection, hover — `Launcher/LauncherView.swift`, `Clipboard/ClipboardView.swift`

All lists share one row grammar so launcher and clipboard look identical:

- `HStack(spacing: lg)`: leading 24pt icon/thumbnail, title (`.body`, `lineLimit(1)`), optional trailing keycaps/kind label, `Spacer`. Insets: `.horizontal md`, `.vertical sm`.
- Background is a `RoundedRectangle(row, .continuous)` filled by `fill`: **selection → hover → clear**, in that precedence. This `fill` computed property is copy-identical across `AppRow`, `ClipboardRow`, `CalculatorCard` — keep them in sync.
- **Hover state lives on the row**, not the list, so a mouse sweep repaints only the rows entering/leaving (a list-level hover rebuilds every row per move — don't do that).
- **Scroll moves only on keyboard nav/reset**, driven by a `ScrollIntent` (`Core/ScrollIntent.swift`) — mouse selection targets a visible row and never yanks scroll. `.follow` is a minimal scroll-to-visible (nil anchor), so the list stays stationary while the selection walks across it and only advances by a row at the viewport edges; `.top` scrolls to the origin anchor that `scrollOriginAnchor()` installs — a zero-height overlay applied to the scrolled content *after* its padding, so it marks offset 0 without joining the layout and the restored origin is exact (targeting the first row instead leaves the top padding hidden under the header). A `.follow` that lands on flat index 0 restores the origin instead, so that row's section header comes back into view. One intent state serves all four modes — they never coexist.
- **Keycaps** use `KeyCapChip`: `.outline` (white-0.20 border) for hotkey hints on rows, `.filled` (white-0.10 fill) for footer shortcuts.

### Section headers

All four palette lists (App Launcher, Clipboard, Emoji, Calculator History) render category labels
through one shared **`SectionHeader`** (`.subheadline.medium`, secondary — `Features/Launcher/LauncherView.swift`).
The launcher shows a single "Results" header over search matches, and per-kind sections
(Favorites / Applications / System Settings / Commands) for the empty query; clipboard/history use
date buckets (Today / Yesterday / …), and the clipboard adds a "Pinned" section above them holding
every pinned entry (filtered searches included).

Spacing lives in `Theme.Spacing`: `sectionHeaderBottom` (header → first row) and `sectionSpacing`
(gap above every header **except the list's first**, which reads as the previous section's closing
padding). Each list passes `isFirst: row.id == <rows>.first?.id` so only the very first row skips the
leading gap. Headers are non-selectable display rows, so selection (keyed by id) is unaffected.

---

## Liquid Glass — `Theme.frosted(in:)`, `Features/PopoverMenu.swift`

Glass is **only** for floating controls, never the main surface.

- `View.frosted(in:)` = `glassEffect(.regular.interactive().tint(glassFrost), in:)` + `.tint(.clear)` — interactive lensing with a whitish frost tint (`glassFrost`) so the glass reads brighter than clear. Used on the action-group capsule and the menu circle; tune the frost amount via the `glassFrost` token, not per call site.
- **Menus are in-window overlays, not system popovers.** `.contextMenu`/`NSMenu` stall clicks for seconds inside a `LazyVStack` and spill outside the panel. Use `PopoverMenu` anchored to a bottom corner via `.overlay`, inset `menuInset` (8pt) so its own corner isn't clipped by the panel's.
- **`PopoverMenu`** uses `glassEffect(.regular, in: RoundedRectangle(menuPanel 16))` with **no hand-tuned shadow** — Tahoe glass carries its own elevation; adding a drop shadow reads heavy and non-native.
- `PopoverMenuRow`: leading glyph, label, trailing shortcut glyph, `menuHover` fill on hover, `menuRow 10` corner. Menus animate in with `.opacity + .scale(0.96)` from the anchored corner, `easeOut 0.14`.
- The glyph is a `PopoverMenuIcon`: `.symbol` (SF Symbol, `hierarchical`, secondary — or **red** when `isDestructive`) or `.file` (a real app icon via `IconCache`, used by the paste rows to show the paste target). `PopoverMenuItem` keeps a `systemImage:` convenience init, so symbol rows read exactly as before.
- **Both glyph kinds share one square `menuIcon` (20) slot**, which is what makes symbol and app-icon rows read as the same size and pins a single row height. 20 is deliberately larger than the artwork looks: an `IconCache` icon paints only ~85% of its canvas (13pt visible at a 16pt slot), while a `.body` SF Symbol renders 17–18pt tall — at 20 the icon lands on 17pt and the two match. Measure before changing it.
- Menu rows are the one place that uses `sm` for the icon→label gap instead of the row-standard `lg`, because that slot's built-in slack already contributes 2–3pt of apparent space.

---

## Modals & HUD `Core/ModalWindowController.swift`, `Features/Modal/TinycastModalView.swift`

Tinycast owns its dialogs; `NSAlert` is never used. `ModalWindowController` is owned by `AppCore` (the
sole owner rule) and is the only presenter, so every confirmation in the app looks and behaves alike.

- **Surface.** A modal reuses the palette's recipe `black panelDimming` → `VisualEffectView()` →
  `clipShape(RoundedRectangle(modal 20))`, in that order at `modalWidth 420`. Glass is reserved for
  the buttons, matching the "glass only on floating controls" rule. The HUD is the exception: it is a
  floating control with no content of its own, so it is stock `glassEffect` throughout.
- **Layout.** Leading tone glyph (`modalIcon 26`, red when the dialog is destructive), title
  (`.headline`) + wrapped secondary message, optional accessory, then right-aligned buttons.
- **Keys.** `ModalPanel.sendEvent` intercepts Esc and ↵ directly instead of relying on SwiftUI
  `onKeyPress`, so the keys work without anything inside the dialog holding focus. Buttons print only
  the caps the panel actually handles (`↵`, `esc`), so a printed cap can't drift from behavior.
  **↵ goes to Cancel on every destructive dialog** the triggering command is one ↵ away in the
  palette, and a reflexive second press must not run it. Arrow keys step the volume slider by the same
  1/16 the volume commands use; click-away resolves as a dismissal.
- **Async, not modal.** Presentation is `async` (`withCheckedContinuation`), so there is no nested run
  loop. A held hotkey can't stack dialogs: while one is up, a second request resolves immediately as a
  dismissal which is why the old `isConfirmingCommand` re-entrancy flag is gone.
- **Non-activating**, like the palette: the dialog takes key focus for its own keys without pulling app
  focus off whatever the user was in. It sits at `.modalPanel`, above the palette's `.floating`, and is
  centred on the **cursor's** display with the same slight optical lift the palette uses.
- **`VolumeSlider`** is hand-drawn (track `volumeTrackHeight 6`, knob `volumeKnob 16`, `controlSurface`
  rail under a white-0.85 fill) with a monospaced-digit percentage in a fixed slot so the track doesn't
  resize between `0%` and `100%`. A click anywhere on the track jumps the level.
- **`TinycastHUDView`** is the transient readout, in two flavours over one shared panel (so a volume
  change and a confirmation can never overlap): a **volume bar** for the volume/mute commands macOS
  only draws its own HUD for real media keys, so a CoreAudio change would otherwise be silent and a
  **one-line message** confirming a command whose effect is invisible (`Trash Emptied`,
  `Hidden Files Shown`, `Bluetooth Off`). It is non-key, auto-dismisses after ~1.5s, and a repeat
  command refreshes the live content instead of stacking a second panel.

## Scrollbars — `Core/ThinScrollbar.swift`

Custom thin overlay scrollbar (the native one flashes and reserves a gutter inside a transparent panel).
`.hideNativeScrollers()` on the scroll _content_ forces the backing `NSScrollView` to a hidden `.overlay`
style; `.thinScrollbar()` on the scroll view draws a hairline thumb (`Color.primary` alpha 0.30 rest →
0.42 hover → 0.5 drag) that fattens on hover, with a faint rail revealed only while hovering/dragging.

Routing: the palette lists (App Launcher, Clipboard history, Emoji, Calculator history) use
`.thinScrollbar()` + `.hideNativeScrollers()`; the Clipboard preview (right pane) and every Settings
pane use the native `.overlayScroller()`. Don't reintroduce native scrollers on the palette lists.

---

## Settings — `Features/Settings/SettingsComponents.swift`

Settings runs in its own `NSWindow` (the SwiftUI `Settings` scene is unreliable for accessory apps) but
shares the palette's `Theme` vocabulary. It reads as macOS System Settings, not the palette:

- **`SettingsPane`**: bold `.title2` title + secondary subtitle header, then scrollable content, `xxl` inset all around, the same thin scrollbar.
- **`SettingsCard`**: rounded `card 10` container, `cardFill` (white 0.05) fill, `cardStroke` (white 0.10) hairline border. Rows inside are split by `SettingsDivider` — an inset hairline aligned under the row title (past the icon).
- **`SettingsRow`**: optional 20pt SF Symbol, title + optional caption subtitle, trailing control, fixed `.horizontal xl / .vertical lg` rhythm.

The calculator's inline `CalculatorCard` reuses this card language (`cardFill` + `cardStroke`) rather than the row language, since it's a highlighted answer, not a list item. A value answer is a **two-column** layout: a source column (input echo) and a target column (result), separated by a centered `arrow.right` glyph (no divider line). Each column optionally carries a word-name **badge pill** beneath its value (`keyCap` font, `controlSurface` fill, `keyCap` radius) — `Expression`→`Result` for scalar arithmetic, unit or currency names for typed results (`Expression`→`Kilograms`), and moment labels for a date/time calc (`12:18 AM`→`9:00 AM`, `Friday, 24 July`→`Friday, 9 April, 2027`). A trailing operator keeps the last complete result and its badge visible while the next operand is being typed.

---

## Rules for agents working on the UI

- **Restyle from screenshots, not extracted CSS.** Pixel-matching Raycast from its bundle led to wrong results before; compare rendered screenshots over a light desktop instead. There's no screen-recording from the shell here — verify AppKit rendering with a `swiftc` harness that prints layer state, and let the user do visual sign-off.
- **Don't add behavior that wasn't requested.** A restyle changes appearance, not interaction — keep selection/scroll/dismiss/focus flows exactly as they are unless the task is about them.
- **New tokens go in `Theme`**, referenced everywhere. No magic numbers in views.
- **Keep the shared grammar shared.** If you change row insets, the `fill` precedence, section-header style, or keycap style, change it for _all_ lists — divergence is the bug, not the feature.
- **Build & verify** with the real toolchain (see [`development.md`](development.md)); a design change that doesn't compile under Swift 6 mode isn't done.
