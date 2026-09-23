# MCP servers

Tinycast connects [Model Context Protocol](https://modelcontextprotocol.io) servers and offers their
tools to the model during a chat. A server is either a remote HTTP endpoint or a command Tinycast
runs on this Mac; either way it advertises tools, Tinycast namespaces them by the server's handle,
and the model calls what it wants. On an API route Tinycast is the MCP client; on the Codex and
Claude routes the vendor CLI is, and Tinycast supplies the servers and answers for them.
`Features/MCP/` owns servers and knows nothing about chat; [AI](ai.md) owns tool calling and knows
nothing about MCP. `AIChatCoordinator.send` is the one place the two meet.

## Invariants

- **MCP is off out of the box, and off means fully off.** `AppSettings.mcpEnabled` is the flag and
  `MCPCoordinator.applyEnabled()` is the only place that projects it: no connection opened, no local
  process resident, no tool named to any model. `aiEnabled` off does the same, because chat is the
  only consumer. That reaches the Codex helper too, which keeps what it was launched with until it
  exits: when MCP goes off, or a server it runs is removed, set to Never Allow or signed out of,
  `ChatGPTSubscriptionManager.dropWithdrawnServers` stops it between turns rather than leave the
  server process and any lent token in it for its ten idle minutes; a change made mid-turn leaves it
  to the next turn's relaunch or that idle stop. Both flags and `mcpServers`
  are excluded from settings backups — a server list is a source of executable code and a
  destination for chat context, and the flag doubles as consent to run it, so an import can never
  arrive having connected one.
- **Credentials live only in the login Keychain.** `MCPServer` persists the endpoint, authentication
  mode, the header *name*, the command, its arguments and its environment variable *names* in
  `UserDefaults`; it never contains a secret. The HTTP header value, environment values, OAuth client
  registration and tokens are one JSON item per server under `KeychainSecretStore.mcpSecrets`, and
  never enter logs, errors or backups.
- **Remote endpoints require HTTPS**, through the same `AIEndpointPolicy.validate` the AI providers
  use — plain HTTP only for `localhost`, `127.0.0.1` and `::1`, and no other scheme at all. There is
  one place that decides this and MCP does not get a second one.
- **OAuth tokens belong to one configured MCP endpoint.** Editing its URL cannot lend its token to
  the new destination. Discovery validates every endpoint; private ephemeral sessions have no URL,
  cookie or credential cache. OAuth endpoints — discovery, registration, token — refuse every
  redirect. An MCP endpoint may redirect within its own origin, the `/mcp` to `/mcp/` that Python
  servers answer with, and the credentials `URLSession` would strip are restored because the origin
  is unchanged; a redirect to any other origin is refused, so no credential ever reaches a second
  host. Refresh tokens go only to the token endpoint retained with their client registration.
- **OAuth sign-in is explicit.** Settings opens the browser after discovery and PKCE S256 checks.
  The callback binds only `127.0.0.1:4962`, validates state and any issuer parameter, accepts one
  response and closes. Cancellation, disabling AI/MCP and the five-minute timeout also close it.
  An occupied port fails instead of choosing another port. No custom URL scheme is involved.
- **A tool call never enters the conversation.** The whole call-and-result round trip lives inside
  one turn, in `AIToolLoopProvider`, and what `ChatSession` keeps is a `ChatToolUse` render record —
  exactly what `ChatSearch` already is. That is deliberate: a stored `tool_call` separated from its
  result, or a result whose call fell outside `boundedContext`, is a request both providers reject,
  so the shape that could produce one is never written down. It also means a later turn sees the
  model's own answer rather than the raw tool output it was billed for once already.
- **A dialog can grant a server, and only Settings can withhold one.** `MCPTrust` is `.ask` by
  default; the first call of a conversation goes through Tinycast's own three-way dialog. **Always
  Allow** persists `.always`, **Allow This Chat** grants for that `ChatSession.id` alone, and **Don't
  Allow** — which is what Escape does — refuses that one call and lets the next ask again. Escape is
  never allowed to persist a decision, and `.never` is set on the server's row in Settings.
  `MCPTrustPolicy` is the whole rule and it is pure.
- **A refused or failed call is content, never a thrown error.** It comes back as an `AIToolResult`
  the model can read and work around, so a declined tool ends in an honest sentence rather than a
  failed turn.
- **Every turn is bounded three ways.** The round cap is `AISettingsStore.toolRounds` — Settings →
  AI → Chat → Tool call rounds, an `AIToolRounds` of 10, 25, 50, 100 or Unlimited, 25 unless changed
  — after which the turn fails saying so: a model that only calls has stopped answering, but a long
  chain of calls is also honest work, which is why it is a choice and not a constant. Unlimited
  hands the loop no round cap, so the model or Stop ends the turn, even while the palette is hidden,
  unless what the turn has added — the model's text, call arguments and results — reaches
  `maxTurnHistoryBytes`, since every round resends all of it. Each result is cut to
  `maxResultBytes`, and a turn's results together to `maxTurnResultBytes`, because tool output is
  appended inside the turn and so never passes through `ChatSession.boundedContext`. The same
  number bounds a CLI route, in the terms its own client counts in: Claude takes it as
  `--max-turns`, which bounds model requests exactly as the loop's rounds do, and Codex — which
  names no round at all — is interrupted once a turn has spent that many **calls**, which is
  stricter, never looser. Neither result size is Tinycast's to cut there: the output goes back to
  the model inside the CLI, and what the transcript keeps is the row. Unlimited reaches a CLI route
  as an `AIToolServerSession.rounds` of `nil`: Claude is given no `--max-turns`, since it has no
  cap without one, and Codex counts nothing, so there too only the model or Stop ends the turn. A
  Claude turn with no server to run is a different case and keeps `--max-turns 1` whatever the
  setting.
- **A server's handle is derived, never typed.** `MCPSlug` makes it from the name and uniques it, so
  `@slug` can never name two servers or nothing at all. An unknown handle is not an address: the text
  is sent exactly as it was typed.
- **Servers start with chat and stop after ten idle minutes**, and at `prepareForTermination()`.
  A stdio server is a resident process of someone else's making, and the 100 MB budget is the reason
  this is not "start at launch".
- **Who runs the loop is the route's own answer, and it is the only thing that differs.**
  `AIModelCapabilities.tools` is true for `.api`, for Codex and for the Claude command, and false
  for Apple Intelligence, Grok, OpenCode and Cursor — the three CLIs whose configurations merge
  with no opt-out, which is why none of them may be handed a server. On an API route Tinycast is
  the MCP client and `AIToolLoopProvider` runs the loop. On the two subscription routes the vendor
  CLI is the MCP client: `AIModelSelection.runsItsOwnTools` says so, and `AIChatCoordinator` hands
  the route an `AIToolServerSession` instead of wrapping it. The same servers — less an OAuth one
  nobody is signed into, which a CLI could not explain — the same `MCPTrust` and the same
  `ChatToolUse` rows either way.
- **A CLI is told what to run, never where to keep it.** Launch arguments, the child's environment
  and files inside Tinycast's own workspace are the whole surface; `~/.codex` and `~/.claude` are
  never written. The secrets Tinycast keeps never reach argv, where `ps` would show them: Codex
  reads them from the app-server's environment through the config keys that name a variable, and
  Claude reads them from a `0600` file written per turn into the private workspace and deleted when
  the turn ends — or, when Tinycast did not live to see it end, by `InstalledAIManager` at the next
  launch. A credential typed into a server's URL is not one of them: it is part of the URL, which
  Codex takes as a launch argument like the rest of its configuration. Neither
  route is ever told to persist a decision — no Codex `persist`, no Claude `updatedPermissions` —
  because only Settings may change a standing one.
- **The user's own CLI servers stay out of a Tinycast thread, and never mix with Tinycast's.**
  Codex's launch disables every one of them by name, read first by a short-lived
  `codex mcp list --json` under the same flags the app-server runs with, because that command
  starts nothing and because a name the configuration does not define cannot be disabled — naming
  one makes the whole config refuse to load. Tinycast's own go by `tinycast-<handle>`: `-c` sets
  single keys, so a Tinycast `github` under the reader's own name would inherit everything of theirs
  it did not set — their `env` table with its literal secrets, `cwd`, a per-tool `approval_mode`
  that skips consent — and a remote one over their stdio one makes Codex refuse the whole config.
  A reader's server already named `tinycast-<handle>` for an armed handle refuses the launch rather
  than merge. The boundary fails closed: a listing that exits non-zero or is not a JSON array of
  named servers refuses the launch, since reading it as empty would start every one of them, and
  so does a name with a dot or `=`, which `-c` splits and so cannot switch off. The Providers row
  and the failed turn both say why. Claude's `--strict-mcp-config` does it in one flag. This is
  what closes the leak the route shipped with: its launch flags never touched `mcp_servers`, so
  every server in `~/.codex/config.toml` used to start inside a Tinycast thread, invisible because
  `CodexTurnRunner` ignored the items.
- **Every Codex tool call asks Tinycast, read-only ones included.** Left alone, the app-server runs
  a tool its server annotates `readOnlyHint: true` without raising an elicitation, even under
  `approvalPolicy: "untrusted"` — and that annotation is the server's own claim. So each server is
  passed with `default_tools_approval_mode="prompt"`, which makes Codex ask for every tool; the
  answer then comes from `MCPTrustPolicy`, exactly as it does on an API route. Reading a server's
  resources does not ask: Codex adds `list_mcp_resources`, `list_mcp_resource_templates` and
  `read_mcp_resource` whenever any server is configured, and none of its settings removes them or
  routes them through approval (codex-rs `spec_plan.rs`, `read_mcp_resource.rs`, 0.156). So on
  Codex **Ask Each Chat** covers a server's tools, not its resources; **Never Allow** still keeps
  the server out, because it is never passed.
- **Tinycast exposes nothing back.** A server request — sampling, elicitation, roots — is declined
  with a JSON-RPC error. The client advertises no capabilities in `initialize`.
- **`Model/` stays Foundation-only.** `mcp-test` compiles the shipped models and pins the framing,
  handles, tool names, output flattening, trust and addressing; `mcp-stdio-test` drives a real
  subprocess. `mcp-oauth-test` pins OAuth parsing, PKCE, endpoint binding, callback lifetime,
  dynamic and supplied client registration, refresh coalescing, redirects and bounded 401 recovery.

## Transports

Both speak JSON-RPC 2.0 through one encoder, `MCPProtocol`; only the framing differs.

| | `MCPHTTPTransport` | `MCPStdioTransport` |
| --- | --- | --- |
| Shape | one POST per message | newline-delimited over the process's stdin/stdout |
| Reply | a JSON body, or an SSE stream read with the AI layer's `SSEParser` | a line, matched by id |
| Session | `Mcp-Session-Id` captured from any response and replayed | the process itself |
| Timeouts | 15 s, 60 s for `tools/call` | the same, per pending request |
| Teardown | the session is dropped | stdin closed, SIGTERM a second later |

`MCPStdioTransport` is `CodexAppServerClient`'s mechanism applied to a second protocol: a pending-id
map with per-request watchdogs, an 8 MB guard on an unterminated line, and a `cleanup` that fails
every waiting continuation. Two details are load-bearing. Termination can beat the last stderr read,
so `didExit` drains the pipe before composing its message — what a server printed on the way out is
the only reason a reader will ever see. And pending calls are failed *before* the owner is told,
because the owner's own `close()` would otherwise overwrite the real reason with "not running".

The command is found by `Platform/ExecutableLocator`, which asks a login shell first and only then
walks PATH, the usual install prefixes and every nvm Node version — a GUI app inherits Finder's PATH,
which has none of `npx`, `uvx` or `node` on it.

## HTTP OAuth

`AppCore` owns `MCPOAuthManager`; Settings and server connections use that same Keychain-backed
session. `MCPOAuth` and `MCPOAuthRequest` hold Foundation-only protocol decisions, with entropy,
hashing and time injected. `MCPOAuthService` performs discovery and exchanges; `MCPOAuthListener`
owns the Network.framework loopback callback.

Sign In probes the MCP endpoint without credentials, reads the Bearer `resource_metadata` challenge,
or tries path-specific then root RFC 9728 discovery. The first advertised authorization server is
resolved through RFC 8414, with the OIDC discovery locations as fallbacks. Its issuer must match,
a trailing slash aside — Google advertises one and publishes none — and it must advertise S256.
A supplied client ID and optional secret take precedence, trimmed of the whitespace a paste brings;
the secret goes as HTTP Basic, or in the form body when the server advertises
`client_secret_post` and not Basic. Otherwise Tinycast uses RFC 7591 dynamic registration with a
native public client. CIMD and device flow are not implemented.

The canonical configured MCP URL is the RFC 8707 `resource` on authorization and token requests.
Protected-resource metadata may describe an ancestor path on the same origin, matching current MCP
SDK behavior; sibling paths and other origins are rejected. Saved tokens remain bound to the exact
configured endpoint. This is deliberately broader than RFC 9728's exact resource-match wording.

Access tokens refresh within 60 seconds of expiry. A token lent to a CLI route refreshes within ten
minutes instead (`MCPOAuthManager.lentToken`): the CLI holds it for its whole turn and cannot ask
for another, while a turn that starts at 61 seconds left can easily outlast them. One with no
refresh token, or whose refresh could not be served, is lent as it is rather than withheld.
Concurrent requests share one refresh, and
rotated refresh tokens replace the old token in the same Keychain item. Closing or saving the editor
leaves a refresh in flight to finish, because a server that rotates refresh tokens may already have
spent the old one; only Sign In and Sign Out discard it. A 401 permits one refresh
and retry; a refresh the authorization server rejects (400 or 401) or a repeated 401 clears the live
tool catalog and reports **Sign-in required**. A refresh that could not be served — offline, a
timeout, a 5xx — is a network failure: the session is kept and the next request refreshes again.
A failed tool call remains a tool result the model can explain. Sign Out disconnects the
server and deletes its access and refresh tokens, retaining the client registration for the next
sign-in; it does not revoke the provider-side grant.

## Tool names

`MCPToolName` is the one place a server's handle and a tool's own name become a single identifier the
providers accept: `slug__tool`, sanitized to `[A-Za-z0-9_-]` and capped at 64 characters, OpenAI's
limit and the tighter of the two. When it has to trim, the handle is the half that survives, because
it is what routes the call back. `MCPTool.aiTool` also carries the display pair — the server's title
and the tool's own name — so the AI layer renders a row without ever parsing a wire name.

## The loop

`AIToolLoopProvider` is an `AIProvider` that wraps another one, which is why `AIChatState` is almost
unchanged and why an unwrapped route behaves exactly as it did. Per round it streams the base route,
passing text, thinking and usage straight through while collecting `.toolCallRequested`; if nothing
was requested it yields `.finished` and stops. Otherwise it appends the assistant turn with its
calls, and for each one yields `.toolCall`, awaits the invoker, yields `.toolResult` and appends a
tool turn — then goes round again with the same tools armed.

The two tool events are deliberately separate. `.toolCallRequested` is what a transport emits and
carries only the wire name; the loop consumes it and never forwards it. `.toolCall` is what the loop
emits in its place, already carrying what a transcript row has to show.

`AIRequestBody` builds each provider's JSON. It is pure and harness-pinned because the shapes are
unforgiving: OpenAI takes a catalog of `{type: "function", function: {…}}` and results as their own
`role: "tool"` turns, while Anthropic takes `input_schema` with no wrapper, a `tool_use` content
block whose `input` is the arguments parsed back into an object, and results as `tool_result` blocks
that must arrive as **one** user turn however many of them there are.

## The loop somebody else runs

On Codex and Claude the CLI is the MCP client, so there is no loop to wrap. `AIToolServer` is the
hand-off — a server shaped for someone else to start — exactly as `AITool` is for the routes
Tinycast runs itself, and `MCPServer.toolServer` is the one place the mapping happens.
`AIToolServerSession` carries the three things the route needs: what to run, who to ask, and how
many rounds it may spend. `MCPCoordinator.toolServers` builds the list from `enabledServers`
honouring `@slug` and dropping `.never`; `MCPCoordinator.permit` answers with `MCPTrustPolicy` and
the same three-way dialog. The session asks one question at a time: a CLI can hold two calls
open at once, where the API loop never does, and `DialogController` shows one dialog and refuses
the next, which read as the reader declining a call nobody showed them. So a second question waits
for the first dialog to close and is then decided afresh, seeing whatever grant it made; one still
waiting when its turn ends is never asked. An OAuth server with no live session is left out rather
than passed without one — a CLI cannot turn a 401 into a sentence the model can work around, and a
tool result is the only place that explanation would fit. A lent token always goes as
`Authorization`, as Tinycast's own transport sends it, whatever header name the server kept from
before it switched to OAuth; and a Header server with no value is offered with no header at all,
which both encoders omit, rather than dropped — it needs no credential on the API route either.

`CodexMCPLaunch` turns the list into `-c` overrides: `command`/`args`/`env_vars` for a local
server, `url` with `bearer_token_env_var` — or `env_http_headers` when the header is not
`Authorization` — for a remote one, each under `mcp_servers.tinycast-<handle>`, and
`enabled=false` for each of the user's own. Every override is process-scoped, like the feature flags
the route always passed, and one of those, `features.plugins=false`, also keeps a plugin's own
servers out of both the listing and the launch. `CodexMCPLaunch.handle(ofServer:)` is the way
back: an elicitation's `serverName` and an `mcpToolCall` item's `server` name a Codex server, and
only one with the prefix is Tinycast's to ask about or to title a row with. The values live in the
app-server's environment under `TC_MCP_<server>_<key>`, two positions in the launch's own
list rather than any spelling of the handle and key: `github-x` + `TOKEN` and `github` + `X_TOKEN`
would upper-case to one name, and so would `token` and `TOKEN`, a header and a local key, or two
non-Latin handles of the same length — and a shared name hands one server another's secret. A name
that repeats anyway refuses the launch. Codex forwards a variable only under the name it already
has, so a local server with variables starts through `/bin/sh`, which moves each value to the name
the server reads and then execs it; the script carries names, never values. Only a name `export`
accepts — a letter or `_`, then letters, digits and `_` — can be moved, so a key like `API-TOKEN`
is not forwarded to Codex's copy at all, where the API route and Claude hand it over as typed.
That environment is fixed at `exec`, so a changed list, a refreshed OAuth token included, is a
**relaunch**: `CodexAppServerClient` remembers what it was started with and starts again when the
next turn wants something else. The account read at the first launch outlives the process, so a
relaunch does not read it again, and a Settings status check is not a turn: it keeps whatever list
is running rather than relaunching around it. A launch is single-flight, handshake included: a
status check racing a turn, or two quick sends, await the one in progress rather than each start a
process whose exit would then tear down the other's, a `stop` that lands while the list is being
read keeps the launch from starting after it, and an exit is only acted on when it is the current
process's. Nothing else can deliver a new list — `config/mcpServer/reload` takes no parameters and
re-reads the config from disk, and thread-scoped `mcp_servers` on `thread/start` both fails to arm
the tools and undoes the launch-level disabling, which is why it is not used. A tool call arrives as
`mcpServer/elicitation/request`, decoded by `CodexElicitation` and answered `accept` or `decline`.
The question names the tool by `_meta.tool_name` when Codex sends it, since the latest item started
on that server is a different call whenever two run at once; only without it does that item's name
stand in. Every other server request is declined as it always was. `item/started` and
`item/completed` for an `mcpToolCall` become `.toolCall` and `.toolResult`.

`ClaudeMCPLaunch` writes the same list as the CLI's own `mcpServers` record, into a file because
argv is in `ps`: `0600`, and named per turn, like Grok's prompt file, so a second turn never
overwrites or deletes a live turn's configuration out from under the process reading it. It is
deleted with the turn; a crash leaves it, and Grok's prompt file, for `InstalledAIManager` to delete
at the next launch, which removes only `tinycast-mcp-*` and `tinycast-prompt-*` files older than
that launch. The turn then runs `--input-format stream-json` so the consent channel has a
pipe to answer on, and drops `--disallowedTools "*"` — verified to remove the MCP tools along with
the built-ins, after which the model narrates a call it never made. The question only reaches
Tinycast if the CLI's own permission system asks it, and the reader's settings can answer first:
an allow rule `mcp__github` written for their own `github` server matches Tinycast's too, and a
`defaultMode` of `bypassPermissions` skips every question. So the armed turn pins
`--permission-mode default`, which beats a settings `defaultMode`, and passes `--settings` with a
`permissions.ask` rule `mcp__<handle>` for every armed server, which outranks an allow rule from any
source; both were verified against the real CLI with the allow rule and the bypass in the project's
own settings. The reader's other settings — environment, proxy, `apiKeyHelper` — keep working,
which `--setting-sources ""` would not have allowed. A `PreToolUse` hook that answers allow is the
one thing this leaves open.

`ClaudeControlProtocol` is the whole of that channel: `--permission-prompt-tool stdio` puts a
`control_request` of subtype `can_use_tool` on stdout and takes a `control_response` of `allow`,
with the arguments untouched, or `deny` with a reason, on stdin. `updatedPermissions` is never
sent: it would have the CLI write its own settings, and only Tinycast's Settings may change a
standing decision. Any other control request — a subtype Tinycast does not know, or a tool that is
not one of its servers — gets the SDK's `error` response, because the CLI holds the turn until
something answers. **It is the Agent SDK's wire format and is not documented for a host that is not
the SDK**; a CLI release may change it, which is why everything about it is one type. The
documented fallback is `--allowedTools "mcp__<handle>"` under `--permission-mode dontAsk`: the mode
is what refuses every tool the list does not name, since an allow list alone denies nothing, and it
asks no per-call question at all, so it could not express Ask Each Chat. `tool_use` and
`tool_result` blocks become the two events.

While Codex or Claude is the chat model, Tinycast keeps no connection of its own to a local
server: the CLI starts its own copy, and a second would only run it twice.
`MCPServer.runsInTinycast(whileCLIRouteSelected:)` is the rule, and `AppCore` re-applies it
whenever the chat model changes, so choosing an API model starts the server again. A remote server
stays connected — a session, not a process — so its row keeps a live status; a local one reads
Stopped.

## Settings

`MCPSettingsSection` is a section inside Settings → AI, the way `AICommandSection` is. Each row leads
with the handle, because that is the half a reader has to type, then the live status and the
transport. `MCPServerEditor` reaches `MCPCoordinator` through its environment. The editor holds name,
HTTP or command, Header or OAuth authentication, optional client ID/secret, one Sign In / Cancel / Sign Out button and live
sign-in status, enabled, trust, and a Test Connection button that runs a real handshake so a typo is
caught there rather than in the middle of a conversation.

## Manual sweep

- An HTTP server with a bearer header reports its tool count from Test Connection and from its row.
- An OAuth-only server signs in through the browser with client fields empty when DCR is available;
  Test Connection and a BYOK chat use the session. Repeat with supplied client credentials.
- Relaunch retains the sign-in, refresh retains connectivity, and Sign Out makes Test Connection
  report Sign-in required. Changing the endpoint never sends the old token to the new endpoint.
- Cancelling sign-in or occupying port 4962 leaves no listener or stale successful sign-in behind.
- A stdio server (`npx -y @modelcontextprotocol/server-filesystem ~/Desktop`) reaches ready; its
  process is gone ten minutes after the palette closes, and immediately on Quit.
- A question answered with a tool shows the row inline, spinner then glyph, and the reply continues
  after it. Reopening that chat from ⌘K → Chat History still shows what ran.
- The first call raises the dialog. Allow This Chat does not ask again in that conversation and does
  in the next; Always Allow survives a relaunch; Escape refuses only that call.
- `@filesystem list my desktop` shows the tools glyph after the text, sends without the prefix, and
  offers only that server's tools. `@nosuch hello` is sent verbatim.
- On Apple Intelligence, Grok, OpenCode or Cursor, no tool is offered and the reply streams as before.
- On Codex and on the Claude command the same question answers with the same rows, the same dialog
  and the same `@slug` scoping; `ps` during a turn shows no secret on either command line.
- With Tool call rounds on Unlimited, `ps` shows no `--max-turns` on an armed Claude turn, and a
  Codex reply that calls a tool more than 100 times still ends on its own answer.
- A Codex turn with the user's own `~/.codex` servers configured runs none of them: nothing they
  would have printed appears, and their processes never start.
- Signing out of an OAuth server mid-conversation, then asking again, relaunches the app-server
  rather than sending the old token; Codex's own `~/.codex/config.toml` is byte-identical after.
- With `/Library/Application Support/ClaudeCode/managed-mcp.json` present, the Claude row says MCP
  is managed by your organization and the turn runs with no MCP flags at all.
- Switching MCP off, then AI off, leaves no server process resident — including right after a
  Codex turn that used a local server.
- A settings backup carries neither a server nor the flag.
- Harnesses: `mcp-test`, `mcp-stdio-test` and `mcp-oauth-test`, plus the tool halves of `ai-provider-test`
  (catalog and turn encoding, fragmented argument decoding, both CLIs' launch encodings and their
  two consent channels), `ai-chat-test` (the loop, its cap, its output bounds, and tool-use
  persistence), `codex-turn-test` (the launch boundary and its failing closed, one launch for
  concurrent starts, the elicitation, the rows and the call cap) and `installed-ai-test` (the flags, the `0600` configuration and its deletion, the control
  channel, the round cap and the managed-policy branch).
