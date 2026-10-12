#if os(macOS)
import Foundation
import AVFoundation

/// Passive AVPlayer instrumentation. Never changes playback or attempts recovery.
@MainActor
final class PlayerStateDiagnostics {
    private let player: AVPlayer
    private let logger: PlaybackDiagnostics?
    private var observations: [NSKeyValueObservation] = []
    private var itemObservations: [NSKeyValueObservation] = []
    private var itemTokens: [NSObjectProtocol] = []
    private var timer: Timer?
    private var requestedPlaying = false
    private var pendingSeeks = 0
    private var lastSample: (item: String, time: Double, uptime: Double, wallTime: Date)?

    init(player: AVPlayer, logger: PlaybackDiagnostics? = PlaybackDiagnostics.shared) {
        self.player = player
        self.logger = logger
        observations = [
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observed, _ in
                logger?.record("player.time_control", fields: ["new": String(observed.timeControlStatus.rawValue)])
                Task { @MainActor [weak self] in self?.snapshot("player.state") }
            },
            player.observe(\.rate, options: [.old, .new]) { _, change in
                logger?.record("player.rate", fields: ["old": String(change.oldValue ?? 0), "new": String(change.newValue ?? 0)])
            },
            player.observe(\.status, options: [.initial, .new]) { [weak self] player, _ in
                var fields = PlaybackDiagnostics.errorFields(player.error)
                fields["new"] = String(player.status.rawValue)
                logger?.record("player.status", fields: fields)
                Task { @MainActor [weak self] in self?.snapshot("player.state") }
            },
            player.observe(\.reasonForWaitingToPlay, options: [.new]) { observed, _ in
                logger?.record("player.waiting_reason", fields: ["reason": observed.reasonForWaitingToPlay?.rawValue ?? "none"])
            }
        ]
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        snapshot("player.created")
    }

    deinit {
        timer?.invalidate()
        observations.forEach { $0.invalidate() }
        itemObservations.forEach { $0.invalidate() }
        itemTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func setRequestedPlaying(_ playing: Bool) {
        requestedPlaying = playing
        if !playing { lastSample = nil }
    }

    func command(_ name: String) {
        if name == "play" { requestedPlaying = true }
        if name == "pause" || name == "stop" { requestedPlaying = false }
        lastSample = nil
        snapshot("engine.\(name)")
    }

    func seekStarted(_ id: String, target: Double) {
        pendingSeeks += 1
        logger?.record("engine.seek_started", fields: ["request": id, "target": String(target), "item": itemID])
    }

    func seekFinished(_ id: String, finished: Bool) {
        pendingSeeks = max(0, pendingSeeks - 1)
        lastSample = nil
        logger?.record("engine.seek_finished", fields: ["request": id, "finished": String(finished), "item": itemID])
    }

    func installed(_ item: AVPlayerItem, generation: Int) {
        itemObservations.forEach { $0.invalidate() }
        itemTokens.forEach { NotificationCenter.default.removeObserver($0) }
        itemTokens.removeAll()
        lastSample = nil
        let identity = String(describing: ObjectIdentifier(item))
        let context = ["item": identity, "generation": String(generation)]
        let logger = self.logger
        itemObservations = [
            item.observe(\.status, options: [.initial, .new]) { item, _ in
                var fields = context.merging(PlaybackDiagnostics.errorFields(item.error)) { _, new in new }
                fields["status"] = String(item.status.rawValue)
                logger?.record("item.status", fields: fields)
            },
            item.observe(\.isPlaybackBufferEmpty, options: [.new]) { _, change in
                logger?.record("item.buffer_empty", fields: context.merging(["value": String(change.newValue ?? false)]) { _, new in new })
            }
        ]
        let notifications: [(Notification.Name, String)] = [
            (.AVPlayerItemDidPlayToEndTime, "item.finished"),
            (.AVPlayerItemFailedToPlayToEndTime, "item.failed_to_finish"),
            (.AVPlayerItemPlaybackStalled, "item.stalled"),
            (.AVPlayerItemTimeJumped, "item.time_jumped"),
            (.AVPlayerItemNewErrorLogEntry, "item.error_log")
        ]
        for (name, event) in notifications {
            let token = NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] note in
                var fields = context
                if let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                    fields.merge(PlaybackDiagnostics.errorFields(error)) { _, new in new }
                }
                if let entry = (note.object as? AVPlayerItem)?.errorLog()?.events.last {
                    fields["logErrorDomain"] = entry.errorDomain
                    fields["logErrorCode"] = String(entry.errorStatusCode)
                }
                logger?.record(event, fields: fields)
                Task { @MainActor [weak self] in self?.snapshot("player.state") }
            }
            itemTokens.append(token)
        }
        snapshot("engine.item_installed")
    }

    private var itemID: String { player.currentItem.map { String(describing: ObjectIdentifier($0)) } ?? "none" }

    func snapshot(_ event: String) {
        var fields = PlaybackDiagnostics.errorFields(player.error)
        fields.merge(MacPlaybackDiagnostics.outputFields()) { _, new in new }
        fields["requestedPlaying"] = String(requestedPlaying)
        fields["playerStatus"] = String(player.status.rawValue)
        fields["timeControlStatus"] = String(player.timeControlStatus.rawValue)
        fields["rate"] = String(player.rate)
        fields["waitingReason"] = player.reasonForWaitingToPlay?.rawValue ?? "none"
        fields["position"] = String(player.currentTime().seconds)
        fields["item"] = itemID
        fields["itemStatus"] = String(player.currentItem?.status.rawValue ?? -1)
        fields["duration"] = String(player.currentItem?.duration.seconds ?? 0)
        fields["pendingSeeks"] = String(pendingSeeks)
        fields["muted"] = String(player.isMuted)
        fields["volume"] = String(player.volume)
        if let asset = player.currentItem?.asset as? AVURLAsset { fields["track"] = PlaybackDiagnostics.trackID(asset.url) }
        logger?.record(event, fields: fields)
    }

    private func sample() {
        guard requestedPlaying else { lastSample = nil; return }
        let now = ProcessInfo.processInfo.systemUptime
        let time = player.currentTime().seconds
        // A long sampling gap can mean sleep or a busy main thread, not a stall.
        if let last = lastSample, last.item == itemID, pendingSeeks == 0,
           time.isFinite, abs(time - last.time) < 0.05, now - last.uptime < 45,
           Date().timeIntervalSince(last.wallTime) - (now - last.uptime) < 2 {
            snapshot("health.no_progress")
        } else {
            snapshot("health.sample")
        }
        lastSample = (itemID, time, now, Date())
    }
}
#endif
