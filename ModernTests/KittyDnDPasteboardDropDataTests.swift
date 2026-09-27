//
//  KittyDnDPasteboardDropDataTests.swift
//  iTerm2 ModernTests
//
//  Phase 4 of the Kitty drag-and-drop protocol (OSC 72). See
//  docs/kitty-dnd-design.md. Pins the MIME ordering and data mapping of the drop
//  data snapshot the terminal builds from a drag pasteboard.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class KittyDnDPasteboardDropDataTests: XCTestCase {
    func testFilesOnlyOfferUriList() {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt")]
        let drop = KittyDnDPasteboardDropData(fileURLs: urls, text: nil, png: nil)
        XCTAssertEqual(drop.mimeTypes, ["text/uri-list"])
        XCTAssertEqual(drop.fileURLs, urls)
        // The controller builds the uri-list from fileURLs, so no inline data.
        XCTAssertNil(drop.data(forMimeIndex: 1))
    }

    func testTextOnlyOffersPlain() {
        let drop = KittyDnDPasteboardDropData(fileURLs: [], text: "hello", png: nil)
        XCTAssertEqual(drop.mimeTypes, ["text/plain"])
        XCTAssertEqual(drop.data(forMimeIndex: 1), Data("hello".utf8))
    }

    func testImageOnlyOffersPng() {
        let png = Data([0x89, 0x50, 0x4e, 0x47])
        let drop = KittyDnDPasteboardDropData(fileURLs: [], text: nil, png: png)
        XCTAssertEqual(drop.mimeTypes, ["image/png"])
        XCTAssertEqual(drop.data(forMimeIndex: 1), png)
    }

    // Ordering is files (uri-list), then text, then image, with 1-based indices.
    func testCombinedOrderingAndIndices() {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt")]
        let png = Data([1, 2, 3])
        let drop = KittyDnDPasteboardDropData(fileURLs: urls, text: "hi", png: png)
        XCTAssertEqual(drop.mimeTypes, ["text/uri-list", "text/plain", "image/png"])
        XCTAssertNil(drop.data(forMimeIndex: 1))            // uri-list
        XCTAssertEqual(drop.data(forMimeIndex: 2), Data("hi".utf8))
        XCTAssertEqual(drop.data(forMimeIndex: 3), png)
    }

    func testEmptyPasteboardYieldsNoMimeTypes() {
        let drop = KittyDnDPasteboardDropData(fileURLs: [], text: nil, png: nil)
        XCTAssertTrue(drop.mimeTypes.isEmpty)
    }
}
