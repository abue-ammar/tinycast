# What Tinycast Won't Do

Some requests get a "no" on purpose. This page lists those choices, so you know what to expect
before you ask.

Every item here comes from a real request on GitHub. The number after each item links to the full
discussion.

## Why we say no

**Tinycast is not a copy of Raycast.** We don't add a feature only because Raycast has it. If
Raycast already does what you need, it may be the better app for you, and that's fine.

**Simple, light and fast comes first.** Each new option makes the app heavier and harder to keep
working. So we keep fewer settings and fewer special cases.

**A little extra effort is on purpose.** Some things take one or two more key presses than in other
launchers. We accept that to keep the app simple.

**Your data stays on your Mac.** We avoid network requests that aren't needed.

---

## Mac, languages and updates

- **Older macOS (Sonoma, Sequoia).** Tinycast needs macOS 26 or later. Support for old versions made
  the app slower on new Macs. Old builds stay in past releases. The last Sequoia build is 0.9.7.
  ([#1611](https://github.com/abue-ammar/tinycast/issues/1611), [#517](https://github.com/abue-ammar/tinycast/issues/517))
- **Windows or Linux.** Tinycast is Mac only. It uses Apple tools that don't run on other systems.
  ([#637](https://github.com/abue-ammar/tinycast/issues/637), [#720](https://github.com/abue-ammar/tinycast/issues/720))
- **More app languages.** Tinycast comes in English plus eight languages. That list is final for now. We may add one more
  language later, but not soon.
  ([#148](https://github.com/abue-ammar/tinycast/issues/148))
- **A beta switch in the regular app.** Stable and beta stay separate until at least version 1.0.
  ([#1411](https://github.com/abue-ammar/tinycast/issues/1411))
- **Updates on accounts without admin rights.** The built-in updater must write to the Applications
  folder. **Instead:** install and update with Homebrew. ([#1340](https://github.com/abue-ammar/tinycast/issues/1340))
- **Import from Alfred, or from old Raycast exports.** Import works with Raycast v2 exports only.
  ([#624](https://github.com/abue-ammar/tinycast/issues/624), [#1373](https://github.com/abue-ammar/tinycast/issues/1373))

## Typing in other languages

- **Input methods (IME) such as Chinese, Japanese or Wubi.** Basic typing works. But each
  input-method fix broke something for other people, so **we no longer fix input-method bugs.**
  That covers arrow keys or Escape while you compose, text that goes to a bar at the bottom of the
  screen, lag right after opening, the Notes placeholder over your text, and snippets leaving part
  of the keyword behind. New input-method reports are closed as not planned.
  **Instead:** the community fork [tinycast-cn](https://github.com/conversun/tinycast-cn).
  ([#990](https://github.com/abue-ammar/tinycast/issues/990), [#851](https://github.com/abue-ammar/tinycast/issues/851), [#1203](https://github.com/abue-ammar/tinycast/issues/1203), [#1580](https://github.com/abue-ammar/tinycast/issues/1580), [#1555](https://github.com/abue-ammar/tinycast/issues/1555))
- **More cases for Chinese app names.** Tinycast finds an app by its Chinese name, and matches
  pinyin too. It works when your Mac uses Simplified or Traditional Chinese with any region, for
  example Simplified Chinese with the US or Hong Kong region. If an app has no name in your
  language, Tinycast uses its English name. **That is every case we support, and we won't add
  more.** New reports about Chinese app names are closed as not planned.
  **⚠️ If these cases keep breaking, we may remove translated app names and show English names
  only.** **Instead:** add the Chinese name as an alias in Settings → Applications.
  ([#1640](https://github.com/abue-ammar/tinycast/issues/1640), [#1649](https://github.com/abue-ammar/tinycast/issues/1649))
- **Keyboard layouts other than US QWERTY.** Paste, snippets and emoji press keys by their position
  on a US keyboard. On Colemak, Dvorak and similar layouts this can trigger the wrong shortcut.
  Shortcuts also don't match by layout. ([#65](https://github.com/abue-ammar/tinycast/issues/65), [#1214](https://github.com/abue-ammar/tinycast/issues/1214), [#1404](https://github.com/abue-ammar/tinycast/issues/1404))
- **App names in another language.** App names follow your Mac's language. **Instead:** set your
  Mac to English if you want English names. ([#595](https://github.com/abue-ammar/tinycast/issues/595))
- **Define Word in languages other than English.** The layout looks right only in English. ([#943](https://github.com/abue-ammar/tinycast/issues/943))

## Launcher and search

- **Search history.** There is no list of past searches, and ↑ won't bring one back. The launcher
  already learns what you open and moves it higher. ([#59](https://github.com/abue-ammar/tinycast/issues/59), [#772](https://github.com/abue-ammar/tinycast/issues/772), [#1446](https://github.com/abue-ammar/tinycast/issues/1446))
- **⌘1–⌘9 to open any result.** Number shortcuts work only on Favorites in the launcher and on
  pinned items in Clipboard History. ([#1090](https://github.com/abue-ammar/tinycast/issues/1090), [#1357](https://github.com/abue-ammar/tinycast/issues/1357), [#951](https://github.com/abue-ammar/tinycast/issues/951), [#396](https://github.com/abue-ammar/tinycast/issues/396), [#278](https://github.com/abue-ammar/tinycast/issues/278), [#1508](https://github.com/abue-ammar/tinycast/issues/1508))
- **Space to act like Tab or Enter.** Space always types a space. After an alias, press **Tab** to
  fill in its inputs. Space in an empty search box won't open File Search either.
  ([#696](https://github.com/abue-ammar/tinycast/issues/696), [#908](https://github.com/abue-ammar/tinycast/issues/908), [#923](https://github.com/abue-ammar/tinycast/issues/923), [#1128](https://github.com/abue-ammar/tinycast/issues/1128), [#1185](https://github.com/abue-ammar/tinycast/issues/1185), [#1070](https://github.com/abue-ammar/tinycast/issues/1070))
- **Vim keys (j/k).** **Instead:** use Ctrl-N and Ctrl-P. ([#786](https://github.com/abue-ammar/tinycast/issues/786), [#334](https://github.com/abue-ammar/tinycast/issues/334))
- **⌘↑ and ⌘↓ to jump between sections.** ([#1461](https://github.com/abue-ammar/tinycast/issues/1461))
- **Click once to select, double-click to open.** ([#1271](https://github.com/abue-ammar/tinycast/issues/1271))
- **Dictionary results right in the launcher.** A lookup takes a few extra key presses. ([#1405](https://github.com/abue-ammar/tinycast/issues/1405))
- **Paste something to act on it**, like JSON to open a viewer or a file path to open Finder.
  **Instead:** use Search Files. ([#200](https://github.com/abue-ammar/tinycast/issues/200), [#240](https://github.com/abue-ammar/tinycast/issues/240))
- **"!" to run shell commands.** **Instead:** make a custom command. ([#147](https://github.com/abue-ammar/tinycast/issues/147))
- **Drop-down choices for custom command inputs.** ([#1512](https://github.com/abue-ammar/tinycast/issues/1512))
- **Keep the palette open after a command shows a message.** ([#1478](https://github.com/abue-ammar/tinycast/issues/1478))
- **Jump from the launcher to an app's shortcut setting.** Go through Settings. ([#981](https://github.com/abue-ammar/tinycast/issues/981))
- **Act on selected text or files from anywhere (LaunchBar's Instant Send).** ([#1323](https://github.com/abue-ammar/tinycast/issues/1323))
- **Apps inside Parallels Desktop.** ([#1603](https://github.com/abue-ammar/tinycast/issues/1603))
- **Small palette quirks we keep:** dragging an app out makes a Desktop alias, a dragged palette can
  move off centre when the screen resolution changes, and very fast drags can stutter a little.
  ([#1272](https://github.com/abue-ammar/tinycast/issues/1272), [#1587](https://github.com/abue-ammar/tinycast/issues/1587), [#1569](https://github.com/abue-ammar/tinycast/issues/1569))

## Clipboard History

- **Encryption.** History is not encrypted. It never leaves your Mac, and encryption would slow it
  down. **Instead:** add sensitive apps to the block list. ([#993](https://github.com/abue-ammar/tinycast/issues/993))
- **⚠️ Copies from menu-bar helpers, like the Passwords menu.** The block list covers normal app
  windows only. Catching menu-bar helpers needs private Apple tools, so **those copies still land in
  your history.** Delete them by hand if you need to. ([#1407](https://github.com/abue-ammar/tinycast/issues/1407))
- **A large ⌘Y Quick Look preview.** The preview pane already shows the selected item. ([#1067](https://github.com/abue-ammar/tinycast/issues/1067), [#740](https://github.com/abue-ammar/tinycast/issues/740),
  [#1477](https://github.com/abue-ammar/tinycast/issues/1477))
- **Open images in Preview.** **Instead:** use Show in Finder. ([#1328](https://github.com/abue-ammar/tinycast/issues/1328))
- **Link previews or website icons.** ([#1330](https://github.com/abue-ammar/tinycast/issues/1330), [#747](https://github.com/abue-ammar/tinycast/issues/747))
- **Keep a pasted item where it was.** A pasted item always moves to the top. ([#1577](https://github.com/abue-ammar/tinycast/issues/1577))
- **Copy without closing Tinycast.** ([#1215](https://github.com/abue-ammar/tinycast/issues/1215))
- **A global shortcut for paste as plain text.** It lives inside Clipboard History (⌃⌘↵). ([#1172](https://github.com/abue-ammar/tinycast/issues/1172))
- **Fuzzy search.** ([#953](https://github.com/abue-ammar/tinycast/issues/953))
- **Type "img" to filter.** **Instead:** press ⌘P to filter by type. ([#403](https://github.com/abue-ammar/tinycast/issues/403), [#1248](https://github.com/abue-ammar/tinycast/issues/1248))
- **Merge duplicate entries.** ([#632](https://github.com/abue-ammar/tinycast/issues/632))
- **Turn an entry into a snippet with ⌘S.** ([#1333](https://github.com/abue-ammar/tinycast/issues/1333))
- **Block chosen extensions.** ([#1522](https://github.com/abue-ammar/tinycast/issues/1522))
- **A separate screenshot browser.** **Instead:** filter history by images and search the text in
  them. It may come later as a plugin. ([#1211](https://github.com/abue-ammar/tinycast/issues/1211), [#1619](https://github.com/abue-ammar/tinycast/issues/1619))

## Snippets

- **Put a snippet on the clipboard instead of typing it.** ([#1595](https://github.com/abue-ammar/tinycast/issues/1595))
- **Pin snippets.** ([#1027](https://github.com/abue-ammar/tinycast/issues/1027))
- **Sort snippets by last used.** ([#1015](https://github.com/abue-ammar/tinycast/issues/1015))

## Calculator

- **A normal space as a thousands separator** (like `1 000 000`). A space already has a job: `1hr 30`
  and `5 feet 3 inches` must keep working. Commas and dots follow your region under Settings →
  General → Calculator → Number format. ([#1319](https://github.com/abue-ammar/tinycast/issues/1319))
- **`_` as a number separator** (like `1_000`). ([#1196](https://github.com/abue-ammar/tinycast/issues/1196))
- **Calculate the text you selected.** Each feature stays separate. ([#1505](https://github.com/abue-ammar/tinycast/issues/1505))

## Window management

Tinycast is an all-in-one launcher, not a full window manager. Its window tools are finished.

- **Custom snap cycles (like Loop), edge-anchored sizes, or step-by-step undo.** ([#1223](https://github.com/abue-ammar/tinycast/issues/1223), [#1630](https://github.com/abue-ammar/tinycast/issues/1630))
- **Move a window without resizing it.** It caused odd side effects. ([#1511](https://github.com/abue-ammar/tinycast/issues/1511))
- **Drag a window to a screen edge to snap it.** ([#984](https://github.com/abue-ammar/tinycast/issues/984))
- **macOS Fill & Arrange layouts.** ([#652](https://github.com/abue-ammar/tinycast/issues/652))
- **Layouts per workspace (like FlashSpace).** ([#639](https://github.com/abue-ammar/tinycast/issues/639))
- **Switch Windows changes.** The order stays stable for muscle memory. No switch-on-release, and no
  alias search. ([#1506](https://github.com/abue-ammar/tinycast/issues/1506), [#1590](https://github.com/abue-ammar/tinycast/issues/1590), [#1589](https://github.com/abue-ammar/tinycast/issues/1589))
- **Snap or move full-screen windows.** Leaving full screen first makes the window flicker.
  ([#1232](https://github.com/abue-ammar/tinycast/issues/1232), [#1258](https://github.com/abue-ammar/tinycast/issues/1258))
- **Follow Stage Manager.** **Instead:** try Window Rooms. ([#1249](https://github.com/abue-ammar/tinycast/issues/1249))
- **Safari's width after Mission Control.** Safari may reset its width afterwards. ([#1556](https://github.com/abue-ammar/tinycast/issues/1556))

## Notes

- **More than one Notes window.** One window, many notes. ([#863](https://github.com/abue-ammar/tinycast/issues/863))
- **Turn off "always on top".** Most people want Notes to float. ([#670](https://github.com/abue-ammar/tinycast/issues/670))
- **Collect everything you copy into a note (AutoPaste).** ([#307](https://github.com/abue-ammar/tinycast/issues/307))

## AI and dictation

- **Send your selected text or file to AI on its own.** macOS often won't share the selection.
  ([#1420](https://github.com/abue-ammar/tinycast/issues/1420), [#415](https://github.com/abue-ammar/tinycast/issues/415))
- **Send prompts with ⌘↵.** ([#1377](https://github.com/abue-ammar/tinycast/issues/1377))
- **Different default models for Quick AI and AI Chat.** They are one feature with two sizes.
  ([#1108](https://github.com/abue-ammar/tinycast/issues/1108))
- **Open and close Quick AI with the main shortcut.** **Instead:** give Quick AI its own shortcut.
  ([#1356](https://github.com/abue-ammar/tinycast/issues/1356))
- **More command-line AI tools (like Pi Coding Agent).** Providers can block these tools at any
  time, so they may stop working. ([#929](https://github.com/abue-ammar/tinycast/issues/929), [#1610](https://github.com/abue-ammar/tinycast/issues/1610))
- **Voice control, screen reading, or AI command suggestions.** Tinycast won't become a Siri-style
  assistant. ([#1550](https://github.com/abue-ammar/tinycast/issues/1550), [#1151](https://github.com/abue-ammar/tinycast/issues/1151), [#1145](https://github.com/abue-ammar/tinycast/issues/1145))
- **AI-powered "smart" search.** Search stays fast and on-device. ([#1574](https://github.com/abue-ammar/tinycast/issues/1574), [#1528](https://github.com/abue-ammar/tinycast/issues/1528), [#1114](https://github.com/abue-ammar/tinycast/issues/1114))
- **Old Raycast AI chats on import.** Raycast doesn't share that data. ([#1286](https://github.com/abue-ammar/tinycast/issues/1286))
- **Quick Action results inside the palette, or a preview that stays open.** **Instead:** copy the
  result with its copy button. ([#1360](https://github.com/abue-ammar/tinycast/issues/1360), [#1023](https://github.com/abue-ammar/tinycast/issues/1023))
- **A proxy setting.** ([#430](https://github.com/abue-ammar/tinycast/issues/430))
- **Your own dictation models or a personal word list.** Tinycast is not a dictation app.
  ([#1529](https://github.com/abue-ammar/tinycast/issues/1529), [#1332](https://github.com/abue-ammar/tinycast/issues/1332))

## Raycast extensions

- **Full Raycast compatibility.** Tinycast runs about 80% of what Raycast extensions use, and **that
  work has stopped.** Some extensions won't work, or will look a bit different. Tinycast's own
  shortcuts (like Tab) win over an extension's. Our future is native Tinycast extensions.
  ([#1592](https://github.com/abue-ammar/tinycast/issues/1592), [#1585](https://github.com/abue-ammar/tinycast/issues/1585), [#1557](https://github.com/abue-ammar/tinycast/issues/1557), [#1561](https://github.com/abue-ammar/tinycast/issues/1561), [#1541](https://github.com/abue-ammar/tinycast/issues/1541), [#1520](https://github.com/abue-ammar/tinycast/issues/1520), [#1495](https://github.com/abue-ammar/tinycast/issues/1495), [#1452](https://github.com/abue-ammar/tinycast/issues/1452), [#1341](https://github.com/abue-ammar/tinycast/issues/1341), [#1129](https://github.com/abue-ammar/tinycast/issues/1129), [#976](https://github.com/abue-ammar/tinycast/issues/976), [#672](https://github.com/abue-ammar/tinycast/issues/672), [#664](https://github.com/abue-ammar/tinycast/issues/664), [#660](https://github.com/abue-ammar/tinycast/issues/660),
  [#1121](https://github.com/abue-ammar/tinycast/issues/1121), [#1200](https://github.com/abue-ammar/tinycast/issues/1200), [#1397](https://github.com/abue-ammar/tinycast/issues/1397))
- **Let extensions use Tinycast's AI.** ([#1462](https://github.com/abue-ammar/tinycast/issues/1462))
- **⚠️ Locking extensions down.** An extension can do anything you can do on your Mac. **Install only
  extensions you trust.** ([#946](https://github.com/abue-ammar/tinycast/issues/946))

## Settings and looks

- **A theme editor or a custom font.** ([#640](https://github.com/abue-ammar/tinycast/issues/640), [#781](https://github.com/abue-ammar/tinycast/issues/781))
- **Show ⌃⌥⇧⌘ as one ◆ symbol.** ([#437](https://github.com/abue-ammar/tinycast/issues/437))
- **Interface Size for the Settings window.** It sizes the palette only. ([#931](https://github.com/abue-ammar/tinycast/issues/931))
- **A switch to hide every item.** You can already turn almost every feature off. ([#791](https://github.com/abue-ammar/tinycast/issues/791))
- **Filter apps by shortcut, a "?" jump to settings, or no sidebar headings.** ([#978](https://github.com/abue-ammar/tinycast/issues/978), [#1391](https://github.com/abue-ammar/tinycast/issues/1391), [#1142](https://github.com/abue-ammar/tinycast/issues/1142))
- **Hide the calendar colour dot, or more meeting filters.** ([#1063](https://github.com/abue-ammar/tinycast/issues/1063), [#1576](https://github.com/abue-ammar/tinycast/issues/1576))

## Hotkeys

- **Turn a shortcut off in chosen apps.** ([#1428](https://github.com/abue-ammar/tinycast/issues/1428))
- **One hotkey that cycles through several apps.** ([#766](https://github.com/abue-ammar/tinycast/issues/766))
- **Shortcut sequences (press one key, then another).** ([#1257](https://github.com/abue-ammar/tinycast/issues/1257))

## Other features we won't add

- **Quit apps on their own, or "quit all except".** Everything stays manual. **Instead:** a custom
  command with AppleScript can quit apps. ([#1031](https://github.com/abue-ammar/tinycast/issues/1031), [#579](https://github.com/abue-ammar/tinycast/issues/579), [#698](https://github.com/abue-ammar/tinycast/issues/698))
- **A timer, focus sessions, a flight tracker or confetti.** ([#1179](https://github.com/abue-ammar/tinycast/issues/1179), [#1025](https://github.com/abue-ammar/tinycast/issues/1025), [#1007](https://github.com/abue-ammar/tinycast/issues/1007), [#992](https://github.com/abue-ammar/tinycast/issues/992))
- **Brightness and volume for external monitors.** ([#1193](https://github.com/abue-ammar/tinycast/issues/1193))
- **Fix accidental capitals as you type.** ([#1387](https://github.com/abue-ammar/tinycast/issues/1387))
- **Type into Translate with auto direction.** ([#1032](https://github.com/abue-ammar/tinycast/issues/1032))
- **The camera inside the palette.** It stays in its own window. ([#1578](https://github.com/abue-ammar/tinycast/issues/1578))
- **Spelling suggestions in Define Word.** ([#1551](https://github.com/abue-ammar/tinycast/issues/1551))
- **File Search extras:** Finder tags, folder search inside Finder or Open dialogs, Tab into a
  folder, play controls for audio and video, and two Quick Look shortcuts. File Search finds files,
  and that's all. ([#1001](https://github.com/abue-ammar/tinycast/issues/1001), [#326](https://github.com/abue-ammar/tinycast/issues/326), [#1125](https://github.com/abue-ammar/tinycast/issues/1125), [#685](https://github.com/abue-ammar/tinycast/issues/685), [#683](https://github.com/abue-ammar/tinycast/issues/683))
- **Fetch website icons for Quicklinks.** **Instead:** pick an icon yourself. ([#826](https://github.com/abue-ammar/tinycast/issues/826))

## Things macOS or other apps won't let us do

- **Move windows between Spaces.** macOS 27 removed the tool for this. Space switching uses a
  workaround that **may have to go** in a future release. ([#1157](https://github.com/abue-ammar/tinycast/issues/1157), [#417](https://github.com/abue-ammar/tinycast/issues/417))
- **Use the Spotlight shortcut.** macOS won't give a shortcut Spotlight owns to another app.
  **Instead:** turn off Spotlight's shortcut in System Settings first. ([#358](https://github.com/abue-ammar/tinycast/issues/358))
- **Read selected text in every app.** Many apps and websites don't share it. ([#1492](https://github.com/abue-ammar/tinycast/issues/1492), [#1420](https://github.com/abue-ammar/tinycast/issues/1420))
- **Another app's Quick Look plugin takes your keys** (like Obsidian's). ([#1607](https://github.com/abue-ammar/tinycast/issues/1607))
- **Duplicate images with Clop running.** ([#1582](https://github.com/abue-ammar/tinycast/issues/1582))
- **Notes opening again after you close it** with text selected. Apple's Writing Tools cause this.
  ([#1164](https://github.com/abue-ammar/tinycast/issues/1164))
- **One-time-password extensions that paste for you.** ([#829](https://github.com/abue-ammar/tinycast/issues/829))

## Not now, but maybe later

These are on hold, not ruled out.

- **Contacts search**, as a separate plugin. ([#1503](https://github.com/abue-ammar/tinycast/issues/1503))
- **Open files in a Finder replacement.** ([#1494](https://github.com/abue-ammar/tinycast/issues/1494))
- **Emoji names in the picker.** Long names don't fit yet. ([#965](https://github.com/abue-ammar/tinycast/issues/965))
- **Keep any window on top.** ([#527](https://github.com/abue-ammar/tinycast/issues/527))

---

## Before you open a request

1. Check this page first.
2. Ask yourself: does it keep Tinycast simple, light and fast?
3. If Raycast already does it well, Raycast may suit you better.
4. Want it anyway? Fork Tinycast and make it yours.

Thank you for your ideas and your understanding.
