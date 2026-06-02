//
//  LineBufferTests.swift
//  iTerm2XCTests
//
//  Created by George Nachman on 12/8/21.
//

import XCTest
@testable import iTerm2SharedARC

class LineBufferTests: XCTestCase {
    func testBasic() throws {
        let linebuffer = LineBuffer()
        let width = Int32(80)
        let hello = screenCharArrayWithDefaultStyle("Hello world",
                                                    eol: EOL_HARD)
        let goodbye = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                      eol: EOL_HARD)
        linebuffer.append(hello,
                          width: width)
        linebuffer.append(goodbye,
                          width: width)

        XCTAssertEqual(linebuffer.numLines(withWidth: width),
                       2)
        XCTAssertEqual(linebuffer.wrappedLine(at: 0, width: width),
                       hello)
        XCTAssertEqual(linebuffer.wrappedLine(at: 1, width: width),
                       goodbye)
    }

    func testBasic_Wraps() throws {
        let linebuffer = LineBuffer()
        let width = Int32(4)
        let linesToAppend = [("Hello world", EOL_HARD),
                             ("Goodbye cruel world", EOL_HARD)]
        for tuple in linesToAppend {
            linebuffer.append(screenCharArrayWithDefaultStyle(tuple.0,
                                                              eol: tuple.1),
                              width: width)
        }

        let expectedLines = [
            screenCharArrayWithDefaultStyle("Hell", eol: EOL_SOFT),
            screenCharArrayWithDefaultStyle("o wo", eol: EOL_SOFT),
            screenCharArrayWithDefaultStyle("rld\0", eol: EOL_HARD),
            screenCharArrayWithDefaultStyle("Good", eol: EOL_SOFT),
            screenCharArrayWithDefaultStyle("bye ", eol: EOL_SOFT),
            screenCharArrayWithDefaultStyle("crue", eol: EOL_SOFT),
            screenCharArrayWithDefaultStyle("l wo", eol: EOL_SOFT),
            screenCharArrayWithDefaultStyle("rld\0", eol: EOL_HARD)
        ]

        let actualLines = (0..<expectedLines.count).map {
            linebuffer.wrappedLine(at: Int32($0), width: width).padded(toLength: width, eligibleForDWC: false)
        }

        XCTAssertEqual(actualLines, expectedLines)
    }

    func testCopyOnWrite_ModifySecond() throws {
        let first = LineBuffer()
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        first.append(s1, width: width)

        let second = first.copy()
        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                 eol: EOL_HARD)
        second.append(s2, width: width)

        XCTAssertEqual(first.allScreenCharArrays, [s1])
        XCTAssertEqual(second.allScreenCharArrays, [s1, s2])
    }

    func testCopyOnWrite_ModifyFirst() throws {
        let first = LineBuffer()
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        first.append(s1, width: width)

        let second = first.copy()
        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                 eol: EOL_HARD)
        first.append(s2, width: width)

        XCTAssertEqual(first.allScreenCharArrays, [s1, s2])
        XCTAssertEqual(second.allScreenCharArrays, [s1])
    }

    func testCopyOnWrite_ModifyBoth() throws {
        let first = LineBuffer()
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        first.append(s1, width: width)

        let second = first.copy()
        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                 eol: EOL_HARD)
        second.append(s1, width: width)
        first.append(s2, width: width)

        XCTAssertEqual(first.allScreenCharArrays, [s1, s2])
        XCTAssertEqual(second.allScreenCharArrays, [s1, s1])
    }

    func testCopyOnWrite_CopyOfCopy() throws {
        let first = LineBuffer()
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        first.append(s1, width: width)

        let second = first.copy()
        let third = second.copy()

        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                 eol: EOL_HARD)
        second.append(s2, width: width)

        let s3 = screenCharArrayWithDefaultStyle("I like traffic lights",
                                                 eol: EOL_HARD)

        third.append(s3, width: width)

        XCTAssertEqual(first.allScreenCharArrays, [s1])
        XCTAssertEqual(second.allScreenCharArrays, [s1, s2])
        XCTAssertEqual(third.allScreenCharArrays, [s1, s3])
    }

    func testCopyOnWrite_ClientKeepsOwnerAliveUntilWriteToSecond() throws {
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        let first = LineBuffer()
        first.append(s1, width: width)
        let second = first.copy()

        XCTAssertEqual(first.testOnlyBlock(at: 0).numberOfClients, 1)
        XCTAssertFalse(first.testOnlyBlock(at: 0).hasOwner())

        XCTAssertEqual(second.testOnlyBlock(at: 0).numberOfClients, 0)
        XCTAssertTrue(second.testOnlyBlock(at: 0).hasOwner())

        second.append(s1, width: width)

        XCTAssertEqual(first.testOnlyBlock(at: 0).numberOfClients, 0)
        XCTAssertFalse(first.testOnlyBlock(at: 0).hasOwner())

        XCTAssertEqual(second.testOnlyBlock(at: 0).numberOfClients, 0)
        XCTAssertFalse(second.testOnlyBlock(at: 0).hasOwner())
    }

    func testCopyOnWrite_ClientKeepsOwnerAliveUntilWriteToFirst() throws {
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        let first = LineBuffer()
        first.append(s1, width: width)
        let second = first.copy()

        XCTAssertEqual(first.testOnlyBlock(at: 0).numberOfClients, 1)
        XCTAssertFalse(first.testOnlyBlock(at: 0).hasOwner())

        XCTAssertEqual(second.testOnlyBlock(at: 0).numberOfClients, 0)
        XCTAssertTrue(second.testOnlyBlock(at: 0).hasOwner())

        first.append(s1, width: width)

        XCTAssertEqual(first.testOnlyBlock(at: 0).numberOfClients, 0)
        XCTAssertFalse(first.testOnlyBlock(at: 0).hasOwner())

        XCTAssertEqual(second.testOnlyBlock(at: 0).numberOfClients, 0)
        XCTAssertFalse(second.testOnlyBlock(at: 0).hasOwner())
    }

    func testCopyOnWrite_Pop() throws {
        let first = LineBuffer()
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                 eol: EOL_HARD)
        first.append(s1, width: width)
        first.append(s2, width: width)

        let second = first.copy()
        let buffer = UnsafeMutablePointer<screen_char_t>.allocate(capacity: Int(width))
        defer {
            buffer.deallocate()
        }

        let sca = second.popLastLine(withWidth: width)
        XCTAssertEqual(sca, s2.padded(toLength: width, eligibleForDWC: false))

        XCTAssertEqual(first.allScreenCharArrays, [s1, s2])
        XCTAssertEqual(second.allScreenCharArrays, [s1])
    }

    func testCopyOnWrite_Truncate() throws {
        let first = LineBuffer()
        first.setMaxLines(2)
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                 eol: EOL_HARD)
        first.append(s1, width: width)
        first.append(s2, width: width)

        let second = first.copy()
        second.dropExcessLines(withWidth: 12)

        XCTAssertEqual(first.allScreenCharArrays, [s1, s2])
        XCTAssertEqual(second.allScreenCharArrays, [s2])
    }

    // Reproduction for the bug seen by Fold All: when dropExcessLines partially trims a raw line
    // from the front (instead of dropping it entirely), the LineBuffer cursor's raw-line index is
    // adjusted but cursor_x is not. cursor_x is an offset *within* the cursor's raw line, so when
    // the front of that raw line is sliced off, cursor_x must decrease by the same number of
    // characters. Otherwise the cursor points past the end of its own raw line, and
    // getCursorInLastLineWithWidth: refuses to recognize it.
    func testDropExcessLinesAdjustsCursorXWhenItsRawLineIsPartiallyTrimmed() throws {
        let linebuffer = LineBuffer()
        let width = Int32(5)

        // Append a 5-char soft-EOL portion. This creates a single partial raw line of length 5.
        let part1 = screenCharArrayWithDefaultStyle("ABCDE", eol: EOL_SOFT)
        linebuffer.append(part1, width: width)

        // Set the cursor at column 2 of the next-to-be-appended portion. setCursor sees the
        // partial last block and stores cursor_x = 2 + 5 = 7 (offset into the combined raw line),
        // cursor_rawline = 0.
        linebuffer.setCursor(2)

        // Complete the raw line with a 3-char hard-EOL portion. The raw line is now "ABCDEXYZ"
        // (length 8); at width 5 it wraps to 2 visual lines: "ABCDE" (offsets 0..4) and "XYZ"
        // (offsets 5..7).
        let part2 = screenCharArrayWithDefaultStyle("XYZ", eol: EOL_HARD)
        linebuffer.append(part2, width: width)

        XCTAssertEqual(linebuffer.numLines(withWidth: width), 2)

        // Sanity check the pre-drop cursor state: cursor_x = 7 lies in [5, 10] for the second
        // wrapped line, so getCursorInLastLineWithWidth returns YES with x = 7 - 5 = 2.
        var preDropX: Int32 = -1
        XCTAssertTrue(linebuffer.getCursorInLastLine(withWidth: width, atX: &preDropX))
        XCTAssertEqual(preDropX, 2)

        // Drop everything but the last wrapped line. dropExcessLines calls LineBlock.dropLines:,
        // which advances the block's bufferStartOffset by 5 chars, leaving the (only) raw line
        // 3 chars long ("XYZ"). No raw lines are entirely dropped, so cursor_rawline stays at 0.
        // cursor_x SHOULD be 7 - 5 = 2 after this, but the bug leaves it at 7.
        linebuffer.setMaxLines(1)
        linebuffer.dropExcessLines(withWidth: width)

        XCTAssertEqual(linebuffer.numLines(withWidth: width), 1)

        // The cursor is on the only remaining wrapped line, at column 2. With cursor_x correctly
        // adjusted to 2, getCursorInLastLineWithWidth should return YES with x = 2. Without the
        // fix, cursor_x is still 7, max_x is 5, the range check fails, and this returns NO —
        // which is what causes Fold All to leave the grid cursor stranded.
        var postDropX: Int32 = -1
        XCTAssertTrue(linebuffer.getCursorInLastLine(withWidth: width, atX: &postDropX))
        XCTAssertEqual(postDropX, 2)
    }

    func testConvertPositionMultiBlock() {
        let buffer = LineBuffer()
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                 eol: EOL_HARD)
        buffer.append(s1, width: width)
        buffer.forceSeal()
        buffer.append(s2, width: width)

        let context = FindContext()
        buffer.prepareToSearch(for: "Hello", startingAt: buffer.lastPosition(), options: .optBackwards, mode: .caseSensitiveSubstring, with: context)

        buffer.findSubstring(context, stopAt: buffer.firstPosition())
        do {
            XCTAssertEqual(context.status, .Searching)
            let pos = buffer.position(of: context, width: width)
            var ok = ObjCBool(false)
            let coord = buffer.coordinate(for: pos, width: width, extendsRight: false, ok: &ok)
            XCTAssertTrue(ok.boolValue)
            XCTAssertEqual(coord, VT100GridCoord(x: 11, y: 0))
        }

        buffer.findSubstring(context, stopAt: buffer.firstPosition())
        do {
            XCTAssertEqual(context.status, .Matched)
            let pos = buffer.position(of: context, width: width)
            var ok = ObjCBool(false)
            let coord = buffer.coordinate(for: pos, width: width, extendsRight: false, ok: &ok)
            XCTAssertTrue(ok.boolValue)
            XCTAssertEqual(coord, VT100GridCoord(x: 0, y: 0))
        }
    }

    // MARK: - coordinateForPosition extendsToEndOfLine cases
    //
    // These tests cover the four combinations of (yOffset == 0 vs > 0) and
    // (extendsRight = YES vs NO) for a position with extendsToEndOfLine = YES,
    // hitting the non-special-case branch of coordinateForPosition: (i.e. when
    // the position is not the buffer's lastPosition).
    //
    // Buffer layout for these tests: line 0 = "abcde" hard EOL (5 chars), then
    // three empty hard-EOL lines, then "xyz" hard EOL. At width 10 each line
    // occupies one wrapped row. lastPosition.absolutePosition is 8, so a
    // position with absolutePosition = 5 sits past line 0's content but is
    // not the lastPosition, so the lower branch of coordinateForPosition runs.
    // At width 10, convertPosition: for raw offset 5 returns y=0, x=5 (the
    // natural end-of-content column).

    private func bufferForExtendsToEOLTests(width: Int32) -> LineBuffer {
        let buffer = LineBuffer()
        buffer.append(screenCharArrayWithDefaultStyle("abcde", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("xyz", eol: EOL_HARD), width: width)
        return buffer
    }

    private func positionPastEOLOfLine0(yOffset: Int32) -> LineBufferPosition {
        let pos = LineBufferPosition()
        pos.absolutePosition = 5
        pos.yOffset = yOffset
        pos.extendsToEndOfLine = true
        return pos
    }

    // Case 1: yOffset == 0, extendsRight = YES. Selection-end semantics: push x to the
    // last column.
    func testCoordinateForPosition_extendsToEOL_yOffset0_extendsRight() {
        let width: Int32 = 10
        let buffer = bufferForExtendsToEOLTests(width: width)
        let pos = positionPastEOLOfLine0(yOffset: 0)
        var ok = ObjCBool(false)
        let coord = buffer.coordinate(for: pos, width: width, extendsRight: true, ok: &ok)
        XCTAssertTrue(ok.boolValue)
        XCTAssertEqual(coord, VT100GridCoord(x: width - 1, y: 0))
    }

    // Case 2: yOffset == 0, extendsRight = NO. Selection-start (and round-trip-coord)
    // semantics: x should be the natural end-of-content column from convertPosition: —
    // i.e. 5 for "abcde" at width 10. Current code clobbers this to 0 (the bug).
    func testCoordinateForPosition_extendsToEOL_yOffset0_notExtendsRight() {
        let width: Int32 = 10
        let buffer = bufferForExtendsToEOLTests(width: width)
        let pos = positionPastEOLOfLine0(yOffset: 0)
        var ok = ObjCBool(false)
        let coord = buffer.coordinate(for: pos, width: width, extendsRight: false, ok: &ok)
        XCTAssertTrue(ok.boolValue)
        XCTAssertEqual(coord, VT100GridCoord(x: 5, y: 0))
    }

    // Case 3: yOffset > 0, extendsRight = YES. We have advanced y onto an empty wrapped
    // row below the content; the selection-end caller still wants x at the last column.
    func testCoordinateForPosition_extendsToEOL_yOffsetPositive_extendsRight() {
        let width: Int32 = 10
        let buffer = bufferForExtendsToEOLTests(width: width)
        let pos = positionPastEOLOfLine0(yOffset: 2)
        var ok = ObjCBool(false)
        let coord = buffer.coordinate(for: pos, width: width, extendsRight: true, ok: &ok)
        XCTAssertTrue(ok.boolValue)
        XCTAssertEqual(coord, VT100GridCoord(x: width - 1, y: 2))
    }

    // Case 4: yOffset > 0, extendsRight = NO. We've moved y onto an empty wrapped row;
    // x should be the start of that row (0), not the end-of-content column from the
    // line above.
    func testCoordinateForPosition_extendsToEOL_yOffsetPositive_notExtendsRight() {
        let width: Int32 = 10
        let buffer = bufferForExtendsToEOLTests(width: width)
        let pos = positionPastEOLOfLine0(yOffset: 2)
        var ok = ObjCBool(false)
        let coord = buffer.coordinate(for: pos, width: width, extendsRight: false, ok: &ok)
        XCTAssertTrue(ok.boolValue)
        XCTAssertEqual(coord, VT100GridCoord(x: 0, y: 2))
    }

    // MARK: - position / coordinate round-trips
    //
    // These tests verify the round-trip property between positionForCoordinate:
    // and coordinateForPosition:. For a coord within the content of a line, the
    // round-trip should be exact under extendsRight=NO. For a coord past the
    // end of the line content, the position only records "past EOL" as a flag,
    // so extendsRight=NO yields the natural end-of-content column and
    // extendsRight=YES yields width - 1.

    private func assertRoundTrip(_ buffer: LineBuffer,
                                 coord: VT100GridCoord,
                                 width: Int32,
                                 expected: VT100GridCoord? = nil,
                                 extendsRight: Bool = false,
                                 file: StaticString = #file,
                                 line: UInt = #line) {
        guard let pos = buffer.position(forCoordinate: coord, width: width, offset: 0) else {
            XCTFail("positionForCoordinate returned nil for \(coord) at width \(width)",
                    file: file, line: line)
            return
        }
        var ok = ObjCBool(false)
        let result = buffer.coordinate(for: pos, width: width, extendsRight: extendsRight, ok: &ok)
        XCTAssertTrue(ok.boolValue,
                      "coordinateForPosition failed for round-trip of \(coord) at width \(width)",
                      file: file, line: line)
        XCTAssertEqual(result, expected ?? coord,
                       "round-trip of \(coord) at width \(width) (extendsRight=\(extendsRight)) gave \(result)",
                       file: file, line: line)
    }

    // 1. Basic round-trip on a single hard-EOL line, every column within content.
    func testRoundTrip_singleLine_noWrap() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abcde", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("xyz", eol: EOL_HARD), width: width)

        for x: Int32 in 0..<5 {
            assertRoundTrip(buffer, coord: VT100GridCoord(x: x, y: 0), width: width)
        }
        for x: Int32 in 0..<3 {
            assertRoundTrip(buffer, coord: VT100GridCoord(x: x, y: 1), width: width)
        }
    }

    // 2. Past-EOL coord under extendsRight=NO collapses to the natural
    //    end-of-content column at the current width. The original x is lost.
    func testRoundTrip_pastEOL_collapsesToEndOfContent() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abcde", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("xyz", eol: EOL_HARD), width: width)

        for inputX: Int32 in [6, 7, 9] {
            assertRoundTrip(buffer,
                            coord: VT100GridCoord(x: inputX, y: 0),
                            width: width,
                            expected: VT100GridCoord(x: 5, y: 0))
        }
    }

    // 3. Past-EOL coord under extendsRight=YES clamps to the last column.
    func testRoundTrip_pastEOL_extendsRight_clampsToWidthMinus1() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abcde", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("xyz", eol: EOL_HARD), width: width)

        assertRoundTrip(buffer,
                        coord: VT100GridCoord(x: 7, y: 0),
                        width: width,
                        expected: VT100GridCoord(x: width - 1, y: 0),
                        extendsRight: true)
    }

    // 4. Round-trip across wrap boundaries on a hard-EOL line wider than width.
    //    "Hello world" (11 chars) at width 5 wraps to "Hello" / " worl" / "d".
    func testRoundTrip_wrappedHardEOLLine() {
        let buffer = LineBuffer()
        let width: Int32 = 5
        buffer.append(screenCharArrayWithDefaultStyle("Hello world", eol: EOL_HARD), width: width)

        XCTAssertEqual(buffer.numLines(withWidth: width), 3)

        for x: Int32 in 0..<5 {
            assertRoundTrip(buffer, coord: VT100GridCoord(x: x, y: 0), width: width)
            assertRoundTrip(buffer, coord: VT100GridCoord(x: x, y: 1), width: width)
        }
        assertRoundTrip(buffer, coord: VT100GridCoord(x: 0, y: 2), width: width)
    }

    // 5. Round-trip across a soft-EOL line that spans multiple appends. The
    //    logical text "abcdefghij" wraps as "abcde" / "fghij" at width 5.
    func testRoundTrip_softEOL() {
        let buffer = LineBuffer()
        let width: Int32 = 5
        buffer.append(screenCharArrayWithDefaultStyle("abcdef", eol: EOL_SOFT), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("ghij", eol: EOL_HARD), width: width)

        XCTAssertEqual(buffer.numLines(withWidth: width), 2)

        for y: Int32 in 0..<2 {
            for x: Int32 in 0..<5 {
                assertRoundTrip(buffer, coord: VT100GridCoord(x: x, y: y), width: width)
            }
        }
    }

    // 6. Round-trip with empty lines between content lines.
    func testRoundTrip_emptyLinesInMiddle() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abc", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("xyz", eol: EOL_HARD), width: width)

        for x: Int32 in 0..<3 {
            assertRoundTrip(buffer, coord: VT100GridCoord(x: x, y: 0), width: width)
            assertRoundTrip(buffer, coord: VT100GridCoord(x: x, y: 3), width: width)
        }
        assertRoundTrip(buffer, coord: VT100GridCoord(x: 0, y: 1), width: width)
        assertRoundTrip(buffer, coord: VT100GridCoord(x: 0, y: 2), width: width)
    }

    // 7a. Regression: positionForCoordinate must succeed on every wrapped row when
    //     the buffer is split into three single-line blocks by two consecutive
    //     forceSeal calls. Previously a coord on the third block returned nil.
    func testRoundTrip_multiBlock_threeBlocks() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("first", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("second", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("third", eol: EOL_HARD), width: width)

        XCTAssertEqual(buffer.numLines(withWidth: width), 3)
        for x: Int32 in 0..<5 {
            assertRoundTrip(buffer, coord: VT100GridCoord(x: x, y: 0), width: width)
            assertRoundTrip(buffer, coord: VT100GridCoord(x: x, y: 2), width: width)
        }
        for x: Int32 in 0..<6 {
            assertRoundTrip(buffer, coord: VT100GridCoord(x: x, y: 1), width: width)
        }
    }

    // 7. Round-trip across multiple blocks (forceSeal forces a block boundary).
    func testRoundTrip_multiBlock() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("first", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("second", eol: EOL_HARD), width: width)

        for x: Int32 in 0..<5 {
            assertRoundTrip(buffer, coord: VT100GridCoord(x: x, y: 0), width: width)
        }
        for x: Int32 in 0..<6 {
            assertRoundTrip(buffer, coord: VT100GridCoord(x: x, y: 1), width: width)
        }
    }

    // 8. Round-trip at width 1 — each character occupies its own wrapped row.
    func testRoundTrip_widthOne() {
        let buffer = LineBuffer()
        let width: Int32 = 1
        buffer.append(screenCharArrayWithDefaultStyle("abc", eol: EOL_HARD), width: width)

        XCTAssertEqual(buffer.numLines(withWidth: width), 3)
        for y: Int32 in 0..<3 {
            assertRoundTrip(buffer, coord: VT100GridCoord(x: 0, y: y), width: width)
        }
    }

    // 9. Cross-width: position built at width A, coord retrieved at width B.
    //    Wide → narrow.
    func testCrossWidth_wideToNarrow() {
        let buffer = LineBuffer()
        let wideWidth: Int32 = 20
        buffer.append(screenCharArrayWithDefaultStyle("abcdefghij", eol: EOL_HARD), width: wideWidth)

        // 'g' is the 7th char (index 6). At wide width 20 it lives at (6, 0).
        let pos = buffer.position(forCoordinate: VT100GridCoord(x: 6, y: 0), width: wideWidth, offset: 0)!

        let narrowWidth: Int32 = 4
        var ok = ObjCBool(false)
        let coord = buffer.coordinate(for: pos, width: narrowWidth, extendsRight: false, ok: &ok)
        XCTAssertTrue(ok.boolValue)
        // At width 4 the line wraps to "abcd","efgh","ij" — 'g' is at (2, 1).
        XCTAssertEqual(coord, VT100GridCoord(x: 2, y: 1))
    }

    // 10. Cross-width: narrow → wide. The wrapped layout collapses back into a
    //     single wider row.
    func testCrossWidth_narrowToWide() {
        let buffer = LineBuffer()
        let narrowWidth: Int32 = 4
        buffer.append(screenCharArrayWithDefaultStyle("abcdefghij", eol: EOL_HARD), width: narrowWidth)

        // At narrow width 4 the line wraps to "abcd","efgh","ij" — 'g' at (2, 1).
        let pos = buffer.position(forCoordinate: VT100GridCoord(x: 2, y: 1), width: narrowWidth, offset: 0)!

        let wideWidth: Int32 = 20
        var ok = ObjCBool(false)
        let coord = buffer.coordinate(for: pos, width: wideWidth, extendsRight: false, ok: &ok)
        XCTAssertTrue(ok.boolValue)
        XCTAssertEqual(coord, VT100GridCoord(x: 6, y: 0))
    }

    // 11. Coord on the last char of the last line — exercises the lastPosition
    //     branch via positionForCoordinate(x=length, y=last) which sets
    //     extendsToEndOfLine.
    func testRoundTrip_lastPositionPastEOL_extendsRight() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abc", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("xyz", eol: EOL_HARD), width: width)

        // x = length of the last line — past content on the last row. positionForCoordinate
        // sets extendsToEndOfLine=YES and absolutePosition equals lastPosition.
        let pos = buffer.position(forCoordinate: VT100GridCoord(x: 3, y: 1), width: width, offset: 0)!
        XCTAssertTrue(pos.extendsToEndOfLine)
        XCTAssertEqual(pos.absolutePosition, buffer.lastPosition().absolutePosition)

        var ok = ObjCBool(false)
        let coord = buffer.coordinate(for: pos, width: width, extendsRight: true, ok: &ok)
        XCTAssertTrue(ok.boolValue)
        XCTAssertEqual(coord, VT100GridCoord(x: width - 1, y: 1))
    }

    // 12. Same as #11 but extendsRight=NO should give the natural end-of-content
    //     column, not width - 1.
    func testRoundTrip_lastPositionPastEOL_noExtendsRight() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abc", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("xyz", eol: EOL_HARD), width: width)

        let pos = buffer.position(forCoordinate: VT100GridCoord(x: 3, y: 1), width: width, offset: 0)!
        var ok = ObjCBool(false)
        let coord = buffer.coordinate(for: pos, width: width, extendsRight: false, ok: &ok)
        XCTAssertTrue(ok.boolValue)
        XCTAssertEqual(coord, VT100GridCoord(x: 3, y: 1))
    }

    // 13. Round-trip of (0, 0).
    func testRoundTrip_origin() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abc", eol: EOL_HARD), width: width)

        assertRoundTrip(buffer, coord: VT100GridCoord(x: 0, y: 0), width: width)
    }

    // 14. Round-trip when line content length equals width exactly. The line
    //     fills the row with no trailing nulls.
    func testRoundTrip_lineLengthEqualsWidth() {
        let buffer = LineBuffer()
        let width: Int32 = 5
        buffer.append(screenCharArrayWithDefaultStyle("abcde", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("xyz", eol: EOL_HARD), width: width)

        for x: Int32 in 0..<5 {
            assertRoundTrip(buffer, coord: VT100GridCoord(x: x, y: 0), width: width)
        }
    }

    // 15. Exhaustive round-trip across a mixed buffer.
    func testRoundTrip_exhaustiveMixed() {
        let buffer = LineBuffer()
        let width: Int32 = 4
        let lines: [(String, Int32)] = [
            ("Hello world", EOL_HARD),
            ("ABC", EOL_HARD),
            ("", EOL_HARD),
            ("12345678", EOL_HARD),
            ("z", EOL_HARD),
        ]
        for (s, eol) in lines {
            buffer.append(screenCharArrayWithDefaultStyle(s, eol: eol), width: width)
        }

        let numLines = Int(buffer.numLines(withWidth: width))
        for y in 0..<numLines {
            let wrapped = buffer.wrappedLine(at: Int32(y), width: width)
            let contentLength = Int(wrapped.length)
            for x in 0..<contentLength {
                assertRoundTrip(buffer,
                                coord: VT100GridCoord(x: Int32(x), y: Int32(y)),
                                width: width)
            }
        }
    }

    // 16. Cross-width past-EOL: position built past end-of-content at one width
    //     and consumed at another. The "past EOL" flag survives and is
    //     reinterpreted at the new width.
    func testCrossWidth_pastEOL_collapsesToEndOfContent() {
        let buffer = LineBuffer()
        let originalWidth: Int32 = 20
        buffer.append(screenCharArrayWithDefaultStyle("abcdefghij", eol: EOL_HARD), width: originalWidth)
        buffer.append(screenCharArrayWithDefaultStyle("zzz", eol: EOL_HARD), width: originalWidth)

        // x=15 past the end of "abcdefghij" (length 10) at width 20.
        let pos = buffer.position(forCoordinate: VT100GridCoord(x: 15, y: 0), width: originalWidth, offset: 0)!
        XCTAssertTrue(pos.extendsToEndOfLine)

        let newWidth: Int32 = 4
        var ok = ObjCBool(false)
        let coord = buffer.coordinate(for: pos, width: newWidth, extendsRight: false, ok: &ok)
        XCTAssertTrue(ok.boolValue)
        // At width 4 the 10-char line wraps to "abcd","efgh","ij". Natural
        // end-of-content offset is 10, which falls at (x=2, y=2) — the cell
        // right after 'j'.
        XCTAssertEqual(coord, VT100GridCoord(x: 2, y: 2))
    }

    // 17. positionForCoordinate persists across forceSeal: a coord captured
    //     before sealing should still round-trip after sealing and appending
    //     more.
    func testRoundTrip_positionStableAcrossForceSeal() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abcde", eol: EOL_HARD), width: width)
        let pos = buffer.position(forCoordinate: VT100GridCoord(x: 2, y: 0), width: width, offset: 0)!

        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("xyz", eol: EOL_HARD), width: width)

        var ok = ObjCBool(false)
        let coord = buffer.coordinate(for: pos, width: width, extendsRight: false, ok: &ok)
        XCTAssertTrue(ok.boolValue)
        XCTAssertEqual(coord, VT100GridCoord(x: 2, y: 0))
    }

    // 18. firstPosition and lastPosition map to the expected boundary coords.
    func testFirstAndLastPosition_mapToBoundaryCoords() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abc", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("xyz", eol: EOL_HARD), width: width)

        // firstPosition is the very start of the buffer.
        var ok = ObjCBool(false)
        let first = buffer.coordinate(for: buffer.firstPosition(),
                                       width: width,
                                       extendsRight: false,
                                       ok: &ok)
        XCTAssertTrue(ok.boolValue)
        XCTAssertEqual(first, VT100GridCoord(x: 0, y: 0))

        // lastPosition under extendsRight=NO is just past the last content cell.
        ok = ObjCBool(false)
        let last = buffer.coordinate(for: buffer.lastPosition(),
                                      width: width,
                                      extendsRight: false,
                                      ok: &ok)
        XCTAssertTrue(ok.boolValue)
        XCTAssertEqual(last, VT100GridCoord(x: 3, y: 1))
    }

    // MARK: - firstBlockContainingPosition unit tests (fast vs slow)
    //
    // These tests call fast_ and slow_firstBlockContainingPosition: directly through
    // the testOnly_ wrappers on iTermLineBlockArray and check (block index,
    // remainder, blockOffset) against a chosen expected value. The chosen
    // semantic is: at a boundary position (position == sum of all blocks up to
    // and including block i), the answer is block i with
    // remainder == block_i.rawSpaceUsed and blockOffset == numLines(blocks
    // before i). This is the natural "past end of content of block i" view, and
    // is what coordinateForPosition: needs to produce coords that round-trip
    // through positionForCoordinate:.
    //
    // Both paths *should* return the same answer for any given input. When they
    // diverge, the test fails for whichever path disagrees.

    private struct BlockLookup: Equatable {
        let index: Int32
        let remainder: Int32
        let blockOffset: Int32
    }

    private func lookup(_ buffer: LineBuffer,
                        path: BlockContainingPath,
                        position: Int64,
                        width: Int32) -> BlockLookup? {
        var remainder: Int32 = -1
        var blockOffset: Int32 = -1
        var index: Int32 = -1
        let array = buffer.testOnly_lineBlockArray()
        let block: LineBlock?
        switch path {
        case .fast:
            block = array.testOnly_fast_firstBlockContainingPosition(position,
                                                                width: width,
                                                                remainder: &remainder,
                                                                blockOffset: &blockOffset,
                                                                index: &index)
        case .slow:
            block = array.testOnly_slow_firstBlockContainingPosition(position,
                                                                width: width,
                                                                remainder: &remainder,
                                                                blockOffset: &blockOffset,
                                                                index: &index)
        }
        guard block != nil else { return nil }
        return BlockLookup(index: index, remainder: remainder, blockOffset: blockOffset)
    }

    private enum BlockContainingPath {
        case fast
        case slow
    }

    private func assertLookup(_ buffer: LineBuffer,
                              position: Int64,
                              width: Int32,
                              expected: BlockLookup,
                              file: StaticString = #file,
                              line: UInt = #line) {
        for path in [BlockContainingPath.fast, .slow] {
            let actual = lookup(buffer, path: path, position: position, width: width)
            XCTAssertEqual(actual,
                           expected,
                           "\(path) firstBlockContainingPosition disagrees for position=\(position) width=\(width)",
                           file: file, line: line)
        }
    }

    // 1. Single non-empty block. Middle of content. Both paths should return
    //    (index=0, remainder=position, blockOffset=0).
    func testBlockContaining_singleBlock_middleOfContent() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abcde", eol: EOL_HARD), width: width)
        assertLookup(buffer,
                     position: 2,
                     width: width,
                     expected: BlockLookup(index: 0, remainder: 2, blockOffset: 0))
    }

    // 2. Single non-empty block. Position at end of content (= block.rawSpaceUsed).
    //    Note: this position equals lastPosition for a single-block buffer,
    //    which coordinateForPosition: short-circuits, but firstBlockContainingPosition:
    //    is still invoked by other callers, so we test it here directly.
    func testBlockContaining_singleBlock_atEnd() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abcde", eol: EOL_HARD), width: width)
        assertLookup(buffer,
                     position: 5,
                     width: width,
                     expected: BlockLookup(index: 0, remainder: 5, blockOffset: 0))
    }

    // 3. Two non-empty blocks, position at the boundary between them. This is
    //    the May 2025 testConvertPositionMultiBlock case — the search machinery
    //    expects coord (length-of-first-block-content, 0), which requires
    //    firstBlockContainingPosition: to return the FIRST block with
    //    remainder == its rawSpaceUsed.
    func testBlockContaining_twoBlocks_atBoundary_secondLonger() {
        let buffer = LineBuffer()
        let width: Int32 = 80
        buffer.append(screenCharArrayWithDefaultStyle("Hello world", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("Goodbye cruel world", eol: EOL_HARD), width: width)
        // Position 11 is the boundary (length of "Hello world").
        // Expect block 0 ("Hello world") with remainder 11 and blockOffset 0
        // (no prior blocks). convertPosition:(p=11) on block 0 yields (11, 0)
        // — the natural "past end of Hello world."
        assertLookup(buffer,
                     position: 11,
                     width: width,
                     expected: BlockLookup(index: 0, remainder: 11, blockOffset: 0))
    }

    // 4. Three non-empty blocks, position at the inner boundary. Same shape as
    //    #3 but with a block before, so the answer is block 1.
    func testBlockContaining_threeBlocks_atInnerBoundary() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("first", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("second", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("third", eol: EOL_HARD), width: width)
        // Position 11 = end of "second" (5 + 6 = 11). Block 1, remainder 6,
        // blockOffset 1 (block 0 contributes 1 wrapped line).
        assertLookup(buffer,
                     position: 11,
                     width: width,
                     expected: BlockLookup(index: 1, remainder: 6, blockOffset: 1))
    }

    // 5. Three non-empty blocks where the *next* block is shorter than the
    //    previous block's last wrapped line. This is the case the May 2025
    //    additionalRemainder fix breaks on (yields an offset past the new
    //    block's content). Same expected answer as #4: stay in the previous
    //    block.
    func testBlockContaining_threeBlocks_atInnerBoundary_nextBlockShorter() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("aaaa", eol: EOL_HARD), width: width)  // 4 chars
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("bbbbbbb", eol: EOL_HARD), width: width)  // 7 chars
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("cc", eol: EOL_HARD), width: width)  // 2 chars — shorter than "bbbbbbb"
        // Position 11 = end of "bbbbbbb" (4 + 7 = 11).
        assertLookup(buffer,
                     position: 11,
                     width: width,
                     expected: BlockLookup(index: 1, remainder: 7, blockOffset: 1))
    }

    // 6. Position in the middle of the second block of a three-block buffer.
    func testBlockContaining_threeBlocks_middleOfMiddleBlock() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("first", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("second", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("third", eol: EOL_HARD), width: width)
        // Position 8 lies inside block 1 (5 ≤ 8 < 11): remainder=8-5=3, blockOffset=1.
        assertLookup(buffer,
                     position: 8,
                     width: width,
                     expected: BlockLookup(index: 1, remainder: 3, blockOffset: 1))
    }

    // 7. Position at the very start of the buffer.
    func testBlockContaining_positionZero() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abc", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("xyz", eol: EOL_HARD), width: width)
        assertLookup(buffer,
                     position: 0,
                     width: width,
                     expected: BlockLookup(index: 0, remainder: 0, blockOffset: 0))
    }

    // 8. yOffset == 0 at the inner boundary of a three-block buffer is the same
    //    as the case in #4 — included explicitly to lock the semantic in.
    func testBlockContaining_yOffsetZero_atBoundary() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("first", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("second", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("third", eol: EOL_HARD), width: width)
        assertLookup(buffer,
                     position: 11,
                     width: width,
                     expected: BlockLookup(index: 1, remainder: 6, blockOffset: 1))
    }

    // 9. yOffset > 0 at the inner boundary, no trailing empties anywhere. Under
    //    the simpler model where firstBlockContainingPosition: ignores yOffset
    //    (caller adds y += yOffset later), this should give the same answer as
    //    #8.
    func testBlockContaining_yOffsetPositive_atBoundary_noEmpties() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("first", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("second", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("third", eol: EOL_HARD), width: width)
        assertLookup(buffer,
                     position: 11,
                     width: width,
                     expected: BlockLookup(index: 1, remainder: 6, blockOffset: 1))
    }

    // 10. Block with trailing empty lines. The empty raw line lives inside the
    //     same block as the content. Position at end of content (= block raw
    //     space used) with yOffset=0.
    func testBlockContaining_singleBlock_withTrailingEmpty_atEnd_yOffsetZero() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abc", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("", eol: EOL_HARD), width: width)
        // rawSpaceUsed of the (single) block is 3 (the empty line contributes 0).
        // numLines at width 10 is 2 ("abc" + empty).
        assertLookup(buffer,
                     position: 3,
                     width: width,
                     expected: BlockLookup(index: 0, remainder: 3, blockOffset: 0))
    }

    // 11. Same buffer as #10 with yOffset=1 — caller wants the empty row.
    //     Under the simpler model, the lookup is the same; yOffset only affects
    //     the y coord later.
    func testBlockContaining_singleBlock_withTrailingEmpty_atEnd_yOffsetOne() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abc", eol: EOL_HARD), width: width)
        buffer.append(screenCharArrayWithDefaultStyle("", eol: EOL_HARD), width: width)
        assertLookup(buffer,
                     position: 3,
                     width: width,
                     expected: BlockLookup(index: 0, remainder: 3, blockOffset: 0))
    }

    // 12. Two sealed blocks, the second of which is all empty.
    //     Position at the boundary should stay in the first block.
    func testBlockContaining_twoBlocks_secondAllEmpty_atBoundary() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abc", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("", eol: EOL_HARD), width: width)
        assertLookup(buffer,
                     position: 3,
                     width: width,
                     expected: BlockLookup(index: 0, remainder: 3, blockOffset: 0))
    }

    // MARK: - LineBuffer integration tests for firstBlockContainingPosition consumers
    //
    // The three callers of firstBlockContainingPosition: in LineBuffer.m we care
    // about are coordinateForPosition: (fast path),
    // positionForStartOfLastLineBeforePosition: (slow via _findPosition:), and
    // prepareToSearchFor: (slow via _findPosition:). Round-trip and search
    // tests elsewhere already cover coordinateForPosition:. These tests exercise
    // the other two callers in the same multi-block scenarios where fast/slow
    // disagree.

    // 13. positionForStartOfLastLineBeforePosition: in a three-block buffer
    //     with limit at the boundary between block 1 and block 2. The "last
    //     line before position" should be the line containing the content of
    //     block 1 ("second"), so the returned position should point at the
    //     start of that line.
    func testPositionForStartOfLastLineBeforePosition_atInnerBoundary() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("first", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("second", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("third", eol: EOL_HARD), width: width)

        let limit = LineBufferPosition()
        limit.absolutePosition = 11  // boundary between "second" and "third"
        limit.yOffset = 0
        limit.extendsToEndOfLine = false

        let result = buffer.positionForStartOfLastLine(before: limit, width: width)
        // The start of "second" is at raw offset 5. The function should return
        // an absolutePosition pointing at the start of "second".
        XCTAssertEqual(result.absolutePosition, 5)
    }

    // 13b. Regression: positionForStartOfLastLine(before:) when the limit's
    //      yOffset spans empty rows that cross a block boundary into a later
    //      block. With the OLD slow_firstBlockContainingPosition:, the function
    //      consumed yOffset by walking past trailing empties of intermediate
    //      blocks, landing in the visually-correct block. The simplified slow
    //      (closed-right at boundary, yOffset ignored) stays in the previous
    //      block, and offsetOfStartOfLineIncludingOffset: in that earlier
    //      block then returns the start of the first line — not the start of
    //      the empty line in the middle block.
    func testPositionForStartOfLastLineBeforePosition_yOffsetSpansEmptyBlock() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("abc", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        // A sealed empty block sits between A and C. Visually: row 0 "abc",
        // row 1 empty (from B), row 2 "xyz" (from C).
        buffer.append(screenCharArrayWithDefaultStyle("", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("xyz", eol: EOL_HARD), width: width)

        // Limit = position for coord (0, 2) (start of "xyz"). The residual
        // mechanism inside positionForCoordinate: bumps yOffset to 2 because
        // absolutePosition=3 (boundary at end of A) reads back as (3, 0)
        // under the simplified firstBlockContainingPosition:.
        let limit = buffer.position(forCoordinate: VT100GridCoord(x: 0, y: 2),
                                    width: width,
                                    offset: 0)!
        XCTAssertEqual(limit.absolutePosition, 3, "precondition: limit absolutePosition")
        XCTAssertEqual(limit.yOffset, 2, "precondition: limit yOffset")

        let result = buffer.positionForStartOfLastLine(before: limit, width: width)
        // The line before row 2 is row 1, which is the empty line in block B.
        // Its raw start is at position 3 (end of A = start of B). The OLD
        // code reached block C with offset 0 and ended with absolutePosition
        // = rawSpaceUsedInRangeOfBlocks(0..2) (= 3 + 0 = 3) + offsetInBlock
        // (= 0) = 3.
        XCTAssertEqual(result.absolutePosition, 3)
    }

    // 14. Search starting from the position one past the end of the second
    //     block. With a 3-block buffer searching for content that appears only
    //     in the third block, the search should find it. This exercises
    //     prepareToSearchFor:'s use of _findPosition:.
    func testPrepareToSearchFor_startingAtInnerBoundary_findsInThirdBlock() {
        let buffer = LineBuffer()
        let width: Int32 = 10
        buffer.append(screenCharArrayWithDefaultStyle("first", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("second", eol: EOL_HARD), width: width)
        buffer.forceSeal()
        buffer.append(screenCharArrayWithDefaultStyle("xthird", eol: EOL_HARD), width: width)

        let start = LineBufferPosition()
        start.absolutePosition = 11  // boundary between "second" and "xthird"
        start.yOffset = 0
        start.extendsToEndOfLine = false

        let context = FindContext()
        buffer.prepareToSearch(for: "xthird",
                               startingAt: start,
                               options: [],
                               mode: .caseSensitiveSubstring,
                               with: context)
        while context.status == .Searching {
            buffer.findSubstring(context, stopAt: buffer.lastPosition())
        }
        XCTAssertEqual(context.status, .Matched,
                       "Search starting at the inner block boundary should find content in the next block")
        if let results = context.results as? [ResultRange], results.count > 0 {
            let xyRanges = buffer.convertPositions(results, withWidth: width)
            XCTAssertEqual(xyRanges?.first?.yStart, 2, "Match should be on row 2 (the 'xthird' row)")
            XCTAssertEqual(xyRanges?.first?.xStart, 0, "Match should start at column 0")
        }
    func testRightPromptBug() {
        let buffer = LineBuffer()
        let width = Int32(133)
        let s0 = screenCharArrayWithDefaultStyle("Blah",
                                                 eol: EOL_HARD)
        let s1 = screenCharArrayWithDefaultStyle(
            "Prompt>                                                     [abcdefgh]",
            eol: EOL_HARD)
        let s2 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        buffer.append(s0, width: width)
        buffer.append(s1, width: width)
        buffer.append(s2, width: width)

        let pos = buffer.position(forCoordinate: VT100GridCoord(x: 70, y: 1), width: width, offset: 0)
        guard let pos else {
            XCTFail("failed to get position")
            return
        }
        var ok = ObjCBool(false)
        let result = buffer.coordinate(for: pos, width: width - 1, extendsRight: false, ok: &ok)
        XCTAssertTrue(ok.boolValue)
        XCTAssertEqual(result, VT100GridCoord(x: 70, y: 1))
    }

    // MARK: - Raw line counting

    func testNumberOfRawLinesInRange() {
        let buffer = LineBuffer(blockSize: 140)
        let width = Int32(30)
        let scas = ["Now is the time for all good men to come to the aid of their party", //  0
                    "Twas brillig and the slithy toves did gyre and gimble in the wabe",  //  1
                    "The quick brown fox jumps over the lazy dog.",                       //  2
                    "Every seasoned coder knows the value of clear, concise logic.",      //  3
                    "Bright stars shimmer quietly above the sleeping valley.",            //  4
                    "Careful planning prevents needless problems down the line.",         //  5
                    "The diligent student reviewed each chapter before the exam.",        //  6
                    "Silence settled across the room as the verdict was read.",           //  7
                    "Persistent effort turns small advantages into real progress.",       //  8
                    "The old clock chimed softly as midnight approached.",                //  9
                    "A well-written test suite guards against subtle regressions.",       // 10
                    "Steady rain fell while the city continued its hurried pace.",        // 11
        ].map {
            screenCharArrayWithDefaultStyle($0, eol: EOL_HARD)
        }
        //  0: Now is the time for all good m
        //  1: en to come to the aid of their
        //  2:  party
        //  3: Twas brillig and the slithy to
        //  4: ves did gyre and gimble in the
        //  5:  wabe
        //
        //  6: The quick brown fox jumps over
        //  7:  the lazy dog.
        //  8: Every seasoned coder knows the
        //  9:  value of clear, concise logic
        // 10: .
        //
        // 11: Bright stars shimmer quietly a
        // 12: bove the sleeping valley.
        // 13: Careful planning prevents need
        // 14: less problems down the line.
        //
        // 15: The diligent student reviewed
        // 16: each chapter before the exam.
        // 17: Silence settled across the roo
        // 18: m as the verdict was read.
        //
        // 19: Persistent effort turns small
        // 20: advantages into real progress.
        // 21: The old clock chimed softly as
        // 22:  midnight approached.
        //
        // 23: A well-written test suite guar
        // 24: ds against subtle regressions.
        // 25: Steady rain fell while the cit
        // 26: y continued its hurried pace.
        for sca in scas {
            buffer.append(sca, width: width)
        }
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 7, length: 13), width: width)
            XCTAssertEqual(count, 7)
        }
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 0, length: 27), width: width)
            XCTAssertEqual(count, 12)
        }
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 1, length: 4), width: width)
            XCTAssertEqual(count, 2)
        }
    }

    func testNumberOfRawLinesInRange_EmptyLines() {
        let buffer = LineBuffer(blockSize: 140)
        let width = Int32(30)
        let scas = ["Now is the time for all good men to come to the aid of their party", //  0
                    "",                                                                   //  1
                    "",                                                                   //  2
                    "",                                                                   //  3
                    "Bright stars shimmer quietly above the sleeping valley.",            //  4
                    "",                                                                   //  5
                    "",                                                                   //  6
                    "",                                                                   //  7
                    "Persistent effort turns small advantages into real progress.",       //  8
                    "The old clock chimed softly as midnight approached.",                //  9
                    "A well-written test suite guards against subtle regressions.",       // 10
                    "Steady rain fell while the city continued its hurried pace.",        // 11
        ].map {
            screenCharArrayWithDefaultStyle($0, eol: EOL_HARD)
        }
        //  0: Now is the time for all good m
        //  1: en to come to the aid of their
        //  2:  party.
        //  3:
        //  4:
        //  5:
        //  6: Bright stars shimmer quietly a
        //  7: bove the sleeping valley.
        //  8:
        //  9:
        // 10:
        // 10: Persistent effort turns small
        // 11: advantages into real progress.
        // 12: The old clock chimed softly as
        // 13:  midnight approached.
        // 14: A wellwritten test suite guar
        // 15: ds against subtle regressions.
        // 16: Steady rain fell while the cit
        // 17: y continued its hurried pace.
        for sca in scas {
            buffer.append(sca, width: width)
        }
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 4, length: 6), width: width)
            XCTAssertEqual(count, 5)
        }
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 0, length: 18), width: width)
            XCTAssertEqual(count, 12)
        }
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 1, length: 4), width: width)
            XCTAssertEqual(count, 3)
        }
    }

    // Range starting/ending at block boundaries
    func testNumberOfRawLinesInRange_BlockBoundaries() {
        let buffer = LineBuffer(blockSize: 140)
        let width = Int32(30)
        let scas = ["Now is the time for all good men to come to the aid of their party",
                    "Twas brillig and the slithy toves did gyre and gimble in the wabe",
                    "The quick brown fox jumps over the lazy dog.",
                    "Every seasoned coder knows the value of clear, concise logic."].map {
            screenCharArrayWithDefaultStyle($0, eol: EOL_HARD)
        }
        for sca in scas {
            buffer.append(sca, width: width)
        }

        // Test starting at first wrapped line of buffer (block boundary)
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 0, length: 3), width: width)
            XCTAssertEqual(count, 1) // All three wrapped lines are from raw line 0
        }
    }

    func testNumberOfRawLinesInRange_SingleWrappedLine() {
        let buffer = LineBuffer(blockSize: 140)
        let width = Int32(30)
        let scas = ["Now is the time for all good men to come to the aid of their party",
                    "Short line",
                    "Another line"].map {
            screenCharArrayWithDefaultStyle($0, eol: EOL_HARD)
        }
        for sca in scas {
            buffer.append(sca, width: width)
        }

        // Test single wrapped line (first segment of a multi-wrapped raw line)
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 0, length: 1), width: width)
            XCTAssertEqual(count, 1)
        }

        // Test single wrapped line (middle segment of a multi-wrapped raw line)
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 1, length: 1), width: width)
            XCTAssertEqual(count, 1)
        }

        // Test single wrapped line (last segment of a multi-wrapped raw line)
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 2, length: 1), width: width)
            XCTAssertEqual(count, 1)
        }

        // Test single wrapped line that is a complete raw line
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 3, length: 1), width: width)
            XCTAssertEqual(count, 1)
        }
    }

    func testNumberOfRawLinesInRange_PartialRawLines() {
        let buffer = LineBuffer(blockSize: 140)
        let width = Int32(30)
        let scas = ["Now is the time for all good men to come to the aid of their party",  // wraps to 3 lines
                    "Twas brillig and the slithy toves did gyre and gimble in the wabe",   // wraps to 3 lines
                    "Short"].map {
            screenCharArrayWithDefaultStyle($0, eol: EOL_HARD)
        }
        for sca in scas {
            buffer.append(sca, width: width)
        }

        // Range starts in middle of raw line 0 and ends in middle of raw line 1
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 1, length: 3), width: width)
            XCTAssertEqual(count, 2) // Partial line 0 + partial line 1
        }

        // Range within middle of single raw line
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 3, length: 2), width: width)
            XCTAssertEqual(count, 1) // Both wrapped lines are from raw line 1
        }
    }

    func testNumberOfRawLinesInRange_SoftEOL() {
        let buffer = LineBuffer(blockSize: 140)
        let width = Int32(30)

        // Create a very long line that will wrap multiple times
        let longLine = String(repeating: "x", count: 100)
        let scas = [longLine, "Short line"].map {
            screenCharArrayWithDefaultStyle($0, eol: EOL_SOFT)
        }
        for sca in scas {
            buffer.append(sca, width: width)
        }

        // Range spanning multiple wrapped segments of same raw line
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 0, length: 3), width: width)
            XCTAssertEqual(count, 1) // All from same raw line with soft EOL continuations
        }
    }

    func testNumberOfRawLinesInRange_DoubleWidthCharacters() {
        let buffer = LineBuffer(blockSize: 140)
        let width = Int32(30)

        // Create lines with double-width characters (e.g., Japanese characters)
        let scas = ["日本語の文字列がとても長くなりますので複数行に分かれます",
                    "Another line with 中文字符",
                    "Regular ASCII text"].map {
            screenCharArrayWithDefaultStyle($0, eol: EOL_HARD)
        }
        for sca in scas {
            buffer.append(sca, width: width)
        }

        // Count raw lines in range containing double-width characters
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 0, length: 3), width: width)
            XCTAssertGreaterThanOrEqual(count, 1) // Should handle DWC correctly
        }
    }

    func testNumberOfRawLinesInRange_EmptyRange() {
        let buffer = LineBuffer(blockSize: 140)
        let width = Int32(30)
        let scas = ["Line 1", "Line 2", "Line 3"].map {
            screenCharArrayWithDefaultStyle($0, eol: EOL_HARD)
        }
        for sca in scas {
            buffer.append(sca, width: width)
        }

        // Zero length range
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 0, length: 0), width: width)
            XCTAssertEqual(count, 0)
        }

        // Empty buffer
        do {
            let emptyBuffer = LineBuffer(blockSize: 140)
            let count = emptyBuffer.numberOfUnwrappedLines(in: .init(location: 0, length: 0), width: width)
            XCTAssertEqual(count, 0)
        }
    }

    func testNumberOfRawLinesInRange_VeryLongRawLines() {
        let buffer = LineBuffer(blockSize: 500)
        let width = Int32(30)

        // Create a very long line that wraps 10+ times
        let veryLongLine = String(repeating: "abcdefghij", count: 50) // 500 chars -> ~17 wrapped lines
        let scas = [veryLongLine, "Short"].map {
            screenCharArrayWithDefaultStyle($0, eol: EOL_HARD)
        }
        for sca in scas {
            buffer.append(sca, width: width)
        }

        // Range spanning only part of a very long raw line
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 5, length: 5), width: width)
            XCTAssertEqual(count, 1) // All wrapped lines from same raw line
        }

        // Range spanning entire very long raw line
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 0, length: 17), width: width)
            XCTAssertEqual(count, 1) // Still just one raw line
        }
    }

    func testNumberOfRawLinesInRange_MultipleBlocks() {
        let buffer = LineBuffer(blockSize: 100)  // Small block size to force multiple blocks
        let width = Int32(30)

        // Add enough content to span multiple blocks
        var scas: [ScreenCharArray] = []
        for i in 0..<20 {
            scas.append(screenCharArrayWithDefaultStyle("Line \(i) with some additional text to fill space", eol: EOL_HARD))
        }
        for sca in scas {
            buffer.append(sca, width: width)
        }

        // Range spanning 2 blocks
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 10, length: 10), width: width)
            XCTAssertGreaterThanOrEqual(count, 5) // At least several raw lines
        }

        // Range spanning 3+ blocks
        do {
            let totalWrappedLines = buffer.numLines(withWidth: width)
            if totalWrappedLines > 20 {
                let count = buffer.numberOfUnwrappedLines(in: .init(location: 5, length: Int32(totalWrappedLines - 10)), width: width)
                XCTAssertGreaterThanOrEqual(count, 10)
            }
        }
    }

    func testNumberOfRawLinesInRange_BufferLimits() {
        let buffer = LineBuffer(blockSize: 140)
        let width = Int32(30)
        let scas = ["First line with enough text to wrap around the width limit",
                    "Middle line",
                    "Last line with enough text to wrap around the width limit too"].map {
            screenCharArrayWithDefaultStyle($0, eol: EOL_HARD)
        }
        for sca in scas {
            buffer.append(sca, width: width)
        }

        let totalWrappedLines = buffer.numLines(withWidth: width)

        // First wrapped line in buffer
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 0, length: 1), width: width)
            XCTAssertEqual(count, 1)
        }

        // Last wrapped line in buffer
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: Int32(totalWrappedLines - 1), length: 1), width: width)
            XCTAssertEqual(count, 1)
        }

        // Entire buffer
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 0, length: Int32(totalWrappedLines)), width: width)
            XCTAssertEqual(count, 3) // Total raw lines
        }
    }

    func testNumberOfRawLinesInRange_VaryingLengths() {
        let buffer = LineBuffer(blockSize: 140)
        let width = Int32(30)

        let scas = ["x",                                                                 // Very short (< width)
                    "This line is exactly 30 chars",                                     // Exactly at width
                    "This line is slightly over 30 characters in length",                // Slightly over width
                    "This is a very long line that will wrap multiple times because it contains a lot of text"].map {
            screenCharArrayWithDefaultStyle($0, eol: EOL_HARD)
        }
        for sca in scas {
            buffer.append(sca, width: width)
        }

        // Range covering very short line
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 0, length: 1), width: width)
            XCTAssertEqual(count, 1)
        }

        // Range covering line exactly at width
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 1, length: 1), width: width)
            XCTAssertEqual(count, 1)
        }

        // Range covering line slightly over width
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 2, length: 2), width: width)
            XCTAssertEqual(count, 1)
        }

        // Range covering very long line
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 4, length: 3), width: width)
            XCTAssertEqual(count, 1)
        }
    }

    // MARK: - Multi-line search across blocks

    /// Tests multi-line search when the pattern spans two LineBlocks.
    /// This test verifies a suspected bug: multi-line search fails to find
    /// matches that cross block boundaries.
    func testMultiLineSearchSpanningBlocks() {
        let buffer = LineBuffer()
        let width = Int32(80)

        // Add a line that will be in the first block
        let line1 = screenCharArrayWithDefaultStyle("first line", eol: EOL_HARD)
        buffer.append(line1, width: width)

        // Force the first block to be sealed, so subsequent lines go into a new block
        buffer.forceSeal()

        // Add a line that will be in the second block
        let line2 = screenCharArrayWithDefaultStyle("second line", eol: EOL_HARD)
        buffer.append(line2, width: width)

        // Verify we have two blocks by checking that block at index 1 exists
        // (testOnlyBlock will return the second block if forceSeal worked)
        let _ = buffer.testOnlyBlock(at: 1)

        // Search for a multi-line pattern that spans the block boundary
        // The pattern "first line\nsecond" should match if multi-line search works across blocks
        let context = FindContext()
        buffer.prepareToSearch(for: "first line\nsecond",
                               startingAt: buffer.firstPosition(),
                               options: .optMultiLine,
                               mode: .caseSensitiveSubstring,
                               with: context)

        // Search through the entire buffer
        while context.status == .Searching {
            buffer.findSubstring(context, stopAt: buffer.lastPosition())
        }

        // If the bug exists, the search will fail to find the match
        // because the pattern spans two blocks.
        // Expected: status should be .Matched if multi-line search works across blocks
        // Actual (with bug): status will be .NotFound
        XCTAssertEqual(context.status, .Matched,
                       "Multi-line search should find patterns spanning block boundaries")

        // Verify we have results and they're at the expected position
        XCTAssertNotNil(context.results)
        XCTAssertEqual(context.results?.count, 1, "Should have exactly one result")

        if let results = context.results as? [ResultRange], results.count > 0 {
            let xyRanges = buffer.convertPositions(results, withWidth: width)
            XCTAssertEqual(xyRanges?.count, 1)
            if let xyRange = xyRanges?.first {
                XCTAssertEqual(xyRange.yStart, 0, "Match should start on line 0")
                XCTAssertEqual(xyRange.xStart, 0, "Match should start at column 0")
            }
        }
    }

    /// Tests multi-line search when entire pattern is within a single block (should work).
    func testMultiLineSearchWithinSingleBlock() {
        let buffer = LineBuffer()
        let width = Int32(80)

        // Add two lines in the same block
        let line1 = screenCharArrayWithDefaultStyle("first line", eol: EOL_HARD)
        let line2 = screenCharArrayWithDefaultStyle("second line", eol: EOL_HARD)
        buffer.append(line1, width: width)
        buffer.append(line2, width: width)

        // Search for a multi-line pattern within the same block
        let context = FindContext()
        buffer.prepareToSearch(for: "first line\nsecond",
                               startingAt: buffer.firstPosition(),
                               options: .optMultiLine,
                               mode: .caseSensitiveSubstring,
                               with: context)

        // Search through the buffer
        while context.status == .Searching {
            buffer.findSubstring(context, stopAt: buffer.lastPosition())
        }

        // This should work since both lines are in the same block
        XCTAssertEqual(context.status, .Matched,
                       "Multi-line search should find patterns within a single block")

        // Verify we have results and they're at the expected position
        XCTAssertNotNil(context.results)
        XCTAssertEqual(context.results?.count, 1, "Should have exactly one result")

        if let results = context.results as? [ResultRange], results.count > 0 {
            let xyRanges = buffer.convertPositions(results, withWidth: width)
            XCTAssertEqual(xyRanges?.count, 1)
            if let xyRange = xyRanges?.first {
                XCTAssertEqual(xyRange.yStart, 0, "Match should start on line 0")
                XCTAssertEqual(xyRange.xStart, 0, "Match should start at column 0")
            }
        }
    }

    /// Tests backward multi-line search when entire pattern is within a single block.
    func testMultiLineSearchWithinSingleBlockBackwards() {
        let buffer = LineBuffer()
        let width = Int32(80)

        // Add three lines in the same block
        let line1 = screenCharArrayWithDefaultStyle("first line", eol: EOL_HARD)
        let line2 = screenCharArrayWithDefaultStyle("second line", eol: EOL_HARD)
        let line3 = screenCharArrayWithDefaultStyle("third line", eol: EOL_HARD)
        buffer.append(line1, width: width)
        buffer.append(line2, width: width)
        buffer.append(line3, width: width)

        // Search backward for a multi-line pattern within the same block
        let context = FindContext()
        buffer.prepareToSearch(for: "second line\nthird",
                               startingAt: buffer.penultimatePosition(),
                               options: [.optMultiLine, .optBackwards],
                               mode: .caseSensitiveSubstring,
                               with: context)

        // Search through the buffer
        while context.status == .Searching {
            buffer.findSubstring(context, stopAt: buffer.firstPosition())
        }

        // This should work since both lines are in the same block
        XCTAssertEqual(context.status, .Matched,
                       "Backward multi-line search should find patterns within a single block")

        // Verify we have results and they're at the expected position
        XCTAssertNotNil(context.results)
        XCTAssertEqual(context.results?.count, 1, "Should have exactly one result")

        if let results = context.results as? [ResultRange], results.count > 0 {
            let xyRanges = buffer.convertPositions(results, withWidth: width)
            XCTAssertEqual(xyRanges?.count, 1)
            if let xyRange = xyRanges?.first {
                XCTAssertEqual(xyRange.yStart, 1, "Match should start on line 1")
                XCTAssertEqual(xyRange.xStart, 0, "Match should start at column 0")
            }
        }
    }

    /// Tests backward multi-line search finds the last occurrence when there are multiple matches.
    func testMultiLineSearchWithinSingleBlockBackwardsFindsLastMatch() {
        let buffer = LineBuffer()
        let width = Int32(80)

        // Add lines with a repeated pattern
        let lines = ["hello", "world", "hello", "world", "end"]
        for line in lines {
            buffer.append(screenCharArrayWithDefaultStyle(line, eol: EOL_HARD), width: width)
        }

        // Search backward for "hello\nworld" - should find the second occurrence (lines 2-3)
        let context = FindContext()
        buffer.prepareToSearch(for: "hello\nworld",
                               startingAt: buffer.penultimatePosition(),
                               options: [.optMultiLine, .optBackwards],
                               mode: .caseSensitiveSubstring,
                               with: context)

        while context.status == .Searching {
            buffer.findSubstring(context, stopAt: buffer.firstPosition())
        }

        XCTAssertEqual(context.status, .Matched,
                       "Backward multi-line search should find the pattern")

        XCTAssertNotNil(context.results)
        XCTAssertEqual(context.results?.count, 1, "Should have exactly one result")

        if let results = context.results as? [ResultRange], results.count > 0 {
            let xyRanges = buffer.convertPositions(results, withWidth: width)
            XCTAssertEqual(xyRanges?.count, 1)
            if let xyRange = xyRanges?.first {
                // Should find the LAST occurrence (at line 2), not the first (at line 0)
                XCTAssertEqual(xyRange.yStart, 2, "Backward search should find the last occurrence at line 2")
                XCTAssertEqual(xyRange.xStart, 0, "Match should start at column 0")
            }
        }
    }

    /// Tests backward multi-line search spanning two blocks.
    func testMultiLineSearchSpanningBlocksBackwards() {
        let buffer = LineBuffer()
        let width = Int32(80)

        // Add a line that will be in the first block
        let line1 = screenCharArrayWithDefaultStyle("first line", eol: EOL_HARD)
        buffer.append(line1, width: width)

        // Force the first block to be sealed
        buffer.forceSeal()

        // Add a line that will be in the second block
        let line2 = screenCharArrayWithDefaultStyle("second line", eol: EOL_HARD)
        buffer.append(line2, width: width)

        // Verify we have two blocks
        let _ = buffer.testOnlyBlock(at: 1)

        // Search backward for a multi-line pattern that spans the block boundary
        let context = FindContext()
        buffer.prepareToSearch(for: "first line\nsecond",
                               startingAt: buffer.penultimatePosition(),
                               options: [.optMultiLine, .optBackwards],
                               mode: .caseSensitiveSubstring,
                               with: context)

        while context.status == .Searching {
            buffer.findSubstring(context, stopAt: buffer.firstPosition())
        }

        // This test verifies the bug: backward multi-line search should find patterns spanning blocks
        XCTAssertEqual(context.status, .Matched,
                       "Backward multi-line search should find patterns spanning block boundaries")

        if let results = context.results as? [ResultRange], results.count > 0 {
            let xyRanges = buffer.convertPositions(results, withWidth: width)
            XCTAssertEqual(xyRanges?.count, 1)
            if let xyRange = xyRanges?.first {
                XCTAssertEqual(xyRange.yStart, 0, "Match should start on line 0")
                XCTAssertEqual(xyRange.xStart, 0, "Match should start at column 0")
            }
        }
    }

    /// Tests multi-line search spanning three blocks to verify the bug with more complex scenarios.
    /// Tests multi-line search where the first query line partially matches a line
    /// and the match spans a block boundary. The query "8\n19\n20\n21\n22" should match
    /// within lines "18", "19", "20", "21", "22" with a block boundary between "20" and "21".
    func testMultiLineSearchPartialFirstLineSpanningBlocks() {
        let buffer = LineBuffer()
        let width = Int32(80)

        // Add lines 18-20 in first block
        for text in ["18", "19", "20"] {
            buffer.append(screenCharArrayWithDefaultStyle(text, eol: EOL_HARD), width: width)
        }
        buffer.forceSeal()

        // Add lines 21-22 in second block
        for text in ["21", "22"] {
            buffer.append(screenCharArrayWithDefaultStyle(text, eol: EOL_HARD), width: width)
        }

        // Verify two blocks
        let _ = buffer.testOnlyBlock(at: 1)

        // Search for "8\n19\n20\n21\n22" — the "8" should match the end of "18"
        let context = FindContext()
        buffer.prepareToSearch(for: "8\n19\n20\n21\n22",
                               startingAt: buffer.firstPosition(),
                               options: .optMultiLine,
                               mode: .caseSensitiveSubstring,
                               with: context)

        while context.status == .Searching {
            buffer.findSubstring(context, stopAt: buffer.lastPosition())
        }

        XCTAssertEqual(context.status, .Matched,
                       "Should find '8\\n19\\n20\\n21\\n22' spanning block boundary")

        XCTAssertEqual(context.results?.count, 1, "Should have exactly one result")

        if let results = context.results as? [ResultRange], results.count > 0 {
            let xyRanges = buffer.convertPositions(results, withWidth: width)
            XCTAssertEqual(xyRanges?.count, 1)
            if let xyRange = xyRanges?.first {
                XCTAssertEqual(xyRange.yStart, 0, "Match should start on line 0 (the '8' in '18')")
                XCTAssertEqual(xyRange.xStart, 1, "Match should start at column 1 (the '8' in '18')")
            }
        }

        // Also verify the full-line version works: "18\n19\n20\n21\n22"
        let context2 = FindContext()
        buffer.prepareToSearch(for: "18\n19\n20\n21\n22",
                               startingAt: buffer.firstPosition(),
                               options: .optMultiLine,
                               mode: .caseSensitiveSubstring,
                               with: context2)

        while context2.status == .Searching {
            buffer.findSubstring(context2, stopAt: buffer.lastPosition())
        }

        XCTAssertEqual(context2.status, .Matched,
                       "Should find '18\\n19\\n20\\n21\\n22' spanning block boundary")
    }

    /// Tests backward multi-line search spanning blocks where the first query line
    /// partially matches the end of a raw line. Searching for "1\n12\n13\n14\n1" backward
    /// in lines "11","12","13" | "14","15" (block boundary between 13 and 14).
    /// The "1" at the end must match the second "1" in "11", not the first.
    func testMultiLineSearchBackwardPartialFirstLineSpanningBlocks() {
        let buffer = LineBuffer()
        let width = Int32(80)

        // Block 1: lines "11", "12", "13"
        for text in ["11", "12", "13"] {
            buffer.append(screenCharArrayWithDefaultStyle(text, eol: EOL_HARD), width: width)
        }
        buffer.forceSeal()

        // Block 2: lines "14", "15"
        for text in ["14", "15"] {
            buffer.append(screenCharArrayWithDefaultStyle(text, eol: EOL_HARD), width: width)
        }

        // Verify two blocks
        let _ = buffer.testOnlyBlock(at: 1)

        // Search backward for "1\n12\n13\n14\n1"
        // The first query line "1" must match at position 1 in "11" (extending to end).
        // Lines "12","13" must match fully. "14" must match fully. "1" must match start of "15".
        let context = FindContext()
        buffer.prepareToSearch(for: "1\n12\n13\n14\n1",
                               startingAt: buffer.penultimatePosition(),
                               options: [.optMultiLine, .optBackwards],
                               mode: .caseSensitiveSubstring,
                               with: context)

        while context.status == .Searching {
            buffer.findSubstring(context, stopAt: buffer.firstPosition())
        }

        XCTAssertEqual(context.status, .Matched,
                       "Backward search for '1\\n12\\n13\\n14\\n1' should find match spanning blocks")

        XCTAssertEqual(context.results?.count, 1, "Should have exactly one result")

        if let results = context.results as? [ResultRange], results.count > 0 {
            let xyRanges = buffer.convertPositions(results, withWidth: width)
            XCTAssertEqual(xyRanges?.count, 1)
            if let xyRange = xyRanges?.first {
                XCTAssertEqual(xyRange.yStart, 0, "Match should start on line 0 (the '1' at end of '11')")
                XCTAssertEqual(xyRange.xStart, 1, "Match should start at column 1")
            }
        }
    }

    // Edge case: backward 2-line query where the block boundary falls between
    // the first and second query lines, and the first query line ("1") must
    // match at a non-zero position in "11" (position 1, extending to end).
    // This triggers a continuation with startIndex == N-1, where the current
    // code applies skip=0 on the first (and only) iteration, filtering out
    // the match at position 1.
    func testMultiLineSearchBackwardFirstQueryLineInPriorBlock() {
        let buffer = LineBuffer()
        let width = Int32(80)

        // Block 1: just "11"
        buffer.append(screenCharArrayWithDefaultStyle("11", eol: EOL_HARD), width: width)
        buffer.forceSeal()

        // Block 2: just "12"
        buffer.append(screenCharArrayWithDefaultStyle("12", eol: EOL_HARD), width: width)

        // Verify two blocks
        let _ = buffer.testOnlyBlock(at: 1)

        // Search backward for "1\n12".
        // "1" must match at the END of "11" (position 1, extending to end of line).
        // "12" must match at the START of "12" (position 0).
        // The block boundary falls between these two lines, so the continuation
        // has startIndex == 1 (N-1 for a 2-line query). The first iteration of
        // the continuation searches for the first query line "1" in block 1.
        let context = FindContext()
        buffer.prepareToSearch(for: "1\n12",
                               startingAt: buffer.penultimatePosition(),
                               options: [.optMultiLine, .optBackwards],
                               mode: .caseSensitiveSubstring,
                               with: context)

        while context.status == .Searching {
            buffer.findSubstring(context, stopAt: buffer.firstPosition())
        }

        XCTAssertEqual(context.status, .Matched,
                       "Backward search for '1\\n12' should find match spanning blocks where first query line is at non-zero position")

        XCTAssertEqual(context.results?.count, 1, "Should have exactly one result")

        if let results = context.results as? [ResultRange], results.count > 0 {
            let xyRanges = buffer.convertPositions(results, withWidth: width)
            XCTAssertEqual(xyRanges?.count, 1)
            if let xyRange = xyRanges?.first {
                XCTAssertEqual(xyRange.yStart, 0, "Match should start on line 0 ('11')")
                XCTAssertEqual(xyRange.xStart, 1, "Match should start at column 1 (the '1' at end of '11')")
            }
        }
    }

    func testMultiLineSearchSpanningThreeBlocks() {
        let buffer = LineBuffer()
        let width = Int32(80)

        // Add content to three separate blocks
        let line1 = screenCharArrayWithDefaultStyle("alpha", eol: EOL_HARD)
        buffer.append(line1, width: width)
        buffer.forceSeal()

        let line2 = screenCharArrayWithDefaultStyle("beta", eol: EOL_HARD)
        buffer.append(line2, width: width)
        buffer.forceSeal()

        let line3 = screenCharArrayWithDefaultStyle("gamma", eol: EOL_HARD)
        buffer.append(line3, width: width)

        // Verify we have three blocks by checking that block at index 2 exists
        let _ = buffer.testOnlyBlock(at: 2)

        // Search for a pattern spanning the first two blocks
        do {
            let context = FindContext()
            buffer.prepareToSearch(for: "alpha\nbeta",
                                   startingAt: buffer.firstPosition(),
                                   options: .optMultiLine,
                                   mode: .caseSensitiveSubstring,
                                   with: context)

            while context.status == .Searching {
                buffer.findSubstring(context, stopAt: buffer.lastPosition())
            }

            XCTAssertEqual(context.status, .Matched,
                           "Multi-line search should find 'alpha\\nbeta' spanning blocks 1-2")
        }

        // Search for a pattern spanning the last two blocks
        do {
            let context = FindContext()
            buffer.prepareToSearch(for: "beta\ngamma",
                                   startingAt: buffer.firstPosition(),
                                   options: .optMultiLine,
                                   mode: .caseSensitiveSubstring,
                                   with: context)

            while context.status == .Searching {
                buffer.findSubstring(context, stopAt: buffer.lastPosition())
            }

            XCTAssertEqual(context.status, .Matched,
                           "Multi-line search should find 'beta\\ngamma' spanning blocks 2-3")
        }

        // Search for a pattern spanning all three blocks
        do {
            let context = FindContext()
            buffer.prepareToSearch(for: "alpha\nbeta\ngamma",
                                   startingAt: buffer.firstPosition(),
                                   options: .optMultiLine,
                                   mode: .caseSensitiveSubstring,
                                   with: context)

            while context.status == .Searching {
                buffer.findSubstring(context, stopAt: buffer.lastPosition())
            }

            XCTAssertEqual(context.status, .Matched,
                           "Multi-line search should find 'alpha\\nbeta\\ngamma' spanning all 3 blocks")
        }
    }

    /// Tests that includesPartialLastLine is set when a cross-block multi-line
    /// match extends to the partial (non-hard-EOL) last line of the last block.
    func testMultiLineSearchSpanningBlocksSetsIncludesPartialLastLine() {
        let buffer = LineBuffer()
        let width = Int32(80)

        // Block 1: hard EOL line
        buffer.append(screenCharArrayWithDefaultStyle("first line", eol: EOL_HARD), width: width)
        buffer.forceSeal()

        // Block 2: soft EOL line (partial — no trailing newline)
        buffer.append(screenCharArrayWithDefaultStyle("second", eol: EOL_SOFT), width: width)

        // Verify two blocks
        let _ = buffer.testOnlyBlock(at: 1)

        // Search for a multi-line pattern that spans both blocks and includes
        // the partial last line of block 2.
        let context = FindContext()
        buffer.prepareToSearch(for: "first line\nsecond",
                               startingAt: buffer.firstPosition(),
                               options: .optMultiLine,
                               mode: .caseSensitiveSubstring,
                               with: context)

        while context.status == .Searching {
            buffer.findSubstring(context, stopAt: buffer.lastPosition())
        }

        XCTAssertEqual(context.status, .Matched,
                       "Should find 'first line\\nsecond' spanning blocks")
        XCTAssertTrue(context.includesPartialLastLine,
                      "includesPartialLastLine should be true when cross-block match touches partial last line")
    }

    // MARK: - stopAt Boundary Tests
    //
    // These tests verify the half-open interval semantics of the stopAt parameter:
    // - Forward search: [start, stopAt) - results at stopAt are EXCLUDED
    // - Backward search: (stopAt, start] - results at stopAt are INCLUDED

    /// Test that forward search excludes results at exactly the stopAt position.
    /// This test mirrors the scenario in testHaveMatchBehavior (AsyncFilterTests):
    /// - Multiple lines in the same block (no forceSeal)
    /// - Searching for a shorter string that exists on all lines
    /// - Using stopAt at the exact position of a match
    /// - The match at stopAt should be EXCLUDED (half-open interval semantics)
    func testForwardSearchExcludesMatchAtStopAtPosition() {
        let buffer = LineBuffer()
        let width = Int32(80)

        // Create three lines in the SAME block (no forceSeal)
        // This mirrors testHaveMatchBehavior which creates ["hello world", "hello there", "hello world again"]
        let s1 = screenCharArrayWithDefaultStyle("hello world", eol: EOL_HARD)
        buffer.append(s1, width: width)
        let posAfterLine1 = buffer.lastPosition()

        let s2 = screenCharArrayWithDefaultStyle("hello there", eol: EOL_HARD)
        buffer.append(s2, width: width)
        let posAfterLine2 = buffer.lastPosition()

        let s3 = screenCharArrayWithDefaultStyle("hello world again", eol: EOL_HARD)
        buffer.append(s3, width: width)

        // Search for "hello world" starting from line 2's position, with stopAt at line 3's position
        // This is exactly what haveMatch does: search within the bounds of line 2 for "hello world"
        // Line 2 is "hello there" which does NOT contain "hello world"
        // But without the fix, "hello world" from line 3 would be incorrectly found
        let context = FindContext()
        buffer.prepareToSearch(for: "hello world",
                               startingAt: posAfterLine1,
                               options: [],
                               mode: .caseSensitiveSubstring,
                               with: context)

        // Search with stopAt at the start of line 3
        buffer.findSubstring(context, stopAt: posAfterLine2)

        // Should NOT find a match because "hello there" does not contain "hello world"
        // The match "hello world" on line 3 starts at posAfterLine2, which is exactly stopAt
        // With the fix (>= instead of >), this match should be excluded
        XCTAssertEqual(context.status, .NotFound,
                       "Forward search should NOT find match at stopAt position")
    }

    /// Test that backward search includes results at exactly the stopAt position.
    /// This uses the same pattern as testConvertPositionMultiBlock which validates
    /// that backward search to firstPosition finds the match at position 0.
    func testBackwardSearchIncludesMatchAtStopAtPosition() {
        let buffer = LineBuffer()
        let width = Int32(80)
        // Same setup as testConvertPositionMultiBlock
        let s1 = screenCharArrayWithDefaultStyle("Hello world", eol: EOL_HARD)
        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world", eol: EOL_HARD)
        buffer.append(s1, width: width)
        buffer.forceSeal()
        buffer.append(s2, width: width)

        let context = FindContext()
        // Search backward for "Hello" starting from lastPosition
        buffer.prepareToSearch(for: "Hello",
                               startingAt: buffer.lastPosition(),
                               options: .optBackwards,
                               mode: .caseSensitiveSubstring,
                               with: context)

        // First call searches second block, doesn't find "Hello"
        buffer.findSubstring(context, stopAt: buffer.firstPosition())
        XCTAssertEqual(context.status, .Searching)

        // Second call searches first block, finds "Hello" at position 0
        // which equals firstPosition - this should be INCLUDED in backward search
        buffer.findSubstring(context, stopAt: buffer.firstPosition())
        XCTAssertEqual(context.status, .Matched,
                       "Backward search should include match at firstPosition (position 0)")

        // Verify the match is at position 0
        if let results = context.results as? [ResultRange], results.count > 0 {
            let xyRanges = buffer.convertPositions(results, withWidth: width)
            XCTAssertEqual(xyRanges?.first?.yStart, 0, "Match should be on line 0")
            XCTAssertEqual(xyRanges?.first?.xStart, 0, "Match should start at column 0")
        }
    }
}

