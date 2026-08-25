//
//  BidiSelectionBoundaryTests.swift
//  ModernTests
//
//  Character selections on bidi lines are VISUAL: the live range stores the
//  columns the user drags over, the highlight converts them to logical cells
//  per line, and when the drag ends the visual span is decomposed into
//  logical subselections so copying stays in reading order. These tests drive
//  the real iTermSelection through that pipeline with a real BidiDisplayInfo
//  for the line «آیا این درست است؟ بله؛ کاملاً درست.» (34 cells, padded to 80,
//  logical 0 at visual 79) and for a mixed line with an embedded LTR island.
//

import XCTest
@testable import iTerm2SharedARC

private class VisualSelectionDelegate: NSObject, iTermSelectionDelegate {
    let width: Int32
    let bidi: BidiDisplayInfoObjc?
    init(width: Int32, bidi: BidiDisplayInfoObjc?) {
        self.width = width
        self.bidi = bidi
    }
    func selectionDidChange(_ selection: iTermSelection!) {}
    func liveSelectionDidEnd() {}
    func selectionAbsRangeForParenthetical(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
    func selectionAbsRangeForWord(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
    func selectionAbsRangeForSmartSelection(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
    func selectionAbsRangeForWrappedLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, absCoord.y, width, absCoord.y), 0, 0) }
    func selectionAbsRangeForLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, absCoord.y, width, absCoord.y), 0, 0) }
    func selectionRangeOfTerminalNulls(onAbsoluteLine absLineNumber: Int64) -> VT100GridRange { VT100GridRangeMake(34, width - 34) }
    func selectionPredecessor(of absCoord: VT100GridAbsCoord) -> VT100GridAbsCoord { VT100GridAbsCoordMake(0, 0) }
    func selectionViewportWidth() -> Int32 { width }
    func selectionTotalScrollbackOverflow() -> Int64 { 0 }
    func selectionIndexes(onAbsoluteLine line: Int64, containingCharacter c: unichar, in range: NSRange) -> IndexSet { IndexSet() }
    func selectionParagraphIsRTL(onAbsoluteLine line: Int64) -> Bool {
        return bidi?.paragraphIsRTL ?? false
    }
    func selectionLogicalIndexes(forVisualRange visualRange: NSRange, onAbsoluteLine line: Int64) -> IndexSet {
        guard let bidi, let range = Range(visualRange) else {
            return IndexSet(integersIn: Range(visualRange) ?? 0..<0)
        }
        var result = IndexSet()
        for v in range {
            if v < Int(bidi.numberOfCells) {
                result.insert(Int(bidi.logicalForVisual(Int32(v))))
            } else {
                result.insert(v)
            }
        }
        return result
    }
}

class BidiSelectionBoundaryTests: XCTestCase {
    private func setBidiPreference(_ enabled: Bool) {
        iTermPreferences.setBool(enabled, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while iTermPreferences.bidiEnabled() != enabled && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }
    private var savedDetect: Any?
    override func setUp() {
        super.setUp()
        setBidiPreference(true)
        savedDetect = iTermUserDefaults.userDefaults().object(forKey: "DetectParagraphDirection")
        iTermUserDefaults.userDefaults().set(true, forKey: "DetectParagraphDirection")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
    }
    override func tearDown() {
        if let v = savedDetect { iTermUserDefaults.userDefaults().set(v, forKey: "DetectParagraphDirection") }
        else { iTermUserDefaults.userDefaults().removeObject(forKey: "DetectParagraphDirection") }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        setBidiPreference(false)
        super.tearDown()
    }

    private func paddedInfo(_ s: String = "آیا این درست است؟ بله؛ کاملاً درست.") -> BidiDisplayInfoObjc? {
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        return BidiDisplayInfoObjc(sca, paddedTo: 80)
    }

    // Simulates a character drag over visual columns and returns
    // (highlighted logical indexes mid-drag, final subselection ranges,
    // per-subselection connected flags).
    private func drag(_ bidi: BidiDisplayInfoObjc,
                      fromVisual v1: Int32, toVisual v2: Int32) -> (IndexSet, [NSRange], [Bool]) {
        let delegate = VisualSelectionDelegate(width: 80, bidi: bidi)
        let selection = iTermSelection()
        selection.delegate = delegate
        selection.begin(at: VT100GridAbsCoordMake(v1, 0),
                        mode: iTermSelectionMode.kiTermSelectionModeCharacter,
                        resume: false,
                        append: false)
        selection.moveEndpoint(to: VT100GridAbsCoordMake(v2, 0))
        let highlighted = IndexSet(selection.selectedIndexes(onAbsoluteLine: 0))
        selection.endLive()
        let subs = selection.allSubSelections.map { sub -> NSRange in
            let r = sub.absRange.coordRange
            return NSRange(location: Int(r.start.x), length: Int(r.end.x - r.start.x))
        }
        let connected = selection.allSubSelections.map { $0.connected }
        return (highlighted, subs, connected)
    }

    func testRightMarginDragSelectsFromFirstCharacter() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        // Drag from the right margin (visual 80) left over three cells:
        // visual 77..79 = logical 0..2 (آیا's first letters).
        let (highlighted, subs, _) = drag(bidi, fromVisual: 80, toVisual: 77)
        XCTAssertEqual(highlighted, IndexSet(0...2))
        XCTAssertEqual(subs, [NSRange(location: 0, length: 3)])
    }

