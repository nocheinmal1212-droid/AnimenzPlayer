# Branching & Parallel Work Rules

This document defines how work is split across branches, which streams can
run in parallel safely, and where the sharp edges are. It's written to be
read by both human contributors and AI coding assistants — the constraints
are the same for both, but the failure modes differ (AI sessions tend to
produce internally-consistent work that conflicts with other sessions'
internally-consistent work, so the interface boundaries matter more than
in a typical team setting).

---

## Table of contents

1. [Branch model](#branch-model)
2. [Work stream taxonomy](#work-stream-taxonomy)
3. [Parallelization matrix](#parallelization-matrix)
4. [File ownership map](#file-ownership-map)
5. [Shared chokepoint rules](#shared-chokepoint-rules)
6. [Non-wave feature branches](#non-wave-feature-branches)
7. [AI-assistant-specific guidance](#ai-assistant-specific-guidance)
8. [Testing gates](#testing-gates)
9. [Merge procedure](#merge-procedure)
10. [Examples](#examples)

---

## Branch model

```
main                               always green, always shippable
 │
 ├── wave/2-now-playing            long-lived, roughly one per wave
 │   ├── feature/2a-repeat-modes   short-lived, stacked on the wave branch
 │   ├── feature/2b-remote-center
 │   └── feature/2c-sleep-timer
 │
 ├── wave/3-collections
 │   ├── feature/3a-show-grouping
 │   └── feature/3b-playlists
 │
 ├── wave/4-animations             don't open until wave 3 is merged (see matrix)
 │
 └── feature/<name>                non-wave work (bugfix, small feature)
```

Naming:

- `wave/N-<slug>` — one branch per wave in the roadmap. Long-lived. Merged to
  `main` only when the wave is complete.
- `feature/N<letter>-<slug>` — a unit of work inside a wave. Branched from
  the wave branch, merged back into it.
- `feature/<slug>` — non-wave work. Branched from `main`, merged back to
  `main`. **Does not** touch any wave branch.
- `fix/<slug>` — bugfix on `main`. Backported into any open wave branch
  immediately after merge (by the wave branch's owner) to prevent drift.

Rules:

- No branch may depend on another in-progress wave. If Wave 3 finds it needs
  something from Wave 2, that something gets extracted into a standalone
  `feature/` branch merged to `main` first.
- Wave branches rebase onto `main` weekly. Drift past two weeks is a
  warning signal that the wave should be broken into smaller mergeable
  units.

---

## Work stream taxonomy

The roadmap has four waves. Their primary architectural footprints are:

| Wave | Primary footprint                                       | Shape             |
| ---- | ------------------------------------------------------- | ----------------- |
| 1    | Refactor: split `PlayerViewModel` into collaborators.   | Done, merged.     |
| 2    | Additive integration: `MPNowPlayingInfoCenter`, remote commands, background audio, repeat modes, sleep timer, favorites, macOS shortcuts. | Mostly new files + small edits to existing ones. |
| 3    | Structural: collections (shows, playlists, smart lists), sidebar navigation, track metadata enrichment. | New files + significant edits to `Track`, `LibraryStore`, `ContentView`. |
| 4    | Visual: expandable full-screen player, matched-geometry transitions, waveform scrubber, ambient animation. | Large edits to `PlayerBarView`, `ContentView`; many new files. |

The shape column is what determines parallelizability. Wave 2 is *mostly
additive* — it drops new files beside the existing ones and makes surgical
edits to a handful. Waves 3 and 4 are *structural and visual* respectively
— they reshape files the other waves depend on.

---

## Parallelization matrix

Legend:
- 🟢 Safe to run in parallel
- 🟡 Possible with coordination (read the chokepoint rules)
- 🔴 Sequence them; do not parallelize

|              | Wave 2 | Wave 3 | Wave 4 | Non-wave feature |
| ------------ | :----: | :----: | :----: | :--------------: |
| **Wave 2**   |   —    |   🟡   |   🔴   |        🟢        |
| **Wave 3**   |   🟡   |   —    |   🔴   |        🟡        |
| **Wave 4**   |   🔴   |   🔴   |   —    |        🟡        |
| **Feature**  |   🟢   |   🟡   |   🟡   |        🟢        |

### Rationale

**🟡 Wave 2 × Wave 3**: both extend `PersistenceStore.State` and make
`PlayerViewModel` aware of new concepts (repeat mode vs. collection sources).
Tractable if the chokepoint rules below are followed.

**🔴 Wave 2 × Wave 4**: both edit `PlayerBarView`. Wave 2 adds a button
to the control cluster; Wave 4 rewrites the whole view into a mini-player
with an expand gesture and matched-geometry artwork. You will lose one of
them on merge. Do Wave 2 first (it's closer to shippable), then Wave 4.

**🔴 Wave 3 × Wave 4**: both restructure `ContentView`. Wave 3 introduces
`NavigationSplitView` (macOS) / `TabView` (iOS) with a sidebar; Wave 4
introduces an expansion gesture and a new full-screen-player presentation.
Integrate sequentially.

**🟡 Wave 3 × Non-wave feature**: depends entirely on what the feature
touches. A feature that lives in its own new files (e.g., an equalizer, a
visualizer) is fine. A feature that edits `ContentView` or `Track` is not.

---

## File ownership map

Every file has a *primary owner*: the wave or stream whose work dominates
edits to that file. Other streams may touch it only via the chokepoint
rules below.

| File                              | Primary owner  | Notes                                 |
| --------------------------------- | -------------- | ------------------------------------- |
| `App/AnimenzPlayerApp.swift`      | Wave 2         | Adds `.commands` for macOS shortcuts, background-audio entitlement wiring. |
| `Models/Track.swift`              | Wave 3         | Adds `show` derivation.                |
| `Models/PlayerError.swift`        | shared         | Append-only: new cases allowed.        |
| `Services/PlaybackEngine.swift`   | Wave 2         | Adds repeat-mode hooks, `MPNowPlayingInfoCenter` integration. |
| `Services/PlayQueue.swift`        | Wave 2         | Adds `RepeatMode` support.             |
| `Services/LibraryStore.swift`     | Wave 3         | Adds grouping.                          |
| `Services/PersistenceStore.swift` | **shared**     | See chokepoint rule #1 below.          |
| `Services/ArtworkCache.swift`     | Wave 4         | Adds collage generation.                |
| `ViewModels/PlayerViewModel.swift`| **shared**     | See chokepoint rule #2 below.          |
| `Views/ContentView.swift`         | Wave 3         | Becomes sidebar host.                   |
| `Views/TrackListView.swift`       | Wave 3         | Becomes one of several list sources.    |
| `Views/PlayerBarView.swift`       | Wave 2 → 4     | Wave 2 completes, then Wave 4 takes over. **Not parallel.** |
| `Views/ArtworkView.swift`         | stable         | Should not need edits in any wave.     |
| `Views/ErrorBanner.swift`         | stable         | Should not need edits in any wave.     |
| `AnimenzPlayerTests/*`            | per-wave       | Each wave ships its own tests.         |

### Append-only files

`PlayerError.swift` is append-only. Anyone may add new cases; no one may
rename, remove, or reorder existing ones. This keeps the type stable as a
shared vocabulary.

---

## Shared chokepoint rules

These are the two files edited by multiple streams concurrently. Rules
exist to make merges mechanical rather than requiring judgment.

### Chokepoint #1: `PersistenceStore.State`

The serialized state struct grows across waves:

```swift
struct State: Codable, Equatable {
    var lastTrackURL: URL?
    var lastPosition: Double = 0
    var isShuffled: Bool = false

    // Wave 2 additions:
    var repeatMode: RepeatMode = .off
    var favorites: Set<URL> = []
    var playHistory: [URL] = []

    // Wave 3 additions:
    var playlists: [Playlist] = []
    var collectionOverrides: [String: String] = [:]
}
```

Rules:

1. **Every added field must have a default value.** Non-optional, defaulted.
   This is what keeps `JSONDecoder` happy when it reads an old file.
2. **Fields are never renamed or removed.** To deprecate, add a replacement
   with a new name and leave the old one in the struct (use `_` prefix to
   signal abandonment).
3. **Each wave owns a contiguous block of fields**, grouped by comment, in
   the order waves merge to `main`. Don't interleave.
4. **Only one wave's PR adds a given field.** If two waves both want
   `favorites`, the first to spec it wins; the second rebases and uses it.

If rules 1–3 are followed, two waves adding disjoint field sets produce a
trivial merge: `git merge` sees additions to the same file but not the
same lines. Conflicts only arise if the chokepoint rules were broken.

### Chokepoint #2: `PlayerViewModel`

The coordinator naturally accretes `@Published` properties and intent
methods. To keep parallel edits tractable:

1. **Group `@Published` state by wave in source order.** Wave 1 state
   first, then a `// MARK: - Wave 2 state` block, then Wave 3, etc.
   Don't interleave.
2. **Group intent methods the same way.** A wave adds its intents as a
   contiguous block, not scattered among Wave 1 methods.
3. **Never edit another wave's block** except to fix a bug in it. If you
   find yourself wanting to, you probably need a refactor that should be
   its own merged-to-`main` `feature/` branch first.
4. **Binding code (`bindEngine`, `bindLibrary`, etc.) is additive.** Each
   wave adds its own `bindX()` method and calls it from `init`. Don't edit
   the existing ones.

These rules are the same recipe as the State chokepoint: partition by
wave, append-only within each partition, no interleaving.

---

## Non-wave feature branches

A "non-wave feature" is anything not on the roadmap — a small UX
improvement, an equalizer, an accessibility pass, a dev tool. These should
branch from `main`, not from a wave branch.

### Where new features live

| Shape of the feature                                    | Where it goes                                      |
| ------------------------------------------------------- | -------------------------------------------------- |
| Self-contained new functionality (visualizer, equalizer)| New files under `Services/` and/or `Views/`.        |
| Cross-cutting UI polish (accessibility, localization)    | Edits spread across `Views/`.                       |
| New data to persist                                      | Extends `PersistenceStore.State` (chokepoint rule). |
| New playback capability                                  | Extends `PlaybackEngine` protocol.                  |

### Can a non-wave feature modify wave-owned files?

Only if:
1. The feature is blocked without it, AND
2. The edit is confined to a new, clearly-labeled section within the file
   (e.g., a new `// MARK: - Keyboard shortcuts` block), AND
3. The wave owner is notified so they can rebase cleanly.

Avoid editing `PlayerViewModel`, `ContentView`, or `PlayerBarView` in a
non-wave branch if any wave touching those files is in progress. Queue the
work instead.

### Should a non-wave feature extend the `PlaybackEngine` protocol?

Yes, if the capability genuinely belongs there (e.g., playback speed,
output-device selection). Adding protocol requirements is a breaking
change for any in-flight branch that has its own conforming mock, so:

- Add a new method with a default implementation in a protocol extension
  where possible, so existing mocks don't break.
- If a default isn't possible (e.g., it returns a value), extend
  `MockPlaybackEngine` in the same PR that extends the protocol.

---

## AI-assistant-specific guidance

AI sessions have a particular failure mode: they don't know what *other*
sessions are doing, and they produce internally-consistent code that can
silently conflict with other internally-consistent code. A few rules
mitigate this:

1. **Start every session with the constraints.** Before asking an assistant
   to work on Wave 3, paste (a) the file ownership map above, (b) the
   chokepoint rules, and (c) the list of files the session is allowed to
   edit. Without this context, the model will make locally-sensible edits
   to files it shouldn't be touching.

2. **Forbid edits to files the assistant doesn't own.** "Do not edit
   `PlayerBarView.swift`" is a load-bearing instruction for a Wave 3
   session while Wave 2 is open.

3. **Require test coverage for each unit of work.** Tests are the
   interface contract. A Wave 2 feature that adds a repeat mode must
   include a test asserting `.one` repeats the current track on finish;
   when a Wave 3 session later reshapes the queue, that test catches
   regressions.

4. **Treat the architecture as a hard constraint, not a suggestion.** The
   assistant should refuse to move business logic into views or to bypass
   the `PlaybackEngine` protocol with direct `AVPlayer` calls from a view
   model. If an assistant's proposed design violates layering, push back
   or start a new session.

5. **Do not ask the assistant to refactor shared files while other work is
   in progress.** "Clean up PlayerViewModel" while Wave 2 is open is a
   recipe for lost work. Refactors of shared files must be their own
   merged-to-`main` changes, fast and scoped.

6. **Favor new files over edits.** When in doubt, ask the assistant to
   create a new file rather than extend an existing one. New files never
   conflict with anything.

---

## Testing gates

| Gate                       | Requirement                                             |
| -------------------------- | ------------------------------------------------------- |
| Before merging `feature/X` into its wave branch   | All existing tests pass. New behavior has tests. |
| Before merging a wave into `main`                 | All tests pass on a clean checkout. The wave's feature matrix is exercised by UI or integration tests. |
| Before merging a non-wave `feature/`              | All tests pass. No new warnings introduced by the change. |
| Before merging a `fix/` into `main`               | Regression test for the specific bug included in the same PR. |

The `PlayerViewModelTests` and `PlayQueueTests` suites are the load-bearing
check that concurrent waves haven't broken each other's behavior. A merge
that requires those tests to be changed (not just extended) is a signal
that something has gone wrong — the shared contract should be stable.

---

## Merge procedure

For a wave branch merging to `main`:

1. Rebase the wave branch onto latest `main`.
2. Run the full test suite on the rebased branch.
3. Open a PR from the wave branch. PR description lists every feature in
   the wave and links to the tests covering each.
4. Ship behind a feature flag if the wave is large — the flag can be
   removed in a follow-up once it's been live for a release.
5. Squash-merge. The wave branch is deleted after merge.
6. Immediately rebase every other open wave branch onto the new `main`
   and re-run their tests. Any breakage is fixed before returning to
   feature work.

For a non-wave feature merging to `main`:

1. Rebase onto latest `main`.
2. Confirm the feature doesn't touch any file currently being edited in
   an open wave branch. If it does, coordinate.
3. Open a PR. Squash-merge.
4. If any wave branch is open and the change affects their territory,
   notify the owner. The wave branch rebases at their convenience.

---

## Examples

### ✅ Example: Wave 2 and Wave 3 running in parallel

- Wave 2 is on `wave/2-now-playing`, adding `MPNowPlayingInfoCenter` and
  repeat modes. Its edits to shared files are:
  - `PersistenceStore.State`: adds `repeatMode`, `favorites`, `playHistory`.
  - `PlayerViewModel`: adds a `// MARK: - Wave 2 state` block with
    `@Published var repeatMode`, intent methods for it, a `bindRemote()`
    method.
- Wave 3 is on `wave/3-collections`, adding shows and playlists. Its
  edits to shared files are:
  - `PersistenceStore.State`: adds `playlists`, `collectionOverrides`.
  - `PlayerViewModel`: adds a `// MARK: - Wave 3 state` block with
    `@Published var currentCollection`, etc.
  - `Track`: adds the `show` computed property (owned by Wave 3, no
    overlap).

When Wave 2 merges first, Wave 3's rebase produces a merge commit that
interleaves the two wave blocks in `PersistenceStore.State` in wave order.
No textual conflict.

### ❌ Example: what goes wrong without the chokepoint rules

Wave 2 adds `repeatMode` to `State` at line 18, between `isShuffled` and
whatever's next. Wave 3, unaware, adds `playlists` at line 18 too. Merge
conflict. Worse, a naive resolution that accepts both sides puts the two
fields on the same line and produces a syntax error the compiler catches
— but if one wave had added a *method* instead of a field, the naive merge
might compile while silently dropping the other wave's code.

This is the exact scenario the "partition by wave, append-only within
partition" rule prevents.

### ✅ Example: a non-wave feature running alongside Wave 2

Feature: "Add a track-info popover when the user hovers over a row
on macOS."

- Branch: `feature/track-info-popover` from `main`.
- Files touched: `TrackListView.swift` (adds a `.popover` modifier), new
  file `Views/TrackInfoView.swift`.
- Wave 2 isn't touching `TrackListView`, so no conflict.
- Merges to `main` independently. Wave 2 rebases and picks it up.

### ❌ Example: a non-wave feature that should have waited

Feature: "Redesign the player bar with a blurred glass background."

- This touches `PlayerBarView.swift`, which is Wave 2's territory until
  Wave 2 merges, and Wave 4's territory after.
- Correct behavior: wait for Wave 2 to merge, then either fold the redesign
  into Wave 4 or do it as a `feature/` branch before Wave 4 starts.
- Incorrect behavior: start the branch now and hope for clean rebase. The
  rebase will not be clean.

---

When in doubt, ask: *which file does this edit, and who owns that file
right now?* If the answer is "someone else's open branch", queue the work.
