//
//  BidiTUIRepaintTests.swift
//  ModernTests
//
//  A TUI (like an AI agent CLI) repaints its output in place: cursor up,
//  erase line, rewrite, then eventually the rows scroll into history. Rows
//  written this way must get the same bidi treatment as rows printed once
//  and never touched. These tests replay that write pattern at the
//  VT100ScreenMutableState level, running populateRTLStateIfNeeded between
//  cycles the way the per-frame sync does, and assert that the per-row
//  BidiDisplayInfo survives each cycle.
//

import XCTest
@testable import iTerm2SharedARC

// FakeSession leaves screenRestore(_:) and screenUpdateDisplay(_:)
// unimplemented. Without the former, the screen's shared-state count never
// returns to zero after a joined block and every synchronizeWithConfig
// short-circuits; without the latter, the end-of-joined-block sync that
// PTYSession performs in production never happens. These tests exercise the
// real sync cadence, so implement both the way PTYSession does.
private class SyncingFakeSession: FakeSession {
    private let syncConfig: VT100MutableScreenConfiguration = {
        let config = VT100MutableScreenConfiguration()
        config.sessionGuid = "BidiTUIRepaintTests"
        return config
    }()

    override func screenRestore(_ state: VT100ScreenState) {
        screen?.restore(state)
    }

    override func screenUpdateDisplay(_ redraw: Bool) {
        guard let screen else { return }
        _ = screen.synchronize(withConfig: syncConfig,
                               expect: nil,
                               checkTriggers: .none,
                               resetOverflow: false,
                               mutableState: screen.mutableState)
    }
}

class BidiTUIRepaintTests: XCTestCase {
    private var session = SyncingFakeSession()

    private let persian = "جشنواره فیلم کوتاه تا یکشنبه ادامه دارد"
    private let mixed = "فستیوال Hikari Japan Festival فقط شنبه است"

