# Wave 3 Plan — Search-First Browsing & Scoped Playback

This document plans Wave 3 of AnimenzPlayer. It supersedes the Wave 3
description in the README and the roadmap pointer in `BRANCHING.md`; the
underlying branch model, chokepoint rules, and file ownership map in
`BRANCHING.md` still apply unchanged.

---

## 1. Scope

### 1.1 What Wave 3 builds

1. **A strong search engine.** Typing `AOT` shows every Attack on Titan
   track. Typing `jjk` shows every Jujutsu Kaisen track. Typing `sao`
   shows Sword Art Online, and so on. Search tolerates acronyms, hand-
   curated aliases, and out-of-order tokens, and ranks results so the
   most relevant matches rise to the top.
2. **Scoped playback.** When the user plays a track from a search, the
   play queue is captured as *that search's results*. Shuffle randomizes
   within the scope. Next/previous cycle within the scope. The queue
   snaps back to the full library only when the user explicitly clears
   scope — not when they clear the search box.
3. **Optional: themed ambient background.** When the active scope maps
   to a known show (AOT, JJK, etc.), the root view gets a blurred
   ambient backdrop derived from a representative track's artwork. No
   new art assets are bundled; everything flows through the existing
   `ArtworkCache`.

### 1.2 What Wave 3 does NOT build (revision from roadmap)

- **No conventional album view.** Track metadata is derived lazily from
  titles for search purposes; there is no albums list, no album detail
  page, no Track → Album relationship surfaced in the UI.
- **No user playlists.** Playlists are deferred. If they're added later,
  they can plug in as another "scope source."
- **No smart playlists or sidebar navigation.** Both were speculative in
  the roadmap and are dropped. The main view remains a single searchable
  list with a filter picker; Wave 4's expanded player continues to fit
  naturally on top of that layout.

These removals are deliberate: search-plus-scope covers roughly the same
user intent ("I want to hear only the Attack on Titan stuff") with far
less structural surface area, and it avoids reshaping `ContentView` in a
way that would collide with Wave 4.

---

## 2. Architectural pivot

Revising Wave 3 this way has concrete consequences for the branch model
in `BRANCHING.md`:

| Original Wave 3 plan                 | Revised Wave 3 plan                 |
| ------------------------------------ | ----------------------------------- |
| Major edits to `ContentView` (sidebar host) | Minor edits to `ContentView` (search wiring, scope indicator, optional ambient bg) |
| `LibraryStore` gains grouping        | `LibraryStore` unchanged; derivation lives in a new `SearchEngine`/`ShowCatalog` |
| `Track` gains `show`, `album`, etc.  | `Track` gains `show` only (still compatible with the ownership map) |
| `TrackListView` becomes one of several list sources | `TrackListView` gets a small edit to pass scope on tap |
| New `Playlist` type, persisted        | No `Playlist`. `PlaybackScope` is an in-memory concept with a lightweight persisted form (`lastScopeQuery`). |

The parallelization matrix improves under the revised plan:

- **Wave 3 × Wave 4** was 🔴 because both reshape `ContentView`. Under
  this plan Wave 3's edits to `ContentView` are additive (a toolbar chip
  and an optional background layer) and leave Wave 4's expansion-gesture
  plans untouched. This moves the cell from 🔴 to 🟡.
- **Wave 3 × non-wave** stays at 🟡: any non-wave feature touching
  `ContentView` or `TrackListView` should still coordinate, but the
  footprint is small enough that coordination is cheap.

`PlayerBarView` remains owned by Wave 2 → Wave 4 per BRANCHING.md. Wave
3 does **not** edit it. The scope-indicator chip lives in `ContentView`
above the player bar.

---

## 3. Feature 1 — Search engine

### 3.1 Capabilities

In priority order, the search engine supports:

1. **Exact substring match** on the track title. This is what we have
   today; it stays the baseline so no existing query regresses.
2. **Curated alias match.** A hand-maintained table maps short strings
   to canonical show names: `AOT → Attack on Titan`, `JJK → Jujutsu
   Kaisen`, `SAO → Sword Art Online`, and so on. An alias hit matches
   every track whose derived show equals the canonical name.
