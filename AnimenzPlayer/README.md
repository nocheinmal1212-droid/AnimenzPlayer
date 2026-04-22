# Animenz Player

A minimal, cross-platform (iOS / macOS) SwiftUI music player for a local library of piano-cover audio files produced by [`yt-dlp`](https://github.com/yt-dlp/yt-dlp). The app scans a bundled `Music/` folder, parses track numbers and titles from `yt-dlp`'s default filename template, surfaces sidecar or embedded artwork, and plays tracks back with shuffle, seek, and continuous-play support.

This repository currently reflects the **Wave 1** state of the improvement roadmap: a foundational refactor that splits the old monolithic view model into testable collaborators, replaces `AVAudioPlayer` with `AVPlayer`, introduces disk persistence for last-played state, and fixes several smaller issues around artwork caching, search, and error surfacing.

---

## Table of contents

1. [Requirements](#requirements)
2. [Project layout](#project-layout)
3. [Architecture](#architecture)
4. [Building and running](#building-and-running)
5. [Adding music](#adding-music)
6. [Testing](#testing)
7. [Troubleshooting](#troubleshooting)
8. [Roadmap](#roadmap)

---

## Requirements

| Component     | Minimum                                    |
| ------------- | ------------------------------------------ |
| Xcode         | 15.0                                       |
| Swift         | 5.9                                        |
| iOS target    | 16.0                                       |
| macOS target  | 13.0                                       |
| Dependencies  | None (first-party frameworks only)         |

The project relies on `AVFoundation`'s async metadata API (`AVAsset.load(.commonMetadata)`) and `NavigationStack`, both of which set the deployment floor at iOS 16 / macOS 13.

---

## Project layout

```
AnimenzPlayer/                       Xcode project root
├── AnimenzPlayer/                   Main app target
│   ├── App/
│   │   └── AnimenzPlayerApp.swift        @main entry point
│   ├── Models/
│   │   ├── Track.swift                   Track value type
│   │   └── PlayerError.swift             Typed user-facing errors
│   ├── Services/
│   │   ├── PlaybackEngine.swift          Protocol + AVPlayer implementation
│   │   ├── PlayQueue.swift               Pure value-type queue
│   │   ├── LibraryStore.swift            Track discovery
│   │   ├── PersistenceStore.swift        Debounced JSON state store
│   │   └── ArtworkCache.swift            ImageIO downsampling + NSCache
│   ├── ViewModels/
│   │   └── PlayerViewModel.swift         Thin coordinator (@MainActor)
│   ├── Views/
│   │   ├── ContentView.swift             Root
│   │   ├── TrackListView.swift           List with search
│   │   ├── PlayerBarView.swift           Bottom player
│   │   ├── ArtworkView.swift             Cross-platform artwork view
│   │   └── ErrorBanner.swift             Non-blocking error UI
│   └── Music/                            (Folder reference — see Adding music)
│
└── AnimenzPlayerTests/              Test target
    ├── Mocks.swift                       MockPlaybackEngine + fixtures
    ├── PlayQueueTests.swift              Queue logic
    └── PlayerViewModelTests.swift        Coordinator logic
```

In Xcode, the subfolders under `AnimenzPlayer/` correspond 1:1 to Groups in the Project Navigator. If you're on Xcode 15+ with a new project, groups synchronize with folders on disk automatically; on older / customized projects you may need to create the groups manually and drag files in.

---

## Architecture

The app follows a thin coordinator pattern. `PlayerViewModel` is the only object the SwiftUI views observe; it delegates every concern to a collaborator behind a narrow interface.

```
                   ┌─────────────────────────────┐
                   │         SwiftUI Views       │
                   │  ContentView / PlayerBar /  │
                   │  TrackListView / …          │
                   └──────────────┬──────────────┘
                                  │ @EnvironmentObject
                   ┌──────────────▼──────────────┐
                   │      PlayerViewModel        │
                   │  (@MainActor coordinator)   │
                   └──┬──────────┬──────────┬────┘
                      │          │          │
        ┌─────────────▼──┐  ┌────▼────┐  ┌──▼──────────────┐
        │ LibraryStore   │  │PlayQueue│  │ PlaybackEngine  │
        │ (tracks)       │  │(value)  │  │ (protocol)      │
        └────────────────┘  └─────────┘  └──┬──────────────┘
                                            │
                                   ┌────────▼─────────┐
                                   │  AVPlayerEngine  │  ← real impl
                                   │  MockPlayback…   │  ← tests
                                   └──────────────────┘

                   ┌─────────────────────────────┐
                   │      PersistenceStore       │ ← last-played, shuffle
                   │  (JSON, debounced writes)   │
                   └─────────────────────────────┘
```

### Collaborator responsibilities

| Collaborator       | Owns                                            | Does not own                  |
| ------------------ | ----------------------------------------------- | ----------------------------- |
| `LibraryStore`     | Scanning the bundle, filtering by extension     | Playback, persistence         |
| `PlayQueue`        | Ordered indices, current position, shuffle      | Audio, side effects           |
| `PlaybackEngine`   | Audio decoding, time observation, seek          | Queue logic, library          |
| `PersistenceStore` | JSON read/write, debouncing                     | Any domain knowledge          |
| `PlayerViewModel`  | Wiring + `@Published` state for SwiftUI         | Anything above                |

### Design decisions worth knowing

- **`PlaybackEngine` is a protocol.** The real implementation (`AVPlayerEngine`) uses `AVPlayer.addPeriodicTimeObserver` for progress and KVO on `timeControlStatus` for play/pause state — both more reliable than the old `Timer` loop against `AVAudioPlayer`. In tests, `MockPlaybackEngine` implements the same protocol without touching audio, so queue and coordinator logic can be exercised in microseconds.

- **`PlayQueue` is a struct.** Shuffle works by permuting a separate `orderedIndices` array, not the tracks themselves — this keeps the source order intact and makes unshuffle a reversible operation.

- **`PersistenceStore` debounces.** Scrubbing or auto-progress would otherwise hammer the disk; writes are batched at 500 ms. On `scenePhase` transitions the view model calls `flushPendingState()` so nothing is lost if the app is suspended.

- **`ArtworkCache` is byte-cost-limited.** `NSCache.totalCostLimit = 64 MB`. Images are keyed by `(url, size)`, so the list thumbnail (≤160 px) and the player-bar artwork (≤600 px) are cached independently; full-resolution decoding never happens for the 44 pt rows.

- **The view model is `@MainActor`.** Every `@Published` mutation happens on the main thread, and async engine work hops back via `MainActor.run` or `[weak self]` + a main-thread callback. This removes a whole category of SwiftUI "publishing changes from background threads" warnings.

---

## Building and running

1. Open `AnimenzPlayer.xcodeproj` in Xcode.
2. Select the `AnimenzPlayer` scheme.
3. Pick an iOS Simulator or "My Mac" as the run destination.
4. ⌘R.

The first launch will show the empty state until you add music (next section).

---

## Adding music

The app looks for audio in two places, in order:

1. A bundled folder reference named **`Music`** at the root of the app bundle.
2. The bundle root itself, as a fallback.

Recognized extensions: `m4a`, `mp3`, `aac`, `wav`, `flac`, `aiff`, `caf`.

### Recommended: folder reference

1. In Finder, create a folder named `Music` next to the `.xcodeproj`.
2. Drop your audio files in. Filenames produced by `yt-dlp` with `--output '%(playlist_index)03d - %(title)s [%(id)s].%(ext)s'` are parsed automatically — the leading `NNN - ` becomes the track number and the trailing `[videoid]` tag is stripped for display.
3. Sidecar JPEG/PNG/WebP thumbnails with the same base filename (as produced by `--write-thumbnail`) are picked up automatically for artwork.
4. In Xcode, drag the `Music` folder into the Project Navigator. When prompted, choose **"Create folder references"** (blue folder icon), not "Create groups" — a folder reference preserves the runtime directory structure inside the bundle.
5. Confirm the `Music` folder is checked for the `AnimenzPlayer` target membership.

If no `Music` folder reference exists, the app will scan the bundle root, which is useful for quick experiments with a few files added directly to the target.

---

## Testing

### One-time test target setup

If the project was opened fresh without a test target, add one:

1. **File → New → Target…**
2. Select **Unit Testing Bundle**. Under **Testing System** pick **XCTest**.
3. Product Name: `AnimenzPlayerTests`. Target to be Tested: `AnimenzPlayer`.
4. Click **Finish**.
5. Delete the boilerplate `AnimenzPlayerTests.swift` that Xcode generates.
6. Drag the three files from `AnimenzPlayerTests/` in this repo into the test target's group.

### Verifying target membership

This is the single most common source of build errors for newly added test files. For **each** file under `AnimenzPlayerTests/`:

1. Select the file in the Project Navigator.
2. Open the **File Inspector** (right sidebar, first tab, ⌥⌘1).
3. Scroll to **Target Membership**.
4. Confirm that **only `AnimenzPlayerTests` is checked**. `AnimenzPlayer` (the app target) **must be unchecked**.

If the app target is checked, the compiler tries to build test files into the main app, which has no `XCTest` dependency — producing the `Unable to find module dependency: 'XCTest'` error.

### Running tests

- ⌘U, or Product → Test.
- Individual tests can be run from the diamond gutter icons.

The suite is designed to be fast — all tests complete in well under a second because no real audio decoding happens.

---

## Troubleshooting

### `Unable to find module dependency: 'XCTest'`

Target membership. See [Verifying target membership](#verifying-target-membership) above. Every file that imports `XCTest` must be a member of a test target and **not** the app target.

If target membership is correct and the error persists, also verify on the test target:

- **Build Phases → Link Binary With Libraries**: `XCTest.framework` should be listed. If it is not, click **+**, search for `XCTest`, and add it.
- **Build Settings → Bundle Loader**: should be `$(TEST_HOST)`.
- **Build Settings → Test Host**: should be `$(BUILT_PRODUCTS_DIR)/AnimenzPlayer.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/AnimenzPlayer` (or the iOS equivalent).

These are set automatically when Xcode creates the test target via File → New → Target. They only need manual inspection if the target was added or edited by hand.

### `@testable import AnimenzPlayer` doesn't resolve

- Make sure the main app target's **Build Settings → Enable Testability** is `YES` for the Debug configuration (the default).
- Clean build folder (⇧⌘K) and rebuild.

### No tracks show up at launch

- Confirm the `Music` folder was added as a **folder reference** (blue icon), not a group (yellow icon). Groups don't put the folder into the built app bundle.
- Confirm the `Music` folder has target membership for `AnimenzPlayer`.
- Check the console for `Failed to play …` logs — unsupported formats are silently filtered by extension, so a typo in the extension would just mean zero matches.

### Last-played position isn't restored

- The state file lives at `~/Library/Application Support/<bundle-id>/player-state.json` on macOS, or the sandbox equivalent on iOS. Deleting it is harmless and resets state.
- On iOS, make sure the app has a chance to reach `scenePhase == .background` before it's killed — the persistence flush happens there.

---

## Roadmap

Wave 1 (done) established the architectural foundation. Waves 2–4 are tracked in `PLAN.md` (or the chat history this was developed in) and cover:

- **Wave 2:** `MPNowPlayingInfoCenter` / remote controls, background audio, repeat modes, sleep timer, favorites, macOS keyboard shortcuts.
- **Wave 3:** Show/album grouping derived from track titles, user playlists, smart playlists, sidebar navigation.
- **Wave 4:** Expandable full-screen player with matched-geometry artwork transitions, waveform scrubber, ambient animation.

Contributions targeting those features are welcome; please keep the architectural boundaries intact — the collaborators should stay individually testable.

## Contributing

See [`BRANCHING.md`](./BRANCHING.md) for the branch model, parallelization rules, file ownership map, and rules for running multiple streams of work concurrently (including multiple AI-assistant sessions). Read it **before** opening a second stream of work — the chokepoint rules in that doc are what make parallel wave development tractable.
