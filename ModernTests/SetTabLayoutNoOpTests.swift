//
//  SetTabLayoutNoOpTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

/// F-073: Tab.async_update_layout() with no changes shrank the panes by a cell
/// per call. An unchanged layout is now recognized and left alone.
final class SetTabLayoutNoOpTests: XCTestCase {
    private func leaf(_ width: Int32, _ height: Int32) -> ITMSplitTreeNode_SplitTreeLink {
        let link = ITMSplitTreeNode_SplitTreeLink()
        link.session.uniqueIdentifier = UUID().uuidString
        link.session.gridSize.width = width
        link.session.gridSize.height = height
        return link
    }

    private func tree(_ a: (Int32, Int32), _ b: (Int32, Int32), _ c: (Int32, Int32)) -> ITMSplitTreeNode {
        let inner = ITMSplitTreeNode()
        inner.vertical = false
        inner.linksArray.add(leaf(b.0, b.1))
        inner.linksArray.add(leaf(c.0, c.1))
        let innerLink = ITMSplitTreeNode_SplitTreeLink()
        innerLink.node = inner

        let root = ITMSplitTreeNode()
        root.vertical = true
        root.linksArray.add(leaf(a.0, a.1))
        root.linksArray.add(innerLink)
        return root
    }

    func testSameGridSizesAreRecognized() {
        XCTAssertTrue(iTermAPIHelper.splitTree(tree((80, 25), (40, 12), (40, 12)),
                                               hasSameGridSizesAs: tree((80, 25), (40, 12), (40, 12))))
    }

    func testDifferentGridSizeAnywhereIsAChange() {
        XCTAssertFalse(iTermAPIHelper.splitTree(tree((80, 25), (40, 12), (40, 12)),
                                                hasSameGridSizesAs: tree((79, 25), (40, 12), (40, 12))))
        XCTAssertFalse(iTermAPIHelper.splitTree(tree((80, 25), (40, 12), (40, 12)),
                                                hasSameGridSizesAs: tree((80, 25), (40, 12), (40, 13))))
    }
}
