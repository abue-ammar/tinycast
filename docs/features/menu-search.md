# Menu Search

`Search Menu Items` opens the frontmost app's main menu bar as a palette screen, so any menu item can
be found by name and pressed without walking the menus. One cold accessibility walk fills a snapshot,
ranking runs in memory over it, and activating a row re-resolves the live element and presses it.

## Invariants

- **The target is frozen at open, and activation never retargets.** `MenuSearchCoordinator.show()`
  captures `paletteCoordinator.targetApp` once, into `frozenApp`; `activate` re-resolves against that
  app, not against whatever is frontmost by the time the user hits ↵. There is no app picker, so the
  app named in the section header is the only app a row can ever reach.
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

## How it is put together

| Piece | Holds |
| --- | --- |
| `Model/MenuTreeNode.swift` | one node of the raw walk: title, flags, shortcut, children |
| `Model/MenuSearchItem.swift` | a flattened, pressable leaf — its id, display path and search fields |
| `Model/MenuSearchShortcut.swift` | the AX modifier bits and the glyphs a row's keycaps draw |
| `Model/MenuSnapshotPolicy.swift` | the flatten: the three caps, de-duplication, cancellation |
| `Model/MenuSearchQuery.swift` | ranking over `SearchRelevance`/`FuzzyMatch`, capped at 200 rows |
| `Model/MenuSearchTarget.swift` | the four cases a summon can land on, and their empty states |
| `Service/AXMenuAccess.swift` | every `AXUIElement` read: the walk, the path re-resolve, the press |
| `Service/MenuSearchSession.swift` | the observable state — walk lifecycle, snapshot, filtered rows |
| `UI/MenuSearchCoordinator.swift` | freezing the target and icon, activation, the failure reports |
| `UI/MenuSearchScreen.swift` | the `PaletteScreen` conformance and the empty-state switch |
| `UI/MenuSearchList.swift` | the list and its row: app icon, title, path, keycap chips |

`MenuSearchTarget.classify` splits a summon four ways — `searchable`, `selfTarget`, `menuLess` and
`noApplication` — so each gets its own sentence instead of an empty list. `selfTarget` is checked
before the menu-bar test, because Tinycast runs as an accessory and would otherwise read as
menu-less.

`MenuSearchSession` takes its walk as an injected `WalkOperation`, which is what lets
`Tests/menu-search-test.swift` drive publication, supersession and cancellation without an AX server.

Ranking scores the title and the `File > Export As` display path together, but the path rides as a
`.owner` field rather than a name one: a hierarchy string is shared by every row beneath it, so
letting it match as a name would pull unrelated rows in.

Two AX details are worth knowing before touching `MenuSearchShortcut`. The modifier field is **not**
`NSEvent.ModifierFlags` — bit 0 is Shift, bit 1 is Option, bit 2 is Control, ⌘ is implied, and
anything above bit 2 is unrenderable, so the shortcut is dropped. And AX reports special keys as
private-use scalars (`0xF700`…) that no text font draws, so `displayCharacter` maps them to
`↑ ↓ ← → ↖ ↘ ⇞ ⇟`; without it an arrow-key row renders as tofu.

The list decodes exactly one `NSImage` — the frozen app's icon — and every row paints it, so a
4,000-row snapshot never costs more than one bitmap.

## Where it is reachable from

The launcher, as `CommandID.searchMenuItems`, so it takes aliases and a global shortcut like any
other command and ships unbound. It claims no `SettingsTab.ownedCommands` entry, so Settings ›
Commands owns its switch; it adds no `AppEntry.Kind` and no `VisibilityStore` category. Rows are not
`AppEntry`s, so there is no frecency and no learning — ranking is per-query only.
