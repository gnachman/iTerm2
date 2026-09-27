//
//  CopyModeSelectionDirectionTests.swift
//  ModernTests
//
//  Copy mode: press space to anchor, then move the cursor UP. The committed
//  selection must stay in document order regardless of the direction it was made:
//  the top line selected from the anchor column to the right edge, the bottom line
//  from the left edge to the cursor column. setSelectedLogicalRange (used by
//  copy-mode character selection) is handed the range as (anchor, cursor); for an
//  upward selection that is REVERSE document order, so it must normalize before
//  committing. This is a plain-ASCII regression, no bidi involved.
//

import XCTest
@testable import iTerm2SharedARC

private class PlainSelectionDelegate: NSObject, iTermSelectionDelegate {
    let width: Int32
    var liveSelectionDidEndCount = 0
    var selectionDidChangeCount = 0
    // When set, every line has trailing nulls starting at this column.
    var nullsLocation: Int32?
    init(width: Int32) { self.width = width }
    func selectionDidChange(_ selection: iTermSelection) { selectionDidChangeCount += 1 }
    func liveSelectionDidEnd() { liveSelectionDidEndCount += 1 }
    func selectionAbsRangeForParenthetical(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
    func selectionAbsRangeForWord(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
    func selectionAbsRangeForSmartSelection(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
    func selectionAbsRangeForWrappedLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, absCoord.y, width, absCoord.y), 0, 0) }
    func selectionAbsRangeForLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, absCoord.y, width, absCoord.y), 0, 0) }
    func selectionRangeOfTerminalNulls(onAbsoluteLine absLineNumber: Int64) -> VT100GridRange {
        if let loc = nullsLocation { return VT100GridRangeMake(loc, width - loc) }
        return VT100GridRangeMake(width, 0)
    }
    func selectionPredecessor(of absCoord: VT100GridAbsCoord) -> VT100GridAbsCoord { VT100GridAbsCoordMake(max(0, absCoord.x - 1), absCoord.y) }
    func selectionViewportWidth() -> Int32 { width }
    func selectionTotalScrollbackOverflow() -> Int64 { 0 }
    func selectionIndexes(onAbsoluteLine line: Int64, containingCharacter c: unichar, in range: NSRange) -> IndexSet? { nil }
    func selectionParagraphIsRTL(onAbsoluteLine line: Int64) -> Bool { false }
    func selectionLogicalIndexes(forVisualRange visualRange: NSRange, onAbsoluteLine line: Int64) -> IndexSet {
        IndexSet(integersIn: Range(visualRange) ?? 0..<0)
    }
}

