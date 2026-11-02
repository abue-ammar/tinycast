---
title: Dictation
description: Turn speech into text with a model on your Mac, and paste it where you were typing.
---

Dictation records your voice while you hold or press a shortcut, turns it into text on your Mac,
and pastes the text where you were typing.

Turn it on in **Settings → Dictation → Enable Dictation**. It's **off** by default. When you turn
it on, Tinycast explains what it needs, then macOS asks for microphone access.

Two more steps before your first dictation, both in the same pane:

1. Under **Model**, click **Download**. No model comes with Tinycast.
2. Under **Commands**, record a **Shortcut**. Dictation has none until you do.

## Dictating

**Shortcut behavior** decides how the shortcut works:

| Shortcut behavior                    | To start           | To finish                                  |
| ------------------------------------ | ------------------ | ------------------------------------------ |
| **Press to start or stop** (default) | Press the shortcut | Press it again, or press <kbd>return</kbd> |
| **Hold to talk**                     | Hold the shortcut  | Release it, or press <kbd>return</kbd>     |

Press <kbd>esc</kbd> to cancel. The recording is discarded.

**Hold to talk** works with a key combination or a single modifier key, like Right <kbd>⌥</kbd>
or <kbd>🌐</kbd>. A single modifier starts recording after you hold it alone for 250 ms. While you
hold it, pressing another key or clicking cancels the recording. Double-tap shortcuts only work with
**Press to start or stop**.

You can also use the 🎤 key on your keyboard as the shortcut. See
[Hotkeys](/docs/reference/hotkeys).

While Tinycast listens, a small capsule near the bottom of the screen shows bars that move with your
voice. While it transcribes, a wave runs across the capsule. A recording stops by itself after
**5 minutes** and is transcribed as usual.

Tinycast records from the **System default** microphone unless you choose another under
**Microphone**.

**Play sounds** (on by default) plays the macOS dictation sounds when recording starts and stops.
Cancelling is silent.

While you record, Tinycast turns your Mac's output volume down to a tenth, and turns it back up
when you finish or cancel. If you change the volume yourself in the meantime, Tinycast leaves it as
you set it.

## Where the text goes

**When finished**, in **Settings → Dictation → Output**, picks the destination:

| When finished                     | Does                                                |
| --------------------------------- | --------------------------------------------------- |
| **Paste in active app** (default) | Pastes into the app you were typing in              |
| **Copy to clipboard**             | Copies the text and pastes nothing                  |
| **Paste and copy**                | Pastes the text and also leaves it on the clipboard |

When it pastes, Tinycast reads the text around the cursor and adds a space before or after the
dictation where one is needed. **Adapt capitalization** (on by default) capitalizes the first
letter at the start of a field, paragraph or sentence, and lowercases it in the middle of a
sentence. If an app doesn't share the text around its cursor, the text goes in as the model wrote
it.

**Insert while recording** is **off** by default. Turn it on to paste the text in pieces while you
speak: at each pause, or after 8 seconds of speech without one. Text already pasted stays, even
if you cancel, and isn't corrected later. It has no effect with **Copy to clipboard**.

Password fields and other protected fields can refuse the paste.

## Models

Choose an **Engine**, then a **Model**. Models download from Hugging Face. After that, transcription
runs entirely on your Mac.

| Engine   | Model           | Notes                            | Languages                            | On disk       |
| -------- | --------------- | -------------------------------- | ------------------------------------ | ------------- |
| Parakeet | Redux (default) | Lightweight and efficient        | 25 languages                         | About 220 MB  |
| Parakeet | Ultra           | Higher accuracy, larger download | 25 languages                         | About 632 MB  |
| Qwen     | 0.6B            | Smaller and faster               | 30 languages and 22 Chinese dialects | About 940 MB  |
| Qwen     | 1.7B            | Higher accuracy, more memory     | 30 languages and 22 Chinese dialects | About 2.35 GB |

Parakeet is faster and uses less memory. Qwen covers more languages but is slower.

A download shows its progress and a **Cancel** button. If you switch to another model, the download
keeps going. **Remove** deletes an installed model.

With a Qwen model installed, a **Language** picker appears. **Auto** lets the model detect the
language. Parakeet has no language setting.

### Memory

The model runs in a separate process, **Tinycast Dictation**, which you can see in Activity Monitor.
**Release model from memory** quits it after the time you choose: **1 minute** by default, up to
1 hour, or **Never**. A released model takes a moment longer to load the next time you dictate.

## In AI Chat

While Dictation is on, the [AI Chat](/docs/ai) message field has a microphone button. Click it to
start, and click it again to stop and insert the text. It always inserts into the message, whatever
**When finished** says, and the shortcut mode doesn't apply. If no model is installed, clicking it
opens Settings → Dictation.

## Privacy and permissions

Audio stays in memory. It's never saved to disk or sent over the network.

- **Microphone.** Asked when you turn Dictation on. If it isn't granted, the pane shows
  **Microphone access required** with a button to grant it or open System Settings.
  **Settings → Permissions** shows it too.
- **Accessibility.** Needed to paste into other apps and read the text around the cursor. Tinycast
  asks for it when you turn Dictation on. **Copy to clipboard** works without it.

Dictation's settings and shortcut aren't included in [backups](/docs/reference/backup), so an
import can't turn on the microphone.

## Messages you might see

| Message                                                   | Meaning                                                                          |
| --------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Download the dictation model in Settings first            | The selected model isn't installed                                               |
| No speech was recorded                                    | The recording was empty or too short                                             |
| Couldn't paste dictation into this app                    | The app refused the paste. With **Paste and copy**, the text is on the clipboard |
| Couldn't paste some dictation into this app               | With **Insert while recording**, one of the pieces didn't paste                  |
| Hold to talk needs a key combination or a single modifier | **Hold to talk** is selected, but the shortcut is a double tap                   |
| Allow Tinycast to use the microphone in System Settings   | Microphone access is off                                                         |
