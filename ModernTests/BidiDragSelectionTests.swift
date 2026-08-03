//
//  BidiDragSelectionTests.swift
//  ModernTests
//
//  A drag selects VISUAL columns; the mouse handler converts each endpoint to a
//  LOGICAL cell (logicalForVisual), stores the inclusive logical range, and the
//  highlight draws each selected logical cell at its visual column. On a right-
//  justified RTL line (content pushed right by trailing spaces that reorder to
//  the visual left) the highlight must cover the same visual columns the user
//  dragged over — not empty space on the far left.
//

import XCTest
@testable import iTerm2SharedARC

// One bidi line, exposed to iTermTextExtractor so its visual→logical conversion
// (the exact call the mouse handler makes on mouse-down and drag) can be tested.
private class OneBidiLineDataSource: NSObject, iTermTextDataSource {
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

class BidiDragSelectionTests: XCTestCase {
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
        // Match the real app: paragraph direction auto-detected, so a first-strong
        // RTL line becomes an RTL paragraph and its content is pushed to the right
        // while trailing spaces reorder to the visual left.
        savedDetect = iTermUserDefaults.userDefaults().object(forKey: "DetectParagraphDirection")
        savedIsolate = iTermUserDefaults.userDefaults().object(forKey: "IsolateLatinRunsInRTL")
        iTermUserDefaults.userDefaults().set(true, forKey: "DetectParagraphDirection")
        iTermUserDefaults.userDefaults().set(true, forKey: "IsolateLatinRunsInRTL")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
    }
    private var savedIsolate: Any?
    override func tearDown() {
        if let v = savedDetect { iTermUserDefaults.userDefaults().set(v, forKey: "DetectParagraphDirection") }
        else { iTermUserDefaults.userDefaults().removeObject(forKey: "DetectParagraphDirection") }
        if let v = savedIsolate { iTermUserDefaults.userDefaults().set(v, forKey: "IsolateLatinRunsInRTL") }
        else { iTermUserDefaults.userDefaults().removeObject(forKey: "IsolateLatinRunsInRTL") }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        setBidiPreference(false)
        super.tearDown()
    }

    // Simulate the mouse path: drag visual [v1,v2] -> logical endpoints via
    // logicalForVisual -> inclusive logical range -> highlight -> visual cells lit.
    private func highlightedVisualsForDrag(_ bidi: BidiDisplayInfoObjc,
                                           sca: ScreenCharArray,
                                           v1: Int, v2: Int) -> Set<Int> {
        let l1 = Int(bidi.logicalForVisual(Int32(v1)))
        let l2 = Int(bidi.logicalForVisual(Int32(v2)))
        var selected = IndexSet()
        selected.insert(integersIn: min(l1, l2)..<(max(l1, l2) + 1))
        let width = Int(sca.length)
        var anyBlink: ObjCBool = false
        guard let runs = iTermBackgroundColorRunsInLine.backgroundRuns(
            inLine: sca.line, lineLength: Int32(width), sourceLineNumber: 0, displayLineNumber: 0,
            selectedIndexes: selected, within: NSRange(location: 0, length: width),
            matches: nil, anyBlink: &anyBlink, y: 0, bidi: bidi, eaIndex: nil, darkMode: false) else {
            return []
        }
        var highlighted = Set<Int>()
        for boxed in runs.array where boxed.valuePointer.pointee.selected.boolValue {
            let r = boxed.valuePointer.pointee.visualRange
            for v in r.location..<(r.location + r.length) { highlighted.insert(v) }
        }
        return highlighted
    }

    private func dumpMapping(_ label: String, _ bidi: BidiDisplayInfoObjc, _ n: Int) {
        var lines = ["=== \(label) (numberOfCells=\(bidi.numberOfCells), inverseCount=\(bidi.inverseLUTCount)) ==="]
        for logical in 0..<n {
            lines.append("logical \(logical) -> visual \(bidi.visualForLogical(Int32(logical)))")
        }
        print(lines.joined(separator: "\n"))
    }

