//
//  BidiSelectionBoundaryTests.swift
//  ModernTests
//
//  A character selection anchors at a cell BOUNDARY. On a bidi line the
//  boundary on the logical-start side of an RTL cell is its VISUAL-RIGHT
//  edge, so a naive visual→logical cell map is off by one on one side:
//  clicking the trailing period of «…درست.» and dragging visually right could
//  never include the period, and a click in the right margin of a
//  right-justified row anchored at the logical END of the line, selecting the
//  whole row the moment the drag started. selectionAnchorForVisualCell picks
//  the nearer boundary from the clicked half of the cell and clamps margin
//  clicks; these tests pin its mapping.
//

import XCTest
@testable import iTerm2SharedARC

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
        // Match the real app: paragraph direction auto-detected so the RTL test
        // line right-justifies (content pushed right, padding on the left).
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

    // «آیا این درست است؟ بله؛ کاملاً درست.» = 34 cells, padded to 80.
    // With an RTL paragraph: logical 0 (آ) at visual 79, period (33) at 46.
    private func paddedInfo() -> BidiDisplayInfoObjc? {
        let s = "آیا این درست است؟ بله؛ کاملاً درست."
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        return BidiDisplayInfoObjc(sca, paddedTo: 80)
    }

    func testRightMarginClickAnchorsAtFirstCharacter() {
        guard let info = paddedInfo() else { return XCTFail("no bidi info") }
        XCTAssertEqual(info.numberOfCells, 80, "expected a fully padded row")
        // Overflow (margin) click: anchor at the logical cell of the last
        // visual column — the line's first character — not logical 80.
        XCTAssertEqual(info.selectionAnchor(forVisualCell: 80, leftHalf: false, gridWidth: 80), 0)
        XCTAssertEqual(info.selectionAnchor(forVisualCell: 80, leftHalf: true, gridWidth: 80), 0)
        // Right half of آ itself: boundary before it.
        XCTAssertEqual(info.selectionAnchor(forVisualCell: 79, leftHalf: false, gridWidth: 80), 0)
        // Left half of آ: boundary between آ and ی.
        XCTAssertEqual(info.selectionAnchor(forVisualCell: 79, leftHalf: true, gridWidth: 80), 1)
    }

    func testTrailingPeriodLeftHalfAnchorsAfterIt() {
        guard let info = paddedInfo() else { return XCTFail("no bidi info") }
        let periodVisual = info.visualForLogical(33)
        XCTAssertEqual(info.logicalForVisual(periodVisual), 33)
        // Left half of the period cell: the boundary AFTER the period
        // logically, so a visually-rightward drag includes it.
        XCTAssertEqual(info.selectionAnchor(forVisualCell: periodVisual, leftHalf: true, gridWidth: 80), 34)
        // Right half: boundary before the period (it stays excluded, matching
        // the left-to-right mirror of this gesture).
        XCTAssertEqual(info.selectionAnchor(forVisualCell: periodVisual, leftHalf: false, gridWidth: 80), 33)
    }

    func testPaddingCellsKeepFloorSemantics() {
        guard let info = paddedInfo() else { return XCTFail("no bidi info") }
        // Padding cells are not RTL; both halves anchor at the same cell.
        let logical = info.logicalForVisual(10)
        XCTAssertEqual(info.selectionAnchor(forVisualCell: 10, leftHalf: true, gridWidth: 80), logical)
        XCTAssertEqual(info.selectionAnchor(forVisualCell: 10, leftHalf: false, gridWidth: 80), logical)
    }

    func testUnpaddedRowKeepsLegacyOverflowIdentity() {
        // LTR-first mixed line: no right-justification, so the row is not
        // padded and clicks past the content keep the legacy identity mapping
        // (selecting the emptiness after the line must still work).
        let s = "The word سلام means hello"
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let info = BidiDisplayInfoObjc(sca) else { return XCTFail("no bidi info") }
        XCTAssertLessThan(info.numberOfCells, 80)
        XCTAssertEqual(info.selectionAnchor(forVisualCell: 60, leftHalf: true, gridWidth: 80), 60)
        XCTAssertEqual(info.selectionAnchor(forVisualCell: 60, leftHalf: false, gridWidth: 80), 60)
    }
}
