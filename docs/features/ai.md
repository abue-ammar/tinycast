# AI providers and chat

Tinycast has one app-wide provider layer for features that need text generation. Settings chooses the
default model; callers ask `AppCore.aiProvider()` for the current provider and stream an `AIRequest`.
AI Chat is the first consumer, but the provider layer does not depend on it.

## Invariants

- **AI is off out of the box, and off means fully off.** `AppSettings.aiEnabled` is the flag and
  `AIChatCoordinator.applyEnabled()` is the only place that projects it: no `AI Chat` command in the
  launcher, no history database opened or created, no Codex helper resident, and the palette leaves
  `.ai`. Turning it off cancels a streaming reply and drops the transcript, but touches neither the
  saved conversations in `ai-chats.sqlite3` nor a Keychain key. `aiEnabled` is excluded from settings
  backups like every other AI key, so an import can never arm a feature it cannot configure.
- **Every request carries Tinycast's own preamble, and the user's text goes after it.**
  `AIInstructions.compose` builds `AIRequest.instructions`: a fixed preamble that tells the model
  where it is running and what the app can do, then whatever Settings → AI holds. The preamble
  states capabilities and asks for honest comparisons; it does not instruct the model to favour
  Tinycast over anything else. It is not shown in the pane, and `AIPreamble.swift` holds the only
  copy of it — edit the prompt there, not here. `compose` returns `nil` when the user has turned
  the system prompt off, and every transport drops a nil instruction, so a turn then carries none.
- **API keys live only in the login Keychain.** `AIConnection` persists the provider, endpoint and
  model identifiers in `UserDefaults`; it never contains a key. Keys are addressed by connection UUID
  through `APIKeyStore`, and never enter logs, errors or settings backups. A key is issued for one
  endpoint and never follows a connection retargeted at another — change the provider or base URL and
  both model discovery and Save ask for a new key, rather than introduce the saved one to a host it
  was never meant to reach (`AIEndpointPolicy.sameDestination`).
- **Remote endpoints require HTTPS.** Plain HTTP is accepted only for `localhost`, `127.0.0.1` and
  `::1`, where a key is optional, and any other scheme is rejected outright — a loopback host does
  not excuse `ftp://`. `AIEndpointPolicy` is the one place that decides this.
- **The default model is the routing decision.** It names either one saved API connection and model or
  one ChatGPT subscription model and reasoning effort. A removed connection, model or subscription
  falls forward to another usable API model, or to no selection.
- **ChatGPT subscription access stays separate from API-key billing.** It uses `codex app-server` with
  a private `CODEX_HOME` under Tinycast's Application Support directory. Tinycast never reads browser
  cookies, copies another Codex login or calls undocumented ChatGPT web endpoints.
- **Codex tools are unavailable.** The app-server launches with tool capabilities disabled, approvals
  set to never and a read-only, network-disabled sandbox. Any server approval request is declined.
- **Every HTTP request uses a private ephemeral `URLSession` with no URL cache.** Provider traffic must
  not create a second credential or response cache on disk.
- **`Model/` stays Foundation-only.** `ai-provider-test` compiles the shipped provider models and pins
  endpoints, stream parsing, persistence repair and Codex protocol framing.
- **Chat is a palette screen, not another window.** The launcher command enters `.ai`; its search field
  is the composer, and the shared footer's primary pill is Return's job: Send (`↵`), or Stop (`↵`)
  while a response streams — followed by Actions (`⌘K`), which owns New Chat.
- **History is local and lazy.** Conversation summaries stay in memory while transcripts load from the
  system SQLite database only for the selected preview or opened chat. Empty chats are never saved.
- **Everything but the newest message is bounded.** `ChatSession.boundedContext` sends that message
  whole — truncating what someone just typed is worse than the provider's own error — keeps images
  only on that turn and only up to `AIAttachmentBudget`, and walks older text newest-first into a
  ~100 KB budget; both transports funnel through `requestMessages`, so no route can resend every
  image each turn or let history grow the payload as a chat goes on. The composer refuses a picture
  past the budget and says so, rather than letting send time drop it silently.

## Connections and routing

`AIProviderKind` exposes four named presets plus a custom OpenAI-compatible route:

| Setting | Transport | Default base URL |
| --- | --- | --- |
| OpenAI API | OpenAI Chat Completions | `https://api.openai.com/v1` |
| Anthropic Claude | Anthropic Messages | `https://api.anthropic.com` |
| Google Gemini | Gemini's OpenAI-compatible API | `https://generativelanguage.googleapis.com/v1beta/openai` |
| OpenRouter | OpenAI-compatible | `https://openrouter.ai/api/v1` |
| OpenAI Compatible | OpenAI-compatible | user-editable |

