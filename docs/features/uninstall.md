# Uninstall Application

Removes an app _and_ the files it leaves behind — caches, preferences, containers, saved state,
launch agents. Reached from the launcher's Actions menu (⌘K → **Uninstall Application**) on
any `.application` entry; it opens the `.uninstall` palette sub-screen scoped to that app.

## Invariants

- **Uninstall moves to the Trash and never deletes.** `FileManager.trashItem` is the only removal call in
  the feature; `removeItem` must never appear here. That is what makes display-name attribution
  tolerable — a false positive costs a drag back, not the user's data — so a "delete permanently" option
  would have to drop name matching in the same commit.
- **The deciding half stays Foundation-only and pure** for `uninstall-test`, with every environment fact
  injected: the scanner hands the rules directory **names**, never URLs, and hands the classifier a
  `PathFacts`.
- **`UninstallScanner` detects Full Disk Access and never requests it.** The probe is silent and
  promptless; this feature asks for no permission and never escalates privilege.
- **`tccRelativePrefixes` is measured, not assumed.** Probe a location by creating and trashing a
  throwaway directory there before adding it — *listing* is not the test. `~/Library/Containers`
  enumerates fine and still refuses the move, while `~/Library/Application Scripts` allows it.
- **A locked candidate can never enter the checked set.** That invariant lives in `UninstallSelection`'s
  one intersection, not in the view.
- **Discovery never waits on sizing.** `UninstallScanner.discover` publishes the list; the directory
  walks stream in behind it. Anything that makes the screen wait for a size — a spinner, a completeness
  gate on ↵ — puts the slow half back in front of the fast half.
- Tinycast refuses to plan its own uninstall, compared against the **running** identity so the Dev channel
  refuses itself too.

## Layers

Same split as `WindowManagement`: a pure half that decides, an impure half that touches the disk.

| File | Role |
| --- | --- |
| `Model/UninstallTarget.swift` | `UninstallTarget`, `UninstallEvidence`, `UninstallIdentity` — and every guard rail, applied in `UninstallIdentity.make` |
| `Model/UninstallSearchRoot.swift` | The root table (where to look, which styles are legal there) and `binDirectories` |
| `Model/UninstallRules.swift` | Matching, plus `isAcceptableCandidate` |
| `Model/UninstallProtection.swift` | `PathFacts` → `UninstallProtection` |
| `Model/UninstallPlan.swift` | `UninstallCandidate`, `UninstallPlan`, `UninstallSelection` |
| `Service/UninstallScanner.swift` | **Impure.** `discover` (`contentsOfDirectory`, `lstat`, `Permissions.hasFullDiskAccess`) and `measure` (the directory walks) |
| `Service/UninstallRunner.swift` | **Impure.** `trashItem`, and nothing else |
| `Service/UninstallSession.swift` | `@MainActor` lifecycle behind the screen |
| `UI/UninstallScreen.swift`, `UI/UninstallView.swift` | The palette screen, list, row and actions menu |
| `UI/UninstallCoordinator.swift` | The action surface — confirmation lives here, not in the runner |

The first five compile standalone into `Tests/uninstall-test.swift`, so they stay Foundation-only
and take every environment fact as a parameter. The scanner hands the rules **child names**, never
URLs, which is what makes "no filesystem access in the pure layer" structural rather than a promise.

## Attribution

Three match styles enabled per root by the table, plus a fourth mechanism for CLI launchers. The
first three run against
`UninstallRules.matchableForms`, which strips `.plist`, `.savedState`, `.binarycookies`, `.lockfile`
and friends — repeatedly, so `…​.plist.lockfile` reduces too.

**`bundleID`** — exact, or a namespaced child. The boundary check is load-bearing: a plain prefix
makes `com.apple.SafariTechnologyPreview` a match for `com.apple.Safari` and trashes a different
product's entire profile. Requiring the next character to be a separator means a match can only be a
namespace _descendant_ — `com.apple.iBooksX.CacheDelete` matches `com.apple.iBooksX`,
`com.apple.iBooksXtra` does not. Both `.` and `-` count, because `-` is how vendors name release
variants: `dev.zed.Zed-Preview.plist` belongs to Zed, unless Zed Preview is itself installed, in
which case the sibling rule below hands it straight back.

Two further guards on that rule:

