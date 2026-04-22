import XCTest
@testable import AnimenzPlayer

@MainActor
final class SleepTimerTests: XCTestCase {

    func testInitialStateIsInactive() {
        let t = SleepTimer()
        XCTAssertNil(t.mode)
        XCTAssertEqual(t.remaining, 0)
    }

    func testStartDurationSetsModeAndRemaining() {
        let t = SleepTimer()
        t.start(.duration(300))

        XCTAssertEqual(t.mode, .duration(300))
        // `remaining` is set to the full duration at start; the visible
        // countdown reflects wall-clock time after the first tick.
        XCTAssertEqual(t.remaining, 300, accuracy: 0.01)
    }

    func testStopClearsMode() {
        let t = SleepTimer()
        t.start(.duration(300))
        t.stop()

        XCTAssertNil(t.mode)
        XCTAssertEqual(t.remaining, 0)
    }

    func testStartingNewTimerReplacesPrevious() {
        let t = SleepTimer()
        t.start(.duration(300))
        t.start(.endOfTrack)

        XCTAssertEqual(t.mode, .endOfTrack)
    }

    // MARK: - End-of-track mode

    func testEndOfTrackFiresOnTrackFinished() {
        let t = SleepTimer()
        var fired = false
        t.onExpire = { fired = true }

        t.start(.endOfTrack)
        t.handleTrackFinished()

        XCTAssertTrue(fired)
        XCTAssertNil(t.mode, "expiration should clear mode")
    }

    func testTrackFinishedWhenNoTimerIsNoOp() {
        let t = SleepTimer()
        var fired = false
        t.onExpire = { fired = true }

        t.handleTrackFinished()

        XCTAssertFalse(fired)
    }

    func testTrackFinishedIgnoredInDurationMode() {
        let t = SleepTimer()
        var fired = false
        t.onExpire = { fired = true }

        t.start(.duration(300))
        t.handleTrackFinished()

        XCTAssertFalse(fired, "duration-mode timer should not fire on track finish")
        XCTAssertNotNil(t.mode)
    }

    // MARK: - Expiration

    func testDurationTimerExpiresAfterItsInterval() async throws {
        let t = SleepTimer()
        let exp = expectation(description: "timer fires")
        t.onExpire = { exp.fulfill() }

        // Use a very short duration so the test finishes quickly.
        t.start(.duration(0.5))

        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertNil(t.mode, "expiration should clear mode")
    }
}