The base URL stays editable for every preset because gateways and organization proxies are legitimate
destinations. `AIHTTPConfiguration.endpointURL` accepts a complete endpoint or appends the transport's
completion path. Gemini requests identify Tinycast through `x-goog-api-client`; OpenRouter requests
carry the app title.

Each connection has an ordered, deduplicated list of exact model identifiers. While its editor is open,
Tinycast asks the configured provider for the models available to the entered key and uses the result
for search-as-you-type completion and validation. It never renders the whole provider catalog at once;
selected models stay visible and search shows at most twelve additions. Discovery is debounced,
cacheless and never persists the typed key. A
custom gateway may not implement a model-list endpoint, so exact identifiers can always be entered
manually. Tinycast does not ship or guess a catalog that can become stale. ChatGPT models are different
because the app-server returns the models and reasoning efforts the signed-in account can actually use.

## Provider interface

`AIProvider.stream(_:)` accepts provider-neutral messages, optional instructions and a maximum output
token count. It returns an `AsyncThrowingStream` of text, thinking state, usage and completion. OpenAI-
compatible reasoning fields are surfaced as `.thinking`, never mixed into answer text. Anthropic
system messages are lifted into its top-level `system` field; the other HTTP routes keep system
messages in the OpenAI message array.

`AIProviderFactory` resolves the selection, validates the endpoint, reads the key at the last possible
moment and returns either `HTTPAIProvider` or `ChatGPTSubscriptionProvider`. A future feature should
hold neither settings nor credentials itself.

## Chat surface

The built-in `AI Chat` launcher command enters `AIScreen`, and carries a bindable global shortcut
(`HotKeyAction.aiChat`) that does the same thing from any app. Settings → AI holds both the recorder and
a checkbox for the command's place in launcher search; the shortcut keeps working while the command is
hidden, and does nothing at all while the feature is off. The palette search field becomes the
single-line composer. The footer pill and Return are one action, `activate`: Send, or Stop while a
response streams — an empty composer sends nothing, so the pill never needs a disabled state. The
header's trailing model switcher uses the same in-window menu control as Clipboard's type filter and
changes the app-wide default route for the next message. It does not interrupt a response already
streaming; stopping one is the pill's job, so the header never has to fit a third control beside the
switcher.

The second footer control is the palette's normal Actions (`⌘K`) menu. It owns New Chat, Chat History
and AI Settings, plus Stop Response and Copy Last Response when those actions apply. Chat adds no
separate footer design and no independent window.

`AIChatState` turns provider-neutral stream events into one live assistant message. Thinking state is
shown without entering the transcript, partial text is preserved on failure, cancellation invalidates
the active generation, and only completed assistant messages become context for the next request.
Assistant replies render Markdown; user messages remain literal. A reply keeps streaming while the
palette is hidden or showing another screen — the state is `AppCore`'s, not the view's — and is
saved when it finishes; only Stop, New Chat, deleting the chat or quitting cut it short.

`ChatHistoryStore` writes `ai-chats.sqlite3` below the bundle-specific Application Support directory.
It uses the system SQLite already linked by Tinycast, stores no provider credentials, and repairs a
reply left streaming by a prior process into an interrupted failure when loaded.

## Palette integration

Two palette modes carry the feature, and neither changes the shell's rules:

| Mode | Screen | Body |
| --- | --- | --- |
| `.ai` | `AIScreen` | `ChatTranscriptView` |
| `.aiHistory` | `ChatHistoryScreen` | `ChatHistoryList` + preview, bucketed by day like Clipboard |

Chat History backs out to Chat; both are sub-screens, so the header shows the back chevron. The
search field is the composer: Return submits, or stops a streaming response, and the footer pill
reads Send `↵` / Stop `↵` to match. The model switcher is a `HeaderMenuButton` — the
active label, glyph and disclosure chevron layered over `BarButton` — which is also what Clipboard's
type filter is now, so the two header menus hover and open identically. Its menu is the palette's
fourth `OpenMenu` case, `.topTrailing` like the type filter, and it opens on the selected model. Each
row leads with the vendor's mark — `AIBrand` resolves it from a native connection's provider, or for
OpenRouter and OpenAI-compatible endpoints from the model id (`anthropic/claude-…`, `deepseek-chat`,
`o4-mini`). The marks are ~300 B–2 KB monochrome template SVGs in `Assets.xcassets` (`AIBrand*`),
twelve from Simple Icons and Z.ai from `@lobehub/icons`, so they tint with the row like a symbol; an
unrecognised model keeps the generic sparkle. Provenance, the MIT notice and the trademark position
are recorded in [`NOTICE.md`](../../NOTICE.md) — the CC0 on the Simple Icons project does not extend
to the brands it depicts. The header's model switcher shows the selected model's mark the same way.

