# Contributing

Start with the [README](README.md) for requirements and music setup, then read the [architecture guide](docs/architecture.md) before changing playback or state handling.

## Workflow

Keep each change focused and reviewable. Branch from the current main branch; use `codex/<description>` for Codex-created branches. Coordinate changes to shared files such as `PlayerViewModel`, `ContentView`, and `PlayerBarView` when other work is in progress.

Describe the concrete problem, resulting behavior, and validation in the change description. Design future improvements from current requirements and code. There is no maintained implementation roadmap or proposal archive.

Keep queue decisions in `PlayQueue`, playback and recovery in the engine collaborators, and intent coordination in `PlayerViewModel`. Views should invoke the coordinator rather than control `AVPlayer` directly. Protocol changes must update the real engine and test mocks together. Changes to serialized state require explicit consideration of decoding existing files; default property values alone do not establish backward compatibility.

The project uses filesystem-synchronized app and test folders. New Swift files belong in the appropriate folder. Keep repository documentation outside the app folder and out of Copy Bundle Resources. Local music, asset catalogs, Xcode user preferences, and build output should not be committed.

## Running tests

The `AnimenzPlayerTests` target already exists. Select the `AnimenzPlayer` scheme and **My Mac** or a supported iOS Simulator, then press **⌘U** or choose **Product → Test**. Individual cases can be run from their gutter icons.

For a local command-line macOS run from the repository root:

```sh
xcodebuild -project AnimenzPlayer.xcodeproj \
  -scheme AnimenzPlayer -destination 'platform=macOS' test
```

Use full Xcode as the active developer directory. If your system selects Command Line Tools, set `DEVELOPER_DIR` to your Xcode app's `Contents/Developer` directory for the command. Physical-device builds require your own signing configuration.

Coverage includes queue and repeat semantics, coordinator intents, search and show derivation, scope behavior, sleep timers, recovery and cancellation, diagnostics retention/export, and player-state instrumentation. Most coordinator tests use `MockPlaybackEngine`; engine and instrumentation tests also exercise AVPlayer. Titles used by search fixtures are written directly into the test code and are drawn from [`music_list.txt`](AnimenzPlayer/music_list.txt). Tests do not require your personal music library.

Run the relevant existing suites for behavior changes and the complete suite for shared playback/state changes. Update assertions when intended behavior changes, and add regression coverage for substantive bug fixes. Prose-only edits need link and factual checks; resource or scheme changes also need a build and resource inspection.

## Manual checks

SwiftUI layout and system integration need runtime checks when affected:

- Search for `AOT`, select a result, and confirm skips remain in scope. Clear the query, then clear the scope chip and confirm the distinction.
- Search for a query with no results, then edit it back. The search field and filter picker should remain usable.
- Exercise the player bar, scrubber, and scope chip on macOS and an iOS destination. Check window chrome, safe-area placement, and hit-testing.
- Check shortcuts with the list and search field focused, and system media commands when those paths change.
- For background-audio changes, test on an iOS device with the screen locked. For macOS recovery changes, check pause cancellation and sleep/wake.
- For diagnostics changes, export through **Playback → Export Debug Log…**, including canceling the save dialog.

For build and setup problems, see [Troubleshooting](docs/troubleshooting.md).
