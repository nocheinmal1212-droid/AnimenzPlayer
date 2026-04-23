# Animenz Player

A minimal, cross-platform (iOS / macOS) SwiftUI music player for a local library of piano-cover audio files produced by yt-dlp. The app scans a bundled Music/ folder, parses track numbers and titles from yt-dlp's default filename template, surfaces sidecar or embedded artwork, and plays tracks back with shuffle, repeat, sleep-timer, and continuous-play support. Lock Screen, Control Center, media keys, and AirPods gestures all work on day one through MPNowPlayingInfoCenter.
The browsing model is search-first rather than album-based. The search box understands acronyms and aliases — typing AOT surfaces every Attack on Titan track, JJK every Jujutsu Kaisen track, and first-letter acronyms reach shows outside the curated table. Playing a track from a search captures those results as the active play queue, so shuffle, next, and previous cycle within the searched scope until the scope is explicitly cleared — the search box and the scope are independent, letting you keep listening to one show while browsing for another. When the scope resolves to a known show, the window picks up a subtle blurred backdrop derived from that show's artwork.
Planned for upcoming waves: an expandable full-screen player with matched-geometry artwork transitions and a waveform scrubber (Wave 4), plus audio enhancements via on-device ML (denoising, timbre transfer, upmix) and MIDI support for driving / being driven by external devices and for exporting the piano covers' transcribed notes.

---

## Table of contents

