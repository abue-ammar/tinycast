# AI providers and chat

Tinycast has one app-wide provider layer for features that need text generation. Chat chooses its
model from Quick AI's header or the AI Chat composer, and `AIChatCoordinator.provider(for:)`
builds that chat's route through `AIProviderFactory` to stream an `AIRequest`.
Chat is the first consumer and [Quick Actions](quick-actions.md) the second; the provider layer
depends on neither, and Quick Actions carries its own route rather than borrowing this one.

Chat has two surfaces over one history, as Raycast's does. **Quick AI** is the palette screen: Tab
from the launcher asks what you typed, and the answer appears in place. **AI Chat** is a window —
saved conversations in a sidebar on the left, the open one on the right, and a composer at the
bottom with the model picker. ⌘J hands a Quick AI conversation to the window.

## Invariants

- **AI is off out of the box, and off means fully off.** `AppSettings.aiEnabled` is the flag:
  no `Quick AI` or `AI Chat` command in the launcher, no history database opened or created, no Codex
  helper for chat, no stop for it on Tab's ring, the palette leaves `.ai` and the window closes.
  Installed providers may still remain available for Quick Actions, which has its own switch and route. Turning AI off cancels
  every streaming reply and drops both transcripts, but touches neither the saved conversations in
  `ai-chats.sqlite3` nor a Keychain key. `aiEnabled` is excluded from settings backups like every
  other AI key, so an import can never arm a feature it cannot configure.
- **Installed model discovery is per-provider.** Settings → AI → Providers keeps Codex, Claude, Grok,
  OpenCode and Cursor visible with an individual toggle for each, all off by default. Turning one off cancels
  its check, clears its catalog and releases its process; Apple Intelligence is the default route when
  available, and saved API connections stay available.
- **Every request carries Tinycast's own preamble, and the user's text goes after it.**
  `AIInstructions.compose` builds `AIRequest.instructions`: a fixed preamble that tells the model
  where it is running and what the app can do, then whatever Settings → AI holds. The preamble
  keeps the model a general-purpose assistant — the app facts are reference for when the user asks,
  never a scope limit — and asks for honest comparisons; it does not instruct the model to favour
  Tinycast over anything else. It is not shown in the pane, and `AIPreamble.swift` holds the only
  copy of it — edit the prompt there, not here. `compose` returns `nil` when the user has turned
  the system prompt off, and every transport drops a nil instruction, so a turn then carries none.
- **API keys live only in the login Keychain.** `AIConnection` persists the provider, endpoint and
  model identifiers in `UserDefaults`; it never contains a key. Keys are addressed by connection UUID
  through `KeychainSecretStore.aiAPIKeys`, and never enter logs, errors or settings backups. A key is issued for one
  endpoint and never follows a connection retargeted at another — change the provider or base URL and
  both model discovery and Save ask for a new key, rather than introduce the saved one to a host it
  was never meant to reach (`AIEndpointPolicy.sameDestination`).
- **Remote endpoints require HTTPS.** Plain HTTP is accepted only for `localhost`, `127.0.0.1` and
  `::1`, where a key is optional, and any other scheme is rejected outright — a loopback host does
  not excuse `ftp://`. `AIEndpointPolicy` is the one place that decides this.
- **MCP OAuth is separate from the model provider's login.** The HTTP MCP client can sign into a
  hosted server from Settings and keep its client credentials and tokens in that server's Keychain
  item. API chat uses this session without receiving its credentials. A rejected refresh becomes
  Sign-in required on the server, an unserved one does not end the session, and either way a
  running tool loop receives an explainable failure result. The same session is lent to the Codex
  and Claude routes as a bearer header, so a hosted server is signed into once for every route.
  See [MCP](mcp.md).
- **The chat model is the routing decision.** It names the on-device model, a model exposed by the
  installed Codex, Claude, Grok, OpenCode or Cursor command, or one saved API connection and model. Installed
  routes also carry their reasoning effort when the selected model supports one. A removed route
  falls forward to the on-device model when this Mac
  has one, then to another usable API model, then to no selection. Discovering an installed command
  never silently selects a networked model.
- **Every chat keeps its own model.** `ChatSession.model` is stamped on the first send and changed by
  either surface's picker; `conversation_details` stores it, so reopening a chat reopens its model and
  effort. A pick also moves the app default, which is only what a *new* chat starts on. A chat whose
  route was removed in Settings answers on the default rather than failing
  (`AIChatCoordinator.model(for:)`), and keeps its stored pick in case the route comes back.
- **Reasoning is shown, folded, and never resent.** `AIStreamEvent.reasoning` carries the text a route
  shares — OpenAI-shaped `reasoning` / `reasoning_content` / `reasoning_details`, Anthropic and
  Claude-CLI `thinking_delta`, Codex's reasoning summary — into `ChatMessage.reasoning`, a list of
  `ChatReasoning` blocks. Thinking that resumes after answer text opens a new block pinned at that
  text offset, so `segments` places it where it happened, like a search or a tool call; each block
  is timed until the answer resumes. The transcript folds each under "Thought for Ns";
  `message_thinking` keeps them; `requestMessages` never sends them back. A route that only says
  it is thinking still just shows "Thinking…". How much there is to read is the route's call:
  Claude streams full summaries, while Grok's CLI sends a line or two in the clear and the rest of
  its reasoning encrypted, so a Grok fold is short by design, not by truncation.
- **A chat is named by its harness.** As soon as a chat's first question is sent — so the title
  lands while the answer streams — again after an answer if that failed, and never over a rename,
  `AIChatCoordinator.nameIfNeeded` asks for a title: Claude's CLI through its own
  `generate_session_title` control request (`persist: false`, so nothing enters its history), every
  other route with one side request to the chat's own model (`ChatTitle.instructions`). The Claude
  request holds stdin open and reads with `availableData` until the answering line is whole: a
  `read(upToCount:)` waits for a full chunk or EOF, which left every title waiting on the watchdog.
  `ChatTitle.sanitize` strips labels, quotes and full stops; `conversation_details` keeps the
  result, and `displayTitle` prefers a rename, then this, then the first question.
- **A reply's links are its sources.** `ChatReferences.extract` gathers the web links of a finished
  reply — Markdown links by their own names, bare URLs by host and path — in the order cited, one
  per page, skipping code, and both surfaces list them under the reply as numbered glass chips that
  open in the browser. The same numbers close the sentence that cited each source, as a raised,
  linked `[n]`: `ChatCitations` finds each link's sentence end in the drawn text and inserts after
  it, two sources in one sentence sharing it, so prose and chips always agree. The preamble asks the model to link a page it relies on inline, so a cited
  answer carries its sources without a second request.
