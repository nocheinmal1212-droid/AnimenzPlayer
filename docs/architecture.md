# Architecture

This guide describes the current implementation. The app is a SwiftUI interface around a main-actor coordinator and narrowly scoped collaborators.

## Components

| Component | Responsibility |
| --- | --- |
| `AnimenzPlayerApp` | App lifetime, coordinator injection, macOS commands and diagnostics startup |
| `PlayerViewModel` | User intents, queue/scope coordination, async load cancellation, published UI state, and persistence wiring |
| `PlaybackProgressModel` | Separately observed playback progress, so frequent engine ticks do not invalidate every coordinator observer |
| `LibraryStore` | Flat bundle discovery, extension filtering, and track ordering |
| `Track` / `ShowCatalog` | Filename-derived metadata, computed show membership, canonical names, aliases, and acronyms |
| `SearchEngine` | Pure ranking over a supplied track list |
| `PlaybackScope` / `PlayQueue` | Scope value/snapshot and ordered traversal, shuffle, previous/next, repeat-aware completion |
| `PlaybackEngine` / `AVPlayerEngine` | Playback interface and AVPlayer implementation, load/seek generations, time and state observation |
| `PlaybackRecovery` / `PlaybackActivity` | Bounded retry policy, playback intent, sleep suspension, and paired macOS idle-sleep activity |
| `PersistenceStore` | Codable JSON state and debounced writes |
| `NowPlayingController` | System metadata, remote commands, and iOS interruption callbacks |
| `SleepTimer` / `Haptics` | Timer expiration and iOS feedback |
| `ArtworkCache` | Sidecar/embedded artwork, ImageIO downsampling, and a byte-cost-limited cache |
| `PlaybackDiagnostics` | Bounded, rotating local event storage and export |
| `PlayerStateDiagnostics` / `MacPlaybackDiagnostics` | Passive AVPlayer observations, macOS system events, and export UI |

Views observe `PlayerViewModel` for coarse state. `ScrubberSlider` observes `PlaybackProgressModel` directly; other surfaces also observe their own collaborators where needed. Engine progress arrives at approximately 4 Hz. Now Playing updates are throttled to 1 Hz.

`PlayQueue` is a value type. Shuffle permutes ordered indices rather than changing the library. The queue receives a scope's tracks and does not interpret search queries. `PlaybackEngine` is a protocol so coordinator tests can use `MockPlaybackEngine` without decoding audio.

## Search and scope

`ContentView` applies the All/Favorites/Recent filter, then calls `SearchEngine.rank`. A track selection sends both the selected track and a scope to the coordinator. A nonempty search takes precedence over the list filter and captures the displayed results.

Search uses alias matches, title/show substrings, short letter acronyms, and token matching, with descending scores and track index as the tiebreaker. An empty query passes through its input. Tokens are matched literally; individual tokens are not alias-expanded. Show derivation is computed from titles, so catalog updates apply to existing tracks without storing new metadata.

A search scope contains its query and a snapshot of results. Clearing search or changing a list filter changes browsing without changing playback. Clearing the scope rebuilds the full-library queue while preserving the current track. Favorites and Recent scopes derive their tracks from coordinator state. Library reloads reapply the scope and filter out missing tracks.

Only the search query is persisted for scope restoration. On launch it is re-ranked against the current library; an empty result falls back to All. Favorites and Recent scopes themselves are not restored, although favorites and history are saved.

`AmbientBackground` resolves the active search scope to a show and selects representative library artwork. It reads `@AppStorage("themedBackgroundsEnabled")`, defaulting to true. A same-named field also exists in JSON state, but it is not the preference read by the view. No settings UI currently exposes this preference.

## State and playback lifetime

The coordinator and mutable playback collaborators use main-actor isolation. Load generations and playback intent prevent older asynchronous operations from overriding a newer selection or Pause. Natural completion consults repeat mode, with end-of-track sleep-timer expiration taking precedence.

`PersistenceStore` saves `player-state.json` under Application Support and the bundle identifier. State includes last track/position, shuffle, repeat, favorites, recent history, and the scope query. Writes are debounced by 500 ms; progress persistence is throttled to roughly five-second buckets. Inactive/background scene transitions flush pending state. Restoration loads the saved track and position without automatically starting playback.

The store uses synthesized `Codable` decoding. If decoding fails, it falls back to a fresh `State`. Initial values on nonoptional properties do not guarantee that older files missing those keys decode successfully. Preserve the existing schema during unrelated work; any schema change needs deliberate compatibility handling and validation.

## Recovery and diagnostics

`AVPlayerEngine` uses `PlaybackRecovery` to track requested playback separately from reported AVPlayer state. Failure can schedule up to three attempts with 1-, 2-, and 4-second delays and an 8-second progress timeout per attempt. The first attempt can reuse a ready player; later attempts rebuild and restore position. Advancing media time confirms recovery.

Pause, Stop, and replacement loads invalidate pending retries/seeks. System sleep suspends recovery; waking resumes only if playback is still requested. `PlaybackActivity` pairs the macOS idle-sleep assertion with active playback/attempts, releasing it during pause, sleep, retry backoff, exhaustion, and teardown.

Diagnostics observe playback and system state without driving recovery. Disk writes use a private utility queue with bounded backlog and rotating files. Export is user-initiated and does not stop playback. See [Troubleshooting](troubleshooting.md) for retention, privacy, and recovery details.

## Artwork and layout constraints

Artwork loads sidecars first, then embedded metadata. ImageIO downsamples during decoding. Cache keys include track URL and rendering size; thumbnail and player images have 160 px and 600 px limits, respectively, with a 64 MiB cost limit.

`ContentView` keeps `NavigationStack` as its navigation root. Search and toolbar modifiers attach to a stable wrapper inside the stack, so list/empty-state swaps do not tear down the search host. The ambient artwork paints through `.background`; the scope chip and player bar use a bottom safe-area inset. Preserve this relationship when editing layout: a sibling background with `ignoresSafeArea` can change safe-area propagation and hit-testing.

macOS menu command buttons remain in the command tree, using disabled states where appropriate. Their shortcuts avoid common text-navigation bindings. The [manual checks](../CONTRIBUTING.md#manual-checks) cover behavior that logic tests do not render.