    // [iTermPreferences bidiEnabled] is a fast-path cache updated via async
    // KVO dispatched to the main queue; pump the runloop until it lands.
    private func setBidiPreference(_ enabled: Bool) {
        iTermPreferences.setBool(enabled, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while iTermPreferences.bidiEnabled() != enabled && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

    private func makeScreen(width: Int32 = 60, height: Int32 = 6) -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
        })
        return screen
    }

    override func setUp() {
        super.setUp()
        setBidiPreference(true)
    }

    override func tearDown() {
        setBidiPreference(false)
        super.tearDown()
    }

    // Runs one "frame": performs the writes, then populates RTL state the way
    // the cross-thread sync does before every draw, and returns the bidi info
    // for the requested grid row.
    @discardableResult
    private func frame(_ screen: VT100Screen,
                       row: Int32 = 0,
                       writes: @escaping (VT100ScreenMutableState) -> Void) -> BidiDisplayInfoObjc? {
        var info: BidiDisplayInfoObjc?
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            writes(mutableState)
            mutableState.populateRTLStateIfNeeded()
            info = mutableState.currentGrid.bidiInfo(forLine: row)
        })
        return info
    }

    private func assertHasRTLRuns(_ info: BidiDisplayInfoObjc?,
                                  _ message: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(info, message, file: file, line: line)
        if let info {
            XCTAssertFalse(info.rtlIndexes.isEmpty,
                           "bidi info exists but has no RTL runs, \(message)",
                           file: file, line: line)
        }
    }

    // Baseline: a Persian row printed once, like `cat`, gets bidi info.
    func testPlainAppendGetsBidiInfo() {
        let screen = makeScreen()
        let info = frame(screen) { mutableState in
            mutableState.appendString(atCursor: self.persian)
            mutableState.appendCarriageReturnLineFeed()
        }
        assertHasRTLRuns(info, "plain append must produce bidi info")
    }

    // One repaint cycle: draw, then cursor-up + erase + rewrite, draw again.
    func testRepaintedRowKeepsBidiInfo() {
        let screen = makeScreen()
        let before = frame(screen) { mutableState in
            mutableState.appendString(atCursor: self.persian)
            mutableState.appendCarriageReturnLineFeed()
        }
        assertHasRTLRuns(before, "before repaint")

        let after = frame(screen) { mutableState in
            mutableState.cursorUp(1, andToStartOfLine: true)
            mutableState.eraseLine(beforeCursor: true, afterCursor: true, decProtect: false)
            mutableState.appendString(atCursor: self.persian)
            mutableState.appendCarriageReturnLineFeed()
        }
        assertHasRTLRuns(after, "after one repaint cycle")
    }

    // Streaming: several repaint cycles with a populate (≈ a drawn frame)
    // between each, mixed Persian/English like real agent output.
    func testStreamingRepaintCyclesKeepBidiInfo() {
        let screen = makeScreen()
        frame(screen) { mutableState in
            mutableState.appendString(atCursor: self.mixed)
            mutableState.appendCarriageReturnLineFeed()
        }
        for cycle in 1...5 {
            let info = frame(screen) { mutableState in
                mutableState.cursorUp(1, andToStartOfLine: true)
                mutableState.eraseLine(beforeCursor: true, afterCursor: true, decProtect: false)
                mutableState.appendString(atCursor: self.mixed)
                mutableState.appendCarriageReturnLineFeed()
            }
            assertHasRTLRuns(info, "after repaint cycle \(cycle)")
        }
    }

    // A repaint that is interrupted mid-frame: erase happens, populate runs
    // (blank row), then the rewrite lands in the next frame. The final frame
    // must still produce bidi info.
    func testEraseThenRewriteAcrossFrames() {
        let screen = makeScreen()
        frame(screen) { mutableState in
            mutableState.appendString(atCursor: self.persian)
            mutableState.appendCarriageReturnLineFeed()
        }
        frame(screen) { mutableState in
            mutableState.cursorUp(1, andToStartOfLine: true)
            mutableState.eraseLine(beforeCursor: true, afterCursor: true, decProtect: false)
        }
        let info = frame(screen) { mutableState in
            mutableState.appendString(atCursor: self.persian)
            mutableState.appendCarriageReturnLineFeed()
        }
        assertHasRTLRuns(info, "rewrite one frame after erase")
    }

    // Region scrolls (DECSTBM, IND at the bottom margin, IL/DL) move row
    // content with scrollRect:downBy:softBreak:. The rtlFound annotation must
    // travel with the content: bidi analysis is gated on it, so leaving it
    // behind makes the next populate pass null out the moved row's bidi info
    // and the row renders in raw logical order.
    func testScrollRectMovesRTLFoundWithContent() {
        let grid = VT100Grid(size: VT100GridSize(width: 20, height: 4), delegate: nil)!
        let lineBuffer = LineBuffer(blockSize: 1000)

        func appendRow(_ text: String, rtl: Bool) {
            let sca = screenCharArrayWithDefaultStyle(text, eol: EOL_HARD)
            grid.appendChars(atCursor: sca.line,
                             length: sca.length,
                             scrollingInto: lineBuffer,
                             unlimitedScrollback: true,
                             useScrollbackWithRegion: false,
                             wraparound: true,
                             ansi: false,
                             insert: false,
                             externalAttributeIndex: nil,
                             rtlFound: rtl,
                             dwcFree: false)
            grid.cursorX = 0
            grid.cursorY += 1
        }
        appendRow("hello", rtl: false)
        appendRow(persian, rtl: true)
        XCTAssertFalse(grid.metadata(atLineNumber: 0).rtlFound.boolValue, "precondition")
        XCTAssertTrue(grid.metadata(atLineNumber: 1).rtlFound.boolValue, "precondition")

        // Scroll the whole grid up one row: the Persian row moves from 1 to 0.
        grid.scroll(VT100GridRectMake(0, 0, 20, 4), downBy: -1, softBreak: false)

        XCTAssertTrue(grid.metadata(atLineNumber: 0).rtlFound.boolValue,
                      "rtlFound must move with the Persian row's content")
    }

    // End to end: after a region scroll, the moved Persian row must still get
    // bidi info from the next populate pass.
    func testRegionScrollKeepsBidiInfo() {
        let screen = makeScreen(width: 40, height: 4)
        let before = frame(screen, row: 1) { mutableState in
            mutableState.appendString(atCursor: "hello")
            mutableState.appendCarriageReturnLineFeed()
            mutableState.appendString(atCursor: self.persian)
            mutableState.appendCarriageReturnLineFeed()
        }
        assertHasRTLRuns(before, "before region scroll")

        var after: BidiDisplayInfoObjc?
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            // Emulate a TUI scrolling its viewport: the grid rows shift up by
            // one without going through the line buffer.
            mutableState.currentGrid.scroll(VT100GridRectMake(0, 0, 40, 4),
                                            downBy: -1,
                                            softBreak: false)
            mutableState.populateRTLStateIfNeeded()
            after = mutableState.currentGrid.bidiInfo(forLine: 0)
        })
        XCTAssertNotNil(after, "Persian row scrolled up a row must keep bidi info")
        if let after {
            XCTAssertFalse(after.rtlIndexes.isEmpty, "moved row must still have RTL runs")
        }
    }

    // Streaming within a row: agents append a sentence to the same row in
    // several chunks, and a bidi pass (≈ a drawn frame) can run between any
    // two chunks. The final row's reordering table must be identical to the
    // one produced by writing the whole sentence at once, a stale mid-write
    // table shifts every subsequent letter by a cell.
    func testChunkedAppendMatchesOneShotBidiInfo() {
        // ZWNJ-heavy, like real Persian prose.
        let sentence = "میرم پیش‌بینی هوای برلین رو از سرویس هواشناسی بگیرم و بعد دنبال برنامه‌های آخر هفته بگردم."

        let oneShot = makeScreen(width: 100, height: 6)
        let expected = frame(oneShot) { mutableState in
            mutableState.appendString(atCursor: sentence)
        }
        assertHasRTLRuns(expected, "one-shot append must produce bidi info")

        let chunked = makeScreen(width: 100, height: 6)
        // Split mid-word and next to ZWNJs, the worst places to pause.
        let chunks = ["میرم پیش", "‌بینی هوا", "ی برلین رو از سروی", "س هواشناسی بگیرم و بع", "د دنبال برنامه‌", "های آخر هفته بگردم."]
        XCTAssertEqual(chunks.joined(), sentence, "chunks must reassemble the sentence")
        var actual: BidiDisplayInfoObjc?
        for chunk in chunks {
            actual = frame(chunked) { mutableState in
                mutableState.appendString(atCursor: chunk)
            }
        }
        XCTAssertNotNil(actual, "chunked append must produce bidi info")
        XCTAssertEqual(actual, expected,
                       "chunked and one-shot appends must yield the same reordering")
    }

    // The renderer draws from the immutable state's grid, refreshed from the
    // mutable grid on every frame sync. After each sync the renderer's copy
    // must be self-consistent: its stored bidi info must match info computed
    // fresh from its own row content. A stale copy shifts every letter drawn
    // after the staleness point.
    func testRendererCopyStaysConsistentAcrossStreamingFrames() {
        let width: Int32 = 100
        let screen = makeScreen(width: width, height: 6)

        let chunks = ["میرم پیش", "‌بینی هوا", "ی برلین رو از سروی", "س هواشناسی بگیرم و بع", "د دنبال برنامه‌", "های آخر هفته بگردم."]
        for (i, chunk) in chunks.enumerated() {
            var mayRTL = false
            // The sync happens automatically at the end of the joined block via
            // SyncingFakeSession.screenUpdateDisplay, as in production.
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                mutableState.appendString(atCursor: chunk)
                mayRTL = mutableState.currentGrid.mayContainRTL
            })
            XCTAssertTrue(mayRTL, "probe: grid must know it may contain RTL after chunk \(i)")
            XCTAssertTrue(iTermPreferences.bidiEnabled(), "probe: pref cache on at sync time, chunk \(i)")

            // What the renderer actually consumes: the SCA from the
            // main-thread state, with its attached bidi info.
            let sca = screen.screenCharArray(forLine: 0)
            let stored = sca.bidiInfo
            let fresh = BidiDisplayInfoObjc(sca, paddedTo: width)
            // Triangulation probes: which hop loses the bidi info?
            var mutableGridInfo: BidiDisplayInfoObjc?
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                mutableGridInfo = mutableState.currentGrid.bidiInfo(forLine: 0)
            })
            let drawingAccessor = screen.bidiInfo(forLine: 0)
            XCTAssertNotNil(mutableGridInfo, "probe: mutable grid after chunk \(i)")
            XCTAssertNotNil(drawingAccessor, "probe: screen.bidiInfoForLine after chunk \(i)")
            XCTAssertEqual(stored, fresh,
                           "renderer bidi info stale after streaming chunk \(i)")
        }
    }

    // zsh edits a line in place instead of repainting it wholesale. For
    //
    //   echo 'מה קורה מותק, how are you'
    //
    // Left, Left, Left, Backspace produces this byte-level repaint sequence:
    // four BS characters, "ou' ", then four more BS characters. The logical
    // row becomes "... how are ou'" and the cursor lands before the `o`.
    // The post-edit frame must not reuse the pre-edit bidi table, which would
    // draw the overwritten tail in its old visual columns.
    func testZshPartialLineEditRefreshesBidiMapping() {
        let width: Int32 = 80
        let screen = makeScreen(width: width, height: 6)
        let beforeText = "BIDI> echo 'מה קורה מותק, how are you'"
        let afterText = "BIDI> echo 'מה קורה מותק, how are ou'"

        frame(screen) { mutableState in
            mutableState.appendString(atCursor: beforeText)
        }

        var logicalCursorX: Int32 = -1
        frame(screen) { mutableState in
            for _ in 0..<4 { mutableState.backspace() }
            mutableState.appendString(atCursor: "ou' ")
            for _ in 0..<4 { mutableState.backspace() }
            logicalCursorX = mutableState.currentGrid.cursorX
        }

        let sca = screen.screenCharArray(forLine: 0)
        XCTAssertTrue(sca.stringValue.hasPrefix(afterText),
                      "zsh repaint must leave the expected logical row")
        guard let stored = screen.bidiInfo(forLine: 0),
              let fresh = BidiDisplayInfoObjc(sca, paddedTo: width) else {
            return XCTFail("edited mixed row must have bidi information")
        }
        XCTAssertEqual(stored, fresh,
                       "partial overwrite must refresh the renderer's bidi table")
        let expectedVisual = "BIDI> echo 'how are ou ,קתומ הרוק המ'"
        XCTAssertEqual(visualOrder(screen, row: 0).visual.trimmingCharacters(in: .whitespaces),
                       expectedVisual,
                       "partial repaint must draw exactly like a full repaint")
        let expectedCursorX = (expectedVisual as NSString).range(of: "ou").location
        XCTAssertEqual(stored.visualForLogical(logicalCursorX),
                       Int32(expectedCursorX),
                       "cursor must land before the remaining `ou`, not at its pre-edit column")
    }

    // The rewritten row scrolls into history; its bidi info must survive in
    // the line buffer, which is what the renderer consults for history rows.
    func testRepaintedRowScrolledIntoHistoryKeepsBidiInfo() {
        let screen = makeScreen(width: 60, height: 4)
        frame(screen) { mutableState in
            mutableState.maxScrollbackLines = 100
            mutableState.appendString(atCursor: self.persian)
            mutableState.appendCarriageReturnLineFeed()
        }
        let before = frame(screen) { mutableState in
            mutableState.cursorUp(1, andToStartOfLine: true)
            mutableState.eraseLine(beforeCursor: true, afterCursor: true, decProtect: false)
            mutableState.appendString(atCursor: self.persian)
            mutableState.appendCarriageReturnLineFeed()
        }
        assertHasRTLRuns(before, "before scrolling out")

        var historyInfo: BidiDisplayInfoObjc?
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for _ in 0..<8 {
                mutableState.appendCarriageReturnLineFeed()
            }
            mutableState.populateRTLStateIfNeeded()
            let width = mutableState.currentGrid.size.width
            historyInfo = mutableState.linebuffer.bidiInfo(forLine: 0, width: width)
        })
        assertHasRTLRuns(historyInfo, "after scrolling into history")
    }

    // The visual (display) order a row renders in: read the row content and its
    // bidi map exactly as the renderer does, then place each logical cell at its
    // visual column. With no bidi the row is drawn in logical order.
    private func visualOrder(_ screen: VT100Screen, row: Int32) -> (visual: String, hasBidi: Bool) {
        let sca = screen.screenCharArray(forLine: row)
        let logical = Array(sca.stringValue)
        guard let bidi = screen.bidiInfo(forLine: row) else {
            return (sca.stringValue, false)
        }
        var visual = ""
        for v in 0..<bidi.numberOfCells {
            let lg = Int(bidi.logicalForVisual(v))
            if lg >= 0 && lg < logical.count { visual.append(logical[lg]) }
        }
        return (visual, true)
    }

    // Regression: a wrapped RTL paragraph that scrolls into scrollback must keep
    // its reorder map on EVERY wrapped row, not just the first. The linebuffer
    // double-split each continuation row's bidi to an empty range and dropped it,
    // so from history those rows drew in logical order, reversed/scrambled. This
    // drives the same accessor the renderer reads (screen.bidiInfo(forLine:)) and
    // requires each row to render identically from history and from the grid.
    func testWrappedRTLKeepsBidiAfterScrollingIntoHistory() {
        let para = "اگر بگویی امروز روز کاری‌ات است یا تعطیل، تنها هستی یا با کسی، و چند ساعت آزاد داری، می‌توانم این را به یک برنامه‌ی ساعت‌به‌ساعت واقعی برای برلین تبدیل کنم."
        let width: Int32 = 77
        let screen = makeScreen(width: width, height: 6)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.maxScrollbackLines = 1000
            mutableState.appendString(atCursor: para)
            mutableState.appendCarriageReturnLineFeed()
            mutableState.populateRTLStateIfNeeded()
        })
        let gridRow0 = visualOrder(screen, row: 0)
        let gridRow1 = visualOrder(screen, row: 1)
        XCTAssertTrue(gridRow0.hasBidi, "row 0 must have bidi on the grid")
        XCTAssertTrue(gridRow1.hasBidi, "continuation row must have bidi on the grid")

        // Scroll the paragraph up into the linebuffer, populating each frame.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for _ in 0..<10 {
                mutableState.appendCarriageReturnLineFeed()
                mutableState.populateRTLStateIfNeeded()
            }
        })
        let histRow0 = visualOrder(screen, row: 0)
        let histRow1 = visualOrder(screen, row: 1)
        XCTAssertTrue(histRow0.hasBidi, "first wrapped row must keep bidi in history")
        XCTAssertTrue(histRow1.hasBidi,
                      "continuation wrapped row must keep bidi in history (else it draws scrambled)")
        XCTAssertEqual(histRow0.visual, gridRow0.visual,
                       "row 0 must render the same from history as on the grid")
        XCTAssertEqual(histRow1.visual, gridRow1.visual,
                       "continuation row must render the same from history as on the grid, not scrambled")
    }
}