    func testDragAcrossTrailingPeriodIncludesIt() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        let periodVisual = bidi.visualForLogical(33)   // 46
        // Drag rightward from the period's left edge over three cells:
        // period + ت + س = logical 31..33.
        let (highlighted, subs, _) = drag(bidi, fromVisual: periodVisual, toVisual: periodVisual + 3)
        XCTAssertEqual(highlighted, IndexSet(31...33))
        XCTAssertEqual(subs, [NSRange(location: 31, length: 3)])
    }

    func testMixedLineVisualSpanDecomposesIntoLogicalRuns() {
        // «کد پستی 12345 است.»: the digits are an LTR island. A visual drag
        // covering the last two digits and the following Persian word covers a
        // logically discontiguous set; the highlight must match the dragged
        // visual span exactly and the final subselections must be its logical
        // runs.
        let s = "کد پستی 12345 است."
        guard let bidi = paddedInfo(s) else { return XCTFail("no bidi info") }
        let ns = s as NSString
        let digitsStart = Int32(ns.range(of: "12345").location)   // logical 8
        let lastLogical = Int32(ns.length - 1)                    // the period
        // Visual columns of logical cells:
        let v4 = bidi.visualForLogical(digitsStart + 3)   // digit 4
        let v5 = bidi.visualForLogical(digitsStart + 4)   // digit 5
        XCTAssertEqual(v5, v4 + 1, "digits render left-to-right")
        // Drag from the period's visual position to digit 4: the visual span
        // covers digits 4,5 plus the Persian tail, not digits 1-3.
        let vPeriod = bidi.visualForLogical(lastLogical)
        let (highlighted, subs, connected) = drag(bidi, fromVisual: vPeriod, toVisual: v4)
        // Expectation computed directly from the visual span.
        var expected = IndexSet()
        for v in min(vPeriod, v4)..<max(vPeriod, v4) {
            expected.insert(Int(bidi.logicalForVisual(v)))
        }
        XCTAssertEqual(highlighted, expected)
        // The span runs from the period (far left) up to digit 4's left edge:
        // it covers digits 1-3 (visually left of 4) and the Persian tail, and
        // excludes digits 4 and 5.
        XCTAssertTrue(highlighted.contains(Int(digitsStart)))
        XCTAssertTrue(highlighted.contains(Int(digitsStart + 2)))
        XCTAssertFalse(highlighted.contains(Int(digitsStart + 3)))
        XCTAssertFalse(highlighted.contains(Int(digitsStart + 4)))
        // The logically discontiguous pieces of one contiguous visual sweep
        // must copy concatenated in reading order, not on separate lines:
        // every same-line piece except the last is connected (no newline).
        XCTAssertGreaterThan(subs.count, 1, "the sweep splits into logical runs")
        XCTAssertEqual(connected, (0..<subs.count).map { $0 < subs.count - 1 },
                       "all but the last same-line piece are connected")
    }

    func testUpwardDragKeepsAnchorLineWords() {
        // Anchor near the visual LEFT of the bottom RTL line (its reading
        // end) and drag up to the line above. The anchor line must keep
        // everything from its reading start (visual right edge) to the
        // anchor, with the left-to-right convention it kept the visually
        // LEFT side instead and the anchor line's words all deselected.
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        let delegate = VisualSelectionDelegate(width: 80, bidi: bidi)
        let selection = iTermSelection()
        selection.delegate = delegate
        selection.begin(at: VT100GridAbsCoordMake(10, 1),
                        mode: iTermSelectionMode.kiTermSelectionModeCharacter,
                        resume: false,
                        append: false)
        selection.moveEndpoint(to: VT100GridAbsCoordMake(70, 0))
        let bottom = IndexSet(selection.selectedIndexes(onAbsoluteLine: 1))
        let top = IndexSet(selection.selectedIndexes(onAbsoluteLine: 0))
        XCTAssertTrue(bottom.contains(0), "anchor line keeps its first character (visual right edge)")
        XCTAssertTrue(bottom.contains(33), "anchor line keeps its trailing period")
        XCTAssertTrue(top.contains(33), "upper line selected from the pointer to its reading end")
        XCTAssertFalse(top.contains(0), "upper line's first character is right of the pointer")
    }

    // BUG: appending a character drag (cmd-drag to add a selection) leaves the
    // live range VISUAL while committed subselections are logical, so
    // selectedIndexesOnAbsoluteLine takes the multi-sub slow path. That path
    // folded the live range in as if its columns were logical, so the in-progress
    // appended highlight landed on the wrong cells on a bidi line. The live
    // visual span must be converted to logical cells like the single-drag fast
    // path does.
    func testAppendingVisualDragHighlightsLogicalCellsNotRawColumns() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        let delegate = VisualSelectionDelegate(width: 80, bidi: bidi)
        let selection = iTermSelection()
        selection.delegate = delegate

        // Commit a first selection: visual 80->77 == logical 0..2.
        selection.begin(at: VT100GridAbsCoordMake(80, 0),
                        mode: .kiTermSelectionModeCharacter, resume: false, append: false)
        selection.moveEndpoint(to: VT100GridAbsCoordMake(77, 0))
        selection.endLive()
        XCTAssertEqual(selection.allSubSelections.count, 1, "first selection committed")

        // Now APPEND a second character drag over visual columns [60, 64).
        let vA: Int32 = 60, vB: Int32 = 64
        selection.begin(at: VT100GridAbsCoordMake(vA, 0),
                        mode: .kiTermSelectionModeCharacter, resume: false, append: true)
        selection.moveEndpoint(to: VT100GridAbsCoordMake(vB, 0))

        let highlighted = IndexSet(selection.selectedIndexes(onAbsoluteLine: 0))
        let appendedExpected = delegate.selectionLogicalIndexes(
            forVisualRange: NSRange(location: Int(vA), length: Int(vB - vA)),
            onAbsoluteLine: 0)

        // The committed selection is still lit.
        XCTAssertTrue(highlighted.contains(0) && highlighted.contains(2),
                      "committed selection must remain highlighted during append")
        // The appended visual span maps to logical cells (the fix).
        XCTAssertTrue(highlighted.isSuperset(of: appendedExpected),
                      "appended visual span must light logical cells \(appendedExpected.map { $0 }); got \(highlighted.sorted())")
        // The raw visual columns are trailing padding here; they must NOT be lit
        // as logical (that is the bug).
        let rawAsLogical = IndexSet(integersIn: Int(vA)..<Int(vB))
        XCTAssertFalse(highlighted.isSuperset(of: rawAsLogical),
                       "raw visual columns \(rawAsLogical.map { $0 }) must not be treated as logical; got \(highlighted.sorted())")
    }

    // After an appended visual drag ends, both selections are committed as
    // logical subselections. (endLive's decomposition is visual-aware even where
    // the live highlight was not, so this held before the fix too; it guards
    // against regressing the committed result.)
    func testAppendedVisualDragCommitsLogicalSubselections() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        let delegate = VisualSelectionDelegate(width: 80, bidi: bidi)
        let selection = iTermSelection()
        selection.delegate = delegate

        selection.begin(at: VT100GridAbsCoordMake(80, 0),
                        mode: .kiTermSelectionModeCharacter, resume: false, append: false)
        selection.moveEndpoint(to: VT100GridAbsCoordMake(77, 0))
        selection.endLive()

        let vA: Int32 = 60, vB: Int32 = 64
        selection.begin(at: VT100GridAbsCoordMake(vA, 0),
                        mode: .kiTermSelectionModeCharacter, resume: false, append: true)
        selection.moveEndpoint(to: VT100GridAbsCoordMake(vB, 0))
        selection.endLive()

        // Every committed subselection is a logical range: none of them may cover
        // the trailing padding columns [vA, vB).
        var committed = IndexSet()
        for sub in selection.allSubSelections {
            let r = sub.absRange.coordRange
            committed.insert(integersIn: Int(r.start.x)..<Int(r.end.x))
        }
        let appendedExpected = delegate.selectionLogicalIndexes(
            forVisualRange: NSRange(location: Int(vA), length: Int(vB - vA)), onAbsoluteLine: 0)
        XCTAssertTrue(committed.isSuperset(of: IndexSet(0...2)), "first selection retained")
        XCTAssertTrue(committed.isSuperset(of: appendedExpected), "appended run committed as logical cells")
        XCTAssertFalse(committed.isSuperset(of: IndexSet(integersIn: Int(vA)..<Int(vB))),
                       "committed subselections must not include the raw visual columns")
    }

    // A copy of a LIVE visual selection (PTYTextView makes such a copy for its
    // dirty-region diff) must highlight the same cells as the original. This
    // requires copyWithZone to carry _liveRangeIsVisual; without it the copy
    // reinterprets the visual live range as logical.
    func testCopyOfLiveVisualSelectionHighlightsSameCells() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        let delegate = VisualSelectionDelegate(width: 80, bidi: bidi)
        let selection = iTermSelection()
        selection.delegate = delegate
        selection.begin(at: VT100GridAbsCoordMake(80, 0),
                        mode: .kiTermSelectionModeCharacter, resume: false, append: false)
        selection.moveEndpoint(to: VT100GridAbsCoordMake(70, 0))

        let original = IndexSet(selection.selectedIndexes(onAbsoluteLine: 0))
        guard let copy = selection.copy() as? iTermSelection else { return XCTFail("copy failed") }
        copy.delegate = delegate
        let copied = IndexSet(copy.selectedIndexes(onAbsoluteLine: 0))

        XCTAssertFalse(original.isEmpty, "sanity: the live selection highlights something")
        XCTAssertEqual(copied, original,
                       "a copy of a live visual selection must highlight the same cells")
    }

    // Box (rectangular) selections are NOT visual even when bidi is on: their
    // columns are logical and must not be remapped through the reorder LUT.
    func testBoxSelectionStaysLogicalOnBidiLine() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        let delegate = VisualSelectionDelegate(width: 80, bidi: bidi)
        let selection = iTermSelection()
        selection.delegate = delegate
        selection.begin(at: VT100GridAbsCoordMake(10, 0),
                        mode: .kiTermSelectionModeBox, resume: false, append: false)
        selection.moveEndpoint(to: VT100GridAbsCoordMake(13, 0))

        let highlighted = IndexSet(selection.selectedIndexes(onAbsoluteLine: 0))
        XCTAssertTrue(highlighted.contains(10), "box column 10 stays at logical column 10")
        let remapped = Int(bidi.logicalForVisual(10))
        if remapped != 10 {
            XCTAssertFalse(highlighted.contains(remapped),
                           "box selection must not remap columns through the bidi LUT (remapped=\(remapped))")
        }
    }

}
