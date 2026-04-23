import XCTest
@testable import AnimenzPlayer

final class PlaybackScopeTests: XCTestCase {

    // MARK: - isRestricted

    func testAllScopeIsUnrestricted() {
        XCTAssertFalse(PlaybackScope.all.isRestricted)
    }

    func testFavoritesScopeIsRestricted() {
        XCTAssertTrue(PlaybackScope.favorites.isRestricted)
    }

    func testRecentScopeIsRestricted() {
        XCTAssertTrue(PlaybackScope.recent.isRestricted)
    }

    func testSearchScopeIsRestricted() {
        let scope = PlaybackScope.search(query: "AOT", results: [])
        XCTAssertTrue(scope.isRestricted)
    }

    // MARK: - displayName

    func testDisplayNameForNamedScopes() {
        XCTAssertEqual(PlaybackScope.all.displayName, "All Tracks")
        XCTAssertEqual(PlaybackScope.favorites.displayName, "Favorites")
        XCTAssertEqual(PlaybackScope.recent.displayName, "Recently Played")
    }

    func testDisplayNameForSearchIncludesQuery() {
        let scope = PlaybackScope.search(query: "AOT", results: [])
        XCTAssertTrue(scope.displayName.contains("AOT"))
    }

    // MARK: - Equatable

    func testEqualityTreatsScopesWithSameQueryEqual() {
        let tracks = TestTrack.library(count: 2)
        let a = PlaybackScope.search(query: "AOT", results: tracks)
        let b = PlaybackScope.search(query: "AOT", results: tracks)
        XCTAssertEqual(a, b)
    }

    func testEqualityDistinguishesScopeCases() {
        XCTAssertNotEqual(PlaybackScope.all, PlaybackScope.favorites)
        XCTAssertNotEqual(PlaybackScope.favorites, PlaybackScope.recent)
    }

    func testEqualityDistinguishesSearchQueries() {
        let a = PlaybackScope.search(query: "AOT", results: [])
        let b = PlaybackScope.search(query: "JJK", results: [])
        XCTAssertNotEqual(a, b)
    }
}
