//
//  VT100GridTests.swift
//  iTerm2
//
//  Created by George Nachman on 4/29/25.
//

import XCTest
@testable import iTerm2SharedARC

class VT100GridTests: XCTestCase {
    func append(strings: [String], toGrid grid: VT100Grid, lineBuffer: LineBuffer) {
        for string in strings {
            let strippedString: String
            let newline = string.hasSuffix("\n")
            if newline {
                strippedString = String(string.dropLast())

            } else {
                strippedString = string
            }
            let eol: Int32
            if newline {
                eol = EOL_HARD
            } else if string.hasSuffix(">") {
                eol = EOL_DWC
            } else {
                eol = EOL_SOFT
            }
            let sca = screenCharArrayWithDefaultStyle(strippedString, eol: eol)
            grid.appendChars(atCursor: sca.line,
                             length: sca.length,
                             scrollingInto: lineBuffer,
                             unlimitedScrollback: true,
                             useScrollbackWithRegion: false,
                             wraparound: true,
                             ansi: false,
                             insert: false,
                             externalAttributeIndex: nil,
                             rtlFound: false,
                             dwcFree: false)
            if newline {
                grid.cursorX = 0
                grid.moveCursorDownOneLineScrolling(into: lineBuffer,
                                                    unlimitedScrollback: true,
                                                    useScrollbackWithRegion: false,
                                                    willScroll: nil,
                                                    sentToLineBuffer: nil)
            }
        }
    }

    func testAppendLineToLineBuffer() {
        let width = Int32(4)
        let grid = VT100Grid(size: VT100GridSize(width: width, height: 4), delegate: nil)!
        let lineBuffer = LineBuffer(blockSize: 1000)

        let linesToAppend = [
            "abcd\n",
            "efgh\n"
        ]
        append(strings: linesToAppend, toGrid: grid, lineBuffer: lineBuffer)
        grid.appendLines(2, to: lineBuffer)
        let expectedLines = [
            "abcd\n",
            "efgh\n"
        ]

        let actualLines = lineBuffer.allWrappedLinesAsStrings(width: width)
        XCTAssertEqual(actualLines, expectedLines)
    }

