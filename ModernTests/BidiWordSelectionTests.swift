//
//  BidiWordSelectionTests.swift
//  ModernTests
//
//  Double-click word selection on a right-to-left line. The mouse handler
//  converts the click's VISUAL column to a LOGICAL cell (logicalForVisual), then
//  rangeForWordAt finds the word at that logical cell. Clicking a word must
//  select THAT word — not a different one elsewhere on the line. This models the
//  pure-Persian TUI case (no Latin) where the bug shows up: click the first
//  word, a word from the middle/end gets selected.
//

import XCTest
@testable import iTerm2SharedARC

private class OneLineDataSource: NSObject, iTermTextDataSource {
    private let sca: ScreenCharArray
    private let gridWidth: Int32
    init(_ sca: ScreenCharArray, width: Int32) { self.sca = sca; self.gridWidth = width; super.init() }
    func width() -> Int32 { gridWidth }
    func numberOfLines() -> Int32 { 1 }
    func totalScrollbackOverflow() -> Int64 { 0 }
    func screenCharArray(forLine line: Int32) -> ScreenCharArray { sca }
    func screenCharArray(atScreenIndex index: Int32) -> ScreenCharArray { sca }
    func externalAttributeIndex(forLine y: Int32) -> (any iTermExternalAttributeIndexReading)? { nil }
    func fetchLine(_ line: Int32, block: (ScreenCharArray) -> Any?) -> Any? { block(sca) }
    func date(forLine line: Int32) -> Date? { nil }
    func commandMark(at coord: VT100GridCoord, mustHaveCommand: Bool, range: UnsafeMutablePointer<VT100GridWindowedRange>?) -> (any VT100ScreenMarkReading)? { nil }
    func metadata(onLine lineNumber: Int32) -> iTermImmutableMetadata { iTermImmutableMetadataDefault() }
    func isFirstLine(ofBlock lineNumber: Int32) -> Bool { false }
}

final class BidiWordSelectionTests: XCTestCase {
    private var savedDetect: Any?
    private var savedIsolate: Any?

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
        savedIsolate = iTermUserDefaults.userDefaults().object(forKey: "IsolateLatinRunsInRTL")
        iTermUserDefaults.userDefaults().set(true, forKey: "DetectParagraphDirection")
        // Pure Persian (no Latin) — islands is irrelevant. Test the default path.
        iTermUserDefaults.userDefaults().set(false, forKey: "IsolateLatinRunsInRTL")
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

    // Logical [lo, hi) cell ranges of the space-separated words in `s`.
    // These simple Persian words are all BMP, one UTF-16 unit == one cell.
    private func words(in s: String) -> [(name: String, lo: Int, hi: Int)] {
        var result: [(String, Int, Int)] = []
        let units = Array(s.utf16)
        var i = 0
        while i < units.count {
            if units[i] == 0x20 { i += 1; continue }
            let start = i
            var chars = [unichar]()
            while i < units.count && units[i] != 0x20 { chars.append(units[i]); i += 1 }
            let name = String(utf16CodeUnits: chars, count: chars.count)
            result.append((name, start, i))
        }
        return result
    }

    private func checkWordSelection(_ content: String, pad: Int, file: StaticString = #file, line: UInt = #line) {
        let s = content + String(repeating: " ", count: pad)
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(sca) else {
            return XCTFail("no bidi info for \(content)", file: file, line: line)
        }
        let ds = OneLineDataSource(sca, width: Int32(sca.length))
        let ext = iTermTextExtractor(dataSource: ds)

        for w in words(in: content) {
            // Click a cell in the middle of the word.
            let midLogical = (w.lo + w.hi - 1) / 2
            // The renderer draws logical cell midLogical at this visual column.
            let visualCol = Int(bidi.visualForLogical(Int32(midLogical)))
            // The mouse handler converts that visual click back to a logical cell.
            let clickedLogical = Int(bidi.logicalForVisual(Int32(visualCol)))
            // rangeForWordAt runs on the logical cell (post double-conversion fix).
            let range = ext.rangeForWord(at: VT100GridCoord(x: Int32(clickedLogical), y: 0),
                                         maximumLength: 1000)
            XCTAssertEqual(Int(range.coordRange.start.x), w.lo,
                           "clicking «\(w.name)» (logical mid \(midLogical), visual \(visualCol)) selected a range starting at \(range.coordRange.start.x), expected \(w.lo)",
                           file: file, line: line)
            XCTAssertEqual(Int(range.coordRange.end.x), w.hi,
                           "clicking «\(w.name)» selected a range ending at \(range.coordRange.end.x), expected \(w.hi)",
                           file: file, line: line)
        }
    }

    // The LUT the mouse handler relies on must be a clean bijection: converting a
    // logical cell to its visual column and back must return the same cell.
    func testLUTRoundTripsForRTLLine() {
        let s = "طرف میره پیش دکتر" + String(repeating: " ", count: 20)
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(sca) else { return XCTFail("no bidi info") }
        let n = Int(bidi.numberOfCells)
        for logical in 0..<n {
            let v = Int(bidi.visualForLogical(Int32(logical)))
            let back = Int(bidi.logicalForVisual(Int32(v)))
            XCTAssertEqual(back, logical,
                           "logical \(logical) -> visual \(v) -> logical \(back) (LUT not a bijection)")
        }
    }

    // Click each word on a right-justified pure-Persian line; the clicked word
    // must be the selected word.
    func testClickingWordSelectsThatWord_rightJustified() {
        checkWordSelection("طرف میره پیش دکتر", pad: 20)
    }

    // Same, but no padding (left-anchored) as a control.
    func testClickingWordSelectsThatWord_noPad() {
        checkWordSelection("طرف میره پیش دکتر", pad: 0)
    }
}
