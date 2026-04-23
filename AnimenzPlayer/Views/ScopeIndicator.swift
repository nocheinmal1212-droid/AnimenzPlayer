import SwiftUI

/// Compact chip shown above the player bar whenever the current
/// `PlaybackScope` restricts playback to a subset of the library.
/// Displays the scope's name and an X to clear it.
///
/// Lives in its own file (rather than inside `PlayerBarView.swift`) because
/// `PlayerBarView` is owned by Wave 2 → Wave 4 per `BRANCHING.md`. Hosting
/// the indicator in `ContentView`'s bottom safe-area inset keeps Wave 3's
/// changes out of player-bar territory.
struct ScopeIndicator: View {
    let scope: PlaybackScope
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)

            Text("Playing from: ")
                .font(.caption)
                .foregroundStyle(.secondary)
            + Text(scope.displayName)
                .font(.caption.weight(.medium))
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
        ScopeIndicator(scope: .favorites, onClear: {})
    }
    .frame(width: 420, height: 220)
}
