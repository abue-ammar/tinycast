---
title: AI Chat
description: Chat with Apple Intelligence, your installed Codex, Claude, Grok, OpenCode or Cursor, or any API you connect, right in the palette.
---

AI Chat is a conversation screen inside the palette. The search field becomes the message box, and
replies stream in above it. You choose the model: one that runs on your Mac, a command-line tool you
already signed in to, or an API key you bring.

**Settings → AI → Enable AI** holds the switch. It ships **off**. While it is off there is no AI Chat
command, no chat history file, and <kbd>tab</kbd> skips straight from the launcher to the clipboard.

Turning AI off stops a reply that is still streaming. It does not delete saved chats or API keys.

## Opening a chat

- The **AI Chat** command in the launcher.
- Its own global shortcut, recorded in **Settings → AI**.
- <kbd>tab</kbd> from the launcher. Whatever you typed is sent straight away as a new question.
- The **AI Chat** row under "Use … with" at the bottom of any search. See
  [Fallbacks](/docs/launcher/fallbacks).

## Talking to it

Type in the search field and press <kbd>return</kbd> to send. While a reply streams, <kbd>return</kbd> stops
it.

Replies render Markdown. Your own messages stay exactly as you typed them. A reply keeps streaming
even if you close the palette or open another screen, and it is saved when it finishes.

The model name sits at the right of the header. Click it to switch models, or to change the reasoning
effort on models that support one. A switch applies to your _next_ message; it never interrupts a
reply already on its way.

| Action (<kbd>⌘</kbd><kbd>K</kbd>) | What it does                         |
| --------------------------------- | ------------------------------------ |
| Stop Response                     | Stops the reply that is streaming    |
| New Chat                          | Starts a fresh conversation          |
| Copy Last Response                | Copies the latest reply              |
| Remove Attachments                | Clears every file waiting to be sent |
| Chat History                      | Opens your saved conversations       |
| AI Settings                       | Opens Settings → AI                  |

<kbd>esc</kbd> on an empty message box leaves the chat. The conversation is still there when you come
back.

### Chat History

<kbd>⌘</kbd><kbd>K</kbd> → **Chat History** lists saved conversations, grouped by day, with a preview
of the one selected.

| Action           | Shortcut                             |
| ---------------- | ------------------------------------ |
| Open Chat        | <kbd>return</kbd>                    |
| Delete Chat      | <kbd>⌃</kbd><kbd>X</kbd>             |
| Delete All Chats | <kbd>⌃</kbd><kbd>⇧</kbd><kbd>X</kbd> |

Empty chats are never saved.

## Coming back to a chat

Two settings in **Settings → AI** decide what you see when you open AI Chat again:

| Setting                        | Options                                  | Default                 |
| ------------------------------ | ---------------------------------------- | ----------------------- |
| Opens to                       | Recent Conversation · A New Conversation | **Recent Conversation** |
| Start a new conversation after | 2 · 5 · 10 · 30 Minutes · Never          | **5 Minutes**           |

With **Recent Conversation**, you land back in the chat you left, unless it has been idle longer than
the second setting. This works across a restart too.

Asking a question with <kbd>tab</kbd> or the fallback row always starts a new chat. A question asked
outright should not be tacked onto an unrelated conversation.

## Choosing a model

**Settings → AI → Providers → Manage…** is where models come from. **Default model** below it picks
the one chat uses, and its reasoning effort.

### Apple Intelligence

Runs **on your Mac**. No key, no account, and nothing leaves the machine. When your Mac supports it,
it is the default.

It reads and writes text only, with no web search and no attachments. If Apple Intelligence is
switched off in System Settings, Tinycast tells you so. **It never quietly moves you to a paid API
instead.**

### Installed AI: Codex, Claude, Grok, OpenCode and Cursor

If you already use the `codex`, `claude`, `grok`, `opencode` or `agent` (Cursor) command-line tools,
Tinycast can use them with the account you are signed in to. **Tinycast never asks for or stores their keys.**

