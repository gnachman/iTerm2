//
//  BidiURLDividerTests.swift
//  ModernTests
//
//  URL detection under the pointer restricts its search to the pane between
//  column dividers (a non-integration tmux split, for example). Divider columns
//  are logical, so the window must be chosen with the logical coordinate. It
//  used the visual one, so on a reordered right-to-left row the window was the
//  pane on the other side of the divider and the URL was not found.
//  QA finding F-076.
//

import XCTest
@testable import iTerm2SharedARC

private final class DividerLinesDataSource: NSObject, iTermTextDataSource {
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

// Implements only what urlForCopyAtCoord: uses. Installed through KVC because
// the full delegate protocol is large and unrelated to this test.
private final class MinimalURLActionHelperDelegate: NSObject {
    let dataSource: DividerLinesDataSource
    init(_ dataSource: DividerLinesDataSource) { self.dataSource = dataSource }
    @objc(urlActionHelperNewTextExtractor:)
    func newTextExtractor(_ helper: iTermURLActionHelper) -> iTermTextExtractor {
        return iTermTextExtractor(dataSource: dataSource)
    }
    @objc(urlActionHelperShouldIgnoreHardNewlines:)
    func shouldIgnoreHardNewlines(_ helper: iTermURLActionHelper) -> Bool { false }
}

class BidiURLDividerTests: XCTestCase {
    private var savedDetect: Any?

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
        XCTAssertTrue(iTermPreferences.bidiEnabled())
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

    private func pad(_ s: String, _ n: Int) -> String {
        s + String(repeating: " ", count: max(0, n - s.count))
    }

    func testURLRightOfDividerOnReorderedRowIsFound() {
        let width = 50
        let leftWidth = 15
        let rightWidth = width - leftWidth - 1
        let url = "https://example.com/abc1"
        var scas = [ScreenCharArray]()
        for i in 0..<10 {
            let row: String
            if i == 4 {
                // RTL text padded to the divider in the left pane; the URL is in
                // the right pane.
                row = String(repeating: " ", count: leftWidth - 4) + "سلام" + "│" + pad(url, rightWidth)
            } else {
                row = pad("left \(i)", leftWidth) + "│" + pad("right \(i)", rightWidth)
            }
            XCTAssertEqual(row.count, width)
            let base = screenCharArrayWithDefaultStyle(row, eol: EOL_HARD)
            if let bidi = BidiDisplayInfoObjc(base) {
                scas.append(ScreenCharArray(copyOfLine: base.line, length: base.length,
                                            continuation: base.continuation, bidiInfo: bidi))
            } else {
                scas.append(base)
            }
        }
        guard let bidi = scas[4].bidiInfo else { return XCTFail("row 4 is not reordered") }
        // Pick a URL cell that is drawn left of the divider even though it is
        // logically right of it.
        let urlStart = leftWidth + 1
        guard let logicalX = (urlStart..<(urlStart + url.count)).first(where: {
            bidi.visualForLogical(Int32($0)) < Int32(leftWidth)
        }) else {
            return XCTFail("no URL cell drawn left of the divider; test is meaningless")
        }
        let visualCoord = VT100GridCoordMake(bidi.visualForLogical(Int32(logicalX)), 4)

        let dataSource = DividerLinesDataSource(scas, width: Int32(width))
        let delegate = MinimalURLActionHelperDelegate(dataSource)
        let helper = iTermURLActionHelper(semanticHistoryController: iTermSemanticHistoryController())
        helper.setValue(delegate, forKey: "delegate")

        let found = helper.urlForCopy(at: visualCoord)
        XCTAssertEqual(found?.absoluteString, url)
        withExtendedLifetime(delegate) {}
    }

