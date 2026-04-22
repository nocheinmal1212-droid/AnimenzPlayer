import XCTest
@testable import AnimenzPlayer

final class RepeatModeTests: XCTestCase {
    func testCycleOrder() {
        XCTAssertEqual(RepeatMode.off.cycled, .all)
        XCTAssertEqual(RepeatMode.all.cycled, .one)
        XCTAssertEqual(RepeatMode.one.cycled, .off)
    }

    func testIsActive() {
        XCTAssertFalse(RepeatMode.off.isActive)
        XCTAssertTrue(RepeatMode.all.isActive)
        XCTAssertTrue(RepeatMode.one.isActive)
    }

    func testCodableRoundTrip() throws {
        // Persistence relies on RepeatMode encoding stably across versions.
        // This test locks in the raw-value encoding.
        let encoded = try JSONEncoder().encode(RepeatMode.one)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), "\"one\"")

        let decoded = try JSONDecoder().decode(RepeatMode.self, from: encoded)
        XCTAssertEqual(decoded, .one)
    }

    func testAllCasesPresent() {
        // Guard against accidental removal; the UI's segmented picker
        // depends on all three being present.
        XCTAssertEqual(Set(RepeatMode.allCases), [.off, .all, .one])
    }
}
