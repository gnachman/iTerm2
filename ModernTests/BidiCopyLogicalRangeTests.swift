//
//  BidiCopyLogicalRangeTests.swift
//  ModernTests
//
//  The selection is stored in LOGICAL coordinates. Copying it must return the
//  text of that LOGICAL range in reading order. On a reordered right-to-left
//  line the extractor's bidi branch used to treat the range as VISUAL, so a
//  partial selection (and the last line of a multi-line selection) extracted
//  the empty left margin instead of the words, the copy came back empty even
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
    // bidiEnabled is a cache updated by KVO dispatched to the main queue;
    // visual character selection keys off it, so wait for it to land.
    private func setBidiPreference(_ enabled: Bool) {
        iTermPreferences.setBool(enabled, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(5)
        while iTermPreferences.bidiEnabled() != enabled && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }
    override func setUp() {
        super.setUp()
        setBidiPreference(true)
        XCTAssertTrue(iTermPreferences.bidiEnabled(), "bidi preference cache did not update")
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

    // Note: the trailing-null trim in the bidi enumerate branch (matching the
    // non-bidi branch's `endx - numNulls` bound) is not unit-tested here because
    // content(in:) applies its own trailing-whitespace trim, which masks the
    // enumerate-level difference; the fix is a symmetric correction verified by
    // inspection.

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
    // whole word contiguously, «Berlin» must not come out as «B … شهری» (the
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

        // Select logical [0, 12): «متن Berlin ش»: covers متن plus the whole Berlin island.
        let range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 12, 0), 0, 0)
        let text = extractor.content(in: range, excludingSubranges: nil) ?? ""
        XCTAssertTrue(text.contains("Berlin"),
                      "English island was split by the copy; expected whole 'Berlin', got >>>\(text)<<<")
    }

    func testHebrewSentenceCopiesInOriginalLogicalOrder() {
        let content = "מה קורה חבר HELOO אתה בסדר?"
        let width = 40
        guard let (sca, _) = reorderedLine(content, width: width) else { return }
        let dataSource = BidiLinesDataSource([sca], width: Int32(width))
        let extractor = iTermTextExtractor(dataSource: dataSource)
        extractor.supportBidi = true

        let range = VT100GridWindowedRangeMake(
            VT100GridCoordRangeMake(0, 0, Int32(content.count), 0), 0, 0)
        let copied = extractor.content(in: range, excludingSubranges: nil) ?? ""
        XCTAssertEqual(copied, content)
    }

    func testLongHebrewSentenceWithFourLTRIslandsCopiesInOriginalLogicalOrder() {
        let content = "ראית ש iTerm2 הוסיפו תמיכה ב RTL ועכשיו אפשר לעבוד בצורה נוחה ונעימה, it's awesome, במיוחד עם README.md בעברית"
        let width = 160
        guard let (sca, _) = reorderedLine(content, width: width) else { return }
        let dataSource = BidiLinesDataSource([sca], width: Int32(width))
        let extractor = iTermTextExtractor(dataSource: dataSource)
        extractor.supportBidi = true

        let range = VT100GridWindowedRangeMake(
            VT100GridCoordRangeMake(0, 0, Int32((content as NSString).length), 0), 0, 0)
        let copied = extractor.content(in: range, excludingSubranges: nil) ?? ""
        XCTAssertEqual(copied, content)
    }

    func testArabicSentenceCopiesInOriginalLogicalOrder() {
        let content = "مرحبا يا صديقي, HELOO كيف حالك؟"
        let width = 40
        guard let (sca, _) = reorderedLine(content, width: width) else { return }
        let dataSource = BidiLinesDataSource([sca], width: Int32(width))
        let extractor = iTermTextExtractor(dataSource: dataSource)
        extractor.supportBidi = true

        let range = VT100GridWindowedRangeMake(
            VT100GridCoordRangeMake(0, 0, Int32(content.count), 0), 0, 0)
        let copied = extractor.content(in: range, excludingSubranges: nil) ?? ""
        XCTAssertEqual(copied, content)
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

// Maps visual columns to logical cells per screen row, the way PTYTextView
// does: through the row's reorder map, or identity for a row without one.
private final class ScreenRowsVisualDelegate: NSObject, iTermSelectionDelegate {
    let width: Int32
    let infos: [BidiDisplayInfoObjc?]
    init(width: Int32, infos: [BidiDisplayInfoObjc?]) { self.width = width; self.infos = infos }
    private func info(_ line: Int64) -> BidiDisplayInfoObjc? {
        (line >= 0 && line < Int64(infos.count)) ? infos[Int(line)] : nil
    }
    func selectionDidChange(_ selection: iTermSelection) {}
    func liveSelectionDidEnd() {}
    func selectionAbsRangeForParenthetical(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
    func selectionAbsRangeForWord(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
    func selectionAbsRangeForSmartSelection(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0) }
    func selectionAbsRangeForWrappedLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, absCoord.y, width, absCoord.y), 0, 0) }
    func selectionAbsRangeForLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, absCoord.y, width, absCoord.y), 0, 0) }
    // PTYTextView reports (width, 0) for a line that has bidi info.
    func selectionRangeOfTerminalNulls(onAbsoluteLine absLineNumber: Int64) -> VT100GridRange { VT100GridRangeMake(width, 0) }
    func selectionPredecessor(of absCoord: VT100GridAbsCoord) -> VT100GridAbsCoord { VT100GridAbsCoordMake(0, 0) }
    func selectionViewportWidth() -> Int32 { width }
    func selectionTotalScrollbackOverflow() -> Int64 { 0 }
    func selectionIndexes(onAbsoluteLine line: Int64, containingCharacter c: unichar, in range: NSRange) -> IndexSet? { IndexSet() }
    func selectionParagraphIsRTL(onAbsoluteLine line: Int64) -> Bool { info(line)?.paragraphIsRTL ?? false }
    func selectionLogicalIndexes(forVisualRange visualRange: NSRange, onAbsoluteLine line: Int64) -> IndexSet {
        guard let range = Range(visualRange) else { return IndexSet() }
        guard let bidi = info(line) else { return IndexSet(integersIn: range) }
        var result = IndexSet()
        for v in range {
            if v < Int(bidi.numberOfCells) { result.insert(Int(bidi.logicalForVisual(Int32(v)))) }
            else { result.insert(v) }
        }
        return result
    }
}

