//
//  PortholeFoldClearTests.swift
//  iTerm2
//
//  Tests for the interval-tree signalling that keeps porthole views in
//  sync with folds and Clear Buffer. Portholes are NSViews owned by the
//  textview; the mutation thread tells the view layer when to hide,
//  unhide, or permanently reclaim one. These tests exercise that
//  signalling without a live textview by spying on the interval tree
//  observer.
//
//  Regression coverage for:
//   - Fold All / Fold leaving an inline view (e.g. imgcat) visible.
//   - Clear Buffer leaving an inline view visible.
//   - A leak where a fold carrying a porthole is destroyed (Clear Buffer
//     or scrollback overflow) without unfolding, so the hidden porthole
//     is never reclaimed.
//

import XCTest
@testable import iTerm2SharedARC

final class PortholeFoldClearTests: XCTestCase {

    /// Records the interval-tree observer callbacks relevant to portholes.
    final class SpyObserver: NSObject, iTermIntervalTreeObserver {
        var hidden: [String] = []
        var unhidden: [String] = []
        var removed: [iTermIntervalTreeObjectType] = []
        var permanentlyRemovedHidden: [String] = []

        private func identifier(_ object: any IntervalTreeImmutableObject) -> String? {
            return (object as? PortholeMarkReading)?.uniqueIdentifier
        }

        func intervalTreeDidReset() {}
        func intervalTreeDidAddObject(of type: iTermIntervalTreeObjectType, onLine line: Int) {}
        func intervalTreeDidRemoveObject(of type: iTermIntervalTreeObjectType, onLine line: Int) {
            removed.append(type)
        }
        func intervalTreeDidUnhideObject(_ object: any IntervalTreeImmutableObject,
                                         of type: iTermIntervalTreeObjectType,
                                         onLine line: Int) {
            if let id = identifier(object) { unhidden.append(id) }
        }
        func intervalTreeDidHide(_ object: any IntervalTreeImmutableObject,
                                 of type: iTermIntervalTreeObjectType,
                                 onLine line: Int) {
            if let id = identifier(object) { hidden.append(id) }
        }
        func intervalTreeVisibleRangeDidChange() {}
        func intervalTreeDidMove(_ objects: [any IntervalTreeImmutableObject]) {}
        func intervalTreeDidPermanentlyRemoveHiddenObject(_ object: any IntervalTreeImmutableObject,
                                                          of type: iTermIntervalTreeObjectType) {
            if let id = identifier(object) { permanentlyRemovedHidden.append(id) }
        }
    }

    private let width: Int32 = 80

    /// Build a harness with `lines` filler rows and attach a spy observer.
    private func makeHarness(lines: Int = 10) -> (TerminalTestHarness, SpyObserver) {
        let harness = TerminalTestHarness(width: Int(width), height: 24)
        for i in 0..<lines {
            harness.appendText("filler \(i)")
            harness.newline()
        }
        harness.sync()
        let spy = SpyObserver()
        harness.screen.intervalTreeObserver = spy
        harness.sync()
        return (harness, spy)
    }

