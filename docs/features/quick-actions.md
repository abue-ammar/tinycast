# Quick Actions

Act on whatever text is selected, in whatever app is frontmost. Four of them — Fix Grammar, Rewrite,
Translate and Summarize — each with its own bindable shortcut **and its own launcher command**, both
listed in **Settings → Quick Actions**. Three go through the AI provider layer; Translate goes to
Apple's own translator. The result either replaces the selection or arrives in a floating panel, per
action.

Quick Actions is the provider layer's second consumer. It shares nothing with AI Chat but the
provider protocol and the connections behind it.

## Invariants

- **Off out of the box, and off means the shortcuts do nothing.** `AppSettings.quickActionsEnabled`
  is the flag and `QuickActionCoordinator` is the only place that reads it: no selection is read, no
  provider is built, no panel opens. The four commands leave the launcher's Commands slice through
  `AppIndex.setCommandsVisible`, the way Notes and AI Chat drop theirs. Carbon bindings stay
  registered, so re-enabling restores every shortcut without touching the hotkey layer. The flag
  grants keystroke delivery into other apps, so like `snippetsEnabled` it is excluded from settings
  backups — an import must never arm it.
- **One funnel, whichever way an action started.** A shortcut and a launcher row both land on
  `QuickActionCoordinator.run(_:)`, which reads `paletteCoordinator.targetApp` **before** hiding the
  palette — once the palette is gone, the frontmost app is Tinycast, and the action would read its
  own window. Hiding there rather than at each caller is what keeps the two paths identical.
- **Enabling is consent, and it is the only place Accessibility is requested.** The toggle confirms
  through `DialogController` first and then calls `Permissions.ensureAccessibility()`, the pattern
  `SnippetCoordinator.setSnippetsEnabled` established. Everything else — a shortcut press, a
  delivery — uses `isAccessibilityTrusted()` and degrades to a HUD.
- **Tinycast is never the target.** `QuickActionRunner.selection(in:using:)` refuses our own bundle
  identifier, and `TextInjector.targetAcceptsInjection` refuses it again before every event post,
  along with anything raised while Secure Event Input is up. A shortcut pressed with Settings
  frontmost, or in a password field, does nothing and says so.
- **One run at a time.** Two overlapping runs would race for one selection, and the second would
  replace text the first had already changed. `QuickActionCoordinator` holds a single task and
  refuses a second while it lives; a generation token stops a task that finishes after being
  replaced — by a retranslate, say — from clearing the newer handle.
- **`Model/` stays Foundation-only.** `quick-action-test` compiles that folder standalone, which is
  what keeps `FoundationModels`, `Translation` and `NaturalLanguage` in `Service/` and `UI/`.
- **Quick Actions route themselves.** `quickActionModel` is a second routing decision, defaulting to
  Apple Intelligence and falling back to chat's model. A shortcut pressed all day should not bill an
  API every time, and that is not a choice chat's default can make on its behalf.
- **The reader's own text gets permissive guardrails.** `AppCore.quickActionProvider()` asks for
  `SystemLanguageModel.Guardrails.permissiveContentTransformations`. The default filter is tuned for
  a model writing fresh prose and refuses to transform text somebody already wrote, which is the
  whole feature.
- **Built-in instructions treat the selection as untrusted input.** `QuickActionPrompt` tells the
  model that the text is material to work on and never instructions to follow, and that only the
  transformed text may come back — no preamble, no fences. Custom instructions replace these rules
  too. The output is pasted into somebody's document.
- **Each model action owns its instructions.** The pencil on Fix Grammar, Rewrite and Summarize opens
  a sheet prefilled with the exact built-in prompt. Saving replaces that prompt for only that action;
  Use Default restores it. Translate has no editor because no model handles translation.

## The actions

`QuickAction` is the extensibility story: a fifth action is one case there, its prompt in
`QuickActionPrompt`, and one `CommandID` case for its launcher row. The shortcut, the settings row
and the panel all read `allCases`, its shortcut is the `HotKeyAction.command(CommandID)` its launcher
row already has, and `CommandID.init(_ action:)` is exhaustive over `QuickAction`, so
a fifth cannot compile without a launcher command of its own.

