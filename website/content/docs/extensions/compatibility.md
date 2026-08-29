---
title: What works
description: The supported API surface, the measured compatibility rate, and the known gaps.
---

## Measured compatibility

Against the 37 extensions installed in a real Raycast on the development machine:

**32 of 37 extensions, and 114 of 147 view commands, boot and render.**

That number is measured, not estimated, and it moves as gaps close.

## Supported

**Components** — `List`, `Grid`, `Detail` with `Metadata`, `Form` with every field type,
`ActionPanel` and `Action` with all the convenience variants, plus the deprecated aliases.

**APIs** — `Clipboard`, `LocalStorage`, `Cache`, `environment`, `getPreferenceValues`, `showToast`,
`showHUD`, `confirmAlert`, `closeMainWindow`, `popToRoot`, `PopToRootType` (`Default` from a view
command resets immediately), `clearSearchBar`, `open`, `trash`, `showInFinder`, `getApplications`,
`getDefaultApplication`, `getFrontmostApplication`,
`getSelectedText`, `getSelectedFinderItems`, `launchCommand`, `openExtensionPreferences`,
`useNavigation`, `Icon`, `Color`, `Image.Mask`, `Keyboard.Shortcut.Common`, `LaunchType`.

**Node built-ins** — `path`, `fs` and `fs/promises`, `os`, `child_process`, `crypto`, `zlib`,
`util`, `events`, `buffer`, `url`, `querystring`, `punycode`, `assert`, `string_decoder`, `timers`.

**Command modes** — `view` renders into the palette; `no-view` runs headless with the palette closed.

`raycast://` URLs stay inside Tinycast. An extension-command URL runs that command if it is
installed; anything else reopens the palette. Handing them to the system would launch Raycast itself.

## Not supported yet

| Gap                                              | Why                                                                                                                                                       |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **OAuth** (`OAuth.PKCEClient`)                   | Routes through Raycast's own redirect service, which is not portable. **The biggest single gap — 3 of the 37 extensions measured, covering 26 commands.** |
| **`menu-bar` commands**                          | The launcher lists them and explains why they do not open                                                                                                 |
| **`AI`, `BrowserExtension`, `WindowManagement`** | Raycast services with no local equivalent. Importing them works; calling one throws with a clear reason                                                   |
| **WebSocket**                                    | No polyfill yet                                                                                                                                           |
| **Aborting an in-flight `fetch`**                | The caller gets its `AbortError`, but the request still runs to completion                                                                                |
| **Streaming `child_process.spawn`**              | Runs to completion, then emits output as one chunk                                                                                                        |
| **`http` / `https` / `net` / `tls`**             | Resolve but throw on use. `fetch` is the supported path, so axios's Node adapter will not work                                                            |
| **`stream`**                                     | Only `PassThrough` and `pipeline` are real                                                                                                                |
| **AI tool entry points (`tools/`)**              | Not surfaced                                                                                                                                              |

**An extension that needs something missing says so when you run it**, rather than failing silently
or half-rendering.