- **Tools are chosen per chat.** The composer's tools menu switches MCP off for the chat or turns
  single servers off (`ChatToolScope`, held on `AIChatState`, not stored); `@server` still narrows
  one turn inside that. The scope binds both shapes alike: Tinycast's loop is offered only the
  allowed servers' tools, and a Codex or Claude turn is handed only the allowed servers. A route that
  cannot call tools shows the menu disabled and says why.
- **A reply can end on choices, and a choice is only ever a message.** The preamble lets the model
  close a reply with a fenced `choices` block, one option per line. `ChatChoices.split` lifts the
  fence out of the prose (an unclosed one mid-stream too, so it never flashes as code). Apple's
  on-device model tends to drop the fence and write a bare `choices` line over a list, so a
  label on its own line with nothing but list items after it, to the reply's end, counts too; and
  `ChatSuggestionChips` draws the options as glass capsules: in the window they rise out of the
  composer, sitting on its top edge until the reader starts typing; in Quick AI they close the
  transcript. A click sends the option as the reader's next message, through the same `send` a
  typed one takes. Older replies lose their chips, since only the last question is still open. It is text in, text out, so it
  works on every route — and not at all with the system prompt switched off, which drops the
  preamble that describes it.
- **Token usage belongs to the reply that reported it.** `AIUsage` carries input, output, cached
  prompt and thinking tokens, and the model's window and cost where a route says them — Claude's CLI
  reports all of it, the Anthropic API its cache, OpenAI-shaped routes their reasoning tokens and
  OpenRouter its cost. `ChatMessage.usage` holds it and `message_details` keeps it, so a reopened chat
  still knows its last turn.
- **The on-device route is configured by having a Mac.** `.appleIntelligence` takes no key, opens no
  socket and names no endpoint, so the Keychain, HTTPS and ephemeral-session rules below have nothing
  to bind to — the Settings pane must never grow a credential field for it. It is text-only and
  offers no web search, the preamble still rides ahead of every turn, and history is bounded to
  `AppleIntelligence.contextBudget` rather than the cloud routes' ~100 KB because the on-device window
  holds a prompt and its reply together. Availability is asked for each time, never cached at launch:
  the model finishes downloading mid-session, and reading it inside a view body leaves SwiftUI
  observing the framework's own state.
- **An unavailable on-device model is reported, never rerouted.** Fall-forward exists for a route the
  reader *removed*; a Mac with Apple Intelligence switched off keeps its stored selection and is told
  why, because silently moving someone from a free, private, local model onto a billed endpoint is
  the one redirection this feature must never perform.
- **Installed commands reuse their own login.** Tinycast launches the user's `codex`, `claude`, `grok` or
  `opencode` executable without asking for or storing another key. Codex inherits the user's normal
  home and credential-store setting; Claude, Grok, OpenCode and Cursor inherit their normal configuration. Tinycast
  never reads those credential files, browser cookies or undocumented web endpoints.
- **Codex runs Tinycast's MCP servers and nothing else.** The app-server still launches with every
  feature flag off and a read-only, network-disabled sandbox, and every server request but one is
  declined. What changed is the list: the servers the reader configured for their own Codex are
  disabled by name at launch — which they were not before, so they used to start inside Tinycast
  threads — and the servers [MCP](mcp.md) supplies take their place when a chat has any, under
  names of their own (`tinycast-<handle>`) so that no table of the reader's merges into one. A
  launch that cannot read the reader's list, or cannot address a name on it, does not start. A turn
  that arms none keeps `approvalPolicy: "never"`; a turn that arms some uses `"untrusted"`, where
  a tool call becomes an elicitation Tinycast answers from the reader's own trust setting.
- **Tool calling is a decorator, except where the CLI is the client.** `AIToolLoopProvider` wraps a
  route and re-streams the turn until the model stops asking, so a route with no tools behaves
  exactly as it did and `AIChatState` reduces one more pair of events. Codex and the Claude command
  run that loop themselves, so `AIModelSelection.runsItsOwnTools` hands them an
  `AIToolServerSession` instead of a wrapper — same servers, same trust, same rows, and the same
  round cap counted in whatever unit the CLI counts in. Only chat wraps or arms: `quickActionProvider()`
  rewrites the reader's own selected text and has nothing to call. A turn's tool messages stay inside
  the loop — what the transcript keeps is a `ChatToolUse` record, pinned at a text offset like a
  search, so `boundedContext` can never separate a stored call from its result.
- **Every HTTP request uses a private ephemeral `URLSession` with no URL cache.** Provider traffic must
  not create a second credential or response cache on disk.
- **`Model/` stays Foundation-only.** `ai-provider-test` compiles the shipped provider models and pins
  endpoints, request bodies, stream parsing, persistence repair, Codex protocol framing and both
  CLI routes' MCP launch encodings. Request
  bodies are `AIRequestBody`'s, in `Model/`, precisely so a wrong shape fails a harness rather than a
  conversation. `installed-ai-test` runs the Claude, Grok, OpenCode and Cursor adapters against real
  subprocess stubs and pins their safety boundaries.
