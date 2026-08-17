# UI & Design System

The design system for Tinycast's UI, written so an agent restyling or extending it stays consistent
with what's already there. This documents **Tinycast as built** — every rule here maps to code in
`Tinycast/`. `DesignSystem/Theme.swift` is the single design-token source.

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
- **No `NSAlert`, no `NSSlider`, no system popovers.** Every confirmation, failure report, value prompt and transient readout is Tinycast's own SwiftUI surface (see "Dialogs & HUD"). An Aqua alert on a white-alpha-over-vibrancy app reads as a different product, and its `runModal` run loop keeps Carbon hotkeys firing underneath.
- **A dialog has three independent axes; never let one infer another.** The **icon** (`DialogRequest.symbol`, required) is always the *subject's* own glyph — a command being confirmed uses its `SystemAction.sfSymbol`, so the Restart dialog shows the same icon as the Restart row. Tone never picks an icon. The **tone** (`DialogTone`: `.neutral` / `.success` / `.danger`) tints only that glyph. The **button** takes its color from `DialogAction.Role` (`.standard` white / `.destructive` red / `.cancel` secondary), so a red-glyph security warning can still carry a plain white button — as "Import executable commands?" does.
- **Resolve every glyph through `SymbolImage`, not `Image(systemName:)`.** Some catalog symbols are bundled assets in `Assets.xcassets` (`toggleBluetooth`), and `Image(systemName:)` silently renders nothing for those.
- **↵ runs the primary action, Escape cancels, and Cancel always renders leading** (the left button), matching macOS convention. A button never prints its key cap; hovering it shows a `Tooltip` instead, styled like the palette's own keycap chips.
- **A transient readout is a HUD, not a dialog.** `VolumeHUDController`'s box is volume and mute only, since that one needs an actual level and number; every other success or info confirmation goes through `MessageHUDController`'s pill, whose trailing glyph *is* its `DialogTone`. A pill has no subject to name, so the icon rule above does not apply to it — and that mapping stays file-scoped so nothing can reach for it when building a `DialogRequest`. A new HUD means a new presenter, not a second shape bolted onto an existing controller.
- **Glass is for controls; content takes the panel recipe.** `glassEffect` needs a backdrop to lens, so it only works *inside* a window that already has a `VisualEffectView` — the action capsule, the menu circle, `PopoverMenu`, a dialog's buttons. On a bare borderless panel it falls back to an opaque backing and shows as a dark edge. Both HUDs therefore use `black panelDimming` → `VisualEffectView()` → `clipShape`, exactly like a dialog.

---

## Tokens

Source: `Tinycast/DesignSystem/Theme.swift`.

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

`panel 26` · `row 10` · `card 10` · `dialog 20` · `menuPanel 16` · `menu 6` · `menuRow 10` · `thumbnail 6` · `keyCap 6` · `recorderKeyCap 4`

Notes has no corner of its own: it clips to `panel`, so the two floating surfaces read as siblings.

`dialog` sits between `menuPanel` and `panel` so a dialog reads as a smaller sibling of the palette, not a second palette.

`menu` is the shared small-control corner (sidebar tiles, About link pills); `menuRow` is the slightly rounder hover highlight behind popover-menu rows.

Always `RoundedRectangle(cornerRadius:, style: .continuous)` — continuous corners everywhere, never `.circular`.

### Size (`Theme.Size`)

`panelWidth 750` · `panelHeight 475` · `headerHeight 44` · `bottomBarHeight 52` · `barButtonHeight 28` ·
`rowIcon 24` · `keyCap 18` · `recorderKeyCap 16` · `menuButton 36` · `clipboardListWidth 290` ·
`menuWidth 276` · `clipboardFilterMenuWidth 200` · `menuIcon 20` ·
`settingsSidebar 215` · `settingsRowIcon 20` · `dialogWidth 420` · `dialogIcon 32` · `hudWidth 200` ·
`hudHeight 100` · `volumeTrackHeight 6` · `volumeKnob 16` · `volumeReadout 38`

Notes adds `noteWindow 520×420` (opening size on a first run only), `noteWindowMinimum 320×220`,
`noteTitlebar 44`, `noteTitleInset 120`, `noteEditorInset 16`, `noteSearchHeight 34`,
`noteFooterHeight 28`, `noteGlyph 16`, and `noteEmptyGlyph 28`.

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
| `glassFrost`     | white 0.05     | whitish tint layered into the floating glass     |
| `noteText`       | white 0.90     | Notes Markdown source                            |

