---
title: MCP servers
description: Give AI Chat tools from Model Context Protocol servers, remote or running on your Mac.
---

[Model Context Protocol](https://modelcontextprotocol.io) servers offer tools a model can call: read
a folder, search an issue tracker, look something up. Add a server and AI Chat hands its tools to the
model while you talk.

**Settings → AI → MCP Servers → Enable MCP servers** holds the switch. It ships **off**, and it only
matters while [AI Chat](/docs/ai) is on. While either is off, no server is contacted and no server
process runs.

## Adding a server

**Add MCP Server** opens the editor.

| Field       | What goes in it                                                             |
| ----------- | --------------------------------------------------------------------------- |
| Name        | Anything. It becomes the server's **handle**, like `@github`.               |
| Connection  | **HTTP** for a remote server, or **Command** for one that runs on your Mac. |
| URL         | For HTTP. Remote servers must use HTTPS; plain HTTP only for `localhost`.   |
| Authentication | For HTTP. **Header** for a static credential, or **OAuth** for browser sign-in. |
| Header      | With Header authentication. A name and value, like `Authorization` and `Bearer …`. |
| Client ID / secret | With OAuth. Leave blank for automatic registration, or enter the credentials supplied by your server provider. |
| Command     | For a local server, like `npx`.                                             |
| Arguments   | Like `-y @modelcontextprotocol/server-filesystem ~/Desktop`.                |
| Environment | `NAME=value`, one per line, like `GITHUB_TOKEN=…`.                          |
| Trust       | **Ask Each Chat**, **Always Allow** or **Never Allow**.                     |

**Test Connection** runs a real handshake and reports how many tools the server offers, so a typo
shows up here instead of halfway through a conversation.

**Header values, environment values and OAuth credentials are stored in your login Keychain**, never in preferences,
logs or backups. Removing a server deletes them.

A local server runs with your own user account, so only add commands you trust.

### Signing into an OAuth server

Choose **HTTP**, paste the server's MCP URL, and select **OAuth**. Choose **Sign In**, complete the
provider's browser sign-in and review its access request. Return to Tinycast when the browser says
you can close the tab. **Signed in** confirms completion; **Test Connection** checks the authenticated
session and reports its tool count. Save the server to use it in an API chat.

Leave Client ID and Client secret blank when the provider supports automatic registration. If it
requires your own registered OAuth client, enter its client ID and any required secret. Register
`http://127.0.0.1:4962/callback` as its redirect URL. Sign-in expires after five minutes; if another
app uses that port, Tinycast reports the conflict so you can free it and retry.

Tinycast refreshes expiring tokens automatically. If it shows **Sign-in required**, open the server
in Settings and sign in again. **Sign Out** disconnects it and removes its access and refresh tokens
from this Mac. It keeps the client registration; revoke the app in the provider's settings if you
also want to withdraw its account access there.

OAuth sign-in does not change the server's tool trust setting. **Ask Each Chat** still asks before
the first tool call.

## Using tools in a chat

Tools from every enabled server are offered to the model. When it calls one, a row shows inline in
the reply, with a spinner while it runs. Several calls in a row share one line: the call running
now, then how many it called once they finish, and any that failed. Click that line to see each
call. The reply carries on after it, and the calls are saved with the chat.

### Talking to one server

Start a message with a handle, like `@filesystem list my desktop`. A tools icon after your text
shows the handle was recognised. Only that server's tools are offered, and the handle is removed
before the message is sent. A handle that matches no server is sent exactly as you typed it.

### Permission to run

With **Ask Each Chat** (the default), the first tool call in a conversation asks first:

- **Always Allow** remembers the choice for that server.
- **Allow This Chat** allows it for this conversation only.
- **Don't Allow** refuses just this call. <kbd>esc</kbd> does the same, and the next call asks
  again.

**Never Allow** on the server's row keeps the server without offering its tools. Only Settings can
set that.

A refused or failed call is not an error. The model is told what happened and can answer without it.

## Which models get tools

**API connections** are offered tools — OpenAI API, Anthropic Claude, Google Gemini, OpenRouter and
OpenAI Compatible endpoints — and so are the installed **Codex** and **Claude** commands. On those
two the CLI calls the tools itself; the servers, the confirmation and the rows in the reply are the
same ones you see everywhere else, except that an OAuth server you are not signed into is left out.
Nothing is written to either command's settings.

Your own Codex and Claude MCP servers stay out of a Tinycast chat. Claude is told to use Tinycast's
list alone. Codex is handed Tinycast's servers under names of their own, like `tinycast-github`,
and every server in your Codex configuration is switched off for that chat, so a server of yours
named `github` never mixes with Tinycast's `@github`. If Tinycast cannot read which servers your
Codex configuration has, or one of them has a dot or `=` in its name, Codex does not start from
Tinycast at all, and the Codex row in Settings says why.

A few things are different on Codex:

- Adding, removing or re-authorizing a server restarts its helper, which takes about a second on
  the next message. So does moving between a message that starts with a handle, like `@github`,
  and one that does not, since each offers a different set of servers.
- Switching MCP off, or setting a server to **Never Allow**, removing it or signing out of it,
  stops the helper at once, so the server does not keep running inside it. If a reply is running
  at that moment, the helper keeps the server until your next message or ten idle minutes.
- An environment variable reaches a server Codex starts only if its name is letters, digits and
  `_`, not starting with a digit. `API_TOKEN` works; `API-TOKEN` is not passed on.
- Codex can also read what a server publishes for reading, like Notion's guides, without asking.
  **Ask Each Chat** covers a server's tools on Codex, not those reads; **Never Allow** still keeps
  a server out entirely.

Apple Intelligence and the installed Grok, OpenCode and Cursor commands never get tools. For those,
chat works exactly as it does without MCP.

If your organization installs a Claude Code MCP policy, MCP on the Claude command is their decision
and Tinycast passes no servers to it. The Providers row says so.

## Limits

- **Settings → AI → Chat → Tool call rounds** sets how many rounds of tool calls one reply can go
  through: **25** by default, or 10, 50, 100 or **Unlimited**. A model that only keeps calling tools
  has stopped answering, so at that limit the reply ends and says it stopped after that many rounds.
  On Codex the count is tool calls rather than rounds, which stops a runaway reply sooner. On
  Unlimited only the model or **Stop** ends it, or on an API connection a tool history past 1 MB,
  and a reply keeps running while the palette is hidden, each round billed by your provider or
  counted against your plan.
- Each tool result, and all results in one reply together, are capped in size.
- Servers start when you use chat and stop after **10 idle minutes**, or when Tinycast quits.
  While Codex or Claude is the chat model, a server that runs on your Mac is started by that
  command instead of Tinycast, so it never runs twice. Its row in Settings shows **Stopped** until
  you choose an API model.
- Tinycast offers nothing back to a server. Requests from a server, like sampling, are declined.

## Backups

Neither the switch nor your server list travels in a [backup](/docs/reference/backup). A server list
can run code on your Mac, so adding one has to be something you do yourself.
