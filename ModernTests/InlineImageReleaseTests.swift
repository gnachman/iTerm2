//
//  InlineImageReleaseTests.swift
//  ModernTests
//
//  An inline image (OSC 1337 File=inline=1) stays in memory as long as its image mark is in the
//  interval tree. At each sync, -[VT100ScreenState releaseOverwrittenImagesIn:] removes the mark
//  of any on-screen image whose cells have all been drawn over. Issue 13214: a live view that
//  redraws a picture in place grew iTerm2's memory by every frame it sent.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

// FakeSession leaves screenRestore(_:) and screenUpdateDisplay(_:) unimplemented, so the
// end-of-joined-block sync that PTYSession performs never happens. The release scan runs during
// that sync, so implement both the way PTYSession does.
private class InlineImageSyncingFakeSession: FakeSession {
    let syncConfig: VT100MutableScreenConfiguration = {
        let config = VT100MutableScreenConfiguration()
        config.sessionGuid = "InlineImageReleaseTests"
        config.cellSize = NSSize(width: 7, height: 14)
        config.maxScrollbackLines = 1000
        return config
    }()

    override func screenRestore(_ state: VT100ScreenState?) {
        guard let state else {
            return
        }
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

final class InlineImageReleaseTests: XCTestCase {
    private var session = InlineImageSyncingFakeSession()

    private lazy var pngBase64: String = {
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 20, height: 20).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!.base64EncodedString()
    }()

    private func makeScreen(width: Int32 = 80,
                            height: Int32 = 30,
                            maxScrollbackLines: Int32 = 1000) -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        let config = session.syncConfig
        config.maxScrollbackLines = maxScrollbackLines
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setConfig(config)
            mutableState.terminalEnabled = true
            mutableState.terminal!.termType = "xterm"
            mutableState.terminal!.encoding = String.Encoding.utf8.rawValue
            screen.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
        })
        return screen
    }

    /// Feeds bytes through the parser and syncs, as the app does after a batch of input. The
    /// autorelease pool lets a removed image mark deallocate, which is what releases its image.
    private func inject(_ screen: VT100Screen, _ string: String) {
        autoreleasepool {
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                mutableState.inject(string.data(using: .utf8)!)
            })
            screen.waitForQueuedTokensForTesting()
            screen.performBlock(joinedThreads: { _, _, _ in })
        }
    }

    private func imageSequence(widthInCells: Int, heightInCells: Int) -> String {
        return "\u{1b}]1337;File=inline=1;width=\(widthInCells);height=\(heightInCells);preserveAspectRatio=0:\(pngBase64)\u{07}"
    }

    /// The image code in the cell at (x, y), or nil if it isn't an image cell. The joined block
    /// syncs when it ends, which can remove marks, so it gets its own autorelease pool too.
    private func imageCode(_ screen: VT100Screen, x: Int32, y: Int32) -> Int? {
        var result: Int?
        autoreleasepool {
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                let c = mutableState.currentGrid.character(at: VT100GridCoord(x: x, y: y))
                if c.image != 0 {
                    result = Int(c.code)
                }
            })
        }
        return result
    }

    private func isRegistered(_ code: Int) -> Bool {
        return ImageRegistry.instance.info(for: code) != nil
    }

    /// Line numbers (0 is the oldest line of history) of every line, in history or on the
    /// current screen, with a cell of image `code`.
    private func linesContaining(_ screen: VT100Screen, code: Int) -> [Int32] {
        var result = [Int32]()
        autoreleasepool {
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                for i in 0..<mutableState.numberOfLines {
                    let sca = mutableState.screenCharArray(forLine: i)
                    let chars = sca.line
                    for x in 0..<Int(sca.length) {
                        if chars[x].image != 0 && chars[x].virtualPlaceholder == 0 && Int(chars[x].code) == code {
                            result.append(i)
                            break
                        }
                    }
                }
            })
        }
        return result
    }

    // Every joined block gets its own autorelease pool, even one that only reads: an object
    // autoreleased during a joined block (including its closing sync) can hold an image mark,
    // and left in the test's outer pool it keeps the image alive until the test ends. Whether
    // such an object goes into the caller's pool depends on the build (the tests that read
    // without a pool failed under the nullability and thread sanitizers).

    /// The first line of history is line 0; this is the line number of the top of the screen.
    private func screenTop(_ screen: VT100Screen) -> Int32 {
        var result: Int32 = 0
        autoreleasepool {
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                result = mutableState.numberOfScrollbackLines
            })
        }
        return result
    }

    /// Asserts the test's premise: a cell of the image is still somewhere in the buffer, so
    /// releasing the image would draw it as a brown rectangle.
    private func assertStillInBuffer(_ screen: VT100Screen,
                                     code: Int,
                                     inHistory: Bool? = nil,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        let lines = linesContaining(screen, code: code)
        XCTAssertFalse(lines.isEmpty, "premise: the image should still have cells in the buffer",
                       file: file, line: line)
        if let inHistory {
            let top = screenTop(screen)
            XCTAssertEqual(lines.contains { $0 < top }, inHistory,
                           inHistory ? "premise: the image should have cells in history"
                                     : "premise: the image should have no cells in history",
                           file: file, line: line)
        }
    }

    /// Asserts the test's premise: no cell of the image is left anywhere in the buffer.
    private func assertGoneFromBuffer(_ screen: VT100Screen,
                                      code: Int,
                                      file: StaticString = #filePath,
                                      line: UInt = #line) {
        XCTAssertEqual(linesContaining(screen, code: code), [],
                       "premise: every cell of the image should have been drawn over",
                       file: file, line: line)
    }

    /// Writes `text` over the first `columns` cells of rows `rows` (0-based).
    private func overwrite(rows: ClosedRange<Int>, columns: Int = 10) -> String {
        return rows.map { "\u{1b}[\($0 + 1);1H" + String(repeating: "Z", count: columns) }.joined()
    }

    private func scrollWholeScreen(_ lines: Int, height: Int = 30) -> String {
        return "\u{1b}[\(height);1H" + String(repeating: "\r\n", count: lines)
    }

    /// Adds screen marks on the first few lines, then scrolls them into history, the way prompts
    /// from earlier commands sit above a program's output in a real session.
    private func addOlderMarks(_ screen: VT100Screen, count: Int) {
        for i in 0..<count {
            autoreleasepool {
                screen.performBlock(joinedThreads: { _, mutableState, _ in
                    _ = mutableState.addMark(onLine: Int32(i), of: VT100ScreenMark.self)
                })
            }
        }
        inject(screen, String(repeating: "x\r\n", count: 60))
    }

    // MARK: - Tests

    func testImageDrawnOverInPlaceIsReleased() {
        let screen = makeScreen()
        var codes = [Int]()
        for _ in 0..<5 {
            inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
            codes.append(imageCode(screen, x: 0, y: 0)!)
        }
        XCTAssertEqual(codes.filter(isRegistered), [codes.last!],
                       "only the image still on screen should be kept")
    }

    /// Issue 13214. Older marks in history ended the release scan before it reached any
    /// on-screen image mark, so every frame stayed in memory until the buffer was cleared.
    func testImageDrawnOverInPlaceIsReleasedWithMarksInHistory() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        var codes = [Int]()
        for _ in 0..<5 {
            inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
            codes.append(imageCode(screen, x: 0, y: 0)!)
        }
        XCTAssertEqual(codes.filter(isRegistered), [codes.last!],
                       "only the image still on screen should be kept")
    }

    /// An image's mark sits on the line below it and doesn't move when a scroll region moves
    /// the image's cells. Pushing the image down past its own mark must not release it.
    func testImageShiftedDownPastItsMarkIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 3))
        let code = imageCode(screen, x: 0, y: 0)!

        // Insert 6 blank lines at the top, moving the image from rows 0-2 to rows 6-8, below
        // its mark on row 3.
        inject(screen, "\u{1b}[H\u{1b}[6L")
        XCTAssertEqual(imageCode(screen, x: 0, y: 6), code, "image cells should have moved down")
        XCTAssertNil(imageCode(screen, x: 0, y: 0))

        // Change something else so the next sync scans again.
        inject(screen, "\u{1b}[20;1Hhello")
        XCTAssertTrue(isRegistered(code), "an image still on screen must not be released")
    }

    /// Same, but scrolling the image up within a scroll region by more than its height.
    func testImageScrolledUpWithinScrollRegionIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[16;1H" + imageSequence(widthInCells: 10, heightInCells: 3))
        let code = imageCode(screen, x: 0, y: 15)!

        // Scroll region rows 3-25 (1-based), scrolled up 8: the image moves from rows 15-17 to
        // rows 7-9, well above its mark on row 18.
        inject(screen, "\u{1b}[3;25r\u{1b}[8S\u{1b}[r")
        XCTAssertEqual(imageCode(screen, x: 0, y: 7), code, "image cells should have moved up")
        XCTAssertNil(imageCode(screen, x: 0, y: 15))

        inject(screen, "\u{1b}[28;1Hhello")
        XCTAssertTrue(isRegistered(code), "an image still on screen must not be released")
    }

    /// An image partly scrolled into history is still visible and must be kept.
    func testImagePartlyInHistoryIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[26;1H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 25)!

        // Scroll the whole screen up 27 lines so the top two rows of the image go into history.
        inject(screen, "\u{1b}[30;1H" + String(repeating: "\r\n", count: 27) + "hello")
        XCTAssertEqual(imageCode(screen, x: 0, y: 1), code, "the bottom row should still be on screen")
        XCTAssertTrue(isRegistered(code), "an image partly in history must not be released")
    }

    /// Issue 13235. A burst of output between two syncs can scroll an image all the way into
    /// history, further up than its own height. It was scrolled away, not drawn over, so it must
    /// be kept: the user can still scroll back to it. It was released and drew as a brown
    /// rectangle. Here the scrollback is still growing, as in a new tab.
    func testImageScrolledFullyIntoHistoryInOneSyncIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        // Scroll the whole screen up 100 lines in a single sync. The image ends up about 100
        // lines above the top of the screen, far past the 4 lines of history its height covers.
        inject(screen, "\u{1b}[30;1H" + String(repeating: "\r\n", count: 100) + "hello")
        for y in Int32(0)..<30 {
            XCTAssertNil(imageCode(screen, x: 0, y: y), "the image should have left the screen")
        }
        XCTAssertTrue(isRegistered(code), "an image scrolled into history must not be released")
    }

    /// The repro from issue 13235: lines of text in one write. (These take the slow path: writing
    /// an image resets the count of plain lines the fast path needs, and by the time a screenful
    /// has followed, the image is off the screen.)
    func testImageScrolledIntoHistoryByBurstOfTextIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[20;1H" + imageSequence(widthInCells: 10, heightInCells: 4) + "\r\n")
        let code = imageCode(screen, x: 0, y: 19)!

        inject(screen, (0..<300).map { "line \($0)\r\n" }.joined())
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "an image scrolled into history must not be released")
    }

    /// Same, but the scrollback is already full, so lines drop off the top as new ones arrive.
    /// The image scrolls into history but stays well inside the scrollback buffer.
    func testImageScrolledFullyIntoFullHistoryInOneSyncIsKept() {
        let screen = makeScreen(maxScrollbackLines: 200)
        addOlderMarks(screen, count: 5)
        inject(screen, String(repeating: "y\r\n", count: 300))
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, "\u{1b}[30;1H" + String(repeating: "\r\n", count: 100) + "hello")
        for y in Int32(0)..<30 {
            XCTAssertNil(imageCode(screen, x: 0, y: y), "the image should have left the screen")
        }
        XCTAssertTrue(isRegistered(code), "an image scrolled into history must not be released")
    }

    /// With “Save lines to scrollback when an app status bar is present” on, a scroll region that
    /// starts at the top of the screen sends the lines it scrolls off into history. A burst inside such a region can push an image far into history in one sync.
    func testImageScrolledIntoHistoryByTopAnchoredRegionInOneSyncIsKept() {
        session.syncConfig.appendToScrollbackWithStatusBar = true
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[11;1H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 10)!

        // Scroll region rows 1-20 (1-based); newlines at its bottom scroll it up 100 lines.
        inject(screen, "\u{1b}[1;20r\u{1b}[20;1H" + String(repeating: "\r\n", count: 100) + "hello\u{1b}[r")
        for y in Int32(0)..<30 {
            XCTAssertNil(imageCode(screen, x: 0, y: y), "the image should have left the screen")
        }
        XCTAssertTrue(isRegistered(code), "an image scrolled into history must not be released")
    }

    // MARK: - Cells moved by DECCRA

    /// DECCRA copies image cells, code and all. The copy keeps the image in use after the original
    /// is drawn over.
    func testImageCopiedByDECCRAThenOriginalDrawnOverIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        // Copy rows 1-4, columns 1-10 (1-based) to row 16.
        inject(screen, "\u{1b}[1;1;4;10;1;16;1;1$v")
        XCTAssertEqual(imageCode(screen, x: 0, y: 15), code, "premise: DECCRA should copy image cells")

        inject(screen, overwrite(rows: 0...3))
        XCTAssertNil(imageCode(screen, x: 0, y: 0))
        assertStillInBuffer(screen, code: code, inHistory: false)
        XCTAssertTrue(isRegistered(code), "an image copied by DECCRA must stay while the copy is visible")
    }

    /// The original is drawn over and the copy is scrolled into history in the same sync.
    func testDECCRACopyScrolledIntoHistoryAfterOriginalDrawnOverIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!
        inject(screen, "\u{1b}[1;1;4;10;1;21;1;1$v")
        XCTAssertEqual(imageCode(screen, x: 0, y: 20), code, "premise: DECCRA should copy image cells")

        inject(screen, overwrite(rows: 0...3) + scrollWholeScreen(100) + "hello")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "a copy in history must keep the image")
    }

    func testImageAndItsDECCRACopyBothDrawnOverIsReleased() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!
        inject(screen, "\u{1b}[1;1;4;10;1;16;1;1$v")
        XCTAssertEqual(imageCode(screen, x: 0, y: 15), code, "premise: DECCRA should copy image cells")

        inject(screen, overwrite(rows: 0...3) + overwrite(rows: 15...18))
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "an image whose cells and copies are all drawn over should be released")
    }

    // MARK: - Cells moved relative to their mark

    /// A full-screen scroll moves the mark up with the image; scrolling a two-row region down then
    /// moves the image back down, leaving the mark one row further above it each time. Then a burst
    /// pushes the image, now well below its mark, into history.
    func testImagePushedBelowItsMarkThenScrolledIntoHistoryIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[29;1H" + imageSequence(widthInCells: 10, heightInCells: 1))
        let code = imageCode(screen, x: 0, y: 28)!
        for _ in 0..<10 {
            inject(screen, scrollWholeScreen(1) + "\u{1b}[28;29r\u{1b}[T\u{1b}[r")
        }
        XCTAssertEqual(imageCode(screen, x: 0, y: 28), code, "premise: the image should be back on row 28")

        inject(screen, scrollWholeScreen(100) + "hello")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "an image scrolled into history must not be released")
    }

    /// Reverse index at the top of the screen scrolls the screen down, moving the image below its
    /// mark. It must be kept on screen, and kept again when a burst scrolls it into history.
    func testImageMovedDownByReverseIndexIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 3))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, "\u{1b}[H" + String(repeating: "\u{1b}M", count: 6))
        XCTAssertEqual(imageCode(screen, x: 0, y: 6), code, "premise: image cells should have moved down")
        inject(screen, "\u{1b}[25;1Hhello")
        XCTAssertTrue(isRegistered(code), "an image still on screen must not be released")

        inject(screen, scrollWholeScreen(100) + "hello")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "an image scrolled into history must not be released")
    }

    /// Deleting lines above the image moves it up, away from its mark.
    func testImageMovedUpByDeleteLinesIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[11;1H" + imageSequence(widthInCells: 10, heightInCells: 3))
        let code = imageCode(screen, x: 0, y: 10)!

        inject(screen, "\u{1b}[3;1H\u{1b}[6M")
        XCTAssertEqual(imageCode(screen, x: 0, y: 4), code, "premise: image cells should have moved up")
        inject(screen, "\u{1b}[25;1Hhello")
        XCTAssertTrue(isRegistered(code), "an image still on screen must not be released")

        inject(screen, scrollWholeScreen(100) + "hello")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "an image scrolled into history must not be released")
    }

    // MARK: - Cells moved sideways or partly erased

    /// Inserting characters pushes most of each row off the right edge, but some cells survive.
    func testImagePartlyPushedOffByInsertCharactersIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, (1...4).map { "\u{1b}[\($0);1H\u{1b}[75@" }.joined())
        XCTAssertEqual(imageCode(screen, x: 75, y: 0), code, "premise: image cells should have moved right")
        XCTAssertTrue(isRegistered(code), "an image partly on screen must not be released")
    }

    /// Deleting characters shifts each row left, dropping some cells but keeping the rest.
    func testImagePartlyDeletedByDeleteCharactersIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, (1...4).map { "\u{1b}[\($0);1H\u{1b}[5P" }.joined())
        assertStillInBuffer(screen, code: code, inHistory: false)
        XCTAssertTrue(isRegistered(code), "an image partly on screen must not be released")
    }

    /// DECIC and DECDC insert and delete columns in every row of the scroll region.
    func testImageShiftedByInsertAndDeleteColumnsIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, "\u{1b}[1;1H\u{1b}[75'}")
        assertStillInBuffer(screen, code: code, inHistory: false)
        XCTAssertTrue(isRegistered(code), "an image partly on screen must not be released")

        inject(screen, "\u{1b}[1;1H\u{1b}[73'~")
        assertStillInBuffer(screen, code: code, inHistory: false)
        XCTAssertTrue(isRegistered(code), "an image partly on screen must not be released")
    }

    /// Erasing most of the image leaves the rest in use.
    func testImagePartlyErasedIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, (1...3).map { "\u{1b}[\($0);1H\u{1b}[10X" }.joined())
        XCTAssertEqual(imageCode(screen, x: 0, y: 3), code, "premise: the last row should survive")
        XCTAssertTrue(isRegistered(code), "an image partly on screen must not be released")
    }

    // MARK: - Cells destroyed without entering history

    /// Issue 13214 with a scroll in the same sync: the image is drawn over, then output scrolls.
    /// No cell of it reached history, so it must still be released.
    func testImageDrawnOverThenScrolledInSameSyncIsReleased() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, overwrite(rows: 0...3) + scrollWholeScreen(100) + "hello")
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "an image drawn over before it scrolled should be released")
    }

    /// One image is drawn over while another scrolls into history in the same sync.
    func testDrawnOverImageReleasedAndScrolledImageKeptInSameSync() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let drawnOver = imageCode(screen, x: 0, y: 0)!
        inject(screen, "\u{1b}[11;1H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let scrolled = imageCode(screen, x: 0, y: 10)!

        inject(screen, overwrite(rows: 0...3) + scrollWholeScreen(100) + "hello")
        assertGoneFromBuffer(screen, code: drawnOver)
        assertStillInBuffer(screen, code: scrolled, inHistory: true)
        XCTAssertFalse(isRegistered(drawnOver), "the drawn-over image should be released")
        XCTAssertTrue(isRegistered(scrolled), "the scrolled image must be kept")
    }

    /// A scroll region in the middle of the screen discards the lines it scrolls off its top.
    func testImageScrolledOutOfMiddleRegionIsReleased() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[7;1H" + imageSequence(widthInCells: 10, heightInCells: 3))
        let code = imageCode(screen, x: 0, y: 6)!

        inject(screen, "\u{1b}[6;21r\u{1b}[10S\u{1b}[r")
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "an image scrolled out of a middle region should be released")
    }

    /// Even with “Save lines to scrollback when an app status bar is present” on, a region with
    /// left and right margins never sends lines to history.
    func testImageScrolledOffTopOfColumnRegionIsReleased() {
        session.syncConfig.appendToScrollbackWithStatusBar = true
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, "\u{1b}[?69h\u{1b}[1;40s\u{1b}[30;1H" + String(repeating: "\n", count: 40) +
               "\u{1b}[s\u{1b}[?69l")
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "an image scrolled out of a column region should be released")
    }

    func testImageDeletedByDeleteLinesIsReleased() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, "\u{1b}[1;1H\u{1b}[4M")
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "a deleted image should be released")
    }

    func testImageErasedByDECERAIsReleased() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, "\u{1b}[1;1;4;10$z")
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "an erased image should be released")
    }

    // MARK: - Alternate screen

    /// The primary screen's contents are kept while the alternate screen is up, so an image on it
    /// must survive syncs that only see the alternate screen.
    func testPrimaryScreenImageKeptWhileAlternateScreenIsUp() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, "\u{1b}[?1049h\u{1b}[Hhello")
        inject(screen, "\u{1b}[5;1Hworld")
        XCTAssertTrue(isRegistered(code), "the primary screen's image must not be released")
        inject(screen, "\u{1b}[?1049l")
        XCTAssertEqual(imageCode(screen, x: 0, y: 0), code, "premise: the image should be back on screen")
        XCTAssertTrue(isRegistered(code), "the primary screen's image must not be released")
    }

    func testAlternateScreenImageDrawnOverIsReleased() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[?1049h\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, overwrite(rows: 0...3))
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "a drawn-over image on the alternate screen should be released")
    }

    /// With “Save lines to scrollback in alternate screen mode” on, lines scrolled off the
    /// alternate screen go into history.
    func testAlternateScreenImageScrolledIntoHistoryIsKept() {
        session.syncConfig.saveToScrollbackInAlternateScreen = true
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[?1049h\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, scrollWholeScreen(100) + "hello")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "an image scrolled into history must not be released")
    }

    // MARK: - Clearing

    /// Clearing history must not release an image whose bottom rows are still on screen.
    func testImagePartlyOnScreenKeptAfterClearingScrollback() {
        session.syncConfig.clearScrollbackAllowed = true
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[26;1H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 25)!
        inject(screen, scrollWholeScreen(27) + "hello")
        XCTAssertEqual(imageCode(screen, x: 0, y: 1), code, "premise: the bottom row should be on screen")

        inject(screen, "\u{1b}[3J")
        inject(screen, "\u{1b}[20;1Hworld")
        assertStillInBuffer(screen, code: code, inHistory: false)
        XCTAssertTrue(isRegistered(code), "an image still on screen must not be released")
    }

    /// Clearing scrollback discards the image's rows in history. Once its rows on screen are
    /// drawn over in place, nothing of it is left, so it must be released.
    func testImageDrawnOverAfterClearingScrollbackIsReleased() {
        session.syncConfig.clearScrollbackAllowed = true
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[26;1H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 25)!
        inject(screen, scrollWholeScreen(27) + "hello")
        XCTAssertTrue(imageCodesInHistory(screen).contains(code), "premise: the top rows went into history")

        inject(screen, "\u{1b}[3J")
        inject(screen, overwrite(rows: 0...1))
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "an image with nothing left must be released")
    }

    /// Erase-display moves the screen's contents into history rather than discarding them.
    func testImageMovedIntoHistoryByEraseDisplayIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, "\u{1b}[2J")
        inject(screen, "\u{1b}[20;1Hworld")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "an image moved into history must not be released")
    }

    /// A full reset (RIS) moves the screen's contents into history rather than discarding them.
    func testImageMovedIntoHistoryByResetIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!
        inject(screen, "\u{1b}[30;1H")

        inject(screen, "\u{1b}c")
        inject(screen, "\u{1b}[20;1Hworld")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "an image moved into history must not be released")
    }

    // MARK: - Rows that come back from history

    private func resize(_ screen: VT100Screen, width: Int32, height: Int32) {
        autoreleasepool {
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                mutableState.setSize(VT100GridSizeMake(width, height), delegate: screen.delegate!)
            })
        }
    }

    /// Making the window taller pulls rows back out of history onto the screen. The image must
    /// survive that and a later burst that scrolls it back into history.
    func testImagePulledBackFromHistoryByResizeThenScrolledAgainIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[26;1H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 25)!
        inject(screen, scrollWholeScreen(27) + "hello")

        resize(screen, width: 80, height: 40)
        inject(screen, "\u{1b}[39;1Hworld")
        assertStillInBuffer(screen, code: code, inHistory: false)
        XCTAssertTrue(isRegistered(code), "an image still on screen must not be released")

        inject(screen, scrollWholeScreen(100, height: 40) + "hello")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "an image scrolled into history must not be released")
    }

    /// Making the window narrower reflows the screen. Then a burst scrolls the image into history.
    func testImageReflowedByResizeThenScrolledIntoHistoryIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[11;1H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 10)!

        resize(screen, width: 40, height: 30)
        inject(screen, "\u{1b}[29;1Hworld")
        assertStillInBuffer(screen, code: code)
        XCTAssertTrue(isRegistered(code), "an image still on screen must not be released")

        inject(screen, scrollWholeScreen(100) + "hello")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "an image scrolled into history must not be released")
    }

    /// Folding takes the image's rows out of the buffer and unfolding puts them back.
    func testImageFoldedUnfoldedThenScrolledIntoHistoryIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[6;1H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 5)!
        let top = Int(screenTop(screen))

        let range = NSRange(location: top + 4, length: 7)
        screen.foldAbsLineRange(range)
        screen.waitForQueuedTokensForTesting()
        XCTAssertEqual(linesContaining(screen, code: code), [], "premise: folding should remove the image's rows")
        inject(screen, "\u{1b}[25;1Hworld")
        XCTAssertTrue(isRegistered(code), "a folded image must not be released")

        screen.removeFolds(in: range, completion: nil)
        screen.waitForQueuedTokensForTesting()
        inject(screen, "\u{1b}[26;1Hagain")
        assertStillInBuffer(screen, code: code, inHistory: false)
        XCTAssertTrue(isRegistered(code), "an unfolded image must not be released")

        inject(screen, scrollWholeScreen(100) + "hello")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "an image scrolled into history must not be released")
    }

    // MARK: - Moving the screen through the line buffer and back

    /// Resizing moves the screen into the line buffer and back. An image that stays on screen did
    /// not enter history, so drawing over it afterwards must still release it.
    func testImageDrawnOverAfterResizeIsReleased() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[11;1H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 10)!

        resize(screen, width: 70, height: 30)
        inject(screen, "\u{1b}[29;1Hworld")
        assertStillInBuffer(screen, code: code, inHistory: false)
        XCTAssertEqual(imageCode(screen, x: 0, y: 10), code, "premise: the image should not have moved")

        inject(screen, overwrite(rows: 10...13))
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "an image drawn over after a resize should be released")
    }

    /// Folding moves the screen into the line buffer and back, too. Fold lines in history so the
    /// image stays put below the fold.
    func testImageDrawnOverAfterFoldingOtherLinesIsReleased() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[11;1H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 10)!
        let top = Int(screenTop(screen))

        autoreleasepool {
            screen.foldAbsLineRange(NSRange(location: top - 10, length: 3))
            screen.waitForQueuedTokensForTesting()
        }
        inject(screen, "\u{1b}[25;1Hworld")
        XCTAssertEqual(imageCode(screen, x: 0, y: 10), code, "premise: the image should not have moved")
        XCTAssertLessThan(Int(screenTop(screen)), top, "premise: the fold should have shortened history")

        inject(screen, overwrite(rows: 10...13))
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "an image drawn over after a fold should be released")
    }

    // MARK: - Recording codes that enter history

    private func imageCodesInHistory(_ screen: VT100Screen) -> IndexSet {
        var result = IndexSet()
        autoreleasepool {
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                result = mutableState.imageCodesInHistory
            })
        }
        return result
    }

    /// Shrinking the window leaves the top of the screen in history. Lines appended during a
    /// resize aren't recorded as they go, since most come back, so the scan afterwards must find
    /// the ones that stayed.
    func testImageLeftInHistoryByShrinkingWindowIsRecorded() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4) + "\u{1b}[30;1Hbottom")
        let code = imageCode(screen, x: 0, y: 0)!
        XCTAssertFalse(imageCodesInHistory(screen).contains(code), "premise: the image starts on screen")

        resize(screen, width: 80, height: 20)
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(imageCodesInHistory(screen).contains(code),
                      "an image the resize left in history must be recorded")
    }

    /// A wide character never straddles two rows, so at an odd width a row of them rewraps into
    /// more rows than the width ratio suggests. The scan after a resize must still reach the
    /// image's rows.
    func testImageAboveWideCharactersLeftInHistoryByNarrowingIsRecorded() {
        let screen = makeScreen(width: 10, height: 30)
        var text = "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4)
        for row in 5...30 {
            text += "\u{1b}[\(row);1H" + String(repeating: "中", count: 5)
        }
        inject(screen, text)
        let code = imageCode(screen, x: 0, y: 0)!
        XCTAssertFalse(imageCodesInHistory(screen).contains(code), "premise: the image starts on screen")

        // At width 3, each row of five wide characters needs five rows, not ceil(10 / 3) = 4.
        resize(screen, width: 3, height: 10)
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(imageCodesInHistory(screen).contains(code),
                      "an image the resize left in history must be recorded")
    }

    /// Unfolding a fold that has scrolled into history puts its lines, image and all, straight
    /// into history.
    func testImageUnfoldedIntoHistoryIsRecorded() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[6;1H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 5)!
        let top = Int(screenTop(screen))
        let range = NSRange(location: top + 4, length: 7)
        screen.foldAbsLineRange(range)
        screen.waitForQueuedTokensForTesting()
        XCTAssertEqual(linesContaining(screen, code: code), [], "premise: folding should remove the image's rows")
        inject(screen, scrollWholeScreen(100) + "hello")
        XCTAssertFalse(imageCodesInHistory(screen).contains(code),
                       "premise: the folded image's rows never scrolled into history")

        screen.removeFolds(in: range, completion: nil)
        screen.waitForQueuedTokensForTesting()
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(imageCodesInHistory(screen).contains(code),
                      "an image unfolded into history must be recorded")
        XCTAssertTrue(isRegistered(code))
    }

    /// A new image may reuse the code of a released one. An entry left over for the old image
    /// must not keep the new one alive, so writing an image clears its code from the record.
    func testWritingImageClearsItsCodeFromHistoryRecord() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!
        inject(screen, scrollWholeScreen(100) + "hello")
        XCTAssertTrue(imageCodesInHistory(screen).contains(code), "premise: the code should be recorded")

        // Forcing the registry to hand out the same code again would mean allocating every other
        // code first, so call the hook the image writer calls, as it would for a reused code.
        forgetImageCodeInHistory(screen, code: code)
        XCTAssertFalse(imageCodesInHistory(screen).contains(code))
    }

    /// Calls the hook the image writer calls before writing an image, which removes its code
    /// from the record of codes in history.
    private func forgetImageCodeInHistory(_ screen: VT100Screen, code: Int) {
        let selector = NSSelectorFromString("inlineImageWillWriteImageWithCode:")
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            XCTAssertTrue(mutableState.responds(to: selector), "the image writer's hook was renamed")
            typealias Hook = @convention(c) (AnyObject, Selector, unichar) -> Void
            let hook = unsafeBitCast(mutableState.method(for: selector), to: Hook.self)
            hook(mutableState, selector, unichar(code))
        })
    }

    /// History restored with a session never passed through the grid, so its image codes aren't
    /// in the record. When the rows of such an image that are still on screen get drawn over, the
    /// release scan must still find its rows in history, within max(its height, the screen's
    /// height) lines above its mark.
    func testImagePartlyInUnrecordedHistoryDrawnOverOnScreenIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[26;1H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 25)!

        // Scroll the top two rows of the image into history, leaving the bottom two on rows 0 and 1.
        inject(screen, scrollWholeScreen(27) + "hello")
        XCTAssertEqual(imageCode(screen, x: 0, y: 1), code, "premise: the bottom row should still be on screen")

        // Leave the record as a restored session would have it.
        forgetImageCodeInHistory(screen, code: code)
        XCTAssertFalse(imageCodesInHistory(screen).contains(code), "premise: the code should not be recorded")

        inject(screen, overwrite(rows: 0...1))
        XCTAssertEqual(linesContaining(screen, code: code).filter { $0 >= screenTop(screen) }, [],
                       "premise: the image's rows on screen should all be drawn over")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "an image with rows left in history must not be released")
    }

    /// Reading the screen appends the live grid to a copy of the line buffer when threads are
    /// joined. That copy isn't history, so it must not keep the image from being released once
    /// it's drawn over.
    func testCountingRawLinesWithThreadsJoinedDoesNotKeepImage() {
        let screen = makeScreen()
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!
        autoreleasepool {
            screen.performBlock(joinedThreads: { _, _, _ in
                _ = screen.numberOfRawLines(in: VT100GridRange(location: 0, length: 30))
            })
        }
        XCTAssertFalse(imageCodesInHistory(screen).contains(code))

        inject(screen, overwrite(rows: 0...3))
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "an image drawn over must be released")
    }

    func testSnapshotOfLiveGridDoesNotKeepImage() {
        let screen = makeScreen()
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!
        autoreleasepool {
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                _ = TerminalContentSnapshot(lineBuffer: mutableState.linebuffer,
                                            grid: mutableState.currentGrid,
                                            cumulativeOverflow: 0)
            })
        }
        XCTAssertFalse(imageCodesInHistory(screen).contains(code))

        inject(screen, overwrite(rows: 0...3))
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "an image drawn over must be released")
    }

    /// Clearing from a line to the end puts back the whole wrapped paragraph the cursor is in,
    /// which can be several rows tall. A row in the middle with image cells must still be marked
    /// as maybe holding an image, or its code isn't recorded when it scrolls into history.
    func testImageInMiddleOfParagraphRestoredByClearToEndIsRecordedInHistory() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        // A paragraph wrapped over rows 10, 11 and 12, with an image one row tall on row 11.
        inject(screen, "\u{1b}[11;1H" + String(repeating: "a", count: 200) + "\u{1b}7"
               + "\u{1b}[12;1H" + imageSequence(widthInCells: 10, heightInCells: 1) + "\u{1b}8")
        let code = imageCode(screen, x: 0, y: 11)!
        var softWrapped = false
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            softWrapped = grid.screenChars(atLineNumber: 10)[80].code == unichar(EOL_SOFT) &&
                grid.screenChars(atLineNumber: 11)[80].code == unichar(EOL_SOFT)
        })
        XCTAssertTrue(softWrapped, "premise: rows 10 through 12 should be one wrapped paragraph")

        // Clear from row 11 (the cursor is on row 12), so the paragraph comes back starting on
        // row 11 and the image's cells land on row 12, neither its first nor its last row.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.clearFromAbsoluteLine(toEnd: mutableState.cumulativeScrollbackOverflow
                                               + Int64(mutableState.numberOfScrollbackLines) + 11)
        })
        let top = screenTop(screen)
        XCTAssertEqual(linesContaining(screen, code: code), [top + 12],
                       "premise: the image should be on the paragraph's middle row")

        inject(screen, scrollWholeScreen(40) + "hello")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(imageCodesInHistory(screen).contains(code),
                      "the image's row must be recorded when it scrolls into history")
        XCTAssertTrue(isRegistered(code))
    }

    /// With a full scrollback, the release scan must find the images that were at the top of the
    /// screen at the last sync. It once mixed the old scrollback size with the new overflow, which
    /// skipped them whenever lines scrolled, so an image drawn over and then scrolled leaked.
    func testImageDrawnOverThenScrolledWithFullScrollbackIsReleased() {
        let screen = makeScreen(maxScrollbackLines: 200)
        addOlderMarks(screen, count: 5)
        inject(screen, String(repeating: "y\r\n", count: 300))
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, overwrite(rows: 0...3) + scrollWholeScreen(10) + "hello")
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "an image drawn over before it scrolled should be released")
    }

    // MARK: - Lines restored by appending saved cells

    /// Filter results, clearing to the end of the buffer, and copying another session's contents
    /// append saved lines through appendScreenChars. Lines holding images must be flagged so they
    /// are recorded when they scroll into history.
    func testImageAppendedFromSavedLinesThenScrolledIntoHistoryIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        autoreleasepool {
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                let top = mutableState.numberOfScrollbackLines
                let saved = (0..<4).map { mutableState.screenCharArray(forLine: top + Int32($0)).copy() as! ScreenCharArray }
                XCTAssertTrue(saved.allSatisfy { $0.metadata.imageFound.boolValue },
                              "premise: lines with image cells should be flagged")
                mutableState.currentGrid.cursor = VT100GridCoordMake(0, 10)
                for sca in saved {
                    mutableState.appendScreenChars(sca.line,
                                                   length: sca.length,
                                                   externalAttributeIndex: nil,
                                                   continuation: sca.continuation,
                                                   rtlFound: false,
                                                   imageFound: sca.metadata.imageFound.boolValue,
                                                   lineAttribute: .singleWidth)
                }
            })
        }
        XCTAssertEqual(imageCode(screen, x: 0, y: 10), code, "premise: the copy should be on rows 10-13")

        // Draw over the original and scroll the copy, which lies below the image's mark, into
        // history.
        inject(screen, overwrite(rows: 0...3) + scrollWholeScreen(100) + "hello")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "a copy in history must keep the image")
    }

    // MARK: - Partial-width moves

    /// With left and right margins, scrolling a region moves only part of each row. The image's
    /// rows must still be flagged where they land, here below the image's mark, so a burst that
    /// scrolls them into history records them.
    func testImageMovedByColumnRegionThenScrolledIntoHistoryIsKept() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4))
        let code = imageCode(screen, x: 0, y: 0)!

        inject(screen, "\u{1b}[?69h\u{1b}[1;40s\u{1b}[1;25r\u{1b}[6T\u{1b}[r\u{1b}[s\u{1b}[?69l")
        XCTAssertEqual(imageCode(screen, x: 0, y: 6), code, "premise: the image should have moved down six rows")
        XCTAssertNil(imageCode(screen, x: 0, y: 0))

        inject(screen, scrollWholeScreen(100) + "hello")
        assertStillInBuffer(screen, code: code, inHistory: true)
        XCTAssertTrue(isRegistered(code), "an image scrolled into history must not be released")
    }

    // MARK: - Removing the last line

    /// Removing the last line (as filtering does) moves the screen into the line buffer and back.
    /// An image that stays on screen must still be released when drawn over.
    func testImageDrawnOverAfterRemovingLastLineIsReleased() {
        let screen = makeScreen()
        addOlderMarks(screen, count: 5)
        inject(screen, "\u{1b}[H" + imageSequence(widthInCells: 10, heightInCells: 4) + "\u{1b}[11;1Hhello")
        let code = imageCode(screen, x: 0, y: 0)!

        autoreleasepool {
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                mutableState.removeLastLine()
            })
        }
        inject(screen, "\u{1b}[20;1Hworld")
        assertStillInBuffer(screen, code: code, inHistory: false)
        XCTAssertFalse(imageCodesInHistory(screen).contains(code),
                       "an image that stayed on screen must not be recorded as in history")
        let top = screenTop(screen)
        let rows = linesContaining(screen, code: code).map { Int($0 - top) }

        inject(screen, overwrite(rows: rows.min()!...rows.max()!))
        assertGoneFromBuffer(screen, code: code)
        XCTAssertFalse(isRegistered(code), "an image drawn over after removing the last line should be released")
    }
}
