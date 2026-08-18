# Raycast import

Tinycast reads both `.rayconfig` formats in the wild. They come from different generations of a
rewritten app and share almost no data shape, so each has its own decrypt and its own mapper:

|          | v1                                                     | v2                                               |
| -------- | ------------------------------------------------------ | ------------------------------------------------ |
| Ships in | Raycast 1.104.x (classic)                              | Raycast X (`appVersion` 0.68, `schemaVersion` 2) |
| File     | `IV(16) ‖ AES-256-CBC(gzip(JSON), PKCS#7)` — no header | gzip → JSON envelope → AES-256-GCM               |
| Key      | `EVP_BytesToKey(SHA-256, salt: none)`                  | scrypt(N=16384, r=8, p=1)                        |
| Reader   | `RaycastImportV1` + `RaycastV1Decoder`                 | `RaycastImportV2`                                |

## Invariants

- **The two export formats share no mapper.** `RaycastFormat.detect` is the *only* branch between them;
  `RaycastImportV1` and `RaycastImportV2` own their own decrypt and their own field mapping, and neither
  is ever tried as a fallback for the other. That is what makes a wrong passphrase report a wrong
  passphrase instead of "not a Raycast export". They meet only at `RaycastImport.Result`.
- **`RaycastFormat.swift` and `RaycastV1Decoder.swift` stay Foundation + CommonCrypto + Carbon** so
  `raycast-test` compiles them standalone — which is why the decoder returns Raycast's own values and
  `RaycastImportV1`, not the decoder, validates them against `PopToRootTimeout` / `EmojiSkinTone` /
  `HyperKeyPhysicalKey` / `KeyShortcut`.
- **Never commit a real `.rayconfig` as a fixture.** The harness builds its own.

## Detection

`RaycastFormat.detect(_:)` decides from the leading bytes and is the **only** branch between the two.
A v2 file is a gzip stream (`1f 8b 08`); anything else must be a v1 blob, which is whole AES blocks —
a 16-byte IV plus at least one block of ciphertext. Neither reader is ever tried as a fallback for the
other, so a wrong passphrase reports a wrong passphrase instead of "not a Raycast export".

Detection needs no passphrase, so the Backup pane runs it the moment a file is chosen: it labels the
row and disables the categories that format can't carry (`RaycastFormat.supportedOptions`).

## v1 wire format

```
file = IV(16) ‖ AES-256-CBC( gzip(JSON), PKCS#7 )
key  = SHA-256(passphrase)
```

The key is OpenSSL's `EVP_BytesToKey` with SHA-256 and no salt, which for a 32-byte AES-256 key is a
single digest round. That derivation also yields an IV, and Raycast **discards it** — the file leads
with a fresh random IV instead. Reading the IV from the file is what makes the plaintext's gzip header
land at offset 0, and that header is the real integrity check: a wrong key usually fails PKCS#7, but
roughly 1 in 256 unpads cleanly by chance.

Raycast encrypts even when the user never chose a password — it generates one and stores it in the
login keychain (service `Raycast`, account `export_passphrase`), viewable at Raycast → Settings →
Extensions → Export Settings & Data. **Tinycast never reads the keychain.** The user supplies the
passphrase in the same field v2 uses.

## v1 → Tinycast mapping

v1 JSON is a set of `builtin_package_*` / `raycast_*` providers, with `raycast_version` at top level.

| v1 path                                                                             | Tinycast                                                              |
| ----------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `…raycastPreferences.preferencesAdvanced.popToRootTimeout`                          | `popToRootSeconds` (exact `PopToRootTimeout` match only)              |
| `…preferencesAdvanced.emojiSkinTone`                                                | `emojiSkinTone` (`default` → none)                                    |
| `…preferencesAdvanced.raycast_hyperKey_state` `{enabled, keyCode, includeShiftKey}` | `hyperKey` (a Carbon code — 57 is caps lock), `hyperKeyIncludesShift` |
| `…preferencesAppearance.raycastPreferredWindowMode`                                 | `compactMode` (`== "compact"`)                                        |
| `…preferencesAppearance.showFavoritesInCompactMode`                                 | same                                                                  |
| `…preferencesAppearance.statusBarIsVisible`                                         | `showInMenuBar`                                                       |
| `builtin_package_clipboardHistory.clipboardHistoryDisabledApplications`             | `clipboardDisabledApps`                                               |
| `…clipboardHistoryRecords[]`                                                        | `[ClipboardItem]`                                                     |
| `builtin_package_rootSearch.rootSearch[]`                                           | app hotkeys, clipboard/emoji command hotkeys                          |
| `builtin_package_navigation.pinnedMenuItems`                                        | `favoriteApps`                                                        |
| `builtin_package_snippets.snippets`                                                 | `[Snippet]`                                                           |

Notes that matter:

- **Hotkeys are strings** — `"Command-32"`, `"Shift-Control-Option-Command-32"`: hyphen-joined
  modifier names with a trailing Carbon key code. An unrecognised modifier rejects the whole shortcut
  rather than importing a weaker combo that could shadow something else.
- **`rootSearch[].key` is already the bundle ID** for `systemApp` entries, so nothing touches the
  filesystem and a hotkey survives the app being uninstalled. (v2 hides a path inside the command id
  and has to resolve it through `Bundle`.)
- **Clipboard records are flat** (`text` / `filePath` / `category`), not v2's nested representations,
  and their timestamps carry no fractional seconds. Only `image` becomes an image clip: a `file`
  record can be any document and Tinycast has no kind for that, so its label imports as text.
- **v1 exports no launch-at-login preference, no global palette hotkey and no aliases**, so none is
  ever mapped. That is why `.launchAtLogin` and `.aliases` are absent from
  `RaycastFormat.v1.supportedOptions`. (v2 carries an `alias` string per `settings.commands[]` entry;
  application ones map to `launcherAliases` by bundle ID, the same resolution the hotkey mapper uses.)
- `builtin_package_navigation` and `builtin_package_snippets` are mapped defensively — no export with
  favorites or snippets configured has been available to verify their exact shape.

## Layout

`RaycastFormat.swift` and `RaycastV1Decoder.swift` stay Foundation + CommonCrypto + Carbon so
`Tests/raycast-test.swift` compiles them against the real sources. The decoder's job is _shape_ — it
returns Raycast's own values in a plain `RaycastV1Payload`; turning those into Tinycast's domain types
(`PopToRootTimeout`, `EmojiSkinTone`, `HyperKeyPhysicalKey`, `KeyShortcut`) is `RaycastImportV1`'s job.
That is the same pure-layer / platform-layer split `Features/WindowManagement/` uses.

`RaycastImport` itself is only the facade: `Result`, `selecting(_:)`, and the `read(file:passphrase:)`
dispatcher. `BackupActions.importRaycast` runs it off the main actor.
