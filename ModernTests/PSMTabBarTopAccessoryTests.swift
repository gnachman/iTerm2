//
//  PSMTabBarTopAccessoryTests.swift
//  ModernTests
//
//  A vertical tab bar can show a view, such as a search field, in a band at
//  its top. The window reserves the band by adding it to the bar's top inset,
//  and the bar centers the view in it.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabBarTopAccessoryTests: XCTestCase {
    private var control: PSMTabBarControl!
    private var accessory: NSView!

    override func setUp() {
        super.setUp()
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        control.style.tabBar = control
        control.orientation = .verticalOrientation
        accessory = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 22))
    }

    override func tearDown() {
        control = nil
        accessory = nil
        super.tearDown()
    }

    func testCenteredInTheBandBelowTheRestOfTheInset() {
        control.insets = NSEdgeInsets(top: 40, left: 4, bottom: 0, right: 6)
        control.topAccessoryBandHeight = 30
        control.topAccessoryView = accessory
        XCTAssertTrue(accessory.superview === control)
        XCTAssertFalse(accessory.isHidden)
        // The band is the last 30 points of the 40 point inset.
        XCTAssertEqual(accessory.frame, NSRect(x: 4 + 8, y: 10 + 4, width: 200 - 4 - 6 - 16, height: 22))
    }

    func testFollowsInsetAndWidthChanges() {
        control.topAccessoryBandHeight = 30
        control.topAccessoryView = accessory
        control.insets = NSEdgeInsets(top: 50, left: 0, bottom: 0, right: 0)
        XCTAssertEqual(accessory.frame.minY, 24)
        control.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        XCTAssertEqual(accessory.frame.width, 300 - 16)
    }

    // A horizontal bar has no room for it.
    func testHiddenOnAHorizontalBar() {
        control.topAccessoryBandHeight = 30
        control.topAccessoryView = accessory
        control.orientation = .horizontalOrientation
        XCTAssertTrue(accessory.isHidden)
        control.orientation = .verticalOrientation
        XCTAssertFalse(accessory.isHidden)
    }

    func testReplacingRemovesTheOldView() {
        control.topAccessoryBandHeight = 30
        control.topAccessoryView = accessory
        control.topAccessoryView = nil
        XCTAssertNil(accessory.superview)
    }
}