The palette's click-away catcher is mounted permanently and only toggles `allowsHitTesting` with the
open menu. Inserting it on open and removing it on close could strand SwiftUI's hover target on the
header button underneath — AppKit kept delivering clicks, but neither the button nor the catcher saw
them until an unrelated render or a window exit/re-enter recomputed hover. It dismisses on a
`DragGesture(minimumDistance: 0)` rather than a tap, so a press that drifts a few points still closes
the menu, as a native menu's click-away does.

Four more `@MainActor @Observable` types join the shared state: `AISettingsStore`,
`ChatGPTSubscriptionManager`, `ChatHistoryStore` and `AIChatState`. `AIChatCoordinator` is the
nineteenth feature coordinator.

### Manual sweep

- The selected model appears at the right of the composer and truncates without crowding typed text.
- Clicking it opens the same anchored menu shape as Clipboard's type filter; arrows, Return and Escape
  operate the menu without changing the draft.
- Repeatedly clicking either the model switcher or the type filter opens and closes every time, even
  when the next click lands immediately after dismissal or a few points off the first one.
- Selecting a model updates the button immediately and the next message reaches that route.
- Switching while a response streams does not stop or reroute that response; the new model applies to
  the following message.
- With no available model, the menu offers Configure AI and opens the AI Settings pane.
- Harnesses: `ai-provider-test` (endpoints, stream decoding, persistence repair, Codex framing),
  `ai-chat-test` (`ChatSession`, `MarkdownBlock`, `ChatHistoryStore`) and `codex-turn-test` (the Stop
  path, driven against a stub app-server stalled where Stop races the turn ID), all in
  `run-tests.sh`.

## ChatGPT subscription

`ChatGPTSubscriptionManager` owns the private app-server's lifecycle and the login: it starts the
server only for a stored sign-in (`auth.json` in the private home) or an explicit Connect, stops it
after ten idle minutes — counted from a failed or still-waiting Connect too, so a sign-in abandoned
in the browser cannot leave the server resident — and restarts it on demand;
`AppCore.prepareForTermination()` stops it for good, by closing stdin first and SIGTERM a second
later. Switching AI off stops it the same way. `stop()` also resets the manager to `.idle` and forgets
the account, so nothing claims a server that is gone and the next visit checks again; a check cancelled
on the way out publishes no verdict. Browser login uses `account/login/start`;
account state, model availability and rate-limit windows come from the app-server. The `codex`
binary is the user's own — found on the app's PATH, the usual install locations, or by asking the
login shell — and is never installed by Tinycast; Settings links to the install docs instead.

`CodexTurnRunner` is the generation half, the `AIProvider` behind `ChatGPTSubscriptionProvider`.

It creates an ephemeral thread for each request, injects prior user/assistant messages, and
streams agent-message deltas, plus `item/started` for the reasoning and web-search items that feed the
bubble's status line. System messages become developer instructions alongside Tinycast's fixed
no-tools boundary. Cancellation interrupts the active turn, including one the server has started but
not yet named: Stop arms that thread, and whichever of `turn/started` or the `turn/start` response
names the turn first spends a single `turn/interrupt` on it.

Web search is thread-scoped config (`thread/start.config.web_search`, `live` or `disabled`) written
into Tinycast's private Codex home, never the user's `~/.codex`; the developer instructions say whether
the model may reach the web so the two can't disagree. Images go out as `image` input parts with data
URLs, and as `input_image` when prior turns are injected.

## Web search and images

`AIRequest.webSearch` and `AIMessage.images` are provider-neutral; each route maps them itself:

| Route | Web search | Images |
| --- | --- | --- |
| ChatGPT subscription | Codex `web_search` config | `image` input part |
| OpenRouter | `plugins: [{id: "web"}]` — OpenRouter's own layer, any model | `image_url` part, only for models whose catalog lists the `image` modality |
| OpenAI / Gemini / compatible | not offered | `image_url` part, assumed supported |
| Anthropic | not offered | base64 `image` block |

A search is part of the reply, not a status: `item/started` for a `webSearch` item appends a
`ChatSearch` to the streaming message pinned at the text length so far, `item/completed` (or the
next text delta, or the turn ending) marks it finished and fills in the query if the start didn't
carry it. `ChatMessage.segments` splits the text around its searches so the transcript renders
text, a search row (spinner → globe, "Searching web" → "Searched web · query"), then the rest, in
the order it happened. Searches persist in `message_searches`. OpenRouter's web plugin is invisible
to the stream, so it shows none. The web-search instructions ask for citations linked by the
publication's name — the model otherwise labels them "Read more".

