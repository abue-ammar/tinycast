# Contributing to Tinycast

Check existing [issues](https://github.com/abue-ammar/tinycast/issues) and
[pull requests](https://github.com/abue-ammar/tinycast/pulls) first.

> **Don't hurry your code. Make sure it works well and is well designed. Don't worry about timing.**

## Non-negotiables

- **RAM.** Under 100 MB, always. No feature is worth going over.
- **No leaks.** Leak-test before you submit. Zero leaks, no retain cycles, memory back to baseline
  after the palette closes.
- **Design.** New UI must look like it shipped with the app — spacing, type, radii and motion from the
  existing tokens ([`docs/ui.md`](docs/ui.md)). If you genuinely need a new one, justify it in the PR.
- **No bloat.** Tinycast stays small on purpose — quality over quantity. A clean patch still gets
  declined if the feature isn't worth its weight, so open an issue and settle that before you build.
- **Never break the Critical Invariants** in [`AGENTS.md`](AGENTS.md).

## Setup

- macOS 26+, Xcode 26. Do the one-time signing setup ([`docs/signing.md`](docs/signing.md) §1).
- `open Tinycast.xcodeproj` → ⌘R. Debug builds are their own channel (`Tinycast Dev.app`).
- After editing `project.yml`: `xcodegen generate`, commit the result. No SwiftPM.
- Details: [`docs/development.md`](docs/development.md). Architecture:
  [`docs/architecture.md`](docs/architecture.md).

## Localization

Tinycast uses Apple's native localization stack: an English-source
`Tinycast/Localizable.xcstrings` String Catalog, SwiftUI's localization-aware text initializers, and
Foundation's `String(localized:)` for strings resolved outside a view. `DisplayText` distinguishes
catalog keys from runtime/user content in generic UI components; there is no generated API or
third-party dependency.

- Pass literal user-facing text directly to SwiftUI controls such as `Text`, `Button`, and `Label`.
- Use `String(localized:)` when AppKit, a model, an error, or an interpolated status needs a `String`.
- Keep interpolation inside the localized value so translators can reorder placeholders. Do not
  assemble a sentence from translated fragments.
- Generic settings and popover components resolve their string values through the catalog. Add their
  English key and every supported translation to `Localizable.xcstrings` when introducing text there.
- Wrap file names, app names, already-localized status messages, and other runtime values in
  `DisplayText.verbatim` when passing them to a generic component.
- Keep app names, file names, typed calculator expressions, keyboard glyphs, URLs, and user content
  verbatim.

To add a language, add it to `Localizable.xcstrings`, translate every entry, and run
`swift Tools/localization-test.swift`. The app follows the language selected by macOS; it does not
maintain a second in-app language setting. See Apple's documentation for
[String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog),
[preparing SwiftUI views](https://developer.apple.com/documentation/swiftui/preparing-views-for-localization),
and [`LocalizedStringResource`](https://developer.apple.com/documentation/foundation/localizedstringresource).

## Before submitting

- Builds clean — no new warnings.
- The `Tools/` harnesses pass; engine changes come with new cases.
- Leak-tested and memory-measured. Numbers in the PR.
- You actually used the app, on your path and the ones next to it.
- Rebased on `main`, squashed into logical commits.
- Anything in [`docs/`](docs/) your change makes wrong is fixed.
- **Read your own diff top to bottom before you open the PR.** Most review comments are things the
  author would have caught on a second pass.
- You agree to the
  [Contributor License and Feedback Agreement](CONTRIBUTOR_LICENSE_AND_FEEDBACK_AGREEMENT.md).
  Opening a PR is your acceptance.

## Pull requests

- **Visual change → side-by-side before/after video. Mandatory.** Same window size, same actions.
  An "after"-only clip doesn't count; stills don't substitute.
- Non-visual → say what you tested.
- Include the memory numbers, idle and peak.
- Flag anything surprising, and any tradeoff you made on purpose.

## Code style

Match the surrounding code.

- Single-line comments only. Comment the *why*, never the *what*.
- Views stay declarative; logic lives in models and managers.
- Swift 6 isolation — heavy work off the main actor.
- [`Core/Theme.swift`](Tinycast/Core/Theme.swift) tokens only. Read [`docs/ui.md`](docs/ui.md) before
  any new view or restyle. Dark only — no light-mode styling.
- New long-lived state goes on `AppCore`, wired in `start()`.
- Networked features ship **off** and consent-gated. Follow `CurrencyRateStore`.
- Delete dead code. Never hand-edit the generated files.
- Commit messages imperative: `Add per-app hotkey toggle`.

## Bugs

macOS version, Tinycast version + channel, steps, expected vs actual. A recording beats a paragraph.

## Security

Not in the issue tracker — see [`SECURITY.md`](SECURITY.md).

## License

[AGPL-3.0](LICENSE). Contributions are licensed under the same terms.
