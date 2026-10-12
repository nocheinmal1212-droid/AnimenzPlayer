#if os(macOS)
import XCTest
@testable import AnimenzPlayer

final class PlaybackDiagnosticsTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PlaybackDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func events(_ data: Data) throws -> [[String: Any]] {
        try String(decoding: data, as: UTF8.self).split(separator: "\n")
            .filter { $0.first == "{" }
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
    }

    func testRetainsEarlierSessionAfterReopeningStore() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var first: PlaybackDiagnostics? = PlaybackDiagnostics(directory: dir)
        let firstSession = first!.sessionID
        first!.record("before.restart")
        _ = try await first!.exportData()
        first = nil
        let second = PlaybackDiagnostics(directory: dir)
        second.record("after.restart")
        let entries = try events(await second.exportData())
        XCTAssertTrue(entries.contains { $0["event"] as? String == "before.restart" && $0["session"] as? String == firstSession })
        XCTAssertTrue(entries.contains { $0["event"] as? String == "after.restart" && $0["session"] as? String == second.sessionID })
        XCTAssertNotEqual(firstSession, second.sessionID)
    }

    func testExportIncludesAllEarlierAcceptedEventsWithoutEndingSession() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let logger = PlaybackDiagnostics(directory: dir)
        for index in 0..<100 { logger.record("test.event", fields: ["index": String(index)]) }
        let first = try events(await logger.exportData())
        XCTAssertEqual(first.count, 101)
        logger.record("after.export")
        let second = try events(await logger.exportData())
        XCTAssertEqual(second.count, 102)
        XCTAssertEqual(second.last?["event"] as? String, "after.export")
        XCTAssertEqual(second.compactMap { $0["sequence"] as? Int }, Array(1...102))
    }

    func testRotationIsBoundedAndKeepsNewestEventsInOrder() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let logger = PlaybackDiagnostics(directory: dir, maxFileBytes: 1024, fileCount: 3)
        for index in 0..<60 {
            logger.record("rotation", fields: ["index": String(index), "payload": String(repeating: "x", count: 500)])
        }
        let entries = try events(await logger.exportData())
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3)
        for file in files { XCTAssertLessThanOrEqual(try Data(contentsOf: file).count, 1024) }
        let indices = entries.compactMap { ($0["fields"] as? [String: String])?["index"].flatMap(Int.init) }
        XCTAssertEqual(indices.last, 59)
        XCTAssertEqual(indices, indices.sorted())
        XCTAssertFalse(indices.contains(0))
    }

    func testConcurrentProducersDoNotCorruptLogLines() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let logger = PlaybackDiagnostics(directory: dir)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<200 { group.addTask { logger.record("concurrent", fields: ["index": String(index)]) } }
        }
        let entries = try events(await logger.exportData())
        let indices = entries.compactMap { ($0["fields"] as? [String: String])?["index"] }
        XCTAssertEqual(Set(indices).count, 200)
        XCTAssertEqual(entries.count, 201)
    }

    func testDiskFailureIsReportedAndNextWriteCanRecover() async throws {
        let blocker = directory()
        let dir = blocker.appendingPathComponent("logs")
        defer { try? FileManager.default.removeItem(at: blocker) }
        try Data("not a directory".utf8).write(to: blocker)
        let logger = PlaybackDiagnostics(directory: dir)
        logger.record("cannot.write")
        do {
            _ = try await logger.exportData()
            XCTFail("Expected export to fail when no log could be saved")
        } catch { }
        try FileManager.default.removeItem(at: blocker)
        logger.record("recovered")
        let data = try await logger.exportData()
        XCTAssertEqual(try events(data).last?["event"] as? String, "recovered")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Write failures this session: 2"))
    }

    func testOversizedEventCannotExceedRotationBudget() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let logger = PlaybackDiagnostics(directory: dir, maxFileBytes: 1024)
        logger.record("oversized", fields: Dictionary(uniqueKeysWithValues: (0..<32).map { (String($0), String(repeating: "x", count: 2000)) }))
        let entries = try events(await logger.exportData())
        let fields = try XCTUnwrap(entries.last?["fields"] as? [String: String])
        XCTAssertNotNil(fields["truncated"])
        XCTAssertLessThanOrEqual(try Data(contentsOf: dir.appendingPathComponent("playback-0.jsonl")).count, 1024)
    }

    func testTrackIdentifiersAndErrorsExcludePathsAndTitles() {
        let first = URL(fileURLWithPath: "/Users/private/Music/My Song.m4a")
        let relocated = URL(fileURLWithPath: "/Applications/Player.app/Music/My Song.m4a")
        XCTAssertEqual(PlaybackDiagnostics.trackID(first), PlaybackDiagnostics.trackID(relocated))
        XCTAssertFalse(PlaybackDiagnostics.trackID(first).contains("Song"))
        let error = NSError(domain: "AVFoundationErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: first.path, NSURLErrorKey: first])
        XCTAssertEqual(PlaybackDiagnostics.errorFields(error), ["errorDomain": "AVFoundationErrorDomain", "errorCode": "-1"])
    }
}
#endif
