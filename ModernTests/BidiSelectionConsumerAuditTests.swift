//
//  BidiSelectionConsumerAuditTests.swift
//  ModernTests
//
//  Audit of consumers of iTermSelection after selection became LOGICAL-
//  coordinate. The highlight path converts a visual character-drag live range
//  to logical cells per line (selectedIndexesOnAbsoluteLine:), but
//  -allSubSelections folds the live range in as raw VISUAL columns with no
//  conversion. Every consumer that reads committed subselections as logical
//  (spanningAbsRange, enumerateSelectedAbsoluteRanges, the Python API's
//  get_selection, the Companion selectionRange) therefore sees VISUAL columns
//  mislabeled as logical while a bidi character drag is in progress.
//
//  This is the model-level (Group 3) finding. It is a FAILING test: it pins the
//  contract that allSubSelections agrees with the known-correct logical
//  highlight during a live bidi drag. It fails today because the live range is
//  folded in unconverted (iTermSelection.m -allSubSelections).
//

import XCTest
@testable import iTerm2SharedARC

private class ConsumerAuditDelegate: NSObject, iTermSelectionDelegate {
    let width: Int32
    let bidi: BidiDisplayInfoObjc?
    init(width: Int32, bidi: BidiDisplayInfoObjc?) {
        self.width = width
        self.bidi = bidi
    }
    func selectionDidChange(_ selection: iTermSelection) {}
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
    func selectionIndexes(onAbsoluteLine line: Int64, containingCharacter c: unichar, in range: NSRange) -> IndexSet? { IndexSet() }
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

final class BidiSelectionConsumerAuditTests: XCTestCase {
    private var savedDetect: Any?

    private func setBidiPreference(_ enabled: Bool) {
        iTermPreferences.setBool(enabled, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while iTermPreferences.bidiEnabled() != enabled && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

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

    // Union of the logical cells covered by logicalSubSelections on `line`,
    // treating each subselection's [start.x, end.x) as a LOGICAL range (which is
    // how the scripting API and other external consumers read them).
    private func logicalCells(fromSubSelections selection: iTermSelection, line: Int64) -> IndexSet {
        var result = IndexSet()
        for sub in selection.logicalSubSelections {
            let cr = sub.absRange.coordRange
            guard cr.start.y == line, cr.end.y == line else { continue }
            let lo = Int(min(cr.start.x, cr.end.x))
            let hi = Int(max(cr.start.x, cr.end.x))
            if hi > lo { result.insert(integersIn: lo..<hi) }
        }
        return result
    }

    // FAILING until the fix: during a live bidi character drag, the external
    // logical view of the selection must agree with the known-correct logical
    // highlight from selectedIndexesOnAbsoluteLine:. allSubSelections folds the
    // live range in as raw VISUAL columns; logicalSubSelections decomposes it.
    func testLogicalSubSelectionsAgreesWithLogicalHighlightDuringBidiCharacterDrag() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        let delegate = ConsumerAuditDelegate(width: 80, bidi: bidi)
        let selection = iTermSelection()
        selection.delegate = delegate

        // Drag over the three rightmost visual cells (visual 77..79), which on
        // this right-justified RTL line are logical 0..2.
        selection.begin(at: VT100GridAbsCoordMake(79, 0),
                        mode: iTermSelectionMode.kiTermSelectionModeCharacter,
                        resume: false,
                        append: false)
        selection.moveEndpoint(to: VT100GridAbsCoordMake(77, 0))

        // The highlight path (known correct): logical cells the drag covers.
        let correctLogical = IndexSet(selection.selectedIndexes(onAbsoluteLine: 0))
        XCTAssertFalse(correctLogical.isEmpty, "sanity: the drag selects something")

        // The committed-subselection view every other consumer reads.
        let fromSubs = logicalCells(fromSubSelections: selection, line: 0)

        XCTAssertEqual(fromSubs, correctLogical,
                       "allSubSelections must report the same logical cells as the highlight " +
                       "during a live bidi character drag; it currently exposes raw visual columns.")
    }

    // Programmatic callers (selectRange:, VoiceOver set-range, smart-select commit)
    // hold LOGICAL coordinates. setSelectedLogicalRange must select exactly those
    // logical cells on a bidi line. Driving a character-mode live selection with
    // the same coordinates would treat them as visual and mis-select, which is the
    // bug those callers had.
    func testSetSelectedLogicalRangeSelectsLogicalCellsOnBidiLine() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        let delegate = ConsumerAuditDelegate(width: 80, bidi: bidi)
        let selection = iTermSelection()
        selection.delegate = delegate

        let range = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, 0, 3, 0), 0, 0)
        selection.setSelectedLogicalRange(range, mode: .kiTermSelectionModeCharacter)

        XCTAssertEqual(IndexSet(selection.selectedIndexes(onAbsoluteLine: 0)), IndexSet(0...2),
                       "a committed logical range must select its logical cells on a bidi line")

        // Contrast: the character-mode LIVE path treats the same logical coords as
        // visual columns, so it selects different cells. (This is why the callers
        // were switched to setSelectedLogicalRange.)
        let live = iTermSelection()
        live.delegate = delegate
        live.begin(at: VT100GridAbsCoordMake(0, 0),
                   mode: iTermSelectionMode.kiTermSelectionModeCharacter,
                   resume: false, append: false)
        live.moveEndpoint(to: VT100GridAbsCoordMake(2, 0))
        live.endLive()
        XCTAssertNotEqual(IndexSet(live.selectedIndexes(onAbsoluteLine: 0)), IndexSet(0...2),
                          "sanity: the live character path mis-selects logical coords on a bidi line")
    }

    // logicalSubSelections must decompose the live range the SAME way endLive
    // commits it, including the `connected` flag on a same-line split (an embedded
    // LTR run not fully swept). Otherwise a client honoring `connected` (no newline)
    // sees a different answer mid-drag than post-drag.
    func testLogicalSubSelectionsMidDragMatchesCommittedConnectedFlags() {
        let s = "کد پستی 12345 است."
        guard let bidi = paddedInfo(s) else { return XCTFail("no bidi info") }
        let ns = s as NSString
        let digitsStart = Int32(ns.range(of: "12345").location)
        let lastLogical = Int32(ns.length - 1)
        let v4 = bidi.visualForLogical(digitsStart + 3)
        let vPeriod = bidi.visualForLogical(lastLogical)

        let delegate = ConsumerAuditDelegate(width: 80, bidi: bidi)
        let sel = iTermSelection()
        sel.delegate = delegate
        // A visual sweep from the period to digit 4 splits into logical runs on one
        // line (digits 1-3 + the Persian tail), which must be marked connected.
        sel.begin(at: VT100GridAbsCoordMake(vPeriod, 0),
                  mode: iTermSelectionMode.kiTermSelectionModeCharacter,
                  resume: false, append: false)
        sel.moveEndpoint(to: VT100GridAbsCoordMake(v4, 0))
        let midConnected = sel.logicalSubSelections.map { $0.connected }

        sel.endLive()
        let committedConnected = sel.allSubSelections.map { $0.connected }

        XCTAssertTrue(committedConnected.contains(true),
                      "sanity: this drag splits into connected same-line runs")
        XCTAssertEqual(midConnected, committedConnected,
                       "mid-drag logicalSubSelections must set connected like the committed selection")
    }
}
