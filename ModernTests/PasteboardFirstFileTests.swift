//
//  PasteboardFirstFileTests.swift
//  iTerm2 ModernTests
//
//  -hasReadableFirstFile must answer the same question as -dataForFirstFile without
//  reading the file, because menu validation calls it every time the Edit menu opens.
//

import XCTest
@testable import iTerm2SharedARC

final class PasteboardFirstFileTests: XCTestCase {

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteboardFirstFileTests-\(UUID().uuidString)"))
        addTeardownBlock {
            pasteboard.releaseGlobally()
        }
        return pasteboard
    }

    private func makeTempFile(_ contents: Data = Data("hello".utf8)) throws -> String {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(
            "PasteboardFirstFileTests-\(UUID().uuidString)")
        try contents.write(to: URL(fileURLWithPath: path))
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: path)
        }
        return path
    }

    private func makeTempDirectory() throws -> String {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(
            "PasteboardFirstFileTests-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: path)
        }
        return path
    }

    func test_hasReadableFirstFile_emptyPasteboard() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        XCTAssertFalse(pasteboard.hasReadableFirstFile())
        XCTAssertNil(pasteboard.dataForFirstFile())
    }

    func test_hasReadableFirstFile_stringOnly() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("not a file", forType: .string)
        XCTAssertFalse(pasteboard.hasReadableFirstFile())
        XCTAssertNil(pasteboard.dataForFirstFile())
    }

    func test_hasReadableFirstFile_regularFile() throws {
        let path = try makeTempFile()
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
        XCTAssertTrue(pasteboard.hasReadableFirstFile())
        XCTAssertNotNil(pasteboard.dataForFirstFile())
    }

    func test_hasReadableFirstFile_emptyFile() throws {
        let path = try makeTempFile(Data())
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
        XCTAssertTrue(pasteboard.hasReadableFirstFile())
        XCTAssertNotNil(pasteboard.dataForFirstFile())
    }

    func test_hasReadableFirstFile_directory() throws {
        // -dataForFirstFile cannot read a directory, so validation must not enable the
        // menu item for one.
        let path = try makeTempDirectory()
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
        XCTAssertFalse(pasteboard.hasReadableFirstFile())
        XCTAssertNil(pasteboard.dataForFirstFile())
    }

    func test_hasReadableFirstFile_deletedFile() throws {
        let path = try makeTempFile()
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
        try FileManager.default.removeItem(atPath: path)
        XCTAssertFalse(pasteboard.hasReadableFirstFile())
        XCTAssertNil(pasteboard.dataForFirstFile())
    }
}
