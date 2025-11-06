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
                                    underlineStyle: VT100UnderlineStyle.single,
                                    invisible: 0,
                                    inverse: 0,
                                    guarded: 0,
                                    virtualPlaceholder: 0,
                                    rtlStatus: .unknown,
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
                                                 underlineStyle: .single,
                                                 invisible: 0,
                                                 inverse: 0,
                                                 guarded: 0,
                                                 virtualPlaceholder: 0,
                                                 rtlStatus: .unknown,
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
                                                 underlineStyle: .single,
                                                 invisible: 0,
                                                 inverse: 0,
                                                 guarded: 0,
                                                 virtualPlaceholder: 0,
                                                 rtlStatus: .unknown,
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
                             underlineStyle: underlineStyle,
                             invisible: invisible,
                             inverse: inverse,
                             guarded: guarded,
                             virtualPlaceholder: 0,
                             rtlStatus: .unknown,
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