    func testAppendLinesWithContinuationMarks() {
        let width: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: 4), delegate: nil)!
        let lineBuffer = LineBuffer(blockSize: 1000)

        let linesToAppend = [
            "abcd\n",
            "efghi",
        ]
        append(strings: linesToAppend, toGrid: grid, lineBuffer: lineBuffer)
        grid.appendLines(2, to: lineBuffer)
        let expectedLines = [
            "abcd\n",
            "efgh",
        ]
        let actualLines = lineBuffer.allWrappedLinesAsStrings(width: width)
        XCTAssertEqual(actualLines, expectedLines)
    }

    func testAppendSoftContinuationThenHardEolJoinsIntoOneLine() {
        let width: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: 4), delegate: nil)!
        let lineBuffer = LineBuffer(blockSize: 1000)

        let linesToAppend = [
            "abcdefgh\n"
        ]
        append(strings: linesToAppend, toGrid: grid, lineBuffer: lineBuffer)

        grid.appendLines(2, to: lineBuffer)

        let expectedLines = [
            "abcd",
            "efgh\n",
        ]
        let actualLines = lineBuffer.allWrappedLinesAsStrings(width: width)
        XCTAssertEqual(actualLines, expectedLines)
    }

    func testAppendLinesRespectsCursorPosition() {
        let width: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: 4), delegate: nil)!
        let lineBuffer = LineBuffer(blockSize: 1000)

        // Populate grid with two lines
        let linesToAppend = [
            "abcd\n",
            "efgh\n",
        ]
        append(strings: linesToAppend, toGrid: grid, lineBuffer: lineBuffer)

        // Move cursor to (2, 1) (third column on second line)
        grid.cursorX = 2
        grid.cursorY = 1

        // Append the first two grid lines into the buffer
        grid.appendLines(2, to: lineBuffer)

        // Verify that the cursor position is preserved in the last buffered line
        var x: Int32 = 0
        XCTAssertTrue(lineBuffer.getCursorInLastLine(withWidth: width, atX: &x))
        XCTAssertEqual(x, 2)
    }

    func testCursorHoistedFromBlankLineAfterSoftEOL() {
        let width: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: 4), delegate: nil)!
        let lineBuffer = LineBuffer(blockSize: 1000)

        // – Row 0: “abcd” with soft‐EOL
        // – Row 1: “efgh” with soft‐EOL
        let initialLines = [
            "abcd",   // no “\n” → soft
            "efghi",   // no “\n” → soft
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: lineBuffer)
        grid.deleteChars(1, startingAt: VT100GridCoord(x: 0, y: 2))

        // Place the cursor at column 0 of the blank line (row 2)
        grid.cursorX = 0
        grid.cursorY = 2

        // Now append the first 2 rows into the buffer
        grid.appendLines(2, to: lineBuffer)

        // The cursor should be hoisted to the end of “efgh”, i.e. column 4
        var x: Int32 = 0
        XCTAssertTrue(lineBuffer.getCursorInLastLine(withWidth: width, atX: &x))
        XCTAssertEqual(x, 4)
    }

    func testLengthOfLineNumber() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)

        // Populate only the first two rows; the rest remain defaultChar
        let linesToAppend = [
            "abcd\n",
            "efg\n"
        ]
        append(strings: linesToAppend, toGrid: grid, lineBuffer: dummyBuffer)

        XCTAssertEqual(grid.length(ofLineNumber: 0), 4)
        XCTAssertEqual(grid.length(ofLineNumber: 1), 3)
        XCTAssertEqual(grid.length(ofLineNumber: 2), 0)
    }

    func testMoveCursorDownOneLineNoScroll() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Load the grid without polluting our test's lineBuffer
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        let lineBuffer = LineBuffer(blockSize: 1000)
        grid.cursorX = 0
        grid.cursorY = 0

        grid.moveCursorDownOneLineScrolling(into: lineBuffer,
                                            unlimitedScrollback: false,
                                            useScrollbackWithRegion: false,
                                            willScroll: { XCTFail("Should not scroll") },
                                            sentToLineBuffer: nil)

        let expected = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expected)
        XCTAssertEqual(lineBuffer.numLines(withWidth: width), 0)
        XCTAssertEqual(grid.cursorX, 0)
        XCTAssertEqual(grid.cursorY, 1)
    }

    func testMoveCursorDownOneLineBelowScrollRegionButAboveLastLine() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill the grid without affecting our test lineBuffer
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        let lineBuffer = LineBuffer(blockSize: 1000)
        grid.scrollRegionRows = VT100GridRange(location: 0, length: 1)
        grid.cursorX = 0
        grid.cursorY = 1

        grid.moveCursorDownOneLineScrolling(into: lineBuffer,
                                            unlimitedScrollback: false,
                                            useScrollbackWithRegion: false,
                                            willScroll: nil,
                                            sentToLineBuffer: nil)

        let expected = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expected)
        XCTAssertEqual(grid.cursorX, 0)
        XCTAssertEqual(grid.cursorY, 2)
    }

    func testMoveCursorDownOneLineWholeScreenScrolls() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill the grid without polluting our test's lineBuffer
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        let lineBuffer = LineBuffer(blockSize: 1000)
        grid.cursorX = 0
        grid.cursorY = 3

        var didScroll = false
        grid.moveCursorDownOneLineScrolling(into: lineBuffer,
                                            unlimitedScrollback: false,
                                            useScrollbackWithRegion: false,
                                            willScroll: { didScroll = true },
                                            sentToLineBuffer: nil)

        XCTAssertTrue(didScroll)

        let expectedGridLines = [
            "efgh\n",
            "ijkl\n",
            "mnop\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedGridLines)

        let buffered = lineBuffer.allWrappedLinesAsStrings(width: width)
        XCTAssertEqual(buffered, ["abcd\n"])

        XCTAssertEqual(grid.cursorX, 0)
        XCTAssertEqual(grid.cursorY, 3)
    }

    func testWholeScreenScrollRespectsSoftEOLs() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill the grid without polluting the test's lineBuffer
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd",    // soft EOL
            "efgh\n",  // hard EOL
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        let lineBuffer = LineBuffer(blockSize: 1000)
        grid.cursorX = 0
        grid.cursorY = 3

        grid.moveCursorDownOneLineScrolling(into: lineBuffer,
                                            unlimitedScrollback: false,
                                            useScrollbackWithRegion: false,
                                            willScroll: nil,
                                            sentToLineBuffer: nil)

        let expectedGrid = [
            "efgh\n",
            "ijkl\n",
            "mnop\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedGrid)

        let buffered = lineBuffer.allWrappedLinesAsStrings(width: width)
        XCTAssertEqual(buffered, ["abcd"])  // soft EOL carried over

        XCTAssertEqual(grid.cursorX, 0)
        XCTAssertEqual(grid.cursorY, 3)
    }

    func testScrollRegionFullWidthAtTopScrollsOnlyRegion() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill the grid without polluting our test's lineBuffer
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        let lineBuffer = LineBuffer(blockSize: 1000)
        grid.scrollRegionRows = VT100GridRange(location: 0, length: 2)
        grid.cursorX = 0
        grid.cursorY = 1

        grid.moveCursorDownOneLineScrolling(into: lineBuffer,
                                            unlimitedScrollback: false,
                                            useScrollbackWithRegion: true,
                                            willScroll: nil,
                                            sentToLineBuffer: nil)

        let expectedGrid = [
            "efgh\n",
            "\n",
            "ijkl\n",
            "mnop\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedGrid)

        let buffered = lineBuffer.allWrappedLinesAsStrings(width: width)
        XCTAssertEqual(buffered, ["abcd\n"])

        XCTAssertEqual(grid.cursorX, 0)
        XCTAssertEqual(grid.cursorY, 1)
    }

    func testMoveCursorDownOneLineRegionScrollWithoutScrollback() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill the grid without affecting our test lineBuffer
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        let lineBuffer = LineBuffer(blockSize: 1000)
        grid.scrollRegionRows = VT100GridRange(location: 0, length: 2)
        grid.cursorX = 0
        grid.cursorY = 1

        grid.moveCursorDownOneLineScrolling(into: lineBuffer,
                                            unlimitedScrollback: false,
                                            useScrollbackWithRegion: false,
                                            willScroll: nil,
                                            sentToLineBuffer: nil)

        let expectedGrid = [
            "efgh\n",
            "\n",
            "ijkl\n",
            "mnop\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedGrid)
        XCTAssertEqual(lineBuffer.numLines(withWidth: width), 0)
        XCTAssertEqual(grid.cursorX, 0)
        XCTAssertEqual(grid.cursorY, 1)
    }

    func testWholeScreenScrollWithMaxLinesDropsOldLines() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill grid without polluting test lineBuffer
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        let lineBuffer = LineBuffer(blockSize: 1000)
        lineBuffer.setMaxLines(1)
        grid.cursorX = 0
        grid.cursorY = 3

        var dropped = Int32(0)
        for _ in 0..<3 {
            dropped += grid.moveCursorDownOneLineScrolling(
                into: lineBuffer,
                unlimitedScrollback: false,
                useScrollbackWithRegion: false,
                willScroll: nil,
                sentToLineBuffer: nil
            )
        }

        XCTAssertEqual(dropped, 2)

        let expectedGrid = [
            "mnop\n",
            "\n",
            "\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedGrid)

        let buffered = lineBuffer.allWrappedLinesAsStrings(width: width)
        XCTAssertEqual(buffered, ["ijkl\n"])

        XCTAssertEqual(grid.cursorX, 0)
        XCTAssertEqual(grid.cursorY, 3)
    }

    func testScrollRegionWithRowsAndColsScrollsWithinRegionOnly() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill the grid without affecting our test's lineBuffer
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        let lineBuffer = LineBuffer(blockSize: 1000)
        grid.scrollRegionRows = VT100GridRange(location: 1, length: 2)
        grid.scrollRegionCols = VT100GridRange(location: 1, length: 2)
        grid.useScrollRegionCols = true
        grid.cursorX = 1
        grid.cursorY = 2

        grid.moveCursorDownOneLineScrolling(into: lineBuffer,
                                            unlimitedScrollback: false,
                                            useScrollbackWithRegion: true,
                                            willScroll: nil,
                                            sentToLineBuffer: nil)

        let expected = [
            "abcd\n",
            "ejkh\n",
            "i\0\0l\n",
            "mnop\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expected)
        XCTAssertEqual(lineBuffer.numLines(withWidth: width), 0)
        XCTAssertEqual(grid.cursorX, 1)
        XCTAssertEqual(grid.cursorY, 2)
    }

    private func smallGrid() -> VT100Grid {
        return VT100Grid(size: VT100GridSize(width: 2, height: 2), delegate: nil)
    }

    private func mediumGrid() -> VT100Grid {
        return VT100Grid(size: VT100GridSize(width: 4, height: 4), delegate: nil)
    }

    private func largeGrid() -> VT100Grid {
        return VT100Grid(size: VT100GridSize(width: 8, height: 8), delegate: nil)
    }

    func testMoveCursorLeft_DefaultBehavior() {
        let grid = mediumGrid()
        grid.cursorX = 1
        grid.cursorY = 0

        grid.moveCursorLeft(1)
        XCTAssertEqual(grid.cursorX, 0)
        XCTAssertEqual(grid.cursorY, 0)

        grid.moveCursorLeft(1)
        XCTAssertEqual(grid.cursorX, 0)
        XCTAssertEqual(grid.cursorY, 0)
    }

    func testMoveCursorLeft_AtScrollRegionLeftEdge_DoesNotMove() {
        let grid = mediumGrid()
        grid.scrollRegionCols = VT100GridRange(location: 1, length: 2)
        grid.useScrollRegionCols = true
        grid.cursorX = 1

        grid.moveCursorLeft(1)
        XCTAssertEqual(grid.cursorX, 1)
    }

    func testMoveCursorLeft_WithinScrollRegion_MovesLeft() {
        let grid = mediumGrid()
        grid.scrollRegionCols = VT100GridRange(location: 1, length: 2)
        grid.useScrollRegionCols = true
        grid.cursorX = 2

        grid.moveCursorLeft(1)
        XCTAssertEqual(grid.cursorX, 1)
    }

    func testMoveCursorLeft_OutsideScrollRegion_MovesNormally() {
        let grid = mediumGrid()
        grid.scrollRegionCols = VT100GridRange(location: 1, length: 2)
        grid.useScrollRegionCols = true
        grid.cursorX = 3

        grid.moveCursorLeft(1)
        XCTAssertEqual(grid.cursorX, 2)
    }

    func testMoveCursorLeftWrappingAroundSoftEOL() {
        let grid = mediumGrid()
        let initialLines = [
            "abcdef"
        ]
        let dummyBuffer = LineBuffer(blockSize: 1000)
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        let expected = [
            "abcd",
            "ef\n",
            "\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expected)
        XCTAssertEqual(grid.cursorX, 2)
        XCTAssertEqual(grid.cursorY, 1)

        grid.moveCursorLeft(4)
        XCTAssertEqual(grid.cursorX, 2)
        XCTAssertEqual(grid.cursorY, 0)
    }

    func testMoveCursorLeftWrappingAroundDoubleWideCharEOL() {
        // 3×3 grid
        let grid = VT100Grid(size: VT100GridSize(width: 3, height: 3), delegate: nil)!
        let lineBuffer = LineBuffer(blockSize: 1000)

        // "abc-" → 'c' is double-width, '-' is the DWC_RIGHT placeholder
        let sca = screenCharArrayWithDefaultStyle("abc-", eol: EOL_SOFT)
        grid.appendChars(atCursor: sca.line,
                         length: sca.length,
                         scrollingInto: lineBuffer,
                         unlimitedScrollback: true,
                         useScrollbackWithRegion: false,
                         wraparound: true,
                         ansi: false,
                         insert: false,
                         externalAttributeIndex: nil,
                         rtlFound: false,
                         dwcFree: false)

        // After wraparound:
        // Row 0: 'a','b', empty
        // Row 1: 'c','-',(empty)
        // Row 2: blank hard-EOL
        let expectedBefore = [
            "ab>>",
            "c-\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedBefore)
        XCTAssertEqual(grid.cursorX, 2)
        XCTAssertEqual(grid.cursorY, 1)

        // Move left 4 places, wrapping across the soft-EOL
        grid.moveCursorLeft(4)
        XCTAssertEqual(grid.cursorX, 1)
        XCTAssertEqual(grid.cursorY, 0)
    }

    func testMoveCursorLeftNotWrappingAroundHardEOL() {
        let grid = mediumGrid()
        let lineBuffer = LineBuffer(blockSize: 1000)

        // Append “abc”
        append(strings: ["abc"], toGrid: grid, lineBuffer: lineBuffer)

        // Move down one line
        grid.moveCursorDownOneLineScrolling(into: lineBuffer,
                                            unlimitedScrollback: true,
                                            useScrollbackWithRegion: false,
                                            willScroll: nil,
                                            sentToLineBuffer: nil)
        // Reset cursorX to 0
        grid.cursorX = 0

        // Append “d” (soft‐EOL) on row 1
        append(strings: ["d"], toGrid: grid, lineBuffer: lineBuffer)

        let expected = [
            "abc\n",
            "d\n",
            "\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expected)
        XCTAssertEqual(grid.cursorX, 1)
        XCTAssertEqual(grid.cursorY, 1)

        // Move left 4 cells; should stop at hard‐EOL boundary on row 1
        grid.moveCursorLeft(4)
        XCTAssertEqual(grid.cursorX, 0)
        XCTAssertEqual(grid.cursorY, 1)
    }

    func testMoveCursorRight_DefaultBehavior() {
        let grid = mediumGrid()
        grid.cursorX = 2
        grid.cursorY = 0

        grid.moveCursorRight(1)
        XCTAssertEqual(grid.cursorX, 3)
        XCTAssertEqual(grid.cursorY, 0)
    }

    func testMoveCursorRight_WithScrollRegion_NoScrollbackBeforeRegion() {
        let grid = mediumGrid()
        grid.scrollRegionCols = VT100GridRange(location: 2, length: 1)
        grid.useScrollRegionCols = true
        grid.cursorX = 0

        grid.moveCursorRight(1)
        XCTAssertEqual(grid.cursorX, 1)
    }

    func testMoveCursorRight_WithScrollRegion_EnteringRegion() {
        let grid = mediumGrid()
        grid.scrollRegionCols = VT100GridRange(location: 2, length: 1)
        grid.useScrollRegionCols = true
        grid.cursorX = 1

        grid.moveCursorRight(1)
        XCTAssertEqual(grid.cursorX, 2)
    }

    func testMoveCursorRight_WithScrollRegion_AtRegionEnd_NoMove() {
        let grid = mediumGrid()
        grid.scrollRegionCols = VT100GridRange(location: 2, length: 1)
        grid.useScrollRegionCols = true
        grid.cursorX = 2

        grid.moveCursorRight(1)
        XCTAssertEqual(grid.cursorX, 2)
    }

    func testMoveCursorUp_DefaultBehavior() {
        let grid = mediumGrid()
        grid.cursorX = 0
        grid.cursorY = 2

        grid.moveCursorUp(1)
        XCTAssertEqual(grid.cursorY, 1)

        grid.moveCursorUp(1)
        XCTAssertEqual(grid.cursorY, 0)

        grid.moveCursorUp(1)
        XCTAssertEqual(grid.cursorY, 0)
    }

    func testMoveCursorUp_ClampsAtScrollRegionTop() {
        let grid = mediumGrid()
        grid.scrollRegionRows = VT100GridRange(location: 1, length: 2)
        grid.cursorY = 2

        grid.moveCursorUp(1)
        XCTAssertEqual(grid.cursorY, 1)

        grid.moveCursorUp(1)
        XCTAssertEqual(grid.cursorY, 1)
    }

    func testMoveCursorUp_AboveScrollTop_DoesNotClamp() {
        let grid = mediumGrid()
        grid.scrollRegionRows = VT100GridRange(location: 2, length: 2)
        grid.cursorY = 1

        grid.moveCursorUp(1)
        XCTAssertEqual(grid.cursorY, 0)
    }

    func testMoveCursorDown_DefaultBehavior() {
        let grid = mediumGrid()
        grid.cursorX = 0
        grid.cursorY = 2

        grid.moveCursorDown(1)
        XCTAssertEqual(grid.cursorY, 3)

        grid.moveCursorDown(1)
        XCTAssertEqual(grid.cursorY, 3)
    }

    func testMoveCursorDown_ClampsAtScrollRegionBottom() {
        let grid = mediumGrid()
        grid.scrollRegionRows = VT100GridRange(location: 1, length: 2)
        grid.cursorX = 0
        grid.cursorY = 1

        grid.moveCursorDown(1)
        XCTAssertEqual(grid.cursorY, 2)

        grid.moveCursorDown(1)
        XCTAssertEqual(grid.cursorY, 2)
    }

    func testMoveCursorDown_BelowScrollRegion_DoesNotClamp() {
        let grid = mediumGrid()
        grid.scrollRegionRows = VT100GridRange(location: 0, length: 2)
        grid.cursorX = 0
        grid.cursorY = 2

        grid.moveCursorDown(1)
        XCTAssertEqual(grid.cursorY, 3)

        grid.moveCursorDown(1)
        XCTAssertEqual(grid.cursorY, 3)
    }

    func testScrollUpIntoLineBuffer() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill the grid without polluting our test's lineBuffer
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        let lineBuffer = LineBuffer(blockSize: 1000)
        grid.scrollUp(into: lineBuffer,
                      unlimitedScrollback: false,
                      useScrollbackWithRegion: true,
                      softBreak: false,
                      sentToLineBuffer: nil)

        let expectedGrid = [
            "efgh\n",
            "ijkl\n",
            "mnop\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedGrid)

        let buffered = lineBuffer.allWrappedLinesAsStrings(width: width)
        XCTAssertEqual(buffered, ["abcd\n"])
    }


    func testScrollUpIntoLineBuffer_DroppedLinesCount() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill grid without affecting our test's lineBuffer
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        let lineBuffer = LineBuffer(blockSize: 1000)
        lineBuffer.setMaxLines(1)

        // First scrollUp: buffer fits one line, so no dropped lines
        var dropped = grid.scrollUp(into: lineBuffer,
                                    unlimitedScrollback: false,
                                    useScrollbackWithRegion: true,
                                    softBreak: false,
                                    sentToLineBuffer: nil)
        XCTAssertEqual(dropped, 0)

        // Second scrollUp: buffer overflows, oldest line dropped
        dropped = grid.scrollUp(into: lineBuffer,
                                unlimitedScrollback: false,
                                useScrollbackWithRegion: true,
                                softBreak: false,
                                sentToLineBuffer: nil)
        XCTAssertEqual(dropped, 1)

        // After two scrolls, grid should show rows 2 & 3 at top
        let expectedGrid = [
            "ijkl\n",
            "mnop\n",
            "\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedGrid)

        // LineBuffer should contain only the second scrolled line ("efgh\n")
        let buffered = lineBuffer.allWrappedLinesAsStrings(width: width)
        XCTAssertEqual(buffered, ["efgh\n"])
    }

    func testScrollUpIntoLineBuffer_HorizontalRegion_NoScrollback() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill the grid without polluting the test's lineBuffer
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        let lineBuffer = LineBuffer(blockSize: 1000)
        grid.scrollRegionCols = VT100GridRange(location: 1, length: 2)
        grid.useScrollRegionCols = true

        let dropped = grid.scrollUp(into: lineBuffer,
                                    unlimitedScrollback: false,
                                    useScrollbackWithRegion: true,
                                    softBreak: false,
                                    sentToLineBuffer: nil)
        XCTAssertEqual(dropped, 0)

        let expected = [
            "afgd\n",
            "ejkh\n",
            "inol\n",
            "m\0\0p\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expected)
        XCTAssertEqual(lineBuffer.numLines(withWidth: width), 0)
    }

    func testScrollWholeScreenUpIntoLineBuffer_DroppedLinesCountAndContent() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!

        // Prefill the grid without polluting our test lineBuffer
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        // Mark a character dirty so timestamps change (exercise code path)
        grid.markCharDirty(true,
                           at: VT100GridCoord(x: 2, y: 2),
                           updateTimestamp: true)

        let lineBuffer = LineBuffer(blockSize: 1000)
        lineBuffer.setMaxLines(1)

        // First full‐screen scroll: should return 0 dropped (buffer has room)
        var dropped = grid.scrollWholeScreenUp(into: lineBuffer,
                                               unlimitedScrollback: false)
        XCTAssertEqual(dropped, 0)

        // After first scroll, top line ("abcd") moved off
        let expectedAfterFirst = [
            "efgh\n",
            "ijkl\n",
            "mnop\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedAfterFirst)

        // Mutate line 3 to "qrst"
        grid.set(line: 3, to: "qrst")

        // Second scroll: buffer overflows maxLines, so 1 line is dropped
        dropped = grid.scrollWholeScreenUp(into: lineBuffer,
                                           unlimitedScrollback: false)
        XCTAssertEqual(dropped, 1)

        // Grid now starts at line 2
        let expectedAfterSecond = [
            "ijkl\n",
            "mnop\n",
            "qrst\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedAfterSecond)

        // The lineBuffer should contain the second‐scrolled line: "efgh\n"
        let buffered = lineBuffer.allWrappedLinesAsStrings(width: width)
        XCTAssertEqual(buffered, ["efgh\n"])
    }

    func testScrollRectDownBy_ZeroDoesNothingAndMarksAllCellsDirty() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Load the grid with hard‐EOL lines
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 2, height: 2)
        grid.scroll(rect, downBy: 0, softBreak: false)

        // Content should be unchanged
        let expectedGrid = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedGrid)
        XCTAssertEqual(grid.dirtyIndexes, IndexSet())
    }

    func testScrollRectDownBy_One_MarksRegionLinesDirty() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill the grid without causing scroll
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 2, height: 2)
        grid.scroll(rect, downBy: 1, softBreak: false)

        let expectedContent = [
            "abcd\n",
            "e\0\0h\n",
            "ifgl\n",
            "mnop\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)

        // Only the rows within the scrolled region (1 and 2) should be marked dirty
        let expectedDirty = IndexSet([1, 2])
        XCTAssertEqual(grid.dirtyIndexes, expectedDirty)
    }

    func testScrollRectDownBy_NegativeOne_MarksRegionLinesDirty() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill grid without causing a scroll
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        // Start with everything clean
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 2, height: 2)
        grid.scroll(rect, downBy: -1, softBreak: false)

        let expected = [
            "abcd\n",
            "ejkh\n",
            "i\0\0l\n",
            "mnop\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expected)

        // Only the two rows in the region should be marked dirty
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([1, 2]))
    }

    func testScrollRectDownBy_Two_MarksRegionLinesDirty() {
        let width: Int32 = 5
        let height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill the grid without causing scroll
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let largerValue = [
            "abcde\n",
            "fghij\n",
            "klmno\n",
            "pqrst\n",
            "uvwxy"
        ]
        append(strings: largerValue, toGrid: grid, lineBuffer: dummyBuffer)
        // Start with everything clean
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: 2, softBreak: false)

        let expectedContent = [
            "abcde\n",
            "f\0\0\0j\n",
            "k\0\0\0o\n",
            "pghit\n",
            "uvwxy\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)

        // Only the rows within the scrolled region (1, 2, 3) should be dirty
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([1, 2, 3]))
    }

    func testScrollRectDownBy_NegativeTwo_MarksRegionLinesDirty() {
        let width: Int32 = 5, height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let largerValue = [
            "abcde\n",
            "fghij\n",
            "klmno\n",
            "pqrst\n",
            "uvwxy"
        ]
        append(strings: largerValue, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: -2, softBreak: false)

        let expected = [
            "abcde\n",
            "fqrsj\n",
            "k\0\0\0o\n",
            "p\0\0\0t\n",
            "uvwxy\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expected)
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([1, 2, 3]))
    }

    func testScrollRectDownBy_Height_EqualsRegionHeight_MarksRegionLinesDirty() {
        let width: Int32 = 5, height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let largerValue = [
            "abcde\n",
            "fghij\n",
            "klmno\n",
            "pqrst\n",
            "uvwxy"
        ]
        append(strings: largerValue, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: 3, softBreak: false)

        let expected = [
            "abcde\n",
            "f\0\0\0j\n",
            "k\0\0\0o\n",
            "p\0\0\0t\n",
            "uvwxy\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expected)
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([1, 2, 3]))
    }

    func testScrollRectDownBy_NegativeHeight_EqualsRegionHeight_MarksRegionLinesDirty() {
        let width: Int32 = 5, height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let largerValue = [
            "abcde\n",
            "fghij\n",
            "klmno\n",
            "pqrst\n",
            "uvwxy"
        ]
        append(strings: largerValue, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: -3, softBreak: false)

        let expected = [
            "abcde\n",
            "f\0\0\0j\n",
            "k\0\0\0o\n",
            "p\0\0\0t\n",
            "uvwxy\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expected)
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([1, 2, 3]))
    }

    func testScrollRectDownBy_GreaterThanRegionHeight_MarksRegionLinesDirty() {
        let width: Int32 = 5, height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let largerValue = [
            "abcde\n",
            "fghij\n",
            "klmno\n",
            "pqrst\n",
            "uvwxy"
        ]
        append(strings: largerValue, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: 4, softBreak: false)

        let expected = [
            "abcde\n",
            "f\0\0\0j\n",
            "k\0\0\0o\n",
            "p\0\0\0t\n",
            "uvwxy\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expected)
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([1, 2, 3]))
    }

    func testScrollRectDownBy_NegativeGreaterThanRegionHeight_MarksRegionLinesDirty() {
        let width: Int32 = 5, height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let largerValue = [
            "abcde\n",
            "fghij\n",
            "klmno\n",
            "pqrst\n",
            "uvwxy"
        ]
        append(strings: largerValue, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: -4, softBreak: false)

        let expectedContent = [
            "abcde\n",
            "f\0\0\0j\n",
            "k\0\0\0o\n",
            "p\0\0\0t\n",
            "uvwxy\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([1, 2, 3]))
    }

    func testScrollRectDownBy_NegativeOne_CleansUpBrokenSplitDwc() {
        let width: Int32 = 3, height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill the grid without causing a scroll
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abc-defg-h"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        // Start with everything clean
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 0, y: 1, width: 3, height: 2)
        grid.scroll(rect, downBy: -1, softBreak: false)

        // The broken EOL_DWC placeholders at rows 0 and 1 should be cleaned up ('.'),
        // blank row inserted at row 2, and the intact DWC_RIGHT at row 3 should remain.
        let expected = [
            "ab\n",
            "ef\n",
            "\n",
            "g-h\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expected)

        // Only the two rows in the scrolled region (1 and 2) should be marked dirty
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([1, 2]))
    }

    func testScrollRectDownBy_One_CleansSplitDWCAtTop() {
        let width: Int32 = 3
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)

        // Initial lines:
        // Row 0: "ab>" (split EOL_DWC placeholder)
        // Row 1: "c-d" (DWC_RIGHT placeholder)
        // Row 2: "efg" (soft‐EOL)
        // Row 3: blank hard‐EOL
        let initialLines = [
            "abc-d\n",
            "efg"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        // Ensure we start with a clean dirty state
        grid.markAllCharsDirty(false, updateTimestamps: false)

        // Scroll rectangle x=0,y=1,width=3,height=2 down by 1
        let rect = VT100GridRect(x: 0, y: 1, width: 3, height: 2)
        grid.scroll(rect, downBy: 1, softBreak: false)

        // After scroll:
        // Row 0: the broken split‐DWC at top is cleaned up → "ab."
        // Row 1: new blank line in region → "\n"
        // Row 2: inherits old row1 → "c-d\n"
        // Row 3: unchanged blank hard‐EOL → "\n"
        let expectedContent = [
            "ab\n",
            "\n",
            "c-d\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)

        // Only the two rows in the region (1 and 2) should be marked dirty
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([1, 2]))
    }

    func testScrollRectDownBy_NegativeOne_FullRegion_CleansSplitDwc() {
        let width: Int32 = 3
        let height: Int32 = 3
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)

        // Initial content:
        // Row 0: "abc\n"
        // Row 1: "de>\n"  // '>' = split EOL_DWC placeholder
        // Row 2: "f-g"   // '-' = DWC_RIGHT placeholder, soft EOL
        let initialLines = [
            "abc\n",
            "def-g"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        // Start with clean dirty state
        grid.markAllCharsDirty(false, updateTimestamps: false)

        // Scroll the entire 3×3 region up by 1 (downBy: -1)
        let rect = VT100GridRect(x: 0, y: 0, width: 3, height: 3)
        grid.scroll(rect, downBy: -1, softBreak: false)

        // After scroll:
        // Row 0 <- old Row 1 ("de>\n")
        // Row 1 <- old Row 2 ("f-g" + implied "\n")
        // Row 2 <- blank hard EOL
        let expected = [
            "de>>",
            "f-g\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expected)

        // All rows in the region (0,1,2) should be marked dirty
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([0, 1, 2]))
    }

    func testScrollRectDownBy_NegativeOne_CleansUpOrphanedSplitDWCAndMarksDirty() {
        let width: Int32 = 5
        let height: Int32 = 6
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcde\n",
            "f-gh-\n",
            "ij-k>\n",
            "l-mno\n",
            "p-qr-\n",
            "stuvw"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)

        // Start with a clean dirty state
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 0, width: 3, height: 6)
        grid.scroll(rect, downBy: -1, softBreak: false)

        let expectedContent = [
            "a\0g\0e\n",
            "\0j-k\n",
            "i\0mn\n",
            "\0\0q\0o\n",
            "\0tuv\n",
            "s\0\0\0w\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)

        // All rows in the region (0 through 5) should be marked dirty
        XCTAssertEqual(grid.dirtyIndexes, IndexSet(0..<6))
    }

    func testScrollRectDownBy_NegativeOne_EdgeCaseSplitDwcOrphans() {
        let width: Int32 = 5, height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd" +   // split‐DWC at end of row 0
            "e-fgh\n",  // 'f-' and 'h-' orphaned
            "ijklm\n",  // intact
            "nopq" +  // split‐DWC at end of row 3
            "r-stu"     // soft EOL
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 0, y: 1, width: 5, height: 3)
        grid.scroll(rect, downBy: -1, softBreak: false)

        let expectedContent = [
            "abcd\n",
            "ijklm\n",
            "nopq\n",
            "\n",
            "r-stu\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)

        // Only rows 1, 2, 3 (the scrolled region) are dirty
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([1, 2, 3]))
    }

    func testScrollRectDownBy_NegativeOne_RegionFromCol1ToRightMargin_CleansSplitDwcAndMarksDirty() {
        let width: Int32 = 5
        let height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)

        // edgeCaseyOrphans initial lines:
        // Row 0: "abcd>" + next-line start → "abcd" + "e-fgh\n"
        // Row 1: "ijklm\n"
        // Row 2: next split at row 3 → "nopq" + "r-stu"
        let initialLines = [
            "abcd" +
            "e-fgh\n",
            "ijklm\n",
            "nopq" +
            "r-stu"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 0, width: 4, height: 5)
        grid.scroll(rect, downBy: -1, softBreak: false)

        let expectedContent = [
            "a\0fgh\n",
            "\0jklm\n",
            "iopq\n",
            "n\0stu\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
        XCTAssertEqual(grid.dirtyIndexes, IndexSet(0..<5))
    }

    func testScrollRectDownBy_NegativeOneEdgeCaseOrphans() {
        let width: Int32 = 5
        let height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Load the “edge case” pattern into the grid
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let edgeCaseOrphans = [
            "abcd" +
            "e-fgh\n",
            "ijklm\n",
            "nopq" +
            "r-stu"
        ]
        append(strings: edgeCaseOrphans, toGrid: grid, lineBuffer: dummyBuffer)

        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 0, y: 0, width: 4, height: 5)
        grid.scroll(rect, downBy: -1, softBreak: false)

        let expectedContent = [
            "e-fg\n",
            "ijklh\n",
            "nopqm\n",
            "r-st\n",
            "\0\0\0\0u\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
        XCTAssertEqual(grid.dirtyIndexes, IndexSet(0..<5))
    }

    func testScrollRectDownBy_EmptyRectIsHarmless() {
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Prefill the grid without causing a scroll
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        // Start with all lines clean
        grid.markAllCharsDirty(false, updateTimestamps: false)

        // Empty rect → no-op
        let rect = VT100GridRect(x: 1, y: 1, width: 0, height: 0)
        grid.scroll(rect, downBy: 1, softBreak: false)

        // Content unchanged
        let expectedContent = [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)

        // No lines should be marked dirty
        XCTAssertTrue(grid.dirtyIndexes.isEmpty)
    }

    func testScrollRectDownBy_NegativeOne_MoveOneDwcReplaced() {
        let width: Int32 = 3
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        // Load the “ab>”, “c-d”, “e-f” pattern into the top three rows
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "ab" +
            "c-d\n",
            "e-f"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        // Start with a clean slate
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 0, y: 1, width: 3, height: 2)
        grid.scroll(rect, downBy: -1, softBreak: false)

        let expectedContent = [
            "ab\n",
            "e-f\n",
            "\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)

        // Only the two rows in the scrolled region (rows 1 and 2) should be dirty
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([1, 2]))
    }

    func testScrollRectDownBy_MoveContinuationMarkToEdgeOfRect() {
        let width: Int32 = 3
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "ab" +
            "c-" +
            "d-" +
            "e-f"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 0, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: 1, softBreak: false)

        let expectedContent = [
            "ab\n",
            "\n",
            "c->>",
            "d-\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)

        // Only the two rows in the scrolled region (rows 1 and 2) should be dirty
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([1, 2, 3]))
    }

    func testScrollRectDownBy_MoveContinuationMarkToEdgeOfRect_ScrollUp() {
        let width: Int32 = 3
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "ab" +
            "c-" +
            "d-" +
            "e-f"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 0, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: -1, softBreak: false)

        let expectedContent = [
            "ab\n",
            "d->>",
            "e-f\n",
            "\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([1, 2, 3]))
    }


    func testScrollRectDownBy_ContinuationMarksCleanedBeforeScrollingDown() {
        let width: Int32 = 4
        let height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd",
            "efgh",
            "ijkl",
            "mnop",
            "qrst"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 0, y: 1, width: 4, height: 3)
        grid.scroll(rect, downBy: 1, softBreak: false)

        let expectedContent = [
            "abcd\n",
            "\n",
            "efgh",
            "ijkl\n",
            "qrst\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
    }

    ///////////

    func testScrollRectDownBy_Two_CleansContinuationMarksInFullWidth() {
        let width: Int32 = 4
        let height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd",
            "efgh",
            "ijkl",
            "mnop",
            "qrst"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 0, y: 1, width: 4, height: 3)
        grid.scroll(rect, downBy: 2, softBreak: false)

        let expectedContent = [
            "abcd\n",
            "\n",
            "\n",
            "efgh\n",
            "qrst\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
    }

    func testScrollRectDownBy_NegativeOne_CleansContinuationMarksInFullWidth() {
        let width: Int32 = 4
        let height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd",
            "efgh",
            "ijkl",
            "mnop",
            "qrst"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 0, y: 1, width: 4, height: 3)
        grid.scroll(rect, downBy: -1, softBreak: false)

        let expectedContent = [
            "abcd\n",
            "ijkl",
            "mnop\n",
            "\n",
            "qrst\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
    }

    func testScrollRectDownBy_NegativeTwo_CleansContinuationMarksInFullWidth() {
        let width: Int32 = 4
        let height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd",
            "efgh",
            "ijkl",
            "mnop",
            "qrst"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 0, y: 1, width: 4, height: 3)
        grid.scroll(rect, downBy: -2, softBreak: false)

        let expectedContent = [
            "abcd\n",
            "mnop\n",
            "\n",
            "\n",
            "qrst\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
    }

    func testScrollRectDownBy_One_CleansContinuationMarksWithPartialWidth() {
        let width: Int32 = 4
        let height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd",
            "efgh",
            "ijkl",
            "mnop",
            "qrst"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: 1, softBreak: false)

        let expectedContent = [
            "abcd",
            "e\n",
            "ifgh",
            "mjkl\n",
            "qrst\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
    }

    func testScrollRectDownBy_Two_CleansContinuationMarksWithPartialWidth() {
        let width: Int32 = 4
        let height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd",
            "efgh",
            "ijkl",
            "mnop",
            "qrst"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: 2, softBreak: false)

        let expectedContent = [
            "abcd",
            "e\n",
            "i\n",
            "mfgh\n",
            "qrst\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
    }

    func testScrollRectDownBy_One_CleansContinuationMarksWithPartialWidthAndDwcSkip() {
        let width: Int32 = 4
        let height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)

        // We need to create a grid with DWC characters that wrap
        // The "M-" represents a double-width character with M in first cell and - in second
        let initialLines = [
            "abcd",
            "efgh",
            "ijk" + // This wraps to next line due to grid width = 4
            "M-op", // M- is a double-width character
            "qrst"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: 1, softBreak: false)

        let expectedContent = [
            "abcd",
            "e\n",
            "ifgh",
            "\0jk\n",
            "qrst\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
    }

    func testScrollRectDownBy_NegativeOne_CleansContinuationMarksWithPartialWidth() {
        let width: Int32 = 4
        let height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd",
            "efgh",
            "ijkl",
            "mnop",
            "qrst"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: -1, softBreak: false)

        let expectedContent = [
            "abcd",
            "ejkl",
            "inop\n",
            "m\n",
            "qrst\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
    }

    func testScrollRectDownBy_NegativeOne_CleansContinuationMarksWithPartialWidthAndDwcSkip() {
        let width: Int32 = 4
        let height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)

        // This includes DWC characters at positions that will be affected by scrolling
        let initialLines = [
            "abc" + // This wraps to next line
            "E-gh", // E- is a double-width character
            "ijkl",
            "mno" + // This wraps to next line
            "Q-st"  // Q- is a double-width character
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: -1, softBreak: false)

        let expectedContent = [
            "abc\n",
            "\0jkl",
            "ino\n",
            "m\n",
            "Q-st\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
    }

    func testScrollRectDownBy_NegativeTwo_CleansContinuationMarksWithPartialWidth() {
        let width: Int32 = 4
        let height: Int32 = 5
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        let initialLines = [
            "abcd",
            "efgh",
            "ijkl",
            "mnop",
            "qrst"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: dummyBuffer)
        grid.markAllCharsDirty(false, updateTimestamps: false)

        let rect = VT100GridRect(x: 1, y: 1, width: 3, height: 3)
        grid.scroll(rect, downBy: -2, softBreak: false)

        let expectedContent = [
            "abcd",
            "enop\n",
            "i\n",
            "m\n",
            "qrst\n"
        ]
        XCTAssertEqual(grid.allLinesAsStrings, expectedContent)
    }

    func testSetContentsFromDVRFrame() {
        let compactLines = [
            "abcd",
            "efgh",
            "ijkl",
            "mnop"
        ]
        let width: Int32 = 4
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummyBuffer = LineBuffer(blockSize: 1000)
        append(strings: compactLines, toGrid: grid, lineBuffer: dummyBuffer)

        let frameWidth: Int32 = 5
        let frameHeight: Int32 = 4
        var frame = [screen_char_t](repeating: screen_char_t(), count: Int(frameWidth + 1) * Int(frameHeight))
        var offset = 0

        for y in 0..<frameHeight {
            let line = grid.screenChars(atLineNumber: y)
            memcpy(&frame[offset], line, MemoryLayout<screen_char_t>.size * Int(frameWidth + 1))
            offset += Int(frameWidth)
        }

        // Test basic functionality -- save and restore 4x4 into 4x4
        let testGrid1 = VT100Grid(size: VT100GridSize(width: 4, height: 4), delegate: nil)!
        let info1 = DVRFrameInfo(
            width: 4,
            height: 4,
            cursorX: 1,
            cursorY: 2,
            timestamp: 0,
            frameType: Int32(DVRFrameTypeKeyFrame.rawValue)
        )
        var metadata = [
            iTermMetadataDefault(),
            iTermMetadataDefault(),
            iTermMetadataDefault(),
            iTermMetadataDefault(),
            iTermMetadataDefault()
        ]
        metadata.withUnsafeMutableBufferPointer { ubp in
            testGrid1.setContentsFromDVRFrame(frame, metadataArray: ubp.baseAddress!, info: info1)
        }

        XCTAssertEqual(testGrid1.allLinesAsStrings, [
            "abcd",
            "efgh",
            "ijkl",
            "mnop\n"
        ])
        XCTAssertEqual(testGrid1.cursorX, 1)
        XCTAssertEqual(testGrid1.cursorY, 2)

        // Put it into a smaller grid
        let testGrid2 = VT100Grid(size: VT100GridSize(width: 3, height: 3), delegate: nil)!
        metadata.withUnsafeMutableBufferPointer { ubp in
            testGrid2.setContentsFromDVRFrame(frame, metadataArray: ubp.baseAddress!, info: info1)
        }

        XCTAssertEqual(testGrid2.allLinesAsStrings, [
            "efg\n",
            "ijk\n",
            "mno\n"
        ])
        XCTAssertEqual(testGrid2.cursorX, 1)
        XCTAssertEqual(testGrid2.cursorY, 1)

        // Put it into a bigger grid
        let testGrid3 = VT100Grid(size: VT100GridSize(width: 5, height: 5), delegate: nil)!
        metadata.withUnsafeMutableBufferPointer { ubp in
            testGrid3.setContentsFromDVRFrame(frame, metadataArray: ubp.baseAddress!, info: info1)
        }

        XCTAssertEqual(testGrid3.allLinesAsStrings, [
            "abcd\n",
            "efgh\n",
            "ijkl\n",
            "mnop\n",
            "\n"
        ])
        XCTAssertEqual(testGrid3.cursorX, 1)
        XCTAssertEqual(testGrid3.cursorY, 2)
    }

    private func ForegroundAttributesEqual(_ a: screen_char_t, _ b: screen_char_t) -> Bool {
        if a.bold != b.bold ||
            a.faint != b.faint ||
            a.italic != b.italic ||
            a.blink != b.blink ||
            a.invisible != b.invisible ||
            a.underline != b.underline ||
            a.underlineStyle != b.underlineStyle ||
            a.strikethrough != b.strikethrough {
            return false
        }

        if a.foregroundColorMode == b.foregroundColorMode {
            if a.foregroundColorMode != UInt32(ColorMode24bit.rawValue) {
                // for normal and alternate ColorMode
                return a.foregroundColor == b.foregroundColor
            } else {
                // RGB must all be equal for 24bit color
                return a.foregroundColor == b.foregroundColor &&
                a.fgGreen == b.fgGreen &&
                a.fgBlue == b.fgBlue
            }
        } else {
            // different ColorMode == different colors
            return false
        }
    }

    private func BackgroundColorsEqual(_ a: screen_char_t, _ b: screen_char_t) -> Bool {
        if a.backgroundColorMode == b.backgroundColorMode {
            if a.backgroundColorMode != ColorMode24bit.rawValue {
                // for normal and alternate ColorMode
                return a.backgroundColor == b.backgroundColor
            } else {
                // RGB must all be equal for 24bit color
                return a.backgroundColor == b.backgroundColor &&
                a.bgGreen == b.bgGreen &&
                a.bgBlue == b.bgBlue
            }
        } else {
            // different ColorMode == different colors
            return false
        }
    }

    func testSetBgFgColorInRect() {
        let grid = mediumGrid()  // 4x4
        var redFg = screen_char_t()
        redFg.foregroundColor = 1
        redFg.foregroundColorMode = UInt32(ColorModeNormal.rawValue)

        var greenBg = screen_char_t()
        greenBg.backgroundColor = 2
        greenBg.backgroundColorMode = UInt32(ColorModeNormal.rawValue)

        grid.setBackgroundColor(greenBg,
                                foregroundColor: redFg,
                                inRectFrom: VT100GridCoord(x: 1, y: 1),
                                to: VT100GridCoord(x: 2, y: 2))

        var foregroundColor_ = screen_char_t()
        var backgroundColor_ = screen_char_t()
        foregroundColor_.foregroundColor = UInt32(ALTSEM_DEFAULT)
        foregroundColor_.foregroundColorMode = UInt32(ColorModeAlternate.rawValue)
        backgroundColor_.backgroundColor = UInt32(ALTSEM_DEFAULT)
        backgroundColor_.backgroundColorMode = UInt32(ColorModeAlternate.rawValue)

        for y in 0..<4 {
            let line = grid.screenChars(atLineNumber: Int32(y))!
            var fg: screen_char_t
            var bg: screen_char_t

            for x in 0..<4 {
                if (x == 1 || x == 2) && (y == 1 || y == 2) {
                    fg = redFg
                    bg = greenBg
                } else {
                    fg = foregroundColor_
                    bg = backgroundColor_
                }
                XCTAssert(ForegroundAttributesEqual(fg, line[x]))
                XCTAssert(BackgroundColorsEqual(bg, line[x]))
            }
        }

        // Test that setting an invalid fg results in no change to fg
        var invalidFg = redFg
        invalidFg.foregroundColorMode = UInt32(ColorModeInvalid.rawValue)
        grid.setBackgroundColor(greenBg,
                                foregroundColor: invalidFg,
                                inRectFrom: VT100GridCoord(x: 0, y: 0),
                                to: VT100GridCoord(x: 3, y: 3))

        // Now should be green bg everywhere, red fg in center square
        for y in 0..<4 {
            let line = grid.screenChars(atLineNumber: Int32(y))!
            var fg: screen_char_t

            for x in 0..<4 {
                if (x == 1 || x == 2) && (y == 1 || y == 2) {
                    fg = redFg
                } else {
                    fg = foregroundColor_
                }
                XCTAssert(ForegroundAttributesEqual(fg, line[x]))
                XCTAssert(BackgroundColorsEqual(greenBg, line[x]))
            }
        }

        // Try an invalid bg now
        var invalidBg = greenBg
        invalidBg.backgroundColorMode = UInt32(ColorModeInvalid.rawValue)
        grid.setBackgroundColor(invalidBg,
                                foregroundColor: foregroundColor_,
                                inRectFrom: VT100GridCoord(x: 0, y: 0),
                                to: VT100GridCoord(x: 3, y: 3))

        // Now should be default fg on green bg everywhere
        for y in 0..<4 {
            for x in 0..<4 {
                let line = grid.screenChars(atLineNumber: Int32(y))!
                XCTAssert(ForegroundAttributesEqual(foregroundColor_, line[x]))
                XCTAssert(BackgroundColorsEqual(greenBg, line[x]))
            }
        }
    }

    private func screenCharLine(forString string: String) -> UnsafeMutablePointer<screen_char_t> {
        let data = NSMutableData(length: string.count * MemoryLayout<screen_char_t>.size)!
        let line = data.mutableBytes.bindMemory(to: screen_char_t.self, capacity: string.count)

        for (i, c) in string.enumerated() {
            var charCode: unichar = c.utf16.first!

            if charCode == Character("-").utf16.first! {
                charCode = unichar(DWC_RIGHT)
            } else if charCode == Character(".").utf16.first! {
                charCode = 0
            }

            line[i].code = charCode
        }

        return line
    }

    private func lineBufferWithStrings(_ first: String?, _ rest: String?...) -> LineBuffer {
        var strings: [String] = []

        if let first = first {
            strings.append(first)
        }

        for arg in rest {
            if let arg = arg {
                strings.append(arg)
            } else {
                break
            }
        }

        let lineBuffer = LineBuffer(blockSize: 1000)

        for (i, string) in strings.enumerated() {
            // Get cursor position from "*" marker
            let range = string.range(of: "*")
            var cursorString = string

            if let range = range {
                let location = string.distance(from: string.startIndex, to: range.lowerBound)
                lineBuffer.setCursor(Int32(location))
                cursorString = string.replacingOccurrences(of: "*", with: "")
            }

            // Check for double width characters indicated by "-"
            if cursorString.range(of: "-") != nil {
                lineBuffer.mayHaveDoubleWidthCharacter = true
            }

            lineBuffer.appendLine(
                screenCharLine(forString: cursorString),
                length: Int32(cursorString.count),
                partial: i == strings.count - 1,
                width: 80,
                metadata: iTermImmutableMetadataDefault(),
                continuation:  screen_char_t()
            )
        }

        return lineBuffer
    }

    func testRestoreScreenFromLineBuffer() {
        let grid = largeGrid()
        let lineBuffer = lineBufferWithStrings("test", "hello wor*ld", nil)
        grid.restoreScreen(from: lineBuffer,
                           withDefaultChar: grid.defaultChar,
                           maxLinesToRestore: 1)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "rld\n",
            "\n",
            "\n",
            "\n",
            "\n",
            "\n",
            "\n",
            "\n"
        ])
        XCTAssertEqual(grid.cursorX, 1)
        XCTAssertEqual(grid.cursorY, 0)

        let grid2 = largeGrid()
        let lineBuffer2 = lineBufferWithStrings("test", "hello wo*rld", nil)
        grid2.restoreScreen(from: lineBuffer2,
                            withDefaultChar: grid2.defaultChar,
                            maxLinesToRestore: 100)

        XCTAssertEqual(grid2.allLinesAsStrings, [
            "test\n",
            "hello wo",
            "rld\n",
            "\n",
            "\n",
            "\n",
            "\n",
            "\n"
        ])
        XCTAssertEqual(grid2.cursorX, 0)
        XCTAssertEqual(grid2.cursorY, 2)

        let grid3 = smallGrid()
        let lineBuffer3 = lineBufferWithStrings("test", "hello wor*ld", nil)
        var dc = screen_char_t()
        dc.backgroundColor = 1
        dc.backgroundColorMode = UInt32(ColorModeNormal.rawValue)
        grid3.restoreScreen(from: lineBuffer3,
                            withDefaultChar: dc,
                            maxLinesToRestore: 100)

        XCTAssertEqual(grid3.allLinesAsStrings, [
            "rl",
            "d\n"
        ])
        XCTAssertEqual(grid3.cursorX, 1)
        XCTAssertEqual(grid3.cursorY, 0)

        let line = grid3.screenChars(atLineNumber: 1)!
        XCTAssertFalse(BackgroundColorsEqual(dc, line[0]))
        XCTAssertFalse(BackgroundColorsEqual(dc, line[1]))

        // Handle DWC_SKIPs
        let grid4 = mediumGrid()
        let lineBuffer4 = lineBufferWithStrings("abc*W-xy", nil)
        grid4.restoreScreen(from: lineBuffer4,
                            withDefaultChar: grid4.defaultChar,
                            maxLinesToRestore: 100)

        XCTAssertEqual(grid4.allLinesAsStrings, [
            "abc>>",
            "W-xy",
            "\n",
            "\n"
        ])
        XCTAssertEqual(grid4.cursorX, 0)
        XCTAssertEqual(grid4.cursorY, 1)
    }

    func testRestoreScreenFromLineBufferCursorAfterPartialDropWithDWC() {
        // This test verifies correct cursor restoration after a partial line drop
        // involving double-width characters. It exercises the fix for the rawLine: bug
        // through the production code path:
        //   restoreScreenFromLineBuffer: → getCursorInLastLineWithWidth: → rawLine:
        //
        // The bug: rawLine: checked "linenum == 0" instead of "linenum == _firstEntry",
        // causing it to return cumulative_line_lengths[_firstEntry - 1] instead of
        // bufferStartOffset when there's been a partial drop with _firstEntry > 0.
        //
        // Setup:
        // - Line 0: "ABCDEFGH" (8 chars, no DWC)
        // - Line 1: "IJKW-NOP" (8 chars, DWC W- at positions 3-4)
        // - Width 4
        // - Cursor at position 3 in line 1
        //
        // At width 4, line 1 wraps as: [IJK>][W-NO][P] (DWC causes wrap, > is DWC_SKIP)
        //
        // After dropping 3 wrapped lines:
        // - _firstEntry = 1, bufferStartOffset = 11
        // - Remaining content: "W-NOP" (5 chars), wraps as [W-NO][P]
        //
        // Bug behavior: rawLine:1 returned position 8 (cumulative_line_lengths[0]),
        // reading "IJKW-" instead of "W-NOP". The DWC_RIGHT at position 4 in the wrong
        // data caused OffsetOfWrappedLine to return 3 instead of 4, shifting min_x and
        // causing the cursor to be found in the FIRST iteration at wrong position (0, 1).
        //
        // Fixed behavior: rawLine:1 returns position 11 (bufferStartOffset), reading
        // correct "W-NOP" data. Cursor is found in the SECOND iteration (after popping
        // [P]) at correct position (3, 0).

        let width: Int32 = 4

        let lineBuffer = LineBuffer(blockSize: 1000)
        lineBuffer.mayHaveDoubleWidthCharacter = true

        // Line 0: "ABCDEFGH"
        let line0 = screenCharLine(forString: "ABCDEFGH")
        lineBuffer.appendLine(line0, length: 8, partial: false, width: width,
                              metadata: iTermImmutableMetadataDefault(), continuation: screen_char_t())

        // Set cursor at position 3 BEFORE appending line 1
        lineBuffer.setCursor(3)

        // Line 1: "IJKW-NOP" where W- is a DWC
        let line1 = screenCharLine(forString: "IJKW-NOP")
        lineBuffer.appendLine(line1, length: 8, partial: false, width: width,
                              metadata: iTermImmutableMetadataDefault(), continuation: screen_char_t())

        // Verify initial state
        XCTAssertEqual(lineBuffer.numLines(withWidth: width), 5)

        // Drop 3 wrapped lines to trigger partial drop
        lineBuffer.setMaxLines(2)
        let dropped = lineBuffer.dropExcessLines(withWidth: width)
        XCTAssertEqual(dropped, 3)
        XCTAssertEqual(lineBuffer.numLines(withWidth: width), 2)

        // Restore screen - this exercises getCursorInLastLineWithWidth which uses rawLine:
        let grid = VT100Grid(size: VT100GridSize(width: width, height: 4), delegate: nil)!
        let foundCursor = grid.restoreScreen(from: lineBuffer,
                                              withDefaultChar: grid.defaultChar,
                                              maxLinesToRestore: 10)

        // With the fix, cursor is found at (3, 0)
        // Before the fix, cursor was incorrectly found at (0, 1) due to wrong data
        XCTAssertTrue(foundCursor, "Cursor should be found")
        XCTAssertEqual(grid.cursorX, 3, "Cursor X should be 3")
        XCTAssertEqual(grid.cursorY, 0, "Cursor Y should be 0")
    }

    func testRectsForRun() {
        let grid = largeGrid()  // 8x8
        let run = VT100GridRun(origin: VT100GridCoord(x: 3, y: 2), length: 20)
        var x = grid.defaultChar
        x.code = Character("x").utf16.first!

        for v in grid.rects(for: run) {
            let value = v as! NSValue
            let rect = value.gridRectValue()
            grid.setCharsFrom(rect.origin, to: VT100GridRectMax(rect), to: x, externalAttributes: nil)
        }

        XCTAssertEqual(grid.allLinesAsStrings, [
            "\n",
            "\n",
            "\0\0\0xxxxx\n",
            "xxxxxxxx\n",
            "xxxxxxx\n",
            "\n",
            "\n",
            "\n"
        ])

        // Test empty run
        let emptyRun = VT100GridRun(origin: VT100GridCoord(x: 3, y: 2), length: 0)
        XCTAssertEqual(grid.rects(for: emptyRun).count, 0)

        // Test one-line run
        let oneLineRun = VT100GridRun(origin: VT100GridCoord(x: 3, y: 2), length: 2)
        let rects = grid.rects(for: oneLineRun) as! [NSValue]
        XCTAssertEqual(rects.count, 1)

        let rect = rects[0].gridRectValue()
        XCTAssertEqual(rect.origin.x, 3)
        XCTAssertEqual(rect.origin.y, 2)
        XCTAssertEqual(rect.size.width, 2)
        XCTAssertEqual(rect.size.height, 1)
    }

    func testResetScrollRegions() {
        let grid = largeGrid()
        grid.scrollRegionRows = VT100GridRange(location: 1, length: 2)
        grid.scrollRegionCols = VT100GridRange(location: 2, length: 3)
        grid.useScrollRegionCols = true
        grid.resetScrollRegions()

        XCTAssertEqual(grid.scrollRegionRows.location, 0)
        XCTAssertEqual(grid.scrollRegionRows.length, 8)
        XCTAssertEqual(grid.scrollRegionCols.location, 0)
        XCTAssertEqual(grid.scrollRegionCols.length, 8)
    }

    func testScrollRegionRect() {
        let grid = largeGrid()
        grid.scrollRegionRows = VT100GridRange(location: 1, length: 2)
        grid.scrollRegionCols = VT100GridRange(location: 2, length: 3)
        grid.useScrollRegionCols = true

        let rect = grid.scrollRegionRect()
        XCTAssertEqual(rect.origin.x, 2)
        XCTAssertEqual(rect.origin.y, 1)
        XCTAssertEqual(rect.size.width, 3)
        XCTAssertEqual(rect.size.height, 2)

        grid.useScrollRegionCols = false
        let rect2 = grid.scrollRegionRect()
        XCTAssertEqual(rect2.origin.x, 0)
        XCTAssertEqual(rect2.origin.y, 1)
        XCTAssertEqual(rect2.size.width, 8)
        XCTAssertEqual(rect2.size.height, 2)
    }

    private func gridFromCompactLinesWithContinuationMarks(_ compact: String) -> VT100Grid {
        let lines = compact.components(separatedBy: "\n")
        let grid = VT100Grid(size: VT100GridSize(width: Int32(lines[0].count - 1),
                                                 height: Int32(lines.count)),
                             delegate: nil)!

        for (i, line) in lines.enumerated() {
            let s = grid.screenChars(atLineNumber: Int32(i))!

            for j in 0..<(line.count - 1) {
                let index = line.index(line.startIndex, offsetBy: j)
                var c = unichar(line[index].utf16.first!)

                if c == Character(".").utf16.first! { c = 0 }
                if c == Character("-").utf16.first! { c = unichar(DWC_RIGHT) }

                let lastCharIndex = line.index(line.startIndex, offsetBy: line.count - 1)
                if c == Character(">").utf16.first! &&
                    j == line.count - 2 &&
                    line[lastCharIndex] == ">" {
                    c = unichar(DWC_SKIP)
                }

                s[j].code = c
            }

            let lastIndex = line.index(line.startIndex, offsetBy: line.count - 1)
            let lastChar = line[lastIndex]

            if lastChar == "!" {
                grid.setContinuationMarkOnLine(Int32(i), to: unichar(EOL_HARD))
            } else if lastChar == "+" {
                grid.setContinuationMarkOnLine(Int32(i), to: unichar(EOL_SOFT))
            } else if lastChar == ">" {
                grid.setContinuationMarkOnLine(Int32(i), to: unichar(EOL_DWC))
            } else {
                XCTFail("Invalid continuation mark")
            }
        }

        return grid
    }

    private func gridFromCompactLines(_ compact: String) -> VT100Grid {
        let lines = compact.components(separatedBy: "\n")
        let grid = VT100Grid(size: VT100GridSize(width: Int32(lines[0].count),
                                                 height: Int32(lines.count)),
                             delegate: nil)!

        for (i, line) in lines.enumerated() {
            let s = grid.screenChars(atLineNumber: Int32(i))!

            for j in 0..<line.count {
                let index = line.index(line.startIndex, offsetBy: j)
                var c = unichar(line[index].utf16.first!)

                if c == Character(".").utf16.first! { c = 0 }
                if c == Character("-").utf16.first! { c = unichar(DWC_RIGHT) }

                let lastCharIndex = line.index(line.startIndex, offsetBy: line.count - 1)
                if c == Character(">").utf16.first! &&
                    j == line.count - 2 &&
                    line[lastCharIndex] == ">" {
                    c = unichar(DWC_SKIP)
                }

                s[j].code = c
            }

            let lastIndex = line.index(line.startIndex, offsetBy: line.count - 1)
            let lastChar = line[lastIndex]

            if lastChar == ">" {
                grid.setContinuationMarkOnLine(Int32(i), to: unichar(EOL_DWC))
            } else {
                grid.setContinuationMarkOnLine(Int32(i), to: unichar(EOL_HARD))
            }
        }

        return grid
    }


    func testEraseDwc() {
        // Erase a DWC
        let grid = gridFromCompactLinesWithContinuationMarks("ab-!")
        let dc = grid.defaultChar
        XCTAssertTrue(grid.erasePossibleDoubleWidthChar(inLineNumber: 0,
                                                        startingAtOffset: 1,
                                                        with: dc))
        XCTAssertEqual(grid.allLinesAsStrings, ["a\n"])
        XCTAssertEqual(grid.dirtyIndexes, IndexSet([0]))

        // Do nothing
        let grid2 = gridFromCompactLinesWithContinuationMarks("ab-!")
        XCTAssertFalse(grid2.erasePossibleDoubleWidthChar(inLineNumber: 0,
                                                          startingAtOffset: 0,
                                                          with: dc))
        XCTAssertEqual(grid2.allLinesAsStrings, ["ab-\n"])
        XCTAssertEqual(grid2.dirtyIndexes, IndexSet())

        // Erase DWC-skip on prior line
        let grid3 = gridFromCompactLinesWithContinuationMarks("ab>>\nc-.!")
        XCTAssertTrue(grid3.erasePossibleDoubleWidthChar(inLineNumber: 1,
                                                         startingAtOffset: 0,
                                                         with: dc))
        XCTAssertEqual(grid3.allLinesAsStrings, ["ab\n", "\n"])
        XCTAssertEqual(grid3.dirtyIndexes, IndexSet([1]))  // Don't need to set DWC_SKIP->NULL char to dirty
    }

    func testMoveCursorToLeftMargin() {
        let grid = mediumGrid()

        // Test without scroll region
        grid.cursorX = 2
        XCTAssertEqual(grid.cursorX, 2)
        grid.moveCursorToLeftMargin()
        XCTAssertEqual(grid.cursorX, 0)

        // Scroll region defined but not used
        grid.scrollRegionCols = VT100GridRange(location: 1, length: 2)
        grid.cursorX = 2
        XCTAssertEqual(grid.cursorX, 2)
        grid.moveCursorToLeftMargin()
        XCTAssertEqual(grid.cursorX, 0)

        // Scroll region defined & used
        grid.useScrollRegionCols = true
        grid.cursorX = 2
        XCTAssertEqual(grid.cursorX, 2)
        grid.moveCursorToLeftMargin()
        XCTAssertEqual(grid.cursorX, 1)
    }

    func testResetWithLineBufferLeavingBehindZero() {
        let grid = gridFromCompactLines("0123\nabcd\nefgh\n....")
        grid.scrollRegionRows = VT100GridRange(location: 1, length: 2)
        grid.scrollRegionCols = VT100GridRange(location: 2, length: 2)
        grid.cursorX = 2
        grid.cursorY = 3

        let lineBuffer = LineBuffer(blockSize: 1000)
        lineBuffer.setMaxLines(1)
        let dropped = grid.reset(with: lineBuffer,
                                 unlimitedScrollback: false,
                                 preserveCursorLine: false,
                                 additionalLinesToSave: 0)

        XCTAssertEqual(dropped, 2)
        XCTAssertEqual(grid.allLinesAsStrings, [
            "\n",
            "\n",
            "\n",
            "\n"
        ])
        XCTAssertEqual(lineBuffer.lineStrings, ["efgh\n"])
        XCTAssertEqual(grid.scrollRegionRows.location, 0)
        XCTAssertEqual(grid.scrollRegionRows.length, 4)
        XCTAssertEqual(grid.scrollRegionCols.location, 0)
        XCTAssertEqual(grid.scrollRegionCols.length, 4)
        XCTAssertEqual(grid.cursor.x, 0)
        XCTAssertEqual(grid.cursor.y, 0)

        // Test unlimited scrollback --------------------------------------------------------------------
        let grid2 = gridFromCompactLines("0123\nabcd\nefgh\n....")
        let lineBuffer2 = LineBuffer(blockSize: 1000)
        lineBuffer2.setMaxLines(1)
        let dropped2 = grid2.reset(with: lineBuffer2,
                                   unlimitedScrollback: true,
                                   preserveCursorLine: false,
                                   additionalLinesToSave: 0)

        XCTAssertEqual(dropped2, 0)
        XCTAssertEqual(grid2.allLinesAsStrings, [
            "\n",
            "\n",
            "\n",
            "\n"
        ])
        XCTAssertEqual(lineBuffer2.lineStrings, ["0123\n", "abcd\n", "efgh\n"])

        // Test on empty screen ------------------------------------------------------------------------
        let grid3 = smallGrid()
        let lineBuffer3 = LineBuffer(blockSize: 1000)
        lineBuffer3.setMaxLines(1)
        let dropped3 = grid3.reset(with: lineBuffer3,
                                   unlimitedScrollback: true,
                                   preserveCursorLine: false,
                                   additionalLinesToSave: 0)

        XCTAssertEqual(dropped3, 0)
        XCTAssertEqual(grid3.allLinesAsStrings, [
            "\n",
            "\n"
        ])
        XCTAssertEqual(lineBuffer3.numLines(withWidth: grid3.size.width), 0)
    }

    func testResetWithLineBufferLeavingBehindCursorLine_CursorBelowContent() {
        // Cursor below content
        let grid = gridFromCompactLines("0123\nabcd\nefgh\n....")
        grid.scrollRegionRows = VT100GridRange(location: 1, length: 2)
        grid.scrollRegionCols = VT100GridRange(location: 2, length: 2)
        grid.cursorX = 2
        grid.cursorY = 3

        let lineBuffer = LineBuffer(blockSize: 1000)
        lineBuffer.setMaxLines(1)
        let dropped = grid.reset(with: lineBuffer,
                                 unlimitedScrollback: false,
                                 preserveCursorLine: true,
                                 additionalLinesToSave: 0)

        XCTAssertEqual(dropped, 2)
        XCTAssertEqual(grid.allLinesAsStrings, [
            "\n",
            "\n",
            "\n",
            "\n"
        ])
        XCTAssertEqual(lineBuffer.lineStrings, ["efgh\n"])
        XCTAssertEqual(grid.scrollRegionRows.location, 0)
        XCTAssertEqual(grid.scrollRegionRows.length, 4)
        XCTAssertEqual(grid.scrollRegionCols.location, 0)
        XCTAssertEqual(grid.scrollRegionCols.length, 4)
        XCTAssertEqual(grid.cursor.x, 0)
        XCTAssertEqual(grid.cursor.y, 0)
    }

    func testResetWithLineBufferLeavingBehindCursorLine_CursorAtEndOfContent() {
        // Cursor at end of content
        let grid = gridFromCompactLines("0123\nabcd\nefgh\n....")
        grid.scrollRegionRows = VT100GridRange(location: 1, length: 2)
        grid.scrollRegionCols = VT100GridRange(location: 2, length: 2)
        grid.cursorX = 2
        grid.cursorY = 2

        let lineBuffer = LineBuffer(blockSize: 1000)
        lineBuffer.setMaxLines(1)
        let dropped = grid.reset(with: lineBuffer,
                                 unlimitedScrollback: false,
                                 preserveCursorLine: true,
                                 additionalLinesToSave: 0)

        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(grid.allLinesAsStrings, [
            "efgh\n",
            "\n",
            "\n",
            "\n"
        ])
        XCTAssertEqual(lineBuffer.lineStrings, ["abcd\n"])
        XCTAssertEqual(grid.scrollRegionRows.location, 0)
        XCTAssertEqual(grid.scrollRegionRows.length, 4)
        XCTAssertEqual(grid.scrollRegionCols.location, 0)
        XCTAssertEqual(grid.scrollRegionCols.length, 4)
        XCTAssertEqual(grid.cursor.x, 0)
        XCTAssertEqual(grid.cursor.y, 0)
    }

    func testResetWithLineBufferLeavingBehindCursorLine_CursorWithinContent() {
        // Cursor within content
        let grid = gridFromCompactLines("0123\nabcd\nefgh\n....")
        grid.scrollRegionRows = VT100GridRange(location: 1, length: 2)
        grid.scrollRegionCols = VT100GridRange(location: 2, length: 2)
        grid.cursorX = 2
        grid.cursorY = 1

        let lineBuffer = LineBuffer(blockSize: 1000)
        lineBuffer.setMaxLines(1)
        let dropped = grid.reset(with: lineBuffer,
                                 unlimitedScrollback: false,
                                 preserveCursorLine: true,
                                 additionalLinesToSave: 0)

        XCTAssertEqual(dropped, 0)
        XCTAssertEqual(grid.allLinesAsStrings, [
            "abcd\n",
            "\n",
            "\n",
            "\n"
        ])
        XCTAssertEqual(lineBuffer.lineStrings, ["0123\n"])
        XCTAssertEqual(grid.scrollRegionRows.location, 0)
        XCTAssertEqual(grid.scrollRegionRows.length, 4)
        XCTAssertEqual(grid.scrollRegionCols.location, 0)
        XCTAssertEqual(grid.scrollRegionCols.length, 4)
        XCTAssertEqual(grid.cursor.x, 0)
        XCTAssertEqual(grid.cursor.y, 0)
    }

    func testResetWithLineBufferLeavingBehindCursorLine_UnlimitedScrollback() {
        // Test unlimited scrollback
        let grid = gridFromCompactLines("0123\nabcd\nefgh\n....")
        grid.cursor = VT100GridCoord(x: 0, y: 3)

        let lineBuffer = LineBuffer(blockSize: 1000)
        lineBuffer.setMaxLines(1)
        let dropped = grid.reset(with: lineBuffer,
                                 unlimitedScrollback: true,
                                 preserveCursorLine: true,
                                 additionalLinesToSave: 0)

        XCTAssertEqual(dropped, 0)
        XCTAssertEqual(grid.allLinesAsStrings, [
            "\n",
            "\n",
            "\n",
            "\n"
        ])
        XCTAssertEqual(lineBuffer.lineStrings, ["0123\n", "abcd\n", "efgh\n"])
    }

    func testResetWithLineBufferLeavingBehindCursorLine_EmptyScreen() {
        // Test on empty screen
        let grid = smallGrid()
        let lineBuffer = LineBuffer(blockSize: 1000)
        lineBuffer.setMaxLines(1)
        let dropped = grid.reset(with: lineBuffer,
                                 unlimitedScrollback: true,
                                 preserveCursorLine: true,
                                 additionalLinesToSave: 0)

        XCTAssertEqual(dropped, 0)
        XCTAssertEqual(grid.allLinesAsStrings, [
            "\n",
            "\n"
        ])
        XCTAssertEqual(lineBuffer.numLines(withWidth: grid.size.width), 0)
    }

    func testMoveWrappedCursorLineToTopOfGrid() {
        // Create test grid from compact lines with continuation marks
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcd+\n" +
            "efg.!\n" +
            "hijk+\n" +
            "lmno+\n" +
            "pq..!\n" +
            "rstu+\n" +
            "vwx.!"
        )

        grid.cursorX = 1
        grid.cursorY = 4
        grid.moveWrappedCursorLineToTopOfGrid()

        XCTAssertEqual(grid.allLinesAsStrings, [
            "hijk",
            "lmno",
            "pq\n",
            "rstu",
            "vwx\n",
            "\n",
            "\n"
        ])
        XCTAssertEqual(grid.cursorX, 1)
        XCTAssertEqual(grid.cursorY, 2)

        // Test empty screen
        let smallGrid = self.smallGrid()
        smallGrid.cursorX = 1
        smallGrid.cursorY = 1
        smallGrid.moveWrappedCursorLineToTopOfGrid()

        XCTAssertEqual(smallGrid.allLinesAsStrings, ["\n", "\n"])
        XCTAssertEqual(smallGrid.cursorX, 1)
        XCTAssertEqual(smallGrid.cursorY, 0)

        // Test that scroll regions are ignored
        let gridWithScrollRegions = gridFromCompactLinesWithContinuationMarks(
            "abcd+\n" +
            "efg.!\n" +
            "hijk+\n" +
            "lmno+\n" +
            "pq..!\n" +
            "rstu+\n" +
            "vwx.!"
        )

        gridWithScrollRegions.scrollRegionRows = VT100GridRange(location: 1, length: 2)
        gridWithScrollRegions.scrollRegionCols = VT100GridRange(location: 2, length: 2)
        gridWithScrollRegions.useScrollRegionCols = true
        gridWithScrollRegions.cursorX = 1
        gridWithScrollRegions.cursorY = 4
        gridWithScrollRegions.moveWrappedCursorLineToTopOfGrid()

        XCTAssertEqual(gridWithScrollRegions.allLinesAsStrings, [
            "hijk",
            "lmno",
            "pq\n",
            "rstu",
            "vwx\n",
            "\n",
            "\n"
        ])
        XCTAssertEqual(gridWithScrollRegions.cursorX, 1)
        XCTAssertEqual(gridWithScrollRegions.cursorY, 2)
    }

    private func screenCharLineForString(_ string: String) -> UnsafeMutablePointer<screen_char_t> {
        let data = NSMutableData(length: string.count * MemoryLayout<screen_char_t>.size)!
        let line = data.mutableBytes.bindMemory(to: screen_char_t.self, capacity: string.count)

        for i in 0..<string.count {
            let stringIndex = string.index(string.startIndex, offsetBy: i)
            var c = string[stringIndex].utf16.first!

            if c == Character("-").utf16.first! {
                c = unichar(DWC_RIGHT)
            } else if c == Character(".").utf16.first! {
                c = 0
            }

            line[i].code = c
        }

        return line
    }

    private func doAppendCharsAtCursorTestWithInitialBuffer(_ initialBuffer: String,
                                                            scrollRegion: VT100GridRect,
                                                            useScrollbackWithRegion: Bool,
                                                            unlimitedScrollback: Bool,
                                                            appending stringToAppend: String,
                                                            at initialCursor: VT100GridCoord,
                                                            expect expectedLinesArray: [String],
                                                            expectCursor expectedCursor: VT100GridCoord,
                                                            expectLineBuffer expectedLineBuffer: [String],
                                                            expectDropped expectedNumLinesDropped: Int32,
                                                            wraparound: Bool = true,
                                                            insert: Bool = false,
                                                            ansi: Bool = false) {
        let grid = gridFromCompactLinesWithContinuationMarks(initialBuffer)
        let lineBuffer = LineBuffer(blockSize: 1000)

        if scrollRegion.size.width >= 0 {
            grid.scrollRegionCols = VT100GridRange(location: scrollRegion.origin.x, length: scrollRegion.size.width)
            grid.useScrollRegionCols = true
        }

        if scrollRegion.size.height >= 0 {
            grid.scrollRegionRows = VT100GridRange(location: scrollRegion.origin.y, length: scrollRegion.size.height)
        }

        let line = screenCharLineForString(stringToAppend)
        grid.cursor = initialCursor

        let numLinesDropped = grid.appendChars(atCursor: line,
                                               length: Int32(stringToAppend.count),
                                               scrollingInto: lineBuffer,
                                               unlimitedScrollback: unlimitedScrollback,
                                               useScrollbackWithRegion: useScrollbackWithRegion,
                                               wraparound: wraparound,
                                               ansi: ansi,
                                               insert: insert,
                                               externalAttributeIndex: nil,
                                               rtlFound: false,
                                               dwcFree: false)

        XCTAssertEqual(grid.allLinesAsStrings, expectedLinesArray)
        XCTAssertEqual(lineBuffer.lineStrings, expectedLineBuffer)
        XCTAssertEqual(numLinesDropped, expectedNumLinesDropped)
        XCTAssertEqual(grid.cursorX, expectedCursor.x)
        XCTAssertEqual(grid.cursorY, expectedCursor.y)
    }

    func testAppendCharsAtCursor() {
        // append empty buffer
        doAppendCharsAtCursorTestWithInitialBuffer("ab!\n" +
                                                   "cd!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "",
                                                   at: VT100GridCoord(x: 0, y: 0),
                                                   expect: ["ab\n", "cd\n"],
                                                   expectCursor: VT100GridCoord(x: 0, y: 0),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0)
    }

    func testAppendCharsAtCursor_ScrollingIntoLineBuffer() {
        doAppendCharsAtCursorTestWithInitialBuffer("abc!\n" +
                                                   "d..!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "efgh",
                                                   at: VT100GridCoord(x: 1, y: 1),
                                                   expect: ["def", "gh\n"],
                                                   expectCursor: VT100GridCoord(x: 2, y: 1),
                                                   expectLineBuffer: ["abc\n"],
                                                   expectDropped: 0)
    }

    func testAppendCharsAtCursor_NoScrollingWithVsplit() {
        doAppendCharsAtCursorTestWithInitialBuffer("abc!\n" +
                                                   "d..!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 1, y: 0), size: VT100GridSize(width: 2, height: 2)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "efgh",
                                                   at: VT100GridCoord(x: 1, y: 1),
                                                   expect: ["aef\n", "dgh\n"],
                                                   expectCursor: VT100GridCoord(x: 3, y: 1),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0)
    }

    func testAppendCharsAtCursor_ScrollingWithScrollRegion() {
        doAppendCharsAtCursorTestWithInitialBuffer("abc!\n" +
                                                   "d..!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: 3, height: 1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "efgh",
                                                   at: VT100GridCoord(x: 3, y: 0),
                                                   expect: ["h\n", "d\n"],
                                                   expectCursor: VT100GridCoord(x: 1, y: 0),
                                                   expectLineBuffer: ["abcefg"],
                                                   expectDropped: 0)
    }

    func testAppendCharsAtCursor_NoScrollingWithRegionAndScrollbackDisabled() {
        doAppendCharsAtCursorTestWithInitialBuffer("abc!\n" +
                                                   "d..!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: 3, height: 1)),
                                                   useScrollbackWithRegion: false,
                                                   unlimitedScrollback: false,
                                                   appending: "efgh",
                                                   at: VT100GridCoord(x: 3, y: 0),
                                                   expect: ["h\n", "d\n"],
                                                   expectCursor: VT100GridCoord(x: 1, y: 0),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0)
    }

    func testAppendCharsAtCursor_NoScrollingWithHVRegions() {
        doAppendCharsAtCursorTestWithInitialBuffer("abc!\n" +
                                                   "d..!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 1, y: 0), size: VT100GridSize(width: 2, height: 1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "efgh",
                                                   at: VT100GridCoord(x: 3, y: 0),
                                                   expect: ["agh\n", "d\n"],
                                                   expectCursor: VT100GridCoord(x: 3, y: 0),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0)
    }

    func testAppendCharsAtCursor_UnlimitedScrollback() {
        doAppendCharsAtCursorTestWithInitialBuffer("ab!\n" +
                                                   "cd!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: true,
                                                   appending: "efghijklmn",
                                                   at: VT100GridCoord(x: 2, y: 1),
                                                   expect: ["kl", "mn\n"],
                                                   expectCursor: VT100GridCoord(x: 2, y: 1),
                                                   expectLineBuffer: ["ab\n", "cdefghij"],
                                                   expectDropped: 0)
    }

    func testAppendCharsAtCursor_DWC() {
        doAppendCharsAtCursorTestWithInitialBuffer("...!\n" +
                                                   "...!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "A-bcd",
                                                   at: VT100GridCoord(x: 0, y: 0),
                                                   expect: ["A-b", "cd\n"],
                                                   expectCursor: VT100GridCoord(x: 2, y: 1),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0)
    }

    func testAppendCharsAtCursor_DWCSplitToNextLine() {
        doAppendCharsAtCursorTestWithInitialBuffer("...!\n" +
                                                   "...!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "abC-d",
                                                   at: VT100GridCoord(x: 0, y: 0),
                                                   expect: ["ab>>", "C-d\n"],
                                                   expectCursor: VT100GridCoord(x: 3, y: 1),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0)
    }

    func testAppendCharsAtCursor_DWCSplitAtVsplit() {
        doAppendCharsAtCursorTestWithInitialBuffer("....!\n" +
                                                   "....!\n" +
                                                   "....!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: 3, height: 3)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "abC-d",
                                                   at: VT100GridCoord(x: 0, y: 0),
                                                   expect: ["ab\n", "C-d\n", "\n"],
                                                   expectCursor: VT100GridCoord(x: 3, y: 1),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0)
    }

    func testAppendCharsAtCursor_WraparoundMode() {
        doAppendCharsAtCursorTestWithInitialBuffer("a.!\n" +
                                                   "..!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "bcd",
                                                   at: VT100GridCoord(x: 1, y: 0),
                                                   expect: ["ab", "cd\n"],
                                                   expectCursor: VT100GridCoord(x: 2, y: 1),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0)
    }

    func testAppendCharsAtCursor_WraparoundModeWithVsplit() {
        doAppendCharsAtCursorTestWithInitialBuffer("a...!\n" +
                                                   "....!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: 2, height: 2)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "bcde",
                                                   at: VT100GridCoord(x: 1, y: 0),
                                                   expect: ["cd\n", "e\n"],
                                                   expectCursor: VT100GridCoord(x: 1, y: 1),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0)
    }

    func testInsertModeWithPlainText() {
        // insert mode with plain text
        doAppendCharsAtCursorTestWithInitialBuffer("abcdgh..!\n" +
                                                   "zy......!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "ef",
                                                   at: VT100GridCoord(x: 4, y: 0),
                                                   expect: ["abcdefgh\n", "zy\n"],
                                                   expectCursor: VT100GridCoord(x: 6, y: 0),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0,
                                                   wraparound: true,
                                                   insert: true)
    }

    func testInsertOrphaningDWCs() {
        // insert orphaning DWCs
        doAppendCharsAtCursorTestWithInitialBuffer("abcdgH-.!\n" +
                                                   "zy......!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "ef",
                                                   at: VT100GridCoord(x: 4, y: 0),
                                                   expect: ["abcdefg\n", "zy\n"],
                                                   expectCursor: VT100GridCoord(x: 6, y: 0),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0,
                                                   wraparound: true,
                                                   insert: true)
    }

    func testInsertStompingDWCSkip() {
        // insert stomping DWC_SKIP, causing lines to be joined normally
        doAppendCharsAtCursorTestWithInitialBuffer("abcdfgh>>\n" +
                                                   "I-......!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "e",
                                                   at: VT100GridCoord(x: 4, y: 0),
                                                   expect: ["abcdefgh", "I-\n"],
                                                   expectCursor: VT100GridCoord(x: 5, y: 0),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0,
                                                   wraparound: true,
                                                   insert: true)
    }

    func testInsertLongStringWithWraparound() {
        // insert really long string, causing truncation at end of line and of inserted string and wraparound
        doAppendCharsAtCursorTestWithInitialBuffer("abcdtuvw+\n" +
                                                   "xyz.....!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "efghijklm",
                                                   at: VT100GridCoord(x: 4, y: 0),
                                                   expect: ["abcdefgh", "ijklmxyz\n"],
                                                   expectCursor: VT100GridCoord(x: 5, y: 1),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0,
                                                   wraparound: true,
                                                   insert: true)
    }

    func testInsertLongStringWithoutWraparound() {
        // insert long string without wraparound
        doAppendCharsAtCursorTestWithInitialBuffer("abcdtuvw+\n" +
                                                   "xyz.....!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "efghijklm",
                                                   at: VT100GridCoord(x: 4, y: 0),
                                                   expect: ["abcdefgm\n", "xyz\n"],
                                                   expectCursor: VT100GridCoord(x: 8, y: 0),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0,
                                                   wraparound: false,
                                                   insert: true)
    }

    func testInsertModeWithVSplit() {
        // insert mode with vsplit
        doAppendCharsAtCursorTestWithInitialBuffer("abcde!\n" +
                                                   "xyz..!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 1, y: 0), size: VT100GridSize(width: 3, height: 2)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "m",
                                                   at: VT100GridCoord(x: 2, y: 0),
                                                   expect: ["abmce\n", "xyz\n"],
                                                   expectCursor: VT100GridCoord(x: 3, y: 0),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0,
                                                   wraparound: true,
                                                   insert: true)
    }

    func testInsertWrappingStringWithVSplit() {
        // insert wrapping string with vsplit
        doAppendCharsAtCursorTestWithInitialBuffer("abcde!\n" +
                                                   "xyz..!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 1, y: 0), size: VT100GridSize(width: 3, height: 2)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "mno",
                                                   at: VT100GridCoord(x: 2, y: 0),
                                                   expect: ["abmne\n", "xoyz\n"],
                                                   expectCursor: VT100GridCoord(x: 2, y: 1),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0,
                                                   wraparound: true,
                                                   insert: true)
    }

    func testInsertOrphaningDWCAtEndOfLineWithVSplit() {
        // insert orphaning dwc and end of line with vsplit
        doAppendCharsAtCursorTestWithInitialBuffer("abcD-e!\n" +
                                                   "xyz...!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 1, y: 0), size: VT100GridSize(width: 4, height: 2)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "m",
                                                   at: VT100GridCoord(x: 2, y: 0),
                                                   expect: ["abmc\0e\n", "xyz\n"],
                                                   expectCursor: VT100GridCoord(x: 3, y: 0),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0,
                                                   wraparound: true,
                                                   insert: true)
    }

    func testOverwriteLeftHalfOfDWC() {
        // with insert mode off, overwrite the left half of a DWC, leaving orphan
        doAppendCharsAtCursorTestWithInitialBuffer("abcD-e!\n" +
                                                   "xyz...!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "mn",
                                                   at: VT100GridCoord(x: 2, y: 0),
                                                   expect: ["abmn\0e\n", "xyz\n"],
                                                   expectCursor: VT100GridCoord(x: 4, y: 0),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0,
                                                   wraparound: true,
                                                   insert: false)
    }

    func testAppendCharsWithAnsiTerminalAndWraparoundMode() {
        // with ansi terminal, placing cursor at right margin wraps it around in wraparound mode
        // TODO: vsplits aren't treated the same way; should they be?
        doAppendCharsAtCursorTestWithInitialBuffer("abc.!\n" +
                                                   "xyz.!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "d",
                                                   at: VT100GridCoord(x: 3, y: 0),
                                                   expect: ["abcd", "xyz\n"],
                                                   expectCursor: VT100GridCoord(x: 0, y: 1),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0,
                                                   wraparound: true,
                                                   insert: false,
                                                   ansi: true)
    }

    func testAppendCharsWithAnsiTerminalAndWraparoundModeOff() {
        // with ansi terminal, placing cursor at right margin moves it back one space if wraparoundmode is off
        // TODO: vsplits aren't treated the same way; should they be?
        doAppendCharsAtCursorTestWithInitialBuffer("abc.!\n" +
                                                   "xyz.!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "d",
                                                   at: VT100GridCoord(x: 3, y: 0),
                                                   expect: ["abcd\n", "xyz\n"],
                                                   expectCursor: VT100GridCoord(x: 3, y: 0),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0,
                                                   wraparound: false,
                                                   insert: false,
                                                   ansi: true)
    }

    func testOverwritingDwcSkipConvertsEolDwcToEolSoft() {
        // Overwriting a DWC_SKIP converts EOL_DWC to EOL_SOFT
        doAppendCharsAtCursorTestWithInitialBuffer("abc>>\n" +
                                                   "D-..!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "d",
                                                   at: VT100GridCoord(x: 3, y: 0),
                                                   expect: ["abcd", "D-\n"],
                                                   expectCursor: VT100GridCoord(x: 4, y: 0),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0,
                                                   wraparound: true,
                                                   insert: false,
                                                   ansi: false)
    }

    func testOverwritingDwcSkipAndWrapping() {
        // Test what happens when we overwrite DWC_SKIP and wrap to next line
        doAppendCharsAtCursorTestWithInitialBuffer("abc>>\n" +
                                                   "D-..!",
                                                   scrollRegion: VT100GridRect(origin: VT100GridCoord(x: 0, y: 0), size: VT100GridSize(width: -1, height: -1)),
                                                   useScrollbackWithRegion: true,
                                                   unlimitedScrollback: false,
                                                   appending: "def",
                                                   at: VT100GridCoord(x: 3, y: 0),
                                                   expect: ["abcd", "ef\n"],
                                                   expectCursor: VT100GridCoord(x: 2, y: 1),
                                                   expectLineBuffer: [],
                                                   expectDropped: 0,
                                                   wraparound: true,
                                                   insert: false,
                                                   ansi: false)
    }


    func testCoordinateBefore_BasicCase() {
        let grid = smallGrid()
        var dwc = ObjCBool(false)
        let before = grid.coordinate(before: VT100GridCoord(x: 1, y: 0),
                                     movedBackOverDoubleWidth: &dwc)
        XCTAssertEqual(before.x, 0)
        XCTAssertEqual(before.y, 0)
    }

    func testCoordinateBefore_FailureToMoveBeforeGrid() {
        let grid = smallGrid()
        let before = grid.coordinate(
            before: VT100GridCoord(x: 0, y: 0),
            movedBackOverDoubleWidth: nil
        )
        XCTAssertEqual(before.x, -1)
        XCTAssertEqual(before.y, -1)
    }

    func testCoordinateBefore_WrapBackOverSoftEOL() {
        // Row 0: "ab" soft-EOL; Row 1: "cd\n" hard-EOL
        let width: Int32 = 2
        let height: Int32 = 2
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummy = LineBuffer(blockSize: 1000)
        append(strings: ["abcd"], toGrid: grid, lineBuffer: dummy)

        let before = grid.coordinate(
            before: VT100GridCoord(x: 0, y: 1),
            movedBackOverDoubleWidth: nil
        )
        XCTAssertEqual(before.x, 1)
        XCTAssertEqual(before.y, 0)
    }

    func testCoordinateBefore_FailureToWrapAcrossHardEOL() {
        // Both rows hard-EOL: no wrap
        let width: Int32 = 2
        let height: Int32 = 2
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummy = LineBuffer(blockSize: 1000)
        append(strings: ["ab\n", "cd\n"], toGrid: grid, lineBuffer: dummy)

        let before = grid.coordinate(
            before: VT100GridCoord(x: 0, y: 1),
            movedBackOverDoubleWidth: nil
        )
        XCTAssertEqual(before.x, -1)
        XCTAssertEqual(before.y, -1)
    }

    func testCoordinateBefore_WrapBackOverEOLDWC() {
        // Row 0: "a>>" with EOL_DWC; Row 1: "C-!\n"
        // Use test helper to interpret '>' and '-' as DWC markers:
        let grid = gridFromCompactLinesWithContinuationMarks("a>>\nC-!")

        let before = grid.coordinate(
            before: VT100GridCoord(x: 0, y: 1),
            movedBackOverDoubleWidth: nil
        )
        XCTAssertEqual(before.x, 0)
        XCTAssertEqual(before.y, 0)
    }

    func testCoordinateBefore_ScrollRegionColsAffectsWrap() {
        // Two hard-EOL rows
        let width: Int32 = 4
        let height: Int32 = 2
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummy = LineBuffer(blockSize: 1000)
        append(strings: ["abcd\n", "efgh\n"], toGrid: grid, lineBuffer: dummy)

        grid.scrollRegionCols = VT100GridRange(location: 1, length: 2)
        grid.useScrollRegionCols = true

        let before = grid.coordinate(
            before: VT100GridCoord(x: 1, y: 1),
            movedBackOverDoubleWidth: nil
        )
        XCTAssertEqual(before.x, 2)
        XCTAssertEqual(before.y, 0)
    }

    func testCoordinateBefore_MovingBackOverDWC_RIGHT() {
        // Single row: "A-b\n" where '-' is DWC_RIGHT
        let width: Int32 = 3
        let height: Int32 = 1
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let dummy = LineBuffer(blockSize: 1000)
        let row = screenCharLine(forString: "A-b")
        grid.appendChars(atCursor: row, length: 3,
                         scrollingInto: dummy,
                         unlimitedScrollback: true,
                         useScrollbackWithRegion: false,
                         wraparound: false,
                         ansi: false,
                         insert: false,
                         externalAttributeIndex: nil,
                         rtlFound: false,
                         dwcFree: false)

        let before = grid.coordinate(
            before: VT100GridCoord(x: 2, y: 0),
            movedBackOverDoubleWidth: nil
        )
        XCTAssertEqual(before.x, 0)
        XCTAssertEqual(before.y, 0)
    }

    func testCoordinateBefore_WrapAndSkipOverDWC() {
        // Row0: "aB-+" (soft-EOL wrap marker '+'), Row1: "cde\n"
        let grid = gridFromCompactLinesWithContinuationMarks("aB-+\ncde!")

        let before = grid.coordinate(
            before: VT100GridCoord(x: 0, y: 1),
            movedBackOverDoubleWidth: nil
        )
        XCTAssertEqual(before.x, 1)
        XCTAssertEqual(before.y, 0)
    }

    func testDeleteChars_base() {
        // Base case
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcd!\n" +
            "efg.!"
        )

        grid.deleteChars(1, startingAt: VT100GridCoord(x: 1, y: 0))

        let actual = grid.allLinesAsStrings
        let expected = [
            "acd\n",
            "efg\n"
        ]

        XCTAssertEqual(actual, expected)
    }

    func testDeleteChars_tooMany() {
        // Delete more chars than exist in line
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcd+\n" +
            "efg.!"
        )

        grid.deleteChars(100, startingAt: VT100GridCoord(x: 1, y: 0))

        XCTAssertEqual(grid.allLinesAsStrings, [
            "a\n",
            "efg\n"
        ])
    }

    func testDeleteChars_delete0() {
        // Delete 0 chars
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcd+\n" +
            "efg.!"
        )

        grid.deleteChars(0, startingAt: VT100GridCoord(x: 1, y: 0))

        XCTAssertEqual(grid.allLinesAsStrings, [
            "abcd",
            "efg\n"
        ])
    }

    func testDeleteChars_deleteLeftHalfDWC() {
        // Orphan dwc - deleting left half
        let grid = gridFromCompactLinesWithContinuationMarks(
            "aB-d!\n" +
            "efg.!"
        )

        grid.deleteChars(1, startingAt: VT100GridCoord(x: 1, y: 0))

        XCTAssertEqual(grid.allLinesAsStrings, [
            "a\0d\n",
            "efg\n"
        ])
    }

    func testDeleteChars_deleteRightHalfDWC() {
        // Orphan dwc - deleting right half
        let grid = gridFromCompactLinesWithContinuationMarks(
            "aB-d!\n" +
            "efg.!"
        )

        grid.deleteChars(1, startingAt: VT100GridCoord(x: 2, y: 0))

        XCTAssertEqual(grid.allLinesAsStrings, [
            "a\0d\n",
            "efg\n"
        ])
    }

    func testDeleteChars_breakSkip() {
        // Break DWC_SKIP
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abc>>\n" +
            "D-ef!"
        )

        grid.deleteChars(1, startingAt: VT100GridCoord(x: 0, y: 0))

        XCTAssertEqual(grid.allLinesAsStrings, [
            "bc\n",
            "D-ef\n"
        ])
    }

    func testDeleteChars_scrollRegion() {
        // Scroll region
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcde+\n" +
            "fghi.!"
        )

        grid.scrollRegionCols = VT100GridRange(location: 1, length: 3)
        grid.useScrollRegionCols = true
        grid.deleteChars(1, startingAt: VT100GridCoord(x: 2, y: 0))

        XCTAssertEqual(grid.allLinesAsStrings, [
            "abd\0e",
            "fghi\n"
        ])
    }

    func testDeleteChars_scrollRegionDeleteBignum() {
        // Scroll region, deleting bignum
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcde+\n" +
            "fghi.!"
        )

        grid.scrollRegionCols = VT100GridRange(location: 1, length: 3)
        grid.useScrollRegionCols = true
        grid.deleteChars(100, startingAt: VT100GridCoord(x: 2, y: 0))

        XCTAssertEqual(grid.allLinesAsStrings, [
            "ab\0\0e",
            "fghi\n"
        ])
    }

    func testDeleteChars_scrollRegionDeleteRightDWC() {
        // Scroll region, creating orphan dwc by deleting right half
        let grid = gridFromCompactLinesWithContinuationMarks(
            "aB-cd+\n" +
            "fghi.!"
        )

        grid.scrollRegionCols = VT100GridRange(location: 1, length: 3)
        grid.useScrollRegionCols = true
        grid.deleteChars(1, startingAt: VT100GridCoord(x: 2, y: 0))

        XCTAssertEqual(grid.allLinesAsStrings, [
            "a\0c\0d",
            "fghi\n"
        ])
    }

    func testDeleteChars_scrollRegionBoundaryOverlapsLeftHalfDWC() {
        // Scroll region right boundary overlaps half a DWC, orphaning its right half
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abC-e+"
        )

        grid.scrollRegionCols = VT100GridRange(location: 0, length: 3)
        grid.useScrollRegionCols = true
        grid.deleteChars(1, startingAt: VT100GridCoord(x: 0, y: 0))

        XCTAssertEqual(grid.allLinesAsStrings, [
            "b\0\0\0e"
        ])
    }

    func testDeleteChars_scrollRegionBoundaryOverlapsRightHalfDWC() {
        // Scroll region right boundary overlaps half a DWC, orphaning its left half
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abC-efg+"
        )

        grid.scrollRegionCols = VT100GridRange(location: 3, length: 2)
        grid.useScrollRegionCols = true
        grid.deleteChars(1, startingAt: VT100GridCoord(x: 3, y: 0))

        XCTAssertEqual(grid.allLinesAsStrings, [
            "ab\0e\0fg"
        ])
    }

    func testDeleteChars_scrollRegionDWCSkipSurvives() {
        // DWC skip survives with a scroll region
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abc>>\n" +
            "D-ef!"
        )

        grid.scrollRegionCols = VT100GridRange(location: 0, length: 3)
        grid.useScrollRegionCols = true
        grid.deleteChars(1, startingAt: VT100GridCoord(x: 0, y: 0))

        XCTAssertEqual(grid.allLinesAsStrings, [
            "bc\0>>",
            "D-ef\n"
        ])
    }

    func testDeleteChars_scrollRegionOutside() {
        // Delete outside scroll region (should be a noop)
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abc!\n" +
            "def!"
        )

        grid.scrollRegionCols = VT100GridRange(location: 0, length: 1)
        grid.useScrollRegionCols = true
        grid.deleteChars(1, startingAt: VT100GridCoord(x: 10, y: 10))

        XCTAssertEqual(grid.allLinesAsStrings, [
            "abc\n",
            "def\n"
        ])
    }

    // Base case
    func testInsertChar_base() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcd+\n" +
            "efg.!"
        )
        let c = grid.defaultChar
        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 1, y: 0), times: 1)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "a\0bc",
            "efg\n"
        ])
    }

    // Insert more chars than there is room for
    func testInsertChar_tooMany() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcd+\n" +
            "efg.!"
        )
        let c = grid.defaultChar
        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 1, y: 0), times: 100)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "a\n",
            "efg\n"
        ])
    }

    // Verify that continuation marks are preserved if inserted char is not null
    func testInsertChar_nonNullChar() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcd+\n" +
            "efg.!"
        )
        var c = grid.defaultChar
        c.code = Character("x").utf16.first!

        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 1, y: 0), times: 100)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "axxx",
            "efg\n"
        ])
    }

    // Insert 0 chars
    func testInsertChar_zero() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcd+\n" +
            "efg.!"
        )
        let c = grid.defaultChar
        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 1, y: 0), times: 0)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "abcd",
            "efg\n"
        ])
    }

    // Insert into middle of dwc, creating two orphans
    func testInsertChar_middleOfDwc() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "aB-de+\n" +
            "fghi.!"
        )
        var c = grid.defaultChar
        c.code = Character("x").utf16.first!

        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 2, y: 0), times: 1)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "a\0x\0d",
            "fghi\n"
        ])
    }

    // Shift right one, removing DWC_SKIP, changing EOL_DWC into EOL_SOFT
    func testInsertChar_removeDwcSkip() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcd>>\n" +
            "E-fgh!"
        )
        let c = grid.defaultChar
        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 2, y: 0), times: 1)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "ab\0cd",
            "E-fgh\n"
        ])
    }

    // Break DWC_SKIP/EOL_DWC
    func testInsertChar_breakDwcSkip() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcd>>\n" +
            "E-fgh!"
        )
        let c = grid.defaultChar
        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 2, y: 0), times: 2)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "ab\0\0c",
            "E-fgh\n"
        ])
    }

    // Break DWC_SKIP/EOL_DWC, leave null and hard-wrap
    func testInsertChar_breakDwcSkipHardWrap() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abC->>\n" +
            "E-fgh!"
        )
        let c = grid.defaultChar
        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 2, y: 0), times: 2)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "ab\n",
            "E-fgh\n"
        ])
    }

    // Scroll region
    func testInsertChar_scrollRegion() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcdef+"
        )
        grid.scrollRegionCols = VT100GridRange(location: 1, length: 4)
        grid.useScrollRegionCols = true

        let c = grid.defaultChar
        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 2, y: 0), times: 1)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "ab\0cdf"
        ])
    }

    // Insert more than fits in scroll region
    func testInsertChar_scrollRegionOverflow() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcdef+"
        )
        grid.scrollRegionCols = VT100GridRange(location: 1, length: 4)
        grid.useScrollRegionCols = true

        let c = grid.defaultChar
        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 2, y: 0), times: 100)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "ab\0\0\0f"
        ])
    }

    // Make orphan by inserting into scroll region that overlaps left half of dwc
    func testInsertChar_orphanLeftDwc() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcD-f+"
        )
        grid.scrollRegionCols = VT100GridRange(location: 1, length: 3)
        grid.useScrollRegionCols = true

        let c = grid.defaultChar
        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 1, y: 0), times: 1)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "a\0bc\0f"
        ])
    }

    // Make orphan by inserting into scroll region that overlaps right half of dwc
    func testInsertChar_orphanRightDwc() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "A-cdef+"
        )
        grid.scrollRegionCols = VT100GridRange(location: 1, length: 3)
        grid.useScrollRegionCols = true

        let c = grid.defaultChar
        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 1, y: 0), times: 1)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "\0\0\0cef"
        ])
    }

    // DWC skip survives with scroll region
    func testInsertChar_dwcSkipWithScrollRegion() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abC->>\n" +
            "E-fgh!"
        )
        grid.scrollRegionCols = VT100GridRange(location: 0, length: 2)
        grid.useScrollRegionCols = true

        let c = grid.defaultChar
        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 0, y: 0), times: 1)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "\0aC->>",
            "E-fgh\n"
        ])
    }

    // Insert outside scroll region (noop)
    func testInsertChar_outsideScrollRegion() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abC->>\n" +
            "E-fgh!"
        )
        grid.scrollRegionCols = VT100GridRange(location: 0, length: 2)
        grid.useScrollRegionCols = true

        let c = grid.defaultChar
        grid.insert(c, externalAttributes: nil, at: VT100GridCoord(x: 3, y: 0), times: 1)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "abC->>",
            "E-fgh\n"
        ])
    }

    func testMoveCursorRightToMargin() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcd+\n" +
            "efg.!"
        )

        grid.cursorX = 1
        grid.moveCursorRight(99)

        XCTAssertEqual(grid.cursorX, grid.size.width - 1)
    }

    // MARK: - Regression Tests

    func testAppendingLongLineAtBottomOfScrollRegionGivesSoftBreak() {
        // Issue 4308
        // There was a scroll region because screen was being used. The user appended a long line at the bottom
        // of the region (just above the status bar). When it scrolled up, a hard linebreak replaced the soft
        // one.
        let grid = largeGrid()
        grid.scrollRegionRows = VT100GridRange(location: 0, length: 4)

        let stringToAppend = "0123456789abcdefghijklmnopqrstuvwxyz"
        let line = screenCharLineForString(stringToAppend)

        grid.appendChars(atCursor: line,
                         length: Int32(stringToAppend.count),
                         scrollingInto: nil,
                         unlimitedScrollback: false,
                         useScrollbackWithRegion: false,
                         wraparound: true,
                         ansi: false,
                         insert: false,
                         externalAttributeIndex: nil,
                         rtlFound: false,
                         dwcFree: false)

        XCTAssertEqual(grid.allLinesAsStrings, [
            "89abcdef",
            "ghijklmn",
            "opqrstuv",
            "wxyz\n",
            "\n",
            "\n",
            "\n",
            "\n"
        ])
    }

    func testGridRunFromRangeBasic() {
        let range = NSRange(location: 0, length: 5)
        let grid = VT100Grid(size: VT100GridSize(width: 10, height: 10), delegate: nil)!
        let actual = grid.gridRun(from: range, relativeToRow: 0)
        let expected = VT100GridRunMake(0, 0, 5)
        XCTAssertTrue(VT100GridRunEquals(actual, expected),
                      "actual=\(VT100GridRunDescription(actual)), expected=\(VT100GridRunDescription(expected))")
    }

    func testGridRunFromRange_SpansLines() {
        let range = NSRange(location: 8, length: 5)
        let grid = VT100Grid(size: VT100GridSize(width: 10, height: 10), delegate: nil)!
        let actual = grid.gridRun(from: range, relativeToRow: 0)
        let expected = VT100GridRunMake(8, 0, 5)
        XCTAssertTrue(VT100GridRunEquals(actual, expected),
                      "actual=\(VT100GridRunDescription(actual)), expected=\(VT100GridRunDescription(expected))")
    }

    func testGridRunFromRange_StartsOnSubsequentLine() {
        let range = NSRange(location: 18, length: 5)
        let grid = VT100Grid(size: VT100GridSize(width: 10, height: 10), delegate: nil)!
        let actual = grid.gridRun(from: range, relativeToRow: 0)
        let expected = VT100GridRunMake(8, 1, 5)
        XCTAssertTrue(VT100GridRunEquals(actual, expected),
                      "actual=\(VT100GridRunDescription(actual)), expected=\(VT100GridRunDescription(expected))")
    }

    func testGridRunFromRange_WithPositiveRowOffset() {
        let range = NSRange(location: 18, length: 5)
        let grid = VT100Grid(size: VT100GridSize(width: 10, height: 10), delegate: nil)!
        let actual = grid.gridRun(from: range, relativeToRow: 5)
        let expected = VT100GridRunMake(8, 6, 5)
        XCTAssertTrue(VT100GridRunEquals(actual, expected),
                      "actual=\(VT100GridRunDescription(actual)), expected=\(VT100GridRunDescription(expected))")
    }

    func testGridRunFromRange_NegativeRow_NoTruncation() {
        let range = NSRange(location: 18, length: 5)
        let grid = VT100Grid(size: VT100GridSize(width: 10, height: 10), delegate: nil)!
        let actual = grid.gridRun(from: range, relativeToRow: -1)
        let expected = VT100GridRunMake(8, 0, 5)
        XCTAssertTrue(VT100GridRunEquals(actual, expected),
                      "actual=\(VT100GridRunDescription(actual)), expected=\(VT100GridRunDescription(expected))")
    }

    func testGridRunFromRange_NegativeRow_TruncatedStart() {
        let range = NSRange(location: 18, length: 5)
        let grid = VT100Grid(size: VT100GridSize(width: 10, height: 10), delegate: nil)!
        let actual = grid.gridRun(from: range, relativeToRow: -2)
        let expected = VT100GridRunMake(0, 0, 3)
        XCTAssertTrue(VT100GridRunEquals(actual, expected),
                      "actual=\(VT100GridRunDescription(actual)), expected=\(VT100GridRunDescription(expected))")
    }

    func testGridRunFromRange_NegativeRow_CompletelyTruncated() {
        let range = NSRange(location: 18, length: 5)
        let grid = VT100Grid(size: VT100GridSize(width: 10, height: 10), delegate: nil)!
        let actual = grid.gridRun(from: range, relativeToRow: -3)
        let expected = VT100GridRunMake(0, 0, 0)
        XCTAssertTrue(VT100GridRunEquals(actual, expected),
                      "actual=\(VT100GridRunDescription(actual)), expected=\(VT100GridRunDescription(expected))")
    }

    func testSingleColumnLineBuffer() {
        let grid = VT100Grid(size: VT100GridSize(width: 1, height: 24), delegate: nil)!
        let lineBuffer = LineBuffer(blockSize: 1000)

        grid.appendLines(5, to: lineBuffer)

        var continuation = screen_char_t()
        let sca: ScreenCharArray? = lineBuffer.wrappedLine(at: 0, width: 1, continuation: &continuation)

        XCTAssertNotNil(sca)
        XCTAssertEqual(sca?.length ?? 0, 0)
    }

    func testRemoveLastLineRegular() {
        let width: Int32 = 80
        let height: Int32 = 24
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let lineBuffer = LineBuffer(blockSize: 1000)

        for string in ["hello", "world"] {
            let sca = screenCharArrayWithDefaultStyle(string, eol: EOL_SOFT)
            grid.appendChars(atCursor: sca.line,
                             length: sca.length,
                             scrollingInto: nil,
                             unlimitedScrollback: false,
                             useScrollbackWithRegion: false,
                             wraparound: true,
                             ansi: false,
                             insert: false,
                             externalAttributeIndex: nil,
                             rtlFound: false,
                             dwcFree: false)
            grid.moveCursorToLeftMargin()
            grid.moveCursorDown(1)
            _ = grid.scrollWholeScreenUp(into: lineBuffer,
                                         unlimitedScrollback: true)
            grid.cursor = VT100GridCoord(x: 0, y: 0)
        }

        XCTAssertEqual(lineBuffer.lineStrings, ["hello\n", "world\n"])
        lineBuffer.removeLastRawLine()
        XCTAssertEqual(lineBuffer.lineStrings, ["hello\n" ])
    }

    private func appendRawLines(_ strings: [String], to grid: VT100Grid, lineBuffer: LineBuffer) {
        for string in strings {
            // Build a screenCharArray with soft‐EOL (no trailing "\n")
            let sca = screenCharArrayWithDefaultStyle(string, eol: EOL_SOFT)
            grid.appendChars(atCursor: sca.line,
                             length: sca.length,
                             scrollingInto: nil,
                             unlimitedScrollback: false,
                             useScrollbackWithRegion: false,
                             wraparound: true,
                             ansi: false,
                             insert: false,
                             externalAttributeIndex: nil,
                             rtlFound: false,
                             dwcFree: false)
            grid.moveCursorToLeftMargin()
            grid.moveCursorDown(1)
            // Scroll until this “raw” line is moved into the buffer
            while grid.length(ofLineNumber: 0) > 0
                    || grid.cursor.x > 0
                    || grid.cursor.y > 0 {
                _ = grid.scrollWholeScreenUp(into: lineBuffer,
                                             unlimitedScrollback: true)
                grid.cursor = VT100GridCoord(x: 0, y: 0)
            }
        }
    }

    func testRemoveLastRawLineWrapped() {
        let grid = VT100Grid(size: VT100GridSize(width: 80, height: 24), delegate: nil)!
        let lineBuffer = LineBuffer(blockSize: 1000)

        let spam = """
        now is the time for all good men, women, and children to come \
        to the aid of his, her, or their party or parties as applicable \
        in his, her, or their local jurisdiction
        """

        appendRawLines(["hello", spam], to: grid, lineBuffer: lineBuffer)


        XCTAssertEqual(lineBuffer.lineStrings, ["hello\n", spam + "\n"])

        lineBuffer.removeLastRawLine()
        XCTAssertEqual(lineBuffer.lineStrings, ["hello\n" ])
    }

    func testRemoveLastRawLineEmpty() {
        let grid = VT100Grid(size: VT100GridSize(width: 80, height: 24), delegate: nil)!
        let lineBuffer = LineBuffer(blockSize: 1000)

        appendRawLines(["hello", ""], to: grid, lineBuffer: lineBuffer)

        XCTAssertEqual(lineBuffer.lineStrings, ["hello\n", "\n"])

        lineBuffer.removeLastRawLine()
        XCTAssertEqual(lineBuffer.lineStrings, ["hello\n"])
    }

    func testRemoveLastRawLineLargerThanBlockSize() {
        let grid = VT100Grid(size: VT100GridSize(width: 80, height: 24), delegate: nil)!
        let lineBuffer = LineBuffer(blockSize: 85)

        let spam = """
        now is the time for all good men, women, and children to come \
        to the aid of his, her, or their party or parties as applicable \
        in his, her, or their local jurisdiction
        """

        appendRawLines(["hello", spam], to: grid, lineBuffer: lineBuffer)

        XCTAssertEqual(lineBuffer.lineStrings, ["hello\n", spam + "\n"])

        lineBuffer.removeLastRawLine()
        XCTAssertEqual(lineBuffer.lineStrings, ["hello\n"])
    }

    func testRemoveLastRawLineEmptyBuffer() {
        let lineBuffer = LineBuffer(blockSize: 85)

        XCTAssertEqual(lineBuffer.lineStrings, [])

        lineBuffer.removeLastRawLine()
        XCTAssertEqual(lineBuffer.lineStrings, [])
    }

    // MARK: - BCE (Background Color Erase) Tests

    /// Test for issue 12723: When scrolling, newly cleared lines should use
    /// the grid's defaultChar background color (BCE behavior).
    func testBCE_ScrollingUsesDefaultCharBackgroundColor() {
        let width: Int32 = 10
        let height: Int32 = 4
        let grid = VT100Grid(size: VT100GridSize(width: width, height: height), delegate: nil)!
        let lineBuffer = LineBuffer(blockSize: 1000)

        // Fill the grid with text
        let initialLines = [
            "line1\n",
            "line2\n",
            "line3\n",
            "line4"
        ]
        append(strings: initialLines, toGrid: grid, lineBuffer: lineBuffer)

        // Set up a custom defaultChar with orange 24-bit background color
        var orangeDefaultChar = screen_char_t()
        orangeDefaultChar.code = 0
        orangeDefaultChar.backgroundColorMode = UInt32(ColorMode24bit.rawValue)
        orangeDefaultChar.backgroundColor = 255  // red
        orangeDefaultChar.bgGreen = 165
        orangeDefaultChar.bgBlue = 0
        grid.defaultChar = orangeDefaultChar

        // Scroll the grid down (which clears the bottom line)
        grid.cursorX = 0
        grid.cursorY = 3  // bottom line
        grid.moveCursorDownOneLineScrolling(into: lineBuffer,
                                            unlimitedScrollback: true,
                                            useScrollbackWithRegion: false,
                                            willScroll: nil,
                                            sentToLineBuffer: nil)

        // The newly scrolled-in line (line 3, 0-indexed) should have the orange background
        let line = grid.immutableScreenChars(atLineNumber: 3)!

        // Check that the empty cells have 24-bit orange background
        XCTAssertEqual(line[0].backgroundColorMode, UInt32(ColorMode24bit.rawValue),
                       "BCE: scrolled-in line should have 24-bit background color mode from defaultChar")
        XCTAssertEqual(line[0].backgroundColor, 255,
                       "BCE: scrolled-in line should have red=255 from defaultChar")
        XCTAssertEqual(line[0].bgGreen, 165,
                       "BCE: scrolled-in line should have green=165 from defaultChar")
        XCTAssertEqual(line[0].bgBlue, 0,
                       "BCE: scrolled-in line should have blue=0 from defaultChar")
    }

    /// Test for issue 12723: scrollRect:downBy: should use defaultChar for cleared regions.
    func testBCE_ScrollRectUsesDefaultCharBackgroundColor() {
        let grid = gridFromCompactLinesWithContinuationMarks(
            "abcdef!\n" +
            "ghijkl!\n" +
            "mnopqr!\n" +
            "stuvwx!"
        )

        // Set up a custom defaultChar with orange 24-bit background color
        var orangeDefaultChar = screen_char_t()
        orangeDefaultChar.code = 0
        orangeDefaultChar.backgroundColorMode = UInt32(ColorMode24bit.rawValue)
        orangeDefaultChar.backgroundColor = 255  // red
        orangeDefaultChar.bgGreen = 165
        orangeDefaultChar.bgBlue = 0
        grid.defaultChar = orangeDefaultChar

        // Scroll the entire rect up by 1 (this clears the bottom line)
        let rect = VT100GridRect(origin: VT100GridCoord(x: 0, y: 0),
                                 size: VT100GridSize(width: grid.size.width, height: grid.size.height))
        grid.scroll(rect, downBy: -1, softBreak: false)

        // The newly cleared bottom line should have the orange background
        let line = grid.immutableScreenChars(atLineNumber: 3)!

        XCTAssertEqual(line[0].backgroundColorMode, UInt32(ColorMode24bit.rawValue),
                       "BCE: scrollRect cleared line should have 24-bit background color mode")
        XCTAssertEqual(line[0].backgroundColor, 255,
                       "BCE: scrollRect cleared line should have red=255")
        XCTAssertEqual(line[0].bgGreen, 165,
                       "BCE: scrollRect cleared line should have green=165")
        XCTAssertEqual(line[0].bgBlue, 0,
                       "BCE: scrollRect cleared line should have blue=0")
    }
}

