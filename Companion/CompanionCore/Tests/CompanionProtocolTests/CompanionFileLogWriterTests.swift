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
}
