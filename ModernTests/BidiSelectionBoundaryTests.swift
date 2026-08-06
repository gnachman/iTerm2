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
    private var savedIsolate: Any?
    override func setUp() {
        super.setUp()
        setBidiPreference(true)
        savedDetect = iTermUserDefaults.userDefaults().object(forKey: "DetectParagraphDirection")
        savedIsolate = iTermUserDefaults.userDefaults().object(forKey: "IsolateLatinRunsInRTL")
        iTermUserDefaults.userDefaults().set(true, forKey: "DetectParagraphDirection")
        iTermUserDefaults.userDefaults().set(true, forKey: "IsolateLatinRunsInRTL")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
    }
    override func tearDown() {
        if let v = savedDetect { iTermUserDefaults.userDefaults().set(v, forKey: "DetectParagraphDirection") }
        else { iTermUserDefaults.userDefaults().removeObject(forKey: "DetectParagraphDirection") }
        if let v = savedIsolate { iTermUserDefaults.userDefaults().set(v, forKey: "IsolateLatinRunsInRTL") }
        else { iTermUserDefaults.userDefaults().removeObject(forKey: "IsolateLatinRunsInRTL") }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        setBidiPreference(false)
        super.tearDown()
    }

    private func paddedInfo(_ s: String = "آیا این درست است؟ بله؛ کاملاً درست.") -> BidiDisplayInfoObjc? {
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        return BidiDisplayInfoObjc(sca, paddedTo: 80)
    }

    // Simulates a character drag over visual columns and returns
    // (highlighted logical indexes mid-drag, final subselection ranges).
    private func drag(_ bidi: BidiDisplayInfoObjc,
                      fromVisual v1: Int32, toVisual v2: Int32) -> (IndexSet, [NSRange]) {
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
        return (highlighted, subs)
    }

    func testRightMarginDragSelectsFromFirstCharacter() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        // Drag from the right margin (visual 80) left over three cells:
        // visual 77..79 = logical 0..2 (آیا's first letters).
        let (highlighted, subs) = drag(bidi, fromVisual: 80, toVisual: 77)
        XCTAssertEqual(highlighted, IndexSet(0...2))
        XCTAssertEqual(subs, [NSRange(location: 0, length: 3)])
    }

    func testDragAcrossTrailingPeriodIncludesIt() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        let periodVisual = bidi.visualForLogical(33)   // 46
        // Drag rightward from the period's left edge over three cells:
        // period + ت + س = logical 31..33.
        let (highlighted, subs) = drag(bidi, fromVisual: periodVisual, toVisual: periodVisual + 3)
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
        let (highlighted, _) = drag(bidi, fromVisual: vPeriod, toVisual: v4)
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

    func testMinimumRTLWordsFlipsLatinMajorityLine() {
        // «novid ~ % تلفن» opens LTR and Latin holds the majority, so by
        // default it stays a left-to-right paragraph. With the minimum-RTL-
        // words rule set to 1, one Persian word is enough to lay the line out
        // right-to-left, so a prompt holding a pasted Persian word
        // right-justifies like the same text does in command output.
        let saved = iTermUserDefaults.userDefaults().object(forKey: "RtlParagraphMinimumWords")
        defer {
            if let saved { iTermUserDefaults.userDefaults().set(saved, forKey: "RtlParagraphMinimumWords") }
            else { iTermUserDefaults.userDefaults().removeObject(forKey: "RtlParagraphMinimumWords") }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        let line = "novid@mac ~ % تلفن"

        iTermUserDefaults.userDefaults().set(0, forKey: "RtlParagraphMinimumWords")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        let sca1 = screenCharArrayWithDefaultStyle(line, eol: EOL_HARD)
        guard let off = BidiDisplayInfoObjc(sca1) else { return XCTFail("no bidi info") }
        XCTAssertFalse(off.paragraphIsRTL, "Latin-majority line stays LTR with the rule off")

        iTermUserDefaults.userDefaults().set(1, forKey: "RtlParagraphMinimumWords")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        let sca2 = screenCharArrayWithDefaultStyle(line, eol: EOL_HARD)
        guard let on = BidiDisplayInfoObjc(sca2) else { return XCTFail("no bidi info") }
        XCTAssertTrue(on.paragraphIsRTL, "one Persian word flips the line with the rule at 1")
    }

    func testGuillemetsJoinLatinIsland() throws {
        // «machine learning» inside a Persian sentence must render with the
        // marks on their typed sides: the guillemets join the LTR island, so
        // visually the quoted phrase reads «machine learning» as typed
        // instead of the UBA placement »machine learning«.
        guard iTermAdvancedSettingsModel.isolateLatinRunsInRTL() else {
            throw XCTSkip("isolateLatinRunsInRTL is off")
        }
        let s = "اصطلاح «machine learning» را جستجو کن."
        let ns = s as NSString
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(sca) else { return XCTFail("no bidi info") }
        let open = Int32(ns.range(of: "«").location)
        let close = Int32(ns.range(of: "»").location)
        let mStart = Int32(ns.range(of: "machine").location)
        // As typed: « immediately left of the m of machine, » immediately
        // right of the g of learning.
        XCTAssertEqual(bidi.visualForLogical(open), bidi.visualForLogical(mStart) - 1,
                       "opening guillemet must sit visually left of 'machine'")
        XCTAssertEqual(bidi.visualForLogical(close), bidi.visualForLogical(close - 1) + 1,
                       "closing guillemet must sit visually right of 'learning'")
    }
}
