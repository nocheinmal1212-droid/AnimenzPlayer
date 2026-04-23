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

    // MARK: - Wave 3: Scoped playback

    func testDefaultScopeIsAll() async {
        let (vm, _, _, _) = makeViewModel()
        XCTAssertEqual(vm.currentScope, .all)
    }

    func testPlayInScopeSetsCurrentScope() async {
        let (vm, _, _, _) = makeViewModel()
        let tracks = vm.tracks
        let subset = Array(tracks.prefix(2))
        let scope = PlaybackScope.search(query: "foo", results: subset)

        vm.play(subset[0], inScope: scope)
        await drainMainActor()

        XCTAssertEqual(vm.currentScope, scope)
        XCTAssertEqual(vm.currentTrack, subset[0])
    }

    func testNextWithinScopeStaysWithinScope() async {
        let (vm, engine, _, _) = makeViewModel(tracks: TestTrack.library(count: 5))
        let tracks = vm.tracks
        let subset = [tracks[1], tracks[3]]  // every-other, on purpose
        let scope = PlaybackScope.search(query: "subset", results: subset)

        vm.play(subset[0], inScope: scope)
        await drainMainActor()
        engine.playCallCount = 0

        vm.next()
        await drainMainActor()
        XCTAssertEqual(vm.currentTrack, subset[1])

        // Wrap within scope, not into the full library.
        vm.next()
        await drainMainActor()
        XCTAssertEqual(vm.currentTrack, subset[0])
    }

    func testFinishInScopeWrapsWithinScopeWhenRepeatAll() async {
        let (vm, engine, _, _) = makeViewModel(tracks: TestTrack.library(count: 5))
        let tracks = vm.tracks
        let subset = [tracks[0], tracks[2]]
        let scope = PlaybackScope.search(query: "s", results: subset)
        vm.repeatMode = .all

        vm.play(subset.last!, inScope: scope)
        await drainMainActor()

        engine.simulateFinish()
        await drainMainActor()

        XCTAssertEqual(vm.currentTrack, subset.first, "repeat-all should wrap within scope")
    }

    func testFinishInScopeStopsAtEndWhenRepeatOff() async {
        let (vm, engine, _, _) = makeViewModel(tracks: TestTrack.library(count: 5))
        let tracks = vm.tracks
        let subset = [tracks[0], tracks[2]]
        let scope = PlaybackScope.search(query: "s", results: subset)
        vm.repeatMode = .off

        vm.play(subset.last!, inScope: scope)
        await drainMainActor()
        let before = engine.pauseCallCount

        engine.simulateFinish()
        await drainMainActor()

        XCTAssertEqual(vm.currentTrack, subset.last,
                       "repeat-off at end of scope should not change track")
        XCTAssertGreaterThan(engine.pauseCallCount, before,
                             "repeat-off at end of scope should pause")
    }

    func testClearScopeResetsToAllAndPreservesCurrentTrack() async {
        let (vm, _, _, _) = makeViewModel(tracks: TestTrack.library(count: 5))
        let tracks = vm.tracks
        let subset = [tracks[1], tracks[3]]
        let scope = PlaybackScope.search(query: "s", results: subset)

        vm.play(subset[0], inScope: scope)
        await drainMainActor()
        XCTAssertEqual(vm.currentScope, scope)

        vm.clearScope()
        XCTAssertEqual(vm.currentScope, .all)
        XCTAssertEqual(vm.currentTrack, subset[0], "clearScope must preserve current track")

        // After clearing, next() should traverse the full library, not the subset.
        vm.next()
        await drainMainActor()
        XCTAssertEqual(vm.currentTrack, tracks[2],
                       "after clearScope, next() advances within the full library")
    }

    func testPlayWithTrackNotInScopeSurfacesError() async {
        let (vm, engine, _, _) = makeViewModel(tracks: TestTrack.library(count: 5))
        let tracks = vm.tracks
        let subset = [tracks[0], tracks[1]]
        let scope = PlaybackScope.search(query: "s", results: subset)

        // tracks[3] isn't in subset, so this should error without loading.
        vm.play(tracks[3], inScope: scope)
        await drainMainActor()

        XCTAssertEqual(engine.loadedURLs.count, 0)
        XCTAssertEqual(vm.currentError, .noTracksAvailable)
        XCTAssertEqual(vm.currentScope, .all, "scope must not change on failed play")
    }

    func testScopePersistsQueryOnPlay() async {
        let (vm, _, _, persistence) = makeViewModel(tracks: TestTrack.library(count: 3))
        let tracks = vm.tracks
        let scope = PlaybackScope.search(query: "demo", results: tracks)

        vm.play(tracks[0], inScope: scope)
        await drainMainActor()
        persistence.flush()

        XCTAssertEqual(persistence.state.lastScopeQuery, "demo")
    }

    func testClearScopeClearsPersistedQuery() async {
        let (vm, _, _, persistence) = makeViewModel(tracks: TestTrack.library(count: 3))
        let tracks = vm.tracks
        let scope = PlaybackScope.search(query: "demo", results: tracks)

        vm.play(tracks[0], inScope: scope)
        await drainMainActor()
        vm.clearScope()
        persistence.flush()

        XCTAssertNil(persistence.state.lastScopeQuery)
    }

    func testLegacyPlayWithoutScopeUsesAll() async {
        // Regression guard: the no-scope `play(_:)` still works as before,
        // and does NOT flip scope to anything else.
        let (vm, _, _, _) = makeViewModel()
        vm.play(vm.tracks[0])
        await drainMainActor()
        XCTAssertEqual(vm.currentScope, .all)
    }
}