    // Pure RTL with trailing spaces: content reorders to the right, spaces to the
    // left. Dragging over the content's visual columns must highlight exactly
    // those columns.
    func testRightJustifiedDragHighlightsDraggedColumns() {
        let content = "سلام دنیا"            // 9 cells, all RTL/neutral
        let s = content + "           "       // pad to 20 with trailing spaces
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(sca) else { return XCTFail("no bidi info") }
        let width = Int(sca.length)
        dumpMapping("right-justified", bidi, width)

        // Find the visual span the CONTENT occupies (logical 0..<9).
        let contentVisuals = (0..<9).map { Int(bidi.visualForLogical(Int32($0))) }
        let vMin = contentVisuals.min()!, vMax = contentVisuals.max()!
        print("content occupies visual [\(vMin)...\(vMax)]; dragging that span")

        // Drag over the full content visual span.
        let lit = highlightedVisualsForDrag(bidi, sca: sca, v1: vMin, v2: vMax)
        print("dragged visual [\(vMin)...\(vMax)] -> lit \(lit.sorted())")

        // Every dragged visual column that holds content must be lit, and no
        // far-left empty column outside the dragged span may be lit.
        for v in vMin...vMax {
            XCTAssertTrue(lit.contains(v), "content visual column \(v) was dragged but not highlighted")
        }
        for v in lit {
            XCTAssertTrue(v >= vMin && v <= vMax, "column \(v) lit but is outside the dragged span [\(vMin)...\(vMax)]")
        }
    }

    // Drag over only PART of the content (a couple of words), not the whole span.
    func testPartialContentDragHighlightsOnlyDraggedColumns() {
        let content = "سلام دنیا خوب"        // 12 cells
        let s = content + "        "           // pad to 20
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(sca) else { return XCTFail("no bidi info") }
        // Drag a visual sub-span in the middle of the content.
        let contentVisuals = (0..<12).map { Int(bidi.visualForLogical(Int32($0))) }
        let vMax = contentVisuals.max()!
        let v1 = vMax - 5, v2 = vMax - 1        // five columns inside the content
        let lit = highlightedVisualsForDrag(bidi, sca: sca, v1: v1, v2: v2)
        print("partial drag visual [\(v1)...\(v2)] -> lit \(lit.sorted())")
        XCTAssertEqual(lit, Set(min(v1, v2)...max(v1, v2)),
                       "partial drag over [\(v1)...\(v2)] should light exactly those columns, got \(lit.sorted())")
    }

    // The user's screenshot line: an English island inside an RTL sentence. Drag
    // over the visual columns and confirm the highlight covers exactly them, so a
    // drag over the words never lands on empty space or mirror columns.
    func testMixedIslandDragHighlightsDraggedColumns() {
        let content = "Berlin شهری بزرگ در آلمان"
        let s = content + "      "
        let ns = content as NSString
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(sca) else { return XCTFail("no bidi info") }
        let width = Int(sca.length)
        dumpMapping("mixed island", bidi, width)

        // Drag over the Persian tail «شهری بزرگ در آلمان» (everything after Berlin).
        let faStart = ns.range(of: "شهری").location
        let faVisuals = (faStart..<content.count).map { Int(bidi.visualForLogical(Int32($0))) }
        let vMin = faVisuals.min()!, vMax = faVisuals.max()!
        let lit = highlightedVisualsForDrag(bidi, sca: sca, v1: vMin, v2: vMax)
        print("mixed drag visual [\(vMin)...\(vMax)] -> lit \(lit.sorted())")
        // Contiguous visual drag must light a contiguous visual block == the drag.
        XCTAssertEqual(lit, Set(vMin...vMax),
                       "mixed-line drag over [\(vMin)...\(vMax)] should light exactly those columns, got \(lit.sorted())")
    }

    // Close the loop with the REAL conversion the mouse handler runs. The drag
    // tests above simulate the endpoint conversion with bidi.logicalForVisual;
    // this proves iTermTextExtractor.logicalCoordForVisualCoord: (what
    // PTYMouseHandler/PTYTextView actually call) returns exactly that for every
    // visual column of the mixed island line — so the simulation is faithful and
    // the fetched line/coord are right (no off-by-one, no wrong line).
    func testExtractorConversionMatchesBidiLogicalForVisual() {
        let content = "Berlin شهری بزرگ در آلمان"
        let s = content + "      "
        let base = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(base) else { return XCTFail("no bidi info") }
        // Rebuild the line carrying the bidi info, so the extractor's fetch sees it.
        let sca = ScreenCharArray(copyOfLine: base.line, length: base.length,
                                  continuation: base.continuation, bidiInfo: bidi)
        let width = Int(sca.length)
        let ds = OneBidiLineDataSource(sca, width: Int32(width))
        let extractor = iTermTextExtractor(dataSource: ds)
        extractor.supportBidi = true

        for v in 0..<width {
            let got = extractor.logicalCoord(forVisualCoord: VT100GridCoord(x: Int32(v), y: 0))
            let want = bidi.logicalForVisual(Int32(v))
            XCTAssertEqual(got.x, want, "extractor visual \(v) -> logical \(got.x), expected \(want)")
            XCTAssertEqual(got.y, 0)
        }
    }
}
