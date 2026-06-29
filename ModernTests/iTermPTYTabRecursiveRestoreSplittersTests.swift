//
//  iTermPTYTabRecursiveRestoreSplittersTests.swift
//  ModernTests
//
//  Characterization tests for the recursive tree-build that turns an
//  arrangement dictionary into a live NSSplitView/SessionView
//  hierarchy. The implementation lives in
//  iTermSplitTreeRebuilder.buildSplitterTree (Swift, since the port);
//  PTYTab._recursiveRestoreSplitters is a thin ObjC shim that delegates
//  to the same code path.
//
//  These tests act as a regression safety net for the leaf-resolver
//  generalization and any future refactoring of the rebuild logic.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermPTYTabRecursiveRestoreSplittersTests: XCTestCase {

    // MARK: - Arrangement key constants
    //
    // These mirror the file-static keys in PTYTab.m. The on-disk arrangement
    // format is stable, so duplicating them as literals here is acceptable.

    private let kViewType         = "View Type"
    private let kSplitter         = "Splitter"
    private let kSessionView      = "SessionView"
    private let kSubviews         = "Subviews"
    private let kIsVertical       = "isVertical"
    private let kFrame            = "frame"
    private let kSplitterID       = "Splitter ID"
    private let kTmuxWindowPane   = "tmux window pane"
    private let kArrangementID    = "ID"

    private let kFrameX           = "x"
    private let kFrameY           = "y"
    private let kFrameWidth       = "width"
    private let kFrameHeight      = "height"

    // MARK: - Arrangement builders

    private func frameDict(_ rect: NSRect) -> [String: Any] {
        return [
            kFrameX:      rect.origin.x,
            kFrameY:      rect.origin.y,
            kFrameWidth:  rect.size.width,
            kFrameHeight: rect.size.height,
        ]
    }

    private func leaf(frame: NSRect,
                      tmuxPane: Int? = nil,
                      arrangementID: Int? = nil) -> [String: Any] {
        var d: [String: Any] = [
            kViewType: kSessionView,
            kFrame:    frameDict(frame),
        ]
        if let tmuxPane = tmuxPane {
            d[kTmuxWindowPane] = tmuxPane
        }
        if let arrangementID = arrangementID {
            // PTYTab.m stores TAB_ARRANGEMENT_ID as NSNumber (see
            // _recursiveEncodeArrangementForView:idMap:isMaximized: which
            // does encoder[TAB_ARRANGEMENT_ID] = @(arrangementID)).
            d[kArrangementID] = arrangementID
        }
        return d
    }

    private func splitter(vertical: Bool,
                          frame: NSRect,
                          children: [[String: Any]],
                          splitterID: String? = nil) -> [String: Any] {
        var d: [String: Any] = [
            kViewType:    kSplitter,
            kIsVertical:  vertical,
            kFrame:       frameDict(frame),
            kSubviews:    children,
        ]
        if let splitterID = splitterID {
            d[kSplitterID] = splitterID
        }
        return d
    }

    // MARK: - Tests

    /// With nil idMap and sessionMap, every leaf becomes a fresh SessionView
    /// and every splitter node becomes an NSSplitView with the right vertical flag.
    func testNoMapsGeneratesFreshLeavesAndCorrectShape() {
        let arrangement = splitter(
            vertical: true,
            frame: NSRect(x: 0, y: 0, width: 200, height: 100),
            children: [
                leaf(frame: NSRect(x: 0, y: 0, width: 100, height: 100)),
                leaf(frame: NSRect(x: 100, y: 0, width: 100, height: 100)),
            ])

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement,
            idMap: nil,
            sessionMap: nil,
            revivedSessions: nil)

        guard let split = view as? NSSplitView else {
            XCTFail("expected NSSplitView, got \(type(of: view))")
            return
        }
        XCTAssertTrue(split.isVertical)
        XCTAssertEqual(split.subviews.count, 2)
        XCTAssertTrue(split.subviews[0] is SessionView,
                      "expected leaf to be SessionView")
        XCTAssertTrue(split.subviews[1] is SessionView)
    }

    /// Horizontal splitter sets isVertical=false on the produced NSSplitView.
    func testHorizontalSplitterProducesNonVerticalSplit() {
        let arrangement = splitter(
            vertical: false,
            frame: NSRect(x: 0, y: 0, width: 100, height: 200),
            children: [
                leaf(frame: NSRect(x: 0, y: 0, width: 100, height: 100)),
                leaf(frame: NSRect(x: 0, y: 100, width: 100, height: 100)),
            ])

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: nil, sessionMap: nil, revivedSessions: nil)
        let split = view as! NSSplitView
        XCTAssertFalse(split.isVertical)
    }

    /// Nested mixed-orientation splitters produce the right hierarchy:
    /// V[ leaf, H[leaf, leaf] ]
    func testNestedMixedOrientationShape() {
        let inner = splitter(
            vertical: false,
            frame: NSRect(x: 100, y: 0, width: 100, height: 100),
            children: [
                leaf(frame: NSRect(x: 100, y: 0, width: 100, height: 50)),
                leaf(frame: NSRect(x: 100, y: 50, width: 100, height: 50)),
            ])
        let outer = splitter(
            vertical: true,
            frame: NSRect(x: 0, y: 0, width: 200, height: 100),
            children: [
                leaf(frame: NSRect(x: 0, y: 0, width: 100, height: 100)),
                inner,
            ])

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: outer, idMap: nil, sessionMap: nil, revivedSessions: nil)
        let outerSplit = view as! NSSplitView
        XCTAssertTrue(outerSplit.isVertical)
        XCTAssertEqual(outerSplit.subviews.count, 2)
        XCTAssertTrue(outerSplit.subviews[0] is SessionView)

        let innerSplit = outerSplit.subviews[1] as! NSSplitView
        XCTAssertFalse(innerSplit.isVertical)
        XCTAssertEqual(innerSplit.subviews.count, 2)
        XCTAssertTrue(innerSplit.subviews[0] is SessionView)
        XCTAssertTrue(innerSplit.subviews[1] is SessionView)
    }

    /// A leaf whose tmux pane key is in idMap recycles the existing
    /// SessionView (same identity), and resets its frame to the arrangement's.
    func testRecycleViaTmuxPaneKey() {
        let recycled = SessionView(frame: NSRect(x: 999, y: 999, width: 10, height: 10))
        let idMap: [NSNumber: SessionView] = [NSNumber(value: 42): recycled]

        let leafFrame = NSRect(x: 0, y: 0, width: 100, height: 50)
        let arrangement = leaf(frame: leafFrame, tmuxPane: 42)

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: idMap, sessionMap: nil, revivedSessions: nil)

        XCTAssertTrue(view === recycled,
                      "expected the same SessionView instance to be recycled")
        XCTAssertEqual((view as! SessionView).frame, leafFrame,
                       "recycled view's frame should be reset to the arrangement frame")
    }

    /// A leaf whose tmux pane key is NOT in idMap produces a fresh SessionView.
    func testFreshLeafWhenTmuxPaneNotInIdMap() {
        let other = SessionView(frame: NSRect(x: 999, y: 999, width: 10, height: 10))
        let idMap: [NSNumber: SessionView] = [NSNumber(value: 7): other]

        let leafFrame = NSRect(x: 0, y: 0, width: 80, height: 40)
        let arrangement = leaf(frame: leafFrame, tmuxPane: 42)  // not 7

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: idMap, sessionMap: nil, revivedSessions: nil)

        XCTAssertFalse(view === other, "should not recycle the unrelated SessionView")
        XCTAssertTrue(view is SessionView)
        XCTAssertEqual((view as! SessionView).frame, leafFrame)
    }

    /// When an arrangementID match exists in idMap (the maximize-restoration
    /// path), that SessionView is returned. The arrangement-ID lookup short-
    /// circuits before the tmux-pane lookup, so the leaf's frame is preserved
    /// via restoreFrameSize rather than being overwritten from the
    /// arrangement frame.
    func testRecycleViaArrangementID() {
        let recycled = SessionView(frame: NSRect(x: 5, y: 5, width: 50, height: 25))
        // TAB_ARRANGEMENT_ID values are NSNumber (assigned via idMap.count
        // when encoding for maximize). The dict is keyed by NSNumber.
        let idMap: [NSNumber: SessionView] = [NSNumber(value: 99): recycled]

        let arrangement = leaf(
            frame: NSRect(x: 0, y: 0, width: 100, height: 100),
            arrangementID: 99)

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement,
            idMap: idMap,
            sessionMap: nil,
            revivedSessions: nil)

        XCTAssertTrue(view === recycled, "expected recycle via arrangement ID")
    }

    /// Splitter unique ID is propagated to the constructed PTYSplitView.
    func testSplitterUniqueIDPropagation() {
        let arrangement = splitter(
            vertical: true,
            frame: NSRect(x: 0, y: 0, width: 200, height: 100),
            children: [
                leaf(frame: NSRect(x: 0, y: 0, width: 100, height: 100)),
                leaf(frame: NSRect(x: 100, y: 0, width: 100, height: 100)),
            ],
            splitterID: "split-abc")

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: nil, sessionMap: nil, revivedSessions: nil)
        let split = view as! PTYSplitView
        XCTAssertEqual(split.stringUniqueIdentifier(), "split-abc")
    }

    /// Splitter frame is applied to the produced NSSplitView.
    func testSplitterFrameApplied() {
        let frame = NSRect(x: 10, y: 20, width: 300, height: 150)
        let arrangement = splitter(
            vertical: true,
            frame: frame,
            children: [
                leaf(frame: NSRect(x: 10, y: 20, width: 150, height: 150)),
                leaf(frame: NSRect(x: 160, y: 20, width: 150, height: 150)),
            ])

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: nil, sessionMap: nil, revivedSessions: nil)
        XCTAssertEqual(view.frame, frame)
    }

    /// Leaf-only arrangement (no enclosing splitter) returns a SessionView,
    /// not a splitter.
    func testBareLeafArrangementReturnsSessionView() {
        let frame = NSRect(x: 0, y: 0, width: 80, height: 40)
        let arrangement = leaf(frame: frame)

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: nil, sessionMap: nil, revivedSessions: nil)
        XCTAssertTrue(view is SessionView)
        XCTAssertFalse(view is NSSplitView)
        XCTAssertEqual(view.frame, frame)
    }

    /// idMap recycling applies recursively inside nested splitters.
    func testRecycleAcrossNestedSplitters() {
        let recycledA = SessionView(frame: .zero)
        let recycledB = SessionView(frame: .zero)
        let idMap: [NSNumber: SessionView] = [
            NSNumber(value: 1): recycledA,
            NSNumber(value: 2): recycledB,
        ]
        let arrangement = splitter(
            vertical: true,
            frame: NSRect(x: 0, y: 0, width: 200, height: 100),
            children: [
                leaf(frame: NSRect(x: 0, y: 0, width: 100, height: 100), tmuxPane: 1),
                splitter(
                    vertical: false,
                    frame: NSRect(x: 100, y: 0, width: 100, height: 100),
                    children: [
                        leaf(frame: NSRect(x: 100, y: 0, width: 100, height: 50), tmuxPane: 2),
                        leaf(frame: NSRect(x: 100, y: 50, width: 100, height: 50), tmuxPane: 3),
                    ]),
            ])

        let outer = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: idMap, sessionMap: nil, revivedSessions: nil) as! NSSplitView

        XCTAssertTrue(outer.subviews[0] === recycledA)
        let inner = outer.subviews[1] as! NSSplitView
        XCTAssertTrue(inner.subviews[0] === recycledB)
        // Pane 3 is not in idMap so a fresh SessionView is created.
        XCTAssertFalse(inner.subviews[1] === recycledA)
        XCTAssertFalse(inner.subviews[1] === recycledB)
        XCTAssertTrue(inner.subviews[1] is SessionView)
    }
}
