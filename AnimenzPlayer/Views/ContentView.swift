import SwiftUI

/// Top-level view. Hosts the track list, player bar, error banner, and
/// (Wave 2) a filter picker to switch between All / Favorites / Recently
/// Played.
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

    /// The tracks to display, after filter + search.
    private var filteredTracks: [Track] {
        let base: [Track]
        switch filter {
        case .all:       base = player.tracks
        case .favorites: base = player.favoriteTracks
        case .recent:    base = player.recentlyPlayedTracks
        }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if player.tracks.isEmpty {
                    emptyState
                } else if filteredTracks.isEmpty {
                    filterEmptyState
                } else {
                    TrackListView(tracks: filteredTracks, searchText: $searchText)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentTrack != nil {
                PlayerBarView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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
            Image(systemName: filter.systemImage)
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

    private var filterEmptyTitle: String {
        switch filter {
        case .all:       return "No tracks match"
        case .favorites: return "No favorites yet"
        case .recent:    return "Nothing played yet"
        }
    }

    private var filterEmptyMessage: String {
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
