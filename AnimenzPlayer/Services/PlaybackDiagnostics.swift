import Foundation
import CryptoKit

/// Local, bounded diagnostics. No audio, titles, full paths, or network traffic.
/// Explicitly nonisolated: encoding and disk I/O run on a private serial queue,
/// even in targets that default to MainActor isolation.
nonisolated final class PlaybackDiagnostics: @unchecked Sendable {
    static let shared: PlaybackDiagnostics? = {
        #if os(macOS)
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return PlaybackDiagnostics(directory: base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "AnimenzPlayer", isDirectory: true)
            .appendingPathComponent("PlaybackDiagnostics", isDirectory: true))
        #else
        return nil
        #endif
    }()

    static func record(_ event: String, _ fields: [String: String] = [:]) {
        shared?.record(event, fields: fields)
    }

    static func trackID(_ url: URL?) -> String {
        guard let url else { return "none" }
        // Stable across launches, without storing the user's home or bundle path.
        return SHA256.hash(data: Data(url.lastPathComponent.utf8))
            .prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func errorFields(_ error: Error?) -> [String: String] {
        guard let error else { return [:] }
        let ns = error as NSError
        var fields = ["errorDomain": ns.domain, "errorCode": String(ns.code)]
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            fields["underlyingDomain"] = underlying.domain
            fields["underlyingCode"] = String(underlying.code)
        }
        // localizedDescription/userInfo may contain filenames and private paths.
        return fields
    }

    private let queue = DispatchQueue(label: "AnimenzPlayer.playback-diagnostics", qos: .utility)
    private let gate = NSLock()
    private var pending = 0
    private var dropped = 0
    private let maxPending = 512
    private let writer: Writer
    let sessionID = UUID().uuidString

    init(directory: URL, maxFileBytes: Int = 2 * 1024 * 1024, fileCount: Int = 3) {
        writer = Writer(directory: directory, maxFileBytes: max(1024, maxFileBytes), fileCount: max(2, fileCount))
        record("session.start", fields: [
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "schema": "2"
        ])
    }

    func record(_ event: String, fields: [String: String] = [:]) {
        let timestamp = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        gate.lock()
        guard pending < maxPending else {
            dropped += 1
            gate.unlock()
            return
        }
        pending += 1
        let lost = dropped
        dropped = 0
        gate.unlock()
        // Limit memory and line size even if a caller supplies excessive context.
        var bounded = Dictionary(uniqueKeysWithValues: fields.keys.sorted().prefix(32).map {
            ($0, String(fields[$0, default: ""].prefix(512)))
        })
        if lost > 0 { bounded["droppedEvents"] = String(lost) }
        let safeFields = bounded
        queue.async { [self] in
            writer.append(event: String(event.prefix(128)), fields: safeFields,
                          session: sessionID, timestamp: timestamp, uptime: uptime)
            gate.lock()
            pending -= 1
            gate.unlock()
        }
    }

    /// The serial queue forms a snapshot barrier: every earlier accepted event
    /// is included; playback may keep logging while the completed data is saved.
    func exportData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do { continuation.resume(returning: try writer.exportData()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Only used during application termination; never wait indefinitely on disk.
    func flushBeforeExit() {
        let done = DispatchSemaphore(value: 0)
        queue.async { [self] in writer.flush(); done.signal() }
        _ = done.wait(timeout: .now() + 0.5)
    }

    private final class Writer {
        let directory: URL
        let maxFileBytes: Int
        let fileCount: Int
        var handle: FileHandle?
        var bytes = 0
        var sequence = 0
        var writeFailures = 0
        var lastWriteError: [String: String] = [:]
        let formatter = ISO8601DateFormatter()

        init(directory: URL, maxFileBytes: Int, fileCount: Int) {
            self.directory = directory
            self.maxFileBytes = maxFileBytes
            self.fileCount = fileCount
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }

        deinit { try? handle?.close() }

        func url(_ index: Int) -> URL { directory.appendingPathComponent("playback-\(index).jsonl") }

        func openIfNeeded() throws {
            guard handle == nil else { return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url(0).path) {
                guard FileManager.default.createFile(atPath: url(0).path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            let opened = try FileHandle(forWritingTo: url(0))
            do { bytes = Int(try opened.seekToEnd()); handle = opened }
            catch { try? opened.close(); throw error }
        }

        func append(event: String, fields: [String: String], session: String, timestamp: Date, uptime: Double) {
            do {
                sequence += 1
                var object: [String: Any] = ["timestamp": formatter.string(from: timestamp),
                    "uptimeSeconds": uptime, "session": session, "sequence": sequence,
                    "event": event, "fields": fields]
                var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                if data.count + 1 > maxFileBytes {
                    object["fields"] = ["truncated": "event exceeded file size limit"]
                    data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                }
                data.append(0x0a)
                try openIfNeeded()
                if bytes + data.count > maxFileBytes { try rotate(); try openIfNeeded() }
                try handle?.write(contentsOf: data)
                bytes += data.count
            } catch {
                writeFailures += 1
                lastWriteError = PlaybackDiagnostics.errorFields(error)
                try? handle?.close()
                handle = nil // Retry on the next event; a disk error must not affect playback.
            }
        }

        func rotate() throws {
            try handle?.close()
            handle = nil
            let fm = FileManager.default
            for index in stride(from: fileCount - 1, through: 1, by: -1) {
                if fm.fileExists(atPath: url(index).path) { try fm.removeItem(at: url(index)) }
                if fm.fileExists(atPath: url(index - 1).path) { try fm.moveItem(at: url(index - 1), to: url(index)) }
            }
            bytes = 0
        }

        func flush() { try? handle?.synchronize() }

        func exportData() throws -> Data {
            try handle?.synchronize()
            var result = Data("AnimenzPlayer Playback Debug Log\nExported: \(formatter.string(from: Date()))\nOldest retained events first. Session IDs distinguish app launches.\nState key: timeControlStatus 0=paused, 1=waiting, 2=playing; player/item status 0=unknown, 1=ready, 2=failed.\nTrack IDs are hashes of filenames; audio and full paths are not included.\nRetention: up to \(fileCount) files of \(maxFileBytes) bytes.\nWrite failures this session: \(writeFailures) \(lastWriteError)\n\n".utf8)
            var found = false
            for index in stride(from: fileCount - 1, through: 0, by: -1) {
                guard FileManager.default.fileExists(atPath: url(index).path) else { continue }
                found = true
                result.append(Data("--- playback-\(index).jsonl ---\n".utf8))
                result.append(try Data(contentsOf: url(index)))
                result.append(0x0a)
            }
            guard found else { throw CocoaError(.fileReadNoSuchFile) }
            return result
        }
    }
}
