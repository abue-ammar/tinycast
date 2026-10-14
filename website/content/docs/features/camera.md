---
title: Camera
description: A quick camera check from the launcher, with mirroring and photos copied to the clipboard.
---

**Open Camera** shows a live camera preview right inside the launcher window. Use it to check how you
look before a call, flip the image, switch cameras, or take a photo and copy it to your clipboard.

There's nothing to turn on or set up. The command is in **Settings → Commands**, where you can give
it a global shortcut and an alias.

## Using it

| Action                         | Does                                                               |
| ------------------------------ | ------------------------------------------------------------------ |
| Take Photo <kbd>↵</kbd>        | Copies a photo to the clipboard as a PNG, then closes              |
| Mirror (<kbd>⌘K</kbd>)         | Flips the preview and the photo together                           |
| Switch Camera (<kbd>⌘K</kbd>)  | Switches to your next camera; only shown if you have more than one |

While the camera starts, the window shows **Starting camera…** and then fades into the live
preview. <kbd>esc</kbd> goes back, and closing the launcher turns the camera off.

Mirroring flips the photo as well as the preview, so the photo always matches what you saw. Tinycast
remembers your Mirror setting until you quit.

Photos appear in your [clipboard history](/docs/features/clipboard) like any other image.

## Privacy

- The camera isn't used until you run the command. The first time, macOS asks for camera access.
- The camera turns off as soon as the preview closes, so the green light never stays on.
- Taking a photo also closes the preview, so the camera doesn't stay on waiting for another shot.

The [Calendar](/docs/features/calendar#camera-preview) feature shows the same preview in its own
window before a meeting.