    /// Insert a bare PortholeMark spanning a single absolute line. This is
    /// the interval-tree footprint a real porthole leaves; the view side
    /// is irrelevant to what we're testing here.
    @discardableResult
    private func addPortholeMark(absLine: Int64,
                                 id: String,
                                 harness: TerminalTestHarness) -> PortholeMark {
        var result: PortholeMark!
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            let mark = PortholeMark(id, width: self.width)
            let range = VT100GridAbsCoordRangeMake(0, absLine, self.width, absLine)
            let interval = mutableState.interval(for: range)
            mutableState.mutableIntervalTree().add(mark, with: interval)
            result = mark
        })
        harness.sync()
        return result
    }

    private func fold(startLine: Int, endLine: Int, harness: TerminalTestHarness) {
        harness.screen.foldAbsLineRange(NSRange(location: startLine, length: endLine - startLine))
        harness.sync()
    }

    private func unfold(startLine: Int, endLine: Int, harness: TerminalTestHarness) {
        harness.screen.removeFolds(in: NSRange(location: startLine, length: endLine - startLine),
                                   completion: nil)
        harness.sync()
    }

    // MARK: - Fold hides

    /// Folding a region that contains a porthole must tell the view layer to
    /// hide it. Before the fix the bulkRemoveObjects path fired no
    /// notification at all, so the view was left behind.
    func test_fold_hidesContainedPorthole() {
        let (harness, spy) = makeHarness(lines: 10)
        addPortholeMark(absLine: 5, id: "p1", harness: harness)

        fold(startLine: 3, endLine: 8, harness: harness)

        XCTAssertEqual(spy.hidden, ["p1"],
                       "folding a region containing a porthole must hide it")
        XCTAssertTrue(spy.permanentlyRemovedHidden.isEmpty,
                      "a normal fold must not permanently remove the porthole")
    }

    /// A porthole outside the folded region must not be touched.
    func test_fold_ignoresPortholeOutsideRange() {
        let (harness, spy) = makeHarness(lines: 10)
        addPortholeMark(absLine: 9, id: "outside", harness: harness)

        fold(startLine: 3, endLine: 7, harness: harness)

        XCTAssertTrue(spy.hidden.isEmpty,
                      "a porthole outside the fold range must not be hidden")
    }

    // MARK: - Unfold restores

    /// Unfolding restores the porthole: the view layer is told to unhide it,
    /// and it is not treated as a permanent removal.
    func test_unfold_unhidesPorthole() {
        let (harness, spy) = makeHarness(lines: 10)
        addPortholeMark(absLine: 5, id: "p1", harness: harness)

        fold(startLine: 3, endLine: 8, harness: harness)
        XCTAssertEqual(spy.hidden, ["p1"], "setup: fold should have hidden the porthole")

        unfold(startLine: 3, endLine: 8, harness: harness)

        XCTAssertEqual(spy.unhidden, ["p1"],
                       "unfolding must unhide the porthole it was carrying")
        XCTAssertTrue(spy.permanentlyRemovedHidden.isEmpty,
                      "unfold is not a permanent removal")
    }

    // MARK: - Clear Buffer reclaims a folded porthole (the leak fix)

    /// Folding a porthole then clearing the buffer destroys the fold without
    /// unfolding. The hidden porthole it carried must be reclaimed, otherwise
    /// it (its view and saved lines) leaks forever.
    func test_clearBuffer_reclaimsFoldedPorthole() {
        let (harness, spy) = makeHarness(lines: 10)
        addPortholeMark(absLine: 5, id: "p1", harness: harness)
        fold(startLine: 3, endLine: 8, harness: harness)
        XCTAssertEqual(spy.hidden, ["p1"], "setup: fold should have hidden the porthole")

        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.clearBufferSavingPrompt(false)
        })
        harness.sync()

        XCTAssertEqual(spy.permanentlyRemovedHidden, ["p1"],
                       "clearing a buffer that holds a folded porthole must reclaim it")
        XCTAssertTrue(spy.unhidden.isEmpty,
                      "the porthole must not be unhidden by a clear")
    }

    // MARK: - Regressions: non-folded removal still uses the normal path

    /// A porthole that is NOT inside a fold, when cleared, must go through the
    /// ordinary porthole-removal notification (which drives prunePortholes),
    /// not the permanent-hidden reclaim path.
    func test_clearBuffer_nonFoldedPorthole_usesNormalRemoval() {
        let (harness, spy) = makeHarness(lines: 10)
        addPortholeMark(absLine: 5, id: "visible", harness: harness)

        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.clearBufferSavingPrompt(false)
        })
        harness.sync()

        XCTAssertTrue(spy.removed.contains(.porthole),
                      "a visible porthole must be removed via the ordinary path on clear")
        XCTAssertTrue(spy.permanentlyRemovedHidden.isEmpty,
                      "a visible (non-folded) porthole must not use the hidden-reclaim path")
    }
}
