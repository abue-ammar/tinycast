---
title: Quick Actions
description: Fix, rewrite, translate or summarize selected text in any app with one shortcut.
---

Select text in any app, press a shortcut, and Tinycast works on it. Depending on the action, the
result either replaces your selection or appears first in a small floating panel.

Turn it on in **Settings → Quick Actions → Enable Quick Actions**. It's **off** by default. When you
turn it on, Tinycast explains what the feature does and asks for
[Accessibility](/docs/permissions), which it needs to read your selection and type the result back.

While it's off, Tinycast doesn't read any selection or call any model, and every Quick Action
shortcut does nothing.

## The four built-in actions

| Action      | Uses                          | Result by default | Shows changes |
| ----------- | ----------------------------- | ----------------- | ------------- |
| Fix Grammar | Your Quick Actions model      | Replace           | Yes           |
| Rewrite     | Your Quick Actions model      | Preview           | Yes           |
| Translate   | Apple's translator, on device | Preview           | No            |
| Summarize   | Your Quick Actions model      | Always a panel    | No            |

Each action has its own launcher command and global shortcut, both set in
**Settings → Quick Actions**.

- **Fix Grammar** replaces the text right away, because it only corrects mistakes.
- **Rewrite** changes your wording, so it shows you the result first.
- **Summarize** produces something new _about_ your text, so it never replaces your text unless you
  choose to.

Use the menu next to each action to choose **Replace** or **Preview**.

## Running one

Press the action's shortcut, or type its name in the launcher. When you run it from the launcher,
the palette closes first, so the action works on the app behind it instead of Tinycast's search
field.

### Replace

The result goes straight into your document. To revert it, use undo in that app.

While the model works, a message like **Fixing Grammar…** shows a spinner. Click it to cancel.

### Preview

A panel shows the result as it comes in. For Fix Grammar and Rewrite, it highlights what changed.
Summarize and your own actions show their result formatted as Markdown, and you can select text
across all of it. Copy and Replace use the text as the model wrote it.

| Key                      | Does                   |
| ------------------------ | ---------------------- |
| <kbd>return</kbd>        | Replace your selection |
| <kbd>⌘</kbd><kbd>C</kbd> | Copy the result        |
| <kbd>esc</kbd>           | Close the panel        |

Clicking outside the panel also closes it.

If the replacement fails, for example because the app doesn't accept it, **Tinycast copies the
result to your clipboard** and tells you, so you never lose the text.

## Your own Quick Actions

**Add Quick Action** creates a new action from a name, an icon and a prompt. Like the four built-in
actions, it gets a launcher row, a shortcut and an alias.

Custom actions show their result in a panel by default. If you trust the prompt, switch it to
Replace. Tinycast can't tell whether a prompt edits your text or answers a question about it, so it
doesn't decide for you.

Click the pencil button to edit an action. Deleting one asks for confirmation, then frees its
shortcut.

## Changing a built-in prompt

Click the pencil next to **Fix Grammar**, **Rewrite** or **Summarize** to see the exact prompt
Tinycast uses. If you change it, the action uses your version. **Use Default** restores the original.

Translate has no prompt, because it doesn't use a language model.

**Your selection is always treated as text to work on, never as instructions.** Custom prompts can't
turn off this protection, because the result is pasted into your document.

## Choosing a model

**Settings → Quick Actions → Model** is separate from AI Chat's model, so a shortcut you use all day
doesn't have to call a paid API every time. It defaults to **Apple Intelligence**, which runs on your
Mac for free, and falls back to the chat model when Apple Intelligence isn't available.

It offers the same models as [AI Chat](/docs/ai#choosing-a-model), including reasoning effort where
the model supports it.

### A model for one action

Every action except Translate can use its own model. Click the action's pencil button and choose a
model and reasoning effort under **Model**. For example, a quick grammar fix can use a fast model
while a demanding custom prompt uses a more capable one.

**Same as Quick Actions** uses the shared model. An action with its own model shows the model's name
under its own. If you remove that model's connection or turn its provider off, the action goes back
to the shared model.

## Translate

Translate uses **Apple's translator on your Mac**. It's free and doesn't send anything to a provider.

**Translate to** sets the language. The default is **Same as this Mac**. The list comes from Apple,
not from your preferred languages, so it only includes languages the translator supports. Bengali,
for example, isn't available yet.

The first time you translate into a new language, the panel opens and says the language hasn't been
downloaded yet, even if Translate is set to Replace. Click **Open Language & Region**, then
**Translation Languages…**, and download it there. While the panel is open, you can also translate
into a different language.

## When an action won't run

- **In Tinycast's own windows.** Pressing a shortcut while Settings is in front does nothing, and
  Tinycast tells you why. [Notes](/docs/features/notes) is the exception: Quick Actions work on text
  you select in a note.
- **In a password field**, or anywhere Secure Event Input is on.
- **While another Quick Action is still running.** Actions run one at a time, so two can't change the
  same selection.
- **Without Accessibility.** A message explains what's missing.

## How the selection is read

Tinycast first asks the app for the selected text through Accessibility. Chrome, Electron apps and
VS Code need an extra request first, because they only share their selection once something asks
for it.

If that doesn't work, Tinycast briefly copies the selection with <kbd>⌘</kbd><kbd>C</kbd>, reads it,
and restores your clipboard. If nothing is selected, it tells you instead of using whatever you
copied last.

## Backups

**No Quick Actions settings are included in [backups](/docs/reference/backup)**: not the switch,
the models, the Replace or Preview choices, custom prompts, the language or your custom actions.
Importing a backup should never change what a shortcut does to your documents.
