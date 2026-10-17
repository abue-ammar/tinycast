# Build variants

`Scripts/build-variant.sh` builds `Tinycast Dev.app` without whole features. It edits no file under
`Tinycast/`, `project.yml` or `Tinycast.xcodeproj`, so ⌘R in Xcode still builds the full app.

```sh
Scripts/build-variant.sh --without ai,extensions,dictation   # build, verify, test, install
Scripts/build-variant.sh --without extensions --no-install   # build and verify only
Scripts/build-variant.sh --check                             # all 8 combinations, no install
Scripts/build-variant.sh                                     # the full app, same pipeline
```

It needs Xcode, `xcodegen` and node. The Command Line Tools lack the SwiftUI macro plugin.

## What each flag removes

| Flag | Compiled out | Dropped from the bundle |
| --- | --- | --- |
| `dictation` | `Features/Dictation/{Service,UI,Settings,Helper}` | the `Tinycast Dev Dictation.app` helper, the `audio-input` entitlement, the microphone usage string |
| `extensions` | `Features/Extensions/{Service,UI,Settings}`, `Model/ExtensionBootConfig.swift` | `RaycastRuntime.generated.js`, JavaScriptCore, the `allow-jit` entitlement, the `raycast://` and `com.raycast://` schemes, the Reminders usage string |
| `ai` | `Features/{AI,MCP,QuickActions}` except their `Model/` folders and settings stores | FoundationModels |

Every variant still compiles each feature's `Model/` folder, `ExtensionScreen`, and the AI, MCP and
Quick Action settings stores. The shared settings code names their types. The stores are the real
ones, so preferences, `settings.json` and backups round-trip unchanged.

## Pipeline

1. `xcodegen dump --type json` turns `project.yml` into a spec.
2. `Scripts/variant/make-spec.mjs` applies `Variants/features.json` to it: excludes, keeps, the
   stand-in folder, `TINYCAST_NO_<FEATURE>`, dropped helper targets, and derived Info.plist and
   entitlements.
3. `xcodegen generate` writes `Tinycast-<variant>.xcodeproj` beside `project.yml`, because its
   `SOURCE_ROOT` paths resolve from the project's own folder. The script adds it to
   `.git/info/exclude`.
4. `xcodebuild` builds into `build/DerivedData`. The script checks the bundle against
   `features.json`, runs `Scripts/run-tests.sh`, and installs to `/Applications`. The previous app
   goes to `build/install-backups/` and a record to `build/install-records/`.
5. The install unregisters every other `Tinycast Dev.app` under `build/` from LaunchServices, and
   `--check` deletes the apps it builds. They share the bundle id, so a fuller copy would answer a
   `raycast://` link with the installed app's preferences. Opening a backup in Finder registers it
   again. Re-run the install or `lsregister -u` that path.

## Stand-ins

`Stubs/<Feature>/` declares the types the rest of the app calls, with the real signatures and no
behaviour. A coordinator hides its launcher commands, which also stops their bound shortcuts. An
entry point that still fires shows "… isn't included in this build", and a Settings pane shows a
placeholder. No stand-in writes a preference.

## Keeping the stand-ins current

Run `Scripts/build-variant.sh --check` after changing a type that shared code calls on AI, Extensions
or Dictation. A stale stand-in fails a slim combination with "cannot find …" or "no member …" at
that call. Add or change the member in `Stubs/<Feature>/` to match the real signature. When a kept `Model/` file starts
calling into `Service/`, stub that call or add the file to `exclude` in `features.json`.