extension VT100Grid {
    var allLinesAsStrings: [String] {
        return (0..<size.height).map {
            lineAsString($0)
        }
    }

    func screenCharArray(atLine i: Int32) -> ScreenCharArray? {
        return ScreenCharArray(line: screenChars(atLineNumber: i),
                               length: size.width,
                               metadata: iTermMetadataMakeImmutable(metadata(atLineNumber: i)),
                               continuation: screenChars(atLineNumber: i)[Int(size.width)])
    }

    func lineAsString(_ i: Int32) -> String {
        let sca = screenCharArray(atLine: i)!
        let msca = sca.mutableCopy() as! MutableScreenCharArray
        let line = msca.mutableLine
        for i in 0..<Int(msca.length) {
            if line[i].code == DWC_SKIP {
                line[i].code = ">".utf16.first!
            } else if line[i].code == DWC_RIGHT {
                line[i].code = "-".utf16.first!
            }
        }
        let eol = switch msca.eol {
        case EOL_HARD:
            "\n"
        case EOL_SOFT:
            ""
        case EOL_DWC:
            ">"
        default:
            "?"
        }
        return msca.stringValueIncludingEmbeddedNulls + eol
    }

    func set(line: Int32, to string: String) {
        let sca = screenCharArrayWithDefaultStyle(string, eol: EOL_SOFT)
        setCharactersInLine(line, to: sca.line, length: sca.length)

    }

    var dirtyIndexes: IndexSet {
        var result = IndexSet()
        for i in 0..<size.height {
            if !dirtyIndexes(onLine: i).isEmpty {
                result.insert(Int(i))
            }
        }
        return result
    }
}

extension LineBuffer {
    var lineStrings: [String] {
        return (0..<Int32(numberOfUnwrappedLines())).map { i in
            let uw = unwrappedLine(at: i)
            let eol = switch uw.eol {
            case EOL_HARD:
                "\n"
            case EOL_SOFT:
                ""
            case EOL_DWC:
                ">"
            default:
                "?"
            }
            return uw.stringValue + eol
        }
    }
}
