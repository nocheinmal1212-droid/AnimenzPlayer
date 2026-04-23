import XCTest
@testable import AnimenzPlayer

final class ShowCatalogTests: XCTestCase {

    // MARK: - canonicalShow(for:)

    func testCanonicalShowResolvesKnownAliases() {
        XCTAssertEqual(ShowCatalog.canonicalShow(for: "AOT"), "Attack on Titan")
        XCTAssertEqual(ShowCatalog.canonicalShow(for: "JJK"), "Jujutsu Kaisen")
        XCTAssertEqual(ShowCatalog.canonicalShow(for: "SAO"), "Sword Art Online")
        XCTAssertEqual(ShowCatalog.canonicalShow(for: "BNHA"), "My Hero Academia")
    }

    func testCanonicalShowIsCaseInsensitive() {
        XCTAssertEqual(ShowCatalog.canonicalShow(for: "aot"), "Attack on Titan")
        XCTAssertEqual(ShowCatalog.canonicalShow(for: "AoT"), "Attack on Titan")
        XCTAssertEqual(ShowCatalog.canonicalShow(for: " AOT  "), "Attack on Titan")
    }

    func testCanonicalShowReturnsNilForUnknown() {
        XCTAssertNil(ShowCatalog.canonicalShow(for: "zzz"))
        XCTAssertNil(ShowCatalog.canonicalShow(for: ""))
        XCTAssertNil(ShowCatalog.canonicalShow(for: "Attack on Titan"))
        // ^ "Attack on Titan" is a known show but not an alias; the search
        //   engine handles direct substring queries separately.
    }

    // MARK: - derivedShow(from:)
    //
    // Titles here are lifted from the real bundled library (music_list.txt)
    // so regressions show up as "track X stopped being recognized as Y".

    func testDerivedShowForAttackOnTitan() {
        XCTAssertEqual(
            ShowCatalog.derivedShow(from: "Guren no Yumiya - Attack on Titan OP1 [Piano]"),
            "Attack on Titan"
        )
        XCTAssertEqual(
            ShowCatalog.derivedShow(from: "The Rumbling - Attack on Titan Final Season OP [Piano] ⧸ SiM"),
            "Attack on Titan"
        )
    }

    func testDerivedShowForJujutsuKaisen() {
        XCTAssertEqual(
            ShowCatalog.derivedShow(from: "SPECIALZ - Jujutsu Kaisen S2 OP2 [Piano] ⧸King Gnu"),
            "Jujutsu Kaisen"
        )
    }

    func testDerivedShowForChainsawMan() {
        XCTAssertEqual(
            ShowCatalog.derivedShow(from: "KICK BACK - Chainsaw Man OP [Piano] ⧸ Kenshi Yonezu"),
            "Chainsaw Man"
        )
    }

    func testDerivedShowWhenShowIsFirst() {
        // The "show - descriptor" shape (e.g. Frieren, Kantai Collection).
        XCTAssertEqual(
            ShowCatalog.derivedShow(from: "Frieren： Beyond Journey's End - Soundtrack Medley [Piano] ⧸ Evan Call"),
            "Frieren"
        )
        XCTAssertEqual(
            ShowCatalog.derivedShow(from: "Kantai Collection - Soundtrack Medley [Piano]"),
            "Kantai Collection"
        )
    }

    func testDerivedShowPrefersLongestMatch() {
        // "Neon Genesis Evangelion" must beat a bare "Evangelion".
        XCTAssertEqual(
            ShowCatalog.derivedShow(from: "A Cruel Angel's Thesis - Neon Genesis Evangelion OP [Piano]"),
            "Neon Genesis Evangelion"
        )
    }

    func testDerivedShowIsCaseInsensitive() {
        XCTAssertEqual(
            ShowCatalog.derivedShow(from: "something - attack on titan OST [Piano]"),
            "Attack on Titan"
        )
    }

    func testDerivedShowReturnsNilWhenNoKnownShow() {
        XCTAssertNil(ShowCatalog.derivedShow(from: "Some Random Song Nobody Knows [Piano]"))
        XCTAssertNil(ShowCatalog.derivedShow(from: "Sayonara Memories - Supercell [Piano]"))
        // ^ Supercell is an artist, not a show; catalog correctly misses.
    }

    // MARK: - acronym(of:)

    func testAcronymForSpaceSeparatedShows() {
        XCTAssertEqual(ShowCatalog.acronym(of: "Attack on Titan"), "AOT")
        XCTAssertEqual(ShowCatalog.acronym(of: "My Hero Academia"), "MHA")
        XCTAssertEqual(ShowCatalog.acronym(of: "No Game No Life"), "NGNL")
    }

    func testAcronymTreatsPunctuationAsSeparator() {
        // Slashes, colons, hyphens get split so "Fate/stay night" → "FSN".
        XCTAssertEqual(ShowCatalog.acronym(of: "Fate/stay night"), "FSN")
    }
}