Beyond these, `.secondary`/`.tertiary` foreground styles are fine for SF Symbols (they resolve against
the forced-dark environment). **Selection always beats hover** when a row is both.

---

## Panel structure

Source: `Palette/PalettePanel.swift`, `Palette/RootPaletteView.swift`.

- **`PalettePanel`** is a borderless `NSPanel`: `isOpaque = false`, `backgroundColor = .clear`, `.floating` level, `hasShadow`, `animationBehavior = .none`. It hosts SwiftUI via `NSHostingView`. `PaletteWindowController` centers it slightly above screen center (`+8%`) and dismisses it on `windowDidResignKey`.
- **The results layer fills the whole panel.** The header and bottom bar attach via `.safeAreaInset(edge: .top/.bottom)` as transparent overlays that float _over_ the list. The list underlaps them and dissolves at the edges.
- **Header** (`headerHeight 44`): a back-chevron _or_ mode glyph, then the plain `TextField` (no border/background). Sub-screens (Clipboard, Calculator History) show the back chevron; the launcher shows a magnifying glass. The search icon aligns horizontally with row content.
- **Compact keyboard entry:** pressing `↓` in the collapsed launcher expands the results and selects the first row without replacing or defocusing the shared search field.
- **Bottom bar** (`bottomBarHeight 52`): a menu circle on the left, the action group on the right — both floating glass, no bar background. The action group is one glass `Capsule` holding the primary-action pill (label + `↵`) and the Actions toggle (`⌘K`).
- **`BarButton`** is the shared bar control: bare label at rest, a `rowHover` capsule on hover, `barButtonHeight 28`. It carries the footer's two buttons and the clipboard header's type filter, so those hover identically. Hover state lives inside it, so sweeping one never re-renders the palette body.

---

## Notes panel

Source: `Features/Notes/UI/`.

Notes is a sibling surface, not a palette mode. `NotesPanel` is a **titled**, resizable,
non-activating panel — AppKit draws the traffic lights, the drag and the resize — but it keeps the
palette's transparent recipe and deliberately does not dismiss on resign-key. `NotesView`'s root
applies `black panelDimming` → `VisualEffectView()` → one continuous **`panel`** corner clip, so
Notes and the palette round identically. The clip is larger than the theme frame's own corner, so it
is what shows; `invalidateShadow()` on every show recuts the shadow to match.

The title bar is a 44-point band, and both halves of it are deliberate. `titleVisibility` is
`.hidden` and `NotesView` draws the title itself, centred on the **window**: a titlebar accessory
drops `NSThemeFrame` off its centred-title layout, so the native title would sit beside the traffic
lights. The drawn title is not hit-testable, so clicks fall through to the real title bar and drag
the window. The three actions cannot do that, so they live in an `NSTitlebarAccessoryViewController`
at `.trailing` — `NoteTitlebarActions`, the launcher's footer capsule (`BarButton` in a
`frosted(in: Capsule())`) with glyphs in place of pills. Its 44-point height is what sizes the band.

`NotesWindowController` no longer computes frames: the user owns the size, and AppKit autosaves both
position and size under `"Notes Window"`. The window shows exactly one surface at a time — editor,
switcher, or the "No Notes" empty state — and the character count is part of the editor surface, so
it never appears without a note.

The header keeps a fixed slot for status so Saving, Saved, failure, and conflict symbols cannot move
the controls. Failure and conflict symbols can be clicked to reopen their recovery report after a
dismissal. A title click opens the in-window note switcher; dragging the title, note icon, or otherwise
empty header moves the panel after a three-point threshold. Create, Reveal, Hide, and actionable status
remain click-only controls. Escape closes the switcher before hiding, while Command-W and the hide
control order the panel out. Show Notes only shows or focuses; focus loss leaves the panel visible.

The editor is one native TextKit 2 surface. Its string is the canonical Markdown source, using one
system font and the `noteText` color. Markdown markers remain visible and receive no parsing, rendering,
formatting controls, task overlays, or link behavior. AppKit owns editing, undo, selection, Find, and
marked text.

The switcher is its own glass panel over the editor, sized to its list up to a 240-point ceiling and
never resizing the note window. Its plain search field and
keyboard-navigable rows use the shared selection/hover ramp; rename and Trash remain row actions rather
than adding another toolbar or window.

The switcher exposes activation, Rename, and Move to Trash as VoiceOver actions with the actual note
title. Its hover buttons are hidden from accessibility so those actions are announced once. See
[features/notes.md](features/notes.md).

---

## The edge dissolve

Source: `DesignSystem/Scrolling/EdgeDissolve.swift`.

