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
the reply, with a spinner while it runs. The reply carries on after it, and the row is saved with
the chat.

### Talking to one server

Start a message with a handle, like `@filesystem list my desktop`. Only that server's tools are
offered, and the handle is removed before the message is sent. A handle that matches no server is
sent exactly as you typed it.

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

Only **API connections** are offered tools: OpenAI API, Anthropic Claude, Google Gemini, OpenRouter
and OpenAI Compatible endpoints.

Apple Intelligence and the installed Codex, Claude, Grok, OpenCode and Cursor commands never get tools. For those,
chat works exactly as it does without MCP.

## Limits

- A reply can go through at most **10 rounds** of tool calls. A model that only keeps calling tools
  has stopped answering, so the reply ends and says so.
- Each tool result, and all results in one reply together, are capped in size.
- Servers start when you use chat and stop after **10 idle minutes**, or when Tinycast quits.
- Tinycast offers nothing back to a server. Requests from a server, like sampling, are declined.

## Backups

Neither the switch nor your server list travels in a [backup](/docs/reference/backup). A server list
can run code on your Mac, so adding one has to be something you do yourself.
