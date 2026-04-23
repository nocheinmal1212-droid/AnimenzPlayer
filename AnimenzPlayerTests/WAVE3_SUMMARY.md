# Wave 3 Implementation — Summary

This folder contains a drop-in implementation of Wave 3 per `WAVE3_PLAN.md`.
Every file here mirrors the exact path it belongs at in the repo, so you can
copy the `AnimenzPlayer/` and `AnimenzPlayerTests/` folders over the existing
ones.

---

## File inventory

### New files (7)

| Path                                               | Purpose                                                  |
| -------------------------------------------------- | -------------------------------------------------------- |
| `AnimenzPlayer/Services/ShowCatalog.swift`         | Canonical shows, alias table, derivation, acronyms.      |
| `AnimenzPlayer/Services/SearchEngine.swift`        | Pure ranking function (`rank(_:in:)`).                   |
| `AnimenzPlayer/Models/PlaybackScope.swift`         | Scope enum + display helpers.                            |
| `AnimenzPlayer/Views/ScopeIndicator.swift`         | "Playing from: X" chip above the player bar.             |
| `AnimenzPlayer/Views/AmbientBackground.swift`      | Themed blurred artwork backdrop (feature 3).             |
| `AnimenzPlayerTests/ShowCatalogTests.swift`        | Aliases + derivation regression tests.                   |
| `AnimenzPlayerTests/SearchEngineTests.swift`       | Ranking tests with fixture library.                      |
| `AnimenzPlayerTests/PlaybackScopeTests.swift`      | Scope enum tests.                                        |

### Modified files (5)

