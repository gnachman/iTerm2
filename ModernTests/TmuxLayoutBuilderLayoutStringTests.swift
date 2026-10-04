//
//  TmuxLayoutBuilderLayoutStringTests.swift
//  iTerm2
//
//  Ported from the legacy iTermTmuxLayoutBuilderTest.m. Checks the full layout
//  string (checksum included) that iTermTmuxLayoutBuilder produces for a few
//  pane trees. The pane-border-status adjustments are covered separately by
//  ModernTests/iTermTmuxLayoutBuilderTest.m.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxLayoutBuilderLayoutStringTests: XCTestCase {
    private func leaf(_ width: Int32, _ height: Int32, pane: Int32) -> iTermTmuxLayoutBuilderLeafNode {
        return iTermTmuxLayoutBuilderLeafNode(sessionOf: VT100GridSize(width: width, height: height),
                                              windowPane: pane)
    }

    private func layoutString(root: iTermTmuxLayoutBuilderNode) -> String {
        return iTermTmuxLayoutBuilder(rootNode: root).layoutString
    }

    func testSinglePane() {
        XCTAssertEqual(layoutString(root: leaf(80, 25, pane: 0)), "b65d,80x25,0,0,0")
    }

    func testOneHorizontalDivider() {
        let root = iTermTmuxLayoutBuilderInteriorNode(verticalDividers: false)
        root.add(leaf(80, 12, pane: 0))
        root.add(leaf(80, 12, pane: 1))

        XCTAssertEqual(layoutString(root: root), "c299,80x25,0,0[80x12,0,0,0,80x12,0,13,1]")
    }

    // horizontal(vertical(0, 3), 1)
    func testThreePanes() {
        let root = iTermTmuxLayoutBuilderInteriorNode(verticalDividers: false)
        let top = iTermTmuxLayoutBuilderInteriorNode(verticalDividers: true)
        top.add(leaf(40, 12, pane: 0))
        top.add(leaf(39, 12, pane: 3))
        root.add(top)
        root.add(leaf(80, 12, pane: 1))

        XCTAssertEqual(layoutString(root: root),
                       "7023,80x25,0,0[80x12,0,0{40x12,0,0,0,39x12,41,0,3},80x12,0,13,1]")
    }

    // You can get this if you destroy a vertical split inside a horizontal split by removing all
    // but one of its sessions. Begin with:
    //   horizontal(vertical(0, horizontal(3, 4)), 1)
    // Then close wp 0, leaving:
    //   horizontal(horizontal(3, 4), 1)
    func testNonNormalizedNestedHorizontalSplits() {
        let root = iTermTmuxLayoutBuilderInteriorNode(verticalDividers: false)
        let inner = iTermTmuxLayoutBuilderInteriorNode(verticalDividers: false)
        inner.add(leaf(80, 6, pane: 3))
        inner.add(leaf(80, 5, pane: 4))
        root.add(inner)
        root.add(leaf(80, 12, pane: 1))

        XCTAssertEqual(layoutString(root: root),
                       "c397,80x25,0,0[80x12,0,0[80x6,0,0,3,80x5,0,7,4],80x12,0,13,1]")
    }

    func testStackOfThree() {
        let root = iTermTmuxLayoutBuilderInteriorNode(verticalDividers: false)
        root.add(leaf(80, 6, pane: 3))
        root.add(leaf(80, 5, pane: 4))
        root.add(leaf(80, 12, pane: 1))

        XCTAssertEqual(layoutString(root: root),
                       "4787,80x25,0,0[80x6,0,0,3,80x5,0,7,4,80x12,0,13,1]")
    }
}
