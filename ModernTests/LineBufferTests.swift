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

        // Keep each raw line short enough to fit in one wrapped line so the
        // expected raw-line count in a wrapped range is deterministic.
        let scas = ["日本語",
                    "中文",
                    "ASCII"].map {
            screenCharArrayWithDefaultStyle($0, eol: EOL_HARD)
        }
        for sca in scas {
            buffer.append(sca, width: width)
        }

        // First 3 wrapped lines correspond to exactly 3 raw lines.
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 0, length: 3), width: width)
            XCTAssertEqual(count, 3)
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
        let width = Int32(200)

        // Add enough content to span multiple blocks
        var scas: [ScreenCharArray] = []
        for i in 0..<20 {
            scas.append(screenCharArrayWithDefaultStyle("Line \(i)", eol: EOL_HARD))
        }
        for sca in scas {
            buffer.append(sca, width: width)
        }

        XCTAssertGreaterThan(buffer.testOnlyNumberOfBlocks, 1)

        // Range spanning 2 blocks
        do {
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 10, length: 10), width: width)
            XCTAssertEqual(count, 10)
        }

        // Range spanning 3+ blocks
        do {
            let totalWrappedLines = buffer.numLines(withWidth: width)
            XCTAssertEqual(totalWrappedLines, 20)
            let count = buffer.numberOfUnwrappedLines(in: .init(location: 5, length: Int32(totalWrappedLines - 10)), width: width)
            XCTAssertEqual(count, 10)
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

    // MARK: - Bulk partial append

    /// Verify that appending many all-partial items via appendLines:width:
    /// distributes them across multiple blocks rather than concentrating them
    /// in a single ever-growing block. This guards against a regression where
    /// the one-at-a-time loop in appendLines: processed every partial item
    /// into one block, causing O(n^2) COW clone cost.
    func testBulkPartialAppendCreatesMultipleBlocks() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        // Seed the buffer with a partial line so lastBlock.hasPartial is true.
        buffer.append(screenCharArrayWithDefaultStyle("seed", eol: EOL_SOFT),
                      width: width)
        XCTAssertEqual(buffer.testOnlyNumberOfBlocks, 1)

        // Append 100 partial items through the bulk path.
        buffer.testOnlyAppendPartialItems(100, ofLength: 40, width: width)

        // With the fix, the first item continues the existing partial in block 0,
        // and the remaining 99 go to a new block via initWithItems:.
        // Without the fix, all 100 would be appended one-at-a-time into block 0.
        XCTAssertGreaterThan(buffer.testOnlyNumberOfBlocks, 1,
                             "Bulk partial items should create a new block, not grow one block indefinitely")

        // All items are partial, so there is exactly 1 raw (unwrapped) line.
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1,
                       "All partial items should form a single raw line across blocks")

        // Verify data integrity: total character count should match.
        // seed = 4 chars, 100 items × 40 chars = 4004 total.
        let totalChars = (0..<buffer.numLines(withWidth: width)).reduce(0) { sum, i in
            sum + Int(buffer.wrappedLine(at: i, width: width).length)
        }
        XCTAssertEqual(totalChars, 4 + 100 * 40)

        // Verify wrapped line count: ceil((4 + 4000) / 80) = ceil(4004/80) = 51
        let expectedWrappedLines = (4 + 100 * 40 + Int(width) - 1) / Int(width)
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), expectedWrappedLines)
    }

    /// Verify that the bulk path correctly handles a mix of partial and
    /// non-partial items (the common CRLF case should not regress).
    func testBulkAppendWithNonPartialItemsPreservesLineBreaks() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        // Append a partial line followed by a hard line to seed.
        buffer.append(screenCharArrayWithDefaultStyle("partial", eol: EOL_SOFT),
                      width: width)
        buffer.append(screenCharArrayWithDefaultStyle("complete", eol: EOL_HARD),
                      width: width)

        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)
        // The single raw line should contain "partialcomplete".
        let line = buffer.unwrappedLine(at: 0)
        XCTAssertEqual(line.stringValue, "partialcomplete")
    }

    /// Verify cross-block partial lines with items that are exact multiples of width.
    /// This is the most common case (full screen rows with no CRLFs).
    func testBulkPartialAppendWithWidthAlignedItems() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        // Seed with a full-width partial line.
        buffer.testOnlyAppendPartialItems(1, ofLength: 80, width: width)

        // Now append more full-width partial items through the bulk path.
        buffer.testOnlyAppendPartialItems(50, ofLength: 80, width: width)

        // Should have multiple blocks.
        XCTAssertGreaterThan(buffer.testOnlyNumberOfBlocks, 1)

        // All partial → 1 raw line.
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)

        // 51 items × 80 chars = 4080 total chars.
        // At width 80: 4080 / 80 = 51 wrapped lines.
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), 51)

        // Verify total character count.
        let totalChars = (0..<buffer.numLines(withWidth: width)).reduce(0) { sum, i in
            sum + Int(buffer.wrappedLine(at: i, width: width).length)
        }
        XCTAssertEqual(totalChars, 51 * 80)
    }

    /// Verify that a hard EOL after cross-block partials starts a new raw line.
    /// Uses width-aligned items to avoid boundary data-loss edge cases.
    func testBulkPartialFollowedByHardEOL() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        // Use width-aligned seed so the continuation block starts aligned.
        buffer.testOnlyAppendPartialItems(1, ofLength: 80, width: width)

        // Append more width-aligned partial items through bulk path.
        buffer.testOnlyAppendPartialItems(5, ofLength: 80, width: width)

        // Now append a full-width hard EOL line.
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "W", count: 80), eol: EOL_HARD),
                      width: width)

        // Should have 1 raw line: 7×80 = 560 chars
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)

        // Total chars: 7 × 80 = 560
        let totalChars = (0..<buffer.numLines(withWidth: width)).reduce(0) { sum, i in
            sum + Int(buffer.wrappedLine(at: i, width: width).length)
        }
        XCTAssertEqual(totalChars, 560)

        // Wrapped lines: 560/80 = 7
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), 7)
    }

    /// Verify that multiple rounds of bulk partial appends produce correct results.
    func testRepeatedBulkPartialAppends() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        // Simulate multiple rounds of bulk appends (like periodic syncs).
        for _ in 0..<5 {
            buffer.testOnlyAppendPartialItems(20, ofLength: 80, width: width)
        }

        // All partial → 1 raw line.
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)

        // 100 items × 80 chars = 8000 total.
        // At width 80: 8000 / 80 = 100 wrapped lines.
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), 100)

        // Verify character count.
        let totalChars = (0..<buffer.numLines(withWidth: width)).reduce(0) { sum, i in
            sum + Int(buffer.wrappedLine(at: i, width: width).length)
        }
        XCTAssertEqual(totalChars, 100 * 80)
    }
    /// Verify correct wrapped-line content when a misaligned prefix triggers
    /// the alignment loop. Seed=60, items=5×100, width=80.
    /// The alignment loop consumes the first item (60+100=160, charsAppended=100>=80, break).
    /// Block 0 has 160 chars. Continuation has 4×100=400 chars, P=160, P%80=0.
    /// Adjustment=0 — no boundary data loss.
    func testBulkPartialWithMisalignedPrefix() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        // Seed with a 60-char partial line.
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "A", count: 60), eol: EOL_SOFT),
                      width: width)
        XCTAssertEqual(buffer.testOnlyNumberOfBlocks, 1)

        // Append 5 × 100-char items. Alignment loop takes 1 item into block 0
        // (charsAppended=100 >= width=80), remaining 4 go to continuation block.
        buffer.testOnlyAppendPartialItems(5, ofLength: 100, width: width)

        // All partial → 1 raw line.
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)

        // Total chars: 60 + 500 = 560. Wrapped: ceil(560/80) = 7.
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), 7)

        // Block 0 has 160 chars (60 seed + 100 first item). P=160, P%80=0.
        // No boundary data loss. Verify exact total char count.
        let totalChars = (0..<buffer.numLines(withWidth: width)).reduce(0) { sum, i in
            sum + Int(buffer.wrappedLine(at: i, width: width).length)
        }
        XCTAssertEqual(totalChars, 560)

        // Verify exact per-line lengths. Block 0: 160 chars = 2×80.
        // Continuation: 400 chars = 5×80.
        for i: Int32 in 0..<buffer.numLines(withWidth: width) {
            let sca = buffer.wrappedLine(at: i, width: width)
            XCTAssertEqual(sca.length, 80,
                           "Line \(i) should be exactly 80 chars (width-aligned)")
        }
    }

    // MARK: - Continuation: resize (width change)

    /// After building cross-block continuation at width 80, querying at a different
    /// width should produce correct wrapped-line counts. This tests that
    /// continuationPrefixCharacters stores total chars (not columns), so the
    /// adjustment is recomputed correctly for any width.
    func testContinuationResizeWidth() {
        let buffer = LineBuffer()
        let originalWidth: Int32 = 80
        let totalChars = 60 + 5 * 100 // = 560

        // Seed with a 60-char partial line.
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "A", count: 60), eol: EOL_SOFT),
                      width: originalWidth)

        // Append 5 × 100-char items through the bulk path at width 80.
        buffer.testOnlyAppendPartialItems(5, ofLength: 100, width: originalWidth)

        // Verify at original width.
        XCTAssertEqual(Int(buffer.numLines(withWidth: originalWidth)),
                       (totalChars + Int(originalWidth) - 1) / Int(originalWidth))

        // Now query at a different width — the continuation adjustment must recompute
        // using continuationPrefixCharacters % newWidth.
        let newWidth: Int32 = 120
        let expectedWrapped = (totalChars + Int(newWidth) - 1) / Int(newWidth) // ceil(560/120) = 5
        XCTAssertEqual(Int(buffer.numLines(withWidth: newWidth)), expectedWrapped)

        // Also verify at a narrower width.
        let narrowWidth: Int32 = 50
        let expectedNarrow = (totalChars + Int(narrowWidth) - 1) / Int(narrowWidth) // ceil(560/50) = 12
        XCTAssertEqual(Int(buffer.numLines(withWidth: narrowWidth)), expectedNarrow)

        // With the alignment loop, P=160 (60+100), P%80=0, so at the original
        // width the continuation block is aligned. Verify exact char count there.
        let readCharsOriginal = (0..<buffer.numLines(withWidth: originalWidth)).reduce(0) { sum, i in
            sum + Int(buffer.wrappedLine(at: i, width: originalWidth).length)
        }
        XCTAssertEqual(readCharsOriginal, totalChars,
                       "Total chars at original width should equal \(totalChars)")

        // At other widths, verify readback remains lossless.
        for w: Int32 in [newWidth, narrowWidth] {
            let readChars = (0..<buffer.numLines(withWidth: w)).reduce(0) { sum, i in
                sum + Int(buffer.wrappedLine(at: i, width: w).length)
            }
            XCTAssertEqual(readChars, totalChars,
                           "Read chars at width \(w) should exactly match total chars")
        }
    }

    /// Width-aligned continuation (P % width == 0) should produce adjustment == 0
    /// regardless of the width queried.
    func testContinuationResizeWidthAligned() {
        let buffer = LineBuffer()
        let originalWidth: Int32 = 80

        // 80-char seed (P=80, P%80=0).
        buffer.testOnlyAppendPartialItems(1, ofLength: 80, width: originalWidth)
        buffer.testOnlyAppendPartialItems(10, ofLength: 80, width: originalWidth)

        let totalChars = 11 * 80

        // At original width: 880/80 = 11
        XCTAssertEqual(Int(buffer.numLines(withWidth: originalWidth)), 11)

        // At width 40 (divides evenly): 880/40 = 22
        XCTAssertEqual(Int(buffer.numLines(withWidth: 40)), 22)

        // At width 160 (multiple of original): 880/160 = 5.5 → 6
        let w160 = (totalChars + 159) / 160
        XCTAssertEqual(Int(buffer.numLines(withWidth: 160)), w160)
    }

    // MARK: - Continuation: block dropping

    /// Dropping the first block when the second block starts with continuation
    /// should clear the continuation and produce correct line counts.
    func testDropFirstBlockClearsContinuation() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        // Seed with a 60-char partial.
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 60), eol: EOL_SOFT),
                      width: width)

        // Bulk append to create a continuation block.
        buffer.testOnlyAppendPartialItems(5, ofLength: 100, width: width)

        let blocksBefore = buffer.testOnlyNumberOfBlocks
        XCTAssertGreaterThan(blocksBefore, 1)

        // Second block should start with continuation.
        let block1 = buffer.testOnlyBlock(at: 1)
        XCTAssertTrue(block1.startsWithContinuation)

        // Set max lines low enough to force dropping the first block.
        // With the alignment loop, the first block has 2 wrapped lines
        // (160 chars at width 80). Total wrapped = 7 (ceil(560/80)).
        let totalWrapped = Int(buffer.numLines(withWidth: width))
        buffer.setMaxLines(Int32(totalWrapped - 2))
        let _ = buffer.dropExcessLines(withWidth: width)

        // The former second block is now the first block and should NOT
        // start with continuation anymore.
        let newFirst = buffer.testOnlyBlock(at: 0)
        XCTAssertFalse(newFirst.startsWithContinuation,
                       "After dropping the first block, the new head should not have continuation")

        // Still one logical raw line (just with a shorter prefix).
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)
    }

    /// Verify that dropping the head block with a continuing successor
    /// produces correct raw-line and wrapped-line counts.
    /// Bug: totalRawLinesDropped used block.numRawLines directly without
    /// accounting for the successor's first raw line surviving as standalone.
    /// And total_lines didn't account for the successor's wrapped count
    /// changing when its continuation was cleared.
    func testDropHeadBlockWithContinuationAccountsForRestoredLine() {
        let buffer = LineBuffer(blockSize: 1000)
        let width: Int32 = 80

        // Seed: 5 chars (misaligned, gcd(30,80)=10, 5 not divisible by 10).
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "A", count: 5),
                                                      eol: EOL_SOFT),
                      width: width)

        // Items of length 30. Alignment loop consumes 3 items (90 chars, >= width 80 cap).
        // Block 0: 5 + 3*30 = 95 chars, 1 raw line.
        // Block 1: continuation, P=95, P%80=15, 7 remaining items = 210 chars.
        // Continuation adjustment at width 80 = -1.
        buffer.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        XCTAssertGreaterThan(buffer.testOnlyNumberOfBlocks, 1)
        let block1 = buffer.testOnlyBlock(at: 1)
        XCTAssertTrue(block1.startsWithContinuation)

        let totalChars = 5 + 10 * 30  // 305
        let totalWrapped = Int(buffer.numLines(withWidth: width))
        let expectedWrapped = (totalChars + Int(width) - 1) / Int(width)  // ceil(305/80) = 4
        XCTAssertEqual(totalWrapped, expectedWrapped)
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)

        // Block 0 has 2 naive wrapped lines (95 chars at width 80: ceil(95/80) = 2).
        // Block 1 contributed 2 wrapped lines (naive 3, adjustment -1).
        // Total = 4. Set max to 2 to force dropping block 0.
        //
        // After block 0 is dropped, the successor's continuation is cleared, so
        // its wrapped count goes from contributed=2 to naive=3. total_lines becomes
        // 4 - 2 (block 0 lines) - (-1) (undo adjustment) = 3. Since 3 > 2 (max),
        // the loop continues and drops 1 more line from the (now standalone) head.
        // Net dropped = block_lines + successorAdjustment + 1 more = 2 + (-1) + 1 = 2.
        buffer.setMaxLines(Int32(totalWrapped - 2))
        let dropped = buffer.dropExcessLines(withWidth: width)
        XCTAssertEqual(Int(dropped), totalWrapped - Int(buffer.numLines(withWidth: width)),
                       "Dropped count must equal the actual difference in wrapped line counts")

        let remainingWrapped = Int(buffer.numLines(withWidth: width))
        XCTAssertEqual(remainingWrapped, 2,
                       "After dropping to max_lines=2, should have exactly 2 wrapped lines")

        // Raw line count: the surviving data is still one logical raw line.
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)
    }

    /// Dropping all blocks via clear should work without crashing.
    func testClearWithContinuationBlocks() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "Z", count: 40), eol: EOL_SOFT),
                      width: width)
        buffer.testOnlyAppendPartialItems(20, ofLength: 80, width: width)

        XCTAssertGreaterThan(buffer.testOnlyNumberOfBlocks, 1)

        // Clear should not crash even with continuation blocks.
        buffer.setMaxLines(0)
        let _ = buffer.dropExcessLines(withWidth: width)

        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), 0)
    }

    // MARK: - Continuation: three-block chain

    /// Verify that a chain of 3+ continuation blocks (seed → bulk → bulk)
    /// maintains correct counts and data throughout.
    func testThreeBlockContinuationChain() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        // Seed: 30-char partial.
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "A", count: 30), eol: EOL_SOFT),
                      width: width)

        // First bulk: creates block 1 as continuation of block 0.
        buffer.testOnlyAppendPartialItems(10, ofLength: 80, width: width)

        // Second bulk: creates block 2 as continuation of block 1.
        buffer.testOnlyAppendPartialItems(10, ofLength: 80, width: width)

        let totalChars = 30 + 20 * 80 // = 1630

        // All partial → 1 raw line.
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)
        XCTAssertGreaterThanOrEqual(buffer.testOnlyNumberOfBlocks, 3)

        // Wrapped lines: ceil(1630/80) = 21 (since 1630/80 = 20.375)
        let expectedWrapped = (totalChars + Int(width) - 1) / Int(width)
        XCTAssertEqual(expectedWrapped, 21)
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), expectedWrapped)

        // Verify total character count.
        let readChars = (0..<buffer.numLines(withWidth: width)).reduce(0) { sum, i in
            sum + Int(buffer.wrappedLine(at: i, width: width).length)
        }
        XCTAssertEqual(readChars, totalChars)

        // Verify at a different width too.
        let altWidth: Int32 = 100
        let expectedAlt = (totalChars + Int(altWidth) - 1) / Int(altWidth)
        XCTAssertEqual(Int(buffer.numLines(withWidth: altWidth)), expectedAlt)
    }

    // MARK: - Continuation: position conversion

    /// Verify that coordinate/position lookup works correctly when data
    /// spans continuation blocks. This exercises slow_blockContainingPosition
    /// which was recently fixed to apply continuation adjustments.
    func testPositionConversionWithContinuation() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        // Seed with a 60-char partial (misaligned).
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "P", count: 60), eol: EOL_SOFT),
                      width: width)

        // Bulk append 5 × 100-char items. Total = 560 chars, 7 wrapped lines.
        buffer.testOnlyAppendPartialItems(5, ofLength: 100, width: width)

        let numWrapped = buffer.numLines(withWidth: width)
        XCTAssertEqual(numWrapped, 7)

        // With alignment loop, block 0 has 160 chars (60+100), P%80=0.
        // No boundary data loss. Verify exact total char count.
        let totalChars = (0..<numWrapped).reduce(0) { sum, i in
            sum + Int(buffer.wrappedLine(at: i, width: width).length)
        }
        XCTAssertEqual(totalChars, 560)

        // Verify exact position-to-grid mapping at several known offsets.
        let ranges = [
            ResultRange(position: 0, length: 1),    // row 0, col 0
            ResultRange(position: 79, length: 1),   // row 0, col 79
            ResultRange(position: 80, length: 1),   // row 1, col 0
            ResultRange(position: 559, length: 1),  // row 6, col 79
        ]
        let xy = buffer.convertPositions(ranges, withWidth: width)
        XCTAssertEqual(xy?.count, 4)

        XCTAssertEqual(xy?[0].yStart, 0)
        XCTAssertEqual(xy?[0].xStart, 0)

        XCTAssertEqual(xy?[1].yStart, 0)
        XCTAssertEqual(xy?[1].xStart, 79)

        XCTAssertEqual(xy?[2].yStart, 1)
        XCTAssertEqual(xy?[2].xStart, 0)

        XCTAssertEqual(xy?[3].yStart, 6)
        XCTAssertEqual(xy?[3].xStart, 79)
    }

    // MARK: - Continuation: mixed partial and non-partial across blocks

    /// Test that appending a hard EOL after continuation blocks then
    /// appending more partials works correctly — the hard EOL should
    /// start a new raw line.
    func testContinuationThenHardEOLThenMorePartials() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        // Use width-aligned items so there are no cross-block boundary issues.
        // Seed + bulk partials → 1 raw line.
        buffer.testOnlyAppendPartialItems(1, ofLength: 80, width: width)
        buffer.testOnlyAppendPartialItems(5, ofLength: 80, width: width)

        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)

        // Hard EOL completes the first raw line.
        // "end" is 3 chars, making partial line 6*80+3 = 483 chars.
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "E", count: 80), eol: EOL_HARD),
                      width: width)
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1) // Still 1 (the hard EOL completes, not adds)

        // Start a new partial line.
        buffer.testOnlyAppendPartialItems(1, ofLength: 80, width: width)
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 2) // Now 2: completed line + new partial

        // More bulk partials continuing the new line.
        buffer.testOnlyAppendPartialItems(3, ofLength: 80, width: width)
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 2) // Still 2

        // Verify total chars: 7*80 (first raw line) + 4*80 (second raw line) = 880
        let totalChars = 7 * 80 + 4 * 80
        let readChars = (0..<buffer.numLines(withWidth: width)).reduce(0) { sum, i in
            sum + Int(buffer.wrappedLine(at: i, width: width).length)
        }
        XCTAssertEqual(readChars, totalChars)

        // Wrapped lines: 880 / 80 = 11
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), 11)
    }

    // MARK: - Continuation: critical adjustment case

    /// Test that a short bulk item that completes a width-aligned line gets
    /// consumed by the alignment loop into block 0, producing no continuation
    /// block and no boundary data loss.
    ///
    /// Seed=60, item=20 chars. Alignment loop: 60+20=80, 80%80=0, break.
    /// All items consumed into block 0. No continuation block created.
    func testContinuationAdjustmentExactWrappedLineSequence() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        // Seed: 60-char partial line of 'A'.
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "A", count: 60), eol: EOL_SOFT),
                      width: width)

        // Bulk: 1 item of 20 chars. The alignment loop consumes it into block 0
        // (60+20=80, logicalPrefix%80=0, break). No continuation block needed.
        buffer.testOnlyAppendPartialItems(1, ofLength: 20, width: width)

        // Total: 80 chars = exactly 1 wrapped line.
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), 1)
        // All data stays in block 0 — no continuation block.
        XCTAssertEqual(buffer.testOnlyNumberOfBlocks, 1)

        // The single wrapped line should be exactly 80 chars.
        let line0 = buffer.wrappedLine(at: 0, width: width)
        XCTAssertEqual(line0.length, 80)
    }

    /// Test continuation with multiple items and misaligned prefix.
    /// Seed=50, items=3×80 chars. Alignment loop: 50+80=130, charsAppended=80>=80, break.
    /// Block 0 has 130 chars. Continuation has 2×80=160 chars, P=130, P%80=50.
    /// Adjustment=0 (correct==naive for these values). Verify counts/size
    /// invariants without asserting a specific cross-block boundary split.
    func testContinuationAdjustmentMultipleItems() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        // Seed: 50-char partial.
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "B", count: 50), eol: EOL_SOFT),
                      width: width)

        // Bulk: 3 items of 80 chars each.
        // Alignment loop takes 1 (50+80=130, charsAppended=80>=80, break).
        // Block 0: 130 chars. Continuation: 160 chars, P=130, P%80=50.
        // Total: 290 chars. Wrapped: ceil(290/80) = 4.
        buffer.testOnlyAppendPartialItems(3, ofLength: 80, width: width)

        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), 4)

        // Verify all returned wrapped lines are non-empty and width-bounded.
        // This test intentionally avoids pinning a specific boundary split
        // across blocks.
        var totalChars = 0
        for i: Int32 in 0..<buffer.numLines(withWidth: width) {
            let sca = buffer.wrappedLine(at: i, width: width)
            XCTAssertGreaterThan(sca.length, 0, "Line \(i) should be non-empty")
            XCTAssertLessThanOrEqual(sca.length, width, "Line \(i) should not exceed width")
            totalChars += Int(sca.length)
        }

        // Total read should equal total stored chars.
        XCTAssertEqual(totalChars, 290)
    }

    /// Test that the alignment loop in appendLines:width: prevents adjustment=-1.
    ///
    /// Seed = 60-char partial. appendLines with 4 items of 10 chars each.
    /// The alignment loop appends items one-at-a-time until block 0's char count
    /// aligns to width: 60+10=70 (not aligned), 70+10=80 (aligned, break).
    /// Remaining 2 items (20 chars) go to continuation block with P=80, P%80=0.
    /// Adjustment = 0 — no hidden lines, no data loss at boundary.
    func testAlignmentLoopPreventsAdjustmentNegativeOne() {
        let buffer = LineBuffer()
        let width: Int32 = 80

        // Seed: 60-char partial.
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "D", count: 60), eol: EOL_SOFT),
                      width: width)

        // Bulk: 4 items of 10 chars each.
        // Alignment loop: appends 2 items to block 0 (60+20=80, aligned).
        // Remaining 2 items (20 chars) → continuation block with P=80.
        buffer.testOnlyAppendPartialItems(4, ofLength: 10, width: width)

        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)

        // Total chars: 80 + 20 = 100. Wrapped = ceil(100/80) = 2.
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), 2)

        // Line 0: block 0 has 80 chars (full width). No short boundary line.
        let l0 = buffer.wrappedLine(at: 0, width: width)
        XCTAssertEqual(l0.length, 80, "Line 0 should be a full 80-char wrapped line")

        // Line 1: continuation block's 20 chars. No hidden lines (adjustment=0).
        let l1 = buffer.wrappedLine(at: 1, width: width)
        XCTAssertEqual(l1.length, 20, "Line 1 should be the remaining 20 chars")

        // Total read = total stored. No lost chars.
        XCTAssertEqual(Int(l0.length) + Int(l1.length), 100)
    }

    /// Verify wrapped line count consistency across multiple widths for
    /// continuation blocks — each width should produce
    /// ceil(totalChars / width) wrapped lines.
    func testContinuationWrappedCountConsistencyAcrossWidths() {
        let buffer = LineBuffer()
        let width: Int32 = 80
        let totalChars = 45 + 8 * 100 // = 845

        // Seed with a 45-char partial (misaligned for most widths).
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "Q", count: 45), eol: EOL_SOFT),
                      width: width)
        buffer.testOnlyAppendPartialItems(8, ofLength: 100, width: width)

        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)

        // Test a variety of widths.
        for w: Int32 in [40, 50, 60, 70, 80, 90, 100, 120, 160, 200] {
            let expected = (totalChars + Int(w) - 1) / Int(w)
            XCTAssertEqual(Int(buffer.numLines(withWidth: w)), expected,
                           "At width \(w): expected \(expected) wrapped lines for \(totalChars) chars")
        }
    }

    /// Verify that numLines is consistent with wrappedLine readback when the
    /// alignment loop cap fires before achieving alignment, producing a
    /// continuation block with adjustment == -1 at the creation width.
    /// Bug: convertPositions, removeLastWrappedLines, and
    /// numBlocksAtEndToGetMinimumLines used naive getNumLinesWithWrapWidth:
    /// to accumulate counts across blocks, causing drift.
    func testMisalignedPrefixFromCapWrappedLineCount() {
        let buffer = LineBuffer(blockSize: 1000)
        let width: Int32 = 80

        // Seed with a 5-char partial (5 % 80 != 0, misaligned).
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                      eol: EOL_SOFT),
                      width: width)

        // Append items of length 30. gcd(30, 80) = 10; 5 is not divisible
        // by 10, so alignment is unreachable. The loop appends until
        // charsAppendedInLoop >= width, consuming 3 items (90 chars), then
        // breaks. The continuation block gets prefixCharacters = 5 + 90 = 95,
        // where P % 80 = 15 and the wrapped-line adjustment is -1.
        buffer.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        XCTAssertGreaterThan(buffer.testOnlyNumberOfBlocks, 1)
        let block1 = buffer.testOnlyBlock(at: 1)
        XCTAssertTrue(block1.startsWithContinuation,
                      "Misaligned cap case should create a continuation block")

        let totalChars = 5 + 10 * 30  // 305

        // Verify the wrapped line count is correct.
        let expectedWrapped = (totalChars + Int(width) - 1) / Int(width)  // ceil(305/80) = 4
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), expectedWrapped,
                       "Wrapped line count should be correct even with misaligned cap")

        // Verify readback is fully lossless as well, not just count-correct.
        let readBackChars = (0..<buffer.numLines(withWidth: width)).reduce(0) { sum, i in
            sum + Int(buffer.wrappedLine(at: i, width: width).length)
        }
        XCTAssertEqual(readBackChars, totalChars,
                       "Wrapped-line readback must not lose boundary chars when adjustment != 0")
    }

    /// Verify that removeLastWrappedLines correctly accounts for continuation
    /// blocks when counting lines to remove.
    /// Bug: removeLastWrappedLines used naive getNumLinesWithWrapWidth: to
    /// count lines per block, causing it to over-subtract and remove fewer
    /// lines than requested.
    func testRemoveLastWrappedLinesWithContinuation() {
        let buffer = LineBuffer(blockSize: 1000)
        let width: Int32 = 80

        // Create aligned continuation blocks: 1 seed + 10 bulk = 880 chars.
        buffer.testOnlyAppendPartialItems(1, ofLength: 80, width: width)
        buffer.testOnlyAppendPartialItems(10, ofLength: 80, width: width)

        let totalWrapped = Int(buffer.numLines(withWidth: width))  // 880/80 = 11
        XCTAssertEqual(totalWrapped, 11)
        XCTAssertGreaterThan(buffer.testOnlyNumberOfBlocks, 1)

        // Remove 3 wrapped lines from the end.
        buffer.removeLastWrappedLines(3, width: width)

        let remaining = Int(buffer.numLines(withWidth: width))
        XCTAssertEqual(remaining, totalWrapped - 3,
                       "After removing 3 wrapped lines, should have exactly \(totalWrapped - 3) left")
    }

    /// Verify that removeLastWrappedLines can remove an entire continuation
    /// block and continue removing from the predecessor.
    func testRemoveLastWrappedLinesRemovesEntireContinuationBlock() {
        let buffer = LineBuffer(blockSize: 500)
        let width: Int32 = 80

        // Seed: 80 chars (1 wrapped line at width 80).
        buffer.testOnlyAppendPartialItems(1, ofLength: 80, width: width)

        // Bulk: creates a continuation block with 10 items × 80 chars = 800 chars.
        // The continuation block has 10 wrapped lines at width 80 (aligned, no adjustment).
        buffer.testOnlyAppendPartialItems(10, ofLength: 80, width: width)

        let totalBefore = Int(buffer.numLines(withWidth: width))  // 11
        XCTAssertEqual(totalBefore, 11)

        // Remove ALL lines — should empty the buffer without crashing.
        buffer.removeLastWrappedLines(Int32(totalBefore), width: width)
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), 0,
                       "Removing all wrapped lines should leave buffer empty")
    }

    /// Verify that removeLastWrappedLines works correctly at a non-creation
    /// width where continuation adjustment is non-zero.
    func testRemoveLastWrappedLinesAtNonCreationWidth() {
        let buffer = LineBuffer(blockSize: 1000)
        let creationWidth: Int32 = 80

        // Seed with 80 chars (aligned at 80 but not at 120).
        buffer.testOnlyAppendPartialItems(1, ofLength: 80, width: creationWidth)
        buffer.testOnlyAppendPartialItems(10, ofLength: 80, width: creationWidth)

        let totalChars = 11 * 80  // 880

        // Query at width 120: ceil(880/120) = 8.
        let queryWidth: Int32 = 120
        let totalWrapped = Int(buffer.numLines(withWidth: queryWidth))
        let expected = (totalChars + Int(queryWidth) - 1) / Int(queryWidth)
        XCTAssertEqual(totalWrapped, expected)

        // Remove 2 lines at the non-creation width.
        buffer.removeLastWrappedLines(2, width: queryWidth)

        let remaining = Int(buffer.numLines(withWidth: queryWidth))
        XCTAssertEqual(remaining, totalWrapped - 2,
                       "removeLastWrappedLines at non-creation width should use contributed counts")
    }

    /// Removing exactly a continuation block's contributed lines must NOT
    /// delete the block when it has hidden head chars. Those chars logically
    /// belong to the predecessor's stitched boundary line.
    func testRemoveExactContributedLinesPreservesPredecessorBoundary() {
        let width: Int32 = 80
        let buffer = LineBuffer(blockSize: 1000)

        // Seed: 20 chars (misaligned at width 80).
        let seedText = String(repeating: "S", count: 20)
        buffer.append(screenCharArrayWithDefaultStyle(seedText, eol: EOL_SOFT),
                      width: width)

        // Bulk: 3 items of 90 chars each. Alignment loop consumes 1 item
        // (charsAppended=90>=80). Block 0: 20+90=110 chars. Block 1:
        // continuation with prefix=110, pCol=30. 2*90=180 chars.
        // naive=3, adjustment=-1, hidden=1, contributed=2.
        buffer.testOnlyAppendPartialItems(3, ofLength: 90, width: width)

        XCTAssertGreaterThan(buffer.testOnlyNumberOfBlocks, 1,
                             "Should have at least 2 blocks")

        let lastIdx = buffer.testOnlyNumberOfBlocks - 1
        let lastBlock = buffer.testOnlyBlock(at: lastIdx)
        XCTAssertTrue(lastBlock.startsWithContinuation)

        let naive = Int(lastBlock.getNumLines(withWrapWidth: width))
        let adj = Int(lastBlock.continuationWrappedLineAdjustment(forWidth: width))
        let contributed = naive + adj
        let hidden = max(0, -adj)
        XCTAssertGreaterThan(hidden, 0,
                             "Continuation block should have hidden head lines")
        XCTAssertGreaterThan(contributed, 0,
                             "Continuation block should contribute visible lines")

        // Record predecessor state.
        let predBlock = buffer.testOnlyBlock(at: lastIdx - 1)
        let predLinesBefore = Int(predBlock.getNumLines(withWrapWidth: width))

        // Remove exactly the continuation block's contributed lines.
        buffer.removeLastWrappedLines(Int32(contributed), width: width)

        // Block must still exist (hidden head preserved) — this is the key
        // behavioral difference from the old code, which deleted the block.
        XCTAssertEqual(buffer.testOnlyNumberOfBlocks, lastIdx + 1,
                       "Block with hidden head must survive partial removal")

        // Predecessor's line count is unchanged (no chars removed from it).
        XCTAssertEqual(Int(predBlock.getNumLines(withWrapWidth: width)),
                       predLinesBefore,
                       "Predecessor block must be untouched")
    }

    /// removeLastWrappedLines correctly traverses past a continuation block
    /// with 0 contributed lines and removes lines from the predecessor.
    func testRemoveLastWrappedLinesTraversesZeroContributedBlock() {
        let width: Int32 = 80
        let buffer = LineBuffer(blockSize: 1000)

        // Seed: 30 chars (misaligned).
        let seedText = String(repeating: "Z", count: 30)
        buffer.append(screenCharArrayWithDefaultStyle(seedText, eol: EOL_SOFT),
                      width: width)

        // Bulk: 3 items of 40 chars. Alignment loop consumes 2 items
        // (charsAppended=80>=80). Block 0: 30+80=110 chars. Block 1:
        // continuation with prefix=110, pCol=30. 1*40=40 chars.
        // naive=1, pCol+40=70<80, so adjustment=-1, contributed=0.
        buffer.testOnlyAppendPartialItems(3, ofLength: 40, width: width)

        XCTAssertGreaterThan(buffer.testOnlyNumberOfBlocks, 1,
                             "Should have at least 2 blocks")
        let contBlock = buffer.testOnlyBlock(at: buffer.testOnlyNumberOfBlocks - 1)
        XCTAssertTrue(contBlock.startsWithContinuation)

        let naive = Int(contBlock.getNumLines(withWrapWidth: width))
        let adj = Int(contBlock.continuationWrappedLineAdjustment(forWidth: width))
        let contributed = naive + adj
        XCTAssertEqual(contributed, 0,
                       "Continuation block should contribute 0 visible lines")

        let totalLinesBefore = Int(buffer.numLines(withWidth: width))

        // Remove 1 line. The zero-contributed block is traversed (removed
        // since contributed=0 < 1), then 1 line is removed from block 0.
        buffer.removeLastWrappedLines(1, width: width)

        XCTAssertEqual(Int(buffer.numLines(withWidth: width)),
                       totalLinesBefore - 1,
                       "Should have one fewer line after removal")
    }

    /// Regression: continuation-path partial removal must use actual wrapped
    /// line lengths when hidden head lines exist. If kept lines include a short
    /// hard-EOL line, assuming keptLines * width can under-remove.
    func testRemoveLastWrappedLinesContinuationWithShortHardEOLKeepsCorrectCells() {
        let width: Int32 = 80

        let fragmented = LineBuffer(blockSize: 1000)
        fragmented.append(
            screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5), eol: EOL_SOFT),
            width: width)
        // Alignment loop consumes first 3 partial 30-char items into block A.
        // Continuation block then starts with:
        //  - 20 chars hard-EOL (hidden by adjustment=-1),
        //  - 8 chars hard-EOL (visible, short kept line),
        //  - 90 chars partial (80 + 10 visible wrapped cells).
        let lengths: [NSNumber] = [30, 30, 30, 20, 8, 90]
        let partials: [NSNumber] = [true, true, true, false, false, true]
        fragmented.testOnlyAppendItems(withLengths: lengths, partials: partials, width: width)

        XCTAssertGreaterThan(fragmented.testOnlyNumberOfBlocks, 1)
        let continuation = fragmented.testOnlyBlock(at: 1)
        XCTAssertTrue(continuation.startsWithContinuation)
        XCTAssertEqual(continuation.continuationWrappedLineAdjustment(forWidth: width), -1,
                       "Fixture requires hidden continuation head lines")

        let monolithic = LineBuffer(blockSize: 100_000)
        let raw0 = String(repeating: "X", count: 5) + Self.alphabetRun(length: 110)
        monolithic.append(screenCharArrayWithDefaultStyle(raw0, eol: EOL_HARD), width: width)
        let raw1 = Self.alphabetRun(length: 8, startingAt: 110)
        monolithic.append(screenCharArrayWithDefaultStyle(raw1, eol: EOL_HARD), width: width)
        let raw2 = Self.alphabetRun(length: 90, startingAt: 118)
        monolithic.append(screenCharArrayWithDefaultStyle(raw2, eol: EOL_SOFT), width: width)

        assertWrappedLineParity(fragmented, monolithic, width: width,
                                context: "before removal")

        // Remove one wrapped line from the tail. Old logic could no-op here.
        fragmented.removeLastWrappedLines(1, width: width)
        monolithic.removeLastWrappedLines(1, width: width)
        assertWrappedLineParity(fragmented, monolithic, width: width,
                                context: "after removeLastWrappedLines(1)")

        let fragPopped = fragmented.popLastLine(withWidth: width)
        let monoPopped = monolithic.popLastLine(withWidth: width)
        XCTAssertEqual(fragPopped?.stringValue, monoPopped?.stringValue,
                       "pop after continuation-tail removal should match monolithic")
        XCTAssertEqual(fragPopped?.eol, monoPopped?.eol)
        assertWrappedLineParity(fragmented, monolithic, width: width,
                                context: "after remove+pop")
    }

    /// Verify that DWC content does NOT create continuation blocks.
    /// When mayHaveDoubleWidthCharacter is true, the alignment loop must
    /// consume all partial items one-at-a-time (no bulk path) because
    /// column-based wrapping makes the continuation adjustment unreliable.
    func testDWCBulkPartialDoesNotCreateContinuation() {
        let buffer = LineBuffer(blockSize: 1000)
        let width: Int32 = 80

        // Enable the DWC flag (sticky, buffer-wide).
        buffer.mayHaveDoubleWidthCharacter = true

        // Seed with a partial.
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "A", count: 40),
                                                      eol: EOL_SOFT),
                      width: width)

        // Append many partial items through appendLines:.
        // Without the DWC deopt, these would go to the bulk initWithItems: path
        // and create a continuation block.
        buffer.testOnlyAppendPartialItems(20, ofLength: 40, width: width)

        // All partial → 1 raw line.
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)

        // Verify NO block has a continuation.
        // (testOnlyNumberOfBlocks tells us how many blocks exist;
        // if any had continuation, it would affect wrapped line counts.)
        let totalChars = 40 + 20 * 40  // 840
        let expectedWrapped = (totalChars + Int(width) - 1) / Int(width)  // ceil(840/80) = 11
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), expectedWrapped,
                       "DWC buffer should have correct wrapped line count without continuation adjustment")

        // Verify total character count by reading back all wrapped lines.
        let readBackChars = (0..<buffer.numLines(withWidth: width)).reduce(0) { sum, i in
            sum + Int(buffer.wrappedLine(at: i, width: width).length)
        }
        XCTAssertEqual(readBackChars, totalChars,
                       "DWC buffer should return all characters without continuation data loss")
    }

    /// After the buffer-wide DWC flag is set (e.g. by a prior emoji), the
    /// bulk initWithItems: path must still be used for pure-ASCII data.
    /// The flag is sticky/global, so checking _mayHaveDoubleWidthCharacter
    /// alone would permanently disable the fast path. The fix scans the
    /// actual data (items + prefix) for DWC_RIGHT instead.
    func testBulkPathWorksAfterDWCFlagSetWithASCIIData() {
        // Use a large block size so that one-at-a-time append will NOT
        // naturally create multiple blocks. If the bulk path fires,
        // it will create a new block (proving it was reached).
        let buffer = LineBuffer(blockSize: 100000)
        let width: Int32 = 80

        // Enable the DWC flag (simulating a prior DWC event).
        buffer.mayHaveDoubleWidthCharacter = true

        // Seed with a small partial line (ASCII, no actual DWC).
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "A", count: 40),
                                                      eol: EOL_SOFT),
                      width: width)

        // Append many partial items (all ASCII). With the bug, these would
        // all go one-at-a-time into one giant block. With the fix, the bulk
        // path creates a continuation block.
        buffer.testOnlyAppendPartialItems(100, ofLength: 80, width: width)

        // With blockSize=100000, one-at-a-time would fit everything in one block
        // (40 + 100*80 = 8040 chars << 100000). Multiple blocks proves bulk path.
        XCTAssertGreaterThan(buffer.testOnlyNumberOfBlocks, 1,
                             "Bulk path should create multiple blocks even with DWC flag set")

        // Verify the second block is a continuation (not a fresh block from
        // a hard EOL or block-size split).
        let block1 = buffer.testOnlyBlock(at: 1)
        XCTAssertTrue(block1.startsWithContinuation,
                      "Second block should be a continuation of the first")

        // All partial → 1 raw line.
        XCTAssertEqual(buffer.numberOfUnwrappedLines(), 1)

        // Correctness: wrapped line count.
        let totalChars = 40 + 100 * 80  // 8040
        let expectedWrapped = (totalChars + Int(width) - 1) / Int(width)  // ceil(8040/80) = 101
        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), expectedWrapped,
                       "Wrapped line count must be correct despite DWC flag being set")

        // Verify total character count by reading back all wrapped lines.
        let readBackChars = (0..<buffer.numLines(withWidth: width)).reduce(0) { sum, i in
            sum + Int(buffer.wrappedLine(at: i, width: width).length)
        }
        XCTAssertEqual(readBackChars, totalChars,
                       "All characters should be readable despite DWC flag + continuation")
    }

    /// Golden test for the true adjustment=-1 case.
    /// Seed=5 and itemLength=30 force cap break at 3 items (90 chars),
    /// giving continuationPrefix=95 (P=15). Remaining first raw line in
    /// continuation is only 60 chars, which is < (width-P)=65, so
    /// continuation adjustment must be -1 and readback must still be lossless.
    func testGoldenAdjustmentNegativeOneNoDroppedChars() {
        let width: Int32 = 80
        let buffer = LineBuffer(blockSize: 1000)

        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                      eol: EOL_SOFT),
                      width: width)
        buffer.testOnlyAppendPartialItems(5, ofLength: 30, width: width)

        XCTAssertGreaterThan(buffer.testOnlyNumberOfBlocks, 1)
        let continuation = buffer.testOnlyBlock(at: 1)
        XCTAssertTrue(continuation.startsWithContinuation)
        XCTAssertEqual(continuation.continuationPrefixCharacters, 95)
        XCTAssertEqual(continuation.length(ofRawLine: 0), 60)

        let expectedString = String(repeating: "X", count: 5) + Self.alphabetRun(length: 150)
        let expectedWrapped = Self.wrapASCII(expectedString, width: Int(width))

        XCTAssertEqual(Int(buffer.numLines(withWidth: width)), expectedWrapped.count)
        XCTAssertEqual(Self.readWrappedStrings(buffer: buffer, width: width), expectedWrapped)
        XCTAssertEqual(Self.readWrappedCellCount(buffer: buffer, width: width), expectedString.count)
    }

    /// Regression test: retroactive DWC flag on an existing continuation block.
    /// Build misaligned ASCII continuation (seed=5, itemLength=30, width=80),
    /// verify adjustment=-1 baseline, then set mayHaveDoubleWidthCharacter=true
    /// and assert the continuation block still reports -1 (not the DWC-guarded 0).
    /// Expected to fail until the DWC guard is fixed.
    func testDWCFlagWithNonZeroPColContinuationAdjustment() {
        let width: Int32 = 80
        let buffer = LineBuffer(blockSize: 1000)

        // Seed: 5-char partial line.
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                      eol: EOL_SOFT),
                      width: width)

        // Bulk: 5 items of length 30 → 150 alphabet chars.
        buffer.testOnlyAppendPartialItems(5, ofLength: 30, width: width)

        // --- Structural assertions ---
        XCTAssertGreaterThan(buffer.testOnlyNumberOfBlocks, 1)
        let continuation = buffer.testOnlyBlock(at: 1)
        XCTAssertTrue(continuation.startsWithContinuation,
                      "Second block must be a continuation")

        // --- Geometry assertions ---
        XCTAssertEqual(continuation.continuationPrefixCharacters, 95,
                       "continuationPrefix must be 95 (seed 5 + 3×30)")
        XCTAssertEqual(continuation.length(ofRawLine: 0), 60,
                       "First raw line in continuation must be 60 chars (2×30)")

        // --- Baseline: adjustment=-1 without DWC flag ---
        XCTAssertEqual(continuation.continuationWrappedLineAdjustment(forWidth: width), -1,
                       "Baseline adjustment must be -1 before DWC flag is set")

        // --- Retroactively set DWC flag (simulates a later DWC event) ---
        buffer.mayHaveDoubleWidthCharacter = true

        // --- Key assertion: adjustment must still be -1 after DWC flag ---
        XCTAssertEqual(continuation.continuationWrappedLineAdjustment(forWidth: width), -1,
                       "DWC guard should not clobber correct adjustment=-1 for pure-ASCII data")

        // --- Monolithic parity ---
        let expectedString = String(repeating: "X", count: 5) + Self.alphabetRun(length: 150)
        let reference = LineBuffer(blockSize: 1_000_000)
        reference.mayHaveDoubleWidthCharacter = true
        reference.append(screenCharArrayWithDefaultStyle(expectedString, eol: EOL_SOFT),
                         width: width)
        assertWrappedLineParity(buffer, reference, width: width,
                                context: "DWC flag + pCol!=0")

        // --- Readback completeness ---
        let totalChars = 5 + 150  // 155
        XCTAssertEqual(Self.readWrappedCellCount(buffer: buffer, width: width), totalChars,
                       "All 155 characters must be readable")
    }

    /// Boundary regression test with double-width glyphs crossing many block boundaries.
    /// Reconstruct wrapped output and compare with a monolithic reference buffer.
    /// Deterministic fuzzing for bulk partial append reconstruction. For each
    /// random scenario, compare wrapped output with a monolithic reference.
    func testFuzzWrappedReconstructionAgainstMonolithicReference() {
        var state = UInt64(0xC0FFEE1234ABCD)
        let widths: [Int32] = [8, 10, 16, 20, 40, 80]

        for _ in 0..<120 {
            state = state &* 6364136223846793005 &+ 1
            let width = widths[Int(state % UInt64(widths.count))]

            state = state &* 6364136223846793005 &+ 1
            let seedLength = Int(state % UInt64(max(1, Int(width))))

            state = state &* 6364136223846793005 &+ 1
            let itemLength = Int(state % 120) + 1

            state = state &* 6364136223846793005 &+ 1
            let itemCount = Int(state % 18) + 2

            state = state &* 6364136223846793005 &+ 1
            let blockSize = Int32((Int(state % 8) + 1) * 128)

            let fragmented = LineBuffer(blockSize: blockSize)
            let reference = LineBuffer(blockSize: 1_000_000)

            if seedLength > 0 {
                fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "S", count: seedLength),
                                                                  eol: EOL_SOFT),
                                  width: width)
            }
            fragmented.testOnlyAppendPartialItems(Int32(itemCount), ofLength: Int32(itemLength), width: width)

            let expected = String(repeating: "S", count: seedLength) +
                Self.alphabetRun(length: itemCount * itemLength)
            reference.append(screenCharArrayWithDefaultStyle(expected, eol: EOL_SOFT),
                             width: width)

            XCTAssertEqual(Int(fragmented.numLines(withWidth: width)),
                           Int(reference.numLines(withWidth: width)),
                           "Wrapped line count mismatch (w=\(width), seed=\(seedLength), itemLength=\(itemLength), itemCount=\(itemCount), blockSize=\(blockSize))")

            let wrappedLineCount = Int(reference.numLines(withWidth: width))
            let ctx = "(w=\(width), seed=\(seedLength), itemLength=\(itemLength), itemCount=\(itemCount), blockSize=\(blockSize))"
            for line in 0..<wrappedLineCount {
                let actual = fragmented.wrappedLine(at: Int32(line), width: width)
                let expected = reference.wrappedLine(at: Int32(line), width: width)
                XCTAssertEqual(actual.stringValue, expected.stringValue,
                               "Wrapped content mismatch at line \(line) \(ctx)")
                XCTAssertEqual(actual.eol, expected.eol,
                               "EOL mismatch at line \(line) \(ctx)")
                XCTAssertEqual(actual.continuation.code, expected.continuation.code,
                               "continuation.code mismatch at line \(line) \(ctx)")
            }
        }
    }

    /// Deterministic repro for the first fuzz failure in
    /// testFuzzWrappedReconstructionAgainstMonolithicReference:
    /// w=8, seed=3, itemLength=33, itemCount=7, blockSize=896.
    func testFuzzReproBoundaryContentMismatch() {
        let width: Int32 = 8
        let seedLength = 3
        let itemLength = 33
        let itemCount = 7
        let blockSize: Int32 = 896

        let fragmented = LineBuffer(blockSize: blockSize)
        let reference = LineBuffer(blockSize: 1_000_000)

        fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "S", count: seedLength),
                                                          eol: EOL_SOFT),
                          width: width)
        fragmented.testOnlyAppendPartialItems(Int32(itemCount), ofLength: Int32(itemLength), width: width)

        let expected = String(repeating: "S", count: seedLength) +
            Self.alphabetRun(length: itemCount * itemLength)
        reference.append(screenCharArrayWithDefaultStyle(expected, eol: EOL_SOFT),
                         width: width)

        let wrappedLineCount = Int(reference.numLines(withWidth: width))
        XCTAssertEqual(Int(fragmented.numLines(withWidth: width)), wrappedLineCount,
                       "Wrapped line count mismatch")

        for line in 0..<wrappedLineCount {
            let actual = fragmented.wrappedLine(at: Int32(line), width: width)
            let exp = reference.wrappedLine(at: Int32(line), width: width)
            XCTAssertEqual(actual.stringValue, exp.stringValue,
                           "Wrapped content mismatch at line \(line)")
            XCTAssertEqual(actual.eol, exp.eol,
                           "EOL mismatch at line \(line)")
            XCTAssertEqual(actual.continuation.code, exp.continuation.code,
                           "continuation.code mismatch at line \(line)")
        }
    }

    /// Precedence contract: at continuation boundaries, wrapped line content and
    /// EOL must match a monolithic (single-block) reference.
    func testBoundaryPrecedenceMatchesMonolithicReference() {
        let width: Int32 = 80
        let fragmented = LineBuffer(blockSize: 1000)
        let reference = LineBuffer(blockSize: 1_000_000)

        // Seed: 5 chars (misaligned, forces pCol=15 after alignment loop).
        let seedText = String(repeating: "S", count: 5)
        fragmented.append(screenCharArrayWithDefaultStyle(seedText, eol: EOL_SOFT),
                          width: width)
        // Bulk: 10 items of 30 chars via bulk path → creates continuation block.
        fragmented.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        // Monolithic reference with the same content.
        let fullText = seedText + Self.alphabetRun(length: 300)
        reference.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT),
                         width: width)

        XCTAssertGreaterThan(fragmented.testOnlyNumberOfBlocks, 1)
        XCTAssertTrue(fragmented.testOnlyBlock(at: 1).startsWithContinuation)

        let wrappedCount = Int(reference.numLines(withWidth: width))
        XCTAssertEqual(Int(fragmented.numLines(withWidth: width)), wrappedCount)

        for i in 0..<wrappedCount {
            let actual = fragmented.wrappedLine(at: Int32(i), width: width)
            let expected = reference.wrappedLine(at: Int32(i), width: width)

            XCTAssertEqual(actual.stringValue, expected.stringValue,
                           "content mismatch at wrapped line \(i)")
            XCTAssertEqual(actual.continuation.code, expected.continuation.code,
                           "continuation/eol mismatch at wrapped line \(i)")
            XCTAssertEqual(actual.metadata.timestamp, expected.metadata.timestamp,
                           "metadata timestamp mismatch at wrapped line \(i)")
            XCTAssertEqual(actual.metadata.rtlFound.boolValue, expected.metadata.rtlFound.boolValue,
                           "metadata rtlFound mismatch at wrapped line \(i)")
        }
    }

    /// Golden case: verify that stitched boundary content and EOL match a
    /// monolithic reference at the creation width.
    func testAdjustmentNegativeOneBoundaryPrecedence() {
        let width: Int32 = 80
        let fragmented = LineBuffer(blockSize: 1000)
        let reference = LineBuffer(blockSize: 1_000_000)

        // Seed: 5 chars (misaligned). Alignment loop consumes 3 items (90 chars),
        // block 0 = 95 chars. Block 1: 7 items, prefix=95, pCol=15, adjustment=-1.
        let seedText = String(repeating: "X", count: 5)
        fragmented.append(screenCharArrayWithDefaultStyle(seedText, eol: EOL_SOFT),
                          width: width)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        let fullText = seedText + Self.alphabetRun(length: 300)
        reference.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT),
                         width: width)

        XCTAssertGreaterThan(fragmented.testOnlyNumberOfBlocks, 1)
        let continuation = fragmented.testOnlyBlock(at: 1)
        XCTAssertTrue(continuation.startsWithContinuation)
        XCTAssertEqual(continuation.continuationWrappedLineAdjustment(forWidth: width), -1)

        // The hidden first wrapped line in block 1 must be represented in
        // line 0 via the stitched result from block 0 + block 1.
        let actual0 = fragmented.wrappedLine(at: 0, width: width)
        let expected0 = reference.wrappedLine(at: 0, width: width)
        XCTAssertEqual(actual0.stringValue, expected0.stringValue)
        XCTAssertEqual(actual0.continuation.code, expected0.continuation.code)

        // Lock down all wrapped lines.
        let wrappedCount = Int(reference.numLines(withWidth: width))
        XCTAssertEqual(Int(fragmented.numLines(withWidth: width)), wrappedCount)
        for i in 0..<wrappedCount {
            let actual = fragmented.wrappedLine(at: Int32(i), width: width)
            let expected = reference.wrappedLine(at: Int32(i), width: width)
            XCTAssertEqual(actual.stringValue, expected.stringValue,
                           "content mismatch at wrapped line \(i)")
            XCTAssertEqual(actual.continuation.code, expected.continuation.code,
                           "continuation/eol mismatch at wrapped line \(i)")
            XCTAssertEqual(actual.metadata.timestamp, expected.metadata.timestamp,
                           "metadata timestamp mismatch at wrapped line \(i)")
            XCTAssertEqual(actual.metadata.rtlFound.boolValue, expected.metadata.rtlFound.boolValue,
                           "metadata rtlFound mismatch at wrapped line \(i)")
        }
    }

    private static func alphabetRun(length: Int, startingAt offset: Int = 0) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var out = String()
        out.reserveCapacity(length)
        for i in 0..<length {
            out.append(letters[(i + offset) % letters.count])
        }
        return out
    }

    private static func wrapASCII(_ s: String, width: Int) -> [String] {
        precondition(width > 0)
        if s.isEmpty {
            return []
        }
        var result = [String]()
        var idx = s.startIndex
        while idx < s.endIndex {
            let end = s.index(idx, offsetBy: min(width, s.distance(from: idx, to: s.endIndex)))
            result.append(String(s[idx..<end]))
            idx = end
        }
        return result
    }

    private static func readWrappedStrings(buffer: LineBuffer, width: Int32) -> [String] {
        return (0..<buffer.numLines(withWidth: width)).map {
            buffer.wrappedLine(at: $0, width: width).stringValue
        }
    }

    private static func readWrappedCellCount(buffer: LineBuffer, width: Int32) -> Int {
        return (0..<buffer.numLines(withWidth: width)).reduce(0) { sum, line in
            sum + Int(buffer.wrappedLine(at: line, width: width).length)
        }
    }

    // MARK: - Boundary stitch tests

    /// Verify that the stitched boundary line has exactly tail(A) + head(B) content.
    func testBoundaryStitchContentIsCorrect() {
        let width: Int32 = 80
        let buffer = LineBuffer(blockSize: 1000)

        // Seed: 5 chars (misaligned).
        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                      eol: EOL_SOFT),
                      width: width)
        // 10 items of 30 chars. Cap breaks after 3 items (90 chars).
        // Block 0: 5 + 90 = 95 chars. Block 1 continuation with prefix=95.
        // P%80 = 15. Block 0 last wrapped line has 15 chars (tail).
        // Block 1 head should contribute 65 chars to fill width.
        buffer.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        let totalChars = 5 + 10 * 30  // 305
        let expectedString = String(repeating: "X", count: 5) + Self.alphabetRun(length: 300)
        let expectedWrapped = Self.wrapASCII(expectedString, width: Int(width))

        // Verify each wrapped line matches the expected content exactly.
        let actualWrapped = Self.readWrappedStrings(buffer: buffer, width: width)
        XCTAssertEqual(actualWrapped.count, expectedWrapped.count)
        for i in 0..<expectedWrapped.count {
            XCTAssertEqual(actualWrapped[i], expectedWrapped[i],
                           "Content mismatch at wrapped line \(i): expected \(expectedWrapped[i].count) chars, got \(actualWrapped[i].count)")
        }

        // Verify total character count.
        XCTAssertEqual(Self.readWrappedCellCount(buffer: buffer, width: width), totalChars)
    }

    /// Verify that the stitched boundary line has EOL_SOFT.
    func testBoundaryStitchEOLIsSoft() {
        let width: Int32 = 80
        let buffer = LineBuffer(blockSize: 1000)

        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                      eol: EOL_SOFT),
                      width: width)
        buffer.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        // Line 0 is the boundary-spanning wrapped line (15 from A + 65 from B = 80 chars).
        // It should have EOL_SOFT since it reaches width.
        let line0 = buffer.wrappedLine(at: 0, width: width)
        XCTAssertEqual(line0.eol, EOL_SOFT,
                       "Stitched boundary line should have EOL_SOFT")
        XCTAssertEqual(Int(line0.length), Int(width),
                       "Stitched boundary line should be full width")
    }

    /// Verify that stitched boundary line metadata matches a monolithic
    /// single-block reference for every wrapped line.
    func testBoundaryStitchMetadataMatchesMonolithic() {
        let width: Int32 = 80

        // Fragmented buffer: creates continuation block with adjustment=-1.
        let fragmented = LineBuffer(blockSize: 1000)
        fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                          eol: EOL_SOFT),
                          width: width)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        XCTAssertGreaterThan(fragmented.testOnlyNumberOfBlocks, 1)

        // Monolithic reference: same content in one block via single append.
        // (testOnlyAppendPartialItems uses appendLines:width: which creates
        // continuation blocks even with large block sizes.)
        let monolithic = LineBuffer(blockSize: 1_000_000)
        let fullText = String(repeating: "X", count: 5) + Self.alphabetRun(length: 300)
        monolithic.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT),
                          width: width)
        XCTAssertEqual(monolithic.testOnlyNumberOfBlocks, 1)

        let wrappedCount = Int(monolithic.numLines(withWidth: width))
        XCTAssertEqual(Int(fragmented.numLines(withWidth: width)), wrappedCount)

        for i in 0..<wrappedCount {
            let actual = fragmented.wrappedLine(at: Int32(i), width: width)
            let expected = monolithic.wrappedLine(at: Int32(i), width: width)

            XCTAssertEqual(actual.stringValue, expected.stringValue,
                           "content mismatch at line \(i)")
            XCTAssertEqual(actual.eol, expected.eol,
                           "eol mismatch at line \(i)")
            XCTAssertEqual(actual.metadata.timestamp, expected.metadata.timestamp,
                           "metadata timestamp mismatch at line \(i)")
            XCTAssertEqual(actual.metadata.rtlFound.boolValue, expected.metadata.rtlFound.boolValue,
                           "metadata rtlFound mismatch at line \(i)")
            XCTAssertEqual(actual.eaIndex == nil, expected.eaIndex == nil,
                           "metadata eaIndex presence mismatch at line \(i)")
        }
    }

    /// Verify stitch produces monolithic-equivalent output at multiple query widths.
    func testBoundaryStitchAtMultipleWidths() {
        let creationWidth: Int32 = 80
        let buffer = LineBuffer(blockSize: 1000)

        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                      eol: EOL_SOFT),
                      width: creationWidth)
        buffer.testOnlyAppendPartialItems(10, ofLength: 30, width: creationWidth)

        let totalChars = 5 + 10 * 30  // 305
        let expectedString = String(repeating: "X", count: 5) + Self.alphabetRun(length: 300)

        // Monolithic reference for EOL/continuation comparison.
        let monolithic = LineBuffer(blockSize: 1_000_000)
        monolithic.append(screenCharArrayWithDefaultStyle(expectedString, eol: EOL_SOFT),
                          width: creationWidth)

        for queryWidth: Int32 in [40, 60, 80, 100, 120] {
            let expectedWrapped = Self.wrapASCII(expectedString, width: Int(queryWidth))
            let actualWrapped = Self.readWrappedStrings(buffer: buffer, width: queryWidth)

            XCTAssertEqual(actualWrapped.count, expectedWrapped.count,
                           "Line count mismatch at width \(queryWidth)")
            for i in 0..<min(actualWrapped.count, expectedWrapped.count) {
                XCTAssertEqual(actualWrapped[i], expectedWrapped[i],
                               "Content mismatch at width \(queryWidth), line \(i)")
            }
            XCTAssertEqual(Self.readWrappedCellCount(buffer: buffer, width: queryWidth), totalChars,
                           "Total char count mismatch at width \(queryWidth)")

            // EOL and continuation parity vs monolithic reference.
            let monoCount = Int(monolithic.numLines(withWidth: queryWidth))
            let fragCount = Int(buffer.numLines(withWidth: queryWidth))
            XCTAssertEqual(fragCount, monoCount,
                           "Wrapped line count mismatch at width \(queryWidth)")
            for i in 0..<min(fragCount, monoCount) {
                let actual = buffer.wrappedLine(at: Int32(i), width: queryWidth)
                let expected = monolithic.wrappedLine(at: Int32(i), width: queryWidth)
                XCTAssertEqual(actual.eol, expected.eol,
                               "EOL mismatch at width \(queryWidth), line \(i)")
                XCTAssertEqual(actual.continuation.code, expected.continuation.code,
                               "continuation.code mismatch at width \(queryWidth), line \(i)")
            }
        }
    }

    /// Verify copyLineToBuffer also stitches the boundary correctly.
    func testCopyLineToBufferStitchesBoundary() {
        let width: Int32 = 80
        let buffer = LineBuffer(blockSize: 1000)

        buffer.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                      eol: EOL_SOFT),
                      width: width)
        buffer.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        let totalChars = 5 + 10 * 30  // 305
        let expectedString = String(repeating: "X", count: 5) + Self.alphabetRun(length: 300)
        let expectedWrapped = Self.wrapASCII(expectedString, width: Int(width))

        // Use copyLineToBuffer for each wrapped line and compare.
        let bufSize = Int(width + 1)
        let rawBuf = UnsafeMutablePointer<screen_char_t>.allocate(capacity: bufSize)
        defer { rawBuf.deallocate() }

        var totalCopied = 0
        for i in 0..<Int(buffer.numLines(withWidth: width)) {
            var continuation = screen_char_t()
            let eol = buffer.copyLine(toBuffer: rawBuf,
                                       width: width,
                                       lineNum: Int32(i),
                                       continuation: &continuation)

            // Count non-null characters.
            var lineLen = 0
            for j in 0..<Int(width) {
                if rawBuf[j].code != 0 || rawBuf[j].complexChar != 0 {
                    lineLen = j + 1
                }
            }

            // For the last line, it may be shorter.
            let expectedLine = expectedWrapped[i]
            XCTAssertEqual(lineLen, expectedLine.count,
                           "copyLineToBuffer length mismatch at line \(i)")
            totalCopied += lineLen

            // Verify content matches.
            for j in 0..<min(lineLen, expectedLine.count) {
                let idx = expectedLine.index(expectedLine.startIndex, offsetBy: j)
                XCTAssertEqual(UnicodeScalar(rawBuf[j].code),
                               UnicodeScalar(String(expectedLine[idx])),
                               "copyLineToBuffer char mismatch at line \(i), col \(j)")
            }

            // Middle lines should be EOL_SOFT, last line EOL_SOFT (partial).
            if i < expectedWrapped.count - 1 {
                XCTAssertEqual(eol, EOL_SOFT,
                               "copyLineToBuffer EOL mismatch at line \(i)")
            }
        }
        XCTAssertEqual(totalCopied, totalChars,
                       "copyLineToBuffer total char count mismatch")
    }

    // MARK: - Search-vs-render parity

    /// Verify that search results and convertPositions output are identical
    /// between a fragmented buffer (with continuation blocks) and a monolithic
    /// single-block reference. Expected to FAIL: convertPositions y+1 bug for
    /// adjustment=-1 continuation blocks causes yStart/yEnd divergence.
    func testSearchAndConvertPositionsParityFragmentedVsMonolithic() {
        let width: Int32 = 80

        // Fragmented buffer: continuation block with adjustment=-1.
        let fragmented = LineBuffer(blockSize: 1000)
        fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                          eol: EOL_SOFT),
                          width: width)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        XCTAssertGreaterThan(fragmented.testOnlyNumberOfBlocks, 1)
        XCTAssertTrue(fragmented.testOnlyBlock(at: 1).startsWithContinuation)

        // Monolithic reference: same content in one block via single append.
        let monolithic = LineBuffer(blockSize: 1_000_000)
        let fullText = String(repeating: "X", count: 5) + Self.alphabetRun(length: 300)
        monolithic.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT),
                          width: width)
        XCTAssertEqual(monolithic.testOnlyNumberOfBlocks, 1)

        // Search for "ABCDEFGHIJ" — appears in the bulk portion at offsets
        // 5, 31, 57, ... (every 26 chars, since bulk content is A-Z repeating).
        let searchTerm = "ABCDEFGHIJ"

        func collectResults(_ buffer: LineBuffer) -> [ResultRange] {
            let context = FindContext()
            buffer.prepareToSearch(for: searchTerm,
                                   startingAt: buffer.firstPosition(),
                                   options: FindOptions(rawValue: FindOptions.multipleResults.rawValue),
                                   mode: .caseSensitiveSubstring,
                                   with: context)
            var allResults = [ResultRange]()
            while context.status != .NotFound {
                buffer.findSubstring(context, stopAt: buffer.lastPosition())
                if let results = context.results as? [ResultRange] {
                    allResults.append(contentsOf: results)
                    context.results?.removeAllObjects()
                }
            }
            return allResults
        }

        let fragResults = collectResults(fragmented)
        let monoResults = collectResults(monolithic)

        // 1. ResultRange parity: same positions and lengths.
        XCTAssertGreaterThan(monoResults.count, 0, "Should find at least one match")
        XCTAssertEqual(fragResults.count, monoResults.count,
                       "Search result count mismatch")
        for i in 0..<min(fragResults.count, monoResults.count) {
            XCTAssertEqual(fragResults[i].position, monoResults[i].position,
                           "Search result position mismatch at index \(i)")
            XCTAssertEqual(fragResults[i].length, monoResults[i].length,
                           "Search result length mismatch at index \(i)")
        }

        // 2. convertPositions parity: full XYRange geometry.
        guard !monoResults.isEmpty else { return }
        let fragXY = fragmented.convertPositions(fragResults, withWidth: width) ?? []
        let monoXY = monolithic.convertPositions(monoResults, withWidth: width) ?? []

        XCTAssertEqual(fragXY.count, monoXY.count,
                       "convertPositions result count mismatch")
        for i in 0..<min(fragXY.count, monoXY.count) {
            XCTAssertEqual(fragXY[i].xStart, monoXY[i].xStart,
                           "xStart mismatch for result \(i) (pos=\(monoResults[i].position))")
            XCTAssertEqual(fragXY[i].yStart, monoXY[i].yStart,
                           "yStart mismatch for result \(i) (pos=\(monoResults[i].position))")
            XCTAssertEqual(fragXY[i].xEnd, monoXY[i].xEnd,
                           "xEnd mismatch for result \(i) (pos=\(monoResults[i].position))")
            XCTAssertEqual(fragXY[i].yEnd, monoXY[i].yEnd,
                           "yEnd mismatch for result \(i) (pos=\(monoResults[i].position))")
        }
    }

    // MARK: - Hard-EOL stitch tests

    /// Verify that stitched boundary lines respect EOL_HARD when the
    /// continuation block's first raw line ends hard before filling width.
    /// Expected to FAIL: stitch forces EOL_SOFT, but monolithic has EOL_HARD.
    func testBoundaryStitchRespectsHardEOLInContinuationHead() {
        let width: Int32 = 80

        // --- Fragmented buffer ---
        let fragmented = LineBuffer(blockSize: 1000)
        // Seed: 5 chars partial (misaligned).
        fragmented.append(
            screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5), eol: EOL_SOFT),
            width: width)
        // Mixed items: alignment loop consumes items 0–2 (3×30=90 chars,
        // charsAppendedInLoop=90 >= 80 → break). Block A = 5+90 = 95 chars.
        // Remaining items go to bulk path → block B continuation, prefix=95.
        // Item 3 (20 chars, non-partial) terminates the first raw line in
        // block B with EOL_HARD. Items 4–9 start a new partial raw line.
        let lengths: [NSNumber] = [30, 30, 30, 20, 30, 30, 30, 30, 30, 30]
        let partials: [NSNumber] = [true, true, true, false, true, true, true, true, true, true]
        fragmented.testOnlyAppendItems(withLengths: lengths, partials: partials, width: width)

        // Verify preconditions.
        XCTAssertGreaterThan(fragmented.testOnlyNumberOfBlocks, 1)
        let contBlock = fragmented.testOnlyBlock(at: 1)
        XCTAssertTrue(contBlock.startsWithContinuation)
        XCTAssertEqual(contBlock.continuationWrappedLineAdjustment(forWidth: width), -1)

        // --- Monolithic reference: same raw line structure, single block ---
        // Raw line 0: seed (5 X's) + items 0–3 (90+20=110 alphabet chars) = 115 chars, EOL_HARD.
        // Raw line 1: items 4–9 (180 alphabet chars), partial.
        let monolithic = LineBuffer(blockSize: 100_000)
        let monoRawLine0 = String(repeating: "X", count: 5) + Self.alphabetRun(length: 110)
        monolithic.append(screenCharArrayWithDefaultStyle(monoRawLine0, eol: EOL_HARD),
                          width: width)
        let monoRawLine1 = Self.alphabetRun(length: 180, startingAt: 110)
        monolithic.append(screenCharArrayWithDefaultStyle(monoRawLine1, eol: EOL_SOFT),
                          width: width)
        XCTAssertEqual(monolithic.testOnlyNumberOfBlocks, 1)

        // --- Assert parity ---
        let wrappedCount = Int(monolithic.numLines(withWidth: width))
        XCTAssertEqual(Int(fragmented.numLines(withWidth: width)), wrappedCount,
                       "Wrapped line count mismatch")

        for i in 0..<wrappedCount {
            let actual = fragmented.wrappedLine(at: Int32(i), width: width)
            let expected = monolithic.wrappedLine(at: Int32(i), width: width)

            XCTAssertEqual(actual.stringValue, expected.stringValue,
                           "content mismatch at line \(i)")
            XCTAssertEqual(actual.eol, expected.eol,
                           "EOL mismatch at line \(i): " +
                           "fragmented=\(actual.eol) monolithic=\(expected.eol)")
            XCTAssertEqual(actual.continuation.code, expected.continuation.code,
                           "continuation.code mismatch at line \(i)")
        }
    }

    /// Validate that all three stitch call paths exhibit the hard-EOL bug:
    /// wrappedLine(at:), copyLineToBuffer, and enumerateLinesInRange.
    /// Expected to FAIL on each path at the boundary line.
    func testBoundaryStitchHardEOLAllCallPaths() {
        let width: Int32 = 80

        // Same fixture as testBoundaryStitchRespectsHardEOLInContinuationHead.
        let fragmented = LineBuffer(blockSize: 1000)
        fragmented.append(
            screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5), eol: EOL_SOFT),
            width: width)
        let lengths: [NSNumber] = [30, 30, 30, 20, 30, 30, 30, 30, 30, 30]
        let partials: [NSNumber] = [true, true, true, false, true, true, true, true, true, true]
        fragmented.testOnlyAppendItems(withLengths: lengths, partials: partials, width: width)

        // Monolithic reference: same raw line structure, single block.
        let monolithic = LineBuffer(blockSize: 100_000)
        let monoRawLine0 = String(repeating: "X", count: 5) + Self.alphabetRun(length: 110)
        monolithic.append(screenCharArrayWithDefaultStyle(monoRawLine0, eol: EOL_HARD),
                          width: width)
        let monoRawLine1 = Self.alphabetRun(length: 180, startingAt: 110)
        monolithic.append(screenCharArrayWithDefaultStyle(monoRawLine1, eol: EOL_SOFT),
                          width: width)
        XCTAssertEqual(monolithic.testOnlyNumberOfBlocks, 1)

        let wrappedCount = Int(monolithic.numLines(withWidth: width))

        // --- copyLineToBuffer path ---
        let rawBuf = UnsafeMutablePointer<screen_char_t>.allocate(capacity: Int(width) + 1)
        defer { rawBuf.deallocate() }

        for i in 0..<wrappedCount {
            var continuation = screen_char_t()
            let eol = fragmented.copyLine(toBuffer: rawBuf, width: width,
                                           lineNum: Int32(i), continuation: &continuation)
            let monoLine = monolithic.wrappedLine(at: Int32(i), width: width)
            XCTAssertEqual(eol, monoLine.eol,
                           "copyLineToBuffer EOL mismatch at line \(i)")
            XCTAssertEqual(continuation.code, monoLine.continuation.code,
                           "copyLineToBuffer continuation.code mismatch at line \(i)")
        }

        // --- enumerateLinesInRange path ---
        var enumLines = [(string: String, eol: Int32, contCode: UInt16)]()
        fragmented.enumerateLines(
            in: NSRange(location: 0, length: wrappedCount),
            width: width) { _, sca, _, _ in
            enumLines.append((sca.stringValue, sca.eol, sca.continuation.code))
        }

        XCTAssertEqual(enumLines.count, wrappedCount)
        for i in 0..<wrappedCount {
            let expected = monolithic.wrappedLine(at: Int32(i), width: width)
            XCTAssertEqual(enumLines[i].string, expected.stringValue,
                           "enumerate content mismatch at line \(i)")
            XCTAssertEqual(enumLines[i].eol, expected.eol,
                           "enumerate EOL mismatch at line \(i)")
            XCTAssertEqual(enumLines[i].contCode, expected.continuation.code,
                           "enumerate continuation.code mismatch at line \(i)")
        }
    }

    /// Regression: continuation stitching must still run when block B's first
    /// raw line is empty but hard-terminated.
    /// Expected to FAIL before fixing stitchedLineFromBlockAtIndex's
    /// rawHeadLength<=0 early-return.
    func testBoundaryStitchEmptyContinuationHeadHardEOLParity() {
        let width: Int32 = 80

        let fragmented = LineBuffer(blockSize: 1000)
        fragmented.append(
            screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5), eol: EOL_SOFT),
            width: width)

        // The alignment loop consumes three 30-char partial items into block A
        // (95 chars total, misaligned). The remaining first item is an empty
        // hard-EOL append, which becomes block B's first raw line.
        let lengths: [NSNumber] = [30, 30, 30, 0]
        let partials: [NSNumber] = [true, true, true, false]
        fragmented.testOnlyAppendItems(withLengths: lengths, partials: partials, width: width)

        XCTAssertGreaterThan(fragmented.testOnlyNumberOfBlocks, 1)
        let contBlock = fragmented.testOnlyBlock(at: 1)
        XCTAssertTrue(contBlock.startsWithContinuation)
        XCTAssertEqual(contBlock.continuationPrefixCharacters, 95)
        XCTAssertEqual(contBlock.length(ofRawLine: 0), 0,
                       "Fixture must create an empty continuation head raw line")
        XCTAssertEqual(contBlock.continuationWrappedLineAdjustment(forWidth: width), -1)

        // Monolithic equivalent: one 95-char raw line hard-terminated.
        let monolithic = LineBuffer(blockSize: 100_000)
        let monoRaw0 = String(repeating: "X", count: 5) + Self.alphabetRun(length: 90)
        monolithic.append(screenCharArrayWithDefaultStyle(monoRaw0, eol: EOL_HARD),
                          width: width)

        assertWrappedLineParity(fragmented, monolithic, width: width,
                                context: "empty continuation head hard-EOL parity")
    }

    // MARK: - Shared parity assertion helper

    /// Compare all wrapped lines between two buffers. Always checks stringValue,
    /// length, eol. Optionally checks full continuation style fields and metadata.
    private func assertWrappedLineParity(
        _ fragmented: LineBuffer,
        _ monolithic: LineBuffer,
        width: Int32,
        checkContinuationStyle: Bool = false,
        checkMetadata: Bool = false,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let fragCount = Int(fragmented.numLines(withWidth: width))
        let monoCount = Int(monolithic.numLines(withWidth: width))
        XCTAssertEqual(fragCount, monoCount,
                       "Line count mismatch \(context)", file: file, line: line)
        for i in 0..<min(fragCount, monoCount) {
            let actual = fragmented.wrappedLine(at: Int32(i), width: width)
            let expected = monolithic.wrappedLine(at: Int32(i), width: width)
            XCTAssertEqual(actual.stringValue, expected.stringValue,
                           "content mismatch at line \(i) \(context)", file: file, line: line)
            XCTAssertEqual(actual.length, expected.length,
                           "length mismatch at line \(i) \(context)", file: file, line: line)
            XCTAssertEqual(actual.eol, expected.eol,
                           "eol mismatch at line \(i) \(context)", file: file, line: line)
            XCTAssertEqual(actual.continuation.code, expected.continuation.code,
                           "continuation.code mismatch at line \(i) \(context)",
                           file: file, line: line)
            if checkContinuationStyle {
                XCTAssertEqual(actual.continuation.foregroundColor,
                               expected.continuation.foregroundColor,
                               "continuation.foregroundColor mismatch at line \(i) \(context)",
                               file: file, line: line)
                XCTAssertEqual(actual.continuation.backgroundColor,
                               expected.continuation.backgroundColor,
                               "continuation.backgroundColor mismatch at line \(i) \(context)",
                               file: file, line: line)
                XCTAssertEqual(actual.continuation.bold,
                               expected.continuation.bold,
                               "continuation.bold mismatch at line \(i) \(context)",
                               file: file, line: line)
                XCTAssertEqual(actual.continuation.italic,
                               expected.continuation.italic,
                               "continuation.italic mismatch at line \(i) \(context)",
                               file: file, line: line)
                XCTAssertEqual(actual.continuation.foregroundColorMode,
                               expected.continuation.foregroundColorMode,
                               "continuation.foregroundColorMode mismatch at line \(i) \(context)",
                               file: file, line: line)
                XCTAssertEqual(actual.continuation.backgroundColorMode,
                               expected.continuation.backgroundColorMode,
                               "continuation.backgroundColorMode mismatch at line \(i) \(context)",
                               file: file, line: line)
            }
            if checkMetadata {
                XCTAssertEqual(actual.metadata.timestamp, expected.metadata.timestamp,
                               "metadata.timestamp mismatch at line \(i) \(context)",
                               file: file, line: line)
                XCTAssertEqual(actual.metadata.rtlFound.boolValue,
                               expected.metadata.rtlFound.boolValue,
                               "metadata.rtlFound mismatch at line \(i) \(context)",
                               file: file, line: line)
            }
        }
    }

    // MARK: - 1. Unicode width fuzz

    func testUnicodeFuzzWrappedReconstructionAgainstMonolithicReference() {
        // Unicode character palette for fuzz generation.
        let unicodeChars: [String] = [
            "\u{4E00}",      // CJK ideograph (DWC, 2 columns)
            "\u{4E8C}",      // CJK ideograph (DWC)
            "\u{4E09}",      // CJK ideograph (DWC)
            "A",             // ASCII
            "B",
            "e\u{0301}",    // e + combining acute (1 column, 2 code points)
            "n\u{0303}",    // n + combining tilde
            "\u{03B1}",     // Greek alpha (ambiguous width)
            "\u{03B2}",     // Greek beta (ambiguous width)
            "Z",
        ]
        var state = UInt64(0xDEADBEEF42)
        let widths: [Int32] = [8, 10, 16, 20, 40, 80]

        for iter in 0..<30 {
            state = state &* 6364136223846793005 &+ 1
            let width = widths[Int(state % UInt64(widths.count))]

            state = state &* 6364136223846793005 &+ 1
            let itemCount = Int(state % 8) + 2

            // Build items as strings of random Unicode chars.
            var items = [String]()
            for _ in 0..<itemCount {
                state = state &* 6364136223846793005 &+ 1
                let itemLen = Int(state % 15) + 3
                var s = ""
                for _ in 0..<itemLen {
                    state = state &* 6364136223846793005 &+ 1
                    s += unicodeChars[Int(state % UInt64(unicodeChars.count))]
                }
                items.append(s)
            }

            let fullText = items.joined()

            // Fragmented: per-line append with small blockSize to force continuation.
            let fragmented = LineBuffer(blockSize: 128)
            fragmented.mayHaveDoubleWidthCharacter = true
            for (idx, item) in items.enumerated() {
                let isLast = (idx == items.count - 1)
                let sca = screenCharArrayWithDefaultStyle(item, eol: isLast ? EOL_SOFT : EOL_SOFT)
                fragmented.appendLine(sca.line, length: sca.length, partial: true,
                                      width: width,
                                      metadata: sca.metadata, continuation: sca.continuation)
            }

            // Monolithic reference: single append.
            let monolithic = LineBuffer(blockSize: 1_000_000)
            monolithic.mayHaveDoubleWidthCharacter = true
            let fullSCA = screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT)
            monolithic.append(fullSCA, width: width)

            let ctx = "(iter=\(iter), w=\(width), items=\(itemCount))"
            assertWrappedLineParity(fragmented, monolithic, width: width, context: ctx)
        }
    }

    // MARK: - 2. Grapheme split safety at stitch boundary

    func testGraphemeClusterNotSplitAtStitchBoundary() {
        let width: Int32 = 10

        // Seed fills most of the first block.
        let seed = String(repeating: "A", count: 8)  // 8 ASCII chars

        // Item starts with base + combining mark, then more chars.
        // The base+combining should never be split across lines.
        let item1 = "e\u{0301}" + String(repeating: "B", count: 20)  // e + combining acute + 20 B's

        let fragmented = LineBuffer(blockSize: 64)
        fragmented.append(screenCharArrayWithDefaultStyle(seed, eol: EOL_SOFT), width: width)
        let sca1 = screenCharArrayWithDefaultStyle(item1, eol: EOL_SOFT)
        fragmented.appendLine(sca1.line, length: sca1.length, partial: true,
                              width: width, metadata: sca1.metadata,
                              continuation: sca1.continuation)

        let monolithic = LineBuffer(blockSize: 1_000_000)
        monolithic.append(screenCharArrayWithDefaultStyle(seed + item1, eol: EOL_SOFT),
                          width: width)

        assertWrappedLineParity(fragmented, monolithic, width: width)

        // Verify no line starts with a lone combining mark.
        let fragCount = Int(fragmented.numLines(withWidth: width))
        for i in 0..<fragCount {
            let line = fragmented.wrappedLine(at: Int32(i), width: width)
            let sv = line.stringValue
            if let first = sv.unicodeScalars.first {
                // Combining marks have general category M (Mark).
                let isCombining = first.properties.generalCategory == .nonspacingMark ||
                                  first.properties.generalCategory == .spacingMark ||
                                  first.properties.generalCategory == .enclosingMark
                XCTAssertFalse(isCombining,
                               "Line \(i) starts with lone combining mark: \(sv.prefix(5))")
            }
        }
    }

    func testDWCAtStitchBoundaryHandledCorrectly() {
        let width: Int32 = 10
        let cjk = "\u{4E00}"  // DWC: 2 columns

        // Case A: DWC fits in remaining columns.
        // Seed = 8 ASCII chars (leaves 2 columns for DWC in stitched line).
        let seedA = String(repeating: "A", count: 8)
        let itemA = cjk + String(repeating: "B", count: 10)

        let fragA = LineBuffer(blockSize: 64)
        fragA.mayHaveDoubleWidthCharacter = true
        fragA.append(screenCharArrayWithDefaultStyle(seedA, eol: EOL_SOFT), width: width)
        let scaA = screenCharArrayWithDefaultStyle(itemA, eol: EOL_SOFT)
        fragA.appendLine(scaA.line, length: scaA.length, partial: true,
                         width: width, metadata: scaA.metadata, continuation: scaA.continuation)

        let monoA = LineBuffer(blockSize: 1_000_000)
        monoA.mayHaveDoubleWidthCharacter = true
        monoA.append(screenCharArrayWithDefaultStyle(seedA + itemA, eol: EOL_SOFT), width: width)

        assertWrappedLineParity(fragA, monoA, width: width, context: "DWC fits")

        // Case B: DWC doesn't fit (1 column remaining → DWC_SKIP + wrap).
        let seedB = String(repeating: "A", count: 9)  // 9 chars → 1 column left
        let itemB = cjk + String(repeating: "C", count: 10)

        let fragB = LineBuffer(blockSize: 64)
        fragB.mayHaveDoubleWidthCharacter = true
        fragB.append(screenCharArrayWithDefaultStyle(seedB, eol: EOL_SOFT), width: width)
        let scaB = screenCharArrayWithDefaultStyle(itemB, eol: EOL_SOFT)
        fragB.appendLine(scaB.line, length: scaB.length, partial: true,
                         width: width, metadata: scaB.metadata, continuation: scaB.continuation)

        let monoB = LineBuffer(blockSize: 1_000_000)
        monoB.mayHaveDoubleWidthCharacter = true
        monoB.append(screenCharArrayWithDefaultStyle(seedB + itemB, eol: EOL_SOFT), width: width)

        assertWrappedLineParity(fragB, monoB, width: width, context: "DWC wraps")
    }

    // MARK: - 3. Continuation style fields

    func testContinuationStyleFieldsPreservedAcrossStitch() {
        let width: Int32 = 80

        // Build a styled continuation character for the seed block.
        var styledCont = screen_char_t.defaultForeground
        styledCont.code = unichar(EOL_SOFT)
        styledCont.foregroundColor = 1  // red
        styledCont.bold = 1
        styledCont.italic = 1

        // Fragmented: seed with styled continuation + bulk items that also
        // carry the styled continuation, so the seed's style survives
        // last-writer-wins in appendToLastLine:.
        let fragmented = LineBuffer(blockSize: 200)
        let seed = Self.alphabetRun(length: 5)
        let seedBuf = screenCharArrayWithDefaultStyle(seed, eol: EOL_SOFT)
        fragmented.appendLine(seedBuf.line, length: seedBuf.length, partial: true,
                              width: width, metadata: seedBuf.metadata,
                              continuation: styledCont)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 30, width: width,
                                              metadata: iTermImmutableMetadataDefault(),
                                              continuation: styledCont)

        // Precondition: must have created continuation blocks.
        XCTAssertGreaterThan(fragmented.testOnlyNumberOfBlocks, 1,
                             "Fixture must create continuation blocks")

        // Monolithic reference: single appendLine with the full concatenated
        // content — a truly independent code path that never touches the
        // bulk/alignment loop.
        let fullContent = seed + Self.alphabetRun(length: 10 * 30)
        let monolithic = LineBuffer(blockSize: 1_000_000)
        let fullBuf = screenCharArrayWithDefaultStyle(fullContent, eol: EOL_SOFT)
        monolithic.appendLine(fullBuf.line, length: fullBuf.length, partial: true,
                              width: width, metadata: fullBuf.metadata,
                              continuation: styledCont)

        // Assert parity including continuation style fields.
        assertWrappedLineParity(fragmented, monolithic, width: width,
                                checkContinuationStyle: true,
                                context: "styled continuation parity")

        // Assert absolute values on line 0's continuation to preserve the
        // original boundary invariant: stitch preserves predecessor's style.
        let line0 = fragmented.wrappedLine(at: 0, width: width)
        XCTAssertEqual(line0.continuation.foregroundColor, 1,
                       "Line 0 continuation foregroundColor should be preserved")
        XCTAssertEqual(line0.continuation.bold, 1,
                       "Line 0 continuation bold should be preserved")
        XCTAssertEqual(line0.continuation.italic, 1,
                       "Line 0 continuation italic should be preserved")
    }

    // MARK: - 4. Metadata merge precedence at boundary

    func testMetadataPreservedAtBoundary() {
        let width: Int32 = 80

        // Block A metadata: timestamp=1000.
        var metaA = iTermMetadataTemporaryWithTimestamp(1000.0)
        let immutableMetaA = iTermMetadataMakeImmutable(metaA)

        let cont = screen_char_t.defaultForeground.with(code: unichar(EOL_SOFT))

        // Fragmented buffer using the bulk path for deterministic fragmentation.
        // All items carry metaA so the seed's timestamp survives last-writer-wins.
        let fragmented = LineBuffer(blockSize: 200)
        let seedText = Self.alphabetRun(length: 5)
        let seedSCA = screenCharArrayWithDefaultStyle(seedText, eol: EOL_SOFT)
        fragmented.appendLine(seedSCA.line, length: seedSCA.length, partial: true,
                              width: width,
                              metadata: immutableMetaA,
                              continuation: cont)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 30, width: width,
                                              metadata: immutableMetaA,
                                              continuation: cont)

        // Precondition: must have created continuation blocks.
        XCTAssertGreaterThan(fragmented.testOnlyNumberOfBlocks, 1,
                             "Fixture must create continuation blocks for boundary test")

        // Monolithic reference: single appendLine with full concatenated
        // content — a truly independent code path.
        let fullContent = seedText + Self.alphabetRun(length: 10 * 30)
        let monolithic = LineBuffer(blockSize: 1_000_000)
        let fullBuf = screenCharArrayWithDefaultStyle(fullContent, eol: EOL_SOFT)
        monolithic.appendLine(fullBuf.line, length: fullBuf.length, partial: true,
                              width: width,
                              metadata: immutableMetaA,
                              continuation: cont)

        // Assert parity including metadata.
        assertWrappedLineParity(fragmented, monolithic, width: width,
                                checkMetadata: true,
                                context: "metadata boundary parity")

        // Assert absolute value: line 0's timestamp must be 1000.
        let line0 = fragmented.wrappedLine(at: 0, width: width)
        XCTAssertEqual(line0.metadata.timestamp, 1000.0,
                       "Line 0 metadata timestamp should be preserved")
    }

    /// Mixed-metadata boundary case: block A tail has metaA, block B head
    /// has metaB, stitch consumes chars from both. Metadata must match a
    /// monolithic reference that applies the same metadata transitions.
    func testMetadataMixedAcrossBoundaryMatchesMonolithic() {
        let width: Int32 = 80

        var metaA = iTermMetadataTemporaryWithTimestamp(1000.0)
        let immutableMetaA = iTermMetadataMakeImmutable(metaA)
        var metaB = iTermMetadataTemporaryWithTimestamp(2000.0)
        metaB.rtlFound = true
        let immutableMetaB = iTermMetadataMakeImmutable(metaB)
        let cont = screen_char_t.defaultForeground.with(code: unichar(EOL_SOFT))

        // Fragmented: seed(5, metaA) + first bulk(10×30, metaA) + second bulk(10×30, metaB).
        // First bulk creates block A + continuation block B (both metaA).
        // Second bulk's alignment loop updates block B to metaB; remainder → block C.
        let fragmented = LineBuffer(blockSize: 200)
        let seedText = String(repeating: "X", count: 5)
        let seedSCA = screenCharArrayWithDefaultStyle(seedText, eol: EOL_SOFT)
        fragmented.appendLine(seedSCA.line, length: seedSCA.length, partial: true,
                              width: width, metadata: immutableMetaA, continuation: cont)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 30, width: width,
                                              metadata: immutableMetaA,
                                              continuation: cont)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 30, width: width,
                                              metadata: immutableMetaB,
                                              continuation: cont)

        XCTAssertGreaterThan(fragmented.testOnlyNumberOfBlocks, 2,
                             "Fixture must create multiple continuation blocks")

        // Monolithic reference: same content and metadata transitions via
        // appendLine into a single block.
        let monolithic = LineBuffer(blockSize: 1_000_000)
        monolithic.appendLine(seedSCA.line, length: seedSCA.length, partial: true,
                              width: width, metadata: immutableMetaA, continuation: cont)
        for i in 0..<10 {
            let chunk = Self.alphabetRun(length: 30, startingAt: i * 30)
            let sca = screenCharArrayWithDefaultStyle(chunk, eol: EOL_SOFT)
            monolithic.appendLine(sca.line, length: sca.length, partial: true,
                                  width: width, metadata: immutableMetaA, continuation: cont)
        }
        for i in 0..<10 {
            let chunk = Self.alphabetRun(length: 30, startingAt: i * 30)
            let sca = screenCharArrayWithDefaultStyle(chunk, eol: EOL_SOFT)
            monolithic.appendLine(sca.line, length: sca.length, partial: true,
                                  width: width, metadata: immutableMetaB, continuation: cont)
        }

        assertWrappedLineParity(fragmented, monolithic, width: width,
                                checkMetadata: false,
                                context: "mixed metadata content parity")

        assertWrappedLineParity(fragmented, monolithic, width: width,
                                checkMetadata: true,
                                context: "mixed metadata across boundary")
    }

    /// Metadata propagation through the continuation chain: line 0 is
    /// entirely inside block A, but after a second bulk append with metaB
    /// lands in block B, block A's metadata must reflect metaB.
    func testPredecessorMetadataPropagatesOnBulkAppend() {
        let width: Int32 = 80

        var metaA = iTermMetadataTemporaryWithTimestamp(1000.0)
        let immutableMetaA = iTermMetadataMakeImmutable(metaA)
        var metaB = iTermMetadataTemporaryWithTimestamp(2000.0)
        metaB.rtlFound = true
        let immutableMetaB = iTermMetadataMakeImmutable(metaB)
        let cont = screen_char_t.defaultForeground.with(code: unichar(EOL_SOFT))

        let buffer = LineBuffer(blockSize: 200)
        let seedSCA = screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                      eol: EOL_SOFT)
        buffer.appendLine(seedSCA.line, length: seedSCA.length, partial: true,
                          width: width, metadata: immutableMetaA, continuation: cont)
        buffer.testOnlyAppendPartialItems(10, ofLength: 30, width: width,
                                          metadata: immutableMetaA, continuation: cont)

        // Line 0 is entirely in block A; metadata should be metaA.
        let before = buffer.wrappedLine(at: 0, width: width)
        XCTAssertEqual(before.metadata.timestamp, 1000.0)
        XCTAssertFalse(before.metadata.rtlFound.boolValue)

        // Second bulk with metaB lands in block B.
        buffer.testOnlyAppendPartialItems(10, ofLength: 30, width: width,
                                          metadata: immutableMetaB, continuation: cont)

        // Line 0 is still in block A, but metadata must now reflect metaB.
        let after = buffer.wrappedLine(at: 0, width: width)
        XCTAssertEqual(after.metadata.timestamp, 2000.0,
                       "Block A line 0 timestamp must propagate from continuation")
        XCTAssertTrue(after.metadata.rtlFound.boolValue,
                      "Block A line 0 rtlFound must propagate from continuation")
    }

    // MARK: - 5. EOL matrix coverage

    func testEOLMatrixAtBoundary() {
        let width: Int32 = 10

        // Helper to create a fixture for a specific EOL case.
        func makeFixture(headLength: Int, headPartial: Bool) -> (fragmented: LineBuffer, monolithic: LineBuffer) {
            // Seed: 7 chars partial → fills 7 of 10 columns, so head needs 3 chars to fill.
            let seed = Self.alphabetRun(length: 7)
            let headText = Self.alphabetRun(length: headLength, startingAt: 7)

            let frag = LineBuffer(blockSize: 64)
            frag.append(screenCharArrayWithDefaultStyle(seed, eol: EOL_SOFT), width: width)

            let cont = screen_char_t.defaultForeground.with(code: unichar(headPartial ? EOL_SOFT : EOL_HARD))
            let headSCA = screenCharArrayWithDefaultStyle(headText, eol: headPartial ? EOL_SOFT : EOL_HARD)
            frag.appendLine(headSCA.line, length: headSCA.length,
                            partial: headPartial, width: width,
                            metadata: headSCA.metadata, continuation: cont)

            // If there are more chars after the head, add them to keep the buffer non-trivial.
            if headPartial {
                let tail = Self.alphabetRun(length: 20, startingAt: 7 + headLength)
                let tailSCA = screenCharArrayWithDefaultStyle(tail, eol: EOL_SOFT)
                frag.appendLine(tailSCA.line, length: tailSCA.length, partial: true,
                                width: width, metadata: tailSCA.metadata,
                                continuation: tailSCA.continuation)
            }

            // Monolithic reference.
            let mono = LineBuffer(blockSize: 1_000_000)
            var fullText = seed + headText
            if headPartial {
                fullText += Self.alphabetRun(length: 20, startingAt: 7 + headLength)
            }
            if headPartial {
                mono.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT), width: width)
            } else {
                // Non-partial head = hard EOL. Append seed+head as one line, rest (if any) as another.
                let seedPlusHead = seed + headText
                let seedPlusHeadSCA = screenCharArrayWithDefaultStyle(seedPlusHead, eol: EOL_HARD)
                mono.appendLine(seedPlusHeadSCA.line, length: seedPlusHeadSCA.length,
                                partial: false, width: width,
                                metadata: seedPlusHeadSCA.metadata,
                                continuation: seedPlusHeadSCA.continuation)
            }

            return (frag, mono)
        }

        // Case 1: Head fully consumed (3 chars) + head ends hard.
        let case1 = makeFixture(headLength: 3, headPartial: false)
        assertWrappedLineParity(case1.fragmented, case1.monolithic, width: width,
                                context: "consumed+hard")

        // Case 2: Head fully consumed (3 chars) + head ends soft.
        let case2 = makeFixture(headLength: 3, headPartial: true)
        assertWrappedLineParity(case2.fragmented, case2.monolithic, width: width,
                                context: "consumed+soft")

        // Case 3: Head partially consumed (15 chars, only 3 used) + head ends hard.
        let case3 = makeFixture(headLength: 15, headPartial: false)
        assertWrappedLineParity(case3.fragmented, case3.monolithic, width: width,
                                context: "partial+hard")

        // Case 4: Head partially consumed (15 chars) + head ends soft.
        let case4 = makeFixture(headLength: 15, headPartial: true)
        assertWrappedLineParity(case4.fragmented, case4.monolithic, width: width,
                                context: "partial+soft")
    }

    // MARK: - 6. Query-width extremes

    func testExtremeWidths() {
        let creationWidth: Int32 = 80
        let totalChars = 200

        let fragmented = LineBuffer(blockSize: 64)
        fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                          eol: EOL_SOFT),
                          width: creationWidth)
        fragmented.testOnlyAppendPartialItems(5, ofLength: 39, width: creationWidth)

        let monolithic = LineBuffer(blockSize: 1_000_000)
        let fullText = String(repeating: "X", count: 5) + Self.alphabetRun(length: 195)
        monolithic.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT),
                          width: creationWidth)

        let queryWidths: [Int32] = [1, 2, 3, 5, 7, 200, 500]
        for w in queryWidths {
            assertWrappedLineParity(fragmented, monolithic, width: w,
                                    context: "queryWidth=\(w)")
        }
    }

    func testWidthChangeAfterCreation() {
        let creationWidth: Int32 = 80

        let fragmented = LineBuffer(blockSize: 1000)
        fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                          eol: EOL_SOFT),
                          width: creationWidth)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 30, width: creationWidth)

        let monolithic = LineBuffer(blockSize: 1_000_000)
        let fullText = String(repeating: "X", count: 5) + Self.alphabetRun(length: 300)
        monolithic.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT),
                          width: creationWidth)

        for w: Int32 in [40, 120, 13] {
            assertWrappedLineParity(fragmented, monolithic, width: w,
                                    context: "createdAt=\(creationWidth) queryAt=\(w)")
        }
    }

    // MARK: - 7. Multi-boundary chains

    func testFourBlockContinuationChain() {
        let width: Int32 = 80

        let fragmented = LineBuffer(blockSize: 1000)
        // Seed to create misalignment.
        fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 30),
                                                          eol: EOL_SOFT),
                          width: width)
        // Three successive bulk appends to create 4+ blocks.
        fragmented.testOnlyAppendPartialItems(10, ofLength: 80, width: width)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 80, width: width)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 80, width: width)

        XCTAssertGreaterThanOrEqual(fragmented.testOnlyNumberOfBlocks, 4,
                                   "Need 4+ blocks for chain test")

        let monolithic = LineBuffer(blockSize: 1_000_000)
        // Each call to testOnlyAppendPartialItems restarts its alphabet from 'A',
        // so the monolithic content must match: seed + 3 × alphabetRun(800).
        let fullText = String(repeating: "X", count: 30)
            + Self.alphabetRun(length: 800)
            + Self.alphabetRun(length: 800)
            + Self.alphabetRun(length: 800)
        monolithic.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT),
                          width: width)

        for w: Int32 in [10, 40, 80, 120] {
            assertWrappedLineParity(fragmented, monolithic, width: w,
                                    context: "4-block chain w=\(w)")
        }
    }

    func testQueryTraversingMultipleBoundaries() {
        let width: Int32 = 80

        let fragmented = LineBuffer(blockSize: 1000)
        fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 30),
                                                          eol: EOL_SOFT),
                          width: width)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 80, width: width)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 80, width: width)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 80, width: width)

        let wrappedCount = Int(fragmented.numLines(withWidth: width))

        // Compare enumerateLinesInRange output against wrappedLineAtIndex.
        var enumLines = [(string: String, eol: Int32, contCode: unichar)]()
        fragmented.enumerateLines(
            in: NSRange(location: 0, length: wrappedCount),
            width: width
        ) { lineNum, sca, metadata, stop in
            enumLines.append((sca.stringValue, sca.eol, sca.continuation.code))
        }
        XCTAssertEqual(enumLines.count, wrappedCount)
        for i in 0..<wrappedCount {
            let direct = fragmented.wrappedLine(at: Int32(i), width: width)
            XCTAssertEqual(enumLines[i].string, direct.stringValue,
                           "enumerate vs direct content mismatch at line \(i)")
            XCTAssertEqual(enumLines[i].eol, direct.eol,
                           "enumerate vs direct eol mismatch at line \(i)")
            XCTAssertEqual(enumLines[i].contCode, direct.continuation.code,
                           "enumerate vs direct continuation.code mismatch at line \(i)")
        }
    }

    // MARK: - 8. Search position edge endpoints

    func testSearchMatchAtBlockBoundary() {
        let width: Int32 = 80

        // Create a buffer where "ABCDEFGHIJ" spans across the block boundary.
        // Seed of 5 chars + bulk items → the A-Z repeating pattern starts at offset 5.
        let fragmented = LineBuffer(blockSize: 1000)
        fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                          eol: EOL_SOFT),
                          width: width)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        let monolithic = LineBuffer(blockSize: 1_000_000)
        let fullText = String(repeating: "X", count: 5) + Self.alphabetRun(length: 300)
        monolithic.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT),
                          width: width)

        let searchTerm = "ABCDEFGHIJ"

        func collectResults(_ buffer: LineBuffer) -> [ResultRange] {
            let context = FindContext()
            buffer.prepareToSearch(for: searchTerm,
                                   startingAt: buffer.firstPosition(),
                                   options: FindOptions(rawValue: FindOptions.multipleResults.rawValue),
                                   mode: .caseSensitiveSubstring,
                                   with: context)
            var allResults = [ResultRange]()
            while context.status != .NotFound {
                buffer.findSubstring(context, stopAt: buffer.lastPosition())
                if let results = context.results as? [ResultRange] {
                    allResults.append(contentsOf: results)
                    context.results?.removeAllObjects()
                }
            }
            return allResults
        }

        let fragResults = collectResults(fragmented)
        let monoResults = collectResults(monolithic)

        XCTAssertGreaterThan(monoResults.count, 0)
        XCTAssertEqual(fragResults.count, monoResults.count,
                       "Search result count mismatch")

        let fragXY = fragmented.convertPositions(fragResults, withWidth: width) ?? []
        let monoXY = monolithic.convertPositions(monoResults, withWidth: width) ?? []

        XCTAssertEqual(fragXY.count, monoXY.count)
        for i in 0..<min(fragXY.count, monoXY.count) {
            XCTAssertEqual(fragXY[i].xStart, monoXY[i].xStart,
                           "xStart mismatch at result \(i)")
            XCTAssertEqual(fragXY[i].yStart, monoXY[i].yStart,
                           "yStart mismatch at result \(i)")
            XCTAssertEqual(fragXY[i].xEnd, monoXY[i].xEnd,
                           "xEnd mismatch at result \(i)")
            XCTAssertEqual(fragXY[i].yEnd, monoXY[i].yEnd,
                           "yEnd mismatch at result \(i)")
        }
    }

    func testSearchMatchAtExactLineEnd() {
        let width: Int32 = 10

        // Create content where a match ends at exactly column width-1.
        // 10-char line "ABCDEFGHIJ" fills exactly 1 wrapped line.
        let fragmented = LineBuffer(blockSize: 64)
        fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 3),
                                                          eol: EOL_SOFT),
                          width: width)
        fragmented.testOnlyAppendPartialItems(5, ofLength: 20, width: width)

        let monolithic = LineBuffer(blockSize: 1_000_000)
        let fullText = String(repeating: "X", count: 3) + Self.alphabetRun(length: 100)
        monolithic.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT),
                          width: width)

        let searchTerm = "ABCDEFG"  // 7 chars starting at offset 3 → ends at column 9 (width-1)

        func collectResults(_ buffer: LineBuffer) -> [ResultRange] {
            let context = FindContext()
            buffer.prepareToSearch(for: searchTerm,
                                   startingAt: buffer.firstPosition(),
                                   options: FindOptions(rawValue: FindOptions.multipleResults.rawValue),
                                   mode: .caseSensitiveSubstring,
                                   with: context)
            var allResults = [ResultRange]()
            while context.status != .NotFound {
                buffer.findSubstring(context, stopAt: buffer.lastPosition())
                if let results = context.results as? [ResultRange] {
                    allResults.append(contentsOf: results)
                    context.results?.removeAllObjects()
                }
            }
            return allResults
        }

        let fragResults = collectResults(fragmented)
        let monoResults = collectResults(monolithic)

        XCTAssertGreaterThan(monoResults.count, 0)
        XCTAssertEqual(fragResults.count, monoResults.count)

        let fragXY = fragmented.convertPositions(fragResults, withWidth: width) ?? []
        let monoXY = monolithic.convertPositions(monoResults, withWidth: width) ?? []

        for i in 0..<min(fragXY.count, monoXY.count) {
            XCTAssertEqual(fragXY[i].xEnd, monoXY[i].xEnd,
                           "xEnd mismatch at result \(i)")
            XCTAssertEqual(fragXY[i].yEnd, monoXY[i].yEnd,
                           "yEnd mismatch at result \(i)")
        }
    }

    func testSearchMatchAtExactLineStart() {
        let width: Int32 = 10

        // Content: 10 chars fills line 0, then search term starts at column 0 of line 1.
        let fragmented = LineBuffer(blockSize: 64)
        fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                          eol: EOL_SOFT),
                          width: width)
        fragmented.testOnlyAppendPartialItems(5, ofLength: 20, width: width)

        let monolithic = LineBuffer(blockSize: 1_000_000)
        let fullText = String(repeating: "X", count: 5) + Self.alphabetRun(length: 100)
        monolithic.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT),
                          width: width)

        // Search for the substring that starts right after the first 10 chars.
        // First 10 chars: "XXXXXABCDE", line 1 starts with "FGHIJKLMNO"
        let searchTerm = "FGHIJ"

        func collectResults(_ buffer: LineBuffer) -> [ResultRange] {
            let context = FindContext()
            buffer.prepareToSearch(for: searchTerm,
                                   startingAt: buffer.firstPosition(),
                                   options: FindOptions(rawValue: FindOptions.multipleResults.rawValue),
                                   mode: .caseSensitiveSubstring,
                                   with: context)
            var allResults = [ResultRange]()
            while context.status != .NotFound {
                buffer.findSubstring(context, stopAt: buffer.lastPosition())
                if let results = context.results as? [ResultRange] {
                    allResults.append(contentsOf: results)
                    context.results?.removeAllObjects()
                }
            }
            return allResults
        }

        let fragResults = collectResults(fragmented)
        let monoResults = collectResults(monolithic)

        XCTAssertGreaterThan(monoResults.count, 0)
        XCTAssertEqual(fragResults.count, monoResults.count)

        let fragXY = fragmented.convertPositions(fragResults, withWidth: width) ?? []
        let monoXY = monolithic.convertPositions(monoResults, withWidth: width) ?? []

        // First result should start at x=0 of some line.
        if let first = fragXY.first {
            XCTAssertEqual(first.xStart, monoXY.first!.xStart,
                           "xStart mismatch")
            XCTAssertEqual(first.yStart, monoXY.first!.yStart,
                           "yStart mismatch")
        }
    }

    // MARK: - 9. Mutation-after-fragmentation parity

    func testMutationSequenceParityVsMonolithic() {
        let width: Int32 = 80

        // Build initial content.
        let fragmented = LineBuffer(blockSize: 1000)
        fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                          eol: EOL_SOFT),
                          width: width)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        let monolithic = LineBuffer(blockSize: 1_000_000)
        let fullText = String(repeating: "X", count: 5) + Self.alphabetRun(length: 300)
        monolithic.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT),
                          width: width)

        // Step 1: Remove last 3 wrapped lines.
        fragmented.removeLastWrappedLines(3, width: width)
        monolithic.removeLastWrappedLines(3, width: width)
        assertWrappedLineParity(fragmented, monolithic, width: width,
                                context: "after removeLastWrappedLines")

        // Step 2: Append more content.
        let moreText = Self.alphabetRun(length: 50, startingAt: 10)
        fragmented.append(screenCharArrayWithDefaultStyle(moreText, eol: EOL_SOFT),
                          width: width)
        monolithic.append(screenCharArrayWithDefaultStyle(moreText, eol: EOL_SOFT),
                          width: width)
        assertWrappedLineParity(fragmented, monolithic, width: width,
                                context: "after append more")

        // Step 3: Set max lines and drop excess.
        fragmented.setMaxLines(3)
        monolithic.setMaxLines(3)
        fragmented.dropExcessLines(withWidth: width)
        monolithic.dropExcessLines(withWidth: width)
        assertWrappedLineParity(fragmented, monolithic, width: width,
                                context: "after dropExcess")
    }

    func testPopLastLineFromFragmentedBuffer() {
        let width: Int32 = 80

        let fragmented = LineBuffer(blockSize: 1000)
        fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                          eol: EOL_SOFT),
                          width: width)
        fragmented.testOnlyAppendPartialItems(5, ofLength: 30, width: width)

        let monolithic = LineBuffer(blockSize: 1_000_000)
        let fullText = String(repeating: "X", count: 5) + Self.alphabetRun(length: 150)
        monolithic.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT),
                          width: width)

        let fragPopped = fragmented.popLastLine(withWidth: width)
        let monoPopped = monolithic.popLastLine(withWidth: width)

        XCTAssertEqual(fragPopped?.stringValue, monoPopped?.stringValue,
                       "Popped line content mismatch")
        assertWrappedLineParity(fragmented, monolithic, width: width,
                                context: "after pop")
    }

    func testTruncateAndAppendAgain() {
        let width: Int32 = 80

        let fragmented = LineBuffer(blockSize: 1000)
        fragmented.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                          eol: EOL_SOFT),
                          width: width)
        fragmented.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        let monolithic = LineBuffer(blockSize: 1_000_000)
        let fullText = String(repeating: "X", count: 5) + Self.alphabetRun(length: 300)
        monolithic.append(screenCharArrayWithDefaultStyle(fullText, eol: EOL_SOFT),
                          width: width)

        // Truncate to 2 lines.
        let fragLines = Int(fragmented.numLines(withWidth: width))
        let monoLines = Int(monolithic.numLines(withWidth: width))
        fragmented.removeLastWrappedLines(Int32(fragLines - 2), width: width)
        monolithic.removeLastWrappedLines(Int32(monoLines - 2), width: width)

        // Append new content.
        let newText = Self.alphabetRun(length: 100, startingAt: 15)
        fragmented.append(screenCharArrayWithDefaultStyle(newText, eol: EOL_HARD),
                          width: width)
        monolithic.append(screenCharArrayWithDefaultStyle(newText, eol: EOL_HARD),
                          width: width)

        assertWrappedLineParity(fragmented, monolithic, width: width,
                                context: "after truncate+append")
    }

    // MARK: - 10. Performance regression tests

    func testBulkAppendScalingIsLinear() {
        let width: Int32 = 80
        let itemLength: Int32 = 100

        // Measure time for N items.
        let nSmall: Int32 = 25_000
        let startSmall = CFAbsoluteTimeGetCurrent()
        let bufSmall = LineBuffer(blockSize: 8192)
        bufSmall.testOnlyAppendPartialItems(nSmall, ofLength: itemLength, width: width)
        let timeSmall = CFAbsoluteTimeGetCurrent() - startSmall

        // Measure time for 2N items.
        let nLarge: Int32 = 50_000
        let startLarge = CFAbsoluteTimeGetCurrent()
        let bufLarge = LineBuffer(blockSize: 8192)
        bufLarge.testOnlyAppendPartialItems(nLarge, ofLength: itemLength, width: width)
        let timeLarge = CFAbsoluteTimeGetCurrent() - startLarge

        // Ratio-based scaling: 2N should take roughly 2x as long, not 4x.
        let ratio = timeLarge / max(timeSmall, 0.001)
        XCTAssertLessThan(ratio, 2.5,
                          "Scaling ratio \(ratio) exceeds 2.5x — possible quadratic regression "
                          + "(N=\(timeSmall)s, 2N=\(timeLarge)s)")

        // Structural gate: block count should be O(n/blockSize).
        let expectedMaxBlocks = Int(nLarge * itemLength) / 8192 + 10
        XCTAssertLessThan(Int(bufLarge.testOnlyNumberOfBlocks), expectedMaxBlocks,
                          "Too many blocks (\(bufLarge.testOnlyNumberOfBlocks)) — bulk path may not be working")

        // Catastrophic wall-clock cap.
        XCTAssertLessThan(timeLarge, 10.0,
                          "50k items took \(timeLarge)s — catastrophic slowdown")
    }

    // MARK: - 11. Copy/snapshot/COW behavior tests

    func testCopyDoesNotRegressionToQuadratic() {
        let width: Int32 = 80

        let original = LineBuffer(blockSize: 1000)
        original.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                        eol: EOL_SOFT),
                        width: width)
        original.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        // Precondition: must have multiple blocks for COW test to be meaningful.
        XCTAssertGreaterThan(original.testOnlyNumberOfBlocks, 1,
                             "Fixture must create multiple blocks")

        let origLineCount = Int(original.numLines(withWidth: width))

        // Copy.
        let copy = original.copy() as! LineBuffer

        // Structural COW check: after copy(), every block in the original
        // must have at least one client (the copy), proving actual data sharing.
        for i in 0..<original.testOnlyNumberOfBlocks {
            let block = original.testOnlyBlock(at: i)
            XCTAssertGreaterThanOrEqual(block.numberOfClients, 1,
                                        "Block \(i) should have COW client after copy()")
        }

        // Verify copy matches original.
        XCTAssertEqual(Int(copy.numLines(withWidth: width)), origLineCount)
        for i in 0..<origLineCount {
            let origLine = original.wrappedLine(at: Int32(i), width: width)
            let copyLine = copy.wrappedLine(at: Int32(i), width: width)
            XCTAssertEqual(origLine.stringValue, copyLine.stringValue,
                           "Copy content mismatch at line \(i)")
        }

        // Mutate original: append more.
        original.testOnlyAppendPartialItems(5, ofLength: 30, width: width)

        // Copy should be unmodified (COW correctness).
        XCTAssertEqual(Int(copy.numLines(withWidth: width)), origLineCount,
                       "Copy should be unmodified after mutating original")

        // Original should have new content.
        XCTAssertGreaterThan(Int(original.numLines(withWidth: width)), origLineCount,
                             "Original should have more lines after append")

        // Verify copy content is still intact after original mutation.
        for i in 0..<origLineCount {
            let copyLine = copy.wrappedLine(at: Int32(i), width: width)
            XCTAssertFalse(copyLine.stringValue.isEmpty,
                           "Copy line \(i) should still be readable after original mutation")
        }
    }

    func testRepeatedCopyAndAppendPerformance() {
        let width: Int32 = 80

        let start = CFAbsoluteTimeGetCurrent()
        var buffer = LineBuffer(blockSize: 8192)
        buffer.testOnlyAppendPartialItems(1000, ofLength: 100, width: width)

        for _ in 0..<100 {
            let copy = buffer.copy() as! LineBuffer
            copy.testOnlyAppendPartialItems(100, ofLength: 100, width: width)
            buffer = copy
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(elapsed, 5.0,
                          "100 copy+append cycles took \(elapsed)s — possible COW regression")
    }

    // MARK: - 12. Remainder normalization for continuation adjustment

    /// Builds a fragmented buffer where block B has
    /// continuationWrappedLineAdjustment == -1 (hidden head line) and a
    /// monolithic single-block reference with identical content.
    /// Width=80, seed=5 partial, then mixed items to force:
    /// - block A: 5 + 3*30 = 95 chars
    /// - block B starts with continuation, first raw line length 20 (hard EOL)
    /// With pCol=15, the continuation adjustment is -1.
    private func makeAdjustmentMinusOneFixture() -> (fragmented: LineBuffer, monolithic: LineBuffer, width: Int32) {
        let width: Int32 = 80
        let cont = screen_char_t.defaultForeground.with(code: unichar(EOL_SOFT))

        let fragmented = LineBuffer(blockSize: 64)
        let seedSCA = screenCharArrayWithDefaultStyle(String(repeating: "A", count: 5), eol: EOL_SOFT)
        fragmented.appendLine(seedSCA.line, length: seedSCA.length, partial: true,
                              width: width, metadata: seedSCA.metadata, continuation: cont)
        let lengths: [NSNumber] = [30, 30, 30, 20, 30, 30, 30, 30, 30, 30]
        let partials: [NSNumber] = [true, true, true, false, true, true, true, true, true, true]
        fragmented.testOnlyAppendItems(withLengths: lengths, partials: partials, width: width)

        let monolithic = LineBuffer(blockSize: 1_000_000)
        // Logical raw line 0: seed + items 0..3 = 5 + (90 + 20) = 115, hard.
        let raw0 = String(repeating: "A", count: 5) + Self.alphabetRun(length: 110)
        monolithic.append(screenCharArrayWithDefaultStyle(raw0, eol: EOL_HARD), width: width)
        // Logical raw line 1: items 4..9 = 180, partial.
        let raw1 = Self.alphabetRun(length: 180, startingAt: 110)
        monolithic.append(screenCharArrayWithDefaultStyle(raw1, eol: EOL_SOFT), width: width)

        // Verify fixture invariants.
        XCTAssertGreaterThan(fragmented.testOnlyNumberOfBlocks, 1,
                             "Fixture must create multiple blocks")
        XCTAssertEqual(monolithic.testOnlyNumberOfBlocks, 1,
                       "Monolithic reference must be a single block")
        XCTAssertEqual(fragmented.numLines(withWidth: width), monolithic.numLines(withWidth: width),
                       "Fixture line counts must match")
        XCTAssertGreaterThanOrEqual(fragmented.numLines(withWidth: width), 5,
                                    "Fixture should have enough wrapped lines for range tests")

        // The key invariant: block B (index 1) must have adjustment == -1.
        let blockB = fragmented.testOnlyBlock(at: 1)
        XCTAssertEqual(blockB.continuationWrappedLineAdjustment(forWidth: width), -1,
                       "Continuation block must have adjustment == -1")

        return (fragmented, monolithic, width)
    }

    /// positionForCoordinate parity: on an adjustment == -1 continuation
    /// boundary, the fragmented buffer must return the same absolute
    /// positions as the monolithic reference.
    func testPositionForCoordinateParityWithContinuationAdjustment() {
        let (fragmented, monolithic, width) = makeAdjustmentMinusOneFixture()
        let numLines = Int(fragmented.numLines(withWidth: width))

        for y in 0..<Int32(numLines) {
            for x: Int32 in [0, width - 1] {
                let coord = VT100GridCoord(x: x, y: y)
                let fragPos = fragmented.position(forCoordinate: coord, width: width, offset: 0)
                let monoPos = monolithic.position(forCoordinate: coord, width: width, offset: 0)
                XCTAssertNotNil(fragPos, "fragmented position nil at (\(x),\(y))")
                XCTAssertNotNil(monoPos, "monolithic position nil at (\(x),\(y))")
                XCTAssertEqual(fragPos?.absolutePosition, monoPos?.absolutePosition,
                               "positionForCoordinate mismatch at (\(x),\(y))")
            }
        }
    }

    /// numberOfCellsUsedInWrappedLineRange parity: ranges that cross or
    /// sit on an adjustment == -1 continuation boundary must match
    /// monolithic cell counts.
    func testNumberOfCellsUsedParityWithContinuationAdjustment() {
        let (fragmented, monolithic, width) = makeAdjustmentMinusOneFixture()
        let numLines = Int(fragmented.numLines(withWidth: width))

        // Test a sliding window of various sizes across all lines.
        for rangeLength in [1, 2, 3, 5] {
            for start in 0..<(numLines - rangeLength + 1) {
                let range = VT100GridRange(location: Int32(start), length: Int32(rangeLength))
                let fragCells = fragmented.numberOfCellsUsed(inWrappedLineRange: range, width: width)
                let monoCells = monolithic.numberOfCellsUsed(inWrappedLineRange: range, width: width)
                XCTAssertEqual(fragCells, monoCells,
                               "numberOfCellsUsed mismatch for range (\(start), \(rangeLength))")
            }
        }
    }

    /// Round-trip coordinate conversion parity: convert a coordinate to a
    /// position and back. On an adjustment == -1 boundary, the fragmented
    /// buffer must reproduce the original coordinate exactly as monolithic does.
    func testCoordinateRoundTripParityWithContinuationAdjustment() {
        let (fragmented, monolithic, width) = makeAdjustmentMinusOneFixture()
        let numLines = Int(fragmented.numLines(withWidth: width))

        for y in 0..<Int32(numLines) {
            for x: Int32 in [0, width / 2, width - 1] {
                let coord = VT100GridCoord(x: x, y: y)

                let monoPos = monolithic.position(forCoordinate: coord, width: width, offset: 0)
                guard let monoPos else {
                    XCTFail("monolithic position nil at (\(x),\(y))")
                    continue
                }
                var monoOk = ObjCBool(false)
                let monoCoord = monolithic.coordinate(for: monoPos, width: width,
                                                      extendsRight: false, ok: &monoOk)

                let fragPos = fragmented.position(forCoordinate: coord, width: width, offset: 0)
                guard let fragPos else {
                    XCTFail("fragmented position nil at (\(x),\(y))")
                    continue
                }
                var fragOk = ObjCBool(false)
                let fragCoord = fragmented.coordinate(for: fragPos, width: width,
                                                      extendsRight: false, ok: &fragOk)

                XCTAssertTrue(monoOk.boolValue, "monolithic round-trip failed at (\(x),\(y))")
                XCTAssertTrue(fragOk.boolValue, "fragmented round-trip failed at (\(x),\(y))")
                XCTAssertEqual(fragCoord.x, monoCoord.x,
                               "round-trip x mismatch at (\(x),\(y))")
                XCTAssertEqual(fragCoord.y, monoCoord.y,
                               "round-trip y mismatch at (\(x),\(y))")
            }
        }
    }

    func testSearchOnCopiedBufferMatchesOriginal() {
        let width: Int32 = 80

        let original = LineBuffer(blockSize: 1000)
        original.append(screenCharArrayWithDefaultStyle(String(repeating: "X", count: 5),
                                                        eol: EOL_SOFT),
                        width: width)
        original.testOnlyAppendPartialItems(10, ofLength: 30, width: width)

        let copy = original.copy() as! LineBuffer

        let searchTerm = "ABCDEFGHIJ"

        func collectResults(_ buffer: LineBuffer) -> [ResultRange] {
            let context = FindContext()
            buffer.prepareToSearch(for: searchTerm,
                                   startingAt: buffer.firstPosition(),
                                   options: FindOptions(rawValue: FindOptions.multipleResults.rawValue),
                                   mode: .caseSensitiveSubstring,
                                   with: context)
            var allResults = [ResultRange]()
            while context.status != .NotFound {
                buffer.findSubstring(context, stopAt: buffer.lastPosition())
                if let results = context.results as? [ResultRange] {
                    allResults.append(contentsOf: results)
                    context.results?.removeAllObjects()
                }
            }
            return allResults
        }

        let origResults = collectResults(original)
        let copyResults = collectResults(copy)

        XCTAssertGreaterThan(origResults.count, 0)
        XCTAssertEqual(origResults.count, copyResults.count,
                       "Search result count mismatch between original and copy")
        for i in 0..<min(origResults.count, copyResults.count) {
            XCTAssertEqual(origResults[i].position, copyResults[i].position,
                           "Position mismatch at result \(i)")
            XCTAssertEqual(origResults[i].length, copyResults[i].length,
                           "Length mismatch at result \(i)")
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
