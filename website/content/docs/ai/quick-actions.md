---
title: Quick Actions
description: Fix, rewrite, translate or summarize the text you have selected in any app, with one shortcut.
---

Select some text in any app, press a shortcut, and Tinycast works on it. The result either replaces
your selection or shows in a small floating panel first, depending on the action.

**Settings → Quick Actions → Enable Quick Actions** holds the switch. It ships **off**. Turning it on
explains what it does, then asks for [Accessibility](/docs/permissions), because Tinycast has to read
your selection and type the result back.

While it is off, no selection is read, no model is called, and every Quick Action shortcut does
nothing.

## The four built-in actions

| Action      | Uses                          | Result by default | Shows changes |
| ----------- | ----------------------------- | ----------------- | ------------- |
| Fix Grammar | Your Quick Actions model      | Replace           | Yes           |
| Rewrite     | Your Quick Actions model      | Preview           | Yes           |
| Translate   | Apple's translator, on device | Preview           | No            |
| Summarize   | Your Quick Actions model      | Always a panel    | No            |

Each one has its own launcher command and its own global shortcut, both in
**Settings → Quick Actions**.

- **Fix Grammar** replaces straight away, because it only fixes what was wrong.
- **Rewrite** changes your voice, so it shows you first.
- **Summarize** answers a question _about_ your text, so it never replaces it without you choosing
  to.

Change **Replace** or **Preview** per action with the menu beside it.

## Running one

Press the action's shortcut, or type its name in the launcher. From the launcher, the palette closes
first and the action works on the app behind it, not on Tinycast's own search field.

### Replace

The result goes straight into your document. To take it back, use undo in that app.

### Preview

A panel shows the result as it arrives. For Fix Grammar and Rewrite it marks what changed.

| Key                      | Does                   |
| ------------------------ | ---------------------- |
| <kbd>return</kbd>        | Replace your selection |
| <kbd>⌘</kbd><kbd>C</kbd> | Copy the result        |
| <kbd>esc</kbd>           | Close the panel        |

Clicking outside the panel closes it too.

If a replacement cannot land, for example because the app would not accept it, **the result is
copied to your clipboard** and a message says so. You never lose the text.

## Your own Quick Actions

**Add Quick Action** creates one from a name, an icon and a prompt. It gets a launcher row, a
shortcut and an alias like the built-in four.

A custom action shows its result in a panel by default. Switch it to Replace if you trust the
prompt; Tinycast cannot tell whether a prompt edits your text or answers a question about it.

The pencil button edits it. Deleting one asks first, then frees its shortcut.

## Changing a built-in prompt

The pencil beside **Fix Grammar**, **Rewrite** or **Summarize** opens the exact prompt Tinycast uses.
Change it and that action follows your version. **Use Default** brings the original back.

Translate has no prompt, because no language model is involved.

**Your selection is always treated as material to work on, never as instructions.** A custom prompt
cannot turn that guard off, because the result gets pasted into your document.

## Choosing a model

**Settings → Quick Actions → Model** is separate from AI Chat's model on purpose. A shortcut you press
all day should not bill an API every time. It defaults to **Apple Intelligence**, which runs on your
Mac for nothing, and falls back to chat's model when Apple Intelligence is not available.

It offers the same models as [AI Chat](/docs/ai#choosing-a-model), including reasoning effort where
the model supports it.

### A model for one action

Any action except Translate can use a model of its own. Open it with the pencil button and pick
one under **Model**, with its own reasoning effort. A quick grammar fix can stay on a fast model while
a demanding custom prompt uses a stronger one.

**Same as Quick Actions** follows the shared model. An action with its own model shows it under its
name. If you remove its connection or turn its provider off, the action goes back to the shared
model.

## Translate

Translate uses **Apple's own translator on your Mac**. It costs nothing and sends nothing to a
provider.

**Translate to** picks the language. **Same as this Mac** is the default. The list is Apple's, not
your preferred languages, so it only offers languages the translator can actually reach. Bengali, for
example, is not on it yet.

The first time you translate into a language, the panel opens and offers to download it, even if
Translate normally replaces. Once the panel is open you can also translate into another language.

## When an action refuses

- **In Tinycast's own windows.** Pressing a shortcut with Settings in front does nothing, and says so.
- **In a password field**, or anywhere Secure Event Input is on.
- **While another Quick Action is still running.** One at a time, so two cannot fight over the same
  selection.
- **Without Accessibility.** A message explains what is missing.

## How the selection is read

Tinycast first asks the app for the selected text through Accessibility. Chrome, Electron apps and VS
Code get a nudge first, because they only share that once something asks.

If that gives nothing, Tinycast briefly copies the selection with <kbd>⌘</kbd><kbd>C</kbd>, reads it,
and puts your clipboard back. If nothing was selected, it says so instead of working on whatever you
copied last.

## Backups

**Nothing about Quick Actions travels in a [backup](/docs/reference/backup)**: not the switch, the
models, the Replace or Preview choices, custom prompts, the language, or your custom actions. An
import must never change what a shortcut does to your documents.
