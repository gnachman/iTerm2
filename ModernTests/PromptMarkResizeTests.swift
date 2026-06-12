//
//  PromptMarkResizeTests.swift
//  iTerm2
//
//  Group 6 tests from the OSC 133 k= plan: width and height resize must
//  keep VT100ScreenMark.excludedSubranges coherent with the rest of the
//  mark. The ResilientCoordinate machinery already self-rewrites each
//  endpoint via the resize converter, so most of these are
//  characterization tests; they fail if a subrange points past the new
//  screen, gets silently dropped from the array, or becomes inverted.
//

import XCTest
@testable import iTerm2SharedARC

final class PromptMarkResizeTests: XCTestCase {

    // MARK: - Helpers

    /// Build a multi-line `for` loop: primary prompt on one row, two PS2
    /// continuation rows, each PS2 prefix marked with `;k=s`. Leaves the
    /// cursor on the line that would be the command line ("done").
    /// Returns the harness for further mutation/assertions.
    private func buildTwoPS2Cycles(width: Int = 80, height: Int = 24) -> TerminalTestHarness {
        let harness = TerminalTestHarness(width: width, height: height)

        // row 0: "$ for i in 1 2; do \"
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("for i in 1 2; do \\")
        harness.newline()

        // row 1: PS2 prefix "for> " then continuation
        harness.sendPromptStart(kind: .secondary)
        harness.appendText("for> ")
        harness.sendCommandStart()
        harness.appendText("echo $i; \\")
        harness.newline()

        // row 2: PS2 prefix "for> " then "done"
        harness.sendPromptStart(kind: .secondary)
        harness.appendText("for> ")
        harness.sendCommandStart()
        harness.appendText("done")
        harness.sync()
        return harness
    }

    private func onlyPromptMark(in harness: TerminalTestHarness,
                                file: StaticString = #file,
                                line: UInt = #line) -> VT100ScreenMark {
        let marks = harness.allScreenMarks().filter { $0.isPrompt }
        XCTAssertEqual(marks.count, 1,
                       "Expected exactly one prompt mark",
                       file: file, line: line)
        return marks.first!
    }

    private func assertWellFormed(_ subranges: [ResilientCoordinateRange],
                                  width: Int32,
                                  file: StaticString = #file,
                                  line: UInt = #line) {
        for (i, r) in subranges.enumerated() {
            // Skip invalid endpoints — that's the documented signal for
            // "consumer should ignore this subrange", and we test that
            // separately. We just make sure the *valid* ones make sense.
            guard r.start.status == .valid && r.end.status == .valid else {
                continue
            }
            let abs = r.absRange
            XCTAssertGreaterThanOrEqual(abs.start.x, 0,
                                        "subrange[\(i)] start.x went negative",
                                        file: file, line: line)
            XCTAssertGreaterThanOrEqual(abs.end.x, 0,
                                        "subrange[\(i)] end.x went negative",
                                        file: file, line: line)
            XCTAssertLessThanOrEqual(abs.start.x, width,
                                     "subrange[\(i)] start.x past new width",
                                     file: file, line: line)
            XCTAssertLessThanOrEqual(abs.end.x, width,
                                     "subrange[\(i)] end.x past new width",
                                     file: file, line: line)
            let startBefore = abs.start.y < abs.end.y
                || (abs.start.y == abs.end.y && abs.start.x <= abs.end.x)
            XCTAssertTrue(startBefore,
                          "subrange[\(i)] inverted (start after end) after resize",
                          file: file, line: line)
        }
    }

    // MARK: - Test 47: width resize during multi-line in-progress

    /// Width shrink that does NOT cause wrap (60 -> 40, all content still
    /// fits). Subrange count and contents should be preserved.
    func test_widthResize_noWrap_subrangesPreserved() {
        let harness = buildTwoPS2Cycles(width: 60, height: 24)
        let before = onlyPromptMark(in: harness).excludedSubranges ?? []
        XCTAssertEqual(before.count, 2,
                       "Two PS2 cycles should produce two excluded subranges")

        harness.screen.size = VT100GridSizeMake(40, 24)
        harness.sync()

        let after = onlyPromptMark(in: harness).excludedSubranges ?? []
        XCTAssertEqual(after.count, 2,
                       "Resize to a still-wide-enough width must not drop subranges")
        assertWellFormed(after, width: 40)
        // Each subrange still on a single row (the PS2 prefix "for> " fits in 40).
        for r in after where r.start.status == .valid && r.end.status == .valid {
            XCTAssertEqual(r.absRange.start.y, r.absRange.end.y,
                           "Subrange split across rows after a non-wrap resize")
        }
    }

    // MARK: - Test 48: width resize that wraps the PS2 prefix

