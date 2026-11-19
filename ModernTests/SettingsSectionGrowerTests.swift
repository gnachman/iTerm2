//
//  SettingsSectionGrowerTests.swift
//  ModernTests
//
//  Settings panes built in Interface Builder lay their sections out by frame.
//  Growing one at its bottom must move everything above it, even sections
//  that overlap it by a point or two, as they do in the Window pane.
//

import XCTest
@testable import iTerm2SharedARC

final class SettingsSectionGrowerTests: XCTestCase {
    func testMovesOverlappingSectionsAbove() {
        // The Window pane's frames: the middle section overlaps the bottom
        // one by 2pt.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 733, height: 838))
        let bottom = NSView(frame: NSRect(x: 3, y: 20, width: 730, height: 352))
        let middle = NSView(frame: NSRect(x: 0, y: 370, width: 733, height: 277))
        let top = NSView(frame: NSRect(x: 0, y: 646, width: 733, height: 161))
        let inside = NSView(frame: NSRect(x: 169, y: 0, width: 427, height: 21))
        bottom.addSubview(inside)
        for view in [bottom, middle, top] {
            container.addSubview(view)
        }

        SettingsSectionGrower.grow(bottom, atBottomBy: 30)

        XCTAssertEqual(container.frame.height, 868)
        XCTAssertEqual(bottom.frame, NSRect(x: 3, y: 20, width: 730, height: 382))
        XCTAssertEqual(inside.frame.minY, 30, "the section's contents keep their place at its top")
        XCTAssertEqual(middle.frame.minY, 400)
        XCTAssertEqual(top.frame.minY, 676)
        XCTAssertLessThanOrEqual(bottom.frame.maxY - middle.frame.minY, 2, "no more overlap than before")
    }

    // A view loaded from a nib records its size in its own awakeFromNib,
    // which may come after the controller's. Until then there's nothing to
    // adjust: it records the grown size itself.
    func testLeavesAnUnrecordedOriginalSizeAlone() {
        let container = iTermSizeRememberingView(frame: .zero)
        container.setFrameSize(NSSize(width: 733, height: 838))
        XCTAssertEqual(container.originalSize, .zero, "precondition: not recorded yet")
        let section = NSView(frame: NSRect(x: 0, y: 20, width: 733, height: 352))
        container.addSubview(section)
        SettingsSectionGrower.grow(section, atBottomBy: 30)
        XCTAssertEqual(container.originalSize, .zero)
        XCTAssertEqual(container.frame.height, 868)
    }

    func testAdjustsARecordedOriginalSize() {
        let container = iTermSizeRememberingView(frame: NSRect(x: 0, y: 0, width: 733, height: 838))
        let section = NSView(frame: NSRect(x: 0, y: 20, width: 733, height: 352))
        container.addSubview(section)
        SettingsSectionGrower.grow(section, atBottomBy: 30)
        XCTAssertEqual(container.originalSize, NSSize(width: 733, height: 868))
    }

    // Settings wraps a tall pane in a scroll view, maybe before the pane
    // grows. The scroll view's document view has to grow with it, or the
    // bottom can't be scrolled to.
    func testGrowsTheScrollViewsDocumentView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 733, height: 492))
        let document = iTermFlippedView(frame: NSRect(x: 0, y: 0, width: 716, height: 838))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 716, height: 838))
        // As the Window pane's is. Resizing the document must not grow it a
        // second time.
        container.autoresizingMask = [.width, .height]
        let section = NSView(frame: NSRect(x: 0, y: 20, width: 716, height: 352))
        container.addSubview(section)
        document.addSubview(container)
        scrollView.documentView = document

        SettingsSectionGrower.grow(section, atBottomBy: 30)

        XCTAssertEqual(container.frame.height, 868)
        XCTAssertEqual(document.frame.height, 868)
        XCTAssertEqual(container.frame.minY, 0, "the pane stays at the top")
    }
}