    // Cmd-hover only underlines a URL whose visual range contains the pointer.
    // The visual range kept the logical column window, so on a reordered row
    // where the URL is logically right of the divider but drawn left of it,
    // the pointer was never "in" the URL. QA finding F-456.
    func testVisualRangeOfURLDrawnAcrossDividerContainsItsCells() {
        let width = 60
        let leftWidth = 20
        let rightWidth = width - leftWidth - 1
        let url = "https://example.com/abc1"
        let rightText = "دنیا " + url + " سلام"
        var scas = [ScreenCharArray]()
        for i in 0..<10 {
            let row: String
            if i == 4 {
                // The QA rows: RTL text touching the divider on the left and an
                // RTL-led line containing a URL on the right.
                row = String(repeating: " ", count: leftWidth - 9) + "سلام دنیا" + "│" + pad(rightText, rightWidth)
            } else {
                row = pad("left \(i)", leftWidth) + "│" + pad("right \(i)", rightWidth)
            }
            XCTAssertEqual(row.count, width)
            let base = screenCharArrayWithDefaultStyle(row, eol: EOL_HARD)
            if let bidi = BidiDisplayInfoObjc(base) {
                scas.append(ScreenCharArray(copyOfLine: base.line, length: base.length,
                                            continuation: base.continuation, bidiInfo: bidi))
            } else {
                scas.append(base)
            }
        }
        guard let bidi = scas[4].bidiInfo else { return XCTFail("row 4 is not reordered") }
        let urlStart = leftWidth + 1 + 5
        let urlCells = urlStart..<(urlStart + url.count)
        let outside = urlCells.filter { bidi.visualForLogical(Int32($0)) <= Int32(leftWidth) }
        XCTAssertFalse(outside.isEmpty, "no URL cell drawn outside the right pane; test is meaningless")

        // The extractor holds its data source weakly.
        let dataSource = DividerLinesDataSource(scas, width: Int32(width))
        let extractor = iTermTextExtractor(dataSource: dataSource)
        extractor.supportBidi = true
        extractor.restrictToLogicalWindow(including: VT100GridCoordMake(Int32(urlStart), 4))
        XCTAssertEqual(extractor.logicalWindow.location, Int32(leftWidth + 1))
        let logical = VT100GridWindowedRangeMake(
            VT100GridCoordRangeMake(Int32(urlStart), 4, Int32(urlCells.upperBound), 4),
            extractor.logicalWindow.location,
            extractor.logicalWindow.length)
        let visual = extractor.visualWindowedRange(forLogical: logical)
        for x in urlCells {
            let visualCoord = VT100GridCoordMake(bidi.visualForLogical(Int32(x)), 4)
            XCTAssertTrue(VT100GridWindowedRangeContainsCoord(visual, visualCoord),
                          "URL cell at logical x=\(x), visual x=\(visualCoord.x) not in \(VT100GridWindowedRangeDescription(visual) ?? "")")
        }
        withExtendedLifetime(dataSource) {}
    }

    // A URL ending in right-to-left text is not drawn in one run: its logical
    // first and last cells are not its visual left and right edges. The
    // visual range was built from those two endpoints only, so it missed the
    // middle of the URL, and Cmd-hover there kept the previous URL
    // underlined. QA finding F-427.
    func testVisualRangeOfURLEndingInRTLTextContainsAllItsCells() {
        let width = 40
        let url = "https://example.com/پ"
        let row = pad("سلام " + url + " دنیا", width)
        let base = screenCharArrayWithDefaultStyle(row, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(base) else { return XCTFail("row is not reordered") }
        let sca = ScreenCharArray(copyOfLine: base.line, length: base.length,
                                  continuation: base.continuation, bidiInfo: bidi)
        let dataSource = DividerLinesDataSource([sca], width: Int32(width))
        let extractor = iTermTextExtractor(dataSource: dataSource)
        extractor.supportBidi = true
        let urlStart = 5
        let urlCells = urlStart..<(urlStart + url.count)
        extractor.restrictToLogicalWindow(including: VT100GridCoordMake(Int32(urlStart), 0))
        let logical = VT100GridWindowedRangeMake(
            VT100GridCoordRangeMake(Int32(urlStart), 0, Int32(urlCells.upperBound), 0),
            extractor.logicalWindow.location,
            extractor.logicalWindow.length)
        let visual = extractor.visualWindowedRange(forLogical: logical)
        for x in urlCells {
            let visualCoord = VT100GridCoordMake(bidi.visualForLogical(Int32(x)), 0)
            XCTAssertTrue(VT100GridWindowedRangeContainsCoord(visual, visualCoord),
                          "URL cell at logical x=\(x), visual x=\(visualCoord.x) not in \(VT100GridWindowedRangeDescription(visual) ?? "")")
        }
        withExtendedLifetime(dataSource) {}
    }
}
