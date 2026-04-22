import SwiftUI

struct ContentView: View {
    @EnvironmentObject var player: PlayerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""

    private var filteredTracks: [Track] {
        guard !searchText.isEmpty else { return player.tracks }
        return player.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if player.tracks.isEmpty {
                    emptyState
                } else {
                    TrackListView(tracks: filteredTracks, searchText: $searchText)
                }
            }
            .navigationTitle("Animenz")
            #if os(macOS)
            .navigationSubtitle(player.currentTrack?.title ?? "")
            #endif
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
}

#Preview {
    ContentView()
        .environmentObject(PlayerViewModel(
            library: LibraryStore(autoload: false),
            engine: AVPlayerEngine(),
            persistence: PersistenceStore(fileURL: nil)
        ))
}