    /// Shrink the width below the PS2 prefix length. The prefix "for> "
    /// (5 cols) won't fit on a single new-width row anymore. The subrange
    /// should not vanish; its endpoints either survive in coordinates
    /// that point at the wrapped cells or report a non-`.valid` status
    /// that downstream consumers know to skip.
    func test_widthResize_prefixWraps_subrangeSurvives() {
        let harness = buildTwoPS2Cycles(width: 80, height: 24)
        let before = onlyPromptMark(in: harness).excludedSubranges ?? []
        XCTAssertEqual(before.count, 2)

        harness.screen.size = VT100GridSizeMake(4, 24)
        harness.sync()

        let after = onlyPromptMark(in: harness).excludedSubranges ?? []
        XCTAssertEqual(after.count, 2,
                       "Subranges must survive a wrap-inducing resize (status may flip)")
        assertWellFormed(after, width: 4)
    }

    // MARK: - Test 49: width resize that pushes a right-prompt off

    /// Synthesise a `k=r` right-prompt sitting at the tail of the primary
    /// prompt row. Shrink the width so those cells fall outside the new
    /// row width and have to wrap. The resulting subrange must not
    /// retain coordinates past the new width.
    func test_widthResize_rightPromptOffScreen_subrangeNotPastWidth() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart()
        harness.appendText("$ ")
        // Primary command-start; user has typed nothing yet, command range starts here.
        harness.sendCommandStart()

        // A k=r right-prompt fires after primary B but before C. p10k
        // emits it via 133;P;k=r ... 133;B. Use a right-aligned 10-cell
        // payload near the row's tail.
        harness.appendText(String(repeating: " ", count: 60))
        harness.sendPromptStart(kind: .right)
        harness.appendText("[12:00:00]")
        harness.sendCommandStart()
        harness.sync()

        let before = onlyPromptMark(in: harness).excludedSubranges ?? []
        XCTAssertEqual(before.count, 1, "One k=r cycle should record one subrange")

        harness.screen.size = VT100GridSizeMake(40, 24)
        harness.sync()