final class CopyModeSelectionDirectionTests: XCTestCase {
    override func tearDown() {
        // Some tests enable bidi; make sure it is off for the rest.
        iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi)
        super.tearDown()
    }

    private func enableBidi() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while !iTermPreferences.bidiEnabled() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

    // FAILING until the fix: an upward selection (anchor on line 3, cursor moved up
    // to line 2, both at column 10) must highlight in document order: line 2 (top)
    // from column 10 to the edge, line 3 (bottom) from the edge to column 10.
    func testUpwardCharacterSelectionHighlightsInDocumentOrder() {
        let delegate = PlainSelectionDelegate(width: 20)
        let sel = iTermSelection()
        sel.delegate = delegate

        // Range given as (anchor=(10,3), cursor=(10,2)): reverse document order.
        let range = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(10, 3, 10, 2), 0, 0)
        sel.setSelectedLogicalRange(range, mode: .kiTermSelectionModeCharacter)

        let line2 = IndexSet(sel.selectedIndexes(onAbsoluteLine: 2))
        let line3 = IndexSet(sel.selectedIndexes(onAbsoluteLine: 3))

        XCTAssertEqual(line2, IndexSet(10..<20),
                       "top line (line 2) must be selected from the anchor column to the right edge")
        XCTAssertEqual(line3, IndexSet(0..<10),
                       "bottom line (line 3) must be selected from the left edge to the cursor column")
    }

    // A downward selection (the natural order) already works and must keep working.
    func testDownwardCharacterSelectionHighlightsInDocumentOrder() {
        let delegate = PlainSelectionDelegate(width: 20)
        let sel = iTermSelection()
        sel.delegate = delegate

        let range = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(10, 2, 10, 3), 0, 0)
        sel.setSelectedLogicalRange(range, mode: .kiTermSelectionModeCharacter)

        XCTAssertEqual(IndexSet(sel.selectedIndexes(onAbsoluteLine: 2)), IndexSet(10..<20))
        XCTAssertEqual(IndexSet(sel.selectedIndexes(onAbsoluteLine: 3)), IndexSet(0..<10))
    }

    // An empty (start == end) range must not create a phantom selection: the live
    // path gates on length > 0 and adds nothing, leaving hasSelection NO. Reachable
    // via copy-mode: space to anchor, move away and back to the anchor.
    func testEmptyRangeDoesNotCreatePhantomSelection() {
        let delegate = PlainSelectionDelegate(width: 20)
        let sel = iTermSelection()
        sel.delegate = delegate

        let empty = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(5, 2, 5, 2), 0, 0)
        sel.setSelectedLogicalRange(empty, mode: .kiTermSelectionModeCharacter)

        XCTAssertFalse(sel.hasSelection, "a zero-length range must not create a selection")
    }

    // Shift-click extension must anchor at the just-committed range, not a stale
    // _initialAbsRange left over from a prior selection. A prior LINE selection on
    // line 10 leaves _initialAbsRange non-empty there; committing a character
    // selection on line 5 via setSelectedLogicalRange must refresh it, so extending
    // forward extends the end rather than collapsing.
    func testExtendAfterSetSelectedLogicalRangeAnchorsAtCommittedRange() {
        let delegate = PlainSelectionDelegate(width: 20)
        let sel = iTermSelection()
        sel.delegate = delegate

        // Poison _initialAbsRange with a prior (non-empty) line selection on line 10.
        sel.begin(at: VT100GridAbsCoordMake(0, 10),
                  mode: iTermSelectionMode.kiTermSelectionModeLine,
                  resume: false, append: false)
        sel.endLive()

        // Commit a character selection on line 5.
        let committed = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(2, 5, 8, 5), 0, 0)
        sel.setSelectedLogicalRange(committed, mode: .kiTermSelectionModeCharacter)

        // Shift-click extend forward to column 14 must keep the start (2) and move
        // the end, not collapse.
        sel.beginExtendingSelection(at: VT100GridAbsCoordMake(14, 5))
        sel.endLive()

        let cells = IndexSet(sel.selectedIndexes(onAbsoluteLine: 5))
        XCTAssertTrue(cells.contains(2) && cells.contains(13),
                      "extend must anchor at the committed range and extend the end; got \(Array(cells))")
    }

    // setSelectedLogicalRange replaced begin/move/endLiveSelection at several call
    // sites; the old endLiveSelection fired liveSelectionDidEnd (autoSearch find
    // pasteboard + AI-chat selection text). It must fire it too, or those side
    // effects are silently lost (and copy mode becomes inconsistent between its
    // character mode and its still-live line/box modes).
    func testSetSelectedLogicalRangeFiresLiveSelectionDidEnd() {
        let delegate = PlainSelectionDelegate(width: 20)
        let sel = iTermSelection()
        sel.delegate = delegate

        sel.setSelectedLogicalRange(VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(2, 3, 8, 3), 0, 0),
                                    mode: .kiTermSelectionModeCharacter)

        XCTAssertEqual(delegate.liveSelectionDidEndCount, 1,
                       "setSelectedLogicalRange must fire liveSelectionDidEnd like endLiveSelection did")
    }

    // Parity with endLiveSelection: committing an empty range with no prior
    // selection must still post selectionDidChange (neither clearSelection nor
    // addSubSelection posts it in that case).
    func testEmptySetSelectedLogicalRangePostsSelectionDidChange() {
        let delegate = PlainSelectionDelegate(width: 20)
        let sel = iTermSelection()
        sel.delegate = delegate

        sel.setSelectedLogicalRange(VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(5, 0, 5, 0), 0, 0),
                                    mode: .kiTermSelectionModeCharacter)

        XCTAssertEqual(delegate.selectionDidChangeCount, 1,
                       "an empty commit with no prior selection must still post selectionDidChange")
        XCTAssertFalse(sel.hasSelection, "an empty range must not create a selection")
    }

    // setSelectedLogicalRange must set _selectionMode, as beginSelectionAtAbsCoord
    // did. Otherwise a stale mode (a prior Box/option-drag selection) survives:
    // the public selectionMode property is left wrong, and the commit's
    // null-extension unflips the range with the stale mode (Box takes independent
    // MIN/MAX of the x-endpoints, corrupting a multi-line character range whose
    // endpoints are not in column order and whose lines have trailing nulls).
    func testSetSelectedLogicalRangeSetsSelectionMode() {
        let delegate = PlainSelectionDelegate(width: 20)
        let sel = iTermSelection()
        sel.delegate = delegate

        // Poison _selectionMode with a prior Box selection.
        sel.selectionMode = .kiTermSelectionModeBox

        sel.setSelectedLogicalRange(VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(2, 1, 8, 1), 0, 0),
                                    mode: .kiTermSelectionModeCharacter)

        XCTAssertEqual(sel.selectionMode, .kiTermSelectionModeCharacter,
                       "setSelectedLogicalRange must set the selection mode, not leave a stale one")
    }

    // The consequence of a stale mode: a multi-line character range with out-of-
    // column-order endpoints, on lines with trailing nulls, is corrupted when the
    // stale mode is Box (its MIN/MAX unflip picks the wrong null boundary). With
    // the mode set correctly the committed cells match a fresh selection's.
    func testStaleBoxModeDoesNotCorruptCommittedCharacterRange() {
        let range = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(10, 1, 3, 3), 0, 0)

        // Reference: a fresh selection (default character mode), lines have nulls at 5.
        let d1 = PlainSelectionDelegate(width: 20); d1.nullsLocation = 5
        let s1 = iTermSelection(); s1.delegate = d1
        s1.setSelectedLogicalRange(range, mode: .kiTermSelectionModeCharacter)
        let ref1 = IndexSet(s1.selectedIndexes(onAbsoluteLine: 1))
        let ref3 = IndexSet(s1.selectedIndexes(onAbsoluteLine: 3))

        // Same commit, but with a stale Box mode poisoning _selectionMode.
        let d2 = PlainSelectionDelegate(width: 20); d2.nullsLocation = 5
        let s2 = iTermSelection(); s2.delegate = d2
        s2.selectionMode = .kiTermSelectionModeBox
        s2.setSelectedLogicalRange(range, mode: .kiTermSelectionModeCharacter)

        XCTAssertEqual(IndexSet(s2.selectedIndexes(onAbsoluteLine: 1)), ref1,
                       "a stale Box mode must not change the committed character range")
        XCTAssertEqual(IndexSet(s2.selectedIndexes(onAbsoluteLine: 3)), ref3)
    }

    // A multi-line character selection inside a restricted column window (e.g.
    // respect-dividers) must stay inside that window on its first/last/middle
    // lines, like the single-line path does. Otherwise it over-selects the full
    // grid width on the boundary lines.
    func testVisualRangeRespectsColumnWindowOnMultiLine() {
        let delegate = PlainSelectionDelegate(width: 80)
        let sel = iTermSelection()
        sel.delegate = delegate

        // Column window [10, 30) (location 10, length 20); range spans lines 1..3.
        let range = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(15, 1, 25, 3), 10, 20)

        // Top (LTR): from start.x=15 to the edge, clamped to the window -> [15, 30).
        XCTAssertEqual(sel.visualRangeOfIndexes(inAbsRange: range, onAbsoluteLine: 1),
                       NSRange(location: 15, length: 15))
        // Middle: full width clamped to the window -> [10, 30).
        XCTAssertEqual(sel.visualRangeOfIndexes(inAbsRange: range, onAbsoluteLine: 2),
                       NSRange(location: 10, length: 20))
        // Bottom (LTR): from 0 to end.x=25, clamped to the window -> [10, 25).
        XCTAssertEqual(sel.visualRangeOfIndexes(inAbsRange: range, onAbsoluteLine: 3),
                       NSRange(location: 10, length: 15))
    }

    // Merely enabling bidi makes every character selection's live range "visual",
    // which used to disable extendPastNulls for ALL character drags, even on
    // all-LTR/ASCII lines where visual == logical and the extension was correct.
    // The gate must key on whether the line is right-justified, not the global pref.
    func testExtendPastNullsStillRunsForCharacterSelectionOnLTRLineWhenBidiEnabled() {
        enableBidi()
        let delegate = PlainSelectionDelegate(width: 20)  // LTR (paragraphIsRTL false)
        delegate.nullsLocation = 5  // content in [0,5), trailing nulls in [5,20)
        let sel = iTermSelection()
        sel.delegate = delegate

        // Character selection dragged into the trailing-null region.
        sel.begin(at: VT100GridAbsCoordMake(0, 0),
                  mode: iTermSelectionMode.kiTermSelectionModeCharacter,
                  resume: false, append: false)
        sel.moveEndpoint(to: VT100GridAbsCoordMake(10, 0))

        // extendPastNulls (LTR line) extends a selection that reaches into the
        // trailing nulls out to the end of the line, as it did before bidi was merely
        // enabled. With the bug (gate on the global pref) it is skipped and the
        // selection stops at the drag column (10).
        let cells = IndexSet(sel.selectedIndexes(onAbsoluteLine: 0))
        XCTAssertEqual(cells, IndexSet(0..<20),
                       "selection into trailing nulls on an LTR line should extend to end of line; got \(Array(cells))")
    }
}