3. **Acronym match** against the derived show name. For shows not in
   the alias table, a query that's all uppercase letters (`BNHA`) is
   matched against the first letters of the show's word tokens. This
   makes the alias table optional rather than mandatory.
4. **Token match.** Split the query on whitespace; a track matches if
   every token appears somewhere in its title or derived show. This
   handles "titan attack" matching "Attack on Titan" and "sao
   alicization" narrowing within SAO tracks.
5. **Fuzzy fallback (deferred).** Levenshtein-style typo tolerance is
   explicitly out of scope for Wave 3. Good ranking on the four rules
   above is cheaper and covers the common cases.

### 3.2 Ranking

Each candidate track is scored and sorted descending; ties break by the
existing library index (ascending). A rough scoring model:

| Signal                                        | Score |
| --------------------------------------------- | ----- |
| Query is an alias matching this track's show  |  100  |
| Query is a substring of the title             |   80  |
| Query is a substring of the derived show      |   70  |
| Query is an acronym of the derived show       |   60  |
| Every token of the query appears in title     |   40  |
| Every token of the query appears in title+show|   25  |
| None of the above                             |    0  |

A track scoring 0 is excluded. Numbers are illustrative; they'll be
tuned against the bundled library once the engine lands, with tests
locking in the expected top-k for a few fixture queries (see §7).

### 3.3 New files

- `Services/SearchEngine.swift` — pure `struct` with a single public
  entry point `rank(_ query: String, in tracks: [Track]) -> [Track]`.
  No Combine, no SwiftUI, no I/O. Trivially testable.
- `Services/ShowCatalog.swift` — the alias table and the derivation
  rules for `Track.show`. Also exposes `canonicalShow(for query:) ->
  String?` so the themed-background feature can ask "does this query
  resolve to a known show?"

### 3.4 Edits to existing files

- `Models/Track.swift` — add a computed property `var show: String?`
  that parses the title using rules in `ShowCatalog`. Owned by Wave 3
  per the existing ownership map, so this edit is expected.
- `Views/ContentView.swift` — replace the inline
  `localizedCaseInsensitiveContains` with `SearchEngine.rank(...)`.

### 3.5 `Track.show` derivation

Looking at the bundled library, most titles follow one of two shapes:

- `<song> - <show> <descriptor> [Piano]` (majority)
- `<song> - <show ><movie/special tag> [Piano]`

The derivation strategy is a small ordered list of patterns applied to
the title (everything between the leading `NNN - ` — which is already
stripped in `Track.init` — and the trailing `[Piano]` bracket). The
rules live in `ShowCatalog` so they can be extended without changing
`Track`, and `show` returns `nil` when nothing matches. Tests lock in
the expected derivation for a representative slice of the bundled
library's 165 titles.

### 3.6 Alias table

The initial alias set, covering the most common acronyms in the bundled
library:

```
AOT   → Attack on Titan
JJK   → Jujutsu Kaisen
SAO   → Sword Art Online
FMA   → Fullmetal Alchemist
MHA   → My Hero Academia
BNHA  → My Hero Academia
CSM   → Chainsaw Man
KnY   → Demon Slayer
NGE   → Neon Genesis Evangelion
FSN   → Fate/stay night
KLK   → Kill la Kill
JJBA  → JoJo's Bizarre Adventure
NGNL  → No Game No Life
MiA   → Made in Abyss
HxH   → Hunter x Hunter
```

The table is a `static let` on `ShowCatalog` and grows by code edit
(not user input) in Wave 3. If user-editable aliases are wanted later,
they fit naturally into `PersistenceStore.State` without touching the
engine.

---

## 4. Feature 2 — Scoped playback

### 4.1 Concepts

A `PlaybackScope` captures *which subset of the library the user is
currently listening through*. Examples:

- `.all` — every track. This is today's behavior and stays the default.
- `.favorites` — heart-filtered view.
- `.recent` — recently-played view.
- `.search(query: String, results: [Track])` — the key new variant.

