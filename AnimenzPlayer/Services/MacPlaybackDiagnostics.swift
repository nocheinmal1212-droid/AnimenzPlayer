#if os(macOS)
import AppKit
import Combine
import CoreAudio
import UniformTypeIdentifiers

/// Owns app-lifetime macOS observers and the user-initiated export panel.
@MainActor
final class MacPlaybackDiagnostics: ObservableObject {
    static let shared = MacPlaybackDiagnostics()
    @Published private(set) var isExporting = false
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        _ = PlaybackDiagnostics.shared
        let appEvents: [(Notification.Name, String)] = [
            (NSApplication.didBecomeActiveNotification, "app.active"),
            (NSApplication.didResignActiveNotification, "app.inactive"),
            (NSApplication.willTerminateNotification, "session.end")
        ]
        for (name, event) in appEvents { observe(.default, name, event) }
        let workspaceEvents: [(Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, "system.sleep"),
            (NSWorkspace.didWakeNotification, "system.wake"),
            (NSWorkspace.screensDidSleepNotification, "screens.sleep"),
            (NSWorkspace.screensDidWakeNotification, "screens.wake"),
            (NSWorkspace.sessionDidResignActiveNotification, "system.session_inactive"),
            (NSWorkspace.sessionDidBecomeActiveNotification, "system.session_active")
        ]
        for (name, event) in workspaceEvents { observe(NSWorkspace.shared.notificationCenter, name, event) }
        var address = Self.outputAddress
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            PlaybackDiagnostics.record("audio.default_output_changed", Self.outputFields())
        }
        outputListener = listener
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        PlaybackDiagnostics.record("audio.output_observer", ["status": String(status)])
        PlaybackDiagnostics.record("audio.output_initial", Self.outputFields())
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ event: String) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            PlaybackDiagnostics.record(event, Self.outputFields())
            if event == "session.end" { PlaybackDiagnostics.shared?.flushBeforeExit() }
        }
        tokens.append((center, token))
    }

    // This singleton lives until process exit; listeners are registered once.
    nonisolated private static var outputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    nonisolated static func outputFields() -> [String: String] {
        var address = outputAddress
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        var fields = ["outputDevice": String(device), "outputQueryStatus": String(status)]
        guard status == noErr, device != 0 else { return fields }
        var alive: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsAlive
        let aliveStatus = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &alive)
        fields["deviceAlive"] = aliveStatus == noErr ? String(alive) : "unavailable"
        var rate = Float64(0)
        size = UInt32(MemoryLayout<Float64>.size)
        address.mSelector = kAudioDevicePropertyNominalSampleRate
        let rateStatus = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate)
        fields["deviceSampleRate"] = rateStatus == noErr ? String(rate) : "unavailable"
        return fields
    }

    func exportLog() {
        guard !isExporting else { return }
        guard let logger = PlaybackDiagnostics.shared else {
            showError("The diagnostics storage location is unavailable.")
            return
        }
        isExporting = true
        let panel = NSSavePanel()
        panel.title = "Export Debug Log"
        panel.message = "Save recent playback diagnostics, including retained logs from earlier launches."
        panel.nameFieldStringValue = "AnimenzPlayer-Debug-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else {
                self.isExporting = false
                return
            }
            Task { @MainActor in
                defer { self.isExporting = false }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try await logger.exportData()
                    try await Self.save(data, to: url)
                    PlaybackDiagnostics.record("export.completed", ["bytes": String(data.count)])
                } catch {
                    PlaybackDiagnostics.record("export.failed", PlaybackDiagnostics.errorFields(error))
                    self.showError("The debug log could not be saved. \(error.localizedDescription)")
                }
            }
        }
    }

    nonisolated private static func save(_ data: Data, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do { try data.write(to: url, options: .atomic); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t Export Debug Log"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
#endif
