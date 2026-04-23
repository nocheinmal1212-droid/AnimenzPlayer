import SwiftUI

/// Top-level view. Hosts the track list, player bar, error banner, filter
/// picker, and (Wave 3) search-driven ranking, scope indicator, and themed
/// ambient background.
struct ContentView: View {
    @EnvironmentObject var player: PlayerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""

    // MARK: - Wave 2 state

    enum ListFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case favorites = "Favorites"
        case recent = "Recent"
        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .all:       return "music.note.list"
            case .favorites: return "heart.fill"
            case .recent:    return "clock.fill"
            }
        }
    }

    @State private var filter: ListFilter = .all

    // MARK: - Derived

    /// Base list of tracks per the current filter (before search ranking).
    private var baseTracks: [Track] {
        switch filter {
        case .all:       return player.tracks
        case .favorites: return player.favoriteTracks
        case .recent:    return player.recentlyPlayedTracks
        }
    }

    /// The tracks to display. Wave 3: search goes through `SearchEngine.rank`
    /// so typing "AOT" returns Attack on Titan tracks, etc.
    private var filteredTracks: [Track] {
        SearchEngine.rank(searchText, in: baseTracks)
    }

    /// The scope to capture when the user starts playback right now. A
    /// non-empty search wins; otherwise it mirrors the filter picker.
    private var currentPlayScope: PlaybackScope {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return .search(query: trimmed, results: filteredTracks)
        }
        switch filter {
        case .all:       return .all
        case .favorites: return .favorites
        case .recent:    return .recent
        }
    }

    // MARK: - Body

    var body: some View {
        // Structure notes — three iterations of bugs, now fixed:
        //
        // Iteration 1 (broken):
        //   Put `.searchable` on `TrackListView`. When search returned no
        //   results, TrackListView was swapped out, `.searchable` went with
        //   it, and on macOS the toolbar entered a state where the search
        //   field vanished AND the filter picker stopped accepting clicks.
        //
        // Iteration 2 (broken differently):
        //   Moved `.searchable` OUTSIDE the NavigationStack onto the outer
        //   view chain. That fixed the empty-state tear-down, but on macOS
        //   `.searchable` needs a navigation container to render into —
        //   placed outside, the search field simply never appears.
        //
        // Iteration 3 (this version):
        //   `.searchable` lives INSIDE the NavigationStack (so it has a
        //   toolbar) but attached to a stable wrapper view — a ZStack
        //   around the conditional content, which never unmounts. This is
        //   the canonical SwiftUI pattern:
        //
        //     NavigationStack {
        //       ZStack { if ... else ... }      ← stable host
        //         .searchable(text: $text)      ← survives content swaps
        //         .toolbar { ... }
        //     }
        //
        // AmbientBackground is layered via `.background { ... }` on the
        // NavigationStack so it paints beneath content without reshaping
        // the layout tree (which, in an earlier attempt using a sibling
        // ZStack + ignoresSafeArea, broke hit-testing and window chrome).
        NavigationStack {
            ZStack {
                contentBody
            }
            #if os(iOS)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always)
            )
            #else
            .searchable(text: $searchText)
            #endif
            .navigationTitle("Animenz")
            #if os(macOS)
            .navigationSubtitle(player.currentTrack?.title ?? "")
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    filterPicker
                }
            }
        }
        .background {
            AmbientBackground(scope: player.currentScope, library: player.tracks)
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomAccessories
        }
        .animation(
            .spring(duration: 0.4, bounce: 0.12),
            value: player.currentScope
        )
        .animation(
            .spring(duration: 0.45, bounce: 0.15),
            value: player.currentTrack != nil
        )
        .overlay(alignment: .top) {
            if let error = player.currentError {
                ErrorBanner(error: error) { player.currentError = nil }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: error.id) {
                        try? await Task.sleep(for: .seconds(5))
                        if player.currentError?.id == error.id {
                            player.currentError = nil
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: player.currentError?.id)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                player.flushPendingState()
            }
        }
    }

    // MARK: - Content

    /// The conditional content region. Lives inside a ZStack in `body` so
    /// modifiers like `.searchable` and `.toolbar` on the ZStack survive
    /// the list/empty-state swap.
    @ViewBuilder
    private var contentBody: some View {
        if player.tracks.isEmpty {
            emptyState
        } else if filteredTracks.isEmpty {
            filterEmptyState
        } else {
            TrackListView(
                tracks: filteredTracks,
                scope: currentPlayScope
            )
        }
    }

    /// Bottom safe-area inset: scope chip + player bar, stacked.
    @ViewBuilder
    private var bottomAccessories: some View {
        VStack(spacing: 8) {
            if player.currentScope.isRestricted, player.currentTrack != nil {
                ScopeIndicator(scope: player.currentScope) {
                    player.clearScope()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if player.currentTrack != nil {
                PlayerBarView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Subviews

    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            ForEach(ListFilter.allCases) { option in
                Label(option.rawValue, systemImage: option.systemImage)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No tracks found")
                .font(.headline)
            Text("Add audio files to the Music folder in the app bundle.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var filterEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: filterEmptyIcon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(filterEmptyTitle)
                .font(.headline)
            Text(filterEmptyMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var filterEmptyIcon: String {
        searchText.isEmpty ? filter.systemImage : "magnifyingglass"
    }

    private var filterEmptyTitle: String {
        if !searchText.isEmpty { return "No results" }
        switch filter {
        case .all:       return "No tracks match"
        case .favorites: return "No favorites yet"
        case .recent:    return "Nothing played yet"
        }
    }

    private var filterEmptyMessage: String {
        if !searchText.isEmpty {
            return "Try a different search term. Aliases like AOT, JJK, or SAO are supported."
        }
        switch filter {
        case .all:       return "Try a different search term."
        case .favorites: return "Tap the heart on any track to add it to favorites."
        case .recent:    return "Play a track and it'll show up here."
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PlayerViewModel(
            library: LibraryStore(autoload: false),
            engine: AVPlayerEngine(),
            persistence: PersistenceStore(fileURL: nil)
        ))
}
