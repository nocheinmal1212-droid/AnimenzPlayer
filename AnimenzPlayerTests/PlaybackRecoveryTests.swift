#if os(macOS)
import XCTest
@testable import AnimenzPlayer

@MainActor
final class RecoveryTestClock {
    var pending: [(Double, CheckedContinuation<Void, Never>)] = []
    func wait(_ seconds: Double) async throws {
        await withCheckedContinuation { pending.append((seconds, $0)) }
    }
    func advance() { pending.removeFirst().1.resume() }
    func finish() { let saved = pending; pending.removeAll(); saved.forEach { $0.1.resume() } }
}

@MainActor
final class PlaybackRecoveryTests: XCTestCase {
    private let error = NSError(domain: "AVFoundationErrorDomain", code: -11800)
    private func drain() async { for _ in 0..<20 { await Task.yield() } }

    func testRetriesAreBoundedEvenWhenPlayerNeverReportsFailureAgain() async {
        let clock = RecoveryTestClock()
        let recovery = PlaybackRecovery(wait: clock.wait)
        var retries = 0
        var exhausted = 0
        recovery.onRetry = { _, _ in retries += 1 }
        recovery.onExhausted = { _ in exhausted += 1 }
        recovery.play()
        recovery.failed(error)
        for _ in 0..<3 {
            await drain()
            XCTAssertFalse(recovery.preventsIdleSleep)
            clock.advance() // backoff
            await drain()
            XCTAssertTrue(recovery.preventsIdleSleep)
            clock.advance() // timeout
        }
        await drain()
        XCTAssertEqual(retries, 3)
        XCTAssertEqual(exhausted, 1)
        XCTAssertFalse(recovery.wantsPlayback)
        XCTAssertFalse(recovery.preventsIdleSleep)
        XCTAssertTrue(clock.pending.isEmpty)
    }

    func testPauseCancelsRetryEvenIfDelayedCallbackStillArrives() async {
        let clock = RecoveryTestClock()
        let recovery = PlaybackRecovery(wait: clock.wait)
        var retries = 0
        recovery.onRetry = { _, _ in retries += 1 }
        recovery.play()
        recovery.failed(error)
        await drain()
        recovery.pause()
        clock.advance() // deliberately non-cooperative cancellation in fake clock
        await drain()
        XCTAssertEqual(retries, 0)
        XCTAssertFalse(recovery.wantsPlayback)
    }

    func testSleepSuspendsRetryAndManualPausePreventsWakeResume() async {
        let clock = RecoveryTestClock()
        let recovery = PlaybackRecovery(wait: clock.wait)
        var retries = 0
        recovery.onRetry = { _, _ in retries += 1 }
        recovery.play()
        recovery.failed(error)
        await drain()
        recovery.willSleep()
        clock.advance()
        await drain()
        XCTAssertEqual(retries, 0)
        XCTAssertFalse(recovery.preventsIdleSleep)
        recovery.pause()
        recovery.didWake()
        await drain()
        XCTAssertTrue(clock.pending.isEmpty)
        XCTAssertFalse(recovery.wantsPlayback)
    }

    func testWakeRetriesAndRealProgressCompletesRecovery() async {
        let clock = RecoveryTestClock()
        let recovery = PlaybackRecovery(wait: clock.wait)
        var tickets: [Int] = []
        recovery.onRetry = { _, ticket in tickets.append(ticket) }
        recovery.play()
        recovery.willSleep()
        recovery.didWake()
        await drain()
        clock.advance()
        await drain()
        XCTAssertEqual(tickets.count, 1)
        XCTAssertTrue(recovery.isCurrentAttempt(tickets[0]))
        recovery.madeProgress()
        clock.advance() // old timeout cannot trigger more playback
        await drain()
        XCTAssertFalse(recovery.isRecovering)
        XCTAssertTrue(recovery.preventsIdleSleep)
        XCTAssertEqual(tickets.count, 1)
        recovery.pause()
    }

    func testRepeatedFailuresDoNotResetBudgetAndNewPlayDoes() async {
        let clock = RecoveryTestClock()
        let recovery = PlaybackRecovery(wait: clock.wait)
        recovery.play()
        recovery.failed(error)
        recovery.failed(error)
        await drain()
        XCTAssertEqual(clock.pending.count, 1)
        clock.advance()
        await drain()
        XCTAssertEqual(recovery.attempts, 1)
        recovery.willSleep()
        recovery.didWake()
        await drain()
        XCTAssertEqual(recovery.attempts, 1)
        recovery.play()
        XCTAssertEqual(recovery.attempts, 0)
        recovery.pause()
        clock.finish()
        await drain()
    }

    func testPauseInvalidatesInFlightAttemptTicket() async {
        let clock = RecoveryTestClock()
        let recovery = PlaybackRecovery(wait: clock.wait)
        var ticket = -1
        recovery.onRetry = { _, t in ticket = t }
        recovery.play(needsRecovery: true)
        await drain()
        clock.advance()
        await drain()
        recovery.pause()
        XCTAssertFalse(recovery.isCurrentAttempt(ticket))
        clock.finish()
        await drain()
    }

    func testPowerAssertionIsBalancedAndIdempotent() {
        var begins = 0
        var ends = 0
        var activity: PlaybackActivity? = PlaybackActivity(begin: { begins += 1; return NSObject() }, end: { _ in ends += 1 })
        activity?.setActive(true)
        activity?.setActive(true)
        XCTAssertEqual(begins, 1)
        activity?.setActive(false)
        activity?.setActive(false)
        XCTAssertEqual(ends, 1)
        activity?.setActive(true)
        activity = nil
        XCTAssertEqual(begins, ends)
    }
}
#endif
