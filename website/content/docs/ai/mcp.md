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
| Header      | For HTTP. A header name and value, like `Authorization` and `Bearer …`.     |
| Command     | For a local server, like `npx`.                                             |
| Arguments   | Like `-y @modelcontextprotocol/server-filesystem ~/Desktop`.                |
| Environment | `NAME=value`, one per line, like `GITHUB_TOKEN=…`.                          |
| Trust       | **Ask Each Chat**, **Always Allow** or **Never Allow**.                     |

**Test Connection** runs a real handshake and reports how many tools the server offers, so a typo
shows up here instead of halfway through a conversation.

**Header values and environment values are stored in your login Keychain**, never in preferences,
logs or backups. Removing a server deletes them.

A local server runs with your own user account, so only add commands you trust.

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