extension LineBuffer {
    var allScreenCharArrays: [ScreenCharArray] {
        return (0..<numberOfUnwrappedLines()).compactMap { i in
            unwrappedLine(at: Int32(i))
        }
    }
    func allWrappedLines(width: Int32) -> [ScreenCharArray] {
        return (0..<numLines(withWidth: width)).map {
            wrappedLine(at: Int32($0), width: width)
        }
    }
    func allWrappedLinesAsStrings(width: Int32) -> [String] {
        return allWrappedLines(width: width).map {
            $0.stringValue + ($0.eol == EOL_HARD ? "\n" : "")
        }
    }
}


extension ScreenCharArray {
    static func create(string: String,
                       predecessor: (sct: screen_char_t, value: String, doubleWidth: Bool)?,
                       foreground: screen_char_t,
                       background: screen_char_t,
                       continuation: screen_char_t,
                       metadata: iTermMetadata,
                       ambiguousIsDoubleWidth: Bool,
                       normalization: iTermUnicodeNormalization,
                       unicodeVersion: Int) -> (sca: ScreenCharArray,
                                                predecessor: screen_char_t?,
                                                foundDWC: Bool) {
        let augmented = predecessor != nil
        let augmentedString = (predecessor?.value ?? " ") + string
        let malloced = malloc(3 * augmentedString.utf16.count * MemoryLayout<screen_char_t>.size)!
        let buffer = malloced.assumingMemoryBound(to: screen_char_t.self)
        var len = Int32(0)
        var cursorIndex = Int32(0)
        var foundDWC: ObjCBool = ObjCBool(false)
        var firstChar: screen_char_t? = nil
        var secondChar: screen_char_t? = nil
        withUnsafeMutablePointer(to: &len) { lenPtr in
            withUnsafeMutablePointer(to: &cursorIndex) { cursorIndexPtr in
                withUnsafeMutablePointer(to: &foundDWC) { foundDWCPtr in
                    StringToScreenChars(augmentedString,
                                        buffer,
                                        foreground,
                                        background,
                                        lenPtr,
                                        ambiguousIsDoubleWidth,
                                        cursorIndexPtr,
                                        foundDWCPtr,
                                        normalization,
                                        unicodeVersion,
                                        false,
                                        nil)
                }
            }
        }
        if len > 0 {
            firstChar = buffer[0]
            if len > 1 {
                secondChar = buffer[1]
            }
        }
        var bufferOffset = 0
        var modifiedPredecessor: screen_char_t? = nil
        if augmented, let firstChar = firstChar, let predecessor = predecessor {
            modifiedPredecessor = predecessor.sct
            modifiedPredecessor!.code = firstChar.code
            modifiedPredecessor!.complexChar = firstChar.complexChar
            bufferOffset += 1

            // Does the augmented result begin with a double-width character? If so skip over the
            // DWC_RIGHT when appending. I *think* this is redundant with the `predecessorIsDoubleWidth`
            // test but I'm reluctant to remove it because it could break something.
            if let secondChar = secondChar {
            let augmentedResultBeginsWithDoubleWidthCharacter = (augmented &&
                                                                 len > 1 &&
                                                                 secondChar.code == DWC_RIGHT &&
                                                                 secondChar.complexChar == 0)
                if ((augmentedResultBeginsWithDoubleWidthCharacter || predecessor.doubleWidth) &&
                    len > 1 &&
                    secondChar.code == DWC_RIGHT) {
                    // Skip over a preexisting DWC_RIGHT in the predecessor.
                    bufferOffset += 1
                }
            }
        } else if (firstChar?.complexChar ?? 0) == 0 {
            // We infer that the first character in |string| was not a combining mark. If it were, it
            // would have combined with the space we added to the start of |augmentedString|. Skip past
            // the space.
            bufferOffset += 1
        }
        let sca = ScreenCharArray(line: buffer,
                                  offset: bufferOffset,
                                  length: len - Int32(bufferOffset),
                                  metadata: iTermMetadataMakeImmutable(metadata),
                                  continuation: continuation,
                                  freeOnRelease: true)
        return (sca: sca,
                predecessor: modifiedPredecessor,
                foundDWC: foundDWC.boolValue)
    }
}