- **Grok, OpenCode and Cursor are text transports, not agents, and so is Claude with no server to
  run.** Claude runs one turn with no tools, browser integration, slash commands or persisted
  session — but never `--bare`, which reads neither
  OAuth nor the keychain and so refuses the very sign-in this route reuses. Given servers by
  [MCP](mcp.md) it becomes an agent for that turn and only over those: `--tools ""` still withholds
  every built-in, the turn keeps its stream-json stdin open so consent has a pipe to answer on,
  `--disallowedTools "*"` comes off because it removes the MCP tools too, `--max-turns` carries
  the round cap instead of the constant 1, or is left out on Unlimited, and
  `--permission-mode default` with an ask rule per server keeps the reader's own allow rules and
  default mode from answering before Tinycast does.
  Grok runs with `--deny *`,
  `dontAsk` permissions and a workspace sandbox, and never `--always-approve`, so a user's always-approve
  config cannot arm tools for this route. OpenCode runs `--pure` with deny-all permissions, disabled
  sharing and a private working directory. Cursor runs `agent -p --mode ask` with `--trust` against
  Tinycast's private workspace and never `--force` / `--yolo` / `--approve-mcps`; ask mode blocks edits.
  Each deletes the session or chat it created once the child exits, and Tinycast never reaches into the
  user's own config to do it. **Only Claude keeps the user's MCP servers out of the process**, through
  `--strict-mcp-config` — whether the config it names is empty or Tinycast's own — and even that
  yields to an installed managed MCP policy, which makes the CLI reject both flags and leaves MCP
  on that route the organization's decision; the Providers row says so.
  Grok, OpenCode and Cursor load the global config either way,
  because their configs merge with no opt-out; what refuses the call is `--deny *` for Grok,
  `permission: deny` for OpenCode and withheld MCP approval for Cursor. Cursor's is the only one resting
  on an approval prompt rather than an explicit deny, which is why its Providers row says so and the
  others do not. That is also why none of the three may be handed a server: there is no way to offer
  one without offering the reader's own. None of these routes offer web search, and only Claude
  takes images: every Claude turn is one `--input-format stream-json` user message, the newest
  question's pictures as base64 `image` blocks beside the framed prompt. Claude also runs with
  `--thinking-display summarized` — a hidden flag, and the only switch that works: a `-p` run forces
  its display to `omitted` unless one is named explicitly, and the `showThinkingSummaries` setting
  is read only by an interactive session. Without it Sonnet and Opus stream every thinking block
  empty, so the fold would show one opening line.
- **A conversation is live in one place at a time.** `AIChatSurfacesState` holds Quick AI's
  `AIChatState`, the window's, and any window chat left mid-reply. Opening a chat anywhere takes the
  live state from wherever it already is — ⌘J moves Quick AI's whole state object, reply, staged
  files and all, into the window — and Quick AI will not take a chat the window has: its open policy
  starts fresh instead, and Chat History opens that chat in the window. Two states editing one
  transcript would each save over the other, and `ChatHistoryStore.save` rewrites the stored tail
  from memory.
- **Leaving a chat never cancels it.** Switching the window to another conversation, or starting a
  new one, parks a streaming reply rather than stopping it; it saves itself when it ends, the sidebar
  shows its spinner meanwhile, and reopening it resumes the same live state. Only Stop, deleting the
  chat, turning AI off or quitting cut a reply short. A reply is the conversation's, which is
  `AppCore`'s, so closing the window cancels nothing either.
  Codex chats run side by side too: each request gets its own ephemeral app-server thread, and
  `CodexTurnRunner` routes every notification and every tool-call question to its turn by
  `threadId`, so a Stop ends only its own. The app-server's server list is fixed at launch, so a
  turn armed with a different one relaunches it and ends the other chats' live threads with a
  reason, rather than leaving them waiting on a process that is gone.
- **Quick AI's lifetime is decided on the way in.** Pop to Root forgets the screen and the query;
  whether the next summon resumes the transcript is Settings → AI's `Quick AI opens to`, applied in
  `QuickAICoordinator.applyOpenPolicy` on the way into `.ai`. That used to be Pop to Root's job by
  accident — it fires on every hide, so a chat never survived Escape — and deciding at open time from
  a timestamp leaves one clock instead of two racing over the same state, and a verdict that still
  holds after a relaunch. A reply still streaming is never reset out from under the reader — it was
  asked for — and the transcript is saved regardless, so the old conversation is one ⌘K → Chat
  History away, and in the window's sidebar. The window has no policy: it reopens on whatever it
  last showed.
- **Arriving with a question skips the open policy entirely.** `ask(_:)` — ⇥ from the launcher, and
  the Quick AI fallback row — always starts a new chat and submits the text, because a question asked
  outright is not a summon: resuming a transcript to append an unrelated line to it would be the one
  reading of `Quick AI opens to` nobody wants. It is `showPalette(mode: .ai)` and `send`, never
  `show`.
- **Staged files survive a re-summon; only the typed draft does not.** `applyOpenPolicy` treats a
  pasted-but-unsent attachment as resident state: `Recent Conversation` will not open a saved chat
  over one, and `A New Conversation` resets only a chat that actually has messages, since an empty
  chat is already new and resetting it would drop the file for nothing. A file cost a read and a
  decode, which is not the same as a half-typed line — that is still dropped by `prepare`.
  ⌘J carries them into the window with the conversation; opening another chat there still disowns
  a state's own, which is the rule they belong to.
- **`AIConversationOpenPolicy` is the whole rule, and it is pure.** `Recent Conversation` resumes the
  resident transcript, or reopens the newest saved one when nothing is resident, unless it has been
  idle past `Start a new conversation after`; `A New Conversation` always starts fresh. There is no
  third setting for "immediately" because that *is* `A New Conversation` — two controls able to
  express one state would only ever disagree.
- **History is local and lazy.** Conversation summaries stay in memory while transcripts load from the
  system SQLite database only for the opened chat. Empty chats are never saved.
- **A rename and a pin are the reader's, and nothing derived overwrites them.** Both live in
  `conversation_details` beside `conversations`, whose `title` stays the first question: every save
  rewrites that summary, so a rename stored there would be undone by the next turn. A blank rename
  hands the title back. The same row holds the harness's title and the chat's model, each column
  upserted on its own so no write clobbers another; `message_details` is its per-message twin, for a
  question's `@server` scope and a reply's usage. Both tables are `CREATE TABLE IF NOT EXISTS` with
  `ON DELETE CASCADE`, so they needed no migration and a deleted chat takes its facts with it.
- **Pinned chats are the ones asked to be kept.** Retention skips them, and so does Delete All Chats
  — which says so in its confirmation — the way a clipboard clear keeps its pins.
- **Retention is enforced only while AI is on.** `Keep conversations` prunes on the enable transition
  and whenever the setting changes, through `AIChatCoordinator.applyRetention` — never on a schedule
  and never while `aiEnabled` is false, because age passes while the feature is off and "off means
  fully off" promises the file is untouched. A Mac left off for four months keeps its chats.
  `ChatHistoryStore.prune(before:)` is one `DELETE`, sparing pinned chats, that cascades to messages, images and searches,
  and it `VACUUM`s only when something actually went: pictures live inline as BLOBs, so this is the
  one store where a delete alone frees pages without ever shrinking the file.
