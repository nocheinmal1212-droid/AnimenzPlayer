# Troubleshooting

See the [README](../README.md) for normal setup and [Contributing](../CONTRIBUTING.md#running-tests) for running the existing test target.

## macOS: playback recovery and sleep

Playback failures, including failed-to-finish notifications whose item status stays
“ready,” trigger bounded recovery while playback is still requested. There are
at most three attempts per Play request or track, with 1-, 2-, and 4-second delays
and an 8-second progress timeout for each attempt. The first attempt reuses a ready
player; subsequent attempts rebuild the player and restore the track position.
Actual media-time advancement confirms recovery. Exhaustion stops retrying and
shows the playback error; pressing Play starts a fresh attempt budget.

System sleep suspends playback and retries. Waking resumes recovery only when
playback is still requested. Pause (including media controls and sleep-timer
expiration), Stop, or selecting another track invalidates pending retries and seek
completions. A pending track load cannot override a later Pause. The Pause control
remains available during recovery.

A paired macOS activity assertion prevents idle system sleep while playing or
attempting recovery. It is released on pause, system sleep, retry backoff, exhaustion,
and teardown. Display sleep and explicit system sleep remain available. Recovery
and assertion changes are included in exported diagnostics.

## macOS: export playback diagnostics

The macOS app records playback diagnostics automatically in both Debug and Release builds.
If playback starts pausing or restarting unexpectedly, note the approximate time and choose
**Playback → Export Debug Log…**. Save the text file and include it with the bug report.
You can restart the app first if necessary: export includes retained events from earlier launches.
Canceling the save panel leaves the logs untouched, and exporting does not stop playback.

The log records interface/menu/media-control commands, automatic queue advancement,
sleep-timer actions, load and seek requests, actual player state, waiting reasons,
playback errors, macOS sleep/wake, and default audio-output changes. A small status
sample runs every 15 seconds while playback is requested; it reports lack of progress
without trying to restart audio. Timestamps, process-uptime values, session IDs, and
request IDs make it possible to distinguish app commands from player state changes.

Logs stay on the device in the app's Application Support directory under
`<bundle-id>/PlaybackDiagnostics/`. A sandboxed build normally places this inside
`~/Library/Containers/<bundle-id>/Data/Library/Application Support/`.
Three rotating files retain up to approximately 6 MiB total; oldest events are replaced
when the limit is reached. Disk writes run on a utility queue, with a bounded pending
event count. Export reports write failures, and subsequent accepted events report
any events dropped during a logging backlog. Logging continues after export.

Exports contain hashed track filenames, not track titles, full file paths, artwork,
or audio. Error logging keeps domains/codes rather than raw error descriptions.
Nothing is uploaded automatically. The instrumentation is passive and does not
change playback or implement automatic recovery.

## No tracks at launch

The local music library is excluded from Git. Add files under `AnimenzPlayer/Music/`, ensure target membership, and rebuild. The text catalog `music_list.txt` does not supply audio to the app.

Inspect the built app's resources: on macOS, open the built `.app` with **Show Package Contents** and look under `Contents/Resources`; on iOS, inspect the built app bundle. The audio must be either directly inside a bundled `Music` directory or directly at the resource root. The scanner does not recurse into nested folders. Ensure file extensions are supported; see [Adding music](../README.md#adding-music).

## Missing asset catalog

`AnimenzPlayer/Assets.xcassets/` is also excluded from Git. If Xcode reports missing AppIcon or AccentColor assets, create a local catalog in that location with the corresponding sets. Keep personal assets out of the cleanup change.

## iOS background audio

The checked-in `AnimenzPlayer/Info.plist` already contains `UIBackgroundModes = [audio]`, and the project uses that plist. If background playback fails after changing project settings, verify the built plist and the target's **Audio, AirPlay, and Picture in Picture** background mode. The engine configures `.playback` on the iOS audio session.

## XCTest build errors

For `Unable to find module dependency: 'XCTest'`, confirm test files belong only to `AnimenzPlayerTests`, not the app target. The checked-in test target already configures its Test Host and Bundle Loader; avoid creating a second target.

For an unresolved `@testable import AnimenzPlayer`, verify Debug **Enable Testability**, then clean the build folder and rebuild.

If `xcodebuild` reports that the active developer directory is Command Line Tools, use full Xcode. A per-command `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` override works when Xcode is installed at that path.

## Search and scope

Alias matching depends on each track's derived show. If `AOT` does not find a track, check its parsed title and the known names in `ShowCatalog`; literal title substring search remains available. Aliases inside multi-word queries are not expanded.

The scope chip resolves aliases through `ShowCatalog`. Queries that are not recognized aliases appear as quoted raw text. Clearing the search field intentionally leaves the scope unchanged; press X on the scope chip to return playback to the full library.

Ambient artwork follows the active search scope and its `themedBackgroundsEnabled` UserDefaults preference. Editing the similarly named JSON state field does not control the view.

## Saved position or preferences are lost

State lives at Application Support / `<bundle-id>` / `player-state.json`, using the sandboxed container where applicable. On macOS a sandboxed build normally uses `~/Library/Containers/<bundle-id>/Data/Library/Application Support/` as its base.

Inactive/background scene transitions flush saved state. A forced termination can lose recent progress. Invalid or incompatible JSON falls back to default state. Removing the file resets saved playback, favorites, history, repeat, and scope; copy it first if investigating a decoding problem.
