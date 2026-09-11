# Menu Items Search

Menu Items Search is an on-demand palette screen for finding and running the frontmost
application's menu-bar items without touching the mouse — a port of Raycast 1.20.0's Search Menu
Items. It walks the app's menu bar once per show, filters the frozen snapshot as you type, and
presses the chosen leaf. It is reached from the built-in Search Menu Items launcher command or its
own global shortcut, which ships unbound. There is no feature switch: the command is always present.

## Invariants

- **The target is the frontmost application, frozen at open.** `show` captures the target once;
  activation re-resolves against it and never retargets, and there is no app picker.
- **The main menu bar only.** No menu extras, Dock menus, or contextual menus; an accessory or
  background app gets the menu-less empty state rather than a walk.
- **Only enabled, visible, pressable leaves become rows.** A parent opens its submenu and is never
  emitted, and a collapsed submenu with no exposed children is accepted as missing coverage rather
  than forced open. Two leaves sharing an exact path keep the first row only, since the palette
  needs one row per id.
- **The snapshot is a value: one walk, then in-memory filtering.** The walk runs off the main
  thread with the same 20-level, 4,000-item, 1-second bounds, so the palette opens instantly and
  rows publish when the walk lands; a superseded walk never publishes. Every cap truncates
  silently — the palette never explains a partial menu. Filtering afterwards reuses the
  launcher's fuzzy tiers with the leaf title primary and the menu path as signal.
- **Activation is `AXPress`-only.** The leaf is re-resolved by path at press time and re-checked
  actionable before pressing; there is no keyboard-shortcut fallback. Dismiss, reactivate, resolve,
  press — in that order, after the Accessibility gate.
- **The Accessibility gate runs on show and on activate.** A denial reports through the dialog
  controller with an Open Settings recovery, never a system alert.
- **No new `AppEntry.Kind`, no visibility gate, no frecency.** Menu rows are query-driven like file
  results: they never learn ranking and never take a Settings pane beyond the automatic Commands row.
- **Everything under `Model/` stays Foundation-only and pure.** `menu-search-test` compiles the
  shipped `Model/` files with the existing fuzzy scorer, plus the `Service/` session. The AX reader
  itself is compile-covered only — it needs a live app and must never be asserted in a harness.
- **Hiding the palette resets the session**, so the snapshot returns to baseline with the window.

## Snapshot path

`AXMenuAccess` recurses the bar's `AXChildren` without opening anything, matching no roles and no
titles — structure only, so the walk is language-independent by construction. Each element gets a
0.2-second messaging timeout and the whole walk shares the deadline, checked per node so an abort
propagates level by level. The reader emits plain `MenuTreeNode` values; `MenuSnapshotPolicy`
decides depth, caps, eligibility, and order from there.

Shortcut glyphs decode `AXMenuItemCmdChar` plus `AXMenuItemCmdModifiers`: bit 0 is Shift, bit 1 is
Option, bit 2 is Control, and ⌘ is implied. The character arrives as its own display glyph,
including special keys. Higher modifier bits mark keys outside ⌘ chords and degrade to path alone
rather than render a wrong chord, and a missing character carries no shortcut at all.

Resolving mirrors the snapshot walk level for level — blank titles skipped the same way — so a
displayed row always resolves to the element the snapshot saw, or to nothing when the menu moved on.

## Palette and actions

`MenuSearchScreen.rows` is the session's filtered list: the query change filters once and the
screen reads the stored rows back, so one keystroke ranks once no matter how often the list
renders. An empty query browses the whole menu, a typed one ranks it, and a query typed while the
walk is still in flight applies the moment it lands. The list names the captured app in its
section header, and a row shows the leaf title, the full menu path, and the shortcut glyph when
the walk decoded one. The self, menu-less, and missing-app targets each have their own empty
state, an in-flight walk says "Reading menu…", and an empty filtered list names the app it found
nothing in.

Return calls `MenuSearchCoordinator.activate`, which hides the palette without restoring focus,
reactivates the frozen app, and presses. A quit target, an unresolvable leaf, or a failed press
each report through Tinycast's own dialog or notice — the failure copy names the item and says the
menu moved, never why AX said no.

## Invocation

`CommandID.searchMenuItems` carries the row: its `hotKeyAction` answers `.command` automatically,
so the chord is bindable from the Shortcuts pane with no default binding. `runCommand` funnels both
the row and the chord into `MenuSearchCoordinator.show`, and Tab out of the screen carries the query
back to the launcher like every other sub-screen.
