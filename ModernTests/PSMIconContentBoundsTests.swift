//
//  PSMIconContentBoundsTests.swift
//  ModernTests
//
//  Some tab icons aren't centered in their canvas (the new-output dot sits
//  right of and below center). A collapsed group chip centers what's actually
//  drawn, so it needs the icon's visible bounds.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMIconContentBoundsTests: XCTestCase {
    // A 16pt image with a 6pt square whose top-left is at (8, 6), measured
    // from the top left.
    private func offCenterImage() -> NSImage {
        return NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.red.setFill()
            NSRect(x: 8, y: 6, width: 6, height: 6).fill()
            return true
        }
    }

    func testVisibleBoundsAreMeasuredFromTheTopLeft() {
        let bounds = PSMIconContentBounds.visibleBounds(of: offCenterImage())
        XCTAssertEqual(bounds.minX, 8, accuracy: 0.5)
        XCTAssertEqual(bounds.minY, 6, accuracy: 0.5)
        XCTAssertEqual(bounds.width, 6, accuracy: 0.5)
        XCTAssertEqual(bounds.height, 6, accuracy: 0.5)
    }

    func testEmptyImageUsesItsWholeCanvas() {
        let empty = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in true }
        XCTAssertEqual(PSMIconContentBounds.visibleBounds(of: empty), NSRect(x: 0, y: 0, width: 16, height: 16))
    }

    // Where to draw an image so its visible part is centered on a point, in a
    // flipped view.
    func testRectCenteringVisibleContent() {
        let rect = PSMIconContentBounds.rect(centeringVisibleContentOf: offCenterImage(),
                                             at: NSPoint(x: 100, y: 50),
                                             size: 16)
        // Visible center is (11, 9) in the image, so the image starts 11 left
        // and 9 above the target.
        XCTAssertEqual(rect.minX, 89, accuracy: 0.5)
        XCTAssertEqual(rect.minY, 41, accuracy: 0.5)
        XCTAssertEqual(rect.width, 16)
    }
}
