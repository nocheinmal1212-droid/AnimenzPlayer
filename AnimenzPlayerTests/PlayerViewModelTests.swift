import XCTest
@testable import AnimenzPlayer

@MainActor
final class PlayerViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeViewModel(
        tracks: [Track] = TestTrack.library(count: 3),
        engine: MockPlaybackEngine = MockPlaybackEngine(),
        initialState: PersistenceStore.State = .init()
    ) -> (PlayerViewModel, MockPlaybackEngine, LibraryStore, PersistenceStore) {
        let library = LibraryStore(autoload: false)
        library.setTracks(tracks)
        let persistence = PersistenceStore(fileURL: nil)
        persistence.update { state in
            state = initialState
        }
        let vm = PlayerViewModel(library: library, engine: engine, persistence: persistence)
        return (vm, engine, library, persistence)
    }

    // Wait for all currently-pending Tasks scheduled on the main actor to drain.
    // Used after intents that kick off `Task { await ... }` work.
    private func drainMainActor() async {
        await Task.yield()
        await Task.yield()
        await Task.yield()
    }

    // MARK: - Play intents

    func testPlayTrackLoadsAndStartsEngine() async {
        let (vm, engine, _, _) = makeViewModel()
        let tracks = vm.tracks

        vm.play(tracks[1])
        await drainMainActor()

        XCTAssertEqual(engine.loadedURLs.last, tracks[1].url)
        XCTAssertEqual(engine.playCallCount, 1)
        XCTAssertEqual(vm.currentTrack, tracks[1])
    }

    func testPlayTrackNotInLibrarySurfacesError() async {
        let (vm, engine, _, _) = makeViewModel()
        let unknown = TestTrack.make(index: 99, title: "Ghost")

        vm.play(unknown)
        await drainMainActor()

        XCTAssertEqual(engine.loadedURLs.count, 0)
        XCTAssertEqual(vm.currentError, .noTracksAvailable)
    }

    func testTogglePlayPauseOnEmptyLibraryDoesNothing() async {
        let (vm, engine, _, _) = makeViewModel(tracks: [])

        vm.togglePlayPause()
        await drainMainActor()

        XCTAssertEqual(engine.playCallCount, 0)
        XCTAssertEqual(engine.pauseCallCount, 0)
    }

    func testTogglePausesWhenPlaying() async {
        let (vm, engine, _, _) = makeViewModel()
        vm.play(vm.tracks[0])
        await drainMainActor()

        vm.togglePlayPause()
        XCTAssertEqual(engine.pauseCallCount, 1)
    }

    // MARK: - Navigation

    func testNextAdvancesAndPlays() async {
        let (vm, engine, _, _) = makeViewModel()
        let tracks = vm.tracks
        vm.play(tracks[0])
        await drainMainActor()
        engine.playCallCount = 0

        vm.next()
        await drainMainActor()

        XCTAssertEqual(vm.currentTrack, tracks[1])
        XCTAssertEqual(engine.playCallCount, 1)
    }

    func testPreviousWithinThreeSecondsGoesToPriorTrack() async {
        let (vm, engine, _, _) = makeViewModel()
        let tracks = vm.tracks
        vm.play(tracks[1])
        await drainMainActor()
        engine.simulateTimeTick(1.5)  // <3s

        vm.previous()
        await drainMainActor()

        XCTAssertEqual(vm.currentTrack, tracks[0])
    }

    func testPreviousAfterThreeSecondsRestartsCurrentTrack() async {
        let (vm, engine, _, _) = makeViewModel()
        let tracks = vm.tracks
        vm.play(tracks[1])
        await drainMainActor()
        engine.simulateTimeTick(10.0)

        vm.previous()
        await drainMainActor()

        XCTAssertEqual(vm.currentTrack, tracks[1], "should NOT change track")
        XCTAssertEqual(engine.seekTargets.last, 0, "should seek to zero")
    }

    // MARK: - Finish -> auto-advance

    func testFinishAdvancesToNextTrack() async {
        let (vm, engine, _, _) = makeViewModel()
        let tracks = vm.tracks
        vm.play(tracks[0])
        await drainMainActor()

        engine.simulateFinish()
        await drainMainActor()

        XCTAssertEqual(vm.currentTrack, tracks[1])
    }

    func testFinishOnLastTrackWrapsToFirst() async {
        let (vm, engine, _, _) = makeViewModel()
        let tracks = vm.tracks
        vm.play(tracks.last!)
        await drainMainActor()

        engine.simulateFinish()
        await drainMainActor()

        XCTAssertEqual(vm.currentTrack, tracks.first)
    }

    // MARK: - Shuffle

    func testShufflePersistsThroughCoordinator() async {
        let (vm, _, _, persistence) = makeViewModel()

        vm.isShuffled = true
        // Debounced write — we need to flush to observe.
        persistence.flush()
        XCTAssertTrue(persistence.state.isShuffled)

        vm.isShuffled = false
        persistence.flush()
        XCTAssertFalse(persistence.state.isShuffled)
    }

    // MARK: - Engine errors propagate

    func testEngineErrorBecomesCurrentError() async {
        let (vm, engine, _, _) = makeViewModel()

        let err = PlayerError.playbackFailed(underlying: "boom")
        engine.simulateError(err)

        XCTAssertEqual(vm.currentError, err)
    }

    func testLoadFailureSurfacesAsError() async {
        let (vm, engine, _, _) = makeViewModel()
        engine.loadError = NSError(domain: "test", code: 1)

        vm.play(vm.tracks[0])
        await drainMainActor()

        XCTAssertNotNil(vm.currentError)
        if case .loadFailed = vm.currentError {} else {
            XCTFail("expected .loadFailed, got \(String(describing: vm.currentError))")
        }
    }

    // MARK: - Time updates wire through

    func testEngineTimeUpdatesProgress() async {
        let (vm, engine, _, _) = makeViewModel()
        vm.play(vm.tracks[0])
        await drainMainActor()

        engine.simulateTimeTick(42.5)
        XCTAssertEqual(vm.progress, 42.5)
    }
}
