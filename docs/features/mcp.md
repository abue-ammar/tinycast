# MCP servers

Tinycast connects [Model Context Protocol](https://modelcontextprotocol.io) servers and offers their
tools to the model during a chat. A server is either a remote HTTP endpoint or a command Tinycast
runs on this Mac; either way it advertises tools, Tinycast namespaces them by the server's handle,
and the model calls what it wants. `Features/MCP/` owns servers and knows nothing about chat;
[AI](ai.md) owns tool calling and knows nothing about MCP. `AIChatCoordinator.send` is the one place
the two meet.

## Invariants

- **MCP is off out of the box, and off means fully off.** `AppSettings.mcpEnabled` is the flag and
  `MCPCoordinator.applyEnabled()` is the only place that projects it: no connection opened, no local
  process resident, no tool named to any model. `aiEnabled` off does the same, because chat is the
  only consumer. Both flags and `mcpServers` are excluded from settings backups — a server list is a
  source of executable code and a destination for chat context, and the flag doubles as consent to
  run it, so an import can never arrive having connected one.
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
- **Every turn is bounded three ways.** `AIToolLoopProvider.maxRounds` is 10, after which the turn
  fails saying so — a model that only calls has stopped answering. Each result is cut to
  `maxResultBytes`, and a turn's results together to `maxTurnResultBytes`, because tool output is
  appended inside the turn and so never passes through `ChatSession.boundedContext`.
- **A server's handle is derived, never typed.** `MCPSlug` makes it from the name and uniques it, so
  `@slug` can never name two servers or nothing at all. An unknown handle is not an address: the text
  is sent exactly as it was typed.
- **Servers start with chat and stop after ten idle minutes**, and at `prepareForTermination()`.
  A stdio server is a resident process of someone else's making, and the 100 MB budget is the reason
  this is not "start at launch".
- **Only the two HTTP shapes are offered tools.** `AIModelCapabilities.tools` is true for `.api` and
  false for `.appleIntelligence` and `.chatGPT`; the Codex route already has an invariant saying its
  tools are unavailable, and a sandbox boundary on a local CLI is not something MCP may lift.
- **Tinycast exposes nothing back.** A server request — sampling, elicitation, roots — is declined
  with a JSON-RPC error. The client advertises no capabilities in `initialize`.
- **`Model/` stays Foundation-only.** `mcp-test` compiles the shipped models and pins the framing,
  handles, tool names, output flattening, trust and addressing; `mcp-stdio-test` drives a real
  subprocess. `mcp-oauth-test` pins OAuth parsing, PKCE, endpoint binding, callback lifetime,
  registration, refresh coalescing, redirects and bounded 401 recovery.

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
a trailing slash aside — Google advertises one and publishes none — and it must advertise S256. A supplied client ID and optional secret take precedence;
otherwise Tinycast uses RFC 7591 dynamic registration with a native public client. CIMD and device
flow are not implemented.

The canonical configured MCP URL is the RFC 8707 `resource` on authorization and token requests.
Protected-resource metadata may describe an ancestor path on the same origin, matching current MCP
SDK behavior; sibling paths and other origins are rejected. Saved tokens remain bound to the exact
configured endpoint. This is deliberately broader than RFC 9728's exact resource-match wording.

Access tokens refresh within 60 seconds of expiry. Concurrent requests share one refresh, and
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
- `@filesystem list my desktop` sends without the prefix, shows the chip, and offers only that
  server's tools. `@nosuch hello` is sent verbatim.
- On Apple Intelligence or a ChatGPT model, no tool is offered and the reply streams as before.
- Switching MCP off, then AI off, leaves no server process resident.
- A settings backup carries neither a server nor the flag.
- Harnesses: `mcp-test`, `mcp-stdio-test` and `mcp-oauth-test`, plus the tool halves of `ai-provider-test`
  (catalog and turn encoding, fragmented argument decoding) and `ai-chat-test` (the loop, its cap,
  its output bounds, and tool-use persistence).
