---
title: AI Chat
description: Chat with Apple Intelligence, your installed Codex, Claude, Grok, OpenCode or Cursor, or any API you connect, in the palette.
---

AI Chat is a conversation screen inside the palette. The search field becomes the message box, and
replies appear above it as they stream in. You choose the model: one that runs on your Mac, a
command-line tool you're already signed in to, or an API key of your own.

Turn it on in **Settings → AI → Enable AI**. It's **off** by default. While it's off, there's no AI
Chat command and no chat history file, and <kbd>tab</kbd> goes straight from the launcher to the
clipboard.

Turning AI off stops a reply that's still streaming. It doesn't delete saved chats or API keys.

## Opening a chat

- Run the **AI Chat** command in the launcher.
- Use its global shortcut, which you can record in **Settings → AI**.
- Press <kbd>tab</kbd> from the launcher. Whatever you typed is sent right away as a new question.
- Choose the **AI Chat** row under "Use … with" at the bottom of any search. See
  [Fallbacks](/docs/launcher/fallbacks).

## Talking to it

Type in the search field and press <kbd>return</kbd> to send. While a reply is streaming,
<kbd>return</kbd> stops it.

Replies are formatted as Markdown. Your own messages appear exactly as you typed them. A reply keeps
streaming even if you close the palette or open another screen, and it's saved when it finishes.

Replies also render math. LaTeX between `\(` and `\)`, or between single `$` signs, appears inline;
between `\[` and `\]`, or between `$$` signs, it appears on its own line. An equation that's still
streaming shows as `…` until it's complete, and copying an equation copies its LaTeX. Prices like
"$5 and $10" stay as written.

The model name is on the right side of the header. Click it to switch models, or to change the
reasoning effort on models that support it. A change applies to your _next_ message and never
interrupts a reply in progress.

| Action (<kbd>⌘</kbd><kbd>K</kbd>) | What it does                          |
| --------------------------------- | ------------------------------------- |
| Stop Response                     | Stops the reply that's streaming      |
| New Chat                          | Starts a new conversation             |
| Copy Last Response                | Copies the latest reply               |
| Remove Attachments                | Removes every file waiting to be sent |
| Chat History                      | Opens your saved conversations        |
| AI Settings                       | Opens Settings → AI                   |

Press <kbd>esc</kbd> in an empty message box to leave the chat. The conversation is still there when
you come back.

### Chat History

<kbd>⌘</kbd><kbd>K</kbd> → **Chat History** lists saved conversations grouped by day, with a preview
of the selected one.

| Action           | Shortcut                             |
| ---------------- | ------------------------------------ |
| Open Chat        | <kbd>return</kbd>                    |
| Delete Chat      | <kbd>⌃</kbd><kbd>X</kbd>             |
| Delete All Chats | <kbd>⌃</kbd><kbd>⇧</kbd><kbd>X</kbd> |

Empty chats are never saved.

## Coming back to a chat

Two settings in **Settings → AI** control what you see when you open AI Chat again:

| Setting                        | Options                                  | Default                 |
| ------------------------------ | ---------------------------------------- | ----------------------- |
| Opens to                       | Recent Conversation · A New Conversation | **Recent Conversation** |
| Start a new conversation after | 2 · 5 · 10 · 30 Minutes · Never          | **5 Minutes**           |

With **Recent Conversation**, you return to the chat you left, unless it's been idle for longer than
the second setting. This also works after a restart.

Asking a question with <kbd>tab</kbd> or the fallback row always starts a new chat, so a new
question is never added to an unrelated conversation.

## Choosing a model

Models come from **Settings → AI → Providers → Manage…**. **Default model**, below it, sets which
model chat uses and its reasoning effort.

The panel lists every provider on the left and shows the selected one on the right, in up to three
tabs:

- **Overview** shows whether the provider is ready, which account it's signed in with, and which
  command it runs. The account's email address is blurred until you click it.
- **Models** lists every model the provider offers, each with a checkbox. **Checked models appear in
  the model picker.** If you haven't changed a provider's list, all of its models are shown,
  including ones it adds later. The default model is always shown.
- **Advanced**, for installed tools, is described below.

Every provider has a switch. **Turning a provider off keeps it set up but removes its models from
every picker**, so you can set an API connection aside without deleting it or its key.

### Apple Intelligence

Apple Intelligence runs **on your Mac**. It needs no key or account, and nothing leaves your Mac.
When your Mac supports it, it's the default.

It works with text only, with no web search or attachments. If Apple Intelligence is turned off in
System Settings, Tinycast tells you. **It never switches you to a paid API without asking.**

### Installed AI: Codex, Claude, Grok, OpenCode and Cursor

If you already use the `codex`, `claude`, `grok`, `opencode` or `agent` (Cursor) command-line tools,
Tinycast can use their existing setup. Codex also works with a configured API provider that doesn't
require an OpenAI sign-in. OpenCode needs version 2 or later. **Tinycast never asks for or stores
their keys.**

