import SwiftUI

/// Non-blocking banner for transient errors. Auto-dismisses after a few seconds
/// via `.task(id:)` in the parent view.
struct ErrorBanner: View {
    let error: PlayerError
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "An error occurred")
                    .font(.subheadline.weight(.medium))
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 12)
    }
}

#Preview {
    VStack {
        ErrorBanner(
            error: .loadFailed(url: URL(fileURLWithPath: "/tmp/song.m4a"), underlying: "Corrupt file"),
            dismiss: {}
        )
        Spacer()
    }
    .frame(width: 480, height: 200)
}
