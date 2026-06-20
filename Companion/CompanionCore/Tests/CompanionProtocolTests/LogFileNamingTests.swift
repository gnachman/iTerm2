//
//  LogFileNamingTests.swift
//  CompanionCore
//
//  The file logger names each launch's file YYYY-MM-DD_HH-MM-SS.log so they sort
//  by creation time, and prunes files older than the retention window by the
//  timestamp encoded in the name. These are the pure, testable pieces of that.
//

import XCTest
@testable import CompanionProtocol

final class LogFileNamingTests: XCTestCase {
    func test_fileNameHasTheSortableTimestampShape() {
        let name = LogFileNaming.fileName(for: Date(timeIntervalSince1970: 0))
        // YYYY-MM-DD_HH-MM-SS.log
        XCTAssertNotNil(name.range(of: #"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.log$"#,
                                   options: .regularExpression), name)
    }

    func test_roundTripsToTheSecond() {
        let when = Date(timeIntervalSince1970: 1_781_640_000) // arbitrary fixed instant
        let parsed = LogFileNaming.date(from: LogFileNaming.fileName(for: when))
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!.timeIntervalSince1970, when.timeIntervalSince1970, accuracy: 1.0)
    }

    func test_labeledNameShapeAndRoundTrip() {
        let when = Date(timeIntervalSince1970: 1_781_640_000)
        let name = LogFileNaming.fileName(for: when, label: "nse")
        XCTAssertNotNil(name.range(of: #"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-nse\.log$"#,
                                   options: .regularExpression), name)
        // The label-tagged name still parses back to the same instant.
        let parsed = LogFileNaming.date(from: name)
        XCTAssertEqual(parsed?.timeIntervalSince1970 ?? -1, when.timeIntervalSince1970, accuracy: 1.0)
    }

    func test_labeledFilesAreExpiredByTimestamp() {
        let now = Date(timeIntervalSince1970: 1_781_640_000)
        let oldNSE = LogFileNaming.fileName(for: now.addingTimeInterval(-15 * 86400), label: "nse")
        let recentApp = LogFileNaming.fileName(for: now.addingTimeInterval(-1 * 86400), label: "app")
        let expired = LogFileNaming.expired([oldNSE, recentApp], now: now, maxAgeDays: 14)
        XCTAssertEqual(expired, [oldNSE])
    }

    func test_parsingRejectsNonLogAndGarbage() {
        XCTAssertNil(LogFileNaming.date(from: "notes.txt"))
        XCTAssertNil(LogFileNaming.date(from: "hello.log"))
        XCTAssertNil(LogFileNaming.date(from: "2026-13-40_99-99-99.log"))
        XCTAssertNil(LogFileNaming.date(from: "garbage-nse.log"))
    }

    func test_expiredPicksOnlyFilesOlderThanTheWindow() {
        let now = Date(timeIntervalSince1970: 1_781_640_000)
        let old = LogFileNaming.fileName(for: now.addingTimeInterval(-15 * 86400))
        let recent = LogFileNaming.fileName(for: now.addingTimeInterval(-13 * 86400))
        let names = [old, recent, "unrelated.txt"]

        let expired = LogFileNaming.expired(names, now: now, maxAgeDays: 14)

        XCTAssertEqual(expired, [old]) // recent kept, unrelated never touched
    }
}