public extension screen_char_t {
    static var zero = screen_char_t(code: 0,
                                    foregroundColor: UInt32(ALTSEM_DEFAULT),
                                    fgGreen: 0,
                                    fgBlue: 0,
                                    backgroundColor: UInt32(ALTSEM_DEFAULT),
                                    bgGreen: 0,
                                    bgBlue: 0,
                                    foregroundColorMode: ColorModeAlternate.rawValue,
                                    backgroundColorMode: ColorModeAlternate.rawValue,
                                    complexChar: 0,
                                    bold: 0,
                                    faint: 0,
                                    italic: 0,
                                    blink: 0,
                                    underline: 0,
                                    image: 0,
                                    strikethrough: 0,
                                    underlineStyle0: VT100UnderlineStyle.single.rawValue & 3,
                                    invisible: 0,
                                    inverse: 0,
                                    guarded: 0,
                                    virtualPlaceholder: 0,
                                    rtlStatus: .unknown,
                                    underlineStyle1: 0,
                                    unused: 0)

    static let defaultForeground = screen_char_t(code: 0,
                                                 foregroundColor: UInt32(ALTSEM_DEFAULT),
                                                 fgGreen: 0,
                                                 fgBlue: 0,
                                                 backgroundColor: 0,
                                                 bgGreen: 0,
                                                 bgBlue: 0,
                                                 foregroundColorMode: ColorModeAlternate.rawValue,
                                                 backgroundColorMode: 0,
                                                 complexChar: 0,
                                                 bold: 0,
                                                 faint: 0,
                                                 italic: 0,
                                                 blink: 0,
                                                 underline: 0,
                                                 image: 0,
                                                 strikethrough: 0,
                                                 underlineStyle0: VT100UnderlineStyle.single.rawValue & 3,
                                                 invisible: 0,
                                                 inverse: 0,
                                                 guarded: 0,
                                                 virtualPlaceholder: 0,
                                                 rtlStatus: .unknown,
                                                 underlineStyle1: 0,
                                                 unused: 0)

