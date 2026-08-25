//
//  KittyDnDViewDragHostTests.swift
//  iTerm2 ModernTests
//
//  Phase 4 of the Kitty drag-and-drop protocol (OSC 72). See
//  docs/kitty-dnd-design.md. The native drag itself is not unit-testable, but
//  the drag host's uri-list parsing is pure logic and pinned here.
//

import XCTest
@testable import iTerm2SharedARC

final class KittyDnDViewDragHostTests: XCTestCase {
    func testParsesFileURLs() {
        let list = "file:///tmp/a.txt\r\nfile:///tmp/b.txt"
        let urls = KittyDnDViewDragHost.parseFileURLs(uriList: list)
        XCTAssertEqual(urls.map { $0.path }, ["/tmp/a.txt", "/tmp/b.txt"])
    }

    func testIgnoresBlankAndCommentLines() {
        let list = "# a comment\r\n\r\nfile:///tmp/a.txt\r\n# another\r\n"
        let urls = KittyDnDViewDragHost.parseFileURLs(uriList: list)
        XCTAssertEqual(urls.map { $0.path }, ["/tmp/a.txt"])
    }

    func testDropsNonFileURLs() {
        let list = "https://example.com/x\r\nfile:///tmp/a.txt"
        let urls = KittyDnDViewDragHost.parseFileURLs(uriList: list)
        XCTAssertEqual(urls.map { $0.path }, ["/tmp/a.txt"])
    }

    func testHandlesLoneLineFeeds() {
        let list = "file:///tmp/a.txt\nfile:///tmp/b.txt\n"
        let urls = KittyDnDViewDragHost.parseFileURLs(uriList: list)
        XCTAssertEqual(urls.count, 2)
    }

    func testEmptyListYieldsNoURLs() {
        XCTAssertTrue(KittyDnDViewDragHost.parseFileURLs(uriList: "").isEmpty)
    }
}
