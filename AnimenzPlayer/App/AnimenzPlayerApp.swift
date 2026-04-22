import SwiftUI

@main
struct AnimenzPlayerApp: App {
    @StateObject private var player = PlayerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .frame(minWidth: 500, minHeight: 600)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        // Wave 2 — macOS menu-bar commands with keyboard shortcuts.
        // Grouped under a "Playback" menu so they're discoverable.
        .commands {
            PlaybackCommands(player: player)
        }
        #endif
    }
}

#if os(macOS)

/// Playback commands for the macOS menu bar. Standard Mac shortcuts:
/// Space toggles play/pause, arrows for prev/next, ⌘⇧R for repeat, etc.
///
/// Note: Space is a valid SwiftUI shortcut but conflicts with any focused
/// text field. If the user is typing in the search box, space inserts a
/// space — correct behavior. When no field is focused, it toggles playback.
struct PlaybackCommands: Commands {
    @ObservedObject var player: PlayerViewModel

    var body: some Commands {
        CommandMenu("Playback") {
            Button(player.isPlaying ? "Pause" : "Play") {
                player.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Next Track") { player.next() }
                .keyboardShortcut(.rightArrow, modifiers: [.command])

            Button("Previous Track") { player.previous() }
                .keyboardShortcut(.leftArrow, modifiers: [.command])

            Divider()

            Button("Shuffle") { player.isShuffled.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Cycle Repeat Mode") { player.cycleRepeatMode() }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            if let track = player.currentTrack {
                Button(
                    player.isFavorite(track)
                        ? "Remove from Favorites"
                        : "Add to Favorites"
                ) {
                    player.toggleFavorite(track)
                }
                .keyboardShortcut("l", modifiers: [.command])
            }
        }
    }
}

#endif
