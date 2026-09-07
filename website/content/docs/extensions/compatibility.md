---
title: What works
description: What Tinycast supports from the Raycast API, how well it works in practice, and the known gaps.
---

## How well it works

Measured against the 37 extensions installed in a real Raycast on the development Mac:

**32 of 37 extensions, and 114 of 147 view commands, open and render.**

That number is measured, not estimated. It was taken before sign-in support arrived, so extensions
that needed it were not counted yet. Expect it to move up.

## Supported

**Components.** `List` and `Grid` with sections, empty views, item details and search-bar dropdowns.
`Detail` with `Metadata`. `Form` with every field type: text, password, text area, checkbox,
dropdown, tag picker, date picker, file picker, separator and description. `ActionPanel` with
sections and submenus, and `Action` with all its ready-made variants. Older names still used by
published extensions work too.

**APIs.** `Clipboard`, `LocalStorage`, `Cache`, `environment`, `getPreferenceValues`, `showToast`,
`showHUD`, `confirmAlert`, `closeMainWindow`, `popToRoot`, `clearSearchBar`, `open`, `trash`,
`showInFinder`, `getApplications`, `getDefaultApplication`, `getFrontmostApplication`,
`getSelectedText`, `getSelectedFinderItems`, `launchCommand`, `updateCommandMetadata`,
`openExtensionPreferences`, `useNavigation`, `OAuth`, `Icon`, `Color`, `Image.Mask`,
`Keyboard.Shortcut.Common`, `LaunchType`.

**Signing in with OAuth.** `OAuth.PKCEClient` works with all three of Raycast's redirect methods.
Tokens are kept in your login Keychain, one set per extension, and removed when you uninstall it.

To catch the redirect, Tinycast registers the `raycast://` link type. If Raycast is also installed,
macOS picks which app gets those links. A sign-in that never comes back gives up after five minutes.

**Node built-ins.** `path`, `fs` and `fs/promises`, `os`, `child_process`, `crypto`, `zlib`,
`http` and `https`, `stream`, `util`, `events`, `buffer`, `url`, `querystring`, `punycode`, `assert`,
`string_decoder` and `timers`. Any other built-in loads fine and only fails if it is actually used.

`http` and `https` requests go through the same path as `fetch`, so libraries like axios and
node-fetch work. Streams are the real thing, so pipelines like `fetch` → file work end to end.

**Bundled Swift helpers**, like Color Picker's, run.

**Command modes.** `view` commands show in the palette. `no-view` commands run in the background with
the palette closed. A `no-view` command with an `interval` can refresh on a schedule; see
[Background refresh](/docs/extensions/customising#background-refresh).
`menu-bar` commands draw native menu items and refresh on their manifest interval, holding no
JavaScript between runs; see [Menu bar commands](/docs/extensions#menu-bar-commands).

**`raycast://` links** stay inside Tinycast. A link to an installed extension command runs that
command — from another app or the browser as well as from inside an extension — with its `arguments`,
`fallbackText` and `launchType` honored, and `tinycast://` works the same way. Anything else reopens
the palette. Passing them on would launch Raycast itself.

## Not supported yet

| Gap                                              | Why                                                                                     |
| ------------------------------------------------ | --------------------------------------------------------------------------------------- |
| **Raycast's sign-in proxy**                      | Providers that need `oauth.raycast.com` to swap tokens still fail                       |
| **`AI`, `BrowserExtension`, `WindowManagement`** | Raycast services with nothing local to stand in. Using one fails with a clear reason    |
| **WebSocket**                                    | Not available yet                                                                       |
| **Cancelling a `fetch` in flight**               | The caller gets its `AbortError`, but the request still finishes in the background      |
| **Live `child_process.spawn` output**            | The command runs to the end, then its output arrives in one piece                       |
| **Streaming HTTP**                               | A response arrives all at once, so server-sent events and download progress do not work |
| **`net` and `tls`**                              | Load, but fail when used                                                                |
| **AI tools (`tools/`)**                          | Not shown                                                                               |

**An extension that needs something missing tells you when you run it**, instead of failing silently
or showing half a screen.
