//
//  BidiFindOnPageSelectionTests.swift
//  ModernTests
//
//  Finding A: find-on-page selected the VISUAL range of a match and handed it to
//  selectCoordRange:, which stores a LOGICAL committed subselection. The logical
//  draw/copy layer then re-mapped it, so on a right-to-left line a find hit
//  highlighted and copied the mirror-image cells. The selection must be the
//  logical match range; only the on-screen find indicator uses the visual range.
//  (The sibling global-search path already passes logical straight through.)
//

import XCTest
@testable import iTerm2SharedARC

final class BidiFindOnPageSelectionTests: XCTestCase {
    // FAILING until the fix: the selection range for a find match must be the
    // LOGICAL range, not the visual one. On a bidi line these differ.
    func testFindOnPageSelectsLogicalMatchNotVisual() {
        let logical = VT100GridCoordRangeMake(2, 0, 5, 0)
        // On an RTL line the same match resolves to a different visual span.
        let visual = VT100GridCoordRangeMake(74, 0, 77, 0)

        let result = PTYTextView.findOnPageSelectionRange(forLogicalMatch: logical,
                                                          visualMatch: visual)

        XCTAssertEqual(result.start.x, logical.start.x,
                       "find-on-page must select the logical match range, not the visual one")
        XCTAssertEqual(result.start.y, logical.start.y)
        XCTAssertEqual(result.end.x, logical.end.x)
        XCTAssertEqual(result.end.y, logical.end.y)
    }

    // The visual range remains available for the on-screen indicator; the helper
    // must not simply echo its input regardless of arguments.
    func testFindOnPageSelectionIgnoresVisualWhenItDiffers() {
        let logical = VT100GridCoordRangeMake(0, 3, 4, 3)
        let visual = VT100GridCoordRangeMake(10, 3, 14, 3)
        let result = PTYTextView.findOnPageSelectionRange(forLogicalMatch: logical,
                                                          visualMatch: visual)
        XCTAssertNotEqual(result.start.x, visual.start.x,
                          "the selection range must not be the visual range on a bidi line")
    }
}