The search variant carries both the text that produced it and the
snapshot of results at that moment, so the scope remains stable even if
the library is reloaded.

### 4.2 What changes behaviorally

- **Play intent.** Today, `player.play(track)` jumps within the full
  library queue. Wave 3 introduces `player.play(track, inScope:
  PlaybackScope)`; the existing signature becomes a thin wrapper that
  preserves today's semantics (`.all`). The new entry point is what the
  list and the filter picker call.
- **Shuffle.** Already works: when the queue is replaced with a scope's
  tracks, `PlayQueue.setShuffled(true)` shuffles indices into *that*
  list. No changes to `PlayQueue` needed.
- **Next / Previous.** Unchanged — they already cycle over whatever is
  in the queue. That's the whole reason this design is cheap.
- **Repeat modes.** Unchanged. `.all` wraps within the current scope;
  `.off` stops at the end of the current scope; `.one` repeats the
  current track. All of this is already inside
  `PlayQueue.advanceForFinish(repeatMode:)`.
- **Clearing scope.** Explicit user action (the X on the scope chip, or
  a `Scope → All Tracks` menu item). On clear, the queue is rebuilt
  from the full library, preserving the currently-playing track at its
  current position.

### 4.3 Search vs. scope are separate

This is the load-bearing UX decision of Wave 3. The search box is a UI
filter on what's *visible*. The scope is what's *playing*. They're
coupled at the moment of pressing play and decoupled thereafter:

| Action                                          | Effect on visible list | Effect on scope |
| ----------------------------------------------- | ---------------------- | --------------- |
| Type `AOT`                                      | Filters to AOT         | No change       |
| Tap an AOT track                                | Plays it               | Scope ← AOT     |
| Clear the search box                            | Shows full library     | **No change**   |
| Tap X on the scope chip                         | No change              | Scope ← All     |
| Switch filter picker to Favorites               | Shows favorites        | No change       |
| Tap a favorites track                           | Plays it               | Scope ← Favorites |

Consequence: the user can search for AOT, start it playing, clear
search to look for something else, and keep hearing AOT music until
they explicitly break scope. This matches how people actually listen.

### 4.4 New / edited files

New:

- `Models/PlaybackScope.swift` — the enum + a `displayName` and
  `tracks` accessor. `Equatable`, `Hashable` so SwiftUI `.animation`
  modifiers work against it.
- `Views/ScopeIndicator.swift` — the chip that renders above the
  player bar when scope is anything other than `.all`. Stays out of
  `PlayerBarView.swift` by design (§2).

Edited:

- `ViewModels/PlayerViewModel.swift` — Wave 3 state block and
  `bindWave3()` method; scope-aware play intents; scope persistence.
  Additive per chokepoint rule #2.
- `Views/ContentView.swift` — pass scope through; render scope
  indicator above the player bar in the `.safeAreaInset(edge: .bottom)`
  composition.
- `Views/TrackListView.swift` — the tap handler becomes scope-aware,
  reading scope from a closure or an environment value rather than
  assuming `.all`.
- `Services/PersistenceStore.swift` — Wave 3 block, additive per
  chokepoint rule #1.

**`PlayQueue.swift` does not change.** This is by design: the queue
already operates on whatever list it's given, and the scope is a
higher-level concept. Keeping `PlayQueue` untouched also avoids
touching territory owned by Wave 2.

---

## 5. Feature 3 — Themed ambient background (optional, recommended)

Recommendation: **ship a minimal version.** Reuse what we already have.

### 5.1 Minimal feasible version

When the current scope is `.search(...)` and `ShowCatalog` maps it to a
known canonical show, pick a single representative track for that show
(rule: the first by index in the current library) and load its
full-size artwork through `ArtworkCache`. Apply the same blur/saturate
treatment the player bar uses for its background, behind the main
content of `ContentView`, at low opacity (~0.25). When scope changes,
cross-fade. When scope isn't a known show, render nothing — the
background stays the usual system material.

