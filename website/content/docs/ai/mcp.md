---
title: MCP servers
description: Give AI chats tools from Model Context Protocol servers, remote or running on your Mac.
---

[Model Context Protocol](https://modelcontextprotocol.io) servers provide tools a model can call, like
reading a folder, searching an issue tracker or looking something up. When you add a server,
Tinycast gives its tools to the model during your conversations.

Turn it on in **Settings → AI → MCP Servers → Enable MCP servers**. It's **off** by default, and it
only applies while [AI](/docs/ai) is on. While either one is off, Tinycast doesn't contact any
server or run any server process.

## Adding a server

**Add MCP Server** opens the editor.

| Field              | What goes in it                                                                                            |
| ------------------ | ---------------------------------------------------------------------------------------------------------- |
| Name               | Anything. It becomes the server's **handle**, like `@github`.                                              |
| Connection         | **HTTP** for a remote server, or **Command** for one that runs on your Mac.                                |
| URL                | For HTTP. Remote servers must use HTTPS; plain HTTP only works for `localhost`.                            |
| Authentication     | For HTTP. **Header** for a fixed credential, or **OAuth** to sign in through your browser.                 |
| Header             | With Header authentication. A name and value, like `Authorization` and `Bearer …`.                         |
| Client ID / secret | With OAuth. Leave these empty for automatic registration, or enter the credentials your provider gave you. |
| Command            | For a local server, like `npx`.                                                                            |
| Arguments          | Like `-y @modelcontextprotocol/server-filesystem ~/Desktop`.                                               |
| Environment        | `NAME=value`, one per line, like `GITHUB_TOKEN=…`.                                                         |
| Trust              | **Ask Each Chat**, **Always Allow** or **Never Allow**.                                                    |

**Test Connection** connects to the server and reports how many tools it offers, so you find typos
here rather than in the middle of a conversation.

**Header values, environment values and OAuth credentials are stored in your login Keychain**, never
in preferences, logs or backups. Removing a server deletes them.

A local server runs with your user account, so only add commands you trust.

### Signing in to an OAuth server

Choose **HTTP**, paste the server's MCP URL, and select **OAuth**. Click **Sign In**, complete the
provider's sign-in in your browser and review the access it asks for. Return to Tinycast when the
browser says you can close the tab. **Signed in** confirms that it worked, and **Test Connection**
checks the signed-in connection and reports how many tools it offers. Save the server to use it in
chat.

Leave Client ID and Client secret empty if the provider supports automatic registration. If it
requires you to register your own OAuth client, enter its client ID and secret, if it has one, and
register `http://127.0.0.1:4962/callback` as the redirect URL. Sign-in times out after five minutes.
If another app is using that port, Tinycast tells you so you can close it and try again.

Tinycast refreshes tokens automatically before they expire. If a server shows **Sign-in required**,
open it in Settings and sign in again. **Sign Out** disconnects the server and removes its access and
refresh tokens from your Mac. The client registration stays; to fully revoke access, remove the app
in the provider's account settings.

Signing in doesn't change the server's trust setting. With **Ask Each Chat**, Tinycast still asks
before the first tool call.

## Using tools in a chat

The model is offered the tools from every enabled server. When it calls one, a row appears in the
reply with a spinner while the tool runs. Consecutive calls share one line, which shows the current
call while it runs, then the number of calls and any failures. Click the line to see each call. The
reply continues after it, and the calls are saved with the chat.

In the [AI Chat window](/docs/ai#the-ai-chat-window), **+ → Tools** chooses the servers for the open
chat. Turn off **Use Tools** to offer none, or turn off single servers under **Servers**. The choice
lasts for that chat only and isn't saved. If the chat's model can't call tools, the menu says so.

### Talking to one server

Start a message with a handle, like `@filesystem list my desktop`. A tools icon after your text shows
that the handle was recognized. Only that server's tools are offered, and the handle is removed
before the message is sent. A handle that doesn't match any server is sent as you typed it.

### Permission to run

With **Ask Each Chat** (the default), Tinycast asks before the first tool call in each conversation:

- **Always Allow** remembers your choice for that server.
- **Allow This Chat** allows calls for this conversation only.
- **Don't Allow** refuses this one call. <kbd>esc</kbd> does the same, and the next call asks again.

Setting a server to **Never Allow** keeps it in your list without offering its tools. You can only
change this in Settings.

A refused or failed call isn't treated as an error. The model is told what happened and can answer
without the tool.

## Which models get tools

Tools are offered to **API connections** (OpenAI API, Anthropic Claude, Google Gemini, OpenRouter and
OpenAI Compatible endpoints) and to the installed **Codex** and **Claude** commands. With those two
commands, the command-line tool calls the tools itself. The servers, the confirmation and the rows in
the reply work the same as everywhere else, except that OAuth servers you aren't signed in to are
left out. Tinycast never changes either command's settings.

When a chat offers servers to Codex or Claude, the model may use anything those servers' tools do,
like running a command or reading a file. The command's own built-in tools stay off, and every call
still goes through the server's **Trust** setting.

Your own Codex and Claude MCP servers aren't used in a Tinycast chat. Claude is told to use only
Tinycast's server list. Codex receives Tinycast's servers under their own names, like
`tinycast-github`, and every server in your Codex configuration is turned off for that chat, so one
of your servers named `github` is never confused with Tinycast's `@github`. If Tinycast can't read
which servers your Codex configuration has, or one of them has a dot or `=` in its name, Tinycast
won't start Codex at all, and the Codex row in Settings explains why.

A few things work differently with Codex:

- Adding, removing or signing in to a server again restarts its helper process, which adds about a
  second to your next message. The same happens when you switch between a message that starts with
  a handle, like `@github`, and one that doesn't, because each offers a different set of servers.
- Turning MCP off, or setting a server to **Never Allow**, removing it or signing out of it, stops
  the helper right away so the server doesn't keep running. If a reply is in progress at that
  moment, the helper keeps the server until your next message or until it's been idle for ten
  minutes.
- An environment variable is only passed to a server that Codex starts if its name uses letters,
  digits and `_` and doesn't start with a digit. `API_TOKEN` works, but `API-TOKEN` isn't passed on.
- Codex can also read content a server publishes, like Notion's guides, without asking. With Codex,
  **Ask Each Chat** applies to a server's tools but not to this content. **Never Allow** still keeps
  the server out completely.

Apple Intelligence and the installed Grok, OpenCode and Cursor commands never get tools. With those,
chat works the same as it does without MCP.

If your organization installs a Claude Code MCP policy, that policy decides MCP for the Claude
command, and Tinycast doesn't pass any servers to it. The Providers row tells you when this applies.

## Limits

- **Settings → AI → Chat → Tool call rounds** sets how many rounds of tool calls a single reply can
  use: **25** by default, or 10, 50, 100 or **Unlimited**. A model that keeps calling tools without
  answering is stuck, so when it reaches the limit, the reply ends with a note saying how many
  rounds it used. With Codex, the limit counts individual tool calls instead of rounds, which stops
  a runaway reply sooner. With Unlimited, a reply only ends when the model finishes, when you click
  **Stop**, or, on an API connection, when the tool history passes 1 MB. The reply keeps running
  while the palette is hidden or the window is closed, and every round is billed by your provider
  or counted against your plan.
- Each tool result, and the total of all results in one reply, has a size limit.
- Servers start when you use chat and stop after **10 minutes** without use, or when Tinycast quits.
  While Codex or Claude is the chat model, a server that runs on your Mac is started by that command
  instead of by Tinycast, so it never runs twice. Its row in Settings shows **Stopped** until you
  switch to an API model.
- Tinycast doesn't offer anything back to servers. Requests from a server, like sampling, are
  declined.

## Backups

Neither the switch nor your server list is included in a [backup](/docs/reference/backup). A server
list can run code on your Mac, so you have to add servers yourself.
