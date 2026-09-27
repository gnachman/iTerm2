//
//  BidiFindOnPageAnchorTests.swift
//  ModernTests
//
//  Find-on-page shift-extend: the reachable path is "plain click (which cleared
//  the selection and stored a VISUAL click coord as the find cursor), then
//  shift-click". Both the find cursor and the click are therefore VISUAL and must
//  be converted to logical. Converting only the click anchored the range at the
//  raw visual find-cursor column, i.e. the mirror-image cell on an RTL line.
//

import XCTest
@testable import iTerm2SharedARC

final class BidiFindOnPageAnchorTests: XCTestCase {
    // FAILING until the fix: with a non-identity (RTL) mapping, BOTH endpoints must
    // be converted. Mirror mapper for a width-10 line: logical = 9 - visual.
    func testShiftExtendConvertsBothEndpoints() {
        let range = iTermSelection.logicalAbsRange(fromVisualStart: VT100GridCoordMake(2, 0),
                                                   visualEnd: VT100GridCoordMake(7, 0),
                                                   overflow: 0) { v in
            VT100GridCoordMake(9 - v.x, v.y)
        }
        XCTAssertEqual(range.coordRange.start.x, 7,
                       "the find cursor (visual) must be converted to logical, not used raw")
        XCTAssertEqual(range.coordRange.end.x, 2,
                       "the click (visual) must be converted to logical")
        XCTAssertEqual(range.coordRange.start.y, 0)
        XCTAssertEqual(range.coordRange.end.y, 0)
    }

    // Identity mapper (no reordering): both endpoints pass through unchanged.
    func testShiftExtendIdentityMapperIsNoOp() {
        let range = iTermSelection.logicalAbsRange(fromVisualStart: VT100GridCoordMake(2, 0),
                                                   visualEnd: VT100GridCoordMake(7, 0),
                                                   overflow: 0) { $0 }
        XCTAssertEqual(range.coordRange.start.x, 2)
        XCTAssertEqual(range.coordRange.end.x, 7)
    }
}