That's it. No new assets, no new cache tier, no network calls. The
existing `ArtworkCache` handles keying (`url × size`), memory caps, and
race-safe loading; we just ask it for one more image.

### 5.2 What would push this out of scope

- Curating hand-picked hero images per show. Too much asset work for a
  personal library.
- Procedurally generating collage backgrounds from multiple tracks.
  This is a Wave 4 concern (ArtworkCache is owned by Wave 4 per the
  ownership map), and interferes with their planned collage work.
- Animated backgrounds. Wave 4's expanded player is where animation
  design happens. Wave 3 stays static.

### 5.3 Kill-switch

A single `@AppStorage("showThemedBackgrounds")` flag toggles the whole
behavior from the settings surface (or, for Wave 3, a hidden
long-press). Setting it to false reverts `ContentView` to today's
appearance.

If implementing the minimal version blows past a day of work, drop it.
Nothing else in Wave 3 depends on it.

---

## 6. File-by-file change summary

| File                               | Action       | Owner | Notes                                   |
| ---------------------------------- | ------------ | ----- | --------------------------------------- |
| `Services/SearchEngine.swift`      | **new**      | W3    | Pure logic + ranking.                   |
| `Services/ShowCatalog.swift`       | **new**      | W3    | Alias table + `Track.show` rules.       |
| `Models/PlaybackScope.swift`       | **new**      | W3    | Enum + display helpers.                 |
| `Views/ScopeIndicator.swift`       | **new**      | W3    | Chip above player bar.                  |
| `Views/AmbientBackground.swift`    | **new** (opt)| W3    | Themed background for known shows.      |
| `Models/Track.swift`               | edit         | W3    | Add `show` computed property.           |
| `Services/PersistenceStore.swift`  | edit (shared)| —     | Chokepoint #1: append Wave 3 block.     |
| `ViewModels/PlayerViewModel.swift` | edit (shared)| —     | Chokepoint #2: append Wave 3 block + `bindWave3()`. |
| `Views/ContentView.swift`          | edit         | W3    | Search → `SearchEngine`; scope indicator; optional ambient bg. |
| `Views/TrackListView.swift`        | edit         | W3    | Tap handler is scope-aware.             |
| `Views/PlayerBarView.swift`        | **not edited** | W2→W4 | Wave 3 stays out per §2.              |
| `Services/PlayQueue.swift`         | **not edited** | W2  | Already sufficient.                     |
| `Services/PlaybackEngine.swift`    | **not edited** | W2  | No protocol changes needed.             |

---

## 7. Branch plan

Stacked on `wave/3-collections`, in merge order:

| Branch                             | Adds                                            | Depends on |
| ---------------------------------- | ----------------------------------------------- | ---------- |
| `feature/3a-show-derivation`       | `ShowCatalog`, `Track.show`, derivation tests.  | —          |
| `feature/3b-search-engine`         | `SearchEngine`, ranking tests.                  | 3a         |
| `feature/3c-search-ui`             | Wire `SearchEngine` into `ContentView`; visible list uses ranked results. *No scoped playback yet.* | 3b         |
| `feature/3d-playback-scope`        | `PlaybackScope`, `ScopeIndicator`, scope-aware play intents, `bindWave3`, persistence. | 3c         |
| `feature/3e-themed-background` (opt)| `AmbientBackground` + wiring; kill-switch.     | 3d         |

Each branch merges back into `wave/3-collections` after its own tests
pass. The wave itself merges to `main` after 3a–3d are green. 3e is
optional and can merge as a follow-up PR to `main` after the wave
lands, or be dropped entirely without affecting the wave's value.

This ordering also minimizes rebase pain if any in-flight non-wave
work touches the search or list UI: 3a and 3b are purely additive, so
they can merge early and often.

---

## 8. Testing gates

Every new module gets a focused test file. Extensions to existing
tests are listed where relevant.

### 8.1 New test files

