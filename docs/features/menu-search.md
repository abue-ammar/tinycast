# Menu Search

`Search Menu Bar Items` opens the frontmost app's main menu bar as a palette screen, so any menu item
can be found by name and pressed without walking the menus. One cold accessibility walk fills a snapshot,
ranking runs in memory over it, and activating a row re-resolves the live element and presses it.

## Invariants

- **The target is frozen at open, and activation never retargets.** `MenuSearchCoordinator.show()`
  captures `paletteCoordinator.targetApp` once, into `frozenApp`; `activate` re-resolves against that
  app, not against whatever is frontmost by the time the user hits ↵. There is no app picker, so the
  app whose icon every row paints is the only app a row can ever reach.
- **The Apple menu is dropped by position, not by name.** `menuSearchShowsAppleMenu` ships **off**,
  and `MenuSnapshotPolicy.excludingAppleMenu` drops the menu bar's *first* item — the one slot macOS
  reserves for it — rather than matching a title that may localise. The flag is read once, in
  `show()`, and rides into `startWalk` beside the pid: a snapshot always answers the question the
  summon asked, whatever Settings says by the time the walk lands.
- **Sections are runs of the snapshot, never a regrouping.** While browsing, `MenuSearchList` cuts
  the rows into consecutive runs of one top-level menu; the walk emits a menu's leaves contiguously,
  so a run *is* a section. A query ranks across menus, so the list collapses to a single `Results`
  section instead. Either way the drawn order stays exactly `session.filtered`, which is what the
  palette's selection index counts — a `Dictionary`-based grouping would silently reorder it and
  make every row activate its neighbour.
- **The walk never opens a menu.** `AXMenuAccess` reads the bar cold. Opening submenus to index them
  would flash the target app's UI on every summon, so a submenu macOS has not built yet exposes no
  children and contributes no rows — accepted coverage loss, not a bug to fix by opening menus.
- **The snapshot is bounded three ways, and truncates rather than delays.** `MenuSnapshotPolicy`
  caps at `maxDepth` 20 levels, `itemLimit` 4,000 items and `perSubmenuLimit` 200 *direct* leaves per
  submenu; `AXMenuAccess.walkBudget` caps the whole walk at one second and `sweepTimeout` each
  element at 0.2 s, matching the window sweep. The per-submenu cap stops one History-like menu eating
  the snapshot and applies to direct leaves only — recursion into later parents always continues.
- **Only a pressable row is offered.** `MenuSearchItem.isEligible` keeps a leaf only when it is
  enabled, not hidden, not a separator, has an `AXPress` action and a non-blank title. `activate`
  re-checks the same thing on the live element through `isActionable`, because the menu may have
  changed since the snapshot.
- **Nothing outlives the show.** `hidePalette` and every mode change call `MenuSearchSession.reset()`,
  which cancels the walk task and drops both arrays. A superseded walk never publishes: `startWalk`
  bumps `revision`, and a landing walk that does not match it is discarded.
- **The walk runs off-main, and holds no actor state.** `AXMenuAccess` is a pure `enum` of static
  functions driven by `Task.detached` from `MenuSearchSession`. There is no second actor.
- **Accessibility is gated twice.** `Permissions.ensureAccessibility()` runs on show *and* on
  activate — a grant revoked while the palette is open must not reach `AXUIElementPerformAction`.
- **An excluded app is refused, never filtered.** `MenuSearchTarget.classify` answers `.excluded`
  from `AppSettings.menuSearchDisabledApps`, before the menu-bar test so an excluded accessory app
  does not read as menu-less, and `show()` starts no walk at all. Filtering a walked snapshot would
  still have read the menu, which is the whole thing the list exists to prevent.

## How it is put together

| Piece | Holds |
| --- | --- |
| `Model/MenuTreeNode.swift` | one node of the raw walk: title, flags, shortcut, children |
| `Model/MenuSearchItem.swift` | a flattened, pressable leaf — its id, display path and search fields |
| `Model/MenuSearchShortcut.swift` | the AX modifier bits and the glyphs a row's keycaps draw |
| `Model/MenuSnapshotPolicy.swift` | the flatten: the three caps, de-duplication, cancellation |
| `Model/MenuSearchQuery.swift` | ranking over `SearchRelevance`/`FuzzyMatch`, capped at 200 rows |
| `Model/MenuSearchTarget.swift` | the five cases a summon can land on, and their empty states |
| `Service/AXMenuAccess.swift` | every `AXUIElement` read: the walk, the path re-resolve, the press |
| `Service/MenuSearchSession.swift` | the observable state — walk lifecycle, snapshot, filtered rows |
| `UI/MenuSearchCoordinator.swift` | freezing the target and icon, activation, the failure reports |
| `UI/MenuSearchScreen.swift` | the `PaletteScreen` conformance and the empty-state switch |
| `UI/MenuSearchList.swift` | the menu sections and the row: app icon, title, path, keycap chips |

`MenuSearchTarget.classify` splits a summon five ways — `searchable`, `excluded`, `selfTarget`,
`menuLess` and `noApplication` — so each gets its own sentence instead of an empty list. `selfTarget`
is checked before the menu-bar test, because Tinycast runs as an accessory and would otherwise read
as menu-less; `excluded` is checked next, for the same reason.

`MenuSearchSession` takes its walk as an injected `WalkOperation` — `(pid, showsAppleMenu)` — which
is what lets `Tests/menu-search-test.swift` drive publication, supersession and cancellation without
an AX server.

Ranking scores the title and the `File > Export As` display path together, but the path rides as a
`.owner` field rather than a name one: a hierarchy string is shared by every row beneath it, so
letting it match as a name would pull unrelated rows in.

A row reads left to right — icon, title, then the path in secondary text — so the right edge carries
keycaps and nothing else. The path says only what the header has not: while browsing, the trail
*below* the section menu, which is empty for a direct child of it; while searching, the whole parent
path. The leaf title never rides along, because the row already draws it, and `MenuSearchItem`
joins every path on one ` → ` so the id, the row and the search field cannot drift apart.

Two AX details are worth knowing before touching `MenuSearchShortcut`. The modifier field is **not**
`NSEvent.ModifierFlags` — bit 0 is Shift, bit 1 is Option, bit 2 is Control, and ⌘ is implied *unless*
bit 3 clears it; only a bit above those four is unrenderable, so the shortcut is dropped. And AX
reports a non-typing key either as a control scalar (`0x1B` Escape, `0x08` Delete) or as a private-use
one (`0xF700`…), neither of which a text font draws, so `displayCharacter` names them instead:
`⎋ ⌫ ⇥ ↩ ⌤ ⇤ ␣ ⌦ ⌧ ↑ ↓ ← → ↖ ↘ ⇞ ⇟` and `F1`…`F35`. Without both, a chord renders as tofu, as a blank
chip, or not at all.

The list decodes exactly one `NSImage` — the frozen app's icon — and every row paints it, so a
4,000-row snapshot never costs more than one bitmap.

## Where it is reachable from

The launcher, as `CommandID.searchMenuItems`, so it takes aliases and a global shortcut like any
other command and ships unbound. It is one of the two commands **[Navigation](navigation.md)** owns
through `SettingsTab.ownedCommands`, so `navigationEnabled` is its switch rather than Settings ›
Commands; it adds no `AppEntry.Kind` and no `VisibilityStore` category. Rows are not `AppEntry`s, so
there is no frecency and no learning — ranking is per-query only.

The display name is `Search Menu Bar Items` while the raw id stays `command:search-menu-items`, which
is what keeps a recorded shortcut, an alias and a visibility flag pointing at the same command.
