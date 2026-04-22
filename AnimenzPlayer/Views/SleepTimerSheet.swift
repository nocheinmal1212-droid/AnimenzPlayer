import SwiftUI

/// Preset picker for the sleep timer. Presented as a sheet from the player
/// bar's repeat-button context menu. Keeps the main UI free of rarely-used
/// controls.
struct SleepTimerSheet: View {
    @EnvironmentObject var player: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    private struct Preset: Identifiable {
        let id = UUID()
        let label: String
        let mode: SleepTimer.Mode
    }

    private let presets: [Preset] = [
        .init(label: "5 minutes",          mode: .duration(5 * 60)),
        .init(label: "15 minutes",         mode: .duration(15 * 60)),
        .init(label: "30 minutes",         mode: .duration(30 * 60)),
        .init(label: "1 hour",             mode: .duration(60 * 60)),
        .init(label: "Until end of track", mode: .endOfTrack),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(presets) { preset in
                        Button {
                            player.startSleepTimer(preset.mode)
                            dismiss()
                        } label: {
                            HStack {
                                Text(preset.label)
                                Spacer()
                                if isSelected(preset.mode) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if player.sleepTimer.mode != nil {
                    Section {
                        Button(role: .destructive) {
                            player.cancelSleepTimer()
                            dismiss()
                        } label: {
                            Text("Cancel Sleep Timer")
                        }
                    }
                }
            }
            .navigationTitle("Sleep Timer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 300, minHeight: 360)
    }

    private func isSelected(_ mode: SleepTimer.Mode) -> Bool {
        guard let current = player.sleepTimer.mode else { return false }
        switch (current, mode) {
        case (.endOfTrack, .endOfTrack):
            return true
        case (.duration(let a), .duration(let b)):
            return abs(a - b) < 0.5
        default:
            return false
        }
    }
}

#Preview {
    SleepTimerSheet()
        .environmentObject(PlayerViewModel(
            library: LibraryStore(autoload: false),
            engine: AVPlayerEngine(),
            persistence: PersistenceStore(fileURL: nil)
        ))
}