| Path                                               | Nature of change                                         |
| -------------------------------------------------- | -------------------------------------------------------- |
| `AnimenzPlayer/Models/Track.swift`                 | Added `var show: String?` computed property.             |
| `AnimenzPlayer/Services/PersistenceStore.swift`    | Appended Wave 3 block to `State` (chokepoint #1).        |
| `AnimenzPlayer/ViewModels/PlayerViewModel.swift`   | Appended Wave 3 state + `bindWave3()` (chokepoint #2).   |
| `AnimenzPlayer/Views/ContentView.swift`            | Search via `SearchEngine`, scope wiring, ambient bg.     |
| `AnimenzPlayer/Views/TrackListView.swift`          | `scope` parameter; tap calls `play(_:inScope:)`.         |
| `AnimenzPlayerTests/PlayerViewModelTests.swift`    | Appended `// MARK: - Wave 3` section with 9 new cases.   |

### Explicitly NOT modified

Per `WAVE3_PLAN.md` §2 and the ownership map in `BRANCHING.md`:

- `AnimenzPlayer/Views/PlayerBarView.swift` — Wave 2 → Wave 4 territory.
- `AnimenzPlayer/Services/PlayQueue.swift` — no queue changes needed.
- `AnimenzPlayer/Services/PlaybackEngine.swift` — no protocol changes.
- `AnimenzPlayerTests/PlayQueueTests.swift` — queue contract unchanged.

---

## How the pieces fit

```
User types "AOT" into search box
       │
       ▼
ContentView.searchText = "AOT"
       │
       ▼
ContentView.filteredTracks
   = SearchEngine.rank("AOT", in: baseTracks)
       │  (SearchEngine asks ShowCatalog.canonicalShow(for: "AOT")
       │   → "Attack on Titan", then scores each track against its
       │   derived show — every AOT track scores 100)
       ▼
TrackListView displays ranked tracks
       │
User taps a track
       │
       ▼
TrackListView.onTapGesture
   → player.play(track, inScope: ContentView.currentPlayScope)
       │  (scope is .search(query: "AOT", results: filteredTracks)
       │   because searchText is non-empty)
       ▼
PlayerViewModel.play(_:inScope:)
   → queue.setTracks(scope.results)     ← queue now contains ONLY AOT tracks
   → currentScope = .search(...)         ← published; UI shows chip
   → queue.jump(to: track)
   → loadAndPlay(track)
       │
       ▼
ScopeIndicator chip appears above PlayerBarView
AmbientBackground loads AOT artwork (if enabled)
       │
User clears search box
       │
       ▼
filteredTracks reverts to baseTracks (full library / filter)
BUT currentScope stays .search(...)    ← queue, audio, chip unchanged
       │
User taps X on the ScopeIndicator chip
       │
       ▼
player.clearScope()
   → queue.setTracks(library.tracks, preservingCurrent: true)
   → currentScope = .all
```

---

## Design decisions worth flagging

### Why `Track.show` is a computed property, not stored

Computed so that adding a new canonical show (or alias) to `ShowCatalog`
takes effect immediately for every existing `Track` value in memory.
Stored would have required a migration path. The cost is trivial — show
derivation is a linear scan of a small string list, and the Track itself
is already cheap to create.

### Why the search-scope snapshot captures `results` in the enum

It's tempting to store only the query and re-rank on every access. But
that would make `PlaybackScope`'s `.search` case depend on ambient state
(the library), breaking its value-type guarantees and making equality
comparisons lie. Storing the snapshot is O(references to Tracks), not
O(Track storage), so it's cheap.

### Why scope persistence only round-trips the query

On relaunch the library may have changed (files added, removed,
renamed), so replaying a literal track snapshot risks pointing at URLs
that no longer exist. Re-ranking the query against the current library
is self-healing: if nothing matches any more, we silently fall back to
`.all`.

### Why `.favorites` and `.recent` scopes are NOT persisted

Both are re-derivable from saved state (`favorites`, `recentlyPlayed`).
If a user is in favorites scope when they quit and they have a last-
played track from favorites restored at launch, they'd have to tap one
track to re-enter favorites scope. That's a reasonable tradeoff given
the alternative (more state fields to round-trip, more surface area to
get wrong on upgrade).

### The alias table is code-resident for Wave 3

Adding user-editable aliases later is mechanical: add
`State.userAliases: [String: String]` (chokepoint rule compliant) and
have `ShowCatalog.canonicalShow(for:)` consult both the static and
dynamic tables. No search-engine changes required. Deliberately out of
scope for Wave 3 to keep the diff small.

---

## Test matrix

| Suite                       | Cases | What's covered                                            |
| --------------------------- | :---: | --------------------------------------------------------- |
| `ShowCatalogTests`          |  10   | Alias resolution, case-insensitivity, derivation for real titles, longest-match-wins, acronym generation. |
| `SearchEngineTests`         |  12   | Empty-query passthrough, substring regressions, alias matching, bare-show substring, token-order independence, deterministic results. |
| `PlaybackScopeTests`        |  8    | `isRestricted`, `displayName`, equality.                  |
| `PlayerViewModelTests`      |  +9   | (additions) Default scope, play-in-scope, next within scope, repeat-all wraps within scope, repeat-off stops at scope end, `clearScope()` preserves track, not-in-scope surfaces error, scope persistence round-trip, legacy `play(_:)` unchanged. |

All additions preserve the existing Wave 1–2 suite unchanged per
`BRANCHING.md`'s "no edits to existing cases" rule.

---

## Pre-existing test worth flagging (not a Wave 3 regression)

`PlayerViewModelTests.testFinishOnLastTrackWrapsToFirst` asserts that
playing the last track to completion auto-advances to the first track.
With Wave 2's `handleTrackFinished` and default `repeatMode = .off`, the
queue's `advanceForFinish(.off)` returns `.stop` on the last track, so
this test appears to be mis-specified against Wave 2's repeat semantics
— it looks like a leftover from Wave 1's `onFinish = next()` behavior.

My Wave 3 code preserves Wave 2's `handleTrackFinished` exactly, so this
test is in the same state it was in Wave 2. If it's currently passing in
the Wave 2 checkout, my changes won't break it; if it's currently
failing, my changes won't fix it. Repeat-mode semantics are owned by
Wave 2 — a separate `fix/` branch per `BRANCHING.md` is the right place
to resolve it.

The Wave 3 finish-behavior tests (`testFinishInScope*`) exercise the
correct semantics directly and will catch any future regression.

---

## Follow-up items (not included)

These are mentioned in `WAVE3_PLAN.md` but kept out of this implementation
intentionally:

1. **Settings UI for `themedBackgroundsEnabled`** — the persisted flag
   exists and `AmbientBackground` already reads it via `@AppStorage`.
   Adding a toggle would live in a settings sheet that doesn't exist
   yet. One line to wire up when the settings surface arrives.

2. **User-editable aliases** — `ShowCatalog.canonicalAliases` is a
   `static let` for Wave 3. Extending it to consult a persisted
   `State.userAliases` is a two-line change if wanted later.

3. **README + BRANCHING.md updates** — per `WAVE3_PLAN.md` §12, the
   README's Roadmap section should be updated to reflect the revised
   Wave 3 (search + scope, not albums + playlists) and BRANCHING.md's
   parallelization matrix updated for the new Wave 3 × Wave 4
   relationship (🔴 → 🟡). Left for the merge PR so the doc changes
   ship with the feature.

---

## How to verify

1. Copy the files here over the equivalent paths in your checkout.
2. Add the three new source files to the `AnimenzPlayer` target in
   Xcode's Project Navigator (they live at their expected paths).
3. Add the three new test files to the `AnimenzPlayerTests` target
   (same drill).
4. ⌘U. The new tests should all pass; the existing suite should remain
   green except for `testFinishOnLastTrackWrapsToFirst` if it was
   already failing in your Wave 2 checkout.
5. Run the app, type `AOT` in the search, tap a track. The scope chip
   should appear above the player bar; next/previous should cycle only
   through AOT tracks; clearing the search box should NOT reset scope;
   tapping the X on the chip should.
