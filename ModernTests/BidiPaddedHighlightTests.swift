//
//  BidiPaddedHighlightTests.swift
//  ModernTests
//
//  Alternate-screen (TUI) rows build a PADDED / right-justified BidiDisplayInfo
//  (initWithScreenCharArray:paddedTo:width), unlike scrollback which is
//  unpadded. The earlier selection-highlight tests only used the unpadded form.
//  This drives the real backgroundRunsInLine path with the padded bidi and
//  asserts the highlight lands on the visual columns the padded LUT maps the
//  selected LOGICAL cells to (i.e. the words on the right), not empty padding.
//

import XCTest
@testable import iTerm2SharedARC

class BidiPaddedHighlightTests: XCTestCase {
    private var savedDetect: Any?
    private var savedRJ: Any?
    override func setUp() {
        super.setUp()
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        savedDetect = iTermUserDefaults.userDefaults().object(forKey: "DetectParagraphDirection")
        savedRJ = iTermUserDefaults.userDefaults().object(forKey: "RightJustifyRTLLines")
        iTermUserDefaults.userDefaults().set(true, forKey: "DetectParagraphDirection")
        iTermUserDefaults.userDefaults().set(true, forKey: "RightJustifyRTLLines")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
    }
    override func tearDown() {
        restore("DetectParagraphDirection", savedDetect)
        restore("RightJustifyRTLLines", savedRJ)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi)
        super.tearDown()
    }
    private func restore(_ k: String, _ v: Any?) {
        if let v { iTermUserDefaults.userDefaults().set(v, forKey: k) }
        else { iTermUserDefaults.userDefaults().removeObject(forKey: k) }
    }

    func testPaddedRightJustifiedHighlightFollowsLogicalCells() {
        let width: Int32 = 24
        let content = "سلام دنیا"                 // 9 cells of RTL content
        // The TUI builds bidi from the paragraph content, padded to the grid width.
        let contentSca = screenCharArrayWithDefaultStyle(content, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(contentSca, paddedTo: width) else {
            return XCTFail("no padded bidi (needs RTL + rightJustify)")
        }
        XCTAssertEqual(bidi.numberOfCells, width, "padded bidi should span the full width")
        // Right-justified: logical 0 must map to a visual column on the RIGHT.
        XCTAssertGreaterThan(bidi.visualForLogical(0), width / 2,
                             "content should be right-justified; visualForLogical(0)=\(bidi.visualForLogical(0))")

        // The actual grid row: content then trailing spaces, full width.
        let full = content + String(repeating: " ", count: Int(width) - content.count)
        let lineSca = screenCharArrayWithDefaultStyle(full, eol: EOL_HARD)

        // Select the first three LOGICAL content cells.
        var selected = IndexSet()
        selected.insert(integersIn: 0..<3)

        var anyBlink: ObjCBool = false
        guard let runs = iTermBackgroundColorRunsInLine.backgroundRuns(
            inLine: lineSca.line, lineLength: width, sourceLineNumber: 0, displayLineNumber: 0,
            selectedIndexes: selected, within: NSRange(location: 0, length: Int(width)),
            matches: nil, anyBlink: &anyBlink, y: 0, bidi: bidi, eaIndex: nil, darkMode: false) else {
            return XCTFail("no runs")
        }
        var highlighted = Set<Int>()
        for boxed in runs.array where boxed.valuePointer.pointee.selected.boolValue {
            let r = boxed.valuePointer.pointee.visualRange
            for v in r.location..<(r.location + r.length) { highlighted.insert(v) }
        }
        let expected = Set(selected.map { Int(bidi.visualForLogical(Int32($0))) })
        XCTAssertEqual(highlighted, expected,
                       "padded/right-justified highlight landed on \(highlighted.sorted()), expected \(expected.sorted())")
    }
}
