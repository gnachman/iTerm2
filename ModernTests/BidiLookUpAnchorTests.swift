//
//  BidiLookUpAnchorTests.swift
//  ModernTests
//
//  Look Up (Ctrl-Cmd-D) finds the word in logical coordinates. Its yellow
//  highlight and popover must be anchored where the word is drawn. On a
//  reordered right-to-left line that is not the word's logical column.
//  QA finding F-320.
//

import XCTest
@testable import iTerm2SharedARC

private final class LookUpLinesDataSource: NSObject, iTermTextDataSource {
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

class BidiLookUpAnchorTests: XCTestCase {
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

    func testAnchorIsLeftmostDrawnCellOfRTLWord() {
        let width = 30
        let content = "שלום עולם טוב"
        let padded = content + String(repeating: " ", count: width - content.count)
        let base = screenCharArrayWithDefaultStyle(padded, eol: EOL_HARD)
        guard let bidi = BidiDisplayInfoObjc(base) else { return XCTFail("no bidi") }
        let sca = ScreenCharArray(copyOfLine: base.line, length: base.length,
                                  continuation: base.continuation, bidiInfo: bidi)
        let dataSource = LookUpLinesDataSource([sca], width: Int32(width))

        // עולם occupies logical cells [5, 9).
        let logical = VT100GridCoordRangeMake(5, 0, 9, 0)
        let expectedX = (5..<9).map { bidi.visualForLogical(Int32($0)) }.min()!
        XCTAssertNotEqual(expectedX, 5, "line not reordered; test is meaningless")

        let anchor = PTYTextView.lookUpAnchor(forLogicalWordRange: logical, dataSource: dataSource)
        XCTAssertEqual(anchor.y, 0)
        XCTAssertEqual(anchor.x, expectedX)
    }

    func testAnchorIsLogicalStartOnLTRLine() {
        let width = 20
        let base = screenCharArrayWithDefaultStyle("hello world" + String(repeating: " ", count: 9), eol: EOL_HARD)
        let dataSource = LookUpLinesDataSource([base], width: Int32(width))
        let anchor = PTYTextView.lookUpAnchor(forLogicalWordRange: VT100GridCoordRangeMake(6, 0, 11, 0),
                                              dataSource: dataSource)
        XCTAssertEqual(anchor.x, 6)
        XCTAssertEqual(anchor.y, 0)
    }
}
