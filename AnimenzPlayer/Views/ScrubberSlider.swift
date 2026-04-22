import SwiftUI

/// Playback scrubber that decouples the thumb from engine updates while the
/// user is dragging. The scrubber has two modes:
///
/// - **Idle**: the thumb tracks `progress` live (so it advances during
///   playback).
/// - **Dragging**: the thumb follows the user's input only. Engine-driven
///   `progress` updates don't move it, and no seek is issued. When the user
///   releases, we commit one seek via `onCommit`.
///
/// This fixes two bugs in the naive `Slider(value: Binding(get:set:))`
/// approach: (1) the thumb snapping back during drag because the engine's
/// progress stream kept overwriting it, and (2) the audio stuttering because
/// every drag delta fired a sample-accurate AVPlayer seek.
struct ScrubberSlider: View {
    let progress: Double
    let duration: Double
    let onCommit: (Double) -> Void

    /// Thumb position while the user is dragging. `nil` when idle.
    @State private var dragValue: Double?

    /// The value the slider displays. During drag this is `dragValue`;
    /// otherwise it's the live engine `progress`. Clamped to the valid range.
    private var visibleValue: Double {
        let v = dragValue ?? progress
        return min(max(v, 0), max(duration, 0.01))
    }

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { visibleValue },
                    set: { newValue in
                        // Only update local drag state here; don't touch the
                        // engine until the drag ends.
                        dragValue = newValue
                    }
                ),
                in: 0...max(duration, 0.01),
                onEditingChanged: { editing in
                    if !editing {
                        // Drag released — commit the seek and release the
                        // thumb back to engine-driven updates.
                        if let final = dragValue {
                            onCommit(final)
                        }
                        dragValue = nil
                    }
                }
            )
            .tint(.primary.opacity(0.75))
            .accessibilityLabel("Playback position")

            HStack {
                Text(formatTime(visibleValue))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
