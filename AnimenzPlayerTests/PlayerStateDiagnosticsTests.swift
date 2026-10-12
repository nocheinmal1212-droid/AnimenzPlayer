#if os(macOS)
import XCTest
import AVFoundation
@testable import AnimenzPlayer

@MainActor
final class PlayerStateDiagnosticsTests: XCTestCase {
    private func events(_ data: Data) throws -> [[String: Any]] {
        try String(decoding: data, as: UTF8.self).split(separator: "\n")
            .filter { $0.first == "{" }
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
    }

    func testRequestedPlaybackIsLoggedSeparatelyFromActualPlayerState() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let logger = PlaybackDiagnostics(directory: dir)
        let player = AVPlayer()
        let diagnostics = PlayerStateDiagnostics(player: player, logger: logger)
        diagnostics.command("play")
        diagnostics.command("pause")
        let entries = try events(await logger.exportData())
        let play = try XCTUnwrap(entries.first { $0["event"] as? String == "engine.play" }?["fields"] as? [String: String])
        let pause = try XCTUnwrap(entries.first { $0["event"] as? String == "engine.pause" }?["fields"] as? [String: String])
        XCTAssertEqual(play["requestedPlaying"], "true")
        XCTAssertEqual(play["timeControlStatus"], "0")
        XCTAssertEqual(pause["requestedPlaying"], "false")
        XCTAssertEqual(player.timeControlStatus, .paused, "Diagnostics must not change playback")
    }

    func testEnumEventsReadObservedValuesInsteadOfMissingKVOChangePayload() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let logger = PlaybackDiagnostics(directory: dir)
        let player = AVPlayer()
        let diagnostics = PlayerStateDiagnostics(player: player, logger: logger)
        let item = AVPlayerItem(asset: AVMutableComposition())
        diagnostics.installed(item, generation: 1)
        let entries = try events(await logger.exportData())
        for event in ["player.time_control", "player.status", "item.status"] {
            let entry = try XCTUnwrap(entries.first { $0["event"] as? String == event })
            let fields = try XCTUnwrap(entry["fields"] as? [String: String])
            XCTAssertEqual(fields[event == "item.status" ? "status" : "new"], "0")
        }
    }

    func testReplacedItemNotificationsAreDetached() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let logger = PlaybackDiagnostics(directory: dir)
        let player = AVPlayer()
        let diagnostics = PlayerStateDiagnostics(player: player, logger: logger)
        let first = AVPlayerItem(asset: AVMutableComposition())
        let second = AVPlayerItem(asset: AVMutableComposition())
        diagnostics.installed(first, generation: 1)
        diagnostics.installed(second, generation: 2)
        NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: first)
        NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: second)
        let entries = try events(await logger.exportData()).filter { $0["event"] as? String == "item.stalled" }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual((entries.first?["fields"] as? [String: String])?["generation"], "2")
    }
}
#endif
