//
//  BidiMouseReportTests.swift
//  ModernTests
//
//  A program that tracks the mouse knows only the cells it wrote. On a
//  bidi-reordered line a mouse report must name the cell that is drawn under the
//  mouse, not the column the mouse is in, or the program acts on the wrong text.
//

import XCTest
@testable import iTerm2SharedARC

private class MouseReportFakeSession: FakeSession {
    private let syncConfig: VT100MutableScreenConfiguration = {
        let c = VT100MutableScreenConfiguration()
        c.sessionGuid = "BidiMouseReportTests"
        return c
    }()
    override func screenRestore(_ state: VT100ScreenState) { screen?.restore(state) }
    override func screenUpdateDisplay(_ redraw: Bool) {
        guard let screen else { return }
        _ = screen.synchronize(withConfig: syncConfig, expect: nil, checkTriggers: .none,
                               resetOverflow: false, mutableState: screen.mutableState)
    }
}

class BidiMouseReportTests: XCTestCase {
    private var session = MouseReportFakeSession()
    private var savedDetect: Any?
    private let width: Int32 = 20

    private func setBidi(_ on: Bool) {
        iTermPreferences.setBool(on, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while iTermPreferences.bidiEnabled() != on && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

    override func setUp() {
        super.setUp()
        setBidi(true)
        savedDetect = iTermUserDefaults.userDefaults().object(forKey: "DetectParagraphDirection")
        iTermUserDefaults.userDefaults().set(true, forKey: "DetectParagraphDirection")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
    }

    override func tearDown() {
        if let savedDetect {
            iTermUserDefaults.userDefaults().set(savedDetect, forKey: "DetectParagraphDirection")
        } else {
            iTermUserDefaults.userDefaults().removeObject(forKey: "DetectParagraphDirection")
        }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        setBidi(false)
        super.tearDown()
    }

    // A text view over a 20x3 screen showing the given lines. More than three
    // lines push the first ones into scrollback.
    private func makeTextView(lines: [String]) -> PTYTextView {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, m, _ in
            m.terminalEnabled = true
            m.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(self.width, height: 3, mutableState: m)
            for (i, line) in lines.enumerated() {
                if i > 0 {
                    m.appendCarriageReturnLineFeed()
                }
                m.appendString(atCursor: line)
            }
            m.populateRTLStateIfNeeded()
        })
        let textView = PTYTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))!
        textView.dataSource = screen
        return textView
    }

    private func reported(_ textView: PTYTextView, x: Int32, y: Int32) -> VT100GridCoord {
        return textView.mouseReportCoord(forVisualCoord: VT100GridCoord(x: x, y: y))
    }

    // «سلام دنیا» is nine cells. Right-justified in 20 columns it is drawn in
    // columns 19 down to 11, so the mouse over column 19 is over its first letter.
    func testRightJustifiedLineReportsTheCellUnderTheMouse() {
        let textView = makeTextView(lines: ["سلام دنیا"])
        XCTAssertNotNil((textView.dataSource as? VT100Screen)?.bidiInfo(forLine: 0), "probe: the line is reordered")
        XCTAssertEqual(reported(textView, x: 19, y: 0).x, 0, "the right edge is the first letter")
        XCTAssertEqual(reported(textView, x: 11, y: 0).x, 8, "the left end of the text is the last letter")
        XCTAssertGreaterThanOrEqual(reported(textView, x: 0, y: 0).x, 9, "the empty left side is past the text")
        XCTAssertEqual(reported(textView, x: 19, y: 0).y, 0, "the row is unchanged")
    }

    func testLeftToRightLineIsUnchanged() {
        let textView = makeTextView(lines: ["hello world", "سلام دنیا"])
        XCTAssertEqual(reported(textView, x: 3, y: 0).x, 3)
        XCTAssertEqual(reported(textView, x: 19, y: 0).x, 19)
        XCTAssertEqual(reported(textView, x: 19, y: 1).x, 0, "probe: the next row is reordered")
    }

    // The mouse coordinate counts rows of the live screen, not lines of history.
    func testRowIsRelativeToTheLiveScreen() {
        let textView = makeTextView(lines: ["one", "two", "three", "سلام دنیا"])
        XCTAssertEqual((textView.dataSource as? VT100Screen)?.numberOfScrollbackLines(), 1, "probe: one line scrolled off")
        XCTAssertEqual(reported(textView, x: 19, y: 2).x, 0, "live row 2 holds the Persian line")
        XCTAssertEqual(reported(textView, x: 19, y: 1).x, 19, "live row 1 holds “three”")
    }
}