- `ShowCatalogTests.swift` (with 3a)
  - `Track.show` derivation for 10–15 representative title shapes from
    the bundled library.
  - Canonical resolution: `canonicalShow(for: "AOT") == "Attack on
    Titan"`, case-insensitive.
  - Unknown queries return nil.

- `SearchEngineTests.swift` (with 3b)
  - Empty query returns all tracks in library order.
  - Exact substring queries return today's behavior unchanged
    (regression guard).
  - Alias queries (`"AOT"`, `"jjk"`) return the expected set.
  - Acronym match on a show not in the alias table.
  - Token order independence: `"titan attack"` ranks AOT tracks highly.
  - Ranking: for a fixed fixture library, the top-3 results for each of
    `"aot"`, `"jjk"`, `"frieren"`, `"one piece"` are locked to known
    lists. This catches silent ranking regressions.

- `PlaybackScopeTests.swift` (with 3d)
  - Playing from `.search` scope limits `next()` cycling to scope
    tracks, wrapping at the end.
  - Shuffle within scope preserves scope membership after a full cycle.
  - Clearing scope preserves the currently-playing track at its
    position.
  - `RepeatMode.all` wraps within scope, not across the full library.
  - `RepeatMode.off` stops at the end of scope, not the end of the
    library.

### 8.2 Extensions to existing test files

- `PlayerViewModelTests.swift`
  - A new section `// MARK: - Wave 3: Scoped playback` with the three
    or four cases that specifically exercise the coordinator wiring
    (as opposed to the pure scope logic above).
  - Persistence restore with a saved scope: on init, if
    `lastScopeQuery` is non-nil, the coordinator re-applies the scope
    after `restoreFromPersistence`.

- `PlayQueueTests.swift`
  - No new cases expected — `PlayQueue` doesn't change. If something
    breaks here, we've violated §2.

The rule from `BRANCHING.md` still holds: the existing
`PlayerViewModelTests` and `PlayQueueTests` suites stay green with
*additions only*, never edits to existing cases. Anything that forces
an existing test to change signals we've accidentally shifted a Wave 1
or Wave 2 contract.

---

## 9. Persistence additions (chokepoint rule compliance)

Per chokepoint rule #1 in `BRANCHING.md`, the new fields go in a
contiguous `// MARK: Wave 3` block at the end of `State`, every field
has a default, nothing is renamed or removed:

```swift
struct State: Codable, Equatable {
    // MARK: Wave 1
    var lastTrackURL: URL?
    var lastPosition: Double = 0
    var isShuffled: Bool = false

    // MARK: Wave 2
    var repeatMode: RepeatMode = .off
    var favorites: Set<URL> = []
    var recentlyPlayed: [URL] = []

    // MARK: Wave 3
    /// The query that produced the current playback scope, if any. On
    /// relaunch, this is re-applied so the user's session continues in
    /// the same scope. Nil means the scope is `.all`.
    var lastScopeQuery: String? = nil
    /// Whether themed ambient backgrounds are enabled (Wave 3 §5.3).
    /// Defaulted to `true`; the feature is off if §5 is cut entirely.
    var themedBackgroundsEnabled: Bool = true
}
```

Old state files predating Wave 3 decode cleanly because both new
fields are defaulted.

`.favorites`, `.recent`, and `.search` scopes are all re-derivable from
other state, so only the search query needs persisting.

---

## 10. `PlayerViewModel` block (chokepoint rule compliance)

Per chokepoint rule #2, Wave 3 gets its own contiguous block of
`@Published` state and a dedicated `bindWave3()` method called from
`init`. Sketch:

```swift
// MARK: - Wave 3 state

@Published private(set) var currentScope: PlaybackScope = .all
@Published var searchQuery: String = ""  // UI-bound; derived results live in ContentView

// ... intent methods: play(_:inScope:), clearScope(), ...

private func bindWave3() {
    // Restore last scope if one was saved. If the query no longer
    // resolves to any tracks (e.g. library changed), fall back to `.all`.
    if let q = persistence.state.lastScopeQuery {
        let results = SearchEngine.rank(q, in: library.tracks)
        if !results.isEmpty {
            currentScope = .search(query: q, results: results)
        }
    }

    // Persist scope changes (query only; results are re-derived on restore).
    $currentScope
        .dropFirst()
        .sink { [weak self] scope in
            let query: String? = {
                if case .search(let q, _) = scope { return q }
                return nil
            }()
            self?.persistence.update { $0.lastScopeQuery = query }
        }
        .store(in: &cancellables)
}
```