extension BidiCopyLogicalRangeTests {
    // Writes `lines` to a real screen (hard newline between them; a line wider
    // than the screen soft-wraps), drags from visual column v1 on row r1 to
    // visual column v2 on row r2, and copies the result through the real
    // SelectionExtractor with the default “trim whitespace on copy” option.
    // The column closures receive the row's reorder map (nil for a row that
    // has none).
    private func copyVisualDragOnScreen(lines: [String],
                                        width: Int32,
                                        options: iTermSelectionExtractorOptions = [.trimWhitespace],
                                        from r1: Int64, _ v1: (BidiDisplayInfoObjc?) -> Int32,
                                        to r2: Int64, _ v2: (BidiDisplayInfoObjc?) -> Int32,
                                        file: StaticString = #filePath,
                                        line: UInt = #line) -> String? {
        let session = FakeSession()
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        var copied: String?
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(width, height: 6, mutableState: mutableState)
            for (i, text) in lines.enumerated() {
                if i > 0 {
                    mutableState.appendCarriageReturnLineFeed()
                }
                mutableState.appendString(atCursor: text)
            }
            mutableState.populateRTLStateIfNeeded()
            let snapshot = TerminalContentSnapshot(lineBuffer: mutableState.linebuffer,
                                                   grid: mutableState.currentGrid,
                                                   cumulativeOverflow: mutableState.cumulativeScrollbackOverflow)
            let infos = (0..<6).map { snapshot.screenCharArray(forLine: Int32($0)).bidiInfo }
            guard infos[Int(r2)] != nil else {
                XCTFail("row \(r2) has no bidi info", file: file, line: line)
                return
            }
            let delegate = ScreenRowsVisualDelegate(width: width, infos: infos)
            let selection = iTermSelection()
            selection.delegate = delegate
            selection.begin(at: VT100GridAbsCoordMake(v1(infos[Int(r1)]), r1),
                            mode: .kiTermSelectionModeCharacter,
                            resume: false, append: false)
            selection.moveEndpoint(to: VT100GridAbsCoordMake(v2(infos[Int(r2)]), r2))
            selection.endLive()
            guard let extractor = StringSelectionExtractor(selection: selection,
                                                           snapshot: snapshot,
                                                           options: options,
                                                           maxBytes: -1,
                                                           minimumLineNumber: 0) else {
                XCTFail("no extractor", file: file, line: line)
                return
            }
            copied = extractor.extract() as String
        })
        withExtendedLifetime(session) {}
        return copied
    }

    // Single-row form: drags [v1, v2) on row 0 holding `content`.
    private func copyVisualDragOnScreen(_ content: String,
                                        width: Int32,
                                        fromVisual v1: @escaping (BidiDisplayInfoObjc) -> Int32,
                                        toVisual v2: @escaping (BidiDisplayInfoObjc) -> Int32,
                                        file: StaticString = #filePath,
                                        line: UInt = #line) -> String? {
        return copyVisualDragOnScreen(lines: [content], width: width,
                                      from: 0, { $0.map(v1) ?? 0 },
                                      to: 0, { $0.map(v2) ?? 0 },
                                      file: file, line: line)
    }


    // QA finding F-321. In the LTR paragraph «L4 שלום עולם טוב end4» (drawn
    // «L4 טוב עולם שלום end4») a drag from the left edge to just past ם, the
    // leftmost glyph of the rightmost Hebrew word, selects «L4 » plus the
    // logical tail «ם עולם טוב». The sweep is copied as two logical pieces;
    // the first ends with the space after «L4», which is inside the selection
    // and must not be trimmed.
    func testPartialDragAcrossLTRToRTLBoundaryKeepsBoundarySpace() {
        let content = "L4 שלום עולם טוב end4"
        // Logical 6 is ם, the last letter of שלום.
        let copied = copyVisualDragOnScreen(content, width: 40,
                                            fromVisual: { _ in 0 },
                                            toVisual: { $0.visualForLogical(6) + 1 })
        XCTAssertEqual(copied, "L4 ם עולם טוב")
    }

    // The same sweep dragged right-to-left (anchor past ם, pointer at the left
    // edge) copies the same text.
    func testReversePartialDragAcrossLTRToRTLBoundaryKeepsBoundarySpace() {
        let content = "L4 שלום עולם טוב end4"
        let copied = copyVisualDragOnScreen(content, width: 40,
                                            fromVisual: { $0.visualForLogical(6) + 1 },
                                            toVisual: { _ in 0 })
        XCTAssertEqual(copied, "L4 ם עולם טוב")
    }

    // Trailing whitespace at the true end of the selection is still trimmed:
    // sweeping «L4 » alone (no RTL piece follows) copies «L4».
    func testTrailingSpaceAtEndOfSelectionIsStillTrimmed() {
        let content = "L4 שלום עולם טוב end4"
        let copied = copyVisualDragOnScreen(content, width: 40,
                                            fromVisual: { _ in 0 },
                                            toVisual: { _ in 3 })
        XCTAssertEqual(copied, "L4")
    }

    // A sweep that ends on the space before «end4» copies the whole Hebrew run;
    // that space ends the last piece on the line, so it is trimmed.
    func testSweepEndingOnSpaceAfterRTLRunTrimsIt() {
        let content = "L4 שלום עולם טוב end4"
        let copied = copyVisualDragOnScreen(content, width: 40,
                                            fromVisual: { _ in 0 },
                                            toVisual: { $0.visualForLogical(16) + 1 })
        XCTAssertEqual(copied, "L4 שלום עולם טוב")
    }

    // A multi-line drag that ends on the split row still trims trailing
    // whitespace before each hard newline; only the whitespace inside the
    // last row's selection is kept.
    func testMultilineDragEndingOnSplitRowStillTrimsEarlierLines() {
        let copied = copyVisualDragOnScreen(lines: ["hello   ", "L4 שלום עולם טוב end4"],
                                            width: 40,
                                            from: 0, { _ in 0 },
                                            to: 1, { $0!.visualForLogical(6) + 1 })
        XCTAssertEqual(copied, "hello\nL4 ם עולם טוב")
    }

    // The same with no trimming option keeps everything that was selected.
    func testMultilineDragWithoutTrimKeepsWhitespace() {
        let copied = copyVisualDragOnScreen(lines: ["hello   ", "L4 שלום עולם טוב end4"],
                                            width: 40,
                                            options: [],
                                            from: 0, { _ in 0 },
                                            to: 1, { $0!.visualForLogical(6) + 1 })
        XCTAssertEqual(copied, "hello   \nL4 ם עולם טוב")
    }
}
