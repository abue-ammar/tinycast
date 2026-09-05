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
`btoa`, `ReadableStream`/`WritableStream`/`TransformStream` and `structuredClone` itself.

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
| `src/api/oauth.js` | `OAuth.PKCEClient`, `OAuth.TokenSet`, redirect url builders |
| `src/api/enums.generated.js` | Icon / Color / Toast.Style / … extracted from the real `@raycast/api` types |
| `src/node-shims.js` | `path`, `fs`, `os`, `child_process`, `crypto`, `zlib`, `util`, `events`, `buffer`, `punycode`, … |
| `src/url.js`, `src/punycode.js`, `src/buffer.js` | web/Node primitives JavaScriptCore lacks |

Two host-call flavours:

- **Async** (`invoke`) for anything that needs the main actor — clipboard, toasts, window control,
  `fetch`, `exec`, `oauth`. Swift answers later through `__tinycast.settle`, so the JS thread never blocks on the
  UI.
- **Blocking** (`invokeSync`) for the synchronous Node shims only — `fs.readFileSync`,
  `execSync`, `createHash`, `gunzipSync`. Safe because Swift services these entirely on the JS queue;
  nothing there touches the main actor, so a blocking answer cannot deadlock.

## The Swift host

`Tinycast/Features/Extensions/`, split the same way as every other feature:

| File | Role |
| --- | --- |
| `Service/ExtensionRuntime.swift` | the `JSContext`, host-function installation, timers, exception reporting |
| `Service/ExtensionHostBridge.swift` | main-actor host APIs (clipboard, storage, cache, window, toasts, system, oauth) |
| `Service/ExtensionNodeShims.swift` | the synchronous `fs` / `child_process` / `crypto` / `zlib` services |
| `Service/ExtensionFetcher.swift` | `fetch` over `URLSession`, plus the async `exec` and the shared PATH resolver |
| `Service/ExtensionOAuthKeychain.swift` | secure OAuth token storage backed by macOS Keychain |
| `Service/ExtensionOAuthSession.swift` | PKCE state tracking, browser launch, and callback redirect resolution |
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
  too. `isShowingDetail` splits the screen into rows plus a detail pane and drops each row's
  subtitle, but **not its accessories**: the API only advises an extension against sending them in
  this mode, and Raycast draws the ones it is sent, so suppressing them here would lose a row its
  whole signal. `ExtensionScreen.Item`
  carries both the flat `selection` index and the scroll id, and is the `ForEach` identity of the row
  and the grid cell alike — see the scroll-id rule in [ui.md](../ui.md#rows-selection-hover).
- **Grid tiles** — `ExtensionGridLayout` reads the `Grid`'s `columns`, `aspectRatio`, `fit` and `inset`
  and is the one place tile geometry is decided. A tile is a column wide and `aspectRatio` tall, and its
  content is scaled to that tile rather than drawn at an icon size, which is what makes an image-heavy
  grid (GIFs, logos) look as it does in Raycast; `inset` is the extension's own knob for pulling small
  artwork back in, so **never compensate for a too-large tile by clamping the content**. The grid is
  measured once for every cell — a tile that measured itself would cost a layout pass each. A symbol or
  glyph has no artwork to scale, so it takes a share of the tile; `Grid.Section` props are not read,
  since the grid draws one column count throughout.
- **Detail** — markdown rendered block-by-block (headings, lists, code fences, quotes, rules, fetched
  and inline images) with `AttributedString` handling inline styling, plus `Detail.Metadata`.
- **Appearance** — `environment.appearance` reports the real one, so an extension that branches on it
  is told the truth. It is an injected field on `ExtensionLaunchContext` (a `Model/` type owns no
  environment), which means a **running command keeps the appearance it booted with**; a change
  reaches it on the next launch. A `{light, dark}` icon or colour is picked by
  `ExtensionImage.resolve(_:assetsPath:isDark:)`, whose `isDark` comes from the view's
  `\.isDarkAppearance` so the pick re-renders when the surface flips; either side stands in when an
  extension supplies only one. `{fileIcon: path}` is its own source: the path names a bundle or
  document whose Finder icon is wanted, so it goes to `NSWorkspace` rather than being decoded as an
  image file — an `.app` has no bitmap to read. A `data:` URL is a source of its own too: an extension
  that renders its own SVG hands over the bytes, so they are decoded inline rather than fetched. A
  `tintColor` on any of them draws the image as a template, which is what colours an SVG written
  against `currentColor`. A `raycast-*` colour name **inside** that SVG is rewritten to `rgba(…)`
  during the decode, in `ExtensionIconCache.loadInlineAsync`: the name is legal wherever a Raycast
  tint is, so extensions write it straight into `stroke`, and no SVG renderer knows it — left alone
  the shape draws nothing at all. It happens there rather than in `resolve` because `resolve` runs
  in a `body` and the decode already runs detached, and because the markdown images a Detail draws
  never pass through `resolve` at all. The palette is handed in as `[name: css]`, resolved once per
  appearance by `ExtensionImage.svgPalette(isDark:)` — a `Color` can only be flattened to sRGB on the
  main actor, which is exactly what the decode must not touch. Anything reading a decoded image keys
  its `.task` on `ExtensionImage.LoadKey`, since the URL alone no longer says what will be drawn.
  The feature's own fills live in `ExtensionColors` — never in `Theme`.
- **Form** — label-left/control-right rows. Field values live in the extension (React owns them); every
  edit dispatches `onTinycastChange` and the resulting re-render is what updates the control, so
  `defaultValue`, a controlled `value`, and `ref.reset()` all behave. **A form takes the whole
  keyboard**: its fields *are* the palette's rows, so the search field is hidden and the header left
  empty. `ExtensionFormField` says what each `Form.*` node is —
  which of them focus lands on, which keys the control keeps, and which need a focus ring drawn — and
  `ExtensionScreen` publishes exactly the focusable ones as `items`, so ↑/↓, ⇥/⇧⇥ and the flat
  selection all walk one order. ⇥ wraps at both ends, ↵ submits from any control that edits no text,
  Space toggles a checkbox and opens a file picker, ←/→ step a dropdown's value and a tag picker's
  chips, and a text area keeps ↑/↓ for its own lines so only ⇥ leaves it. A field marked `autoFocus`
  is where the form opens, otherwise the first one. While a control holds focus
  `PaletteState.isEditingField` is set, which is what keeps a bare backspace deleting text rather
  than backing out of the command. The footer's Actions half is drawn only when the panel holds more
  than the one action the ↵ pill already runs, so a plain Submit-only form shows just the pill.

  **Every control is drawn by the feature, none by SwiftUI's stock parts.** `ExtensionFieldChrome`
  is the one rounded surface they all share and `ExtensionFormMetrics` the one place their geometry
  is stated, so a field, a picker and a text area line up by construction. A `Picker` opens only to a
  click and a `DatePicker` has no expression field, which is why neither is used.

  A `Form.Dropdown` and a `Form.TagPicker` are the same control — `ExtensionPickerField` — differing
  only in whether it holds one value or several. It drops `ExtensionPickerList`, a searchable list,
  and **the control keeps first responder the whole time it is open**: the list is a separate window,
  and a second field inside it would take focus off the control and close the list. So the
  popover's search row renders the query rather than editing it, and every key — the arrows, ↵, ⎋,
  ⌫ and each typed character — is claimed on the control. `PaletteState.isControlListOpen` is what
  keeps the palette's own arrow and Escape handlers out of an open list; without it ↓ moved the
  form's selection instead of the list's highlight.

  **The list is hosted in a window of its own**, `ExtensionListPanel`, exactly as the ⌘K menu is by
  `MenuPanelController`. Glass samples what lies behind the window it is in, so a list drawn as an
  in-window overlay sampled the form and read as a different material however its fill was tuned.
  With its own borderless child panel it samples the desktop, and a picker and the actions menu are
  the same surface by construction rather than by matching. It keeps the panel's row pitch, icon
  slot and overflow fade, and a focused control takes the system accent edge that Settings and the
  shortcut recorder already draw.
  Its metrics are restated in `ExtensionFormMetrics` rather than read off the panel: an extension's
  surfaces own their own, and a launcher change must never move a form.

  **The query is typed into the control, not into the list.** The one field editor belongs to the
  palette's search field, so a picker draws its own caret (`ExtensionCaret`) and renders what has
  been typed in place of its value — the text appears where the eye already is, and a multi-select
  keeps its chosen values beside it. `ExtensionQueryText` puts the caret at the insertion point with
  the prompt after it, as an empty field editor does, and the caret is stepped by a timer at AppKit's
  own rate — a `repeatForever` animation fades where a real caret switches. The list is results only.

  **Every key an open list can receive is resolved in one place**, `ExtensionListKey`. A stack of
  separate `onKeyPress` modifiers let a character rule shadow ⌫, and ⌫ arrives carrying U+007F
  rather than the U+0008 SwiftUI's `.delete` names, so nothing was ever deleted from a search.
  Both spellings are answered before characters are considered at all, and the rules are pure so
  `ext-form-test` drives them.

  `ExtensionDateField` is the same shape over `ExtensionDateExpression`, which parses what Raycast's
  date field parses — "tomorrow at 10am", "in 3 days", "next friday", "25 dec" — and offers the same
  presets. It is pure and takes its clock and calendar as parameters, so `ext-form-test` drives it
  and the popover's flip-up rule directly.

  A picker opens downward, or upward when the form's bottom edge would cut the list off, which is
  `ExtensionFormMetrics.placement` applied by `ExtensionListPlacement` against the palette's own
  frame in screen space, so a list can overhang the form's scroller but never the window. The
  chevron points the way the list actually went.

  **React answers a keystroke a render late**, so a value echoed back mid-word is older than what has
  been typed since. Both text controls hold the last edit they dispatched and ignore every echo until
  it catches up; without that, typing at speed dropped characters — "Test from Codex" arrived as
  "T Codex".

  Every control carries its title as an accessibility label and its selection as a value, so a
  picker announces "Difficulty, Easy" rather than the chevron it is drawn with. It reads under the
  pointer as well as the keyboard: controls lift on hover, a list's rows highlight under the mouse
  so both share one selection, and clicking a control takes focus as well as acting, which is what
  lets the two be mixed mid-form.

  `Tests/ext-form-test.swift` drives the geometry and the parser; the interaction was checked against
  a Form Lab extension covering every control, sectioned and empty and 40-option lists, validation
  errors, wrapping labels, and forms taller than the palette, in both appearances.
- **ActionPanel** — flattened (sections and submenus included) into `ExtensionActionsPanel`, the
  feature's own scrolling ⌘K panel. Its rows are `ExtensionActionItem`, not `PopoverMenuItem`: an
  action's `icon` is a full `ImageLike`, so it resolves through `ExtensionImage` like every other
  extension icon and keeps its `tintColor` — which is what makes a palette of `{Icon.Circle, tintColor}`
  rows read as colours rather than a column of grey circles. A destructive action with no tint of its
  own falls back to red. The first action is the primary ↵ action; an action's own `shortcut` is
  matched against modified keystrokes. `ExtensionCommandScreen.menuContent` hands the whole panel to
  the palette as a `PaletteMenuContent`, so the palette never learns the row type — and a row's
  handler is taken from the flattened `ExtensionAction` list rather than the drawn rows, so ↵ and the
  panel fire the same one without resolving an icon per arrow key.
- **Feedback** — `showToast` stacks above the footer, `showHUD` is a centred pill, and `confirmAlert`
  goes through `DialogController` like every other question the app asks. Its dialog sits at
  `.modalPanel`, above the palette's `.floating`, so a view command keeps its screen behind it — and
  the palette does not dismiss while it is up (`AppCore.isShowingDialog`), because dismissing pops to
  root, which would tear the command down before its `await confirmAlert(…)` ever returns.
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

Escape clears a non-empty search field first, and dispatches `onSearchTextChange` as any other edit
would, so a command that took the search text over sees the empty string. Only over an empty field do
Escape and a bare backspace pop the extension's own navigation stack, and only leave the command once
it's at its root. Pushed screens stay mounted, so popping back restores their state.

## Turning it on

Extensions are **off until asked for**, and the switch is a real one rather than a filter: while it is
off no directory is scanned, no launcher row is published and no JavaScript context exists. Turning it
on confirms first — it is consent to run third-party code, and a running command holds a JavaScript
engine in memory until you leave it, which is the one standing cost this app has.

`Show in launcher` is separate, and independent: it decides whether the commands reach launcher search
at all, without unloading anything.

A published row carries the extension's own title in `AppEntry.ownerName`, which both labels the row
and makes the extension a keyword for every command it ships — `lucide` finds *Search Icons*. It is
matched in the launcher's weakest literal band, so a third-party title can never take a query from a
real app; see [launcher.md](launcher.md#owner-names).

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

**Downloading one is a walk to the folder's tree, then one recursive listing.** Contents costs an API
call per directory, and GitHub's anonymous budget is 60 an hour per IP — Color Picker has 17
directories, so an install used to spend 18 calls and three of them exhausted the hour. Walking
`extensions/<folder>` to its sha and asking for that tree with `recursive=1` costs 3 calls whatever
the folder holds, and the file bodies come from `raw.githubusercontent.com`, which the API budget
does not count. A `truncated` listing is a prefix, so it throws rather than install part of an
extension.

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

**An extension carrying a Rust package builds `-e dev` instead.** A `rust:` helper is Raycast's
Windows counterpart to `swift:`, and `dist` cross-compiles it with `cargo xwin` for
`x86_64-pc-windows-msvc` — a toolchain nobody on macOS has, so Color Picker failed its whole build on
a binary it would never load. `dev` is the environment whose Rust plugin skips it and emits the stub
that throws on use; the Swift helper still compiles. `ExtensionInstaller.environment(for:)` picks the
environment by looking for a `Cargo.toml`, so every other extension keeps `dist`'s minification,
external source maps and type check.

`-e dist` also type-checks, so an extension that does not compile now fails at the build rather than
at the copy. An extension without `ray` falls back to its own build script and installs from the
source, which is the only contract such an extension offers. Lifecycle scripts are skipped on purpose: the
build script is the contract, a `postinstall` is code nobody asked to run. The package manager is
`Automatic` by default, which takes the first of pnpm, Bun, Yarn and npm that is installed — a GUI app
inherits none of a login shell's `PATH`, so `ExtensionPackageManager.searchPaths` is where they are
looked for, version managers included (Homebrew, Volta, asdf, mise, fnm, nvm, Yarn).

That hardcoded list can never cover every toolchain layout — Nix among them — so the Registries sheet
also has "Custom search paths": a `:`-separated list, `extensionCustomSearchPaths` in `AppSettings`,
checked *before* the built-in list wherever it resolves a package manager or Node. Set once, it applies
to every future install; nothing about it needs entering per-install. `ExtensionInstaller` takes it as
`additionalSearchPaths` rather than reading settings itself, keeping the Model/Service split intact.

Neither the registry list, the package manager, nor the custom search paths ride a settings backup:
the first two name a tool or a source of code the machine an import lands on may not have or want, and
the last is a set of paths specific to this Mac's toolchain layout.

## Shortcuts

A global shortcut binds to a **command**, not to an extension — a shortcut has to land on one thing to
run, and an extension is a set of commands. `HotKeyAction.extensionCommand` is keyed by the launcher
entry id (`extension:<extension>/<command>`).

A view command summons the palette when the shortcut fires while it is hidden, or it would load
behind a closed window. A no-view command still hides it and reports through its HUD.

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
`useNavigation`, `OAuth`, `Icon`, `Color`, `Image.Mask`, `Keyboard.Shortcut.Common`, `LaunchType`.

**OAuth 2.0 PKCE** — `OAuth.PKCEClient`, `OAuth.TokenSet`, `OAuth.RedirectMethod`, with S256 challenges and
tokens in the login Keychain (service `com.tinycast.extensions.oauth`, `kSecAttrAccessibleWhenUnlocked`),
scoped per extension and dropped on uninstall.

The redirect address belongs to the extension author's OAuth app registration, so Tinycast cannot choose
it — it can only be there to catch it. **Tinycast therefore claims `raycast`, `com.raycast` and `tinycast`
as URL schemes**, which is what makes all three of Raycast's redirect methods land back in the app:

| `RedirectMethod` | Registered address | How it returns |
| --- | --- | --- |
| `App` | `raycast://oauth?package_name=Extension` | straight to Tinycast, no server |
| `AppURI` | `com.raycast:/oauth?package_name=Extension` | straight to Tinycast, no server |
| `Web` | `https://raycast.com/redirect?packageName=Extension` | through Raycast's page, which reopens a claimed scheme |

Claiming `raycast` means an installed Raycast competes with Tinycast for those links and macOS picks the
winner. That is a deliberate trade: without it, `App` redirects have nowhere to land. `Web` additionally
depends on a page Raycast can change at any time — `ExtensionOAuthSession` times out after five minutes so
a redirect that never arrives cannot wedge the palette.

**`raycast://` URLs** — extensions address Raycast by scheme; the most common is a bare
`open("raycast://")` to bring the window back after something stole focus (1Password's auth flow does
this). `ExtensionHostBridge` keeps those inside Tinycast: `raycast://extensions/<author>/<extension>/<command>`
runs that command when it's installed, anything else reopens the palette. Handing them to the workspace
would launch Raycast itself.

**Node built-ins** — `path`, `fs` (+ `fs/promises`, and `createReadStream`/`createWriteStream`), `os`,
`child_process` (`exec`, `execFile`, `execSync`, `execFileSync`, `spawnSync`, and a buffered `spawn`),
`crypto` (hashes, HMAC, random, UUID), `zlib` (gzip/zlib/raw deflate, both directions), `http`/`https`
(`request` and `get`, buffered over the same URLSession bridge as `fetch`), `stream` (`Readable`,
`Writable`, `Duplex`, `Transform`, `PassThrough`, `pipeline`, `finished`, plus `stream/promises` and
`stream/web`), `util`, `events`, `buffer`, `url`, `querystring`, `punycode`, `assert`,
`string_decoder`, `timers`. Every other built-in resolves to a stub that throws only when used, so a
bundle that merely references `dgram` or `http2` still loads.

**Streams** — the stream core is Node's real contract, not a stand-in: an extension that ships
`stream-chain` and `stream-json` to walk a package index builds object-mode pipelines out of it, and
`Homebrew` is the reference case. `fetch` responses expose `body` as a `ReadableStream`, so
`pipeThrough` → `Readable.fromWeb` → `pipeline` → `fs.createWriteStream` works end to end. The bytes
have already arrived by then, though: the "stream" hands out a buffered response in reader-sized
pieces, so a progress callback reports how much has been written, never how much has been received.
One shortcut inside `Transform`: it acknowledges a write as soon as `_transform` calls back rather
than waiting for room on its readable side, so only a transform nobody reads from can grow unbounded.

A bundle that ships its own HTTP client rather than calling `fetch` — node-fetch travels inside
`@raycast/utils`, and axios has a Node adapter — reaches the network through `http.request`, so the
shim answers it: one request when the body ends, one response chunk when the bridge replies. The
transport decodes for us, so the response drops `content-encoding` and `content-length` rather than
have the client gunzip plaintext.

**Bundled Swift helpers** — an extension that imports `swift:../swift/<package>` ships the compiled
Mach-O in `assets/`, and the wrapper Raycast generates chmods it to `755` before spawning it. Store
zips ship that binary `644`, so the chmod is what makes it runnable at all; the buffered `spawn`
covers the rest of the wrapper. Color Picker is the reference case.

**Command modes** — `view` renders into the palette; `no-view` runs headless with the palette closed.
Both receive `props.arguments` and `props.launchType`.

Measured against the 37 extensions installed in a real Raycast on the development machine: **32
extensions / 114 of 147 view commands** boot and render. `Scripts/raycast-runtime/test.mjs <dir>` and
`Scripts/run-tests.sh ext-test` reproduce that measurement. OAuth landed after this run, so the three
OAuth extensions it excluded are not counted yet — re-measure before quoting these numbers.

## What isn't supported yet

| Gap | Why |
| --- | --- |
| **`menu-bar` commands** | The launcher lists them and explains why they don't open. |
| **Raycast's PKCE proxy (`oauth.raycast.com`)** | Extensions whose provider has no PKCE support exchange tokens through Raycast's proxy. `OAuth.PKCEClient` works; a provider that needs that proxy still fails. |
| **`AI`, `BrowserExtension`, `WindowManagement`** | Raycast services with no local equivalent. Importing them works; calling one throws with a clear reason. |
| **WebSocket** | No polyfill yet; `URLSessionWebSocketTask` could back one. |
| **Aborting a `fetch` already in flight** | `AbortSignal` is complete — `timeout`, `abort` and `any` included — and `fetch` checks it on both sides of the host call, so a caller gets its `AbortError`. The request itself still runs to completion: the signal isn't carried across the bridge, so nothing cancels the `URLSessionTask`. A timeout bounds the caller, not the network. |
| **Streaming `child_process.spawn`** | `spawn` runs the child to completion and emits its output as one chunk (async-iterable, which is what `get-stream`/`execa` consume). True duplex streaming would need a bidirectional channel across the bridge. Extensions built on `execa`'s deeper stream API can still fail. |
| **`net` / `tls`** | Resolve but throw on use. Nothing bridges a socket. |
| **Streaming HTTP** | The bridge answers a request with the whole body at once, so `http.request` delivers one chunk and `Response.body` replays bytes that already arrived. Server-sent events, network-level progress and backpressure onto the socket are all out of reach; `stream` itself is real enough to carry them the day the bridge is. |
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
| OAuth tokens | macOS Keychain (`com.tinycast.extensions.oauth`) | yes |
| Icon override | `UserDefaults` → `extensionAppearances` | yes |
| Command shortcuts | `UserDefaults` → `hotkey.extensionCommand.<entry id>` | yes |
| Favorites, hidden items | `UserDefaults` → `favoriteApps`, `hiddenItemKeys` | yes |
| User alias | `UserDefaults` → `launcherAliases` | yes |
| Launch ranking | `launcher-ranking.json` | yes |

`ExtensionCatalog.safeName` maps an npm-style name onto one path segment, and is the **only** copy of
that mapping — a second one that drifts orphans every file the first one wrote.

The last four rows are pruned by `ExtensionCoordinator.removeExtensionReferences`, reached through
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

Every macOS 26 app icon is a squircle with a glyph inside it, and the ground disappears into the
palette, so only the glyph reads. A Raycast icon is a flat, fully saturated tile,
so every pixel of it reads. At equal geometry the extension shouts, and fitting it smaller is what
makes the two match by eye. Shipped and fetched images take the same target, so an icon doesn't
change size depending on where it came from. An inline `data:` image is the one exception and is never
fitted: the extension that drew it has already sized it, and rasterizing would cost the vector.

Change the number only against a rendered strip of real icons; it means nothing on its own.
`ext-icon-test` guards the invariant: padding in the source cannot change the drawn size, and a
`data:` payload decodes in either encoding — and one naming a `raycast-*` colour draws ink, in the
stroke that appearance calls for.

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