| Action | Engine | Default result | Diff |
| --- | --- | --- | --- |
| Fix Grammar | provider | replaces directly | yes |
| Rewrite | provider | panel | yes |
| Translate | Apple Translation | panel | no |
| Summarize | provider | panel, always | no |

Custom instructions stay on this Mac and are excluded from settings backups, like chat's system
prompt, because importing them would change results without the reader seeing them first.

Only Fix Grammar applies unseen: it changes what was wrong, where a rewrite changes the voice.
Summarize can never be told to replace text unseen — it answers a question *about* the text, so
replacing the text with the answer has to be a choice made in the panel. Every other default is a
**Replace / Preview** popup in the pane — a popup rather than a second checkbox, because the trailing
checkbox column means "show in the launcher" in every pane the app has. `QuickActionSettings` stores
only what the reader actually changed, so a new action arrives with its own default rather than
whatever a missing key would have meant.

## Translation

`TextTranslator` uses Apple's translator rather than the language model: it runs on device, costs
nothing on every route, and a 3B model is markedly worse at it. `NLLanguageRecognizer` supplies the
source language, because `TranslationSession(installedSource:target:)` needs a concrete one and
`LanguageAvailability` reports only a status.

`TranslationError` is annotated `macOS 26.4` while the deployment floor is `26.0`, so failures are
caught as plain `Error` and reported by what was asked rather than by matching its cases.

**The picker offers Apple's own list, never the reader's preferred languages.** `supportedLanguages`
is 47 entries on macOS 26 and is the framework's to change; building the menu from
`Locale.preferredLanguages` instead would put a language the translator cannot reach in front of
someone, where it could only fail at press time. Notably **Bengali is not among the 47**. The list
loads asynchronously, so the coordinator holds it as observed state rather than a computed property.
Names come from `minimalIdentifier` — the maximal form carries the script, and `es` would read
"Spanish (Latin, Spain)" in a menu that should say "Spanish".

A pair that is supported but not downloaded **opens the panel**, whatever the action's usual result.
Fetching one needs SwiftUI's `translationTask`, and there is no other API for it — so the download
has a surface to live on rather than a shortcut that silently does nothing, and text is never
replaced once a download the reader never saw has finished.

## The panel

`QuickActionPanel` is Tinycast's **fourth borderless surface**, beside the dialog, the notes panel
and the join preview. It takes the same recipe — `panelScrim`, then `VisualEffectView`, then the
clip — and sits at `.floating` like the join preview, so a failure report still lands on top of it.
Its buttons are the system's own — `Button` with `.borderedProminent` on Replace — not a copy of
`DialogButton`. A dialog asks a question and styles its answers; this panel presents a result, and
standard controls are what a reader expects to act on one with.

It could not have been built on `HUDPresenter`: `HUDPanel` sets `ignoresMouseEvents` and returns
`false` from `canBecomeKey`, so it is click-through and hosts no buttons. Nor on `DialogAccessory`,
which is a closed two-case enum measured once at present time — a growing stream would clip.

Non-activating, so the target app keeps its selection while the panel holds key. Keys go through
`sendEvent`: `↵` replaces, `⌘C` copies, `esc` dismisses; click-away dismisses like every other
borderless surface. The panel is anchored by its **top-left** and re-measured as the reply arrives —
centring on every measure would walk it up the screen. `MarkdownView` and `MarkdownBlock.parse` are
reused from chat; neither takes palette state.

The body is a `ScrollView` with its height **set** rather than capped: a scroll view has no ideal
height, so `NSHostingView.fittingSize` measures it as nothing and the body collapses to a slot. The
content's ideal height is measured with `fixedSize` + `onGeometryChange`, the way the Support and
Updates windows size themselves.

The scroll view owns the **whole** panel and the bars are overlays on top, so a result dissolves
beneath them rather than stopping at a line. The mask is clear for each bar's height, ramps over
`quickActionScrollFade`, and the content is inset by bar + ramp — so the first line starts fully
opaque and only dissolves once it has scrolled up into the gradient. It is skipped entirely when the
result already fits, since dimming text that needs no scrolling reads as a defect.

