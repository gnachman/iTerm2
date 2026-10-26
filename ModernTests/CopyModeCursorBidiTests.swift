//
//  CopyModeCursorBidiTests.swift
//  ModernTests
//
//  The copy mode cursor coordinate is logical (copy mode moves and selects in
//  logical space). It must be drawn where its character is drawn. On a
//  reordered right-to-left line it was drawn at the logical column, so after
//  `0` it sat in the blank area at the far left. QA finding F-082.
//

import XCTest
@testable import iTerm2SharedARC

// Implements only what visualCopyModeCursorCoord uses. Installed through KVC
// because the full delegate protocol is large and unrelated to this test.
private final class BidiOnlyDrawingDelegate: NSObject {
    let bidiByLine: [Int32: BidiDisplayInfoObjc]
    init(_ bidiByLine: [Int32: BidiDisplayInfoObjc]) { self.bidiByLine = bidiByLine }
    @objc(drawingHelperBidiInfoForLine:)
    func bidiInfo(forLine line: Int32) -> BidiDisplayInfoObjc? { bidiByLine[line] }
}

class CopyModeCursorBidiTests: XCTestCase {
    private var savedDetect: Any?

    override func setUp() {
        super.setUp()
        savedDetect = iTermUserDefaults.userDefaults().object(forKey: "DetectParagraphDirection")
        iTermUserDefaults.userDefaults().set(true, forKey: "DetectParagraphDirection")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
    }

    override func tearDown() {
        if let v = savedDetect { iTermUserDefaults.userDefaults().set(v, forKey: "DetectParagraphDirection") }
        else { iTermUserDefaults.userDefaults().removeObject(forKey: "DetectParagraphDirection") }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        super.tearDown()
    }

    func testCopyModeCursorIsDrawnOnItsCharacterOnRTLLine() {
        let width = 30
        let content = "سلام دنیا"
        let padded = content + String(repeating: " ", count: width - content.count)
        guard let bidi = BidiDisplayInfoObjc(screenCharArrayWithDefaultStyle(padded, eol: EOL_HARD)) else {
            return XCTFail("no bidi")
        }
        XCTAssertNotEqual(bidi.visualForLogical(0), 0, "line not reordered; test is meaningless")

        let scrollback: Int32 = 5
        let screenLine: Int32 = 2
        let delegate = BidiOnlyDrawingDelegate([scrollback + screenLine: bidi])
        let helper = iTermTextDrawingHelper()
        helper.setValue(delegate, forKey: "delegate")
        helper.gridSize = VT100GridSizeMake(Int32(width), 10)
        helper.numberOfScrollbackLines = scrollback

        for logicalX: Int32 in [0, 3, 5] {
            helper.copyModeCursorCoord = VT100GridCoordMake(logicalX, scrollback + screenLine)
            let visual = helper.visualCopyModeCursorCoord()
            XCTAssertEqual(visual.y, scrollback + screenLine)
            XCTAssertEqual(visual.x, bidi.visualForLogical(logicalX), "logical column \(logicalX)")
        }
        helper.setValue(nil, forKey: "delegate")
        withExtendedLifetime(delegate) {}
    }

    func testCopyModeCursorUnchangedOnLTRLine() {
        let delegate = BidiOnlyDrawingDelegate([:])
        let helper = iTermTextDrawingHelper()
        helper.setValue(delegate, forKey: "delegate")
        helper.gridSize = VT100GridSizeMake(30, 10)
        helper.numberOfScrollbackLines = 5
        helper.copyModeCursorCoord = VT100GridCoordMake(4, 7)
        let visual = helper.visualCopyModeCursorCoord()
        XCTAssertEqual(visual.x, 4)
        XCTAssertEqual(visual.y, 7)
        helper.setValue(nil, forKey: "delegate")
        withExtendedLifetime(delegate) {}
    }
}