No edits to `bindEngine`, `bindLibrary`, or `bindWave2`. `bindWave3()`
is additive and called from both the designated initializer and the
Wave-1-compatible convenience init, immediately after `bindWave2()`.

---

## 11. Risks and open questions

### 11.1 Ranking quality against the bundled library

Ranking rules that look sensible on paper can produce surprising top-k
results on a specific library. Mitigation: the locked top-3 tests in
`SearchEngineTests` act as a quality gate, and the ranking constants
live in one place so tuning is a single PR.

### 11.2 Scope drift across library reloads

If `LibraryStore` re-scans (today only at init; in a hypothetical
future, on user action), the snapshot of tracks in a
`.search(results:)` scope can point to stale URLs. The coordinator
filters scope tracks against the current library before handing them
to the queue, so stale entries silently disappear rather than producing
playback errors. A test in `PlayerViewModelTests` covers this.

### 11.3 Feature flag hygiene for themed backgrounds

If 5.3's kill-switch is on by default but the feature is cut mid-wave,
old state files will have `themedBackgroundsEnabled = true` referring
to absent code. This is harmless — the view just doesn't read the flag
— but worth noting so someone doesn't "fix" the unused field and
violate the append-only rule.

### 11.4 Surface for user-provided aliases

Some users will want `"JJK2" → "Jujutsu Kaisen S2"` or similar custom
aliases. Wave 3 doesn't build a UI for this because adding editable
tables and their persistence would blow out the scope. A future wave
can add `State.userAliases: [String: String]` and a settings screen;
`ShowCatalog` is already the single place that consumes them.

### 11.5 Interaction with Wave 4's planned restructure

Wave 4 will add matched-geometry transitions from the mini player bar
to an expanded full-screen player, which means reshaping
`ContentView`'s composition. Wave 3's scope indicator and ambient
background are positioned *outside* the player bar and *inside*
`ContentView` for this exact reason — Wave 4 can re-parent the player
bar without having to migrate any Wave 3 surfaces. This is why §2's
matrix upgrade from 🔴 to 🟡 holds.

---

## 12. Sequencing notes for AI-assisted or parallel work

Following the AI-assistant guidance in `BRANCHING.md`:

1. **Sessions working on Wave 3 should start from this doc plus the
   ownership map.** Paste both at the beginning of each session. The
   model otherwise tends to "helpfully" refactor `PlayerBarView` or
   fold Wave 2's `bindRemote` into `bindWave3`, both of which violate
   §2 and chokepoint rule #2.
2. **Forbid edits to `PlayerBarView.swift` and `PlayQueue.swift`.**
   These are the two files most at risk of accidental drift. Making
   this an explicit constraint up front is load-bearing.
3. **Prefer new files over edits.** `SearchEngine`, `ShowCatalog`,
   `PlaybackScope`, `ScopeIndicator`, and `AmbientBackground` are all
   new. The surface of *edits* is deliberately small.
4. **Land 3a and 3b behind tests only before touching any view code.**
   The search engine is the load-bearing piece; if its behavior isn't
   locked down by tests before UI work starts, every UI session will
   drift the ranking under the model's feet.
5. **Don't run Wave 3 in parallel with any branch that edits
   `ContentView` or `Track`.** Non-wave work that touches either file
   should queue behind Wave 3's merge, per the 🟡 rule in the revised
   matrix.

---

When Wave 3 merges, the README's Roadmap section (§"Roadmap") should be
updated to reflect the revised wave (search + scope, not albums +
playlists), and `BRANCHING.md`'s parallelization matrix updated to
reflect the new Wave 3 × Wave 4 relationship (🔴 → 🟡).
