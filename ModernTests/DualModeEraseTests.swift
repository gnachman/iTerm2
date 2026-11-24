//
//  DualModeEraseTests.swift
//  iTerm2
//
//  Cells cleared with the current background (EL, ED, ECH, DECSEL, ICH, DCH,
//  scrolling) must carry the dual-mode light/dark pair set by SGR 48:12, or
//  they render with the light variant in dark mode. Issue 13231.
//

import XCTest
@testable import iTerm2SharedARC

final class DualModeEraseTests: XCTestCase {
    private var session = FakeSession()

    private let width: Int32 = 10
    private let height: Int32 = 4

    // Light red, dark green.
    private let setDualBackground = "\u{1b}[48:12:200:0:0:0:200:0m"

    private func makeScreen() -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(self.width, height: self.height, mutableState: mutableState)
        })
        return screen
    }

    private func feed(_ screen: VT100Screen, _ string: String) {
        screen.inject(string.data(using: .utf8)!)
        screen.waitForQueuedTokensForTesting()
    }

    private func gridLine(_ screen: VT100Screen, _ y: Int32) -> ScreenCharArray {
        return screen.screenCharArray(forLine: screen.numberOfLines() - screen.height() + y)
    }

    private func assertDualBackground(_ screen: VT100Screen,
                                      y: Int32,
                                      xs: ClosedRange<Int32>,
                                      file: StaticString = #filePath,
                                      line: UInt = #line) {
        let sca = gridLine(screen, y)
        for x in xs {
            let c = sca.line[Int(x)]
            XCTAssertEqual(c.backgroundColorMode, ColorModeExternal.rawValue,
                           "cell (\(x), \(y)) should be dual-mode", file: file, line: line)
            guard let ea = sca.eaIndex?.attribute(at: Int32(x)) else {
                XCTFail("cell (\(x), \(y)) has no external attribute", file: file, line: line)
                continue
            }
            let dual = ea.dualModeBackground
            XCTAssertTrue(dual.valid.boolValue, "cell (\(x), \(y)) dual bg invalid", file: file, line: line)
            XCTAssertEqual(dual.light.red, 200, file: file, line: line)
            XCTAssertEqual(dual.light.green, 0, file: file, line: line)
            XCTAssertEqual(dual.light.blue, 0, file: file, line: line)
            XCTAssertEqual(dual.dark.red, 0, file: file, line: line)
            XCTAssertEqual(dual.dark.green, 200, file: file, line: line)
            XCTAssertEqual(dual.dark.blue, 0, file: file, line: line)
            XCTAssertNil(ea.url, file: file, line: line)
            XCTAssertNil(ea.blockIDList, file: file, line: line)
        }
    }

    // MARK: - The reported bug

    func testELToEndOfLineCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, setDualBackground + "ab\u{1b}[K")
        assertDualBackground(screen, y: 0, xs: 0...(width - 1))
    }

    func testELWholeLineCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "abcdef" + setDualBackground + "\u{1b}[2K")
        assertDualBackground(screen, y: 0, xs: 0...(width - 1))
    }

    func testELToStartOfLineCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "abcdef\u{1b}[4G" + setDualBackground + "\u{1b}[1K")
        assertDualBackground(screen, y: 0, xs: 0...3)
    }

    func testDECSELCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "abcdef\u{1b}[3G" + setDualBackground + "\u{1b}[?K")
        assertDualBackground(screen, y: 0, xs: 2...(width - 1))
    }

    func testELInISOProtectedModeCarriesDualBackground() {
        let screen = makeScreen()
        // ESC V starts ISO protected mode, which routes EL through selective erase.
        feed(screen, "abcdef\u{1b}V\u{1b}W\u{1b}[3G" + setDualBackground + "\u{1b}[K")
        assertDualBackground(screen, y: 0, xs: 2...(width - 1))
    }

    func testEDInISOProtectedModeCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "abc\u{1b}V\u{1b}W\u{1b}[1;1H" + setDualBackground + "\u{1b}[J")
        for y in 0..<height {
            assertDualBackground(screen, y: y, xs: 0...(width - 1))
        }
    }

    // MARK: - Protected-mode erase covers the whole requested range

    private func lineString(_ screen: VT100Screen, _ y: Int32) -> String {
        let sca = gridLine(screen, y)
        return (0..<Int(width)).map { x -> String in
            let code = sca.line[x].code
            return code == 0 || code == 32 ? "." : String(UnicodeScalar(UInt8(code)))
        }.joined()
    }

    func testELInISOProtectedModeErasesLastColumn() {
        let screen = makeScreen()
        // Unprotected text fills the line; ESC V ESC W turns on ISO mode without protecting it.
        feed(screen, "abcdefghi\u{1b}[10Gj\u{1b}V\u{1b}W\u{1b}[3G\u{1b}[K")
        XCTAssertEqual(lineString(screen, 0), "ab........")
    }

    func testEL1InISOProtectedModeErasesCursorCell() {
        let screen = makeScreen()
        feed(screen, "abcdefghi\u{1b}V\u{1b}W\u{1b}[3G\u{1b}[1K")
        XCTAssertEqual(lineString(screen, 0), "...defghi.")
    }

    func testEDInISOProtectedModeErasesLastColumn() {
        let screen = makeScreen()
        feed(screen, "\u{1b}[\(height);1Habcdefghi\u{1b}[\(height);10Hj\u{1b}V\u{1b}W\u{1b}[1;1H\u{1b}[J")
        XCTAssertEqual(lineString(screen, height - 1), "..........")
    }

    func testED1InISOProtectedModeErasesCursorCell() {
        let screen = makeScreen()
        feed(screen, "abcdefghi\u{1b}V\u{1b}W\u{1b}[1;3H\u{1b}[1J")
        XCTAssertEqual(lineString(screen, 0), "...defghi.")
    }

    // MARK: - Other paths that fill with the current background

    func testECHCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "abcdef\u{1b}[2G" + setDualBackground + "\u{1b}[3X")
        assertDualBackground(screen, y: 0, xs: 1...3)
    }

    func testEDBelowCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "abc\r\ndef\r\nghi\u{1b}[1;1H" + setDualBackground + "\u{1b}[J")
        for y in 0..<height {
            assertDualBackground(screen, y: y, xs: 0...(width - 1))
        }
    }

    func testEDWholeScreenCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "abc\r\ndef" + setDualBackground + "\u{1b}[2J")
        for y in 0..<height {
            assertDualBackground(screen, y: y, xs: 0...(width - 1))
        }
    }

    func testDCHCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "abcdefghij\u{1b}[1G" + setDualBackground + "\u{1b}[3P")
        assertDualBackground(screen, y: 0, xs: (width - 3)...(width - 1))
    }

    func testICHCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "abcdef\u{1b}[1G" + setDualBackground + "\u{1b}[3@")
        assertDualBackground(screen, y: 0, xs: 0...2)
    }

    func testLineScrolledInAtBottomCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "\u{1b}[\(height);1H" + setDualBackground + "\n")
        assertDualBackground(screen, y: height - 1, xs: 0...(width - 1))
    }

    func testLineScrolledInWithinScrollRegionCarriesDualBackground() {
        let screen = makeScreen()
        // Scroll region rows 1-3, cursor at its bottom, then scroll.
        feed(screen, "\u{1b}[1;3r\u{1b}[3;1H" + setDualBackground + "\n")
        assertDualBackground(screen, y: 2, xs: 0...(width - 1))
    }

    func testReverseIndexCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "abc\u{1b}[1;1H" + setDualBackground + "\u{1b}M")
        assertDualBackground(screen, y: 0, xs: 0...(width - 1))
    }

    func testInsertLineCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "abc\r\ndef\u{1b}[1;1H" + setDualBackground + "\u{1b}[L")
        assertDualBackground(screen, y: 0, xs: 0...(width - 1))
    }

    func testDeleteLineCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "abc\r\ndef\u{1b}[1;1H" + setDualBackground + "\u{1b}[M")
        assertDualBackground(screen, y: height - 1, xs: 0...(width - 1))
    }

    // MARK: - Resizing

    private func assertWholeScreenDualBackground(_ screen: VT100Screen,
                                                 file: StaticString = #filePath,
                                                 line: UInt = #line) {
        for y in 0..<screen.height() {
            assertDualBackground(screen, y: y, xs: 0...(screen.width() - 1), file: file, line: line)
        }
    }

    func testGrowingTallerAfterClearCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, setDualBackground + "\u{1b}[2J")
        screen.size = VT100GridSizeMake(width, height + 3)
        assertWholeScreenDualBackground(screen)
    }

    func testGrowingWiderAfterClearCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, setDualBackground + "\u{1b}[2J")
        screen.size = VT100GridSizeMake(width + 5, height)
        assertWholeScreenDualBackground(screen)
    }

    func testShrinkingAfterClearCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, setDualBackground + "\u{1b}[2J")
        screen.size = VT100GridSizeMake(width - 3, height - 1)
        assertWholeScreenDualBackground(screen)
    }

    func testResizingAltScreenCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, "\u{1b}[?1049h" + setDualBackground + "\u{1b}[2J")
        screen.size = VT100GridSizeMake(width + 2, height + 3)
        assertWholeScreenDualBackground(screen)
    }

    func testRestoredLineTailCarriesDualBackground() {
        let screen = makeScreen()
        feed(screen, setDualBackground + "\u{1b}[2Jab\u{1b}[K")
        screen.size = VT100GridSizeMake(width + 4, height + 2)
        assertWholeScreenDualBackground(screen)
        XCTAssertEqual(gridLine(screen, 0).line[0].code, unichar(("a" as Character).asciiValue!))
    }

    // MARK: - The normal case must not change

    func testResizeWithoutDualModeCreatesNoExternalAttributes() {
        let screen = makeScreen()
        feed(screen, "\u{1b}[41m\u{1b}[2Jab\u{1b}[K")
        screen.size = VT100GridSizeMake(width + 4, height + 2)
        for y in 0..<screen.height() {
            let sca = gridLine(screen, y)
            for x in 0..<Int(screen.width()) {
                XCTAssertNil(sca.eaIndex?.attribute(at: Int32(x)), "cell (\(x), \(y))")
            }
        }
    }

    func testELWithoutDualModeCreatesNoExternalAttributes() {
        let screen = makeScreen()
        feed(screen, "\u{1b}[41mab\u{1b}[K")
        let sca = gridLine(screen, 0)
        for x in 2..<Int(width) {
            XCTAssertNotEqual(sca.line[x].backgroundColorMode, ColorModeExternal.rawValue)
            XCTAssertNil(sca.eaIndex?.attribute(at: Int32(x)), "cell \(x) should have no external attribute")
        }
    }

    func testELAfterResetDoesNotCarryStaleDualBackground() {
        let screen = makeScreen()
        feed(screen, setDualBackground + "ab\u{1b}[0m\u{1b}[K")
        let sca = gridLine(screen, 0)
        for x in 2..<Int(width) {
            XCTAssertNotEqual(sca.line[x].backgroundColorMode, ColorModeExternal.rawValue)
            XCTAssertNil(sca.eaIndex?.attribute(at: Int32(x)), "cell \(x) should have no external attribute")
        }
    }

    func testELDoesNotCopyURLOntoErasedCells() {
        let screen = makeScreen()
        // OSC 8 hyperlink is open while erasing; erased cells must not become links.
        feed(screen, setDualBackground + "\u{1b}]8;;https://example.com\u{1b}\\ab\u{1b}[K")
        assertDualBackground(screen, y: 0, xs: 2...(width - 1))
    }
}