Each one has its own switch, and all five ship off. The pane shows whether each is ready, missing,
or needs you to sign in. It links to the install page and can copy the sign-in command for you.

Tinycast uses them as plain chat. Claude, Grok and OpenCode run with tools, file access and shell access
switched off. Cursor runs in Ask mode against Tinycast's private workspace: read-only exploration,
no edits, and no MCP auto-approval. Cursor's CLI has no way to start without your MCP configuration,
so MCP servers you have already approved in Cursor still apply on this route — the Providers pane
says so on the Cursor row. After each reply, Tinycast deletes the chat or session that turn
created — not your other saved chats.

### API connections

Bring your own key for **OpenAI API**, **Anthropic Claude**, **Google Gemini**, **OpenRouter**, or
any **OpenAI Compatible** endpoint, including a local one like Ollama.

- **Keys live only in your login Keychain.** They never appear in preferences, logs or backups.
- Remote endpoints must use HTTPS. Plain HTTP works only for `localhost`, `127.0.0.1` and `::1`,
  where a key is optional.
- A key belongs to the address it was saved for. Point a connection at a different base URL and
  Tinycast asks for a new key rather than sending the old one somewhere new.
- While you edit a connection, Tinycast asks the provider which models your key can use, and you
  search that list as you type. If a gateway cannot list models, type the model ID by hand.

For a gateway that copies DeepSeek's API, the reasoning effort menu offers **None**, which turns
thinking off.

## Web search

**Settings → AI → Web search** is off by default. Your prompts only reach a search engine once you
turn it on.

It works with **Codex** and with **OpenRouter** models. A search shows inline in the reply, with the
query it used, and sources are linked by name.

## Attachments

Press <kbd>⌘</kbd><kbd>V</kbd> in the message box to attach what is on your clipboard:

- **An image or screenshot.** Scaled to at most 1568 px on its long edge.
- **A PDF.**
- **A text file**, like a CSV, Markdown or source file. Its contents go into the message.

Attachments show as one small pill after what you type: an icon for the newest, and `+2` or so for
the rest. Hover over it to see their names, or click it to list them, each image with a small
preview, and remove any one with its ✕.
<kbd>delete</kbd> in an empty message box removes the last one.

Not every model can take every kind. Tinycast refuses at the moment you attach, and says why, rather
than sending something the model will never see.

| Route                               | Images               | PDFs | Text files |
| ----------------------------------- | -------------------- | ---- | ---------- |
| Apple Intelligence                  | No                   | No   | Yes        |
| Codex                               | Yes                  | No   | Yes        |
| Claude, Grok, OpenCode and Cursor commands | No                   | No   | Yes        |
| OpenAI API and Anthropic Claude     | Yes                  | Yes  | Yes        |
| Google Gemini and OpenAI Compatible | Yes                  | No   | Yes        |
| OpenRouter                          | If the model says so | No   | Yes        |

Only files on your Mac are read. A copied web address is never downloaded.

## System prompt

Tinycast sends a short note ahead of every conversation that tells the model where it is running.
The **System prompt** box adds your own instructions after it.

**Send a system prompt** (on by default) controls both. Turn it off and no instructions are sent at
all. Both are billed again on every message, which is why the pane says so.

The box opens blurred when it has text in it, so a screenshot of Settings does not show your
instructions. Click to edit.

## Tools from MCP servers

With an API connection, the model can call tools from MCP servers you add. See
[MCP servers](/docs/ai/mcp).

## Privacy and storage

- Conversations are saved on your Mac in `ai-chats.sqlite3`, in Tinycast's Application Support
  folder.
- **Keep conversations** decides how long: **7 Days**, **30 Days**, **3 Months** or **Forever**
  (default). Old chats are only removed while AI is on, so a Mac with AI switched off keeps them.
- **No AI setting travels in a [backup](/docs/reference/backup)**: not the switch, the connections,
  the default model, the system prompt, web search or history rules.
- The signed-in Codex account is blurred in Settings until you click it.
