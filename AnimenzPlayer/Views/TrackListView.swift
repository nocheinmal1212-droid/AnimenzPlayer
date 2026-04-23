import SwiftUI

struct TrackListView: View {
    let tracks: [Track]
    @Binding var searchText: String

    /// The scope to apply when the user plays a track from this list. Owned
    /// by the parent (ContentView) because it depends on filter + search
    /// state the list itself doesn't know about.
    let scope: PlaybackScope

    @EnvironmentObject var player: PlayerViewModel

    var body: some View {
        List(tracks) { track in
            TrackRow(track: track)
                .listRowSeparator(.hidden)
                .contentShape(Rectangle())
                .onTapGesture {
                    player.play(track, inScope: scope)
                    Haptics.play(.selection)
                }
                .contextMenu {
                    Button {
                        player.toggleFavorite(track)
                    } label: {
                        Label(
                            player.isFavorite(track)
                                ? "Remove from Favorites"
                                : "Add to Favorites",
                            systemImage: player.isFavorite(track) ? "heart.slash" : "heart"
                        )
                    }
                    Button {
                        player.play(track, inScope: scope)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                }
        }
        // Let the ambient background show through when the surrounding
        // ContentView has one. iOS 16+/macOS 13+.
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .listStyle(.plain)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always)
        )
        #else
        .searchable(text: $searchText)
        #endif
    }
}

private struct TrackRow: View {
    let track: Track
    @EnvironmentObject var player: PlayerViewModel
    @State private var artwork: PlatformImage?

    private var isCurrent: Bool { player.currentTrack == track }
    private var isFavorite: Bool { player.isFavorite(track) }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(image: artwork, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Color.pink)
                            .font(.caption2)
                            .accessibilityLabel("Favorite")
                    }
                    Text(track.title)
                        .lineLimit(1)
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                        .fontWeight(isCurrent ? .semibold : .regular)
                }
                Text(track.index == Int.max ? "—" : String(format: "#%03d", track.index))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isCurrent {
                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption)
                    .accessibilityLabel(player.isPlaying ? "Now playing" : "Paused")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .task(id: track.id) {
            artwork = await ArtworkCache.image(for: track, size: .thumbnail)
        }
    }
}
