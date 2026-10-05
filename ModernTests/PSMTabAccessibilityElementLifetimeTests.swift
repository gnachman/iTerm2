//
//  PSMTabAccessibilityElementLifetimeTests.swift
//  ModernTests
//
//  Each tab cell vends an accessibility element (and a child for its close button) that refers
//  back to the cell. Assistive apps can hold on to an element after its tab closes and the cell is
//  freed, and then ask it for its parent. The elements kept an unretained, non-zeroing reference,
//  so that messaged the freed cell and crashed in -[PSMTabAccessibilityElement accessibilityParent].
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabAccessibilityElementLifetimeTests: XCTestCase {
    func testElementsOutliveTheirCell() throws {
        let control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 600, height: 24))
        var tabElement: NSAccessibilityElement?
        var closeButtonElement: Any?
        autoreleasepool {
            let cell = PSMTabBarCell(controlView: control)!
            tabElement = cell.element
            closeButtonElement = cell.element.accessibilityChildren()?.first
            XCTAssertNotNil(tabElement?.accessibilityParent(), "Precondition: the element's parent is the control")
        }
        // The cell is gone. Asking its elements about it must not touch freed memory.
        let element = try XCTUnwrap(tabElement)
        XCTAssertNil(element.accessibilityParent())
        _ = element.accessibilityLabel()
        _ = element.accessibilityFrame()
        let closeButton = try XCTUnwrap(closeButtonElement as? NSAccessibilityElement)
        XCTAssertNil(closeButton.accessibilityParent())
        _ = closeButton.accessibilityFrame()
    }
}
