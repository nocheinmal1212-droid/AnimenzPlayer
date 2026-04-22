import SwiftUI

struct PlayerBarView: View {
    @EnvironmentObject var player: PlayerViewModel
    @State private var artwork: PlatformImage?

    var body: some View {
        VStack(spacing: 14) {
            ArtworkView(image: artwork, size: 160)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)

            nowPlayingTitle
            progressSlider
            controlButtons
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(barBackground)
        .clipped()                                  // belt — clips any residual overflow
        .overlay(alignment: .top) { topDivider }    // hairline separator from the list
        .task(id: player.currentTrack?.id) {
            await loadArtwork()
        }
    }

    // MARK: - Background

    /// Ambient blurred artwork layered on top of the material. Sized with a
    /// GeometryReader + explicit .frame so the image never reports its natural
    /// (potentially huge) dimensions back up the layout tree — which was the
    /// cause of the earlier bug where the blur overflowed upward and blocked
    /// clicks on the track list.
    private var barBackground: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(.regularMaterial)

                if let artwork {
                    Image(platformImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()                  // suspenders — clip before blur
                        .blur(radius: 48)
                        .saturation(1.4)
                        .opacity(0.35)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: artwork != nil)
        }
    }

    private var topDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .allowsHitTesting(false)
    }

    // MARK: - Subviews

    private var nowPlayingTitle: some View {
        VStack(spacing: 3) {
            Text(player.currentTrack?.title ?? "")
                .font(.headline)
                .lineLimit(1)
            Text(player.isPlaying ? "Now playing" : "Paused")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    @ViewBuilder
    private var progressSlider: some View {
        if player.duration > 0 {
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { player.progress },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 0.01)
                )
                .tint(.primary.opacity(0.75))

                HStack {
                    Text(formatTime(player.progress))
                    Spacer()
                    Text(formatTime(player.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Transport trio centered via HStack inside a ZStack; shuffle sits on the
    /// leading edge in an overlay. The play button stays on the optical center.
    private var controlButtons: some View {
        ZStack {
            HStack(spacing: 32) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .symbolRenderingMode(.hierarchical)
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                }
            }
            .buttonStyle(.plain)

            HStack {
                Button { player.isShuffled.toggle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(
                            player.isShuffled ? Color.accentColor : Color.primary.opacity(0.75)
                        )
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .font(.title2)
    }

    // MARK: - Loading

    @MainActor
    private func loadArtwork() async {
        artwork = nil
        guard let track = player.currentTrack else { return }
        let loaded = await ArtworkCache.image(for: track)
        // Guard against a race where the user skipped to another track while loading.
        guard player.currentTrack?.id == track.id else { return }
        artwork = loaded
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    PlayerBarView()
        .environmentObject(PlayerViewModel())
}