Each tool has its own switch, and all five are off by default. The pane shows whether each one is
ready, not installed, or needs you to sign in. It links to the install page and can copy the sign-in
command for you.

Tinycast finds each command the same way your Terminal does. If it finds the wrong copy, or none,
open the tool's **Advanced** tab:

- **Command path** sets the command to run instead. Leave it empty to let Tinycast find it. **If
  nothing exists at the path, Tinycast reports it** rather than using another copy it finds.
- **Variables** are set for that tool every time it starts, such as a proxy or a config folder.
  Values are stored in your login Keychain. A few variable names are reserved by Tinycast to keep the
  tool from touching your files, and the row tells you when a value won't be used.

Tinycast uses these tools for chat only. Claude, Grok and OpenCode run with tools, file access and
shell access turned off. The exception is [MCP servers](/docs/ai/mcp) you add, which Codex and Claude
can call but the other three can't.

Cursor runs in Ask mode in a private Tinycast workspace: it can read but not edit, and MCP tools
aren't approved automatically. Cursor's command-line tool can't start without your MCP
configuration, so MCP servers you've already approved in Cursor still apply. The Cursor row in the
Providers pane points this out.

After each reply, Tinycast deletes the chat or session that the reply created. Your other saved
chats in those tools aren't touched.

### API connections

Use your own key with **OpenAI API**, **Anthropic Claude**, **Google Gemini**, **OpenRouter**, or
any **OpenAI Compatible** endpoint, including a local one like Ollama.

- **Keys are stored only in your login Keychain.** They never appear in preferences, logs or
  backups.
- Remote endpoints must use HTTPS. Plain HTTP only works for `localhost`, `127.0.0.1` and `::1`,
  where a key is optional.
- A key is tied to the address it was saved for. If you change a connection's base URL, Tinycast
  asks for a new key instead of sending the old one to the new address.
- While you edit a connection, Tinycast asks the provider which models your key can use, and you can
  search that list as you type. If a gateway can't list its models, type the model ID yourself.

For gateways that follow DeepSeek's API, the reasoning effort menu includes **None**, which turns
thinking off.

## Web search

**Settings → AI → Web search** is off by default. Your prompts are only sent to a search engine after
you turn it on.

It works with **Codex** and with **OpenRouter** models. Searches appear inline in the reply with the
query that was used, and sources are linked by name.

## Attachments

Press <kbd>⌘</kbd><kbd>V</kbd> in the message box to attach what's on your clipboard:

- **An image or screenshot**, scaled to at most 1568 px on its longest side.
- **A PDF.**
- **A text file**, like a CSV, Markdown or source file. Its contents are added to the message.

Attachments appear as one small pill after your text, with an icon for the newest one and a count,
like `+2`, for the rest. Hover over the pill to see their names, or click it to list them, with a
small preview for each image, and remove any one with its ✕. Press <kbd>delete</kbd> in an empty
message box to remove the last one.

Not every model accepts every kind of file. Tinycast refuses an attachment as soon as you add it and
explains why, so it never sends something the model can't read.

| Route                                      | Images                   | PDFs | Text files |
| ------------------------------------------ | ------------------------ | ---- | ---------- |
| Apple Intelligence                         | No                       | No   | Yes        |
| Codex                                      | Yes                      | No   | Yes        |
| Claude command                             | Yes                      | No   | Yes        |
| OpenCode command                           | If the model supports it | No   | Yes        |
| Grok and Cursor commands                   | No                       | No   | Yes        |
| OpenAI API and Anthropic Claude            | Yes                      | Yes  | Yes        |
| Google Gemini and OpenAI Compatible        | Yes                      | No   | Yes        |
| OpenRouter                                 | If the model supports it | No   | Yes        |

Only files on your Mac are read. Copied web addresses are never downloaded.

## System prompt

Tinycast sends a short note before every conversation that tells the model where it's running. The
**System prompt** box adds your own instructions after that note.

**Send a system prompt** (on by default) controls both. If you turn it off, no instructions are sent.
Both are billed again with every message, and the pane mentions this.

When the box contains text, it opens blurred, so a screenshot of Settings doesn't show your
instructions. Click it to edit.

## Tools from MCP servers

With an API connection, or with the installed Codex or Claude command, the model can call tools from
MCP servers you add. See [MCP servers](/docs/ai/mcp).

## Privacy and storage

- Conversations are saved on your Mac in `ai-chats.sqlite3`, in Tinycast's Application Support
  folder.
- **Keep conversations** sets how long they're kept: **7 Days**, **30 Days**, **3 Months** or
  **Forever** (default). Old chats are only removed while AI is on, so they're kept on a Mac with AI
  turned off.
- **No AI settings are included in [backups](/docs/reference/backup)**: not the switch, the
  connections, the default model, the system prompt, web search or history settings.
- The signed-in Codex account is blurred in Settings until you click it.
