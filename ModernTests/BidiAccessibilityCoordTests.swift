//
//  BidiAccessibilityCoordTests.swift
//  ModernTests
//
//  Accessibility findings. VoiceOver hit-testing derives a VISUAL column from a
//  screen point but the accessibility text model is LOGICAL, so range-for-position
//  landed on the wrong character on right-to-left lines. And bounds-for-range was
//  computed by multiplying a LOGICAL column by the cell width with no visual
//  mapping, so the focus rectangle landed on the mirror-image cells. These pin the
//  two pure coordinate helpers the accessibility methods now use.
//

import XCTest
@testable import iTerm2SharedARC

final class BidiAccessibilityCoordTests: XCTestCase {
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

    // FAILING until the fix: coord-for-point must map the VISUAL column it derives
    // from the screen point to the LOGICAL cell the accessibility model indexes.
    func testCoordForPointMapsVisualToLogicalOnBidiLine() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        let visualX: Int32 = 78
        let expectedLogical = bidi.logicalForVisual(visualX)
        XCTAssertNotEqual(expectedLogical, visualX, "sanity: visual != logical at this column")

        let got = PTYTextView.accessibilityLogicalX(forVisualX: visualX, bidiInfo: bidi)
        XCTAssertEqual(got, expectedLogical,
                       "accessibility coord-for-point must convert the visual column to logical")

        // No bidi info: identity, so left-to-right text is untouched.
        XCTAssertEqual(PTYTextView.accessibilityLogicalX(forVisualX: visualX, bidiInfo: nil), visualX)
    }

    // FAILING until the fix: bounds-for-range must place the focus rect at the
    // VISUAL columns of a logical range, not at the logical columns.
    func testFrameForRangeUsesVisualColumnSpanOnBidiLine() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        // Logical cells 0..2 of a right-justified RTL line sit at the far right.
        var lo = Int32.max, hi = Int32.min
        for l in Int32(0)..<3 {
            let v = bidi.visualForLogical(l)
            lo = min(lo, v); hi = max(hi, v)
        }
        XCTAssertNotEqual(lo, 0, "sanity: logical start maps to a nonzero visual column here")

        let span = PTYTextView.accessibilityVisualColumnSpan(forLogicalStartX: 0, endX: 3, bidiInfo: bidi)
        XCTAssertEqual(span.location, lo, "focus rect must start at the visual column")
        XCTAssertEqual(span.length, hi - lo + 1)

        // No bidi info: identity span.
        let plain = PTYTextView.accessibilityVisualColumnSpan(forLogicalStartX: 2, endX: 6, bidiInfo: nil)
        XCTAssertEqual(plain.location, 2)
        XCTAssertEqual(plain.length, 4)
    }

    // FAILING until the fix: a zero-width query (a VoiceOver caret/focus position)
    // must still convert its single column to visual, or the caret rect lands on the
    // mirror-image cell on a right-to-left line.
    func testVisualColumnSpanConvertsZeroWidthCaretOnBidiLine() {
        guard let bidi = paddedInfo() else { return XCTFail("no bidi info") }
        let span = PTYTextView.accessibilityVisualColumnSpan(forLogicalStartX: 0, endX: 0, bidiInfo: bidi)
        XCTAssertNotEqual(bidi.visualForLogical(0), 0, "sanity: logical 0 != visual 0 on this RTL line")
        XCTAssertEqual(span.location, bidi.visualForLogical(0),
                       "a zero-width caret must map to the visual column, not the raw logical column")
        XCTAssertEqual(span.length, 0)
    }
}
