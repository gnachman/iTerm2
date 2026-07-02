//
//  CompanionSelectionRangeTests.swift
//  iTerm2 ModernTests
//
//  iTermSelection uses a half-open (exclusive) end x, but the Companion wire and
//  the phone treat the selection end as the inclusive last cell. The bridge
//  converts on the way out; these cover the conversion, including the wrap when
//  the exclusive end sits at column 0 (previous line selected through its end).
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionSelectionRangeTests: XCTestCase {
    func testMidLineEndSubtractsOne() {
        let end = CompanionHostBridge.inclusiveSelectionEnd(exclusiveColumn: 10, absLine: 42, gridWidth: 80)
        XCTAssertEqual(end.column, 9)
        XCTAssertEqual(end.absLine, 42)
    }

    func testSelectAllEndMapsToLastColumn() {
        // Select all yields an exclusive end at the grid width; the inclusive last
        // cell is gridWidth - 1 on the same line.
        let end = CompanionHostBridge.inclusiveSelectionEnd(exclusiveColumn: 80, absLine: 42, gridWidth: 80)
        XCTAssertEqual(end.column, 79)
        XCTAssertEqual(end.absLine, 42)
    }

    func testEndAtColumnZeroWrapsToPreviousLineEnd() {
        let end = CompanionHostBridge.inclusiveSelectionEnd(exclusiveColumn: 0, absLine: 42, gridWidth: 80)
        XCTAssertEqual(end.column, 79)
        XCTAssertEqual(end.absLine, 41)
    }

    func testEndAtColumnZeroWithUnknownWidthDoesNotGoNegative() {
        let end = CompanionHostBridge.inclusiveSelectionEnd(exclusiveColumn: 0, absLine: 42, gridWidth: 0)
        XCTAssertEqual(end.column, 0)
        XCTAssertEqual(end.absLine, 41)
    }

    // MARK: inclusiveCharacterRange (document-order exclusivity)

    private func range(anchor: (Int32, Int64), live: (Int32, Int64), gridWidth: Int = 80)
    -> (start: VT100GridAbsCoord, end: VT100GridAbsCoord) {
        CompanionHostBridge.inclusiveCharacterRange(
            anchor: VT100GridAbsCoordMake(anchor.0, anchor.1),
            live: VT100GridAbsCoordMake(live.0, live.1),
            gridWidth: gridWidth)
    }

    private func assertRange(_ r: (start: VT100GridAbsCoord, end: VT100GridAbsCoord),
                             start: (Int32, Int64), end: (Int32, Int64),
                             _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.start.x, start.0, message, file: file, line: line)
        XCTAssertEqual(r.start.y, start.1, message, file: file, line: line)
        XCTAssertEqual(r.end.x, end.0, message, file: file, line: line)
        XCTAssertEqual(r.end.y, end.1, message, file: file, line: line)
    }

    func testForwardSameLine() {
        // Anchor at col 3, drag right to col 7: cells 3..7 -> [3, 8).
        assertRange(range(anchor: (3, 5), live: (7, 5)), start: (3, 5), end: (8, 5))
    }

    func testBackwardSameLineIncludesBothEndpoints() {
        // Anchor at col 7, drag LEFT to col 3: still cells 3..7 -> [3, 8), so the
        // cell under the finger (3) and the anchor (7) are both included.
        assertRange(range(anchor: (7, 5), live: (3, 5)), start: (3, 5), end: (8, 5))
    }

    func testSameCellIsSingleNonEmptyCell() {
        // The zero-length regression: a one-cell selection must not collapse.
        assertRange(range(anchor: (4, 5), live: (4, 5)), start: (4, 5), end: (5, 5))
    }

    func testBackwardByOneCellDoesNotVanish() {
        // Dragging exactly one cell back (live == anchor - 1) covers cells 4..5.
        assertRange(range(anchor: (5, 5), live: (4, 5)), start: (4, 5), end: (6, 5))
    }

    func testMultiLineForward() {
        assertRange(range(anchor: (2, 5), live: (1, 7)), start: (2, 5), end: (2, 7))
    }

    func testMultiLineBackwardOrdersByDocument() {
        // Anchor below the live point: document order puts the live line first.
        assertRange(range(anchor: (1, 7), live: (2, 5)), start: (2, 5), end: (2, 7))
    }

    func testColumnsClampToGridWidth() {
        // A column past the grid clamps to the last cell; the exclusive end is width.
        assertRange(range(anchor: (3, 5), live: (200, 5), gridWidth: 80),
                    start: (3, 5), end: (80, 5))
    }

    func testHostileMaxColumnDoesNotOverflow() {
        // Int32.max would wrap to Int32.min on the +1 without the clamp; it must
        // instead resolve to a sane in-grid range.
        assertRange(range(anchor: (Int32.max, 5), live: (Int32.max, 5), gridWidth: 80),
                    start: (79, 5), end: (80, 5))
    }

    func testUnknownWidthStillAvoidsOverflow() {
        // With no known width, the column is capped short of Int32.max so +1 is safe.
        let r = range(anchor: (Int32.max, 5), live: (Int32.max, 5), gridWidth: 0)
        XCTAssertEqual(r.end.x, Int32.max, "the exclusive end must not overflow to a negative column")
        XCTAssertEqual(r.start.x, Int32.max - 1)
    }

    // MARK: clampAbsLine

    func testClampAbsLineInRangeIsUnchanged() {
        XCTAssertEqual(CompanionHostBridge.clampAbsLine(50, firstAbs: 10, lineCount: 100), 50)
    }

    func testClampAbsLineBelowFirstAbs() {
        XCTAssertEqual(CompanionHostBridge.clampAbsLine(-5, firstAbs: 10, lineCount: 100), 10)
    }

    func testClampAbsLineAboveLastLine() {
        // Valid lines are [10, 10+100) -> last is 109.
        XCTAssertEqual(CompanionHostBridge.clampAbsLine(Int64.max, firstAbs: 10, lineCount: 100), 109)
    }

    func testClampAbsLineEmptyBufferPinsToFirstAbs() {
        XCTAssertEqual(CompanionHostBridge.clampAbsLine(50, firstAbs: 10, lineCount: 0), 10)
    }

    // MARK: selectionPushDecision

    private func selRange(_ startCol: Int, _ endCol: Int) -> CompanionSelectionRange {
        CompanionSelectionRange(start: CompanionSelectionPoint(absLine: 5, column: startCol),
                                end: CompanionSelectionPoint(absLine: 5, column: endCol))
    }

    func testPushDecisionNoChangeNoBumpDoesNothing() {
        let r = selRange(1, 4)
        let d = CompanionHostBridge.selectionPushDecision(current: r, lastSent: r, generationBumped: false)
        XCTAssertFalse(d.resetDragState)
        XCTAssertFalse(d.push)
    }

    func testPushDecisionValueChangeResetsAndPushes() {
        let d = CompanionHostBridge.selectionPushDecision(current: selRange(1, 4), lastSent: selRange(1, 6),
                                                          generationBumped: false)
        XCTAssertTrue(d.resetDragState)
        XCTAssertTrue(d.push)
    }

    func testPushDecisionBumpOnlyPushesWithoutResetting() {
        // The regression: a generation bump re-pushes the SAME value but must not
        // reset an in-progress drag (which would collapse a resize-while-dragging).
        let r = selRange(1, 4)
        let d = CompanionHostBridge.selectionPushDecision(current: r, lastSent: r, generationBumped: true)
        XCTAssertFalse(d.resetDragState, "a bump-forced re-push of the same value must not reset the drag")
        XCTAssertTrue(d.push)
    }

    func testPushDecisionValueChangeAndBumpResets() {
        let d = CompanionHostBridge.selectionPushDecision(current: selRange(1, 4), lastSent: selRange(2, 4),
                                                          generationBumped: true)
        XCTAssertTrue(d.resetDragState)
        XCTAssertTrue(d.push)
    }

    func testPushDecisionNilBothWithBumpPushesWithoutReset() {
        let d = CompanionHostBridge.selectionPushDecision(current: nil, lastSent: nil, generationBumped: true)
        XCTAssertFalse(d.resetDragState)
        XCTAssertTrue(d.push)
    }
}