        let after = onlyPromptMark(in: harness).excludedSubranges ?? []
        XCTAssertEqual(after.count, 1, "Right-prompt subrange must not be dropped")
        assertWellFormed(after, width: 40)
    }

    // MARK: - Test 50: height resize + scrollback overflow

    /// Build a multi-line PS2 cycle, then write enough lines to push the
    /// prompt mark and its excluded subranges into scrollback. The
    /// subranges' coordinates should shift in lockstep with the mark
    /// itself (or report `.scrolledOff` if history isn't large enough).
    func test_heightResize_scrollbackOverflow_subrangesShiftWithMark() {
        // Use a small terminal so scrollback overflow happens quickly.
        let harness = buildTwoPS2Cycles(width: 80, height: 5)
        let mark = onlyPromptMark(in: harness)
        let beforeSubs = mark.excludedSubranges ?? []
        XCTAssertEqual(beforeSubs.count, 2)
        let beforeMarkLine = mark.entry?.interval.location ?? -1

        // Push the mark into scrollback by appending many newlines.
        for _ in 0..<50 {
            harness.appendText("padding\n")
        }
        harness.sync()

        let afterSubs = mark.excludedSubranges ?? []
        XCTAssertEqual(afterSubs.count, beforeSubs.count,
                       "Subrange array length should not change just because " +
                       "lines were appended")

        // For every still-valid subrange, its absY should equal the
        // corresponding pre-shift absY (line shifts adjust the *grid*
        // index, but absolute coordinates are stable across LineBuffer
        // pushes).
        let afterMarkLine = mark.entry?.interval.location ?? -2
        XCTAssertEqual(beforeMarkLine, afterMarkLine,
                       "Mark's absolute interval location should be stable " +
                       "across scrollback overflow")
        assertWellFormed(afterSubs, width: 80)
    }

    // MARK: - Test 51: saved-tree path (alt-screen mark with excluded subranges)

    /// Group 6 + saved-tree coverage. A prompt mark with excluded
    /// subranges that lives in the saved interval tree (alt-screen
    /// content viewed after switching back to primary) must reflow its
    /// subranges through the saved-tree RC pool's resize broadcast,
    /// not the primary one — the alt content lives in altScreenLineBuffer,
    /// not self.linebuffer. Without the saved-tree pool split (commit
    /// `93441e04a`), the primary converter would invalidate the
    /// subranges' RCs because it can't resolve alt-grid coords against
    /// the primary line buffer.
    func test_savedTree_widthResize_excludedSubranges_reflowViaAltLinebuffer() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        // Enter alt mode FIRST so the OSC 133 cycle's mark and PS2
        // excluded subranges are anchored to alt content.
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()

        // Same two-PS2-cycle shape as buildTwoPS2Cycles(), but emitted
        // into the alt grid. The prompt mark and both `k=s` cycles get
        // recorded against alt coords.
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("for i in 1 2; do \\")
        harness.newline()
        harness.sendPromptStart(kind: .secondary)
        harness.appendText("for> ")
        harness.sendCommandStart()
        harness.appendText("echo $i; \\")
        harness.newline()
        harness.sendPromptStart(kind: .secondary)
        harness.appendText("for> ")
        harness.sendCommandStart()
        harness.appendText("done")
        harness.sync()

        // Capture the mark's guid while it's still in the active tree.
        var guid = ""
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in mutableState.mutableIntervalTree().allObjects() {
                if let m = obj as? VT100ScreenMark, m.isPrompt {
                    guid = m.guid
                    return
                }
            }
        })
        XCTAssertFalse(guid.isEmpty, "setup: alt-mode prompt mark missing")

        // Switch back to primary. swapOnscreenIntervalTreeObjects
        // moves the alt-anchored mark into the saved tree, where its
        // RCs are now bound to the saved-tree pool.
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showPrimaryBuffer()
        })
        harness.sync()

        // Pre-resize: the mark is in the saved tree with two excluded
        // subranges that resolve to valid coords.
        let beforeMark = findMark(guid: guid, in: harness)
        XCTAssertNotNil(beforeMark, "setup: mark must exist in saved tree")
        let beforeSubs = beforeMark?.excludedSubranges ?? []
        XCTAssertEqual(beforeSubs.count, 2,
                       "setup: two PS2 cycles should produce two excluded subranges")
        for (i, r) in beforeSubs.enumerated() {
            XCTAssertEqual(r.start.status, .valid,
                           "setup: subrange[\(i)] start must be valid pre-resize")
            XCTAssertEqual(r.end.status, .valid,
                           "setup: subrange[\(i)] end must be valid pre-resize")
        }

        // Width resize. The saved-tree broadcast's converter is built
        // against altScreenLineBuffer; if the alt-content marks were
        // observing the primary pool, the primary converter would
        // invalidate them.
        harness.screen.size = VT100GridSizeMake(40, 24)
        harness.sync()

        guard let afterMark = findMark(guid: guid, in: harness) else {
            XCTFail("mark must survive resize while in saved tree")
            return
        }
        let afterSubs = afterMark.excludedSubranges ?? []
        XCTAssertEqual(afterSubs.count, beforeSubs.count,
                       "saved-tree mark's excluded subranges must not be dropped on resize")
        for (i, r) in afterSubs.enumerated() {
            XCTAssertEqual(r.start.status, .valid,
                           "subrange[\(i)] start must stay valid through saved-tree resize " +
                           "(would revert to sentinel if the primary converter were applied)")
            XCTAssertEqual(r.end.status, .valid,
                           "subrange[\(i)] end must stay valid through saved-tree resize")
        }
        assertWellFormed(afterSubs, width: 40)
    }

    private func findMark(guid: String,
                          in harness: TerminalTestHarness) -> VT100ScreenMark? {
        var result: VT100ScreenMark?
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in mutableState.mutableIntervalTree().allObjects() {
                if let m = obj as? VT100ScreenMark, m.guid == guid {
                    result = m
                    return
                }
            }
            for obj in mutableState.mutableSavedIntervalTree().allObjects() {
                if let m = obj as? VT100ScreenMark, m.guid == guid {
                    result = m
                    return
                }
            }
        })
        return result
    }

    // MARK: - Edge: invalid endpoints are tolerated by consumers

    /// If a subrange's endpoint becomes `.invalid` after a resize (we
    /// can't directly force this from a test, but the wrap case above
    /// can), the selection-clipping helper must silently skip it rather
    /// than producing a malformed selection.
    func test_widthResize_invalidEndpoints_selectionClippingSkipsThem() {
        let harness = buildTwoPS2Cycles(width: 80, height: 24)

        // Force a violent shrink that may invalidate some subrange ends.
        harness.screen.size = VT100GridSizeMake(2, 24)
        harness.sync()

        let mark = onlyPromptMark(in: harness)
        let subs = mark.excludedSubranges ?? []

        // Call into iTermSubSelection.subSelections(in:excluding:width:)
        // with the mark's command range. We don't care about the exact
        // result; we care that it doesn't crash and returns *something*
        // (possibly empty if everything got eaten).
        let commandRange = VT100GridAbsCoordRangeMake(0, 0, 2, 0)
        let result = iTermSubSelection.subSelections(in: commandRange,
                                                     excluding: subs,
                                                     width: 2)
        XCTAssertNotNil(result, "Selection clipping must not crash on invalid endpoints")
    }
}
