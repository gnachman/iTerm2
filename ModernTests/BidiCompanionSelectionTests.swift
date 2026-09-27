//
//  BidiCompanionSelectionTests.swift
//  ModernTests
//
//  Companion (iOS "Buddy") finding. The phone works in VISUAL columns (it renders
//  a streamed image and touches at pixel positions), but iTermSelection is LOGICAL.
//  Word/smart gestures fed the phone's visual column into a mode that interprets it
//  as logical (wrong token on RTL lines), and the reverse selectionRange reported
//  logical committed columns to a phone that draws them visually (handles jumped on
//  finger-lift). These pin the two pure column converters the bridge now uses.
//

import XCTest
@testable import iTerm2SharedARC

final class BidiCompanionSelectionTests: XCTestCase {
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

    // Input: a phone word/smart gesture column (VISUAL) must be converted to the
    // LOGICAL cell iTermSelection expects for those modes.
    func testLogicalColumnForVisualConvertsOnBidiLine() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        let visualX: Int32 = 78
        XCTAssertNotEqual(bidi.logicalForVisual(visualX), visualX, "sanity: visual != logical here")

        XCTAssertEqual(CompanionHostBridge.logicalColumn(forVisualColumn: visualX, bidi: bidi),
                       bidi.logicalForVisual(visualX))
        // Identity without bidi so left-to-right lines are untouched.
        XCTAssertEqual(CompanionHostBridge.logicalColumn(forVisualColumn: visualX, bidi: nil), visualX)
        // Out-of-range columns pass through.
        XCTAssertEqual(CompanionHostBridge.logicalColumn(forVisualColumn: 1000, bidi: bidi), 1000)
    }

    // Reverse: a committed LOGICAL selection column must be converted to the VISUAL
    // column the phone draws its handle at.
    func testVisualColumnForLogicalConvertsOnBidiLine() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        let logicalX: Int32 = 0
        XCTAssertNotEqual(bidi.visualForLogical(logicalX), logicalX, "sanity: logical != visual here")

        XCTAssertEqual(CompanionHostBridge.visualColumn(forLogicalColumn: logicalX, bidi: bidi),
                       bidi.visualForLogical(logicalX))
        XCTAssertEqual(CompanionHostBridge.visualColumn(forLogicalColumn: 5, bidi: nil), 5)
        XCTAssertEqual(CompanionHostBridge.visualColumn(forLogicalColumn: 1000, bidi: bidi), 1000)
    }

    // FAILING until the fix: a selection running through the end of a line is stored
    // as (startX, y, 0, y+1). The single-line span must sweep to the grid width for a
    // sub whose end wrapped to the next line, not to its raw exclusive end.x (0),
    // which would select nothing and make the phone's handles vanish. Plain LTR too.
    func testVisualColumnSpanIncludesSelectionThroughEndOfLine() {
        let sub = iTermSubSelection(absRange: VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(5, 3, 0, 4), 0, 0),
                                    mode: .kiTermSelectionModeCharacter,
                                    width: 20)
        let span = CompanionHostBridge.visualColumnSpan(forSelectedSubs: [sub],
                                                        onLine: 3,
                                                        gridWidth: 20,
                                                        bidi: nil)
        XCTAssertNotNil(span, "a selection running through end-of-line must not vanish")
        XCTAssertEqual(span?.min, 5)
        XCTAssertEqual(span?.max, 19, "the sweep must reach the last cell of the line")
    }

    // FAILING until the fix: a select-through-EOL range on a reordered RTL line
    // whose content is shorter than the grid width must not push the visual max out
    // to the grid's right edge. The trailing padding (logical cols >= numberOfCells)
    // maps to identity/large visual columns; the sweep must exclude them.
    func testVisualColumnSpanThroughEOLExcludesTrailingPaddingOnRTLLine() {
        let content = "آیا این درست است؟ بله؛ کاملاً درست."  // shorter than the grid width
        let sca = screenCharArrayWithDefaultStyle(content, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(sca) else { return XCTFail("no bidi info") }
        let numCells = bidi.numberOfCells
        XCTAssertLessThan(numCells, 80, "content must be shorter than the grid width")

        // Select-through-EOL sub on line 0, stored as (5, 0, 0, 1) (end wraps to line 1).
        let sub = iTermSubSelection(absRange: VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(5, 0, 0, 1), 0, 0),
                                    mode: .kiTermSelectionModeCharacter, width: 80)
        guard let span = CompanionHostBridge.visualColumnSpan(forSelectedSubs: [sub],
                                                              onLine: 0, gridWidth: 80, bidi: bidi) else {
            return XCTFail("nil span")
        }

        // vmax should bound the actually-reordered content, not the padding.
        var contentMax = Int32.min
        for l in Int32(5)..<numCells { contentMax = max(contentMax, bidi.visualForLogical(l)) }
        XCTAssertEqual(span.max, contentMax,
                       "vmax should bound the content's visual columns; got \(span.max) vs \(contentMax)")
        XCTAssertLessThan(span.max, 79,
                          "vmax must not be inflated to the grid's right edge by trailing padding")
    }

    // Round-trip: converting a visual column to logical and back returns the
    // original for every mapped cell.
    func testColumnConversionRoundTrips() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        for v in Int32(0)..<bidi.numberOfCells {
            let logical = CompanionHostBridge.logicalColumn(forVisualColumn: v, bidi: bidi)
            let visual = CompanionHostBridge.visualColumn(forLogicalColumn: logical, bidi: bidi)
            XCTAssertEqual(visual, v, "round-trip failed at visual column \(v)")
        }
    }
}
