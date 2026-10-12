#if os(macOS)
import XCTest
import AVFoundation
@testable import AnimenzPlayer

@MainActor
final class PlaybackEngineRecoveryTests: XCTestCase {
    private func silentAudio() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Recovery-\(UUID().uuidString).caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
        buffer.frameLength = 44100
        buffer.floatChannelData![0].initialize(repeating: 0, count: 44100)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func testFailedToFinishStartsRecoveryWhileItemRemainsReady() async throws {
        let url = try silentAudio()
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = RecoveryTestClock()
        let recovery = PlaybackRecovery(wait: clock.wait)
        let player = AVPlayer()
        player.isMuted = true
        let engine = AVPlayerEngine(player: player, recovery: recovery,
            activity: PlaybackActivity(begin: { NSObject() }, end: { _ in }), workspaceCenter: NotificationCenter())
        try await engine.load(url: url)
        let item = try XCTUnwrap(player.currentItem)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in item.status == .readyToPlay }, object: nil)
        await fulfillment(of: [ready], timeout: 3)
        XCTAssertEqual(item.status, .readyToPlay)
        recovery.play() // Establish intent without starting the actual audio device.
        let error = NSError(domain: "AVFoundationErrorDomain", code: -11800,
                            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -66681)])
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: item,
                                        userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: error])
        XCTAssertTrue(recovery.isRecovering)
        XCTAssertTrue(engine.isPlaying, "Pause must remain available while retrying")
        XCTAssertEqual(item.status, .readyToPlay)
        engine.pause()
        for _ in 0..<20 { await Task.yield() }
        clock.finish()
        XCTAssertFalse(recovery.wantsPlayback)
        engine.stop()
    }

    func testFailureFromReplacedItemCannotRecoverOldTrack() async throws {
        let url = try silentAudio()
        defer { try? FileManager.default.removeItem(at: url) }
        let recovery = PlaybackRecovery()
        let player = AVPlayer()
        let engine = AVPlayerEngine(player: player, recovery: recovery,
            activity: PlaybackActivity(begin: { NSObject() }, end: { _ in }), workspaceCenter: NotificationCenter())
        try await engine.load(url: url)
        let previous = try XCTUnwrap(player.currentItem)
        try await engine.load(url: url)
        recovery.play()
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: previous,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: NSError(domain: "test", code: 1)])
        XCTAssertFalse(recovery.isRecovering)
        engine.stop()
    }
}
#endif
