# Raycast import

Tinycast reads the `.rayconfig` written by Raycast 2.x: a `RAYCFG3` container holding an AES-256-GCM
payload under a scrypt-derived key. It is the only format read — the 1.x export and the Raycast X beta
between them are both gone, deleted rather than carried.

## Invariants

- **`RaycastDecoder` stays platform-UI-free** so `raycast-test` compiles it standalone. Which is why the
  decoder returns the payload's own bytes and `RaycastImportReader`, not the decoder, validates them
  against `PopToRootTimeout` / `EmojiSkinTone` / `HyperKeyPhysicalKey` / `KeyShortcut`.
- **Recognition is the container signature and nothing else.** `RaycastDecoder.isExport` needs no
  passphrase, so the Backup pane runs it the moment a file is chosen and a wrong passphrase reports a
  wrong passphrase instead of "not a Raycast export".
- **Never commit a real `.rayconfig` as a fixture.** The harness builds its own.
- **Every scrypt derive costs seconds in the unoptimized harness.** `raycast-test` derives once for its
  fixture and keeps the cases that reach key derivation to the few that need it; anything testing the
  container's framing is written to fail before it.

## Wire format

```
file = "RAYCFG3\n" ‖ UInt32LE(header.count) ‖ gzip(header JSON) ‖ ciphertext ‖ tag(16)
body = AES-256-GCM(gzip(payload JSON))
key  = scrypt(passphrase, salt, N=16384, r=8, p=1, dkLen=32)
```

The header carries `schemaVersion`, `iv` and `salt`, hex-encoded, 16 bytes each. `schemaVersion` is
Raycast's own container number and is **3**; anything else is rejected. The payload is category-keyed
JSON: `settings`, `clipboardHistory` and a top-level `snippets`, whose entries name themselves `title`.

Raycast encrypts even when the user never chose a password — it generates one and stores it in the
login keychain (service `Raycast`, account `export_passphrase`), viewable at Raycast → Settings →
Extensions → Export Settings & Data. **Tinycast never reads the keychain**; the user supplies the
passphrase.

## Mapping

An applications command hides the launched app's path after `::=::` in its id, resolved through
`Bundle` to a bundle ID — the same resolution the hotkey, favorite and alias mappers all use. Hotkeys
are `LayoutIndependent` key codes with named modifiers, and always import as a `.combo`: Raycast has no
double-tap binding. A clipboard record's representations are nested and its timestamps carry fractional
seconds; only an `image/*` representation whose file still exists becomes an image clip, and the rest
are counted as missing rather than dropped silently.

## Layout

`RaycastDecoder` unwraps the container and returns Raycast's own values; `RaycastImportReader` turns
those into Tinycast's domain types. That is the same pure-layer / platform-layer split
`Features/WindowManagement/` uses — the reader needs AppKit, so it lives in `Service/` and is covered by
the app build rather than the harness.

`RaycastImport` is only the data: `Result`, `selecting(_:)` and `RaycastImportOptions`.
`BackupActions.importRaycast` runs the reader off the main actor.