1. [Requirements](#requirements)
2. [Features](#features)
3. [Project layout](#project-layout)
4. [Architecture](#architecture)
5. [Building and running](#building-and-running)
6. [iOS: enabling background audio](#ios-enabling-background-audio)
7. [Adding music](#adding-music)
8. [Searching and scoped playback](#searching-and-scoped-playback)
9. [Keyboard shortcuts (macOS)](#keyboard-shortcuts-macos)
10. [Testing](#testing)
11. [Troubleshooting](#troubleshooting)
12. [Roadmap](#roadmap)
13. [Contributing](#contributing)

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

## Features

**Core playback** (Wave 1):
- Bundled-library scanning with `yt-dlp` filename conventions.
- Shuffle, seek, continuous play across tracks.
- Sidecar and embedded-metadata artwork, cached and downsampled.
- Last-played track and position restored across launches.

**Platform & UX** (Wave 2):
- **Now Playing integration** — lock screen, Control Center, Apple Watch, AirPods double-tap, macOS media keys all work via `MPRemoteCommandCenter`.
- **Repeat modes** — off / all / one, cycled from the player bar (off → all → one → off). Persisted.
- **Favorites** — tap the heart on any track or in the player bar. Filter the list to favorites-only from the nav bar.
- **Recently Played** — last 50 tracks, newest first, deduplicated. Filterable from the nav bar.
- **Sleep timer** — 5 / 15 / 30 / 60 min, or "until end of current track". Sleep-timer expiration beats repeat mode: if you set end-of-track, the app stops even when repeat all is on.
- **Interruption handling** (iOS) — pauses on phone calls and Siri, auto-resumes when the system signals `shouldResume`.
- **macOS keyboard shortcuts** — see [Keyboard shortcuts](#keyboard-shortcuts-macos) below.
- **Light haptics** (iOS) — selection ticks on track tap, soft impacts on skip.

**Search-first browsing** (Wave 3):
- **Alias- and acronym-aware search** — typing `AOT`, `JJK`, `SAO`, `BNHA`, `CSM` etc. matches the corresponding show's tracks, not just the literal string. Shows not in the curated alias table are still reachable via first-letter acronym matching (e.g. `MHA` → My Hero Academia).
- **Scoped playback** — playing a track from a search captures the result set as the play queue. Next / previous / shuffle / repeat all cycle within that scope. A chip above the player bar labels the current scope (**Playing from: Attack on Titan**).
- **Independent search and scope** — clearing the search box does *not* reset scope. The user can browse elsewhere while their searched selection keeps playing. Only the X on the scope chip breaks out.
- **Themed ambient background** — when the search resolves to a known show, the window gets a subtle blurred backdrop derived from that show's artwork. Gated by an `@AppStorage("themedBackgroundsEnabled")` flag, defaulting to on.
- **Scope persistence** — the active search query is saved across launches. On relaunch the query is re-ranked against the current library (so it's self-healing if files have moved).

---

## Project layout

```
AnimenzPlayer/                       Xcode project root
├── AnimenzPlayer/                   Main app target
│   ├── App/
│   │   └── AnimenzPlayerApp.swift        @main entry point + macOS commands
│   ├── Models/
│   │   ├── Track.swift                   Track value type (+ `show`, Wave 3)
│   │   ├── PlayerError.swift             Typed user-facing errors
│   │   ├── RepeatMode.swift              off / all / one (Wave 2)
│   │   └── PlaybackScope.swift           all / favorites / recent / search (Wave 3)
│   ├── Services/
│   │   ├── PlaybackEngine.swift          Protocol + AVPlayer implementation
│   │   ├── PlayQueue.swift               Pure value-type queue
│   │   ├── LibraryStore.swift            Track discovery
│   │   ├── PersistenceStore.swift        Debounced JSON state store
│   │   ├── ArtworkCache.swift            ImageIO downsampling + NSCache
│   │   ├── NowPlayingController.swift    MediaPlayer + iOS interruptions (Wave 2)
│   │   ├── SleepTimer.swift              Duration / end-of-track timer (Wave 2)
│   │   ├── Haptics.swift                 iOS haptic wrapper (Wave 2)
│   │   ├── ShowCatalog.swift             Aliases, derivation, acronyms (Wave 3)
│   │   └── SearchEngine.swift            Pure ranking (Wave 3)
│   ├── ViewModels/
│   │   └── PlayerViewModel.swift         Thin coordinator (@MainActor)
│   ├── Views/
│   │   ├── ContentView.swift             Root + filter + search wiring
│   │   ├── TrackListView.swift           List with context menu
│   │   ├── PlayerBarView.swift           Bottom player with heart/repeat (Wave 2)
│   │   ├── SleepTimerSheet.swift         Preset picker (Wave 2)
│   │   ├── ScopeIndicator.swift          "Playing from: X" chip (Wave 3)
│   │   ├── AmbientBackground.swift       Themed blurred backdrop (Wave 3)
│   │   ├── ArtworkView.swift             Cross-platform artwork view
│   │   ├── ScrubberSlider.swift          Scrub-with-commit slider
│   │   └── ErrorBanner.swift             Non-blocking error UI
│   └── Music/                            (Folder reference — see Adding music)
│
└── AnimenzPlayerTests/              Test target
    ├── Mocks.swift                       MockPlaybackEngine + fixtures
    ├── PlayQueueTests.swift              Queue logic
    ├── PlayerViewModelTests.swift        Coordinator logic (+ Wave 2, Wave 3 cases)
    ├── RepeatModeTests.swift             (Wave 2)
    ├── SleepTimerTests.swift             (Wave 2)
    ├── ShowCatalogTests.swift            Aliases + derivation (Wave 3)
    ├── SearchEngineTests.swift           Ranking (Wave 3)
    └── PlaybackScopeTests.swift          Scope enum (Wave 3)
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
                   │      PersistenceStore       │ ← last-played, shuffle,
                   │  (JSON, debounced writes)   │    favorites, scope query
                   └─────────────────────────────┘

                   ┌─────────────────────────────┐
                   │   SearchEngine (Wave 3)     │ ← pure ranking function
                   │   ShowCatalog  (Wave 3)     │    consulted by Views
                   └─────────────────────────────┘
```

### Collaborator responsibilities

| Collaborator       | Owns                                            | Does not own                  |
| ------------------ | ----------------------------------------------- | ----------------------------- |
| `LibraryStore`     | Scanning the bundle, filtering by extension     | Playback, persistence         |
| `PlayQueue`        | Ordered indices, current position, shuffle      | Audio, side effects           |
| `PlaybackEngine`   | Audio decoding, time observation, seek          | Queue logic, library          |
| `PersistenceStore` | JSON read/write, debouncing                     | Any domain knowledge          |
| `SearchEngine`     | Ranking tracks against a query (pure, stateless) | Any mutable state             |
| `ShowCatalog`      | Alias table, show derivation from titles, acronym generation | Scoring logic |
| `PlayerViewModel`  | Wiring + `@Published` state for SwiftUI         | Anything above                |

### Design decisions worth knowing

- **`PlaybackEngine` is a protocol.** The real implementation (`AVPlayerEngine`) uses `AVPlayer.addPeriodicTimeObserver` for progress and KVO on `timeControlStatus` for play/pause state — both more reliable than the old `Timer` loop against `AVAudioPlayer`. In tests, `MockPlaybackEngine` implements the same protocol without touching audio, so queue and coordinator logic can be exercised in microseconds.

- **`PlayQueue` is a struct.** Shuffle works by permuting a separate `orderedIndices` array, not the tracks themselves — this keeps the source order intact and makes unshuffle a reversible operation. Wave 3 did *not* need to edit `PlayQueue`: scoped playback is implemented by replacing the queue's track list, not by teaching the queue about scopes.

- **`PersistenceStore` debounces.** Scrubbing or auto-progress would otherwise hammer the disk; writes are batched at 500 ms. On `scenePhase` transitions the view model calls `flushPendingState()` so nothing is lost if the app is suspended.

- **`ArtworkCache` is byte-cost-limited.** `NSCache.totalCostLimit = 64 MB`. Images are keyed by `(url, size)`, so the list thumbnail (≤160 px) and the player-bar artwork (≤600 px) are cached independently; full-resolution decoding never happens for the 44 pt rows. Wave 3's themed background reuses this cache for its blurred backdrop rather than bundling new assets.

- **`SearchEngine` and `ShowCatalog` are pure.** No Combine, no I/O, no SwiftUI. The entire search experience — ranking, aliases, derivation — is covered by deterministic XCTests that run in milliseconds.

- **The view model is `@MainActor`.** Every `@Published` mutation happens on the main thread, and async engine work hops back via `MainActor.run` or `[weak self]` + a main-thread callback. This removes a whole category of SwiftUI "publishing changes from background threads" warnings.

---

## Building and running

1. Open `AnimenzPlayer.xcodeproj` in Xcode.
2. Select the `AnimenzPlayer` scheme.
3. Pick an iOS Simulator or "My Mac" as the run destination.
4. ⌘R.

The first launch will show the empty state until you add music (next section).

---

## iOS: enabling background audio

For Now Playing, Lock Screen controls, and continued playback when the screen is locked to work on iOS, the app needs the **Audio, AirPlay, and Picture in Picture** background mode. This is a one-time Xcode setup:

1. Select the project in the Xcode navigator.
2. Select the **AnimenzPlayer** target.
3. Open the **Signing & Capabilities** tab.
4. Click **+ Capability** and add **Background Modes**.
5. In the Background Modes section that appears, check **Audio, AirPlay, and Picture in Picture**.

This adds `UIBackgroundModes = [audio]` to `Info.plist`. Without it, iOS will suspend the app when the screen locks and playback will stop.

`AVAudioSession.setCategory(.playback)` is already called inside `AVPlayerEngine` on iOS at startup, so no further code changes are needed.

On macOS there is no equivalent setting — the app plays in the background automatically.

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

## Searching and scoped playback

The search box understands more than literal substrings. In rough order of how the ranker decides what matches:

1. **Aliases.** Short strings mapped to canonical show names in `ShowCatalog.canonicalAliases`. `AOT` → Attack on Titan. `JJK` → Jujutsu Kaisen. `SAO` → Sword Art Online. `BNHA` / `MHA` → My Hero Academia. `CSM` → Chainsaw Man. `KnY` → Demon Slayer. `JJBA` / `JoJo` → JoJo's Bizarre Adventure. Full list is in the source. Aliases are case-insensitive.
2. **Title substrings.** Literal substring matches on the filename's parsed title. `rumbling` finds the AoT Final Season OP.
3. **Show-name substrings.** `frieren` finds every track whose derived show is Frieren, even when "Frieren" doesn't literally appear in the title.
4. **First-letter acronyms.** Short all-letter queries (2–5 chars) that aren't in the alias table are matched against acronyms generated from known show names. Lets you reach shows without hand-curating aliases for them.
5. **Tokens.** Multi-word queries are split on whitespace; a track matches if every token appears somewhere in its title. `titan attack` (out of order) still finds AoT tracks.

### Scope vs. search — how they interact

The search box controls what's *visible* in the list. The scope controls what's *playing*. They couple only at the moment you press play:

| Action | Visible list | Scope |
| --- | --- | --- |
| Type `AOT` | Filters to AOT | No change |
| Tap an AOT track | — | Scope ← AOT |
| Clear the search box | Shows full library | **No change** — AOT keeps playing |
| Tap the X on the "Playing from" chip | — | Scope ← All Tracks |
| Switch filter picker to Favorites | Shows favorites | No change |

So if you want to browse the full library while your AoT queue keeps playing, type `AOT`, pick a track, then clear search. The scope chip stays put and next / previous / shuffle keep rotating within AoT.

### Known limitation

Multi-token queries don't currently expand aliases. `sao alicization` won't match the SAO Alicization track because `sao` isn't a substring of "Sword Art Online" — and token-match doesn't run aliases through the catalog. Single-token alias queries (just `AOT`, just `SAO`) work as expected.

### Themed background

When the search resolves to a known show, the main view gets a blurred ambient backdrop derived from one of that show's tracks. Disable it by toggling the `themedBackgroundsEnabled` default (no UI surface exists yet; set it with `defaults write` or add a settings toggle).

---

## Keyboard shortcuts (macOS)

Available from the **Playback** menu in the menu bar.

| Action                  | Shortcut         |
| ----------------------- | ---------------- |
| Play / Pause            | Space            |
| Next track              | ⌥⌘ →             |
| Previous track          | ⌥⌘ ←             |
| Toggle shuffle          | ⇧⌘ S             |
| Cycle repeat mode       | ⇧⌘ R             |
| Toggle favorite         | ⇧⌘ L             |

The `⌥⌘` and `⇧⌘` modifiers are chosen deliberately — `⌘ ←` / `⌘ →` and `⌘ L` are intercepted by `List` and `TextField` for beginning/end-of-line navigation, so the shortcuts would silently no-op when the search box had focus. See the `PlaybackCommands` comment in `AnimenzPlayerApp.swift` for the full rationale.

Space toggles playback only when no text field is focused — when the search box or any other input has focus, Space inserts a space character as expected.

On iOS the same actions are accessible via the player bar and the context menu on the repeat button (which also contains the Sleep Timer… entry).

---

## Testing

### One-time test target setup

If the project was opened fresh without a test target, add one:

1. **File → New → Target…**
2. Select **Unit Testing Bundle**. Under **Testing System** pick **XCTest**.
3. Product Name: `AnimenzPlayerTests`. Target to be Tested: `AnimenzPlayer`.
4. Click **Finish**.
5. Delete the boilerplate `AnimenzPlayerTests.swift` that Xcode generates.
6. Drag every file from `AnimenzPlayerTests/` in this repo into the test target's group.

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

The suite is designed to be fast — all tests complete in well under a second because no real audio decoding happens. Wave 3 added `ShowCatalogTests`, `SearchEngineTests`, and `PlaybackScopeTests`, plus a `// MARK: - Wave 3: Scoped playback` section inside `PlayerViewModelTests`. The ranking tests use a fixture library of real titles so regressions show up as "this query used to return these tracks and now returns something else".

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

### Search for `AOT` doesn't return Attack on Titan tracks

- The alias matching runs against each track's *derived* show — `Track.show`, which comes from `ShowCatalog.derivedShow(from:)` parsing the title. If your track filenames don't contain the literal show name (e.g. you renamed files), derivation fails and alias matching has nothing to hit. The fix is either to re-import with yt-dlp's default naming or to add an entry for the missing show name to `ShowCatalog.knownShows`.
- Literal substring search still works in all cases — typing `Attack on Titan` will always find AoT tracks whose titles contain that phrase.

### The scope chip says "aot" instead of "Attack on Titan"

The chip should resolve the query through `ShowCatalog.canonicalShow(for:)` before rendering. If you see the raw query, the query isn't in the alias table — add it, or it means you used a non-alias query (e.g. typed `rumbling`, which is a title substring rather than a show alias). Raw queries appear in quotes; canonical names appear unquoted.

### Last-played position isn't restored

- The state file lives at `~/Library/Application Support/<bundle-id>/player-state.json` on macOS, or the sandbox equivalent on iOS. Deleting it is harmless and resets state.
- On iOS, make sure the app has a chance to reach `scenePhase == .background` before it's killed — the persistence flush happens there.

### `Music` folder missing from bundle

The `.gitignore` excludes `AnimenzPlayer/Music/` by design — the library is per-developer. A fresh clone will show the empty state until you add files; see [Adding music](#adding-music).

---

## Roadmap

Waves 1 through 3 are complete. Wave 4 remains:

- **Wave 1 (done):** Foundational refactor — thin coordinator, `AVPlayer`-backed engine, value-type queue, JSON persistence, error surface, cache improvements.
- **Wave 2 (done):** `MPNowPlayingInfoCenter` / remote controls, iOS interruption handling + background audio, repeat modes, sleep timer, favorites, recently-played, macOS keyboard shortcuts, iOS haptics.
- **Wave 3 (done, scope revised):** Search-first browsing with alias and acronym matching, scoped playback, optional themed ambient background, scope persistence. The original roadmap anticipated albums, user playlists, smart playlists, and sidebar navigation; the revised implementation achieves the same "listen to only X" user intent through search + scope without restructuring `ContentView`, which keeps Wave 4's planned expansion gesture uncontested. See [`WAVE3_PLAN.md`](./WAVE3_PLAN.md) for the full rationale and the implementation doc.
- **Wave 4:** Expandable full-screen player with matched-geometry artwork transitions, waveform scrubber, ambient animation.

Contributions targeting those features are welcome; please keep the architectural boundaries intact — the collaborators should stay individually testable.

### Ideas deferred from Wave 3

These fit naturally as follow-up work without blocking Wave 4:

- **User-editable aliases.** `ShowCatalog.canonicalAliases` is a `static let` today. Adding a `State.userAliases: [String: String]` (chokepoint-rule-compliant) plus a small settings UI would let users teach the search engine `JJK2 → Jujutsu Kaisen S2` and similar.
- **Multi-token alias expansion.** See the known-limitation note under [Searching](#searching-and-scoped-playback). Expanding each token through the alias table before token-matching would make `sao alicization` work.
- **Fuzzy / typo-tolerant search.** Levenshtein distance against titles and shows. Cheap to add once the ranking rules stabilize.
- **Settings UI for `themedBackgroundsEnabled`.** The persisted flag is already in `PersistenceStore.State`; it just needs a toggle somewhere.

---

## Contributing

See [`BRANCHING.md`](./BRANCHING.md) for the branch model, parallelization rules, file ownership map, and rules for running multiple streams of work concurrently (including multiple AI-assistant sessions). Read it **before** opening a second stream of work — the chokepoint rules in that doc are what make parallel wave development tractable. Wave 3's implementation plan ([`WAVE3_PLAN.md`](./WAVE3_PLAN.md)) also revised the parallelization matrix's Wave 3 × Wave 4 cell from 🔴 to 🟡 given the reduced structural footprint — a follow-up update to `BRANCHING.md` is still pending.