The signature effect. A scroll-driven `LinearGradient` mask on each list so rows soften as they approach
a floating bar, ghost beneath it, and vanish only at the window edge. Attach with `.edgeDissolve()` on
the `ScrollView`, **before `.thinScrollbar()`** (so the scrollbar overlay stays unmasked).

- Fade bands: top = `headerHeight + headerPadding + 32`, bottom = `bottomBarHeight + 28` — each overshoots its bar into the visible list, so the ramp finishes ~32/28px _past_ the bar rather than cliffing at its edge.
- Alpha floors mid-scroll (not to 0): **top 0.15, bottom 0.25**, eased by how much content is hidden past the edge (`1 − (1 − floor)·clamp(dist/band, 0, 1)`).
- Only masks when the list is scrollable; the edge stop stays transparent so rubber-band bounces still dissolve. A list that fits gets no mask.
- The mask spans the scroll view's **full** frame (`.ignoresSafeArea()`) — otherwise the bars' safe-area insets shift the gradient onto at-rest rows.

**Palette only.** Every one of its call sites is a palette screen, and the bands above are measured
against the palette's bars. A Settings list underlaps nothing, so it uses `.overflowFade()` instead —
and so does the Notes switcher, whose search row is a sibling in a `VStack`, not a floating bar.

---

## The overflow fade

Source: `DesignSystem/Scrolling/OverflowFade.swift`.

The counterpart for any list with no bars over it — the Settings lists and the Notes switcher — and
deliberately a separate type: sharing one modifier would tie such a list to geometry that only means
something under a bar. Attach with `.overflowFade()` on the `ScrollView`, before `.thinScrollbar()`,
same as the edge dissolve.

- **Bottom only.** Nothing sits over the top of these lists; fading the first row reads as "this one can't be chosen", which in a list of checkboxes is a lie.
- Fade band: a flat **24px**, borrowed from no bar because there is no bar.
- **No alpha floor.** The fade is purely an affordance for content past the edge, so it eases in with how much is hidden and clears completely once the list rests at the bottom.
- No `.ignoresSafeArea()`: a Settings list carries no bar insets to correct for.

---

## Rows, selection, hover

Source: `Launcher/UI/LauncherList.swift`, `Clipboard/UI/ClipboardView.swift`,
`FileSearch/UI/FileSearchList.swift`, `Uninstall/UI/UninstallView.swift`.

All lists share one row grammar so launcher and clipboard look identical:

