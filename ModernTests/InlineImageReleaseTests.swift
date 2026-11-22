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

    private func makeScreen(width: Int32 = 80, height: Int32 = 30) -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        let config = session.syncConfig
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
}