Three things here were settled by rendering them, not by reasoning:
`scrollEdgeEffectStyle` draws nothing in this panel — it renders a material where a scroll view meets
a safe area, and over `panelScrim` + `VisualEffectView` that composites to nothing. `safeAreaBar`
makes it visible but lays its bars *over* the content instead of insetting it, so text runs through
the buttons and escapes the corner clip. And a ramp starting at the panel edge rather than below the
bar leaves text about 60% visible behind the title.

`TextDiffEngine` shows what changed when the output is the input, edited. Its LCS matrix is
quadratic, so past `maxTokens` a side it degrades to whole-text rather than asking for gigabytes.

## Reading the selection

Two tiers, in order. `AccessibilityText.read` asks for `kAXSelectedTextAttribute`, then the
text-marker range browsers use instead. `AXManualAccessibility` is set on the application element
first, because Chromium builds its accessibility tree only once something asks and Chrome, Electron
apps and VS Code otherwise answer every attribute with nothing.

When Accessibility yields nothing, `TextInjector.copySelection` borrows a ⌘C: snapshot the
pasteboard, synthesise the chord, wait for `changeCount` to **move**, read, restore. It lives on
`TextInjector` because the pasteboard has one owner — the same lease, queue and `ClipboardManager`
coordination a paste needs, and a second owner would race it.

**The `changeCount` guard is load-bearing.** With nothing selected, ⌘C is a no-op; returning the
pasteboard's existing contents there would transform whatever the reader last copied and paste it
over their selection. Movement is the only proof a copy happened — never comparing content, which
false-positives when the same text was already on the clipboard.

Copying is the fallback and never the first try: it synthesises a keystroke into somebody else's app.
When both tiers come back empty, only an Accessibility result of `.empty` justifies "nothing is
selected"; otherwise the app told us nothing either way and says so.

## Delivery

`TextInjector` — shared with Snippets and Quicklinks, and owned by `AppCore` — does the replacement.
`replaceSelection(with:in:)` takes the interactive path: no keyword to match, no generation to
cancel, because a shortcut is an explicit gesture rather than an expansion the app decided to
attempt. Its serial delivery queue is what stops two features fighting over the pasteboard lease.

The Accessibility tier replaces the live selection atomically, under the five-rule delivery contract
in [snippets.md](snippets.md#text-delivery-and-pasteboard-safety) — Quick Actions simply enter it with
no keyword, so rule 2 never applies. The event tiers behind it type or paste over the selection, which
every app treats as replacing it — but that is the target app's behaviour rather than something
Tinycast asserts, so it is the part worth checking by hand.

**A replacement that never lands says so, and keeps the reply.** Every tier can decline, and a shortcut
that quietly did nothing is indistinguishable from a shortcut that is not bound. `DeliveryCompletion`
now settles either way, so a delivery that returned early reports failure exactly once; Quick Actions
put the generated text on the clipboard and raise a HUD rather than dropping it. Snippets pass no
failure handler, so automatic expansion stays silent as before.

### Manual sweep

- Select text in Safari, Chrome, Brave, Slack, Mail, Notes, VS Code and Terminal, press Fix Grammar,
  and confirm the selection is **replaced** rather than appended to.
- In a Chromium target, run one on a **short** selection whose result stays under 100 characters on
  one line: the whole result lands, not its first four characters.
- Replace mode, with a slow route selected: the message pill says `Fixing Grammar…` with a blue
  spinner while the model works, and the result message takes its place.
- Run one from the launcher (⌘Space → "Fix Grammar") with text selected behind it: the palette
  closes and the selection in the displaced app is what gets acted on, not Tinycast's own field.
- Uncheck an action's launcher checkbox: the row leaves ⌘Space, and its shortcut still works.
- Press a shortcut with Tinycast's own Settings window frontmost: refused, with a HUD.
- Press one in a password field: refused.
- Summarize a long selection: the panel streams, grows without the title drifting, and scrolls past
  `quickActionPanelBody`.
- Replace Rewrite's instructions, confirm only Rewrite follows them after relaunch, then use the
  modal's default and confirm the shipped behaviour returns.
- Translate into a language that has not been downloaded: the panel offers the download, then
  translates.
- Revoke Accessibility while enabled: a HUD explains instead of failing silently.
- Harness: `quick-action-test` (action metadata, prompt boundaries, preview choices, diffs).