`AIModelCapabilities` says what the footer may offer for the selected model. OpenRouter is the only
catalog that reports `architecture.input_modalities`, so it is the only provider gated on it:
Settings records a model into `AIConnection.visionModels` when it is added from that catalog, and a
model added by hand is assumed text-only. A vendor API is assumed to take images; a model that
doesn't simply returns the provider's error.

Web search is a Settings → AI toggle, `aiWebSearch`, off by default: a prompt reaches a search engine
only once the user has opted in.
It's still excluded from backups — which Mac may send prompts to a search engine is that Mac's call.
Nothing gates images: a model that takes them gets them, one that doesn't is never offered one.

Attachments arrive by ⌘V. `PaletteWindowController`'s command-shortcut hook gives chat the chord
first; a pasteboard holding an image file URL or a bare image (a screenshot) stages it as a
`ChatAttachment`, while anything carrying text falls through to the field editor as a normal paste.
Images are re-encoded to PNG and bounded to 1568px on the long edge, off-main on a detached task so
a display-sized screenshot does not decode on the keystroke; one past `AIAttachmentBudget` is refused
with a HUD instead of being staged. Because that decode outlives the keystroke, it shares the staged
images' lifetime exactly: whatever consumes or clears them — a send, a new chat, Remove Attachments,
or leaving the conversation for another through history — disowns one still in flight and says so,
rather than letting it surface on a later message. The counter that decides this sits on
`AIChatState` beside the staged images, so a route that drops them cannot forget to move it. A
staged image shows as a pill — a photo glyph plus file name, or "Image" for a screenshot; the row is
too thin for a thumbnail to read — beside the typed text, through the same `headerAccessory` the
launcher's argument fields use, so the field shrinks to its text and the chip
follows it rather than the composer growing. Bare backspace on an empty composer removes the last
chip before it backs out of chat; ⌘K → Remove Attachments clears them all. Sent images persist in
`message_images` beside their message and render as thumbnails in the user bubble.

The switcher's glyph comes from the selection — ChatGPT is OpenAI's mark, an API model resolves
through its connection — never from `modelOptions`, which for ChatGPT is empty until the app-server
has answered `model/list`; opening the chat on a ChatGPT model warms that list so the title is the
display name from the first frame. Tab is a no-op in chat and history: `toggleMode` swaps the mode
without `prepare`, which would carry the draft into the launcher's field.

The model switcher is `fixedSize` with its title shortened in `AIChatCoordinator` (26 characters,
middle ellipsis) rather than truncated by layout: a flexible label claimed the row up to its max
width and clipped the search field well short of the button.

## Settings and backup boundary

Settings → AI is a normal grouped `Form` inside Tinycast's existing Settings window. It owns no
separate settings window or palette overlay. The pane edits multiple API connections, manages the
ChatGPT login and chooses the one default model shared by future features.

The signed-in ChatGPT address is the one thing on the pane that names a person, and a Settings pane
is what gets screenshotted into a bug report or left on screen in a recording, so `RedactedText`
shows it scrambled and blurred until it is clicked. `RedactedPlaceholder` derives the stand-in from
the address itself — stable across redraws, same length, `@ . - _` left in place — because a blurred
real address can be recovered from a still frame while a blurred fake one cannot. It hides an
address from a camera, not a secret from an attacker: the length still shows and one click undoes
it. The scramble is not selectable, since dragging it out would only ever yield the stand-in.

The System prompt box appends to the preamble rather than replacing it, so the model never loses
the ground truth about where it is. `SystemPromptEditor` opens blurred and non-editable whenever it
already holds something — a Settings pane is exactly what ends up in a screenshot or a stream — and
opens plain when it is empty, since a blurred empty box is only a puzzle. The footer says the text
rides along on every turn, because it is billed on every turn and nothing else in the pane is.

`Send a system prompt` governs the whole instruction, not just the half the user typed. Clearing the
box already withholds their own text, so a switch that spared the preamble would add nothing; the
preamble is the part that is billed on every turn for every user and has no other way off. Off
disables the editor rather than hiding it, so what is being withheld stays readable. One thing it
deliberately cannot reach: the Codex route always prepends its own instruction never to invoke
tools, run commands or touch files. That is a sandbox boundary on a local CLI, not Tinycast
describing itself, and a user switch must not be able to lift it.

`aiConnections`, `aiDefaultModel`, `aiSystemPrompt` and `aiSystemPromptEnabled` are deliberately
excluded from settings backups. The first is meaningless without machine-local Keychain items; the
second names an external destination and must not silently redirect AI traffic after an import; the
last two are standing instructions and the switch that sends them, both of which change every
answer and must not arrive on another Mac unread.