    static let defaultBackground = screen_char_t(code: 0,
                                                 foregroundColor: 0,
                                                 fgGreen: 0,
                                                 fgBlue: 0,
                                                 backgroundColor: UInt32(ALTSEM_DEFAULT),
                                                 bgGreen: 0,
                                                 bgBlue: 0,
                                                 foregroundColorMode: 0,
                                                 backgroundColorMode: ColorModeAlternate.rawValue,
                                                 complexChar: 0,
                                                 bold: 0,
                                                 faint: 0,
                                                 italic: 0,
                                                 blink: 0,
                                                 underline: 0,
                                                 image: 0,
                                                 strikethrough: 0,
                                                 underlineStyle0: VT100UnderlineStyle.single.rawValue & 3,
                                                 invisible: 0,
                                                 inverse: 0,
                                                 guarded: 0,
                                                 virtualPlaceholder: 0,
                                                 rtlStatus: .unknown,
                                                 underlineStyle1: 0,
                                                 unused: 0)

    func with(code: unichar) -> screen_char_t {
        return screen_char_t(code: code,
                             foregroundColor: foregroundColor,
                             fgGreen: fgGreen,
                             fgBlue: fgBlue,
                             backgroundColor: backgroundColor,
                             bgGreen: bgGreen,
                             bgBlue: bgBlue,
                             foregroundColorMode: foregroundColorMode,
                             backgroundColorMode: backgroundColorMode,
                             complexChar: 0,
                             bold: bold,
                             faint: faint,
                             italic: italic,
                             blink: blink,
                             underline: underline,
                             image: 0,
                             strikethrough: strikethrough,
                             underlineStyle0: underlineStyle.part0,
                             invisible: invisible,
                             inverse: inverse,
                             guarded: guarded,
                             virtualPlaceholder: 0,
                             rtlStatus: .unknown,
                             underlineStyle1: underlineStyle.part1,
                             unused: unused)
    }
}

func screenCharArrayWithDefaultStyle(_ string: String, eol: Int32) -> ScreenCharArray {
    let sca = ScreenCharArray.create(string: string,
                                  predecessor: nil,
                                  foreground: screen_char_t.defaultForeground,
                                  background: screen_char_t.defaultBackground,
                                  continuation: screen_char_t.defaultForeground.with(code: unichar(eol)),
                                  metadata: iTermMetadataDefault(),
                                  ambiguousIsDoubleWidth: false,
                                  normalization: .none,
                                  unicodeVersion: 9).sca
    let msca = sca.mutableCopy() as! MutableScreenCharArray
    let line = msca.mutableLine
    for i in 0..<Int(msca.length) {
        if line[i].code == "-".utf16.first! {
            line[i].code = UInt16(DWC_RIGHT)
        } else if line[i].code == ">".utf16.first! && i == Int(msca.length - 1) {
            line[i].code = UInt16(DWC_SKIP)
            msca.eol = EOL_DWC
        }
    }
    return msca
}