- `HStack(spacing: lg)`: leading 24pt icon/thumbnail, title (`.body`, `lineLimit(1)`), optional trailing keycaps/kind label, `Spacer`. Insets: `.horizontal md`, `.vertical sm`.
- **The leading slot is always `Theme.Size.rowIcon`, whatever fills it.** A glyph smaller than an app icon — the uninstall list's 16pt checkbox — is centred _inside_ that 24pt slot rather than sizing the slot to itself. Every list then starts its title at the same x, so switching palette modes doesn't jog the column sideways. The slot doubles as the hit target.
- Background is a `RoundedRectangle(row, .continuous)` filled by `fill`: **selection → hover → clear**, in that precedence. This `fill` computed property is copy-identical across `AppRow`, `ClipboardRow`, `CalculatorCard` and `UninstallRow` — keep them in sync.
- **Hover state lives on the row**, not the list, so a mouse sweep repaints only the rows entering/leaving (a list-level hover rebuilds every row per move — don't do that).
- **Hover is armed by pointer movement, not by the pointer's position** (`armedHover`, `Palette/HoverArming.swift`). A palette shown under a resting pointer lights nothing, and keys or a scroll drop the highlight until the pointer moves clear of the slop radius around where it stood — a row must never light up because it *slid under* a still pointer. Two measured facts the rule rests on: SwiftUI fires hover phases for rows arriving under a stationary pointer, but **not** for a lit row that merely shifts, so `PaletteState.hoverDisarmToken` clears what is already lit; and a wheel gesture ends with a mouse-moved event carrying no displacement, so *event type is not evidence the pointer moved*. `Tests/hover-arming-test.swift` pins both halves.
- **Scroll moves only on keyboard nav/reset**, driven by a `ScrollIntent` (`DesignSystem/Scrolling/ScrollIntent.swift`) — mouse selection targets a visible row and never yanks scroll. `.top` scrolls to the origin anchor that `scrollOriginAnchor()` installs — a zero-height overlay applied to the scrolled content _after_ its padding, so it marks offset 0 without joining the layout and the restored origin is exact (targeting the first row instead leaves the top padding hidden under the header); it is restated when the header's inset settles after mount, which moves the resting offset. A `.follow` that lands on flat index 0 restores the origin instead, so that row's section header comes back into view. One intent state serves every mode — they never coexist.
- **`.follow` is an invariant, not a command** (`scrollFollowsSelection`, `DesignSystem/Scrolling/`). Each list marks its selected row with `selectionFrame(_:)`, and the modifier keeps that row inside the band between the floating bars, re-checking as the geometry and the row's frame settle, then **stops watching the moment the row is inside**. That self-release is what keeps it safe: once a keystroke has landed nothing is observing, so a wheel scroll — or a scrollbar-thumb drag, which `onScrollPhaseChange` cannot see at all — is never pulled back. Two measured facts it rests on: `frame(in: .scrollView)` reports the *inset-excluded* space, so the band is simply `0…containerSize.height`; and SwiftUI's minimal scroll-to-visible counts the strip behind the bottom bar as visible while its *destination* math respects the insets. Hence the split — Tinycast decides **whether** to scroll (`SelectionReveal`, pure, pinned by `Tests/scroll-reveal-test.swift`) and SwiftUI performs the move with an explicit `.top`/`.bottom` anchor. Scroll far by hand and the lazy stack drops the selected row, so there is no frame to measure at all: the fallback brings it back by id and the invariant, still standing, re-checks the moment it reports — which is why arrowing after a long mouse scroll lands the selection on screen rather than moving it out of sight. A one-shot `scrollTo` here left the highlight stranded under the pill whenever the target row's layout was not yet known, with nothing looking again until the next key press.
- **Keycaps** use `KeyCapChip`: `.outline` (white-0.20 border) for hotkey hints on rows, `.filled` (white-0.10 fill) for footer shortcuts.

### Section headers

All six palette lists (App Launcher, Clipboard, Emoji, File Search, Calculator History, Uninstall) render category labels
through one shared **`SectionHeader`** (`.subheadline.medium`, secondary — `Features/Launcher/UI/SectionHeader.swift`).
The launcher shows a single "Results" header over search matches, and per-kind sections
(Favorites / Applications / System Settings / Commands) for the empty query; clipboard/history use
date buckets (Today / Yesterday / …), and the clipboard adds a "Pinned" section above them holding
every pinned entry (filtered searches included).

Spacing lives in `Theme.Spacing`: `sectionHeaderBottom` (header → first row) and `sectionSpacing`
(gap above every header **except the list's first**, which reads as the previous section's closing
padding). Each list passes `isFirst: row.id == <rows>.first?.id` so only the very first row skips the
leading gap. Headers are non-selectable display rows, so selection (keyed by id) is unaffected.

---

## Liquid Glass

Source: `Theme.frosted(in:)`, `DesignSystem/PopoverMenu.swift`.

Glass is **only** for floating controls, never the main surface.

- `View.frosted(in:)` = `glassEffect(.regular.interactive().tint(glassFrost), in:)` + `.tint(.clear)` — interactive lensing with a whitish frost tint (`glassFrost`) so the glass reads brighter than clear. Used on the action-group capsule, the menu circle, `PopoverMenu` and a dialog's buttons — always _inside_ a window that already has a `VisualEffectView` behind it. Neither HUD uses it: on a panel of its own, glass has no backdrop to lens and falls back to an opaque backing that reads as a dark edge, so both take the panel recipe instead (see "Dialogs & HUD"). Tune the frost amount via the `glassFrost` token, not per call site.
- **Menus are in-window overlays, not system popovers.** `.contextMenu`/`NSMenu` stall clicks for seconds inside a `LazyVStack` and spill outside the panel. Use `PopoverMenu` anchored to a corner via `.overlay`, inset `menuInset` (8pt) so its own corner isn't clipped by the panel's. A menu hung off a control instead of a corner — the clipboard type filter, `.topTrailing` — insets by that control's own metrics so their edges line up.
- **A menu's `width` is fixed, never intrinsic**, so it can't jitter as its rows change: `menuWidth 276` by default, or a token of its own where that reads too wide (`clipboardFilterMenuWidth 200`).
- **`PopoverMenu`** uses `glassEffect(.regular, in: RoundedRectangle(menuPanel 16))` with **no hand-tuned shadow** — Tahoe glass carries its own elevation; adding a drop shadow reads heavy and non-native.
- `PopoverMenuRow`: leading glyph, label, trailing shortcut glyph, `menuHover` fill on hover, `menuRow 10` corner. Menus animate in with `.opacity + .scale(0.96)` from the anchored corner, `easeOut 0.14`.
- The glyph is a `PopoverMenuIcon`: `.symbol` (SF Symbol, `hierarchical`, secondary — or **red** when `isDestructive`) or `.file` (a real app icon via `IconCache`, used by the paste rows to show the paste target). `PopoverMenuItem` keeps a `systemImage:` convenience init, so symbol rows read exactly as before.
- **Both glyph kinds share one square `menuIcon` (20) slot**, which is what makes symbol and app-icon rows read as the same size and pins a single row height. 20 is deliberately larger than the artwork looks: an `IconCache` icon paints only ~85% of its canvas (13pt visible at a 16pt slot), while a `.body` SF Symbol renders 17–18pt tall — at 20 the icon lands on 17pt and the two match. Measure before changing it.
- Menu rows are the one place that uses `sm` for the icon→label gap instead of the row-standard `lg`, because that slot's built-in slack already contributes 2–3pt of apparent space.

---

## Dialogs & HUD

Source: `Windows/Dialog/`, `Windows/HUD/`.

Tinycast owns its dialogs; `NSAlert` is never used. `DialogController` is owned by `AppCore` (the
sole owner rule) and is the only presenter, so every confirmation in the app looks and behaves alike.

- **Three independent axes.** The **icon** says _what_, the **tone** says _how serious_, the **button
  role** says _what happens if you click_. None of them derives another — that separation is the
  whole point of the design, and collapsing any two of them back together is a regression.
- **Icon.** `DialogRequest.symbol` is required and is always the subject's own glyph: a system
  command passes its `SystemAction.sfSymbol`, so the Restart dialog shows `arrow.clockwise` and
  Empty Trash shows `trash.slash` — the same glyph as the launcher row the user just activated.
  Custom commands use `terminal`, the backup flows `square.and.arrow.up` / `.down`. Symbols render
  through `SymbolImage` (`DesignSystem/SymbolImage.swift`), never raw `Image(systemName:)`, because some
  catalog symbols are bundled template assets rather than SF Symbols — `toggleBluetooth` ships its
  own artwork since the logo is a SIG trademark, and a raw `Image(systemName:)` draws nothing for it.
- **Tone.** `DialogTone` is `.neutral` (secondary gray), `.success` (green) or `.danger` (red), and
  it tints the leading glyph and nothing else. `.neutral` stays gray rather than system blue on
  purpose, since a hue here should mark a state the way the other two do, not decorate an otherwise
  neutral message. There is no separate warning-vs-error case: both read equally severe and were
  only ever told apart by the icon's shape, which the action-derived icon now owns.
  `MessageHUDController.show(message:tone:)` (the pill; see below) takes the same `DialogTone` for its
  status dot, so the pill and the dialogs speak one tint vocabulary even though they render it
  differently. `AppCore` derives a system action's tone from `SystemActionFeedback.isNoOp`, so
  "Trash Emptied" reads `.success` and "Trash Is Already Empty" reads `.neutral`, rather than every
  pill defaulting to the same green dot regardless of whether anything happened.
- **Button role.** `DialogAction.Role` colors the label: `.standard` `Color.primary`, `.destructive`
  `Theme.Colors.destructive`, `.cancel` `textSecondary`. Because role is independent of tone, a
  red-glyph security warning can carry a plain white button — "Import executable commands?" does,
  since importing a file destroys nothing — and running a shell command the user wrote themselves is
  `.neutral` + `.standard` rather than a red alarm.
- **Surface.** A dialog reuses the palette's recipe `black panelDimming` → `VisualEffectView()` →
  `clipShape(RoundedRectangle(dialog 20))`, in that order at `dialogWidth 420`. Glass is reserved for
  the buttons, matching the "glass only on floating controls" rule. The **volume HUD takes the same
  recipe**, and so does the **message pill**. That is the line: glass needs a backdrop to lens, so it
  only works _inside_ a window that already has a `VisualEffectView` behind it — the action capsule,
  the menu circle, `PopoverMenu`, a dialog's buttons. On a bare borderless panel of its own it falls
  back to an opaque backing that shows as a dark edge outside the shape, which is exactly what the
  pill did before it moved to the recipe.
- **Layout.** Leading glyph (`dialogIcon 32`), title (`.headline`) + wrapped secondary message,
  optional volume slider, then buttons at the trailing edge with **Cancel rendered leading** among
  them, matching macOS convention. `DialogView.visualOrder` reorders only the display;
  `onChoose(index)` still dispatches against `DialogRequest.actions`' original order, so a caller
  never has to think about layout position when it builds a request.
- **Keys.** `DialogPanel.sendEvent` intercepts Esc and ↵ directly instead of relying on SwiftUI
  `onKeyPress`, so the keys work without anything inside the dialog holding focus. Buttons don't print
  a key cap; hovering one shows a `Tooltip` (`DesignSystem/Tooltip.swift`) with the cap the panel actually
  handles (`↵`, `esc`), styled like the palette's own `KeyCapChip` but hover-triggered instead of
  always-on, so a shown cap can't drift from behavior. **↵ runs the dialog's primary action; Escape
  cancels**, on every dialog including destructive ones.
  Arrow keys walk the volume slider along the same 5% grid the volume commands use (`DialogPanel`
  reports `.increment` / `.decrement` and `DialogController` applies `VolumeLevel.stepped`, so the
  panel never learns what a volume step is); click-away resolves as a dismissal.
- **Async, not modal.** Presentation is `async` (`withCheckedContinuation`), so there is no nested run
  loop. A held hotkey can't stack dialogs: while one is up, a second request resolves immediately as a
  dismissal — which is why the old `isConfirmingCommand` re-entrancy flag is gone. The guard is keyed
  on the live continuation, not on the panel, so a dialog still fading out can't swallow the next one.
- **Entrance and exit — `DesignSystem/Interaction/PanelTransition.swift`.** Every borderless surface arrives the same
  way, so dialogs and HUDs read as one gesture. `NSWindow.fadeIn` animates the _window's_ alpha over
  `Duration.enter` (0.18s) — the window, not just the content, so the drop shadow arrives with the
  surface instead of snapping in ahead of it — while `View.panelEntrance()` scales `0.94 → 1` over the
  same beat. Scaling _up_ inside the measured frame leaves `fittingSize` untouched and clips nothing,
  which is why this is a SwiftUI `scaleEffect` rather than a `CALayer` transform fighting
  `NSHostingView` over `anchorPoint`. `invalidateShadow()` runs on completion, since the shadow is
  cached from the scaled-down first frame. `fadeOut` (`Duration.exit`, 0.12s) is interruptible: its
  handler hides the window only if the alpha is still 0, so a `cancelFade()` from a re-show can't be
  undone by the fade it replaced. For a dialog the continuation resumes **first** and the panel fades
  afterwards, so confirming Restart is never held up by an animation. The pill fades without the
  scale — a growing capsule reads bouncy.
- **Non-activating**, like the palette: the dialog takes key focus for its own keys without pulling app
  focus off whatever the user was in. It sits at `.modalPanel`, above the palette's `.floating`, and is
  centred on the **cursor's** display with the same slight optical lift the palette uses.
- **`VolumeSlider`** is hand-drawn (track `volumeTrackHeight 6`, knob `volumeKnob 16`, `controlSurface`
  rail under a white-0.85 fill) with a monospaced-digit percentage in the same `volumeReadout 38` slot
  the HUD uses, so the track doesn't resize between `0%` and `100%`. A click anywhere on the track jumps
  the level; the arrows walk the 5% grid.
- **`VolumeHUDController`'s box** is the readout for the volume/mute commands, since macOS only
  draws its own HUD for real media keys and a CoreAudio change would otherwise be silent. It exists
  because a level needs an actual bar and number, not a one-line message: speaker glyph
  (`dialogIcon 32`, neutral `Color.primary` — a level isn't a success/warning statement), the bar, then
  the level as monospaced text beside it, in a fixed `volumeReadout 38` slot so the track can't resize
  as the number runs 0% → 100% — the same trick `VolumeSlider` uses, since the two now read as one
  control in two places. That slot is measured, not guessed: 38 is the widest string it ever holds
  ("Muted", 36pt in `rowTrailing`) plus a hair, because every point of slack is subtracted straight off
  the track. Fixed `hudWidth 200 × hudHeight 100`, with **asymmetric padding** — `xxl` 20 vertical,
  `xl` 12 horizontal — since 20pt of side padding costs a fifth of a 200pt box where the same token on
  a 420pt dialog costs a twentieth, and the bar is the content here.
  Muted prints `Muted`, not `0%`: the bar is already empty, so a
  number would either contradict it or hide the level the user comes back to. Auto-dismisses after
  `Duration.volumeHUD` (1.6s); a repeat command updates the shared `VolumeState` and calls
  `HUDPresenter.extend()`, so the bar slides to its new value in place instead of replaying the
  entrance.
- **`MessageHUDController`'s pill** is every _other_ transient
  confirmation: Custom Commands and Snippets confirming a run, and every system action whose effect
  is invisible (`Trash Emptied`, `Hidden Files Shown`, `Bluetooth Off`). One capsule shape, sized to
  its message (`hudMaxWidth 420` ceiling), clipped to a `Capsule()`, with the message first and a
  filled glyph trailing it: `checkmark.circle.fill` green for `.success`, `exclamationmark.circle.fill`
  red for `.danger`, `info.circle.fill` secondary for `.neutral`. **Here the glyph is the tone** — the
  one place that's true, because a pill has no subject to name the way a dialog does; the message
  already says what happened ("Trash Emptied"), so the icon only has to say how it went. The mapping is
  `fileprivate` in `MessageHUDView.swift` precisely so nobody can reach for it when building a
  `DialogRequest`, where the icon rule is the opposite. It trails rather than leads because a pill is
  read left to right and the outcome is the last thing you want to land on. Auto-dismisses after
  `Duration.messageHUD` (2.4s) — longer than the volume box, since a sentence needs reading time and a
  level only needs a glance — and a repeat call replaces rather than stacks.
- **`HUDPresenter`** is what keeps those two controllers from duplicating each other: one panel at a
  time, replace rather than stack, fade in, sit out its dwell, fade away, centred horizontally on
  a screen. The two HUDs differ only in their content, their anchor (`edgeInset(hudEdgeOffset 48)` for
  the pill, `heightFraction(0.12)` for the box) and how long they dwell — so those are the presenter's
  three arguments. **It sizes its window from a local, never from `host.frame` after attaching the
  content view**: assigning a content view resizes it to the window's current content rect, which is
  zero on a fresh panel, and a zero-width window "centers" with its leading edge on the screen's
  midline — visible only on the session's first HUD, which is what makes it easy to miss. Add a
  third HUD by constructing another presenter, not by teaching an existing controller a second shape.

## Scrollbars

Source: `DesignSystem/Scrolling/ThinScrollbar.swift`.

Custom thin overlay scrollbar (the native one flashes and reserves a gutter inside a transparent panel).
`.hideNativeScrollers()` on the scroll _content_ forces the backing `NSScrollView` to a hidden `.overlay`
style; `.thinScrollbar()` on the scroll view draws a hairline thumb (`Color.primary` alpha 0.30 rest →
0.42 hover → 0.5 drag) that fattens on hover, with a faint rail revealed only while hovering/dragging.

Routing: the palette lists (App Launcher, Clipboard history, Emoji, File Search, Calculator history) use
`.thinScrollbar()` + `.hideNativeScrollers()`; the Clipboard preview (right pane) and every Settings
pane take the native scroller as-is. Don't reintroduce native scrollers on the palette lists.

**Native scrollers are overlay app-wide, set once.** `AppDelegate.applicationWillFinishLaunching`
writes `AppleShowScrollBars = WhenScrolling` into Tinycast's own defaults domain, which outranks the
global one. Under the system's "Automatic" setting AppKit otherwise switches every scroll view to
thick legacy scrollers the moment it sees a mouse — a scroll view is born overlay and flips ~half a
second later, which read as a thick bar flashing at the right edge of each pane. There is no
per-scroll-view shim: chasing that flip after the fact is what caused the flash.

---

## Settings

Source: `DesignSystem/SettingsComponents.swift`.

Settings runs in its own resizable `NSWindow` (the SwiftUI `Settings` scene is unreliable for accessory
apps) with real traffic lights and a lifecycle wholly its own. It does not share the palette's look: **every pane is a stock
`Form` with `.formStyle(.grouped)`**, so the cards, headers, row insets and hairlines are all
system-drawn and a pane reads exactly as macOS System Settings does.

- **A row is a stock control.** `LabeledContent`, `Toggle` or `Picker`, each with a two-view label —
  the first view is the title, the rest become the secondary subtitle. Never a hand-built `HStack`
  with its own padding.
- **A row with a custom trailing control uses `SettingsRow`, not `LabeledContent`.** `LabeledContent`
  wraps its value in a selectable text field, which swallows the taps a `ShortcutRecorder` needs —
  the recorder renders but never starts recording. Stock `Toggle`/`Picker`/`Button` trailing content
  is unaffected.
- **`.settingsEnabled(_:)`, never a bare `.disabled(_:)`.** It dims as well as disables, so a
  switched-off row reads as unavailable rather than merely unresponsive.
- **A group is a `Section`**, with `header:` for its name and `footer:` for the caption that used to
  ride under the last row.
- **The pane's own title is not in the pane.** `SettingsToolbarController` puts it in the titlebar,
  seated in the detail column by `.sidebarTrackingSeparator`.
- `SettingsComponents.swift` holds only what more than one pane needs: **`SettingsRow`**,
  **`FeatureSwitchSection`** (a feature's master switch plus its launcher-visibility companion) and
  **`SettingsFilterField`** (the filter row above a long list). `Onboarding/OnboardingCard.swift`
  keeps the older hand-drawn card, which that window still uses.
- **A `Form` realizes every row it is handed.** `LauncherItemsSection` therefore holds its items in
  a `LazyVStack` inside one Form row — 400 apps cost 55 ms and 69 views that way against 750 ms and
  2040 eager. Any other unbounded list must do the same.

### The shortcut recorder callout

`ShortcutRecorder` is a **120pt** field showing only the binding — a combo's modifiers collapse into
one cap (`HotKeyBinding.compactKeycaps`), so any shortcut fits in two chips. Recording is narrated by
`ShortcutRecorderPopover`, a small **132 × 82** callout above it: caps, one label line, an `esc` cap in
the bottom-right corner. Three states in one fixed frame — prompt (`⌥ A` at half opacity, "Type a
shortcut"), live held modifiers, and conflict (rejected caps + owner, orange).

- **An ancestor draws it.** The open recorder publishes its bounds via `ShortcutRecorderAnchorKey`;
  `.shortcutRecorderPopoverHost()` sits on `SettingsDetailView` — one host above every pane's
  `Form`, and on `OnboardingView`. An overlay on the row would be clipped by the scroll view.
- **`shortcutPopover.width` is load-bearing.** The callout centres on the recorder only while it
  fits either side of it; wider than that and the clamp kicks in and skews the caret.
  `Tests/callout-test.swift` pins this.
- **One glass shape.** `CalloutShape` (`HotKeys/UI/`) draws body and caret as a single path so `glassEffect`
  lenses them together. The caret is two straight edges meeting at an arc — a rounded-tip triangle,
  not a dome. Stock `.regular` glass, no hand-tuned shadow, as in `PopoverMenu`.
- **Placement is pure.** `CalloutPlacement` (`HotKeys/UI/`) picks above-vs-below, clamps, and walks the caret;
  the harness compiles it against the real `Theme` so a retuned token can't outdate the assertions.
- **`KeyCapChip.Scale`** is `compact` / `standard` / `hero` — three tokenised sizes, no stray frames.
- `allowsHitTesting(false)`: clicks fall through to the capture session's mouse monitor, which closes it.

The calculator's inline `CalculatorCard` reuses this card language (`cardFill` + `cardStroke`) rather than the row language, since it's a highlighted answer, not a list item. A value answer is a **two-column** layout: a source column (input echo) and a target column (result), separated by a centered `arrow.right` glyph (no divider line). Each column optionally carries a word-name **badge pill** beneath its value (`keyCap` font, `controlSurface` fill, `keyCap` radius) — `Expression`→`Result` for scalar arithmetic, unit or currency names for typed results (`Expression`→`Kilograms`), and moment labels for a date/time calc (`12:18 AM`→`9:00 AM`, `Friday, 24 July`→`Friday, 9 April, 2027`). A trailing operator keeps the last complete result and its badge visible while the next operand is being typed.

---

## The palette search field

Its placeholder is drawn by Tinycast, not by the field's `prompt` — an `NSTextField` renders a prompt
through either its cell or its (one point taller) field editor, so a real prompt steps vertically when
focus moves. Don't reintroduce `prompt:` on that field. See
[features/palette.md](features/palette.md#the-placeholder-is-tinycasts-not-the-fields).

## Rules for agents working on the UI

- **Restyle from screenshots, not extracted CSS.** Pixel-matching Raycast from its bundle led to wrong results before; compare rendered screenshots over a light desktop instead. There's no screen-recording from the shell here — verify AppKit rendering with a `swiftc` harness that prints layer state, and let the user do visual sign-off.
- **Don't add behavior that wasn't requested.** A restyle changes appearance, not interaction — keep selection/scroll/dismiss/focus flows exactly as they are unless the task is about them.
- **New tokens go in `Theme`**, referenced everywhere. No magic numbers in views.
- **Keep the shared grammar shared.** If you change row insets, the `fill` precedence, section-header style, or keycap style, change it for _all_ lists — divergence is the bug, not the feature.
- **Build & verify** with the real toolchain (see [`development.md`](development.md)); a design change that doesn't compile under Swift 6 mode isn't done.
