import SwiftUI

/// Subtle themed background: when the current scope is a search resolving to
/// a known show (via `ShowCatalog.canonicalShow(for:)`), we load artwork
/// from a representative track of that show, blur it heavily, and render at
/// low opacity behind the main content. When scope doesn't resolve to a
/// known show, renders nothing (callers see a transparent view).
///
/// This is the minimal implementation from WAVE3_PLAN §5.1:
/// - No new bundled assets — everything flows through the existing
///   `ArtworkCache`, keyed by `(track.url, size)`.
/// - No collage / procedural generation (those overlap with Wave 4).
/// - No animation beyond a simple cross-fade when scope changes.
///
/// Gated by `PersistenceStore.State.themedBackgroundsEnabled` via
/// `@AppStorage`. Setting that to false reverts the view to its default
/// appearance, no code changes required.
struct AmbientBackground: View {
    let scope: PlaybackScope
    let library: [Track]

    @State private var artwork: PlatformImage?
    @AppStorage("themedBackgroundsEnabled") private var enabled: Bool = true

    // MARK: - Resolution

    /// The track whose artwork drives the background. Resolution rule:
    /// 1. Scope is `.search`.
    /// 2. The query resolves to a known canonical show via `ShowCatalog`.
    /// 3. Pick the first library track whose derived show matches.
    /// Returns nil for all other cases.
    private var representativeTrack: Track? {
        guard enabled, case .search(let query, _) = scope else { return nil }
        guard let canonical = ShowCatalog.canonicalShow(for: query) else {
            // Fall back to show-name substring: if the user typed
            // "frieren" (not an alias), we can still theme based on that.
            let lower = query.lowercased().trimmingCharacters(in: .whitespaces)
            guard !lower.isEmpty else { return nil }
            return library.first { track in
                guard let show = track.show else { return false }
                return show.lowercased() == lower
                    || show.lowercased().contains(lower)
            }
        }
        return library.first { track in
            track.show?.caseInsensitiveCompare(canonical) == .orderedSame
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if let artwork {
                Image(platformImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 64)
                    .saturation(1.35)
                    .opacity(0.28)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: artwork != nil)
        .allowsHitTesting(false)
        .task(id: representativeTrack?.id) {
            await loadArtwork(for: representativeTrack)
        }
    }

    private func loadArtwork(for track: Track?) async {
        guard let track else {
            artwork = nil
            return
        }
        let loaded = await ArtworkCache.image(for: track, size: .full)
        // Guard against a stale load: the scope may have changed while we
        // were loading the image for the previous scope.
        guard representativeTrack?.id == track.id else { return }
        artwork = loaded
    }
}
