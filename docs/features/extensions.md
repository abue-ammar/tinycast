# Raycast extensions

Tinycast runs Raycast extensions: the same `package.json` + prebuilt CommonJS bundles Raycast itself
produces, rendered natively into the palette. No Electron, no browser, no Node.js.

- [How it works](#how-it-works) · [The JS runtime](#the-js-runtime) ·
  [The Swift host](#the-swift-host) · [Rendering](#rendering)
- [Turning it on](#turning-it-on) · [Installing extensions](#installing-extensions) ·
  [Registries](#registries) · [Shortcuts](#shortcuts) · [What's supported](#whats-supported) ·
  [What isn't](#what-isnt-supported-yet) · [Working on the runtime](#working-on-the-runtime)

## Invariants

- **Exactly one command runs at a time, in its own `JSContext`.** Starting a command stops the previous
  one and discards the whole context (`ExtensionRuntime.shutdown()`); the next launch boots a fresh one.
  Never cancel timers globally to "clean up" instead — React's scheduler commits through `setTimeout`,
  so that wedges every later session. Host calls carry no session id, so
  `ExtensionManager.activeExtensionName` is what namespaces storage, cache and preferences; a second
  concurrent session would need a session id threaded through the bridge first.
- **`ExtensionRuntime`'s `@unchecked Sendable` is load-bearing.** Every `JSContext` / `JSValue` touch
  happens on its private serial queue, and only plain `Sendable` values (`RenderValue`, `RenderTree`,
  JSON strings) cross in or out. Keep that boundary.
- **`Resources/RaycastRuntime.generated.js` is emitted by `Scripts/raycast-runtime/build.mjs`** and
  committed — never edit it by hand; change `Scripts/raycast-runtime/src/` and rebuild.
- **`ExtensionScreen` is the only place extension row order is decided**, so the flat palette selection
  keeps matching the visible rows — the same invariant every other palette screen holds.
- **Off means off.** `extensionsEnabled` is opt-in, and `ExtensionManager.setEnabled(false)` stops the
  running command, discards the JS context, empties the installed set and clears the launcher rows;
  `refresh()` returns early while it is off, so nothing is scanned and nothing is held. Enabling is also
  consent to run third-party code, so it confirms first and never rides a settings backup.
- **`SymbolCatalog` reads a system bundle, not API.** The list comes from `CoreGlyphs.bundle` at
  runtime; every read stays optional and falls back to `SymbolCatalog.suggested`, and Apple's restricted
  marks are never offered.

## How it works

A Raycast extension command is a **single prebuilt CommonJS file** that keeps `react`,
`react/jsx-runtime`, `@raycast/api` and the Node built-ins external. Tinycast supplies exactly those,
runs the bundle, and renders the React tree it produces:

```
  <command>.js  (esbuild output, deps inlined)
        │  require("@raycast/api"), require("react"), require("node:fs"), …
        ▼
  RaycastRuntime.generated.js          ← in the app bundle; React 19 + react-reconciler
        │                                 + the @raycast/api shim + Node/web polyfills
        │  render tree as JSON      ▲  dispatch(handlerId, args)
        ▼                          │
  ExtensionRuntime (JavaScriptCore, private serial queue)
        │  RenderTree / RenderValue (Sendable)     ▲  host calls
        ▼                                          │
  ExtensionManager (@MainActor) ── ExtensionHostBridge ── Clipboard / storage / toasts / fetch / exec
        │
        ▼
  ExtensionScreen → Features/Extensions/* → the palette
```

Two conventions make the Raycast component surface expressible in a tree:

- **`__slot`** — Raycast passes elements as *props* (`actions={<ActionPanel/>}`,
  `detail={<List.Item.Detail/>}`, `metadata={…}`, `searchBarAccessory={…}`). React never renders an
  element sitting in a prop, so each shim component re-emits those props as `__slot` children; the
  serializer folds them back into the parent's props. That way hooks inside them work and Swift
  receives them as structure.
- **`{"$fn": "<nodeId>:<propName>"}`** — function props become dispatchable handles. The handler table
  is rebuilt on every commit, so a dispatch always reaches the callback from the newest render.

### Why JavaScriptCore

JavaScriptCore ships with macOS: embedding it costs **zero binary size** and no vendored C. QuickJS
would add ~1 MB plus a build-system detour, for an engine that is slower and no more capable here — the
work is not in the interpreter, it's in the `@raycast/api` shim and the Node surface, which are the
same either way. A bare `JSContext` has the full modern language (checked: `Object.groupBy`,
`Array.fromAsync`, `Intl`, lookbehind regex) and nothing else, so the runtime supplies `console`,
timers, `fetch`, `URL`, `URLSearchParams`, `TextEncoder`/`TextDecoder`, `AbortController`, `atob`/
`btoa` and `structuredClone` itself.

## The JS runtime

`Tinycast/Resources/RaycastRuntime.generated.js` (~200 KB minified) is **generated and committed**, the
same arrangement as `EmojiData.generated.swift`: building Tinycast never needs Node. Sources live in
[`Scripts/raycast-runtime/`](../../Scripts/raycast-runtime):

| File | What it is |
| --- | --- |
| `src/index.js` | the `__tinycast` object Swift calls into (`boot`, `start`, `dispatch`, `popNavigation`, `settle`, `fireTimer`, `stop`) |
| `src/host.js` | the JS→Swift seam: async `hostCall`, blocking `hostCallSync`, logging |
| `src/reconciler.js` | `react-reconciler` host config that commits into a JSON tree |
| `src/api/components.js` | every `@raycast/api` component |
| `src/api/system.js` | Clipboard, LocalStorage, Cache, Toast, preferences, environment |
| `src/api/enums.generated.js` | Icon / Color / Toast.Style / … extracted from the real `@raycast/api` types |
| `src/node-shims.js` | `path`, `fs`, `os`, `child_process`, `crypto`, `zlib`, `util`, `events`, `buffer`, `punycode`, … |
| `src/url.js`, `src/punycode.js`, `src/buffer.js` | web/Node primitives JavaScriptCore lacks |

Two host-call flavours:

- **Async** (`invoke`) for anything that needs the main actor — clipboard, toasts, window control,
  `fetch`, `exec`. Swift answers later through `__tinycast.settle`, so the JS thread never blocks on the
  UI.
- **Blocking** (`invokeSync`) for the synchronous Node shims only — `fs.readFileSync`,
  `execSync`, `createHash`, `gunzipSync`. Safe because Swift services these entirely on the JS queue;
  nothing there touches the main actor, so a blocking answer cannot deadlock.

## The Swift host

`Tinycast/Features/Extensions/`, split the same way as every other feature:

| File | Role |
| --- | --- |
| `Service/ExtensionRuntime.swift` | the `JSContext`, host-function installation, timers, exception reporting |
| `Service/ExtensionHostBridge.swift` | main-actor host APIs (clipboard, storage, cache, window, toasts, system) |
| `Service/ExtensionNodeShims.swift` | the synchronous `fs` / `child_process` / `crypto` / `zlib` services |
| `Service/ExtensionFetcher.swift` | `fetch` over `URLSession`, plus the async `exec` and the shared PATH resolver |
| `Service/ExtensionStorage.swift` | per-extension `LocalStorage`, `Cache` and preference values (one JSON file each) |
| `Service/ExtensionCatalog.swift` | discovery on disk, install, uninstall, import-from-Raycast |
| `Service/ExtensionCleanup.swift` | the build workspace's name, the launch sweep, and reclaiming orphans |
| `Service/ExtensionManager.swift` | the single owner: installed set, the one running session, launcher entries |
| `Model/ExtensionManifest.swift` | `package.json` → commands, preferences, arguments |
| `Model/RenderNode.swift` | the decoded render tree (`RenderTree` / `RenderNode` / `RenderValue`) |
| `Model/ExtensionAppearance.swift` | the per-extension icon override and its tint palette |
| `Service/ExtensionAppearanceStore.swift` | where those overrides persist |
| `Service/SymbolCatalog.swift` | the SF Symbol list read from `CoreGlyphs.bundle` |
| `UI/ExtensionScreen.swift` | flattens one screen into the palette's row order |
| `UI/ExtensionCommandScreen.swift` | that order adapted to `PaletteScreen`, so the flat selection indexes it |
| `UI/ExtensionCoordinator.swift` | launching, leaving, and every host callback that touches a surface |

`ExtensionRuntime` is `@unchecked Sendable` deliberately and narrowly: every `JSContext` / `JSValue`
touch happens on one private serial queue, and only plain `Sendable` values cross in or out
(`RenderValue` for arguments, `RenderTree` for output, JSON strings for results). That keeps extension
evaluation and the blocking shims off the main actor.

**One command at a time, one context per command.** Starting a command stops whatever was running and
throws the whole `JSContext` away; the next launch boots a fresh one (~7 ms warm, measured).

Reusing a context was subtly broken. Timers are global and React's scheduler drives every commit
through `setTimeout`, so cancelling an extension's leftover timers on teardown also cancelled the
scheduler's — which latches `isMessageLoopRunning` and silently stops *every later session* from
committing. The symptom was a command that worked once and then hung on "Starting…" forever. Leaving
the timers alone instead leaks any interval an extension forgot to clear. Discarding the context avoids
both, and as a bonus no module-level state in an extension bundle survives into its next run.

Host calls carry no session id, so `ExtensionManager.activeExtensionName` is what namespaces storage,
cache and preferences — the single-session rule is what makes that safe. It also matches the UI: the
palette shows one screen.

## Rendering

`ExtensionScreen` is the single source of truth for row order, so the flat `selection` index the rest of
the palette relies on maps 1:1 onto visible rows — the same invariant the launcher, clipboard and emoji
screens hold (see [palette.md](palette.md)).

- **List / Grid** — sections and items flattened in render order. When `filtering` is on (Raycast's
  default unless the command supplies `onSearchTextChange`) rows are filtered with the launcher's own
  `FuzzyMatch` over title, subtitle and keywords, and a section whose items all drop loses its header
  too. `isShowingDetail` splits the screen into rows plus a detail pane.
- **Detail** — markdown rendered block-by-block (headings, lists, code fences, quotes, rules, remote
  images) with `AttributedString` handling inline styling, plus `Detail.Metadata`.
- **Form** — label-left/control-right rows. Field values live in the extension (React owns them); every
  edit dispatches `onTinycastChange` and the resulting re-render is what updates the control, so
  `defaultValue`, a controlled `value`, and `ref.reset()` all behave.
- **ActionPanel** — flattened (sections and submenus included) into the palette's ⌘K menu. The first
  action is the primary ↵ action; an action's own `shortcut` is matched against modified keystrokes.
- **Feedback** — `showToast` stacks above the footer, `showHUD` is a centred pill, and `confirmAlert`
  goes through `DialogController` like every other question the app asks. Its dialog sits at
  `.modalPanel`, above the palette's `.floating`, so a view command keeps its screen behind it.
- **Command arguments** — a command declaring `arguments` shows inline fields sized to their
  placeholders, right after the typed text, exactly as Raycast does. Tab walks search field → each
  argument → back; ↵ from any of them runs the command with the values as `props.arguments`; a blank
  required argument blocks the launch and focuses the offending field. The fields get their own
  `FocusState` rather than joining the search field's, so the palette's one always-attached `TextField`
  (see [palette.md](palette.md)) keeps owning focus.

  Every declared argument is sent, **empty string when unfilled** (`ExtensionCommand.completeArguments`).
  That is Raycast's contract and extensions depend on it: `Number(args.seconds)` is `0` for `""` but
  `NaN` for `undefined`, so omitting a blank argument silently corrupts whatever they compute — Coffee's
  "Caffeinate for…" spawned `caffeinate -t NaN`, which exits instantly.

Escape and a bare backspace pop the extension's own navigation stack first, and only leave the command
once it's at its root. Pushed screens stay mounted, so popping back restores their state.

## Turning it on

Extensions are **off until asked for**, and the switch is a real one rather than a filter: while it is
off no directory is scanned, no launcher row is published and no JavaScript context exists. Turning it
on confirms first — it is consent to run third-party code, and a running command holds a JavaScript
engine in memory until you leave it, which is the one standing cost this app has.

`Show in launcher` is separate, and independent: it decides whether the commands reach launcher search
at all, without unloading anything.

## Installing extensions

Extensions live in `~/Library/Application Support/<bundle id>/extensions/<name>/`, keyed by bundle id
like everything else, so a Debug build never shares installs with a release channel. A directory holds
`package.json`, `assets/` and one `<command>.js` per command — byte-for-byte the layout Raycast's own
build produces.

Settings → Extensions offers three routes, under **Install New**:

1. **Search Registries…** — searches every enabled registry and installs from any of them. See below.
2. **Import from Raycast** — copies the already-built bundles out of a local Raycast. Nothing is
   compiled, so no Node, npm or network is involved. The pane also scans whenever it opens, and says
   so when Raycast has something Tinycast doesn't — installing in Raycast otherwise leaves no trace
   here. **Both channels are searched**: `~/.config/raycast` and `~/.config/raycast-x`, the latter
   being Raycast Beta v2. Checking only the first reported "no Raycast install" to every Beta user,
   whose stable directory is present but empty. The same extension in both is offered once.
3. **Add Folder…** — pick any directory with a manifest and built command files, e.g. an extension you
   just ran `ray build` in.

Only `package.json`, the built commands and `assets/` are copied — never `node_modules` or the
multi-megabyte `.js.map` Raycast writes beside each bundle.

## Registries

A registry is a place extensions are searched for and fetched from. Two kinds, because the two sources
hand back different things:

| | Raycast Store | A GitHub repository |
| --- | --- | --- |
| What it serves | The bundle Raycast already built | Source |
| Installing needs | Nothing | Node, and a package manager |
| How it's found | `raycast.com/frontend_api/extensions/search`, the endpoint the store's own site uses — unofficial, hence the fallback | The Git trees API, then a `package.json` read per candidate |

Both ship enabled, and anyone can add their own GitHub registry — a repository laid out like
`raycast/extensions`, one folder per extension.

**Only the extension's own folder is ever fetched.** `raycast/extensions` is gigabytes; cloning it to
install one extension would be absurd.

**Listings come from the Git trees API, not the contents API.** Contents caps a directory at 1000
entries and says nothing about having done so, and `raycast/extensions` holds over three thousand —
under contents, everything alphabetically past the cap was simply unfindable.

Installing from a source registry runs `<package manager> install --ignore-scripts`, then
**`node_modules/.bin/ray build -e dist -o <build dir>` directly — never the manifest's `build`
script.** That script is `ray build`, whose default environment is `dev`, and dev mode *installs into
the local Raycast* rather than emitting anything. The build reported success and exited 0 while
writing nothing beside the manifest, so every source install failed afterwards with "no built command
bundles", and each attempt quietly added the extension to the user's own Raycast.

**`-o` points at a sibling `build/` directory, never at the source.** `ray` clears its output
directory first, so aiming it at the source deleted `assets/` before the install could copy it — the
extension arrived with no icon. Building into its own directory leaves the source intact and yields
exactly the layout `ExtensionCatalog.install` expects: `package.json`, one `<command>.js` each, and
`assets/`. What it installs from is that directory, not the source.

`-e dist` also type-checks, so an extension that does not compile now fails at the build rather than
at the copy. An extension without `ray` falls back to its own build script and installs from the
source, which is the only contract such an extension offers. Lifecycle scripts are skipped on purpose: the
build script is the contract, a `postinstall` is code nobody asked to run. The package manager is
`Automatic` by default, which takes the first of pnpm, Bun, Yarn and npm that is installed — a GUI app
inherits none of a login shell's `PATH`, so `ExtensionPackageManager.searchPaths` is where they are
looked for, version managers included.

Neither the registry list nor the package manager rides a settings backup: one names a tool the
machine an import lands on may not have, the other is a source of code that will be run.

## Shortcuts

A global shortcut binds to a **command**, not to an extension — a shortcut has to land on one thing to
run, and an extension is a set of commands. `HotKeyAction.extensionCommand` is keyed by the launcher
entry id (`extension:<extension>/<command>`).

Its index is not pruned at launch the way the UUID-keyed ones are: the installed set is scanned
asynchronously and only while extensions are on, so at launch "not installed yet" and "gone" look
identical, and pruning there would quietly drop a working binding. Uninstalling clears its own instead,
along with the extension's stored preferences and its chosen icon.

## What's supported

**Components** — `List` (+ `Item`, `Section`, `EmptyView`, `Item.Detail`, `Dropdown`), `Grid`
(+ `Item`, `Section`, `EmptyView`, `Dropdown`), `Detail` (+ `Metadata` with `Label`, `Link`, `TagList`,
`Separator`), `Form` (`TextField`, `PasswordField`, `TextArea`, `Checkbox`, `Dropdown`, `TagPicker`,
`DatePicker`, `FilePicker`, `Separator`, `Description`), `ActionPanel` (+ `Section`, `Submenu`) and
`Action` with every convenience variant (`CopyToClipboard`, `Paste`, `OpenInBrowser`, `Open`, `OpenWith`,
`ShowInFinder`, `Trash`, `Push`, `SubmitForm`, `PickDate`). Deprecated aliases (`ActionPanel.Item`,
`Form.DropdownItem`, `CopyToClipboardAction`, …) are present too — shipped bundles still use them.

**APIs** — `Clipboard`, `LocalStorage`, `Cache`, `environment`, `getPreferenceValues`, `showToast`,
`showHUD`, `confirmAlert`, `closeMainWindow`, `popToRoot`, `clearSearchBar`, `open`, `trash`,
`showInFinder`, `getApplications`, `getDefaultApplication`, `getFrontmostApplication`,
`getSelectedText`, `getSelectedFinderItems`, `launchCommand`, `openExtensionPreferences`,
`useNavigation`, `Icon`, `Color`, `Image.Mask`, `Keyboard.Shortcut.Common`, `LaunchType`.

**`raycast://` URLs** — extensions address Raycast by scheme; the most common is a bare
`open("raycast://")` to bring the window back after something stole focus (1Password's auth flow does
this). `ExtensionHostBridge` keeps those inside Tinycast: `raycast://extensions/<author>/<extension>/<command>`
runs that command when it's installed, anything else reopens the palette. Handing them to the workspace
would launch Raycast itself.

**Node built-ins** — `path`, `fs` (+ `fs/promises`), `os`, `child_process` (`exec`, `execFile`,
`execSync`, `execFileSync`, `spawnSync`, and a buffered `spawn`), `crypto` (hashes, HMAC, random,
UUID), `zlib` (gzip/zlib/raw deflate, both directions), `util`, `events`, `buffer`, `url`,
`querystring`, `punycode`, `assert`, `string_decoder`, `timers`. Every other built-in resolves to a
stub that throws only when used, so a bundle that merely references `dgram` or `http2` still loads.

**Command modes** — `view` renders into the palette; `no-view` runs headless with the palette closed.
Both receive `props.arguments` and `props.launchType`.

Measured against the 37 extensions installed in a real Raycast on the development machine: **32
extensions / 114 of 147 view commands** boot and render. `Scripts/raycast-runtime/test.mjs <dir>` and
`Scripts/run-tests.sh ext-test` reproduce that measurement.

## What isn't supported yet

| Gap | Why |
| --- | --- |
| **OAuth** (`OAuth.PKCEClient`) | The `Web` redirect method routes through `raycast.com/redirect`, which the provider's app registration is bound to. Not portable without that service; `App`/`AppURI` redirects would need a Tinycast URL scheme. This is the single biggest gap — 3 of the 37 extensions measured, 26 commands. |
| **`menu-bar` commands** | The launcher lists them and explains why they don't open. |
| **`AI`, `BrowserExtension`, `WindowManagement`** | Raycast services with no local equivalent. Importing them works; calling one throws with a clear reason. |
| **WebSocket** | No polyfill yet; `URLSessionWebSocketTask` could back one. |
| **Aborting a `fetch` already in flight** | `AbortSignal` is complete — `timeout`, `abort` and `any` included — and `fetch` checks it on both sides of the host call, so a caller gets its `AbortError`. The request itself still runs to completion: the signal isn't carried across the bridge, so nothing cancels the `URLSessionTask`. A timeout bounds the caller, not the network. |
| **Streaming `child_process.spawn`** | `spawn` runs the child to completion and emits its output as one chunk (async-iterable, which is what `get-stream`/`execa` consume). True duplex streaming would need a bidirectional channel across the bridge. Extensions built on `execa`'s deeper stream API can still fail. |
| **`http` / `https` / `net` / `tls`** | Resolve but throw on use. `fetch` is the supported path; `axios`'s Node adapter is not. |
| **`stream`** | Only `PassThrough` and `pipeline` are real — enough for `@raycast/utils`' `useExec`, which pipes a child's stdout through them. The rest of the module still throws. |
| **Tool/AI-extension entry points (`tools/`)** | Not surfaced. |

## Working on the runtime

```sh
cd Scripts/raycast-runtime
pnpm install
node gen-enums.mjs        # only after bumping the @raycast/api devDependency
node build.mjs            # → Tinycast/Resources/RaycastRuntime.generated.js (commit it)
node build.mjs --dev       # unminified, React in development mode (better error messages)
```

Then the tests, fastest first:

```sh
# 1. JS-only fixtures, in a bare `vm` context (the closest thing Node has to JavaScriptCore)
node fixtures.mjs

# 2. any prebuilt extension, printing the render tree it produces
node test.mjs ~/.config/raycast/extensions/<uuid> [command]

# 3. the real Swift engine, against JavaScriptCore
Scripts/run-tests.sh ext-test
"${TMPDIR:-/tmp}"/tinycast-harness/ext-test ~/Library/Application\ Support/com.tinycast.app.dev/extensions/<name> [command]
```

`ext-test` compiles the real engine sources — there is no copy to keep in sync. `EXT_TEST_VERBOSE=1`
prints the extension's own console output; `EXT_TEST_SETTLE_MS=8000` gives a slow command longer;
`EXT_TEST_PREFS='{"version":"v8"}'` stands in for preferences the user set in Settings, which is the
only way to reach a code path an extension gates on a preference with no manifest default. Both
harnesses read the same three variables.

### Debugging a failing extension

1. Run it through `node test.mjs <dir>` for a full render-tree dump, then through `/tmp/ext-test <dir>`
   to confirm the same behaviour under JavaScriptCore.
2. `EXT_TEST_VERBOSE=1` surfaces the extension's `console.error`, which is usually where an extension
   explains itself.
3. Build the runtime with `--dev` to get unminified React errors instead of `Minified React error #130`.

Two JavaScriptCore differences that have already bitten and are worth remembering: `Error.stack`
contains frames only (V8 repeats the message, so the headline has to be prepended by hand), and
`MessageChannel` is absent, so React's scheduler falls back to `setTimeout`.

## Where things are stored, and what uninstall removes

Everything is under `~/Library/Application Support/<bundle id>/`, keyed by bundle id so a Debug run
never shares with an installed copy.

| What | Where | Gone on uninstall |
| --- | --- | --- |
| The extension | `extensions/<name>/` | yes |
| `LocalStorage`, `Cache`, preferences | `extension-data/<safe name>.json` | yes |
| `environment.supportPath` | `extension-support/<safe name>/` | yes |
| Icon override | `UserDefaults` → `extensionAppearances` | yes |
| Command shortcuts | `UserDefaults` → `hotkey.extensionCommand.<entry id>` | yes |
| Favorites, hidden items | `UserDefaults` → `favoriteApps`, `hiddenItemKeys` | yes |
| Launch ranking | `Caches/<bundle id>/launcher-ranking.json` | yes |

`ExtensionCatalog.safeName` maps an npm-style name onto one path segment, and is the **only** copy of
that mapping — a second one that drifts orphans every file the first one wrote.

The last three rows are pruned by `ExtensionCoordinator.removeExtensionReferences`, reached through
`ExtensionManager.onDidUninstall`. An extension's `preferenceKey` is its entry id, because it has no
bundle id, so `extension:<name>/<command>` is what those stores are keyed by. `CustomCommandCoordinator`
and `QuicklinkCoordinator` prune the same stores the same way; extensions are not a special case.

**Builds happen in `$TMPDIR/tinycast-install-<UUID>/`**, named by `ExtensionCleanup.workspace` so the
sweep below cannot disagree about what a workspace is called. A `defer` removes it on every exit an
install can take. A crash mid-build is the one it cannot cover, so `ExtensionManager.start` sweeps
strays once at launch — deliberately not gated on `extensionsEnabled`, because a stranded
`node_modules` is ours either way.

`$TMPDIR` is kept on purpose over a directory of our own: it is the same APFS volume, equally excluded
from Time Machine, and `com.apple.tmp_cleaner` reclaims it as a second backstop. `~/Library/Caches`
has no such daemon, so a leak there would be permanent.

**Settings › Extensions › Storage** measures the same strays and offers them back, so a leak from an
older build is recoverable without a terminal. It sits outside the enabled group deliberately: the
files are on disk whether or not extensions are on. The row is empty in normal use — an install
cleans up after itself — and the scan runs off-main, because measuring walks a `node_modules`.

**Nothing here touches `~/Library/pnpm` or `~/.npm`.** Those belong to the package manager and are
shared with every other project on the machine.

## Making one look native

An imported extension draws whatever icon it shipped, which rarely matches the rest of the launcher.
**Settings › Extensions › Configure › Launcher icon** replaces it with an SF Symbol on a tinted tile —
the same tile `IconCache` draws for the built-in commands, so the row reads as part of the app.

### `ExtensionIconCache`, and why extension artwork draws smaller

An extension's own artwork has its own cache — `Service/ExtensionIconCache.swift` — rather than
living in `IconCache`. That split is the point: `IconCache` stays the app-and-symbol layer and knows
nothing about extensions. It lends out only the pixel work (`displayPixel`, `artworkExtent`,
`paintedExtent`, `rasterized`), so there is one definition of how an icon is measured and drawn.

`ExtensionIconCache.extent` fits that artwork to **0.76** of the canvas, where an app icon and a
symbol tile both sit at `IconCache.artworkExtent` **0.83**. The gap is deliberate and optical, not a
size correction — measured, all three paths already produce an identical 40pt box.

In dark mode every macOS 26 app icon is a dark squircle with a bright glyph inside it. The ground
disappears into the palette, so only the glyph reads. A Raycast icon is a flat, fully saturated tile,
so every pixel of it reads. At equal geometry the extension shouts, and fitting it smaller is what
makes the two match by eye. Shipped and fetched images take the same target, so an icon doesn't
change size depending on where it came from.

Change the number only against a rendered strip of real icons; it means nothing on its own.
`ext-icon-test` guards the invariant: padding in the source cannot change the drawn size.

- `ExtensionAppearance` (symbol + `ExtensionTint`) is stored per extension by manifest name in
  `ExtensionAppearanceStore`, and applies to **every command** of that extension — the same inheritance
  Raycast has when a command declares no icon of its own.
- `ExtensionManager.publishLauncherEntries` resolves it into each `AppEntry`; `setAppearance`
  re-publishes immediately, so rows change without waiting for a rescan.
- 18 tints, pinned sRGB rather than system colours: tiles rasterize off the main thread, where a dynamic
  colour would resolve against whatever appearance that thread sees. Pinning also makes the picker's
  SwiftUI preview and the drawn bitmap the same colour by construction.
- "Use Original" clears the override. Choices ride along in a settings backup.

### Where the symbols come from

`SymbolCatalog` reads **the system's own catalog** at runtime from
`/System/Library/CoreServices/CoreGlyphs.bundle` — the symbol order, each symbol's categories, and the
extra search terms the SF Symbols app matches on, so "coffee" finds `cup.and.saucer`. Reading it beats
bundling a name list: the offer always matches the OS, with nothing to regenerate per release.

Two filters apply, leaving ~6,500 of the 8,302 names on macOS 26:

- **Apple's reserved marks** (`symbol_restrictions.strings`, ~600 symbols: iCloud, iPhone, AirPlay…),
  which may only refer to those products.
- **Locale renderings** (`.ar`, `.hi`, `.rtl`…), near-duplicates of a symbol already in the list.

None of this is API, so every read is optional and `SymbolCatalog.fallback` — the curated ~85 in
`SymbolCatalog.suggested` — stands in if the bundle ever moves. That curated set is also what the picker
opens on, since scrolling six thousand icons is not a way to choose one; a search reaches the whole
catalog regardless of the selected category.

`Tests/symbols-test.swift` compiles the real source and asserts those invariants against this machine's
CoreGlyphs (shapes and rules, not counts — those move every release).
