---
title: What works
description: What Tinycast supports from the Raycast API, how well it works in practice, and the known gaps.
---

## How well it works

We tested Tinycast against the 37 extensions installed in Raycast on the development Mac:

**32 of 37 extensions, and 114 of 147 view commands, open and render.**

## Supported

**Components.** `List` and `Grid` with sections, empty views, item details and search bar dropdowns.
`Detail` with `Metadata`. `Form` with every field type: text, password, text area, checkbox,
dropdown, tag picker, date picker, file picker, separator and description. `ActionPanel` with
sections and submenus, and `Action` with all its built-in variants. Older names still used by
published extensions also work.

**APIs.** `Clipboard`, `LocalStorage`, `Cache`, `environment`, `getPreferenceValues`, `showToast`,
`showHUD`, `confirmAlert`, `closeMainWindow`, `popToRoot`, `clearSearchBar`, `open`, `trash`,
`showInFinder`, `getApplications`, `getDefaultApplication`, `getFrontmostApplication`,
`getSelectedText`, `getSelectedFinderItems`, `launchCommand`, `updateCommandMetadata`,
`openExtensionPreferences`, `useNavigation`, `Icon`, `Color`, `Image.Mask`,
`Keyboard.Shortcut.Common`, `LaunchType`.

**Node built-ins.** `path`, `fs` and `fs/promises`, `os`, `child_process`, `crypto`, `zlib`,
`http` and `https`, `stream`, `util`, `events`, `buffer`, `url`, `querystring`, `punycode`,
`assert`, `string_decoder` and `timers`. Other built-ins load without errors and only fail when
they're actually used.

`http` and `https` requests use the same code as `fetch`, so libraries like axios and node-fetch
work. Streams are fully implemented, so pipelines like `fetch` → file work from start to finish.

**Bundled Swift helpers**, like Color Picker's, run normally.

**Command modes.** `view` commands appear in the palette. `no-view` commands run in the background
with the palette closed. A `no-view` command with an `interval` can refresh on a schedule; see
[Background refresh](/docs/extensions/customising#background-refresh). `menu-bar` commands show
native menu items and refresh on their manifest interval, without keeping JavaScript in memory
between runs; see [Menu bar commands](/docs/extensions#menu-bar-commands).

**`raycast://` links** are handled inside Tinycast. Tinycast registers this link type; if Raycast is
also installed, macOS decides which app receives those links. A link to an installed extension command
runs that command, whether it comes from another app, the browser or an extension, with its `arguments`,
`fallbackText` and `launchType` applied. `tinycast://` links work the same way. Any other link
reopens the palette, since passing it on would open Raycast itself.

## Not supported yet

| Gap                                              | Why                                                                                       |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| **`AI`, `BrowserExtension`, `WindowManagement`** | These are Raycast services with no local equivalent. Using one fails with a clear message |
| **WebSocket**                                    | Not available yet                                                                         |
| **Canceling a `fetch` in progress**              | The caller gets its `AbortError`, but the request still finishes in the background        |
| **Live `child_process.spawn` output**            | The command runs to completion, then all of its output arrives at once                    |
| **Streaming HTTP**                               | Responses arrive all at once, so server-sent events and download progress don't work      |
| **`net` and `tls`**                              | Load without errors, but fail when used                                                   |
| **AI tools (`tools/`)**                          | Not shown                                                                                 |

**If an extension needs something that's missing, it tells you when you run it** instead of failing
silently or showing a broken screen.
