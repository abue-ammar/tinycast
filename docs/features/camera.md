# Camera

One camera, two surfaces. `Open Camera` is a launcher command that puts a live preview on screen,
mirrors it, switches between the Mac's cameras and copies a photo to the clipboard. Calendar's
pre-meeting preview is the other, and it rides the same session, panel and stage — the join-specific
controller and footer are all that stay in [calendar.md](calendar.md).

## Invariants

- **Nothing runs until the command is run.** `CameraCoordinator` is `lazy` on `AppCore`, and
  `CameraSession.init` stores a `Purpose` and touches nothing else — no device, no discovery session,
  no TCC read. The camera permission prompt is raised by `start()`, from the gesture that asked for
  it, and never on launch.
- **The camera settles before the panel opens, and stops after it closes.** `start()` resolves access
  and blocks on `startRunning` first, then hands a settled `Feed` up — so the first frame is live
  video rather than a stage swapped out from under the user, and the TCC prompt never takes key from
  a panel already up. `stop()` runs from the fade-out's completion, so the camera light never
  outlives the panel but is never torn down under a visible one either.
- **Escape, click-away and the shot all end the same way.** Every route goes through
  `CameraCoordinator.close()`, which drops the panel and stops the session; `windowDidResignKey` is
  what covers clicking away. Taking a photo closes too — the command is done, so the camera goes out
  with it rather than idling for a second shot.
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
| `UI/CameraCoordinator.swift` | the standalone panel's lifecycle, mirror state, the clipboard write |
| `UI/CameraView.swift` | the standalone surface: stage over a footer of controls |
| `UI/CameraStage.swift` | the shared stage — the hosted preview layer, or why there is no video |
| `UI/CameraPanel.swift` | the shared borderless panel: ↵ and Esc, and cursor-screen centring |
| `UI/CameraButton.swift` | the shared capsule button both footers use |

`Purpose` is the session's one knob. `.preview` is the cheap one Calendar takes — a `.medium` preset
and no output. `.capture` raises the preset to `.photo` and adds an `AVCapturePhotoOutput`, which is
the whole cost of being able to take a photo, and it is paid only by the command that does.

`CameraCoordinator` is `@Observable` and the view reads it directly, so toggling Mirror re-renders
through Observation rather than through a hand-reassigned `rootView`. `mirrored` lives on the
coordinator rather than in `AppSettings`: it is remembered for the launch, and a display preference
that grants nothing is not worth a settings key or a line in a backup.

Switching cameras swaps the input inside one `beginConfiguration`/`commitConfiguration` while the
session keeps running, so the stage never blanks. `Switch Camera` only appears when
`hasMultipleDevices` says the discovery session found more than one.

## Where it is reachable from

The launcher, as `CommandID.openCamera` — so it takes aliases and a global shortcut like any other
command, and hides with the `Command` category. It has no Settings pane and no enable switch: there
is nothing to configure and nothing to leave running.
