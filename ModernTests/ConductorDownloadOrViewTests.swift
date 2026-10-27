//
//  ConductorDownloadOrViewTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

// F-960: with the browser plugin installed, “Download using SSH Integration” on a file with a
// known MIME type examined the file before asking whether to download or view it, and did
// nothing at all when that failed (for example, a name in older output, whose path was built
// from a different working directory). It must download instead, so the failure is reported.
@MainActor
final class ConductorDownloadOrViewTests: XCTestCase {
    private struct Missing: Error {}

    func testFileAsks() async {
        let choice = await Conductor.downloadOrViewChoice(path: "/home/user/c.txt") { path in
            RemoteFile(kind: .file(.init(size: 3)), absolutePath: path)
        }
        XCTAssertEqual(choice, .ask)
    }

    func testFolderDownloads() async {
        let choice = await Conductor.downloadOrViewChoice(path: "/home/user/sub.txt") { path in
            RemoteFile(kind: .folder, absolutePath: path)
        }
        XCTAssertEqual(choice, .download)
    }

    func testFailedStatDownloadsSoTheFailureIsReported() async {
        let choice = await Conductor.downloadOrViewChoice(path: "/home/user/c.txt") { _ in
            throw Missing()
        }
        XCTAssertEqual(choice, .download)
    }
}
