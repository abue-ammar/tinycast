# Native extensions: build plan

Proposed 2026-11-22, from the [ARCH 04 diagram](Arch04.png). It breaks that design into ordered tasks across three
places: this repo (the host), a new `tinycast-extensions` repo (SDK, docs, extensions, the Store's
Worker) and Cloudflare (the Store's files and install counts).

## What v1 is

The user opens the Store, installs an extension and runs its commands from the palette or the menu bar.
A running extension is a small native Swift process that describes its UI; the main app draws it.
Commands can also refresh in the background on an interval. Extensions update on their own unless the
user turns that off or pins one. CI builds and signs every extension from reviewed source, and nobody
uploads a binary.

## Decisions

- **One process per running extension.** Each extension is one native Swift executable holding all its
  commands. The main app starts it over a pipe with `ProcessLink.spawn`, tells it which command to run
  and why, and stops it after an idle delay. One process per extension at a time: a command the user
  starts stops a background run of the same extension. It is never a `ProcessRole`. With extensions
  off there is no process, no menu bar item, no schedule and no index fetch.
- **The main app draws all UI.** The extension sends versioned List, Grid, Detail, Form and MenuBar
  trees with their actions. It links no AppKit or SwiftUI, which keeps it at 2–5 MB.
- **One repo, source only.** The SDK, its docs and every extension's source live in
  `tinycast-extensions`, so an SDK change is built against every extension in the same PR. Review
  happens on the PR; a merged version bump is built, signed with Developer ID and published by CI.
- **Developer ID, never notarized.** CI signs every extension with a Developer ID certificate and the
  hardened runtime, and never sends one to Apple's notary service. Extensions install only through the
  in-app Store, so the downloads carry no quarantine and macOS does not gatekeep them.
- **The main app owns installs, updates and preferences.** The Store UI runs in the Settings process and
  asks the main app through `ExtensionCall`, as Settings does today.
- **Extensions use Tinycast's permissions.** An extension runs outside any sandbox as Tinycast's child
  process, so macOS counts it as Tinycast: whatever macOS granted Tinycast, every extension has. The
  manifest lists the permissions an extension uses, and the Store and its About page show that list.
  Nothing asks at install or update, and nothing checks the list at runtime: review on the PR is the
  guard. The tradeoff is deliberate: an extension can read anything Tinycast can, Tinycast's own data
  included, in exchange for a much simpler host. When Tinycast lacks a macOS permission, the extension
  shows a standard view that links to Tinycast's Permissions settings.
- **Three-link trust chain.** A signed index (Ed25519 store key) → each zip's SHA-256 in that index →
  the bundle's Developer ID signature, which must carry Tinycast's team ID and the extension's fixed
  identifier. The main app checks the signature at install and before every run.
- **A fixed identifier.** CI writes `com.abueammar.tinycast.ext.<id>` from the extension's `id`, and
  the signature check pins it, so one extension's binary can never stand in for another's. Everything
  an extension saves lives in its data folder, `ExtensionData/<id>/` in `AppPaths`' Application Support
  folder, which the main app passes in `start`. The prefix and an `id` never change, or the check fails
  and the extension's saved data is stranded.
- **Menu bar items hold no process.** The main app owns each item and keeps the last snapshot the
  extension rendered. The extension runs only to refresh it: when its menu opens, on its interval, or at
  launch.
- **Background refresh is scheduled by macOS.** `NSBackgroundActivityScheduler` runs each command with
  an interval, so macOS batches wake-ups to save energy. Every run has a time limit.
- **Updates install on their own by default.** A Settings toggle turns that off, and a per-extension
  switch pins one. Check for Updates, Update All and a per-extension Update button work either way. A
  revoked version stops whatever the toggle or pin says.
- **Cloudflare hosting.** R2 serves every file behind a custom domain. One small Worker with a D1 table
  counts installs; nothing else runs server-side.
- **Versioned protocol.** The host runs an extension whose `api` major equals its own and whose minor
  is not newer. CI holds every extension's source, so a major bump rebuilds them all in one run instead
  of the host keeping old majors alive.
- **Built for coding agents.** An AGENTS.md for maintainers and one for authors, and four skills that
  call the CLI and link to the docs.

## Folder structure

### `tinycast-extensions` (new, public)

```
tinycast-extensions/
├── AGENTS.md                     for maintainers: SDK, CLI, CI and docs rules; points authors below
├── Package.swift                 SDK package: TinycastProtocol, TinycastKit, the tinycast CLI
├── Sources/
│   ├── TinycastProtocol/         messages, manifest, permissions, store index; Foundation only
│   ├── TinycastKit/              what an extension imports: entry point, commands, UI, host calls
│   └── TinycastCLI/              tinycast new | validate | build | pack, for authors and CI alike
├── Tests/
├── schema/
│   └── extension.schema.json     manifest schema, for editors and CI
├── docs/                         Markdown, read on GitHub; the one source of truth
├── extensions/
│   ├── AGENTS.md                 for authors: the extension contract
│   └── <id>/
│       ├── extension.json        the manifest
│       ├── Package.swift         one executable target; depends on the SDK by path, and nothing else
│       ├── Sources/<Name>/
│       ├── assets/               icon.png (512×512) and images the UI shows; shipped
│       ├── metadata/             Store screenshots 1.png … 5.png; not shipped
│       ├── README.md             the Store's long description
│       └── CHANGELOG.md          the Store's What's New
├── worker/                       the install counter: Worker, wrangler.toml, D1 schema
├── .agents/skills/               new-extension, debug-extension, submit-extension, review-extension
├── .claude/skills → ../.agents/skills
├── .github/
│   ├── CODEOWNERS                /extensions/<id>/ → its author
│   └── workflows/
│       ├── ci.yml                every PR
│       ├── publish.yml           every push to main touching extensions/
│       └── worker.yml            every push to main touching worker/
└── LICENSE                       MIT, covering the SDK and every extension
```

- One folder is one extension: one executable with all its commands, one Store entry, one data
  folder.
- `<id>` matches `^[a-z0-9]+(-[a-z0-9]+)*$`, equals its folder name and never changes. Ids are unique
  in the Store, first come, first served; maintainers approve names on the PR.
- An extension depends on the SDK and nothing else (see [Never](#never)).
- `TinycastProtocol` is the one definition of everything both sides read. The app vendors it; nothing
  is written twice.

### `tinycast` (this repo), once the Raycast runtime is gone

```
Tinycast/Features/Extensions/
├── Model/
│   ├── Protocol/*.generated.swift       vendored by Scripts/sync-extension-protocol.sh <tag>
│   └── ExtensionIndex.swift             the Store index: search, update, pin and revoke decisions
├── Service/
│   ├── ExtensionManager.swift           processes: spawn, idle stop, one per extension, off means off
│   ├── ExtensionSession.swift           one running extension: link, revisions, pending requests
│   ├── ExtensionBundle.swift            one packed .tcext: its manifest, executable and origin
│   ├── ExtensionHostCallRunner.swift    the host calls that need no macOS permission
│   ├── ExtensionSignatureService.swift  Developer ID and team check: at install, before every run
│   ├── ExtensionStatusItemController.swift  one menu bar item: its last snapshot and its menu
│   ├── ExtensionRefreshScheduler.swift  background runs on each command's interval
│   ├── ExtensionIndexStore.swift        the cached signed index: daily and on-demand refresh
│   ├── ExtensionInstaller.swift         download, verify, unpack, swap, update, uninstall
│   └── InstalledExtensionStore.swift    installed set, preferences, pins, per-command switches
├── UI/                                  host-drawn List, Grid, Detail, Form, Actions, Markdown
└── Settings/                            Extensions pane, per-extension page, Store, ExtensionLibrary
Tests/ExtensionModelTests.swift          index decisions, version rules
Tests/ExtensionSessionTests.swift        the session against the packed hello and a stand-in
```

Installed extensions live in `AppPaths`' Application Support folder, under `Extensions/<id>.tcext`,
and their data under `ExtensionData/<id>/`.

### Cloudflare

```
R2 bucket tinycast-extensions → https://extensions.tinycast.dev
v1/index.json                          the catalog; cached 5 minutes
v1/index.json.sig                      Ed25519 signature by the store key
v1/stats.json                          install counts; unsigned; rewritten hourly by the Worker
v1/<id>/<version>/<id>.zip             immutable; cached 1 year
v1/<id>/media/<sha256>.<ext>           icon, screenshots, README, CHANGELOG; immutable; cached 1 year

Worker on the same domain
POST /v1/installs/<id>                 adds 1 to the extension's count in D1
cron, hourly                           writes v1/stats.json from D1
```

Media is named by its hash: a file shared by several versions is stored once, a README or screenshot
change needs no version bump, and the Store checks each file against its name.

## Contracts

### Manifest

```json
{
  "$schema": "../../schema/extension.schema.json",
  "id": "weather",
  "name": "Weather",
  "version": "1.0.0",
  "description": "Forecast for your city.",
  "author": { "name": "Jane Doe", "github": "janedoe" },
  "categories": ["productivity"],
  "icon": "assets/icon.png",
  "permissions": ["network"],
  "preferences": [
    {
      "name": "api-key",
      "type": "secret",
      "title": "API key",
      "required": true
    },
    {
      "name": "units",
      "type": "dropdown",
      "title": "Units",
      "options": ["metric", "imperial"]
    }
  ],
  "commands": [
    { "name": "forecast", "title": "Forecast", "mode": "view" },
    {
      "name": "copy-temperature",
      "title": "Copy Temperature",
      "mode": "no-view"
    },
    {
      "name": "temperature",
      "title": "Temperature",
      "mode": "menu-bar",
      "interval": "15m"
    }
  ]
}
```

- `mode` is `view`, `no-view` or `menu-bar`.
- `interval` is optional on `no-view` and `menu-bar` commands, at least `10m`.
- Authors never write `api`: `tinycast pack` stamps the SDK's protocol version into the packaged copy.

### Store text and screenshots

- **`description`**: one plain line, at most 100 characters, for the Store list and search.
- **`README.md`**: the long description on the detail page, the same file GitHub shows. Markdown
  headings, paragraphs, lists, links, code and quotes. No HTML and no images: screenshots carry the
  visuals, and a remote image would let a README track who opens it.
- **`CHANGELOG.md`**: one `## <version>` section per release; the detail page shows it as What's New.
- **Screenshots**: `metadata/1.png` … `5.png`, exactly 2000×1250, at most 1 MB each.

`tinycast validate` checks every rule here.

### Store index

```json
{
  "extensions": [
    {
      "id": "weather",
      "name": "Weather",
      "version": "1.3.0",
      "api": "1.0",
      "description": "Forecast for your city.",
      "author": { "name": "Jane Doe", "github": "janedoe" },
      "categories": ["productivity"],
      "permissions": ["network"],
      "commands": [{ "name": "forecast", "title": "Forecast", "mode": "view" }],
      "archive": {
        "path": "weather/1.3.0/weather.zip",
        "sha256": "…",
        "size": 812345
      },
      "icon": "weather/media/3f2a….png",
      "screenshots": ["weather/media/9b1c….png"],
      "readme": "weather/media/77d0….md",
      "changelog": "weather/media/c41e….md"
    }
  ],
  "revoked": [{ "id": "weather", "versions": ["1.2.0"] }]
}
```

Install counts stay out of the signed index, so the Worker never holds the store key.

### Permissions (v1)

The list tells the user what an extension uses. The Store and the About page show it, and review
checks it; nothing enforces it at runtime.

| Permission       | The extension                                   | Needs from macOS           |
| ---------------- | ----------------------------------------------- | -------------------------- |
| `network`        | makes outbound connections                      | nothing                    |
| `clipboard-read` | reads the current clipboard                     | nothing                    |
| `paste`          | pastes into the frontmost app                   | Tinycast has Accessibility |
| `accessibility`  | reads selected text, acts on the front app's UI | Tinycast has Accessibility |

A host call that needs a macOS permission Tinycast lacks gets `permissionOff` at request time, so a
command that needs it for one action still runs the rest. The SDK shows `permissionOff` as one
standard view: the permission is off, with a link to Tinycast's Permissions settings. An update that
adds a permission installs without asking; the PR is where a new permission is reviewed.

Needing no entry: its data folder, the preferences and secrets it declares, copying, HUDs, opening
`https` URLs, opening Tinycast's Permissions settings and closing the palette.

Every extension is signed with Developer ID and the hardened runtime, and carries no entitlements.

### Protocol (v1)

| Direction  | Message   | Carries                                                                                                                                              |
| ---------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| main → ext | `start`   | api version, command, why it started (user, menu opened, schedule, launch), preferences, its data folder, locale, appearance                         |
| ext → main | `render`  | a revision and one tree (List, Grid, Detail, Form or MenuBar) with its actions; images are SF Symbols or files in `assets/`; Detail text is Markdown |
| main → ext | `event`   | the revision it answers, and search text, a selection, an action ID or form values                                                                   |
| ext → main | `request` | a request ID and one host call: clipboard, paste, HUD, open URL, open Tinycast's Permissions settings, close palette, accessibility                  |
| main → ext | `reply`   | the request ID and a result or a typed error: `permissionOff` or a failure                                                                           |
| ext → main | `finish`  | the command is done, with an optional HUD, shown only when the user started it                                                                       |
| main → ext | `stop`    | the view or menu closed, the idle delay or time limit passed, the user started another command, or extensions were turned off; the process exits     |

Messages are `Codable` JSON framed by `PipeFraming`, the same as every other link, each at most
`ExtensionWire.maximumFrameBytes`. After `stop`, the main app answers requests until the process
exits, so an action chosen as a menu closes still completes.

### Packaged extension

```
<id>.tcext/Contents/
├── Info.plist        CFBundleIdentifier com.abueammar.tinycast.ext.<id>, the version
├── MacOS/<id>        universal (macOS 26 still runs on Intel), signed as above
└── Resources/        extension.json (with api stamped), assets/
```

`tinycast pack` builds this bundle, so CI and developer mode produce the same thing. It signs ad-hoc
by default; CI passes `--identity` to sign with Developer ID.

### Menu bar and background

- **Showing a menu bar command** is a per-command switch on the extension's page, off by default.
  Running the command from the palette turns it on.
- **A shown item** draws from the last MenuBar snapshot. Opening its menu shows that snapshot at once
  and starts the extension to refresh it. Each shown item also runs once at launch to fill itself.
- **Background refresh** is a per-command switch for every command with an `interval`. It is on by
  default for menu bar commands, which need it to stay current, and off for `no-view` commands, which
  act without being asked.
- **A background run** has a 30-second limit, shows no UI except its menu bar item, and gives way to a
  command the user starts. It runs again at its next interval.

### Updates

```
Settings › Extensions
  [✓] Update extensions automatically
  Checked 10:42 · 3 updates available        [Check for Updates]  [Update All]
  ──────────────────────────────────────────────────────────────
  Weather    1.2.0 → 1.3.0                   [Update]
  Notes      1.0.0 · Pinned, 1.1.0 available [Update]
  GitHub     2.0.1 · Needs a newer Tinycast
```

- **Checking**: the main app fetches the index when the Store opens and once a day while extensions
  are on, with `If-None-Match`, so an unchanged index costs an empty 304. Check for Updates fetches it
  at once.
- **Auto-update on** (the default): a newer version the host can run downloads and verifies in the
  background, and swaps in once the extension isn't running. No prompt, no notification.
- **Auto-update off**: the daily check still fills the list; nothing installs until Update or Update
  All.
- **Pinned**: the extension's page has a Don't Update switch. Auto-update and Update All skip a pinned
  extension; its row still shows the newer version, and its own Update button still works.
- **Update All** installs every listed update except pinned ones and those that need a newer Tinycast.
- **Revoked** versions stop and are disabled whatever the toggle or pin says.
- The toggle is an ordinary preference, so it gets a `SettingsFileKey` and rides backups. The buttons
  send `ExtensionCall`s; the list reads through `ExtensionLibrary`.

## Tasks, in order

Each task names its repo and ends with when it is done. Once Phase 2 is done, Phases 3–6 and Phase 7
can run in parallel.

### Phase 0: remove Raycast extensions (app), before anything else

1. **Remove Raycast extension support completely.** Delete `Features/Extensions/`,
   `RaycastRuntime.generated.js`, `Scripts/raycast-runtime/`, its harnesses, settings keys, strings and
   docs, and every reference in AGENTS.md, `architecture.md` and `not-planned.md`. No migration: files
   an old install left behind stay where they are. `AppEntry.Kind.extensionCommand` goes too, with
   the palette mode, hotkey action and Settings tab built on it; Phase 3 adds back what native
   commands need. Raycast import (snippets, quicklinks, script commands) is a separate feature and
   stays.
   _Done when_ the app builds, tests pass and nothing imports JavaScriptCore.

### Phase 1: the contract (extensions repo)

2. **Bootstrap the repo** with the tree above, `LICENSE`, `CODEOWNERS`, empty workflows and both
   AGENTS.md files. The root one guides SDK work from day one; `extensions/AGENTS.md` states the author
   contract: Foundation and the SDK only, list every permission it uses, never edit another extension,
   bump the version.
3. **`TinycastProtocol` v1**: the messages, the manifest, the permissions and the store index, all
   `Codable` and Foundation only. _Done when_ every message round-trips in tests.
4. **`extension.schema.json`**, matching the Swift manifest type. _Done when_ both accept the sample
   manifest and reject a counter-example for each rule.

### Phase 2: SDK, CLI and a first extension (extensions repo)

5. **TinycastKit**: an `@main` entry that reads `start` and runs the named command; view commands that
   render, re-render on change and handle events; no-view commands; menu-bar commands; the start reason;
   async host calls with cancellation; the standard `permissionOff` view; preferences; storage in the
   data folder from `start`. It links Foundation only.
6. **The `tinycast` CLI**:
   - `new <id>`: scaffolds `extensions/<id>/` from the template, after checking the id is free.
   - `validate`: the schema, id equals folder, no dependency but the SDK, intervals of at least 10
     minutes, icon size, the Store text and screenshot rules, a version greater than the published one
     with a CHANGELOG section when `Sources/` changed, linked frameworks within Foundation, CryptoKit
     and the Swift runtime, no `dlopen`.
   - `build`: release, `--arch arm64 --arch x86_64`.
   - `pack`: the `.tcext` bundle with `api` stamped, signed ad-hoc, or with Developer ID and the
     hardened runtime when given `--identity`.
7. **`extensions/hello`**: one view, one no-view and one menu-bar command with an interval; it grows to
   use every UI type in Phase 4. _Done when_ an SDK test spawns the packed `hello` and drives it
   through `start → render → event → render → stop`.
8. **Tag `v1.0.0`**, the first tag the app vendors.

### Phase 3: the host (app)

9. **`Scripts/sync-extension-protocol.sh <tag>`** vendors `TinycastProtocol` into `Model/Protocol/`.
   Add it to AGENTS.md's generated-files list.
10. **Model and `Tests/ExtensionModelTests.swift`**: the index decisions (install, update, pinned,
    needs a newer Tinycast, revoked).
11. **`ExtensionManager` and `ExtensionSession`**, wired in `AppCore.start()`: a signature check
    through `ExtensionSignatureService` before every spawn, spawn, `start`, request routing, a stale
    render dropped by revision, idle stop, one process per extension, every process stopped when off.
12. **Developer mode, in Debug builds only**: a Settings toggle and a folder of locally packed bundles
    that run without the Store or the signature check. Release builds have neither, so an end user
    installs only from the Store. It grants a capability, so it never rides a backup or
    `settings.json`, like `snippetsEnabled`.
13. **Launcher**: add `AppEntry.Kind.extensionCommand`; its rows come from installed manifests, so
    listing starts no process. Per-command hotkeys and aliases use the existing command paths.

_Done when_ `hello` runs from the palette in Tinycast Dev and exits after the idle delay, and with
extensions off no extension process exists and the main app's memory matches its baseline.

### Phase 4: host-drawn UI (app)

14. **List, Detail and Actions first**, which most extensions need, **then Grid and Form**. HUDs go
    through `HUDPresenter`; errors show as a Detail. One Markdown view draws Detail text and, later, the
    Store's README and CHANGELOG; it builds on the AI feature's `MarkdownBlock` parser, which shares
    parsing, not appearance. Everything stays in `Features/Extensions/UI/`.

_Done when_ `hello` shows every type; search, selection, actions and form submit round-trip; and a
late render never replaces a newer one.

### Phase 5: permissions (app)

15. **`InstalledExtensionStore`**: the installed set, preferences, pins and per-command switches, with
    secrets in the Keychain. Only the main app writes it; Settings reads it through `ExtensionLibrary`
    and changes it through `ExtensionCall`.
16. **A `request` that needs a macOS permission checks Tinycast has it, at request time**: if not, it
    gets `permissionOff`.
17. **Accessibility and paste**: the main app acts for the extension, because only it knows the front
    app and closes the palette before it pastes.
18. **Per-extension Settings page**: About (the permissions it uses, author, version), preferences, the
    menu bar and background switches, Don't Update, uninstall. The Extensions list marks an extension
    that needs a permission Tinycast doesn't have.

_Done when_ a request whose macOS permission is off shows the standard view and works once the
permission is on, and the About page lists the extension's permissions.

### Phase 6: menu bar and background refresh (app)

19. **`ExtensionStatusItemController`**: one `NSStatusItem` per shown menu bar command, drawn from its
    last MenuBar snapshot, with the refresh rules in the Menu bar and background contract.
20. **`ExtensionRefreshScheduler`**: one `NSBackgroundActivityScheduler` per command whose background
    refresh is on, the 30-second limit, and giving way to a command the user starts. Add a `Scheduler`
    row to the naming table in `standards.md`.
21. **Off means off**: turning extensions off removes every menu bar item and cancels every schedule.

_Done when_ `hello`'s menu bar command shows, refreshes on its interval and when opened, with no process
between runs; a `no-view` interval command runs only once switched on; and with extensions off no item,
schedule or process remains.

### Phase 7: publishing pipeline and install counts (extensions repo, Cloudflare)

22. **Cloudflare, the store key and the signing certificate**: the R2 bucket, the custom domain, the
    cache rules above, a D1 database and an API token limited to them. A new Ed25519 store key: private
    in a `publish` GitHub environment, public in the app's Info.plist as `TinycastExtensionsPublicKey`.
    It is separate from the update key, so this pipeline can never sign an app update. A Developer ID
    Application certificate for extensions only, in the same environment, so revoking it never touches
    the app's; the team ID goes in Info.plist as `TinycastExtensionsTeamID`. Those three are the only
    secrets.
23. **`ci.yml`**, every PR, on the `xcode-27` runner the app's release uses: SDK build and tests;
    `tinycast validate` and `build` for each changed `extensions/<id>`, or for all of them when the SDK
    changed; a PR comment listing any permission a manifest adds, since nothing checks the list at
    runtime and updates install without asking.
24. **`publish.yml`**, every push to main touching `extensions/`, one run at a time and never cancelled,
    because two runs would both read the old index and the second would drop the first one's
    extension. For each changed extension:
    1. If its version is newer than the published one: `tinycast build`, then
       `tinycast pack --identity` (signed with Developer ID, never notarized), then
       `ditto -c -k --keepParent <id>.tcext <id>.zip` and its SHA-256, and upload the zip to
       `v1/<id>/<version>/`. A published version never changes, so an install in progress never meets
       a half-replaced file.
    2. Upload the icon, screenshots, README and CHANGELOG to `v1/<id>/media/` under their hashes,
       skipping files already there. A change to only these, or to `description`, publishes without a
       version bump or a rebuild.

    Then download `index.json`, replace those entries, sign it and upload it last, so the index only
    points at files that exist; a run that fails midway leaves the old, complete index.

25. **The install counter** in `worker/`, deployed by `worker.yml`: `POST /v1/installs/<id>` adds 1 to
    that id's row in D1 when the id is in the index, and stores nothing else, not even the IP address.
    An hourly cron writes `v1/stats.json`.

_Done when_ merging a version bump of `hello` puts it in a verified index on `extensions.tinycast.dev`,
a README-only change updates its entry without a new zip, and an install shows in `stats.json` within
the hour.

### Phase 8: installer, updates and Store (app)

26. **`ExtensionIndexStore`**: fetches the index on a private `.ephemeral`, `urlCache = nil` session
    like `CurrencyRateStore`, with `If-None-Match`; checks the signature; caches it on disk. Refreshes
    when the Store opens, once a day while extensions are on, and on Check for Updates.
27. **`ExtensionInstaller`**: download → SHA-256 against the signed index → unpack into staging →
    Developer ID and team check → swap in while the extension isn't running. After a first install it
    sends `POST /v1/installs/<id>` without waiting for the answer, so a failed count never affects the
    install. Updates follow the Updates contract above. Uninstall removes the bundle and its data
    folder. A revoked version stops and is disabled.
28. **Update settings**: the auto-update toggle (`SettingsFileKey` included), Check for Updates, Update
    All, per-extension Update and Don't Update, as in the Updates contract.
29. **The Store in Settings**: browse, search, sort by popularity from `stats.json`, and a detail page
    with screenshots, README, What's New, permissions and install count. Media loads only on the detail
    page, in the Settings process, so the main app never holds images. Install, update and uninstall go
    through `ExtensionCall`. The palette's Search Extensions opens Settings on the Store.

_Done when_ install, update with auto-update on and off, a pinned extension, Update All, uninstall and
revoke all work against the live index, and the Store shows counts from `stats.json`.

### Phase 9: docs, skills and launch (both repos)

30. **Extensions repo docs**: getting started, manifest, Store text and screenshots, permissions, UI,
    menu bar and background commands, host calls, publishing and review guidelines.
31. **Skills**, once the SDK and CLI have settled: `new-extension`, `debug-extension` and
    `submit-extension` for authors, `review-extension` for maintainers reviewing third-party PRs. Each
    is a standard `SKILL.md` (`name`, `description`, plain Markdown) in `.agents/skills/`, with
    `.claude/skills` a committed symlink to it. Skills call the CLI and link to `docs/`, never restate
    them. Check each agent's current docs for where it loads skills.
32. **App docs**: rewrite `docs/features/extensions.md` with its invariants; add the extension process
    to `architecture.md`; update AGENTS.md, whose process rule must name the extension process as the
    one place third-party code runs with Tinycast's privacy grants, and `not-planned.md`; translate the
    new app screens' strings into all eight languages with `./Scripts/sync-strings.sh`.
33. **Two or three first-party extensions** that together use every UI type, command mode and
    permission.

## Delivery

- **Extensions repo**: commits to its `main`; `v1.0.0` after Phase 2.
- **App**: one PR for Phase 0, merged before anything else, then one PR for native extensions
  (Phases 3–6, 8 and task 32).

## Confirm on the prototype first

Both happen in normal use:

- **A Developer ID extension that was never notarized runs without a prompt** once the Store has
  installed it. The prototype tested ad-hoc builds only.
- **macOS counts a spawned extension as Tinycast.** An extension that reads a protected folder uses
  Tinycast's grant, and any prompt names Tinycast, never the extension. If macOS treats the bundle as
  its own app instead, the permission model above needs rethinking before Phase 3.

## Budgets

- Extensions off: no extension process, menu bar item, schedule or network; the main app's memory at
  its baseline.
- A running extension: 2–5 MB; first reply about 33 ms median, as the prototype measured.
- A menu bar item: one `NSStatusItem` and its last snapshot in the main app; no process between
  refreshes.
- A background run: at most one per command per interval, 30 seconds at most.
- 50 installed: the main app holds only their manifests and the index; Store media lives in Settings'
  process.
- Update checks: one conditional request a day while extensions are on.

## Still to discuss

- More names for the permission list, such as files outside the extension's data folder, ending
  processes or capturing the screen. Without a sandbox an extension can already do all of these; the
  list only tells the user.

## Not in v1

AI access.

## Never

- **Third-party Swift packages.** An extension depends on the SDK only, so review covers every line
  that ships and binaries stay small. `validate` rejects any other dependency.
- **Installing from a file or folder in a release build.** An end user installs only from the Store.
  A browser download is quarantined, and a file skips the signed index, the signature check and PR
  review. Debug builds' developer mode is the one exception.
- **Rollback.** A bad release is fixed by the next one; Don't Update covers staying on a version.
- **Ratings.**