- **Vendor namespaces don't prefix-match.** A two-component ID like `com.adobe` names a vendor, not a
  product, so `allowsBundleIDPrefixMatch` requires three components. `com.adobe` still matches itself.
- **An installed sibling owns its own artifacts.** If any _other_ installed app's bundle ID is a
  longer match for the same component, that app owns it. Without this, uninstalling `com.tinycast.app`
  would also trash `com.tinycast.app.beta` and `…​.dev` — separate products that merely share a
  namespace, which is exactly the channel-isolation invariant in reverse.

**`groupContainer`** — strips a leading `group.` and/or a 10-character Team ID (uppercase
alphanumerics only, which is what stops an arbitrary `something.com.foo.Bar` being read as a
container), then applies the bundle-ID rule to the remainder.

**`displayName`** — the weak one, and the only one hedged. Exact, case- and diacritic-folded equality;
never a prefix or substring, so "Books" and "Books Reader" cannot claim each other's folders in either
direction. On top of that a name must be ≥ 3 folded characters, must not be a standard Library
subdirectory name (`Preferences`, `Caches`, `Containers`, …), and **must not be shared with another
installed app** — a second app called "Mail" is precisely what makes `~/Library/Application Support/Mail`
unattributable. Three, not four, is the floor: Zed, IINA and Xee all name their own folders, and the
safety comes from those three guards rather than from length. Enabled in the human-named roots
(`Application Support`, `Caches`, `Logs`) and the plug-in wells; everywhere else a child is a bundle
ID by construction, so a name match there would be a false positive by definition.

A `.displayName` match **is** checked by default, and the row says "matched by name" so the weaker
evidence is visible before confirming. It earns that because the match is exact, confined, and never
claims a name another installed app answers to — and because the feature only ever moves to the
Trash, so an unwanted row costs a drag back rather than data.

**`binSymlink`** — a launcher in `/usr/local/bin`, `/opt/homebrew/bin`, `~/.local/bin` or `~/bin`
whose symlink resolves inside the app bundle. Attribution is by **link target, never by name**: `zed`
in `/usr/local/bin` is Zed's because it points at `Zed.app/Contents/MacOS/cli`, not because of what
it is called. On a stock Mac `/usr/local/bin` is root-owned, so the row renders locked; where
Homebrew has made it user-owned it is removable, and the classifier reaches that from the facts
without a special case.

`UninstallIdentity.make` returns `nil` — refusing the whole uninstall — when the target is Tinycast
itself, by bundle ID _or_ bundle URL, compared against the **running** identity so the Dev channel
refuses itself too.

### Roots

The **home directory itself is not a root**, and that is a decision rather than an oversight. Every
root lives under `~/Library` or `/Library`; nothing directly in `~` is ever a candidate. Claiming
`~/<name>` would rest on a name match, and `~` is the one place where a wrong match costs the user
their own work instead of an app's cache — VS Code's `CFBundleName` is literally `Code`, and `~/Code`
is a source tree on a great many machines. Narrowing it to dot-folders only moves the problem: an app
named "Local" would then claim `~/.local`, and screening for that needs a hand-kept blocklist with no
source of truth — the same reasoning that keeps slang out of `CalcCurrency.contested`. Measured
against 62 installed apps the entire root was worth one 115 kB folder, so it bought almost nothing
and carried the only catastrophic failure mode in the design. Raycast does list `~/OrbStack`; we
deliberately don't.

