//
//  ImageProtocolSizeTests.swift
//  iTerm2
//
//  Sizes that a program controls in the kitty graphics protocol and the iTerm2 inline image
//  protocol (OSC 1337 File=). A huge value must not hang the session, crash, or move the cursor to
//  the wrong place.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

final class ImageProtocolSizeTests: XCTestCase {
    private var session = FakeSession()

    // A 64x64 red square encoded as PNG.
    private let redPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAeUlEQVR4nO3PQQkAMAzAwAqrfxUTMxF7HINABFzm7H7dcEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFj108cEE8uoIF1wAAAABJRU5ErkJggg=="

    override func setUp() {
        super.setUp()
        session = FakeSession()
    }

    // MARK: - Helpers

    private struct Outcome: Equatable, CustomStringConvertible {
        var x: Int32
        var y: Int32
        // Lines that have been pushed off the top of the screen, whether still in scrollback or
        // dropped from it.
        var linesScrolledOff: Int64

        var description: String {
            return "cursor=(\(x), \(y)) linesScrolledOff=\(linesScrolledOff)"
        }
    }

    private func makeScreen(width: Int32 = 20,
                            height: Int32 = 15,
                            backingScaleFactor: CGFloat = 1,
                            maxScrollbackLines: Int32 = 1000) -> VT100Screen {
        let config = VT100MutableScreenConfiguration()
        config.sessionGuid = "ImageProtocolSizeTests"
        config.cellSize = NSSize(width: 7, height: 14)
        config.backingScaleFactor = backingScaleFactor
        config.maxScrollbackLines = maxScrollbackLines
        config.unicodeVersion = 9
        config.isDirty = true
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setConfig(config)
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
            mutableState.terminal?.encoding = String.Encoding.utf8.rawValue
            screen.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
        })
        return screen
    }

    private func feed(_ screen: VT100Screen, _ string: String) {
        screen.inject(Data(string.utf8))
        screen.waitForQueuedTokensForTesting()
        // An inline image creates its helper on the mutation queue after a side effect; a join
        // lets that work finish.
        screen.performBlock(joinedThreads: { _, _, _ in })
        screen.waitForQueuedTokensForTesting()
    }

    private func outcome(_ screen: VT100Screen) -> Outcome {
        var result = Outcome(x: -1, y: -1, linesScrolledOff: -1)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            result.x = mutableState.currentGrid.cursor.x
            result.y = mutableState.currentGrid.cursor.y
            result.linesScrolledOff = Int64(mutableState.numberOfScrollbackLines) + mutableState.totalScrollbackOverflow()
        })
        return result
    }

    private func kitty(_ keys: String, payload: String) -> String {
        return "\u{1b}_G\(keys);\(payload)\u{1b}\\"
    }

    /// Displays a 64x64 PNG with the given extra keys, from row 3 of a fresh screen, with the
    /// default cursor policy (move the cursor past the image). The cap tests use a 5x3 screen,
    /// where each line feed is cheap and the cursor starts on the bottom row.
    private func kittyOutcome(_ keys: String, small: Bool = false) -> Outcome {
        let screen = small ? makeScreen(width: 5, height: 3, maxScrollbackLines: 10) : makeScreen()
        feed(screen, "\u{1b}[3;1H")
        feed(screen, kitty("a=T,f=100,t=d,q=2," + keys, payload: redPNGBase64))
        return outcome(screen)
    }

    // MARK: - Kitty: cursor movement after a placement

    func testKittyPlacementMovesCursorDownByItsRows() {
        let result = kittyOutcome("i=1,r=3")
        XCTAssertEqual(result.y, 5)
        XCTAssertEqual(result.linesScrolledOff, 0)
        let tall = kittyOutcome("i=1,r=20")
        XCTAssertEqual(tall.y, 14)
        XCTAssertEqual(tall.linesScrolledOff, 8)
    }

    func testKittyPlacementWithHugeRowCountIsBounded() {
        // Each row the cursor moves past the bottom scrolls one line, so before the bound
        // r=4294967295 meant about 4.3 billion line feeds on the mutation thread.
        // The cursor starts on the bottom row, so every row of the move scrolls one line. The cap
        // is 65535 rows; one run at the largest r shows it, since each run of 65535 line feeds
        // takes a noticeable fraction of a second in a test build.
        let huge = kittyOutcome("i=1,r=4294967295", small: true)
        XCTAssertEqual(huge.y, 2)
        XCTAssertEqual(huge.linesScrolledOff, 65535)
    }

    func testKittyPlacementWithHugeDeclaredHeightIsBounded() {
        // With no r key the placement is as tall as the v key says, in pixels. Cells are 14
        // pixels tall here.
        XCTAssertEqual(kittyOutcome("i=1,s=1,v=4294967295", small: true).linesScrolledOff, 65535)
        XCTAssertEqual(kittyOutcome("i=1,s=1,v=\(14 * 20)", small: true).linesScrolledOff, 20)
        XCTAssertEqual(kittyOutcome("i=1,s=1,v=\(14 * 3)").y, 5)
    }

    // MARK: - Kitty: raw image dimensions

    private final class RecordingKittyDelegate: NSObject, KittyImageControllerDelegate {
        var reports = [String]()
        func kittyImageControllerReport(message: String) {
            reports.append(message)
        }
        func kittyImageControllerPlacementsDidChange() {}
        func kittyImageControllerCursorCoord() -> VT100GridAbsCoord {
            return VT100GridAbsCoord(x: 0, y: 0)
        }
        func kittyImageControllerMoveCursor(dx: Int, dy: Int) {}
        func kittyImageControllerCellSize() -> NSSize {
            return NSSize(width: 10, height: 20)
        }
        func kittyImageControllerScreenAbsLine() -> Int64 {
            return 0
        }
    }

    /// Transmits and displays raw RGB data with the given dimensions and returns the number of
    /// placements that resulted.
    private func rawImagePlacementCount(width: String, height: String) -> Int {
        let delegate = RecordingKittyDelegate()
        let controller = KittyImageController()
        controller.delegate = delegate
        // Three bytes: one RGB pixel.
        let command = KittyImageCommand("a=T,f=24,t=d,i=9,s=\(width),v=\(height);AAAA")!
        controller.execute(command: command)
        withExtendedLifetime(delegate) {}
        return controller.draws().count
    }

    func testKittyRawImageWithHugeDimensionsIsRejected() {
        // bpp * width * height and width * 4 overflowed Int, which traps in Swift.
        XCTAssertEqual(rawImagePlacementCount(width: "4000000000", height: "4000000000"), 0)
        XCTAssertEqual(rawImagePlacementCount(width: "18446744073709551615", height: "1"), 0)
        XCTAssertEqual(rawImagePlacementCount(width: "18446744073709551615", height: "0"), 0)
        XCTAssertEqual(rawImagePlacementCount(width: "4611686018427387904", height: "0"), 0)
        XCTAssertEqual(rawImagePlacementCount(width: "1", height: "1"), 1)
    }

    // MARK: - Inline images

    private func inlineImageCursorX(backingScaleFactor: CGFloat,
                                    screenWidth: Int32 = 20,
                                    startColumn: Int = 1,
                                    arguments: String) -> Int32 {
        return inlineImage(backingScaleFactor: backingScaleFactor,
                           screenWidth: screenWidth,
                           startColumn: startColumn,
                           arguments: arguments).cursorX
    }

    /// Draws an inline image and returns where the cursor ends up and which columns of the
    /// cursor's row (the image's last row) hold image cells.
    private func inlineImage(backingScaleFactor: CGFloat,
                             screenWidth: Int32,
                             startColumn: Int,
                             arguments: String) -> (cursorX: Int32, imageColumns: [Int32]) {
        let screen = makeScreen(width: screenWidth, height: 15, backingScaleFactor: backingScaleFactor)
        feed(screen, "\u{1b}[1;\(startColumn)H")
        feed(screen, "\u{1b}]1337;File=inline=1;\(arguments):\(redPNGBase64)\u{07}")
        var columns = [Int32]()
        var cursorX = Int32(-1)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            cursorX = grid.cursor.x
            for x in 0..<screenWidth where grid.character(at: VT100GridCoord(x: x, y: grid.cursor.y)).image != 0 {
                columns.append(x)
            }
        })
        return (cursorX, columns)
    }

    func testInlineImageWithZeroScaleFactorIsSizedAsScaleOne() {
        // A backing scale factor of 0 divided sizes by zero, so the image filled the line.
        for arguments in ["width=28px;height=28px;preserveAspectRatio=0",
                          "width=auto;height=auto",
                          "width=28px;height=auto"] {
            let atOne = inlineImageCursorX(backingScaleFactor: 1, arguments: arguments)
            XCTAssertLessThan(atOne, 19, arguments)
            XCTAssertEqual(inlineImageCursorX(backingScaleFactor: 0, arguments: arguments), atOne, arguments)
        }
        XCTAssertEqual(inlineImageCursorX(backingScaleFactor: 1,
                                          arguments: "width=28px;height=28px;preserveAspectRatio=0"),
                       4)
    }

    /// The size in cells recorded for the inline image drawn at the cursor's row and the given
    /// column.
    private func inlineImageSizeInCells(screenWidth: Int32 = 20,
                                        startColumn: Int = 1,
                                        arguments: String) -> NSSize? {
        let screen = makeScreen(width: screenWidth, height: 15, backingScaleFactor: 1)
        feed(screen, "\u{1b}[1;\(startColumn)H")
        feed(screen, "\u{1b}]1337;File=inline=1;\(arguments):\(redPNGBase64)\u{07}")
        var size: NSSize?
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            let c = grid.character(at: VT100GridCoord(x: Int32(startColumn - 1), y: grid.cursor.y))
            if c.image != 0 {
                size = ImageRegistry.instance.info(for: Int(c.code))?.size
            }
        })
        return size
    }

    func testInlineImageCappedAt255RowsIsNarrowedInProportion() {
        // Capping the height multiplied the width by height / 255, widening the image instead of
        // shrinking it in proportion as capping the width does.
        XCTAssertEqual(inlineImageSizeInCells(arguments: "width=10;height=510;preserveAspectRatio=0"),
                       NSSize(width: 5, height: 255))
        XCTAssertEqual(inlineImageSizeInCells(arguments: "width=10;height=255;preserveAspectRatio=0"),
                       NSSize(width: 10, height: 255))
    }

    func testInlineImageTooWideForTheRestOfTheLineIsScaledToFit() {
        // With the cursor in column 11 of 20, ten columns remain. The height was scaled to fit
        // them but the width was set to the whole screen's, so the image was clipped.
        XCTAssertEqual(inlineImageSizeInCells(startColumn: 11, arguments: "width=20;height=4;preserveAspectRatio=0"),
                       NSSize(width: 10, height: 2))
        XCTAssertEqual(inlineImageSizeInCells(startColumn: 1, arguments: "width=20;height=4;preserveAspectRatio=0"),
                       NSSize(width: 20, height: 4))
    }

    func testInlineImageWithHugeHeightIsNarrowedWithoutOverflow() {
        // Capping the height at 255 rows used to multiply the width by height / 255, which
        // overflowed int; adding the result to the cursor's column overflowed again. The width
        // now shrinks in proportion instead: 290 * 255 / 2147483647 truncates to 0, so 1 column.
        let huge = inlineImage(backingScaleFactor: 1,
                               screenWidth: 300,
                               startColumn: 11,
                               arguments: "width=290;height=2147483647;preserveAspectRatio=0")
        let large = inlineImage(backingScaleFactor: 1,
                                screenWidth: 300,
                                startColumn: 11,
                                arguments: "width=290;height=256;preserveAspectRatio=0")
        // 290 * 255 / 256 is 288.9, which truncates to 288.
        XCTAssertEqual(large.cursorX, 298)
        XCTAssertEqual(large.imageColumns, Array(10..<298))
        XCTAssertEqual(huge.cursorX, 11)
        XCTAssertEqual(huge.imageColumns, [10])
        XCTAssertEqual(inlineImageCursorX(backingScaleFactor: 1,
                                          screenWidth: 300,
                                          startColumn: 11,
                                          arguments: "width=5;height=2;preserveAspectRatio=0"),
                       15)
    }
}
