//
//  CompanionFileLogWriterTests.swift
//  CompanionCore
//
//  The short-lived-process file writer: writes when enabled, is silent when
//  disabled, and exposes its files for export. Uses a unique temp directory so
//  it never touches a real container and can't be flaky.
//

import XCTest
@testable import CompanionProtocol

final class CompanionFileLogWriterTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompanionFileLogWriterTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testWritesLinesWhenEnabled() throws {
        let writer = CompanionFileLogWriter(directory: dir, isEnabled: { true })
        writer.log("hello")
        writer.log("world")

        let urls = writer.logFileURLs()
        XCTAssertEqual(urls.count, 1)
        let contents = try String(contentsOf: try XCTUnwrap(urls.first), encoding: .utf8)
        XCTAssertTrue(contents.contains("hello"))
        XCTAssertTrue(contents.contains("world"))
        XCTAssertEqual(contents.split(separator: "\n").count, 2)
    }

    func testSilentWhenDisabled() throws {
        let writer = CompanionFileLogWriter(directory: dir, isEnabled: { false })
        writer.log("nope")
        XCTAssertTrue(writer.logFileURLs().isEmpty)
    }

    func testStaticEnumerationMatches() throws {
        let writer = CompanionFileLogWriter(directory: dir, isEnabled: { true })
        writer.log("x")
        XCTAssertEqual(CompanionFileLogWriter.logFileURLs(in: dir), writer.logFileURLs())
    }

    func testConcurrentWritersToSameFileDoNotLoseOrTearLines() throws {
        // Two writers with SEPARATE locks (no shared serialization) appending to
        // the SAME file model two concurrent NSE processes. With O_APPEND every
        // line must survive intact; a seek-then-write would lose/tear lines.
        let fixedNow = { Date(timeIntervalSince1970: 1_000_000) }   // pins one file name
        let a = CompanionFileLogWriter(directory: dir, label: "nse", now: fixedNow, isEnabled: { true })
        let b = CompanionFileLogWriter(directory: dir, label: "nse", now: fixedNow, isEnabled: { true })
        let perWriter = 300

        DispatchQueue.concurrentPerform(iterations: perWriter * 2) { i in
            let writer = (i % 2 == 0) ? a : b
            // Distinct, fixed-shape payload per line so we can verify integrity.
            writer.log("W\(i % 2)-\(String(format: "%05d", i)) payload-marker")
        }

        let urls = a.logFileURLs()
        XCTAssertEqual(urls.count, 1, "both writers shared one file")
        let contents = try String(contentsOf: try XCTUnwrap(urls.first), encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, perWriter * 2, "no line was overwritten")
        for line in lines {
            // Each line is intact: it carries exactly one payload marker (no
            // interleaving) and ends as written.
            XCTAssertEqual(line.components(separatedBy: "payload-marker").count, 2,
                           "a torn/interleaved line: \(line)")
        }
        XCTAssertEqual(Set(lines).count, perWriter * 2, "every distinct line is present exactly once")
    }
}
