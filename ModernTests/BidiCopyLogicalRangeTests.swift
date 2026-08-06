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

    // A partial selection covering an English word embedded in RTL must copy the
    // whole word contiguously — «Berlin» must not come out as «B … شهری» (the
    // visually-adjacent-but-logically-split result the user hit).
    func testPartialCopyKeepsEnglishWordWhole() {
        let width = 40
        // Persian first -> RTL paragraph; «Berlin» is an English island in the middle.
        let content = "متن Berlin شهری بزرگ"
        let s = content + String(repeating: " ", count: width - content.count)
        let base = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(base) else { return XCTFail("no bidi") }
        XCTAssertNotEqual(bidi.visualForLogical(0), 0, "mixed line not reordered; test is meaningless")
        let sca = ScreenCharArray(copyOfLine: base.line, length: base.length,
                                  continuation: base.continuation, bidiInfo: bidi)
        let ds = BidiLinesDataSource([sca], width: Int32(width))
        let extractor = iTermTextExtractor(dataSource: ds)
        extractor.supportBidi = true

        // Select logical [0, 12): «متن Berlin ش» — covers متن plus the whole Berlin island.
        let range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 12, 0), 0, 0)
        let text = extractor.content(in: range, excludingSubranges: nil) ?? ""
        XCTAssertTrue(text.contains("Berlin"),
                      "English island was split by the copy; expected whole 'Berlin', got >>>\(text)<<<")
    }
}

// Minimal delegate for driving a VISUAL character selection end to end.
private final class VisualCopyDelegate: NSObject, iTermSelectionDelegate {
    let width: Int32
    let bidi: BidiDisplayInfoObjc
    init(width: Int32, bidi: BidiDisplayInfoObjc) { self.width = width; self.bidi = bidi }
    func selectionDidChange(_ selection: iTermSelection!) {}
    func liveSelectionDidEnd() {}
    func selectionAbsRangeForParenthetical(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
    func selectionAbsRangeForWord(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
    func selectionAbsRangeForSmartSelection(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
    func selectionAbsRangeForWrappedLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, absCoord.y, width, absCoord.y), 0, 0) }
    func selectionAbsRangeForLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, absCoord.y, width, absCoord.y), 0, 0) }
    func selectionRangeOfTerminalNulls(onAbsoluteLine absLineNumber: Int64) -> VT100GridRange { VT100GridRangeMake(0, 0) }
    func selectionPredecessor(of absCoord: VT100GridAbsCoord) -> VT100GridAbsCoord { VT100GridAbsCoordMake(0, 0) }
    func selectionViewportWidth() -> Int32 { width }
    func selectionTotalScrollbackOverflow() -> Int64 { 0 }
    func selectionIndexes(onAbsoluteLine line: Int64, containingCharacter c: unichar, in range: NSRange) -> IndexSet { IndexSet() }
    func selectionParagraphIsRTL(onAbsoluteLine line: Int64) -> Bool { bidi.paragraphIsRTL }
    func selectionLogicalIndexes(forVisualRange visualRange: NSRange, onAbsoluteLine line: Int64) -> IndexSet {
        guard let range = Range(visualRange) else { return IndexSet() }
        var result = IndexSet()
        for v in range {
            if v < Int(bidi.numberOfCells) { result.insert(Int(bidi.logicalForVisual(Int32(v)))) }
            else { result.insert(v) }
        }
        return result
    }
}

extension BidiCopyLogicalRangeTests {
    // A full visual sweep of a right-justified RTL line (margin to left edge)
    // must copy the logical sentence exactly: one subselection, period
    // attached at the reading end, no stray whitespace.
    func testVisualFullLineSweepCopiesLogicalSentence() {
        let width = 60
        let content = "کتابخانه (کتابخانهٔ ملی) دو چیزند."
        // Full-width line like a real grid row (spaces stand in for nulls).
        let s = content + String(repeating: " ", count: width - content.count)
        let base = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(base) else { return XCTFail("no bidi") }
        let sca = ScreenCharArray(copyOfLine: base.line, length: base.length,
                                  continuation: base.continuation, bidiInfo: bidi)
        let ds = BidiLinesDataSource([sca], width: Int32(width))
        let extractor = iTermTextExtractor(dataSource: ds)
        extractor.supportBidi = true

        let delegate = VisualCopyDelegate(width: Int32(width), bidi: bidi)
        let selection = iTermSelection()
        selection.delegate = delegate
        selection.begin(at: VT100GridAbsCoordMake(Int32(width), 0),
                        mode: iTermSelectionMode.kiTermSelectionModeCharacter,
                        resume: false, append: false)
        selection.moveEndpoint(to: VT100GridAbsCoordMake(0, 0))
        selection.endLive()

        var pieces: [String] = []
        for sub in selection.allSubSelections {
            let r = sub.absRange.coordRange
            print("DIAG sub: (\(r.start.x),\(r.start.y))-(\(r.end.x),\(r.end.y))")
            let range = VT100GridWindowedRangeMake(
                VT100GridCoordRangeMake(r.start.x, Int32(r.start.y), r.end.x, Int32(r.end.y)), 0, 0)
            let text = extractor.content(in: range, excludingSubranges: nil) ?? ""
            print("DIAG piece: >>>\(text.debugDescription)<<<")
            pieces.append(text)
        }
        let joined = pieces.joined()
        XCTAssertEqual(selection.allSubSelections.count, 1,
                       "a full-line visual sweep of a pure-RTL line is one logical run")
        XCTAssertEqual(joined, content,
                       "copied text must be the logical sentence with the period attached")
    }
}
