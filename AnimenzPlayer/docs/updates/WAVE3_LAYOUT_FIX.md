# Wave 3 — Layout Fixes

Three files are updated to fix the glitches in the screenshot:

- `AnimenzPlayer/Views/ContentView.swift`
- `AnimenzPlayer/Views/TrackListView.swift`
- `AnimenzPlayer/Views/ScopeIndicator.swift`

**Replace just those three files** over your checkout. All other Wave 3
files (models, services, tests) are unchanged.

---

## What went wrong

### Glitch 1 — "Playing from: aot" captures all input; chrome is broken

Symptoms visible in the screenshot:
- Traffic lights rendered on top of the filter picker instead of in the
  title bar.
- Title bar itself is gone; a `#015` row fragment leaks into the top area.
- A large empty region under the scope chip with just the avatar floating.
- Can't interact with anything until the X on the chip is clicked.

**Root cause:** I wrapped `NavigationStack` in a `ZStack` with
`AmbientBackground().ignoresSafeArea()` as a sibling, then put
`.safeAreaInset(edge: .bottom)` on the `ZStack`. Three things went wrong:

1. The `NavigationStack` is no longer the root view, so the macOS
   `.hiddenTitleBar` window style (set in `AnimenzPlayerApp.swift`) loses
   its integration with the toolbar. Traffic lights end up drawn over
   toolbar content.
2. `.safeAreaInset` attached to the `ZStack` — whose safe area spans the
   entire window because of `.ignoresSafeArea()` on its first child —
   made the inset a full-width layer rather than docking under the nav
   container. Anything the inset draws (including its invisible padding
   area) captures hits over everything above it.
3. `PlayerBarView`'s internal `GeometryReader` background received a
   larger frame than expected, which is why the avatar artwork appears
   floating with no surrounding bar.

**Fix:** Put `AmbientBackground` in `.background { ... }` on the
`NavigationStack` instead of a sibling. `NavigationStack` stays the root;
the ambient layer paints beneath it without reshaping the layout tree or
the safe-area chain.

### Glitch 2 — Empty search freezes the whole toolbar

**Root cause:** `.searchable` was on `TrackListView`. When search returned
no matches, `TrackListView` was replaced by the empty-state placeholder
in the view tree, so `.searchable` was torn down with it. On macOS,
removing and re-adding `.searchable` mid-toolbar causes the toolbar to
enter a degraded state where buttons stop responding until the window is
rebuilt.

**Fix:** Hoist `.searchable` to the `NavigationStack` itself (outside
`contentBody`). The field now lives on a view that's always present, so
the toolbar never goes through the add/remove cycle. `TrackListView`
dropped its `searchText: Binding` parameter since it no longer owns the
field.

### Also fixed: "Playing from: aot" should say "Attack on Titan"

Good catch. The chip was echoing the raw query. Updated `ScopeIndicator`
to resolve the query through `ShowCatalog.canonicalShow(for:)` when it
matches an alias — so `aot` displays as **Attack on Titan**, `jjk` as
**Jujutsu Kaisen**, etc. Unresolvable queries still show the raw string
in quotes (e.g. `"rumbling"`).

The canonical lookup lives in the view, not in `PlaybackScope.displayName`,
so the model stays free of `ShowCatalog` dependency and the existing
`PlaybackScopeTests` don't need to change.

---

## Why this wasn't caught by the tests

The existing `PlayerViewModelTests` exercise coordinator logic (play /
pause / scope / next / etc.) with a `MockPlaybackEngine`, but there's no
SwiftUI view rendering involved. Layout bugs of this shape — toolbar
lifecycle, safe-area propagation, hit-testing through ZStack siblings —
only show up at runtime in a real window.

This isn't easy to fix inside XCTest. The better mitigation is the one
`BRANCHING.md` already recommends: **smoke-test layouts by running the
app**, not just by running tests. Lesson learned on my end: the first
pass tried to do too much in one commit (the ambient background + the
scope chip + the content-region changes) and the layout-restructure
subtlety was buried in among logic changes I was more confident about.

The split above (three small view files, nothing else) is a more
reviewable hunk.
