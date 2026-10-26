//
//  SSHRemoteZipReplyTests.swift
//  iTerm2
//
//  F-721: downloading a folder over SSH Integration silently left out any file in it that
//  couldn't be read. The framer now reports what it left out of the archive, and the
//  download finishes with a note that says so.
//

import XCTest
@testable import iTerm2SharedARC

final class SSHRemoteZipReplyTests: XCTestCase {
    // iTerm2 asks for the report, and a framer that predates it ignores the extra argument.
    func testZipCommandAsksForSkippedFileReport() {
        let path = "/home/user/dir"
        let command = Conductor.FileSubcommand.zip(path: path.data(using: .utf8)!)
        XCTAssertEqual(command.stringValue,
                       "zip\n\(path.data(using: .utf8)!.base64EncodedString())\nreport-skipped")
    }

    // An older framer replies with just the archive's path.
    func testBarePathFromOlderFramer() {
        let reply = SSHRemoteZipReply(framerOutput: "/home/user/.abc123")
        XCTAssertEqual(reply.path, "/home/user/.abc123")
        XCTAssertEqual(reply.skippedCount, 0)
        XCTAssertNil(reply.skippedItemsNote)
    }

    func testNothingSkipped() {
        let reply = SSHRemoteZipReply(framerOutput: #"{"path": "/home/user/.abc", "skipped": 0, "examples": []}"#)
        XCTAssertEqual(reply.path, "/home/user/.abc")
        XCTAssertEqual(reply.skippedCount, 0)
        XCTAssertNil(reply.skippedItemsNote)
    }

    func testOneSkipped() {
        let reply = SSHRemoteZipReply(framerOutput: #"{"path": "/home/user/.abc", "skipped": 1, "examples": ["secret.txt"]}"#)
        XCTAssertEqual(reply.path, "/home/user/.abc")
        XCTAssertEqual(reply.skippedItemsNote, "“secret.txt” couldn’t be read and was left out.")
    }

    func testTwoSkipped() {
        let reply = SSHRemoteZipReply(framerOutput: #"{"path": "/home/user/.abc", "skipped": 2, "examples": ["a", "sub/"]}"#)
        XCTAssertEqual(reply.skippedItemsNote, "“a” and “sub/” couldn’t be read and were left out.")
    }

    func testManySkipped() {
        let reply = SSHRemoteZipReply(framerOutput: #"{"path": "/home/user/.abc", "skipped": 5, "examples": ["a", "b", "c"]}"#)
        XCTAssertEqual(reply.skippedItemsNote, "5 items couldn’t be read and were left out. One of them is “a”.")
    }

    func testSkippedWithoutNames() {
        let reply = SSHRemoteZipReply(framerOutput: #"{"path": "/home/user/.abc", "skipped": 1, "examples": []}"#)
        XCTAssertEqual(reply.skippedItemsNote, "1 item couldn’t be read and was left out.")
    }

    // Extra fields from a future framer are ignored.
    func testUnknownFieldsAreIgnored() {
        let reply = SSHRemoteZipReply(framerOutput: #"{"path": "/x", "skipped": 2, "examples": ["a", "b"], "new": true}"#)
        XCTAssertEqual(reply.path, "/x")
        XCTAssertEqual(reply.skippedCount, 2)
    }
}
