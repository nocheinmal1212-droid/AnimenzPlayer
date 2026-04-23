import SwiftUI

/// Playback scrubber. Decouples the thumb from engine updates while the
/// user is dragging, and smooths 4 Hz engine ticks into continuous motion
/// with a linear implicit animation between updates.
struct ScrubberSlider: View {
    @ObservedObject var progressModel: PlaybackProgressModel
    let duration: Double
    let onCommit: (Double) -> Void

    /// Thumb position while the user is dragging. `nil` when idle.
    @State private var dragValue: Double?

    private var visibleValue: Double {
        let v = dragValue ?? progressModel.progress
        return min(max(v, 0), max(duration, 0.01))
    }

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { visibleValue },
                    set: { dragValue = $0 }
                ),
                in: 0...max(duration, 0.01),
                onEditingChanged: { editing in
                    if !editing {
                        if let final = dragValue {
                            onCommit(final)
                        }
                        dragValue = nil
                    }
                }
            )
            .tint(.primary.opacity(0.75))
            .accessibilityLabel("Playback position")
            // The engine publishes progress at 4 Hz. Without this, the
            // thumb jumps ~0.25 s of distance per tick (teleport). A
            // linear animation matching the tick interval turns the four
            // discrete jumps into continuous motion. Disabled while
            // dragging so user input stays 1:1 with the finger.
            .animation(
                dragValue == nil ? .linear(duration: 0.25) : nil,
                value: progressModel.progress
            )

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
