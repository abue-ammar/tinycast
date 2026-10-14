# Camera

One camera, two surfaces. `Open Camera` is a palette screen that shows a live preview inside the
launcher window, mirrors it, switches between the Mac's cameras and copies a photo to the clipboard.
Calendar's pre-meeting preview is the other, a borderless panel over the same session and stage — the
join-specific controller and footer are all that stay in [calendar.md](calendar.md).

## Invariants

- **Nothing runs until the command is run.** `CameraCoordinator` is `lazy` on `AppCore`, and
  `CameraSession.init` stores a `Purpose` and touches nothing else — no device, no discovery session,
  no TCC read. The camera permission prompt is raised from the gesture that asked for it, and never
  on launch.
- **The TCC prompt comes before the palette.** It takes key, which would dismiss a palette already
  up, so `show()` hides the palette, asks, and only then opens the camera screen.
- **The stage is full-bleed, and the keyboard stays with the search field.** `CameraView` ignores
  the safe area, so the header and footer float over the feed, and the hosted feed view refuses
  hit-testing, or it would swallow their clicks. `CameraScreen` sets `drawsSearchField` false
  rather than `hidesSearchField`: nothing else on the screen can hold focus, and ↵, Esc and ⌘K are
  `onKeyPress` handlers that need a focused view beneath them.
- **The palette never shows a black stage.** The screen opens at once on a warm-up, and
  `CameraView` dissolves it into the stage only once `start()` has blocked through `startRunning`
  and handed up a settled `Feed`. Reduce Motion makes that a cut.
- **The camera runs only while its screen is on screen.** `load()` runs from `onScreenOpening`, so a
  restored screen starts the camera again; `stop()` runs when the palette hides on the camera screen
  and when the mode leaves it. `stop()` drops the `AVCaptureSession`, so every open builds its own: a
  reused session with no output of its own — the preview's — restarts to a black stage. A start
  that settles after a stop turns its own session off, and its feed is dropped by `generation`.
- **The shot ends the command.** Taking a photo hides the palette — the camera goes out with it
  rather than idling for a second shot. Esc and click-away are the palette's own.
- **The join preview's panel owns its click-away.** `CameraPanel` reports losing key as the same
  `.cancel` as Esc, unless the window under the pointer sits at the Dock's level or above — the menu
  bar, what it drops down, the Dock — so reframing from Control Center keeps the feed live. The
  palette has no such exception, so a menu-bar click closes the Open Camera screen like any other.
- **The preview and the photo are mirrored together.** Mirroring is `isVideoMirrored` on a connection
  — the preview layer's, and the photo output's at capture time — never a `scaleEffect` on the view,
  which would hand back a photo that is not what the user framed.
- **A photo reaches the clipboard as PNG.** The camera's own encoding is decoded and re-encoded off
  main, because `ClipboardManager` records `.png` and `.tiff` and nothing else.
- **`AVCaptureSession` is not `Sendable`, and only `CaptureBox` crosses that line.** The blocking
  calls — `startRunning`, `stopRunning`, and the begin/commit around a device swap — run in
  `Task.detached` behind that one `@unchecked Sendable` box, which is private to `CameraSession.swift`.
  There is no second actor.

## How it is put together

| Piece | Holds |
| --- | --- |
| `Service/CameraSession.swift` | access, start/stop, device cycling, the photo, and the box |
| `UI/CameraCoordinator.swift` | the palette screen's camera lifecycle, mirror state, the clipboard write |
| `UI/CameraScreen.swift` | the `PaletteScreen`: ↵ takes the photo, ⌘K holds Mirror and Switch Camera |
| `UI/CameraView.swift` | the screen's body: the warm-up, then the stage |
| `UI/CameraStage.swift` | the shared stage — the hosted preview layer, or why there is no video |
| `UI/CameraPanel.swift` | the join preview's borderless panel: ↵, Esc, click-away, centring |
| `UI/CameraButton.swift` | the join preview footer's button: `ModalActionButtonStyle` plus a key cap |

`Purpose` is the session's one knob. `.preview` is the cheap one Calendar takes — a `.medium` preset
and no output. `.capture` raises the preset to `.photo` and adds an `AVCapturePhotoOutput`, which is
the whole cost of being able to take a photo, and it is paid only by the command that does.

`CameraCoordinator` is `@Observable` and the screen reads it directly, so toggling Mirror or the feed
settling re-renders through Observation. `mirrored` lives on the
coordinator rather than in `AppSettings`: it is remembered for the launch, and a display preference
that grants nothing is not worth a settings key or a line in a backup.

Switching cameras swaps the input inside one `beginConfiguration`/`commitConfiguration` while the
session keeps running, so the stage never blanks. The next open starts on the camera switched to,
unless it has been unplugged since. `Switch Camera` only appears in ⌘K when
`hasMultipleDevices` says the discovery session found more than one.

## Where it is reachable from

The launcher, as `CommandID.openCamera`, which opens `PaletteMode.camera` — so it takes aliases and a
global shortcut like any other command, and hides with the `Command` category. It has no Settings pane and no enable switch: there
is nothing to configure and nothing to leave running.
