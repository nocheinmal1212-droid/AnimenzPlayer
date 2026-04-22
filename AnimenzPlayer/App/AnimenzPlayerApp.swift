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

/// Playback commands for the macOS menu bar.
///
/// Shortcut choices
/// ----------------
/// Several "obvious" shortcuts conflict with standard macOS view behavior
/// and must be avoided:
///
/// - `⌘ ←` / `⌘ →` are intercepted by `List` and text fields for
///   beginning/end-of-line navigation. Picking them for skip silently does
///   nothing when the list has focus.
/// - `⌘ L` is used by many sidebar-driven apps and, more importantly, by
///   `TextField` for "go to end of line"; it gets swallowed by the search
///   box even when the field isn't visually focused.
///
/// The choices below use `⌥⌘` modifiers, which no system view claims:
///
/// | Action              | Shortcut   |
/// | ------------------- | ---------- |
/// | Play / Pause        | Space      |
/// | Next track          | ⌥⌘ →       |
/// | Previous track      | ⌥⌘ ←       |
/// | Shuffle             | ⇧⌘ S       |
/// | Cycle repeat mode   | ⇧⌘ R       |
/// | Toggle favorite     | ⇧⌘ L       |
///
/// Buttons are *always* present (disabled when there's no current track)
/// rather than conditionally inserted. SwiftUI re-registers shortcuts
/// whenever the command tree changes; conditional buttons cause the
/// shortcut to flicker off and on and can fail to fire depending on
/// timing. Unconditional + `.disabled` is the reliable pattern.
struct PlaybackCommands: Commands {
    @ObservedObject var player: PlayerViewModel

    private var favoriteTitle: String {
        guard let track = player.currentTrack else {
            return "Add to Favorites"
        }
        return player.isFavorite(track)
            ? "Remove from Favorites"
            : "Add to Favorites"
    }

    var body: some Commands {
        CommandMenu("Playback") {
            Button(player.isPlaying ? "Pause" : "Play") {
                player.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Next Track") { player.next() }
                .keyboardShortcut(.rightArrow, modifiers: [.option, .command])

            Button("Previous Track") { player.previous() }
                .keyboardShortcut(.leftArrow, modifiers: [.option, .command])

            Divider()

            Button("Shuffle") { player.isShuffled.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Cycle Repeat Mode") { player.cycleRepeatMode() }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button(favoriteTitle) {
                if let track = player.currentTrack {
                    player.toggleFavorite(track)
                }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(player.currentTrack == nil)
        }
    }
}

#endif
