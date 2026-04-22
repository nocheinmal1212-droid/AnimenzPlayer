import XCTest
@testable import AnimenzPlayer

final class PlayQueueTests: XCTestCase {

    // MARK: - Empty state

    func testEmptyQueueHasNoCurrent() {
        let q = PlayQueue()
        XCTAssertNil(q.current)
        XCTAssertTrue(q.isEmpty)
        XCTAssertEqual(q.count, 0)
    }

    func testAdvanceOnEmptyQueueReturnsNil() {
        var q = PlayQueue()
        XCTAssertNil(q.advance())
        XCTAssertNil(q.retreat())
    }

    // MARK: - Basic setup

    func testSetTracksPlacesHeadAtFirstTrack() {
        var q = PlayQueue()
        let tracks = TestTrack.library(count: 3)
        q.setTracks(tracks)
        XCTAssertEqual(q.current, tracks[0])
        XCTAssertEqual(q.count, 3)
    }

    // MARK: - Navigation

    func testAdvanceWrapsAround() {
        var q = PlayQueue()
        let tracks = TestTrack.library(count: 3)
        q.setTracks(tracks)

        XCTAssertEqual(q.advance(), tracks[1])
        XCTAssertEqual(q.advance(), tracks[2])
        XCTAssertEqual(q.advance(), tracks[0], "should wrap around to start")
    }

    func testRetreatWrapsAround() {
        var q = PlayQueue()
        let tracks = TestTrack.library(count: 3)
        q.setTracks(tracks)

        XCTAssertEqual(q.retreat(), tracks[2], "should wrap around to end")
        XCTAssertEqual(q.retreat(), tracks[1])
    }

    func testJumpToTrack() {
        var q = PlayQueue()
        let tracks = TestTrack.library(count: 5)
        q.setTracks(tracks)

        let result = q.jump(to: tracks[3])
        XCTAssertEqual(result, tracks[3])
        XCTAssertEqual(q.current, tracks[3])
    }

    func testJumpToMissingTrackReturnsNil() {
        var q = PlayQueue()
        q.setTracks(TestTrack.library(count: 3))
        let missing = TestTrack.make(index: 99, title: "Missing")
        XCTAssertNil(q.jump(to: missing))
    }

    // MARK: - Shuffle

    func testShuffleRandomizesOrderButPreservesTracks() {
        var q = PlayQueue()
        let tracks = TestTrack.library(count: 20)  // 20 makes a pure-luck identical shuffle statistically ~1/20! negligible
        q.setTracks(tracks)
        q.setShuffled(true)

        let shuffledOrder = (0..<q.count).map { _ -> Track in
            let c = q.current!
            _ = q.advance()
            return c
        }
        XCTAssertEqual(Set(shuffledOrder), Set(tracks), "all tracks must still be present")
    }

    func testShufflePreservesCurrentTrack() {
        var q = PlayQueue()
        let tracks = TestTrack.library(count: 10)
        q.setTracks(tracks)
        _ = q.jump(to: tracks[4])

        q.setShuffled(true)
        XCTAssertEqual(q.current, tracks[4], "shuffle must not displace the current track")
    }

    func testUnshufflePreservesCurrentTrack() {
        var q = PlayQueue()
        let tracks = TestTrack.library(count: 10)
        q.setTracks(tracks)
        q.setShuffled(true)
        let currentAfterShuffle = q.current

        q.setShuffled(false)
        XCTAssertEqual(q.current, currentAfterShuffle)
    }

    func testSetShuffledToSameValueIsNoOp() {
        var q = PlayQueue()
        q.setTracks(TestTrack.library(count: 3))
        q.setShuffled(false)  // already false
        // Order should be exactly sequential, not a fresh shuffle
        XCTAssertEqual(q.orderedIndices, [0, 1, 2])
    }

    // MARK: - Replace tracks

    func testReplacingTracksPreservesCurrentWhenStillPresent() {
        var q = PlayQueue()
        let initial = TestTrack.library(count: 3)
        q.setTracks(initial)
        _ = q.jump(to: initial[1])

        let replacement = initial  // same list
        q.setTracks(replacement, preservingCurrent: true)
        XCTAssertEqual(q.current, initial[1])
    }

    func testReplacingTracksFallsBackToStartWhenCurrentGone() {
        var q = PlayQueue()
        let initial = TestTrack.library(count: 3)
        q.setTracks(initial)
        _ = q.jump(to: initial[2])

        let replacement = [TestTrack.make(index: 99)]
        q.setTracks(replacement, preservingCurrent: true)
        XCTAssertEqual(q.current, replacement[0])
    }
}
