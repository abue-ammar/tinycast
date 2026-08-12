# Tinycast documentation

Start with [`AGENTS.md`](../AGENTS.md) at the repo root — it is the short version, and it links here for
anything that needs more than a line.

Each document below has one job and one trigger: the change that obliges you to edit it. A document that
contradicts the code is a defect, so fix it in the commit that made it wrong.

| Document | Covers | Edit it when |
| --- | --- | --- |
| [architecture.md](architecture.md) | How the app is wired: the layers, who owns what, the windows, the Observation model, the folder tree | a layer boundary, an owner, or the tree changes |
| [standards.md](standards.md) | How code here is written: posture, naming, style, concurrency, performance budgets, comments | a convention changes, or a check is added |
| [testing.md](testing.md) | How to verify a change: the definition of done, the harnesses, purity checks, budgets, the manual sweep | a harness moves, or a budget changes |
| [development.md](development.md) | The local loop: setup, build, dev channel, editor, format/lint, generated data | the local toolchain changes |
| [release.md](release.md) | How a build reaches a user: packaging, CI, releases, the Homebrew tap, the website | the pipeline changes |
| [signing.md](signing.md) | The self-signed identity and the two CI secrets | the signing setup changes |
| [ui.md](ui.md) | The design system: tokens, panel chrome, row grammar, glass, dialogs and HUDs | a token or a presentation rule changes |

## Features

One document per feature, covering its invariants and internals. A few span more than one source
folder — `palette.md` covers `Tinycast/Palette/`, `backup.md` covers two. Every one of them **must**
open with an `## Invariants` section; read it before changing anything in that area.

[palette](features/palette.md) ·
[launcher](features/launcher.md) ·
[clipboard](features/clipboard.md) ·
[calculator](features/calculator.md) ·
[emoji](features/emoji.md) ·
[file search](features/file-search.md) ·
[snippets](features/snippets.md) ·
[quicklinks](features/quicklinks.md) ·
[hotkeys](features/hotkeys.md) ·
[window management](features/window-management.md) ·
[custom commands](features/custom-commands.md) ·
[uninstall](features/uninstall.md) ·
[backup](features/backup.md) ·
[Raycast import](features/raycast-import.md) ·
[Raycast extensions](features/extensions.md)

## Contributing

[`CONTRIBUTING.md`](../CONTRIBUTING.md) covers the workflow — what to open, what to test, what a PR needs.
[`SECURITY.md`](../SECURITY.md) covers vulnerability reports.
