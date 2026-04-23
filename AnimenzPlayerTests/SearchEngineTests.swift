import XCTest
@testable import AnimenzPlayer

/// Tests for the Wave 3 search engine. Uses a fixture library of real titles
/// drawn from the bundled `music_list.txt` so regressions show up as "query
/// X used to return tracks A,B,C and now returns something else".
final class SearchEngineTests: XCTestCase {

    // MARK: - Fixture

    private static let fixtureTitles: [String] = [
        // AOT cluster — a mix of show-first and song-first shapes.
        "Guren no Yumiya - Attack on Titan OP1 [Piano]",
        "Jiyuu no Tsubasa - Attack on Titan OP2 [Piano]",
        "The Rumbling - Attack on Titan Final Season OP [Piano] ⧸ SiM",
        "Shinzou wo Sasageyo! - Attack on Titan S2 OP [Piano] ⧸ Linked Horizon",
        "Call of Silence (Ymir's theme) - Attack on Titan S2 OST [Piano] ⧸ Hiroyuki Sawano",
        // JJK cluster.
        "SPECIALZ - Jujutsu Kaisen S2 OP2 [Piano] ⧸King Gnu",
        "Kaikai Kitan - Jujutsu Kaisen OP [Piano] ⧸ Eve",
        "Ao no Sumika - Jujutsu Kaisen S2 OP1 [Piano] ⧸ Tatsuya Kitani",
        // SAO cluster.
        "crossing field - Sword Art Online OP [Piano]",
        "Swordland - Sword Art Online Main Theme [Piano]",
        "unlasting - Sword Art Online： Alicization - War of Underworld ED [Piano]",
        // Frieren.
        "Frieren： Beyond Journey's End - Soundtrack Medley [Piano] ⧸ Evan Call",
        // One Piece.
        "We Are! - One Piece OP1 [Piano]",
        // A title that mentions "Titan" nowhere but is named similarly.
        "Kaibutsu - BEASTARS S2 OP [Piano] ⧸ YOASOBI",
        // Something unrelated.
        "Butter-Fly - Digimon Adventure OP [Piano]",
    ]

    private static func makeFixture() -> [Track] {
        fixtureTitles.enumerated().map { i, title in
            TestTrack.make(index: i + 1, title: title)
        }
    }

    // MARK: - Empty / passthrough

    func testEmptyQueryReturnsAllTracksInOrder() {
        let tracks = Self.makeFixture()
        let result = SearchEngine.rank("", in: tracks)
        XCTAssertEqual(result, tracks)
    }

    func testWhitespaceOnlyQueryReturnsAllTracks() {
        let tracks = Self.makeFixture()
        let result = SearchEngine.rank("   ", in: tracks)
        XCTAssertEqual(result, tracks)
    }

    // MARK: - Substring regressions (Wave 1 behavior preserved)

    func testTitleSubstringMatch() {
        let tracks = Self.makeFixture()
        let result = SearchEngine.rank("Rumbling", in: tracks)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].title.contains("Rumbling"))
    }

    func testSubstringIsCaseInsensitive() {
        let tracks = Self.makeFixture()
        let lower = SearchEngine.rank("rumbling", in: tracks)
        let upper = SearchEngine.rank("RUMBLING", in: tracks)
        XCTAssertEqual(lower, upper)
        XCTAssertFalse(lower.isEmpty)
    }

    // MARK: - Alias matching

    func testAliasAOTReturnsAllAttackOnTitanTracks() {
        let tracks = Self.makeFixture()
        let result = SearchEngine.rank("AOT", in: tracks)
        let aotCount = tracks.filter { $0.title.contains("Attack on Titan") }.count
        XCTAssertEqual(result.count, aotCount)
        XCTAssertTrue(result.allSatisfy { $0.title.contains("Attack on Titan") })
    }

    func testAliasJJKReturnsJujutsuTracks() {
        let tracks = Self.makeFixture()
        let result = SearchEngine.rank("JJK", in: tracks)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { $0.title.contains("Jujutsu Kaisen") })
    }

    func testAliasIsCaseInsensitive() {
        let tracks = Self.makeFixture()
        let upper = SearchEngine.rank("AOT", in: tracks)
        let lower = SearchEngine.rank("aot", in: tracks)
        let mixed = SearchEngine.rank("Aot", in: tracks)
        XCTAssertEqual(upper, lower)
        XCTAssertEqual(lower, mixed)
    }

    // MARK: - Show-name substring (the bare "Frieren" or "Attack on Titan" case)

    func testShowNameQueryMatchesAll() {
        let tracks = Self.makeFixture()
        let result = SearchEngine.rank("Attack on Titan", in: tracks)
        XCTAssertEqual(result.count, 5)
    }

    func testBareShowSubstring() {
        let tracks = Self.makeFixture()
        let result = SearchEngine.rank("frieren", in: tracks)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].title.lowercased().contains("frieren"))
    }

    // MARK: - Token matching

    func testTokenOrderIndependence() {
        let tracks = Self.makeFixture()
        let result = SearchEngine.rank("titan attack", in: tracks)
        // "titan attack" — no substring match, but both tokens appear in the
        // AOT titles. Should return all 5 AOT tracks.
        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(result.allSatisfy { $0.title.contains("Attack on Titan") })
    }

    func testTokenMatchNarrowsWithinAShow() {
        let tracks = Self.makeFixture()
        // Two tokens, both substrings of exactly one title. Narrows SAO
        // tracks to just the Alicization one.
        //
        // (Note: "sao alicization" would feel natural here but doesn't work
        // under current scoring — "sao" is an alias, not a substring of
        // "sword art online". Expanding aliases inside multi-token queries
        // is a fine Wave 3+ enhancement, intentionally left out of scope
        // here to keep the ranking rules simple and predictable.)
        let result = SearchEngine.rank("sword alicization", in: tracks)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].title.contains("Alicization"))
    }

    // MARK: - Ranking order (locked top-k)

    func testAliasMatchesOutrankSubstringMatches() {
        // A track whose title literally says "Attack on Titan" (score 80 via
        // substring OR 100 via alias) should be preceded by all alias-matches
        // — which is everyone with derived show == "Attack on Titan". In our
        // fixture every AOT track both alias-matches and substring-matches,
        // so the ranking collapses and index order wins.
        let tracks = Self.makeFixture()
        let result = SearchEngine.rank("AOT", in: tracks)
        let indices = result.map(\.index)
        XCTAssertEqual(indices, indices.sorted(), "ties should break by library index")
    }

    func testUnknownQueryReturnsEmpty() {
        let tracks = Self.makeFixture()
        let result = SearchEngine.rank("zzzabcdef", in: tracks)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Stability

    func testResultsAreDeterministic() {
        let tracks = Self.makeFixture()
        let a = SearchEngine.rank("AOT", in: tracks)
        let b = SearchEngine.rank("AOT", in: tracks)
        XCTAssertEqual(a, b)
    }
}
