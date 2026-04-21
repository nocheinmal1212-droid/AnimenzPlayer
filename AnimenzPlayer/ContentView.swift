import SwiftUI

struct ContentView: View {
    @EnvironmentObject var player: PlayerViewModel
    @State private var searchText = ""

    private var filteredTracks: [Track] {
        guard !searchText.isEmpty else { return player.tracks }
        return player.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if player.tracks.isEmpty {
                emptyState
            } else {
                TrackListView(tracks: filteredTracks, searchText: $searchText)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentTrack != nil {
                PlayerBarView()
                    .transition(
                        .move(edge: .bottom).combined(with: .opacity)
                    )
            }
        }
        .animation(
            .spring(duration: 0.45, bounce: 0.15),
            value: player.currentTrack != nil
        )
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
        .environmentObject(PlayerViewModel())
}
