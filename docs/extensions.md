# Raycast extensions

Tinycast runs Raycast extensions: the same `package.json` + prebuilt CommonJS bundles Raycast itself
produces, rendered natively into the palette. No Electron, no browser, no Node.js.

- [How it works](#how-it-works) · [The JS runtime](#the-js-runtime) ·
  [The Swift host](#the-swift-host) · [Rendering](#rendering)
- [Installing extensions](#installing-extensions) · [What's supported](#whats-supported) ·
  [What isn't](#what-isnt-supported-yet) · [Working on the runtime](#working-on-the-runtime)

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
[`Tools/raycast-runtime/`](../Tools/raycast-runtime):

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

`Tinycast/Core/Extensions/`:

| File | Role |
| --- | --- |
| `ExtensionRuntime.swift` | the `JSContext`, host-function installation, timers, exception reporting |
| `ExtensionHostBridge.swift` | main-actor host APIs (clipboard, storage, cache, window, toasts, system) |
| `ExtensionNodeShims.swift` | the synchronous `fs` / `child_process` / `crypto` / `zlib` services |
| `ExtensionFetcher.swift` | `fetch` over `URLSession`, plus the async `exec` and the shared PATH resolver |
| `ExtensionStorage.swift` | per-extension `LocalStorage`, `Cache` and preference values (one JSON file each) |
| `ExtensionManifest.swift` | `package.json` → commands, preferences, arguments |
| `ExtensionCatalog.swift` | discovery on disk, install, uninstall, import-from-Raycast |
| `ExtensionManager.swift` | the single owner: installed set, the one running session, launcher entries |
| `RenderNode.swift` | the decoded render tree (`RenderTree` / `RenderNode` / `RenderValue`) |
| `ExtensionScreen.swift` | flattens one screen into the palette's row order |

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
- **Feedback** — `showToast` stacks above the footer, `showHUD` is a centred pill, `confirmAlert` is an
  `NSAlert`.
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

## Installing extensions

Extensions live in `~/Library/Application Support/<bundle id>/extensions/<name>/`, keyed by bundle id
like everything else, so a Debug build never shares installs with a release channel. A directory holds
`package.json`, `assets/` and one `<command>.js` per command — byte-for-byte the layout Raycast's own
build produces.

Settings → Extensions offers two routes:

1. **Import from Raycast** — copies the already-built bundles out of `~/.config/raycast/extensions`.
   Nothing is compiled, so no Node, npm or network is involved.
2. **Add Extension Folder…** — pick any directory with a manifest and built command files, e.g. an
   extension you just ran `ray build` in.

Only `package.json`, the built commands and `assets/` are copied — never `node_modules` or the
multi-megabyte `.js.map` Raycast writes beside each bundle.

Tinycast does **not** bundle extensions itself. That is the deliberate boundary: bundling needs a
JavaScript toolchain and a dependency installer, which would dwarf the app.

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

**Node built-ins** — `path`, `fs` (+ `fs/promises`), `os`, `child_process` (`exec`, `execFile`,
`execSync`, `execFileSync`, `spawnSync`, and a buffered `spawn`), `crypto` (hashes, HMAC, random,
UUID), `zlib` (gzip/zlib/raw deflate, both directions), `util`, `events`, `buffer`, `url`,
`querystring`, `punycode`, `assert`, `string_decoder`, `timers`. Every other built-in resolves to a
stub that throws only when used, so a bundle that merely references `dgram` or `http2` still loads.

**Command modes** — `view` renders into the palette; `no-view` runs headless with the palette closed.
Both receive `props.arguments` and `props.launchType`.

Measured against the 37 extensions installed in a real Raycast on the development machine: **32
extensions / 114 of 147 view commands** boot and render. `Tools/raycast-runtime/test.mjs <dir>` and
`Tools/ext-test <dir>` reproduce that measurement.

## What isn't supported yet

| Gap | Why |
| --- | --- |
| **OAuth** (`OAuth.PKCEClient`) | The `Web` redirect method routes through `raycast.com/redirect`, which the provider's app registration is bound to. Not portable without that service; `App`/`AppURI` redirects would need a Tinycast URL scheme. This is the single biggest gap — 3 of the 37 extensions measured, 26 commands. |
| **`menu-bar` commands** | The launcher lists them and explains why they don't open. |
| **`AI`, `BrowserExtension`, `WindowManagement`** | Raycast services with no local equivalent. Importing them works; calling one throws with a clear reason. |
| **WebSocket** | No polyfill yet; `URLSessionWebSocketTask` could back one. |
| **Streaming `child_process.spawn`** | `spawn` runs the child to completion and emits its output as one chunk (async-iterable, which is what `get-stream`/`execa` consume). True duplex streaming would need a bidirectional channel across the bridge. Extensions built on `execa`'s deeper stream API can still fail. |
| **`http` / `https` / `net` / `tls` / `stream`** | Resolve but throw on use. `fetch` is the supported path; `axios`'s Node adapter is not. |
| **Tool/AI-extension entry points (`tools/`)** | Not surfaced. |

## Working on the runtime

```sh
cd Tools/raycast-runtime
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
swiftc -parse-as-library -swift-version 6 \
  Tinycast/Core/Extensions/{ExtensionRuntime,ExtensionNodeShims,ExtensionBootConfig,ExtensionManifest,ExtensionScreen,ExtensionCatalog,ExtensionFetcher,RenderNode}.swift \
  Tinycast/Core/FuzzyMatch.swift Tinycast/Core/Compression/Zlib.swift \
  Tools/ext-test.swift -o /tmp/ext-test && /tmp/ext-test
/tmp/ext-test ~/Library/Application\ Support/com.tinycast.app.dev/extensions/<name> [command]
```

`ext-test` compiles the real engine sources — there is no copy to keep in sync. `EXT_TEST_VERBOSE=1`
prints the extension's own console output; `EXT_TEST_SETTLE_MS=8000` gives a slow command longer.

### Debugging a failing extension

1. Run it through `node test.mjs <dir>` for a full render-tree dump, then through `/tmp/ext-test <dir>`
   to confirm the same behaviour under JavaScriptCore.
2. `EXT_TEST_VERBOSE=1` surfaces the extension's `console.error`, which is usually where an extension
   explains itself.
3. Build the runtime with `--dev` to get unminified React errors instead of `Minified React error #130`.

Two JavaScriptCore differences that have already bitten and are worth remembering: `Error.stack`
contains frames only (V8 repeats the message, so the headline has to be prepended by hand), and
`MessageChannel` is absent, so React's scheduler falls back to `setTimeout`.
