# 06 — Camera and Dictation capture isolation

Status: proposed. [Audit index](README.md). Read [camera](../features/camera.md) and
[Dictation](../features/dictation.md) invariants. Hardware checks are required before these land.

## Findings

| ID | Confirmed pattern | Priority | Difficulty | Risk |
| --- | --- | --- | --- | --- |
| C01 | [CameraSession](../../Tinycast/Features/Camera/Service/CameraSession.swift#L38) passes one non-Sendable capture session into independent detached start/stop/configuration jobs | P1 | High | High |
| C02 | [PhotoCapture](../../Tinycast/Features/Camera/Service/CameraSession.swift#L131) mutates one continuation from MainActor and an AVFoundation delegate callback using `@unchecked Sendable` | P1 | Medium | High |
| C03 | [DictationCapture](../../Tinycast/Features/Dictation/Service/DictationCapture.swift#L99) has an unchecked session box and an unchecked queue-confined audio collector | P2 | Medium | High |

The boxes silence checks rather than proving operation ordering. That does not establish an existing
data race. MainActor methods can interleave while awaiting detached work; camera switching and photos
are launched by unowned action tasks, and stop is detached without a completion the owner can await.
Those are concrete openings to inspect and test.

## C01 — One session-operation boundary

Extend CameraSession, its coordinator and its existing operation ownership. Keep long-lived ownership
under AppCore; do not add a global camera singleton or a second actor.

1. Establish one serialized off-main boundary for capture-session operations that can block. Confine
   configuration, device changes, start and stop to that boundary. Keep preview hosting and UI state on
   MainActor, exposing only the references AppKit/AVFoundation actually require there.
2. Retain and await the current operation where ordering requires completion. Reject or serialize
   repeated device switches and capture requests based on existing UI behavior. `@concurrent` alone
   does not serialize capture access or provide a dedicated blocking executor.
3. Carry a session generation back to MainActor. Only the current session can publish its device,
   feed or photo. Closing/reopening during an old operation must not change the new panel.
4. Make stop completion observable to the owner while preserving fade behavior: begin teardown after
   the closing surface's fade, and prevent reopening from racing that stop. A generation check and
   one owned operation chain are preferable to scattered boolean flags.
5. Update the camera feature document, which currently describes detached boxes as its invariant,
   in the same implementation commit. Keep a minimal narrow unchecked SDK bridge only where the
   compiler cannot represent the established confinement.

Preserve lazy permission requests, a settled feed before presentation, fresh sessions on reopening,
Continuity/external-camera discovery, nonactivating panels, Control Center behavior, mirroring, PNG
conversion off-main and the selected device. This is an isolation change, not a capture redesign.

## C02 — Exactly-once photo completion

The delegate stores a continuation on main, resumes it on AVFoundation's callback and clears it there.
There is no cancellation completion path. Keep the continuation in one synchronized completion state
or one verified isolated callback domain; `Mutex` is a candidate for the short state transition.
Take the continuation once, release protection, then resume it. Do not pass the photo reference to an
unrelated task: derive the needed data within its valid SDK boundary.

Specify what happens when the photo request is cancelled, the panel closes, the device disconnects,
or the session stops before callback. Retain the delegate for the SDK's required callback lifetime,
even if the awaiting UI operation has ended. Ignore later callbacks after a completion has been taken.
Scope cleanup to the request generation so finishing an old request cannot clear a newer delegate.

This is a callback bridge that still needs a delegate on current AVFoundation; wrapping it in async
is valid. The gap is shared mutable completion state and lifetime, not the existence of a delegate.

## C03 — Dictation boundary

AudioCollector already confines mutable sample data to its serial delegate queue and uses `queue.sync`
for `finish()`. Preserve that efficient arrangement. Do not spawn one task per sample buffer, move
the spectrum computation to MainActor, or copy entire recordings on every callback.

Verify shutdown ordering: stop capture, detach the delegate, finish/drain on the delegate queue, then
release the collector. Document and check that `finish()` is not invoked from its own queue. Carry a
recording/session identity with queued level/limit delivery so callbacks from an ended capture cannot
update a new one. Inspect the coordinator's existing generation rules before adding state.

Align capture-session start/stop confinement with the same narrow principle as C01, without forcing
camera preview and Dictation into one new abstraction. Their platform needs differ.

## Validation and completion

Run `dictation-test`, `dictation-field-test`, `dictation-volume-test`, `dictation-worker-test`,
`calendar-test` and the complete suite/build. Add deterministic overlap/completion tests for the
changed owner boundary; policy tests alone do not validate AVFoundation.

On hardware, test permission grant/denial, repeated open/close, switch-switch-close, photo-photo-close,
photo cancellation, disconnect, Continuity Camera, calendar preview, mirroring and reopening while a
fade/stop is in flight. Dictation needs rapid start/cancel/start, input switching, long recording and
queued meter/limit callbacks. Run Thread Sanitizer where supported and inspect repeated-cycle memory,
CPU and camera/microphone release. Coordinate interactive automation with the user.

Done when session mutations cannot overlap unpredictably, every photo request completes once,
late capture callbacks are rejected, and UI latency/device-release behavior is preserved. Roll back
Camera and Dictation separately if the hardware checks fail.
