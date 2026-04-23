import SwiftUI

/// Compact chip shown above the player bar whenever the current
/// `PlaybackScope` restricts playback to a subset of the library.
/// Displays the scope's name and an X to clear it.
///
/// For `.search` scopes we show the canonical show name when the query
/// resolves to one via `ShowCatalog` ("aot" → "Attack on Titan") rather
/// than echoing the raw query. This matches the user's mental model: they
/// typed an alias to *find* the show; the chip confirms which show.
struct ScopeIndicator: View {
    let scope: PlaybackScope
    let onClear: () -> Void

    /// The label shown after "Playing from: ". Prefers canonical show names
    /// over raw queries so the chip reads naturally.
    private var resolvedLabel: String {
        switch scope {
        case .all:        return "All Tracks"
        case .favorites:  return "Favorites"
        case .recent:     return "Recently Played"
        case .search(let query, _):
            if let canonical = ShowCatalog.canonicalShow(for: query) {
                return canonical
            }
            return "\"\(query)\""
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)

            Text("Playing from: ")
                .font(.caption)
                .foregroundStyle(.secondary)
            + Text(resolvedLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear playback scope")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(.regularMaterial)
        )
        .overlay(
            Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
        // Make the chip only as wide as its content. Without this the
        // HStack stretches to fill the safe-area-inset width, and its
        // transparent padding area captures clicks over the list.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack {
        Spacer()
        ScopeIndicator(
            scope: .search(query: "AOT", results: []),
            onClear: {}
        )
        ScopeIndicator(
            scope: .search(query: "Frieren", results: []),
            onClear: {}
        )
        ScopeIndicator(scope: .favorites, onClear: {})
    }
    .frame(width: 420, height: 280)
}
