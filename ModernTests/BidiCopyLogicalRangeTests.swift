//
//  BidiCopyLogicalRangeTests.swift
//  ModernTests
//
//  The selection is stored in LOGICAL coordinates. Copying it must return the
//  text of that LOGICAL range in reading order. On a reordered right-to-left
//  line the extractor's bidi branch used to treat the range as VISUAL, so a
//  partial selection (and the last line of a multi-line selection) extracted
//  the empty left margin instead of the words — the copy came back empty even
//  though the highlight (which correctly uses the logical range) showed text.
//

import XCTest
@testable import iTerm2SharedARC

private final class BidiLinesDataSource: NSObject, iTermTextDataSource {
    private let scas: [ScreenCharArray]
    private let gridWidth: Int32
    init(_ scas: [ScreenCharArray], width: Int32) { self.scas = scas; self.gridWidth = width; super.init() }
    func width() -> Int32 { gridWidth }
    func numberOfLines() -> Int32 { Int32(scas.count) }
    func totalScrollbackOverflow() -> Int64 { 0 }
    func screenCharArray(forLine line: Int32) -> ScreenCharArray {
        (line >= 0 && line < Int32(scas.count)) ? scas[Int(line)] : ScreenCharArray.emptyLine(ofLength: gridWidth)
    }
    func screenCharArray(atScreenIndex index: Int32) -> ScreenCharArray { screenCharArray(forLine: index) }
    func externalAttributeIndex(forLine y: Int32) -> (any iTermExternalAttributeIndexReading)? { nil }
    func fetchLine(_ line: Int32, block: (ScreenCharArray) -> Any?) -> Any? { block(screenCharArray(forLine: line)) }
    func date(forLine line: Int32) -> Date? { nil }
    func commandMark(at coord: VT100GridCoord, mustHaveCommand: Bool, range: UnsafeMutablePointer<VT100GridWindowedRange>?) -> (any VT100ScreenMarkReading)? { nil }
    func metadata(onLine lineNumber: Int32) -> iTermImmutableMetadata { iTermImmutableMetadataDefault() }
    func isFirstLine(ofBlock lineNumber: Int32) -> Bool { false }
}

class BidiCopyLogicalRangeTests: XCTestCase {
    private var savedDetect: Any?
    override func setUp() {
        super.setUp()
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        savedDetect = iTermUserDefaults.userDefaults().object(forKey: "DetectParagraphDirection")
        iTermUserDefaults.userDefaults().set(true, forKey: "DetectParagraphDirection")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
    }
    override func tearDown() {
        if let v = savedDetect { iTermUserDefaults.userDefaults().set(v, forKey: "DetectParagraphDirection") }
        else { iTermUserDefaults.userDefaults().removeObject(forKey: "DetectParagraphDirection") }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi)
        super.tearDown()
    }

    // Returns (sca, bidi). Asserts the line is actually reordered.
    private func reorderedLine(_ content: String, width: Int, file: StaticString = #filePath, line: UInt = #line) -> (ScreenCharArray, BidiDisplayInfoObjc)? {
        let s = content + String(repeating: " ", count: max(0, width - content.count))
        let base = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(base) else { XCTFail("no bidi", file: file, line: line); return nil }
        // Sanity: a right-to-left line must NOT be identity-mapped, or the test
        // isn't exercising reordering at all.
        XCTAssertNotEqual(bidi.visualForLogical(0), 0, "line not reordered; test is meaningless", file: file, line: line)
        let sca = ScreenCharArray(copyOfLine: base.line, length: base.length,
                                  continuation: base.continuation, bidiInfo: bidi)
        return (sca, bidi)
    }

    // Partial selection on ONE reordered RTL line: logical [0, k). Copy must be
    // the first k logical characters (reading order), not the empty left margin.
    func testPartialSingleLineCopyIsLogical() {
        let width = 30
        let content = "سلام دنیا خوب"
        guard let (sca, _) = reorderedLine(content, width: width) else { return }
        let ds = BidiLinesDataSource([sca], width: Int32(width))
        let extractor = iTermTextExtractor(dataSource: ds)
        extractor.supportBidi = true

        let k: Int32 = 4  // logical [0,4) == first 4 chars "سلام"
        let range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, k, 0), 0, 0)
        let text = (extractor.content(in: range, excludingSubranges: nil) ?? "")
            .trimmingCharacters(in: .whitespaces)
        let expected = String(Array(content)[0..<Int(k)])
        XCTAssertEqual(text, expected, "partial RTL copy should be the logical range \(expected), got >>>\(text)<<<")
    }

    // Multi-line: line 0 from logical 4 to end, line 1 from start to logical 6.
    // Copy must include BOTH lines' logical text.
    func testMultilineRTLCopyIncludesBothLines() {
        let width = 30
        let l0 = "سلام دنیا خوب"
        let l1 = "روز خوش دوست"
        guard let (s0, _) = reorderedLine(l0, width: width),
              let (s1, _) = reorderedLine(l1, width: width) else { return }
        let ds = BidiLinesDataSource([s0, s1], width: Int32(width))
        let extractor = iTermTextExtractor(dataSource: ds)
        extractor.supportBidi = true

        let range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(4, 0, 6, 1), 0, 0)
        let text = extractor.content(in: range, excludingSubranges: nil) ?? ""
        // «ر»/«ز» appear only in line 1 (روز); their presence means line 1 wasn't dropped.
        XCTAssertTrue(text.contains("ن") || text.contains("ا"), "line 0 missing; got >>>\(text)<<<")
        XCTAssertTrue(text.contains("ر") || text.contains("ز"),
                      "line 1 (روز خوش دوست) dropped from multi-line copy; got >>>\(text)<<<")
    }
}