Immediate children only, everywhere. `Preferences/ByHost` is its own root rather than raising
`Preferences` to depth 2, which would descend into every unrelated app's subfolder. Beyond the
`~/Library` and `/Library` staples the table covers the plug-in wells — `QuickLook`, `Services`,
`PreferencePanes`, `Screen Savers`, `Internet Plug-Ins`, `Spotlight`, `Automator`, `Input Methods`,
`Audio/Plug-Ins/{HAL,Components}` — whose children are wrappers named after the product that
installed them, which is why `strippedExtensions` also drops `.qlgenerator`, `.saver`, `.prefPane`
and friends. `.app` is deliberately **not** in that list. Deliberately out of scope, and worth
keeping out: `/private/var/db/receipts` (root-owned, and deleting a receipt
corrupts the installer's view of the system), `~/Library/Keychains`, `/Library/Extensions`, and every
user-document location. `/usr/local` is reached **only** through `binDirectories`, and only for
symlinks that resolve into the bundle — never by name, and never recursively.

One root only yields under Full Disk Access:
`Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments`,
each app's recent-documents list, named `<bundle id>.sfl3`. Without the grant the listing itself is
refused, so the root contributes nothing rather than a locked row. `~/Library/Cookies` behaves the same.

`UninstallRules.isAcceptableCandidate` is belt and braces over whatever matched: an immediate child of
its own root, never the home directory or `/`, no relative components, and no overlap with the app
bundle (which is emitted separately).

## Locking

`UninstallProtection` is **advisory, not a security boundary** — TCC is evaluated at the syscall, so
it can be wrong in both directions. It exists to gray a row with an honest reason and to skip
obviously doomed attempts; `UninstallRunner` still reports per-item failure.

Precedence, asserted by the harness:

1. `!exists` → `.missing` (dropped from the plan)
2. `SF_RESTRICTED`/`SF_IMMUTABLE`, or a read-only volume → `.systemProtected` — this is what locks
   `/System/Applications/Books.app`, and it falls out of the facts rather than a hardcoded `/System`
   prefix
3. `UF_IMMUTABLE` → `.userLocked` (its own case: the user can clear it in Get Info)
4. a TCC-gated path without Full Disk Access → `.needsFullDiskAccess`
5. parent not writable → `.parentNotWritable`
6. sticky parent _and_ not owned by the current user → `.notOwned`
7. a directory the current user can't write → `.notWritable`
8. → `.removable`

Steps 5 to 7 are the whole permission story, and the order is deliberate. Removing a directory entry
is governed by write permission on the **enclosing directory**, not by who owns the item: a root-owned
file inside a folder you can write is yours to remove. Checking ownership first — as an earlier
revision did — grayed out rows that trash perfectly well. Ownership decides exactly one case, a
sticky parent (`S_ISVTX`, the `/tmp` rule), where only an owner may unlink.

A **directory** also needs its own write bit, because the trash moves it to a new parent and that
rewrites its `..` entry. This is what locks App Store and TestFlight bundles: they are
`drwxr-xr-x root:wheel` inside an admin-writable `/Applications`, so the parent check passes and the
move still fails with `EPERM` (#1634). The row says to drag the bundle to the Trash in Finder, which
asks for the password this feature never requests.

This is also why `/usr/local/bin/code` stays locked while `/opt/homebrew/bin/orb` does not:
`/usr/local/bin` is `drwxr-xr-x root:wheel`, so the trash is refused outright (measured, not
inferred), whereas Homebrew leaves `/opt/homebrew/bin` group-writable. Raycast offers the
`/usr/local/bin` row as checked; that removal cannot succeed without an administrator password, which
this feature never asks for.

A locked candidate can never enter the checked set. That invariant lives in `UninstallSelection`,
whose every mutation funnels through one intersection with `plan.removableIDs`, so re-scanning drops
a row that has since become locked for free.

The TCC list is **measured, not assumed.** A probe that creates and then trashes a throwaway
directory in each candidate location shows that `~/Library/Containers`, `~/Library/Group Containers`
and `~/Library/Cookies` refuse the move, and `com.apple.sharedfilelist` refuses even the listing, while `~/Library/Application Scripts` and
`~/Library/Autosave Information` allow it — which is why Books' five `Application Scripts` rows are
checkable while the five `Containers` rows beside them are locked. Note that _listing_ a directory is
not the test: both container roots enumerate fine and still refuse the trash. Re-measure before
adding an entry.

**Full Disk Access is detected, never requested.** The probe is `Permissions.hasFullDiskAccess()`,
shared with File Search: it opens the per-user `TCC.db`, then the system one at
`/Library/Application Support/com.apple.TCC/TCC.db`. TCC denies that read _silently_, with no prompt,
which is what makes it usable under the rule that this feature asks for no permissions. macOS 27 has
no per-user `TCC.db` at all, so a probe of that file alone reads every grant as "no access" and locks
every gated row — keep the system path. It runs once per scan, not once per candidate, and can only
under-report (a per-folder grant reads as "no access"), which just leaves a row locked. Settings ›
Permissions shows the same status and opens the Full Disk Access pane in System Settings; File Search
keeps its own access section. Granting access is optional for Uninstall and required for File Search.

Symlinks are never followed: `lstat`, and no descent when sizing. A symlinked candidate is judged and
trashed as the link.

## Sizing

The two halves of a scan differ by three orders of magnitude. Discovery is 36 parallel shallow
`contentsOfDirectory` listings plus one `lstat` per hit — milliseconds. Sizing is a recursive
enumerator walk per directory candidate, and `/Applications/Xcode.app` alone is ~9.5 GB. So they are
two calls, not one: `UninstallSession` publishes `.ready` the moment `discover` returns, then
`measure` streams each walk to a `@MainActor` sink that writes only the row it measured, via
`UninstallPlan.setSize(_:forPath:)`.

`UninstallCandidate.size` is optional, and `nil` **is** the pending state — which is why there is no
`needsWalk` flag and no side table of sizes. A pending row renders a blank size slot rather than a
dash or a spinner; the slot sits between a `Spacer` and the trailing icon, so a landed size expands
leftward and shifts nothing. Totals treat pending as zero and simply climb. The `≥` prefix stays
reserved for a walk that hit `SizeBudget.maxEntries`, so it never doubles as "still counting".

The consequence to accept: confirming inside the first second states a total lower than what gets
trashed. Everything selected is still trashed — only the number in the copy is early.

Sizes are **logical bytes**, not allocated blocks: `.totalFileSizeKey` in the walk and `st_size` in
`inspect`. Allocated blocks disagree with every other tool on the machine, badly. Xcode ships
decmpfs-compressed, so its blocks read 4.19 GB against Finder's and Raycast's 9.45 GB, and a
593-byte plist occupies one block and reads as 4 kB. Blocks are not the safer number either — a
decmpfs payload can live in an xattr, which `st_blocks` does not count, so they are only a floor.

`measure`'s task group is deliberately built in a `nonisolated` context. It is a structured child of
`UninstallSession.scanTask`, which is what keeps `cancel()` reaching `Task.checkCancellation()`
inside the enumerator loop, and building it there leaves no question about which executor 30
concurrent walks run on. A walk that throws yields nothing, so a cancelled row stays pending instead
of publishing a false zero.

## The screen

A `PaletteMode` case like Clipboard and Calculator History, so the back chevron, Escape,
bare-backspace exit, arrow nav and the menu-open input freeze all come from the shared contract (see
[palette.md](palette.md)). It does **not** join the Tab cycle. The search field filters candidates by
name or location; there is no sort control, and the footer's leading corner keeps the standard menu
circle. The primary pill is the one rendered in `Theme.Colors.destructive`.

↵ uninstalls, ⌘↵ toggles the highlighted row, clicking the checkbox toggles, double-clicking a row
toggles. ⌘K carries Uninstall, Select/Unselect File, Copy Path, Show in Finder and Show Info in
Finder. There is no launcher keybinding for Uninstall — it is a menu action only. Copy Path stays on the screen (losing a whole scan to copy one path is a bad
trade); the two Finder actions hand focus to Finder and so hide the palette. Show Info has no AppKit
route and drives Finder over Apple events, which raises the system Automation prompt on first use.

`UninstallCoordinator.performUninstall()` is the one funnel, so neither ↵ nor the menu row can skip the
confirmation. After confirmation it checks the selected copy again and **waits for it to exit** before
trashing anything — an app still quitting writes its saved state and preferences back behind the trash.
If it hasn't exited within `AppLauncher`'s grace period (a save sheet left standing), nothing is moved.
The wait checks `NSRunningApplication.isTerminated`, since workspace exit notifications exclude
background and menu-bar apps. It then trashes, and **only clears the app's hotkey, favorite, visibility
and ranking when the bundle itself went** — a leftovers-only cleanup leaves the
app installed. The bundle is trashed last: either order can leave a partial state, but with the
bundle still in place the user can re-run the uninstall to retry, and once it's gone the launcher
entry that reaches this screen is gone with it. Success shows the message pill; partial failure names
what stayed behind.

## Tests

```sh
./Scripts/run-tests.sh uninstall-test
```

No filesystem, no temp directories — every input is a `String` or a `PathFacts`. `testStreamedSizes`
covers the half a walk cannot: a landed size never reorders the plan, never disturbs a neighbour's
pending state and never re-derives the checked set. Beyond the per-rule
assertions it ends with a cross-identity sweep: for a set of realistic apps × every root × every
artifact shape, no app's artifacts may ever be attributed to another. That is the one test that
catches a regression in the matcher as a whole rather than in a single rule.
