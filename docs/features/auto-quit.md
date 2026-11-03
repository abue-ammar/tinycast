# Auto Quit

Closes apps the user opted in, a few minutes after they leave the foreground. Nothing quits until it
is on the list. The clock, the holds and the exclusions live in `AutoQuitSchedule`; `AutoQuitMonitor`
arms it from workspace notifications and `AutoQuitActivity` reports a recording or Music/Spotify
playback.

## Invariants

- **Opt-in, per app.** A rule is a bundle ID plus an optional duration. Nil follows
  `autoQuitMinutes`, so changing the default retimes every app still on Default and leaves an
  override where it is. The choices are 1, 3, 5, 10 and 15 minutes, and 3 is the default.
- **Finder and Tinycast never quit.** A rule that names either is dropped. The action panel does not
  offer them.
- **The clock starts when the app is in the background.** A regular app that is already there starts
  when the rule is added. Becoming frontmost clears it, and leaving starts it again. An accessory or
  menu-bar app is not armed just because it is running: only a deactivate does, which is why those
  apps usually never quit.
- **A hold restarts the interval rather than spending it.** A microphone or camera in use pauses
  every clock. Music (`com.apple.Music`) and Spotify (`com.spotify.client`) are held while they
  produce audio. When the hold ends, that clock starts over. Screen capture with neither a camera
  nor a microphone is not detected: listing screen-capture devices asks for screen-recording
  permission, so they are suppressed.
- **Quit is `terminate()`.** A save sheet can refuse it, and the interval then starts over. Force
  quit is never used.
- **The running dot turns orange** while an opted-in app is running. A plain dot still means only
  that the app is running.

## Where it is set

**Enable Auto Quit** and **Disable Auto Quit** are on an application's ⌘K menu, whether or not it is
running. Settings → Applications → Auto Quit edits the default duration and each app's own. An app
on the default shows that duration beside the word Default.

`applications.autoQuitMinutes` and `applications.autoQuit` mirror the two preferences.
`applications.autoQuit` is a list of `{ "bundleID", "minutes" }`, and `minutes: null` follows the
default. One unusable entry rejects the list.
