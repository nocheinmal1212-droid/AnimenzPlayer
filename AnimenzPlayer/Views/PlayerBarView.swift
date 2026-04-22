import SwiftUI

struct PlayerBarView: View {
    @EnvironmentObject var player: PlayerViewModel
    @State private var artwork: PlatformImage?
    @State private var showSleepTimerSheet = false

    var body: some View {
        VStack(spacing: 14) {
            ArtworkView(image: artwork, size: 160)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)

            nowPlayingTitle
            sleepTimerStrip
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
        .sheet(isPresented: $showSleepTimerSheet) {
            SleepTimerSheet()
                .environmentObject(player)
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

    /// Title + "Now playing" caption, with a heart to the right that toggles
    /// favorite. Symmetric spacer on the left keeps the title optically centered.
    private var nowPlayingTitle: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 28, height: 28)

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
            .frame(maxWidth: .infinity)

            if let track = player.currentTrack {
                Button {
                    player.toggleFavorite(track)
                } label: {
                    Image(systemName: player.isFavorite(track) ? "heart.fill" : "heart")
                        .foregroundStyle(
                            player.isFavorite(track)
                                ? Color.pink
                                : Color.primary.opacity(0.75)
                        )
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    player.isFavorite(track) ? "Remove from favorites" : "Add to favorites"
                )
            } else {
                Color.clear.frame(width: 28, height: 28)
            }
        }
    }

    /// Compact countdown strip shown only when a sleep timer is active.
    @ViewBuilder
    private var sleepTimerStrip: some View {
        if player.sleepTimer.mode != nil {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .font(.caption)

                Text(sleepTimerLabel)
                    .font(.caption.monospacedDigit())

                Spacer()

                Button {
                    player.cancelSleepTimer()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel sleep timer")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.08))
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var sleepTimerLabel: String {
        guard let mode = player.sleepTimer.mode else { return "" }
        switch mode {
        case .endOfTrack:
            return "Until end of track"
        case .duration:
            let r = max(0, Int(player.sleepTimer.remaining))
            let m = r / 60
            let s = r % 60
            return String(format: "Sleep in %d:%02d", m, s)
        }
    }

    @ViewBuilder
    private var progressSlider: some View {
        if player.duration > 0 {
            ScrubberSlider(
                progress: player.progress,
                duration: player.duration,
                onCommit: { player.seek(to: $0) }
            )
        }
    }

    /// Transport controls. Layout: [shuffle] [←] [⏯] [→] [repeat].
    /// Shuffle and repeat flank the transport trio symmetrically. Each button
    /// gets `frame(maxWidth: .infinity)` so they divide available width evenly.
    private var controlButtons: some View {
        HStack(spacing: 0) {
            Button { player.isShuffled.toggle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(
                        player.isShuffled ? Color.accentColor : Color.primary.opacity(0.75)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isShuffled ? "Shuffle on" : "Shuffle off")
            .frame(maxWidth: .infinity)

            Button {
                player.previous()
                Haptics.play(.impactSoft)
            } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")
            .frame(maxWidth: .infinity)

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .frame(maxWidth: .infinity)

            Button {
                player.next()
                Haptics.play(.impactSoft)
            } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
            .frame(maxWidth: .infinity)

            Button {
                player.cycleRepeatMode()
                Haptics.play(.selection)
            } label: {
                Image(systemName: player.repeatMode.systemImageName)
                    .foregroundStyle(
                        player.repeatMode.isActive
                            ? Color.accentColor
                            : Color.primary.opacity(0.75)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repeat mode: \(player.repeatMode.rawValue)")
            .contextMenu {
                Button("Off") { player.repeatMode = .off }
                Button("Repeat All") { player.repeatMode = .all }
                Button("Repeat One") { player.repeatMode = .one }
                Divider()
                Button("Sleep Timer…") { showSleepTimerSheet = true }
            }
            .frame(maxWidth: .infinity)
        }
        .font(.title2)
    }

    // MARK: - Loading

    @MainActor
    private func loadArtwork() async {
        artwork = nil
        guard let track = player.currentTrack else { return }
        let loaded = await ArtworkCache.image(for: track, size: .full)
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
        .environmentObject(PlayerViewModel(
            library: LibraryStore(autoload: false),
            engine: AVPlayerEngine(),
            persistence: PersistenceStore(fileURL: nil)
        ))
}