- **Everything but the newest message is bounded.** `ChatSession.boundedContext` sends that message
  whole — truncating what someone just typed is worse than the provider's own error — keeps images
  and documents only on that turn and only up to `AIAttachmentBudget`, inlining an attached text
  file into that turn alone, and walks older text newest-first into a
  budget the *route* names: ~100 KB for a cloud endpoint, `AppleIntelligence.contextBudget` for the
  on-device model. Every transport funnels through `requestMessages(textBudget:)`, so no route can
  resend every image each turn or let history grow the payload as a chat goes on. The composer refuses a picture
  past the budget and says so, rather than letting send time drop it silently.

## Connections and routing

`AIModelSelection` has seven cases: `.appleIntelligence`, `.codex`, `.claude`, `.grok`, `.openCode`,
`.cursor` and `.api`.
The first needs no connection at all. The next five name a model from an installed command and carry
no credential. `.api` points at one `AIConnection`; `AIProviderKind` exposes four named presets plus a
custom OpenAI-compatible route. Decoding still accepts the old `.chatGPT` spelling and writes it back
as `.codex`, so an existing selection survives the rename.

| Setting | Transport | Default base URL |
| --- | --- | --- |
| Apple Intelligence | Foundation Models, on device | none |
| Codex | installed `codex app-server` | user's Codex account |
| Claude | installed `claude -p` | user's Claude login |
| Grok | installed `grok --prompt-file` | user's Grok login |
| OpenCode | installed `opencode run` | providers already configured in OpenCode |
| Cursor | installed `agent -p --mode ask` | user's Cursor login |
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
manually. Tinycast does not ship or guess an API catalog that can become stale. Codex gets its models
and reasoning efforts from `model/list`; OpenCode gets identifiers and model-specific variants from
`opencode models --pure --verbose`. Claude answers an `initialize` control request — written to a
stream-json `-p` run that then gets no prompt, so no model is called — with its own `/model` list;
`InstalledAIModel.claudeCatalog` keeps one row per resolved model (dropping `default`, which restates
another), names each by the version its alias points at today ("Claude Opus 5.5"), and takes each
one's `supportedEffortLevels`. A model the CLI starts offering appears without a Tinycast release. Cursor lists models
from `agent --list-models` after `agent status --format json` confirms a login.

Turning thinking off is a reasoning effort, not a second control: `reasoningOptions(for:)` answers with
the connection's catalogued efforts, or — for a connection with no catalog to publish one — `Default`
and `None`. `takesThinkingField` decides who gets that pair: an OpenAI-shaped preset whose base URL is
not that preset's own, because a preset pointed away from its own API is a gateway, and a gateway is
the only destination Tinycast can offer the switch to honestly. Picking `None` sends
`"thinking": {"type": "disabled"}`, which is how DeepSeek and the endpoints that copied its contract
answer without reasoning first. A vendor API is never offered the pair and so is never sent a field it
does not define — which matters precisely because the preset alone says nothing about the destination
when every base URL is editable. Only `None` is ever written, so every other body is the one it always
was, and the choice rides in `AIModelSelection.effort` like every other route's.

## Provider interface

`AIProvider.stream(_:)` accepts provider-neutral messages, optional instructions, a maximum output
token count and the tools the turn may call. It returns an `AsyncThrowingStream` of text, thinking
state, tool activity, usage and completion. OpenAI-
compatible reasoning fields are surfaced as `.thinking`, never mixed into answer text. Anthropic
system messages are lifted into its top-level `system` field; the other HTTP routes keep system
messages in the OpenAI message array.

`AIProviderFactory` resolves the selection, validates an API endpoint, reads an API key at the last
possible moment and returns `AppleIntelligenceProvider`, `HTTPAIProvider`, `CodexInstalledProvider`
or `InstalledCLIProvider`. A consumer should hold neither settings nor credentials itself. The
`selection` and `guardrails` overload lets Quick Actions pick its own route and ask for permissive
content transformations without a second factory.

`AIModelOption.groupedCatalog` is the Settings picker catalog for both AI and Quick Actions. Provider
sections, ordering and model labels therefore cannot drift between the panes. Each route stores its
own complete `AIModelSelection`, including the selected reasoning effort for installed models and
OpenRouter models that offer one.

`AppleIntelligenceProvider` is the only route whose model is a local process. It builds a `Transcript`
from the turns ahead of the newest user message and streams the rest as the prompt, so a conversation
resumes rather than being replayed as one blob. Foundation Models reports the whole answer so far in
every snapshot while every other transport speaks in deltas; `AppleIntelligenceDelta` is the one place
that difference lives. Guardrails are a construction parameter rather than a constant: chat writes
fresh prose, where the default filter belongs, and a later text-rewrite feature transforms text the
reader already wrote, which is what `permissiveContentTransformations` exists for — so that feature
needs no second provider. `GenerationError` never reaches the transcript as-is; its `Context` carries
a debug description written for a log, so each case maps to a plain sentence instead.

## Chat surfaces

### Quick AI

The built-in `Quick AI` launcher command enters `AIScreen`, and carries a bindable global shortcut
(`HotKeyAction.command(.quickAI)`) that does the same thing from any app; Tab from the launcher is the
third way in. Settings → AI holds the recorder and a checkbox for the command's place in launcher
search, beside `AI Chat`'s; either shortcut keeps working while its command is hidden, and does
nothing at all while the feature is off. The palette search field becomes the single-line composer.
The footer pill and Return are one action, `activate`: Send, or Stop while a response streams — an
empty composer sends nothing, so the pill never needs a disabled state. The header's trailing model
switcher uses the same in-window menu control as Clipboard's type filter and changes the chat route
for the next message. For installed routes and OpenRouter models whose catalog reports the
capability, it also shows the supported reasoning efforts and changes the chat effort for the next
message. Other API routes keep their provider default because their model catalogs expose no
portable effort contract. Neither change interrupts a response already streaming; stopping one is
the pill's job, so the header never has to fit a third control beside the switcher.

The second footer control is the palette's normal Actions (`⌘K`) menu. It owns Continue in AI Chat
(`⌘J`; Open AI Chat while the chat is empty), New Chat (`⌘N`), Chat History (`⌘Y`) and AI Settings
(`⌥⌘,`), plus Stop Response (`⌘.`), Regenerate Response (`⌘R`), Copy Last Response (`⇧⌘C`) and
Remove Attachments when those apply. The chords are Raycast's where it has one, and `AIScreen.perform`
maps each `PaletteShortcut` to its action. AI Settings takes ⌥⌘, because ⌘, stays the app's own
Settings on every screen. Continuing closes the palette and carries the half-typed line into the
window's composer with the conversation. Chat History is the palette's own browser over the same
saved chats the window's sidebar lists: ↵ opens one in Quick AI, or in the window when the window
already holds it, and Continue in AI Chat (`⌘J`) takes it to the window either way.

