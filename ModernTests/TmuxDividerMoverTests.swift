//
//  TmuxDividerMoverTests.swift
//  iTerm2
//
//  Checks the select-layout strings iTermTmuxDividerMover builds to match what a divider drag
//  previewed. Checksums are covered by TmuxLayoutBuilderLayoutStringTests, so only the part after
//  the checksum is compared.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxDividerMoverTests: XCTestCase {
    // +-----+-----+----+----+
    // |  0  |  3  |    |    |
    // +-----+-----+ 1  | 5  |
    // |  2  |  4  |    |    |
    // +-----+-----+----+----+
    private let threeColumns =
        "0000,80x24,0,0{39x24,0,0[39x12,0,0{19x12,0,0,0,19x12,20,0,3},39x11,0,13{19x11,0,13,2,19x11,20,13,4}],19x24,40,0,1,20x24,60,0,5}"

    // The widths of threeColumns.
    private let threeColumnsWidths: [Int32: Double] = [0: 19, 3: 19, 2: 19, 4: 19, 1: 19, 5: 20]

    // +-----+-----+-----+-----+
    // |  0  |  1  |  4  |  5  |
    // +-----+-----+-----+-----+
    // |  2  |  3  |  6  |  7  |
    // +-----+-----+-----+-----+
    private let twoGrids =
        "0000,81x24,0,0{40x24,0,0[40x12,0,0{20x12,0,0,0,19x12,21,0,1},40x11,0,13{20x11,0,13,2,19x11,21,13,3}],40x24,41,0[40x12,41,0{20x12,41,0,4,19x12,62,0,5},40x11,41,13{20x11,41,13,6,19x11,62,13,7}]}"

    // +-----+-----+
    // |  0  |  1  |
    // +-----+-----+
    // |     2     |
    // +-----------+
    private let rows =
        "0000,41x25,0,0[41x12,0,0{20x12,0,0,0,20x12,21,0,1},41x12,0,13,2]"

    private func tree(_ layout: String,
                      paneBorderStatus: iTermTmuxPaneBorderStatus = .off) -> NSMutableDictionary {
        let parser = TmuxLayoutParser.sharedInstance()!
        let parsed = parser.parsedLayout(from: layout)!
        return parser.parseTree(parsed, adjustedFor: paneBorderStatus)
    }

    private func move(_ layout: String,
                      divider: Int,
                      panes: [Int32],
                      verticalDividers: Bool = true,
                      shown: [Int32: Double],
                      paneBorderStatus: iTermTmuxPaneBorderStatus = .off) -> String? {
        var extents = [NSNumber: NSNumber]()
        for (pane, extent) in shown {
            extents[NSNumber(value: pane)] = NSNumber(value: extent)
        }
        let result = TmuxDividerMover.layoutString(parseTree: tree(layout, paneBorderStatus: paneBorderStatus),
                                                   dividerIndex: divider,
                                                   panes: panes.map { NSNumber(value: $0) },
                                                   verticalDividers: verticalDividers,
                                                   measuredExtents: extents,
                                                   paneBorderStatus: paneBorderStatus)
        return result.map { String($0.dropFirst(5)) }
    }

    private func shown(_ base: [Int32: Double], _ changes: [Int32: Double]) -> [Int32: Double] {
        return base.merging(changes) { $1 }
    }

    // If nothing moved by a whole cell, tmux is sent the layout it already has.
    func testUnchangedPreviewKeepsLayout() {
        XCTAssertEqual(move(threeColumns, divider: 0, panes: [0, 1, 2, 3, 4, 5], shown: threeColumnsWidths),
                       String(threeColumns.dropFirst(5)))
        XCTAssertEqual(move(threeColumns, divider: 0, panes: [0, 1, 2, 3, 4, 5],
                            shown: shown(threeColumnsWidths, [3: 19.4, 4: 19.4, 1: 18.6])),
                       String(threeColumns.dropFirst(5)))
    }

    // The window spreads a drag over a nested split beside the divider in proportion to its
    // children's sizes, so tmux must too.
    func testNestedSplitSharesChangeAsShown() {
        XCTAssertEqual(move(threeColumns, divider: 0, panes: [0, 1, 2, 3, 4, 5],
                            shown: shown(threeColumnsWidths, [0: 21.4, 3: 21.6, 2: 21.4, 4: 21.6, 1: 14])),
                       "80x24,0,0{44x24,0,0[44x12,0,0{21x12,0,0,0,22x12,22,0,3},44x11,0,13{21x11,0,13,2,22x11,22,13,4}],14x24,45,0,1,20x24,60,0,5}")
    }

    func testNestedSplitsOnBothSides() {
        XCTAssertEqual(move(twoGrids, divider: 0, panes: [0, 1, 2, 3, 4, 5, 6, 7],
                            shown: [0: 21.5, 1: 20.5, 2: 21.5, 3: 20.5, 4: 18.5, 5: 17.5, 6: 18.5, 7: 17.5]),
                       "81x24,0,0{43x24,0,0[43x12,0,0{22x12,0,0,0,20x12,23,0,1},43x11,0,13{22x11,0,13,2,20x11,23,13,3}],37x24,44,0[37x12,44,0{19x12,44,0,4,17x12,64,0,5},37x11,44,13{19x11,44,13,6,17x11,64,13,7}]}")
    }

    // A divider is placed at the cell nearest where it was dropped.
    func testRoundsToNearestCell() {
        XCTAssertEqual(move(threeColumns, divider: 1, panes: [0, 1, 2, 3, 4, 5],
                            shown: shown(threeColumnsWidths, [1: 21.6, 5: 17.4])),
                       "80x24,0,0{39x24,0,0[39x12,0,0{19x12,0,0,0,19x12,20,0,3},39x11,0,13{19x11,0,13,2,19x11,20,13,4}],22x24,40,0,1,17x24,63,0,5}")
    }

    // The split is found by its panes, so an inner divider can be moved too, and nothing outside
    // its split changes.
    func testMovesInnerDivider() {
        XCTAssertEqual(move(threeColumns, divider: 0, panes: [0, 3],
                            shown: shown(threeColumnsWidths, [0: 21, 3: 17])),
                       "80x24,0,0{39x24,0,0[39x12,0,0{21x12,0,0,0,17x12,22,0,3},39x11,0,13{19x11,0,13,2,19x11,20,13,4}],19x24,40,0,1,20x24,60,0,5}")
    }

    // Horizontal dividers resize heights.
    func testHorizontalDivider() {
        XCTAssertEqual(move(rows, divider: 0, panes: [0, 1, 2], verticalDividers: false,
                            shown: [0: 15.2, 1: 15.2, 2: 8.8]),
                       "41x25,0,0[41x15,0,0{20x15,0,0,0,20x15,21,0,1},41x9,0,16,2]")
    }

    // Every pane keeps at least one cell, even if the preview showed less.
    func testClampsToMinimumPaneSize() {
        XCTAssertEqual(move(threeColumns, divider: 0, panes: [0, 1, 2, 3, 4, 5],
                            shown: shown(threeColumnsWidths, [0: 0.3, 3: 0.3, 2: 0.3, 4: 0.3, 1: 56])),
                       "80x24,0,0{3x24,0,0[3x12,0,0{1x12,0,0,0,1x12,2,0,3},3x11,0,13{1x11,0,13,2,1x11,2,13,4}],55x24,4,0,1,20x24,60,0,5}")
    }

    // A pane below the minimum takes its cell from a neighbor that can spare one.
    func testInnerPaneKeepsMinimumSize() {
        XCTAssertEqual(move(threeColumns, divider: 0, panes: [0, 1, 2, 3, 4, 5],
                            shown: shown(threeColumnsWidths, [0: 42.5, 3: 0.5, 2: 42.5, 4: 0.5, 1: 14])),
                       "80x24,0,0{44x24,0,0[44x12,0,0{42x12,0,0,0,1x12,43,0,3},44x11,0,13{42x11,0,13,2,1x11,43,13,4}],14x24,45,0,1,20x24,60,0,5}")
    }

    // With a variable window size the window can be bigger than tmux's, so the panes show more
    // cells than tmux has. Their proportions are kept.
    func testScalesSlackAwayInProportion() {
        XCTAssertEqual(move(threeColumns, divider: 1, panes: [0, 1, 2, 3, 4, 5],
                            shown: shown(threeColumnsWidths, [1: 24.2, 5: 19.8])),
                       "80x24,0,0{39x24,0,0[39x12,0,0{19x12,0,0,0,19x12,20,0,3},39x11,0,13{19x11,0,13,2,19x11,20,13,4}],21x24,40,0,1,18x24,62,0,5}")
    }

    // The leaves were shortened by a row on the way in; the layout sent back must restore it.
    func testUndoesPaneBorderStatusCorrection() {
        XCTAssertEqual(move(threeColumns, divider: 0, panes: [0, 1, 2, 3, 4, 5],
                            shown: shown(threeColumnsWidths, [0: 21.4, 3: 21.6, 2: 21.4, 4: 21.6, 1: 14]),
                            paneBorderStatus: .top),
                       "80x24,0,0{44x24,0,0[44x12,0,0{21x12,0,0,0,22x12,22,0,3},44x11,0,13{21x11,0,13,2,22x11,22,13,4}],14x24,45,0,1,20x24,60,0,5}")
    }

    func testUnmeasuredPaneReturnsNil() {
        var widths = threeColumnsWidths
        widths[3] = nil
        XCTAssertNil(move(threeColumns, divider: 0, panes: [0, 1, 2, 3, 4, 5], shown: widths))
    }

    func testUnknownSplitReturnsNil() {
        XCTAssertNil(move(threeColumns, divider: 0, panes: [0, 1], shown: threeColumnsWidths))
        XCTAssertNil(move(threeColumns, divider: 0, panes: [0, 1, 2, 3, 4, 5], verticalDividers: false,
                          shown: threeColumnsWidths))
    }

    func testDividerOutOfRangeReturnsNil() {
        XCTAssertNil(move(threeColumns, divider: 2, panes: [0, 1, 2, 3, 4, 5], shown: threeColumnsWidths))
    }

    func testFloatingPanesReturnNil() {
        let parsed = tree(threeColumns)
        parsed[kLayoutDictFloatingPanesKey] = [["dummy": 1]]
        var extents = [NSNumber: NSNumber]()
        for (pane, extent) in threeColumnsWidths {
            extents[NSNumber(value: pane)] = NSNumber(value: extent)
        }
        XCTAssertNil(TmuxDividerMover.layoutString(parseTree: parsed,
                                                   dividerIndex: 0,
                                                   panes: [0, 1, 2, 3, 4, 5].map { NSNumber(value: $0) },
                                                   verticalDividers: true,
                                                   measuredExtents: extents,
                                                   paneBorderStatus: .off))
    }
}
