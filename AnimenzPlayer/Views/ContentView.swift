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
    /// so typing "AOT" returns Attack on Titan tracks, etc. Empty query =
    /// baseTracks in their natural order.
    private var filteredTracks: [Track] {
        SearchEngine.rank(searchText, in: baseTracks)
    }

    /// The scope that should be captured when the user starts playback
    /// right now. Rule: a non-empty search always wins (scope becomes
    /// `.search`); otherwise it mirrors the filter picker.
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
        ZStack {
            // Wave 3: themed ambient background behind everything. Renders
            // nothing when scope doesn't resolve to a known show.
            AmbientBackground(scope: player.currentScope, library: player.tracks)
                .ignoresSafeArea()

            NavigationStack {
                Group {
                    if player.tracks.isEmpty {
                        emptyState
                    } else if filteredTracks.isEmpty {
                        filterEmptyState
                    } else {
                        TrackListView(
                            tracks: filteredTracks,
                            searchText: $searchText,
                            scope: currentPlayScope
                        )
                    }
                }
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
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                // Wave 3: scope indicator. Only meaningful when there's a
                // track to play from scope, so we gate on currentTrack too.
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
                    .transition(
                        .move(edge: .top).combined(with: .opacity)
                    )
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

    // MARK: - Subviews

    /// Segmented picker for the list filter. Iconified to keep it compact
    /// in the nav bar on iOS.
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

    /// Shown when the current filter returns no tracks but the library
    /// itself has tracks. Different copy per filter because the remedy differs.
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

    /// Search-aware icon: if the user is searching, show a magnifier;
    /// otherwise show the filter's icon.
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