### AI Chat

The `AI Chat` command (`command:ai-chat-window`, `HotKeyAction.command(.aiChat)`) opens a titled
`AppWindowController` window owned by `AIChatCoordinator`, autosaved as `AIChatWindow`. It is built the
way Settings is — an `AIChatSplitViewController` with a native sidebar item, here collapsible, and a
unified toolbar whose title is the open chat's — so it takes the system's own sidebar, toolbar and
menus rather than the palette's scrim. `AIChatWindowChrome` owns the toolbar — the sidebar toggle
and New Chat as two round buttons at the sidebar's trailing edge, then Find in Chat and Actions
alone at the window's — the title, and one key monitor for ⌘V, ⌘F, ⌘G / ⇧⌘G, ⌘K and the Actions
menu's own chords, and dies with the window.

- **Find in Chat** (⌘F): the system's `NSSearchToolbarItem`, as is. `ChatFindState` is one per
  window and steps match by match, not message by message:
  `ChatFindIndex` walks each message exactly as the transcript draws it — reasoning folds, every
  paragraph, list item, code block and table cell, in order — and lists every occurrence as
  (message, drawn text, index within it). A reply's hidden choices fence never matches. A drawn
  text is named by its position path (segment, block, item or cell), not its content, so two
  identical table cells are two matches. `ChatTextHighlight` rides the environment into every text
  a message draws, which marks all its matches in the Mac's find yellow and the current one solid;
  a clear marker over the current match takes the scroll anchor, so the transcript centres on the
  word itself.
- **A reply's text is one selectable text view.** SwiftUI's `Text` selects within itself only, so
  a reply drawn paragraph by paragraph could be dragged across one paragraph at most.
  `ChatMarkdownText` draws each text segment into one read-only `NSTextView`, and
  `ChatMarkdownRenderer` builds its single attributed string: lists with hanging indents, quotes,
  code as `NSTextBlock`s, tables as an `NSTextTable`, with find's marks and the citation numbers
  in it. Its leaf paths are `ChatFindIndex.leaves`'s, which `chat-markdown-test` pins. A code
  block's language and Copy sit in a strip its block leaves above the code. Thinking folds, search
  and tool rows stay separate views, so a drag spans one segment's text. A fold holding a match
  opens. A glass counter at the transcript's top edge says "3 of 17" with the same steps as
  Return / ⇧↩ in the field and ⌘G / ⇧⌘G anywhere. The sidebar's own filter is still there, by click.
- **Actions** (⌘K): Quick AI's ⌘K menu for a window, on the same chords — Stop Response (`⌘.`), New
  Chat (`⌘N`), Regenerate (`⌘R`), Copy Last Response (`⇧⌘C`), Remove Attachments, Find in Chat
  (`⌘F`) and AI Settings (`⌥⌘,`) — plus what only a saved chat has: Copy Chat, Pin and Delete.
  `AIChatActionsMenu` builds it per open from the chat's state, as an `NSMenu` hung under the
  toolbar button whether the click or ⌘K opened it.

- **Sidebar** (`AIChatSidebarView`): a filter field over a `List` of every saved chat, Pinned
  first and then bucketed by day like Clipboard. The open chat is the selected row. A new chat has
  none until its first message saves it, so starting one or leaving an empty one never adds or
  drops a row under the pointer. A row shows a spinner while its reply streams, else a pin when
  pinned. Its content fills the whole cell, so hover — a fainter fill in the selection's own
  shape — never blinks off crossing between rows.
  The context menu pins, renames in place, copies or exports the chat as Markdown
  (`ChatSession.markdownTranscript`), and deletes one or all through `DialogController`; ⌫ deletes
  the selected chat the same way.
- **Transcript**: `ChatTranscriptView` with `surface: .window`, which drops the palette's edge
  dissolve and thin scrollbar (both are measured against the palette's bars) and centres the column
  at `aiChatReadingWidth`. The last finished reply offers Regenerate beside Copy: `AIChatState`
  drops only a trailing reply and asks again with the question and its attachments, of whichever
  model is selected now.
- **Composer** (`AIChatDetailView`): one pane of untinted Liquid Glass, stacked under the transcript
  rather than floated over it, with glass capsules for its menus, the glass on a background layer.
  The title bar keeps the system's own band, as a native document window's does.
  Transcript text runs `spacing.chatLine` apart, both surfaces. `ChatComposerTextView` is an `NSTextView`, not a `TextEditor`: its delegate sees
  `insertNewline:` only outside input-method composition, so Return sends and ⇧↩ or ⌥↩ breaks the
  line without Return ever stealing an IME's confirm. It grows with its text to
  `aiChatComposerMaxHeight`, then scrolls. Under it: the paperclip (an `NSOpenPanel`), the model
  menu, the reasoning menu (always shown, disabled for a model with no efforts, so the row never
  changes shape), a web-search toggle when the route offers search, a context gauge, and Send/Stop.
  One paperclip takes every kind; its help names what this chat's model can read. The gauge is the
  last reply's `contextTokens` against the model's window when the route reported one, and
  `ChatSession.historyBytes` against Tinycast's history budget otherwise — orange from 80%, red at
  100%. Hovering it raises Tinycast's own card (never a popover), drawn inside the transcript's
  frame at its bottom edge — just above the composer and inside the window whatever its size — and
  solid under its glass so the transcript cannot show through. `ChatContextReport`
  lays it out: tokens in context of the window, input with its cached share, output with its
  thinking share and cost; then what the next message sends — model, history of budget, messages
  sent of total, staged files, and whether the system prompt, web search and tools ride along. The model and reasoning menus are this chat's, as Quick AI's header is Quick AI's. Files arrive by ⌘V, a drop anywhere on the pane, or the paperclip, and all three take
  the refusals a paste does. The unsent text lives on `AIChatState.draft`, so it survives closing
  the window.

`AIChatState` turns provider-neutral stream events into one live assistant message. Thinking state is
shown without entering the transcript, partial text is preserved on failure, cancellation invalidates
the active generation, and only completed assistant messages become context for the next request.
Assistant replies render Markdown; user messages remain literal. A reply keeps streaming while the
palette is hidden, the window is closed or showing another chat — the state is `AppCore`'s, not the
view's — and is saved when it finishes.

Tool activity persists in `message_tools` beside `message_searches`, and `ChatMessage.segments`
interleaves the two by text offset so a reply renders what it did in the order it did it. Offsets tie
whenever no text arrived between two of them, so each search and call also takes a `sequence` — its
place among the reply's searches and calls — as it is created, and that breaks the tie. Both tables
store it as their `position`, so no column was added; a chat saved earlier holds each table's own
index there, so its ties go by that index and then to the search. Consecutive tool calls render as
one run: the latest running call while live, then an expandable count with any failures once done.
Text and searches separate runs; a single call keeps its own row. A call loaded still marked running
belonged to a process that is gone, so it reads back as failed — the same repair a message left
streaming gets.

`ChatHistoryStore` writes `ai-chats.sqlite3` below the bundle-specific Application Support directory.
It uses the system SQLite already linked by Tinycast, stores no provider credentials, and repairs a
reply left streaming by a prior process into an interrupted failure when loaded.

## Palette integration

Two palette modes carry Quick AI, and neither changes the shell's rules:

| Mode | Screen | Body |
| --- | --- | --- |
| `.ai` | `AIScreen` | `ChatTranscriptView` (`surface: .palette`) |
| `.aiHistory` | `ChatHistoryScreen` | `ChatHistoryList` + preview, bucketed by day like Clipboard |

Chat History backs out to Quick AI; both are sub-screens, so the header shows the back chevron.
Quick AI keeps the `command:ai-chat` id it shipped with while it was the only chat, so a hotkey,
alias or fallback order recorded then still reaches it with nothing migrated; the window's command
is the new id. The search field is the composer: Return submits, or stops a streaming response, and the footer pill
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

Seven more `@MainActor @Observable` types join the shared state: `AISettingsStore`,
`ChatGPTSubscriptionManager`, `InstalledAIManager`, `ChatHistoryStore`, `AIChatSurfacesState` (which
owns every live `AIChatState`), `MCPSettingsStore` and `MCPServerManager`. `AIChatCoordinator` — the
window, and every chat action either surface sends — is the nineteenth feature coordinator,
`MCPCoordinator` the twentieth and `QuickAICoordinator` the twenty-first.

### Manual sweep

- The selected model appears at the right of the composer and truncates without crowding typed text.
- An `@server` chip — the tools glyph alone, since the handle is still in the text — or a staged
  pill follows the typed text with a clear gap, and a long draft stops it right before the model
  name, the same gap with a reasoning menu and without.
- Clicking it opens the same anchored menu shape as Clipboard's type filter; arrows, Return and Escape
  operate the menu without changing the draft.
- Repeatedly clicking either the model switcher or the type filter opens and closes every time, even
  when the next click lands immediately after dismissal or a few points off the first one.
- Selecting a model updates the button immediately and the next message reaches that route.
- Switching while a response streams does not stop or reroute that response; the new model applies to
  the following message.
- With no available model, the menu offers Configure AI and opens the AI Settings pane.
- With Apple Intelligence available and nothing else configured, opening chat or the AI pane leaves
  the selection reading **Apple Intelligence** without asking for anything.
- With it switched off in System Settings, the pane says so and chat says so; neither moves the
  reader onto a configured API connection.
- Install and sign in to each supported command outside Tinycast, choose one of its discovered models,
  and confirm Chat and each model-backed Quick Action use it without showing a credential field.
- Sign out of an installed command, press Check Again, and confirm its models leave both pickers while
  the stored selection is repaired according to the normal routing rule.
- On Codex and on the Claude command, with an MCP server enabled, a question answered with a tool
  shows the same rows the API routes show and the reply continues after them; with MCP off, both
  routes stream exactly as they did before.
- With `Quick AI opens to: Recent Conversation` and a five-minute window, Escape out and summon again inside
  five minutes resumes the transcript; past it, the composer is empty. Quitting and relaunching still
  reopens the last conversation. `A New Conversation` is always empty.
- Setting `Keep conversations` to 7 days drops older unpinned chats from the window's sidebar and
  shrinks `ai-chats.sqlite3`; a pinned one stays. Switching AI off, waiting past a boundary and switching back on prunes nothing
  that was saved before it went off.
- Ask in Quick AI, press ⌘J while it streams: the window opens on that chat, still streaming, with
  the unsent line in its composer, and Quick AI is empty on the next summon.
- In the window, send, then press ⌘N before the reply ends: the old chat keeps its sidebar spinner,
  finishes, and reopens complete. Rename one, send another turn in it, and the name holds.
- Return sends, ⇧↩ breaks the line, and a Japanese IME's Return confirms its text without sending.
- Drop a PDF on the pane with a text-only model selected: the HUD refuses it, as a paste would.
- Collapse the sidebar with the toolbar button; ⌘N and ⌘Q (Close Window) still work, and ⌘Q with
  Settings in front closes Settings instead.
- Harnesses: `ai-provider-test` (endpoints, request bodies, stream decoding, persistence repair,
  Codex framing, on-device routing, the two MCP launch encodings and the two consent channels),
  `ai-chat-test` (`ChatSession`, `MarkdownBlock`, `ChatHistoryStore` with renames and pins,
  `AIToolLoopProvider`, regenerate, and `AIChatSurfacesState`'s one-live-place rule),
  `codex-turn-test` (the Stop path, driven against a stub app-server stalled where Stop races the
  turn ID, plus the MCP launch boundary, one launch for concurrent starts, the elicitation, the
  rows and the call cap),
  `installed-ai-test` (Claude/Grok/OpenCode/Cursor flags, prompt
  framing, streaming and cleanup, and Claude's private MCP configuration, control channel, round
  cap and managed-policy branch) and `apple-intelligence-test` (status copy, snapshot deltas,
  transcript assembly, error mapping, plus one real generation when this Mac can run one), all in
  `run-tests.sh`.

## Installed commands

`ExecutableLocator` finds `codex`, `claude`, `grok`, `opencode` and `agent` by asking the account's
login shell, so a stale copy in another prefix never shadows the one Terminal runs. Only when the shell
names no absolute executable does it fall back to the app's PATH, the normal Homebrew and local-bin
locations and every nvm Node version, newest first — a fallback that can pick a different copy. The
commands are never installed by Tinycast; Settings links to their own install docs and offers a sign-in
command to copy. `InstalledAIManager` probes Claude, Grok, OpenCode and Cursor off-main, in parallel.
Claude's auth status gates an `initialize` control request, and `InstalledAIModel.claudeCatalog` builds
its model list from the answer; a successful Grok or OpenCode model list is both its auth check and
catalog; Cursor's `status --format json` gates `--list-models`.

`ChatGPTSubscriptionManager` retains its historical type name but now owns only the installed Codex
app-server lifecycle and discovered account metadata. Production never sets `CODEX_HOME`, so the
server uses the same login and credential store as the user's normal Codex command. Tinycast supplies
only a private working directory. The server stops after ten idle minutes, when AI is switched off or
when the app terminates, and restarts on demand. Account state, model availability and rate-limit
windows come from the supported app-server protocol.

MCP is the one thing about that server that is fixed at `exec`: its overrides and its environment
both are, so `CodexAppServerClient` remembers the list it was launched with and relaunches when the
next turn wants a different one — a server added or removed, or an OAuth token refreshed. A check
is not a turn and keeps whatever is already running. The account survives the relaunch because it
was never the process's to begin with. See [MCP](mcp.md) for what goes on the launch line.

`CodexTurnRunner` is the generation half behind `CodexInstalledProvider`.

It creates an ephemeral thread for each request, injects prior user/assistant messages, and
streams agent-message deltas, plus `item/started` for the reasoning and web-search items that feed the
bubble's status line. System messages become developer instructions alongside Tinycast's fixed
boundary, which forbids every tool except the MCP tools an armed turn supplies. Cancellation interrupts the active turn, including one the server has started but
not yet named: Stop arms that thread, and whichever of `turn/started` or the `turn/start` response
names the turn first spends a single `turn/interrupt` on it.

Web search is thread-scoped config (`thread/start.config.web_search`, `live` or `disabled`) and
reasoning effort belongs to `turn/start`; neither is written to the user's Codex configuration. The
developer instructions say whether the model may reach the web so the two cannot disagree. Images go
out as `image` input parts with data URLs, and as `input_image` when prior turns are injected.

`InstalledCLITurnRunner` handles Claude, Grok, OpenCode and Cursor behind the same provider protocol. It
frames Tinycast's instructions and bounded conversation history as stdin (or a private `--prompt-file` for
Grok, whose CLI requires a path), consumes newline-delimited JSON, and never puts prompt text on the
process command line. Claude uses stream JSON, `--effort` and no session persistence, and takes every
turn as one framed `stream-json` user line. With servers armed it keeps stdin open for the consent
channel and closes it on the CLI's own result frame; writes are chained rather than concurrent,
because two racing the same pipe would interleave a line.
Grok uses `streaming-messages-json` and `--effort`, with `--deny *` so tools cannot run even when the
user's Grok config is always-approve; it captures the session id, then calls `grok sessions delete`.
OpenCode runs pure with an inline deny-all configuration and passes the selected
model variant through `--variant`; it captures the returned session identifier, then calls
`opencode session delete` after the process exits. Cursor runs ask mode with `--trust`,
`stream-json` and `--stream-partial-output`, never `--force` / `--yolo` / `--approve-mcps`, then removes
the local chat under `~/.cursor/chats/<workspace>/<session_id>` because the CLI has no delete-chat.
A turn finishes on its own completion frame; both cleanups run detached after the child exits, so
housekeeping never holds the composer shut.
Cancellation terminates the child process; only one installed-CLI turn can own a runner at a time.

## Web search and attachments

`AIRequest.webSearch`, `AIMessage.images` and `AIMessage.documents` are provider-neutral; each
route maps them itself:

A text-ish file is deliberately absent from this table: it is inlined as text before any transport
sees the turn, so every route — the on-device model and all installed CLI transports included — takes one with no
transport code at all.

| Route | Web search | Images | PDFs | MCP tools |
| --- | --- | --- | --- | --- |
| Apple Intelligence | never — it reaches nothing | never — the model is text-only | never | never |
| Codex | thread-scoped `web_search` config | `image` input part | never — the app-server takes no document part | Tinycast's servers, added as launch overrides; the reader's own are disabled by name |
| Claude command | never | base64 `image` block in its stream-json user message | never | Tinycast's servers, through `--strict-mcp-config` and a private config file — an empty one when there are none, and neither flag under a managed MCP policy |
| Grok command | never | never | never | the global config still loads — `--deny *` refuses the call |
| OpenCode command | never | never | never | the global config still loads — `permission: deny` refuses the call |
| Cursor command | never | never | never | the global config still loads — ask mode and withheld approval refuse the call |
| OpenRouter | `plugins: [{id: "web"}]` — OpenRouter's own layer, any model | `image_url` part, only for models whose catalog lists the `image` modality | never yet — its catalog publishes a `file` modality Tinycast does not read | `tools` + `role: "tool"` turns |
| OpenAI | not offered | `image_url` part, assumed supported | `file` part with `filename` and a `file_data` data URL | `tools` + `role: "tool"` turns |
| Gemini / compatible | not offered | `image_url` part, assumed supported | never — a gateway that has not implemented the part bills the upload before rejecting it | `tools` + `role: "tool"` turns |
| Anthropic | not offered | base64 `image` block | base64 `document` block, ahead of the text block | `tools` + `tool_use` / `tool_result` blocks |

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
Nothing *guesses* at a capability: images ride on what the model's own catalog said, and a vendor
API that does not take one simply returns its error. What is gated is only what a route provably
cannot carry — a PDF to a text transport — refused at the composer with a HUD naming the reason.
`AIModelCapabilities.documents` is true only for the two HTTP shapes whose bodies Tinycast writes;
a gateway that has not implemented the `file` part would bill the upload before rejecting it, which
is why documents are *not* assumed the way images are. An attachment is never dropped on the way
out: answering a question about a document the model never received is the one outcome this must
not produce.

In Quick AI attachments arrive by ⌘V; the window also takes a drop and the paperclip. They come in
three kinds: an **image**, a **PDF** sent as a native document block,
and a **text-ish file** whose contents are inlined as fenced, named text.
`PaletteWindowController`'s command-shortcut hook gives chat the chord first; a pasteboard holding
file URLs or a bare image (a screenshot) stages them, while anything else carrying text falls
through to the field editor as a normal paste. **Only `isFileURL` URLs are read** — without that
filter a copied `https://…/a.png` reaches `Data(contentsOf:)`, turning a keystroke into a network
request. Every file is **sized before it is read**, so a huge CSV can never be slurped into memory.

**A text file is inlined by `ChatSession.boundedContext`, never into `ChatMessage.text`.** That
seam is load-bearing: `ChatSession.title` summarises the first user message, so folding a CSV into
the stored text would make the dump the conversation's title in the AI Chat sidebar, its preview, and what
the user bubble renders back. Inlining after the transcript and before the transport also means
only the newest turn carries it, so a chat's payload cannot grow turn on turn. The block names the
file and fences it with a run longer than any inside it, so a Markdown file holding its own fence
cannot escape; a staged name is stripped of newlines and capped, so a file called
`a\nAttached file: passwd` cannot forge a second header. Undecodable bytes are refused rather than
guessed at, and a file past `AIAttachmentBudget.maxInlinedTextBytes` is refused rather than
truncated — a silently truncated CSV is a lie the model then answers confidently.

`AIAttachmentPolicy` is the one place deciding what may be attached and as what. It is pure and
Foundation-only, so `ai-chat-test` pins it. It uses **extension allowlists rather than
`UTType.conforms(to:)`**: a machine's installed apps declare types, so a conformance answer differs
between two Macs and would make a harness machine-dependent — the exact environment coupling
`Model/` exists to keep out. Adding a type is a one-line change; a type answer that differs per Mac
is a bug you cannot reproduce.
Images are re-encoded to PNG and bounded to 1568px on the long edge, off-main on a detached task so
a display-sized screenshot does not decode on the keystroke; one past `AIAttachmentBudget` is refused
with a HUD instead of being staged. Because that decode outlives the keystroke, it shares the staged
images' lifetime exactly: whatever consumes or clears them — a send, a new chat, Remove Attachments,
or leaving the conversation for another in the window — disowns one still in flight and says so,
rather than letting it surface on a later message. The counter that decides this sits on
`AIChatState` beside the staged images, so a route that drops them cannot forget to move it.
**Staged attachments share one pill beside the typed text**: the newest one's kind as a glyph — a
photo, a PDF, a text file — and `+N` for the rest, because the strip's width is taken out of the
search field and a named pill per file left too little room to read what you are typing. The names
are a hover away, one per line, and clicking the pill opens a header menu listing every file, an
image by its own thumbnail, with its ✕, so a mispaste is taken back without clearing the rest — ⌘K → Remove Attachments
and bare backspace stay as the bulk and last-one routes. A row runs by its index, so the open menu
is re-laid whenever the staged list changes and closes once it empties; left stale, a file decoded
under it would shift the rows, and clicking Remove All would take back only that file. The menu's
thumbnail is the ~1 KB PNG downsampled on the same detached task that encodes the attachment and
carried on the staged attachment itself, decoded once per row, so there is no cache whose lifetime
could drift from the staging counter's. The strip states its own width — `AttachmentsPill.width(for:)`, the `@`
chip's, and every gap it lays out, the one between the two chips included — which
`RootPaletteView.searchFieldWidth(for:)` subtracts from the search field, so they must move together
or the caret drifts. Pills ride the same `headerAccessory` the launcher's argument fields use, so the field shrinks to
its text and the chip follows it rather than the composer growing. Nothing is reserved for the model
menu: the row itself squeezes a long draft, so the strip stops right before that menu however wide
its title is. Bare backspace on an empty composer removes the last
chip before it backs out of chat; ⌘K → Remove Attachments clears them all. Sent images persist in `message_images` and sent PDFs in `message_documents` beside their message;
the bubble renders images as thumbnails and documents as named chips.
A text file is already in the message's text and needs no table. The schema is
`CREATE TABLE IF NOT EXISTS` re-applied on every open, so the table needed no migration, and its
`ON DELETE CASCADE` leaves `prune` unchanged.

The switcher's glyph comes from the selection. Codex uses OpenAI's mark; Claude and Grok use their own
marks; OpenCode resolves a brand from the model id or falls back to a sparkle; Cursor uses an SF Symbol;
an API model resolves through its connection. It never depends on `modelOptions`, which for
Codex is empty until the app-server has answered `model/list`; opening the chat on a Codex model warms that list so the title is the
display name from the first frame. Tab hands Quick AI on to the clipboard, and Escape on an empty
composer takes its own back step — to whatever opened it, or out of the palette when its hotkey
did; either way the unsent draft is dropped rather than carried into a field that would search it.
History is pushed over Quick AI and pops back to it, and Tab carries its query to the launcher
because there the field really is a search. Neither exit touches the conversation: it lives on
`AIChatState`, so Tab away and back resumes the same transcript.

The model switcher is `fixedSize` with its title shortened in `AIChatCoordinator` (26 characters,
middle ellipsis) rather than truncated by layout: a flexible label claimed the row up to its max
width and clipped the search field well short of the button.

## Settings and backup boundary

Settings → AI is a normal grouped `Form` inside Tinycast's existing Settings window. Its top AI
section owns the feature switch and the **Providers → Manage…** action, and **Default model** below
it picks the app-wide route and its reasoning effort. Provider management opens as a sheet, where
**Installed AI** reports Codex, Claude, Grok, OpenCode and Cursor separately as checking, ready, sign-in required,
missing or failed. It never contains a credential field: installation and sign-in happen in each
command's own flow. **API Connections** remains the explicit Keychain-backed path in that sheet. A
pick in Quick AI's header or the AI Chat composer sets that chat's model and moves this default with
it, while Quick Actions keeps its own model selection.

The signed-in Codex address is the one thing on the pane that names a person, and a Settings pane
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
deliberately cannot reach: every installed CLI route prepends its own instruction never to run
commands or touch files, and never to invoke a tool beyond the MCP tools an armed Codex or Claude
turn supplies. That is a sandbox boundary on a local CLI, not Tinycast describing itself, and a user
switch must not be able to lift it.

`mcpEnabled` and `mcpServers` are excluded for the reasons in [mcp.md](mcp.md).
`aiConnections`, `aiDefaultModel`, `aiSystemPrompt` and `aiSystemPromptEnabled` are deliberately
excluded from settings backups. The first is meaningless without machine-local Keychain items; the
second names an external destination and must not silently redirect AI traffic after an import; the
last two are standing instructions and the switch that sends them, both of which change every
answer and must not arrive on another Mac unread. `aiRetention`, `aiOpensTo` and `aiNewChatAfter`
join them: all three are decisions about conversations that never leave the Mac that had them, and
an import must not arrive carrying an instruction to delete them. `aiToolRounds` stays behind too: it
limits what a tool-driven reply may spend, and an import must not raise that unasked.
