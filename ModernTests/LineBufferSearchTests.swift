//
//  LineBufferSearchTests.swift
//  iTerm2
//
//  Ported from the legacy SearchTests.m. Exercises LineBlock substring search
//  going backwards with multiple results, including adjacent candidate matches and
//  text whose cells are complex characters made of many combining marks.
//

import XCTest
@testable import iTerm2SharedARC

final class LineBufferSearchTests: XCTestCase {
    private static let rawBufferSize = 8192

    // MARK: - Helpers

    // Appends `string` to a fresh LineBlock as one hard-EOL raw line, the way the
    // legacy test did, converting it with StringToScreenChars.
    private func makeBlock(containing string: String) -> LineBlock {
        let block = LineBlock(rawBufferSize: Int32(Self.rawBufferSize), absoluteBlockNumber: 0)
        var buffer = [screen_char_t](repeating: screen_char_t(), count: Self.rawBufferSize)
        var length = Int32(Self.rawBufferSize)
        var foundDwc = ObjCBool(false)
        buffer.withUnsafeMutableBufferPointer { umbp in
            StringToScreenChars(string,
                                umbp.baseAddress!,
                                screen_char_t(),
                                screen_char_t(),
                                &length,
                                false,
                                nil,
                                &foundDwc,
                                .none,
                                9,
                                false,
                                nil)
            append(umbp.baseAddress!, length: length, to: block)
        }
        return block
    }

    // Appends one hard-EOL raw line with a cell per character of `ascii`. A "\0" leaves
    // the cell unwritten, as when the cursor moves over it with CHA or CUF.
    private func makeBlock(cells ascii: String) -> LineBlock {
        let block = LineBlock(rawBufferSize: Int32(Self.rawBufferSize), absoluteBlockNumber: 0)
        var buffer = ascii.utf16.map { code -> screen_char_t in
            var c = screen_char_t()
            c.code = code
            return c
        }
        buffer.withUnsafeMutableBufferPointer { umbp in
            append(umbp.baseAddress!, length: Int32(umbp.count), to: block)
        }
        return block
    }

    private func append(_ line: UnsafeMutablePointer<screen_char_t>, length: Int32, to block: LineBlock) {
        var eol = screen_char_t()
        eol.code = unichar(EOL_HARD)
        block.appendLine(line,
                         length: length,
                         partial: false,
                         width: 80,
                         metadata: iTermImmutableMetadataDefault(),
                         continuation: eol)
    }

    // Searches backwards from the end of the block for every match of `needle`.
    private func backwardsMatches(for needle: String,
                                  in block: LineBlock,
                                  mode: iTermFindMode = .smartCaseSensitivity) -> [ResultRange] {
        return matches(for: needle,
                       in: block,
                       options: FindOptions(rawValue: FindOptions.optBackwards.rawValue | FindOptions.multipleResults.rawValue),
                       offset: -1,
                       mode: mode)
    }

    // Searches forwards from the start of the block for every match of `needle`.
    private func forwardMatches(for needle: String,
                                in block: LineBlock,
                                mode: iTermFindMode = .smartCaseSensitivity) -> [ResultRange] {
        return matches(for: needle,
                       in: block,
                       options: .multipleResults,
                       offset: 0,
                       mode: mode)
    }

    private func matches(for needle: String,
                         in block: LineBlock,
                         options: FindOptions,
                         offset: Int32,
                         mode: iTermFindMode) -> [ResultRange] {
        let results = NSMutableArray()
        var includesPartialLastLine = ObjCBool(false)
        block.findSubstring(needle,
                            options: options,
                            mode: mode,
                            atOffset: offset,
                            results: results,
                            multipleResults: true,
                            includesPartialLastLine: &includesPartialLastLine,
                            multiLinePriorState: nil,
                            continuationState: nil,
                            crossBlockResultCount: nil)
        return results.compactMap { $0 as? ResultRange }
    }

    // `end` is inclusive.
    private func range(from start: Int32, to end: Int32) -> ResultRange {
        return ResultRange(position: start, length: end - start + 1)
    }

    private static func zalgoText() throws -> String {
        // tests/zalgo.txt is not bundled with the test host, so resolve it relative
        // to this source file.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ModernTests/
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("tests")
            .appendingPathComponent("zalgo.txt")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Tests

    func testBackwardsSearchFindsMatchesAcrossCombiningMarkHeavyText() throws {
        let block = makeBlock(containing: try Self.zalgoText())

        let actual = backwardsMatches(for: "zal", in: block)

        // Each base letter plus its pile of combining marks occupies one cell, so the
        // second "Zalgo" begins at cell 469.
        let expected = [ range(from: 469, to: 471),
                         range(from: 0, to: 2) ]
        XCTAssertEqual(actual, expected)
    }

    func testBackwardsSearchFindsSingleMatchAtEndOfLine() {
        let block = makeBlock(containing: "abczal")

        let actual = backwardsMatches(for: "zal", in: block)

        XCTAssertEqual(actual, [ range(from: 3, to: 5) ])
    }

    func testBackwardsSearchDoesNotReturnOverlappingMatches() {
        // The legacy test expected the overlapping match at [0...1] as well. Since the
        // core-search rewrite (iTermCoreSearch, October 2025) each backwards match
        // continues searching only in the text before the match's start, so results
        // never overlap, matching the regex path and NSString range enumeration.
        let block = makeBlock(containing: "xxx")

        let actual = backwardsMatches(for: "xx", in: block)

        XCTAssertEqual(actual, [ range(from: 1, to: 2) ])
    }

    // MARK: - Unwritten cells

    func testForwardSearchTreatsSkippedCellAsSpace() {
        let block = makeBlock(cells: "gamma\0delta")

        XCTAssertEqual(forwardMatches(for: "gamma delta", in: block), [ range(from: 0, to: 10) ])
    }

    func testBackwardsSearchTreatsSkippedCellAsSpace() {
        let block = makeBlock(cells: "gamma\0delta")

        XCTAssertEqual(backwardsMatches(for: "gamma delta", in: block), [ range(from: 0, to: 10) ])
    }

    func testRegexSearchTreatsSkippedCellAsWhitespace() {
        let block = makeBlock(cells: "gamma\0delta")

        XCTAssertEqual(forwardMatches(for: "gamma\\sdelta", in: block, mode: .caseSensitiveRegex),
                       [ range(from: 0, to: 10) ])
        XCTAssertEqual(forwardMatches(for: "\\S+", in: block, mode: .caseSensitiveRegex),
                       [ range(from: 0, to: 4), range(from: 6, to: 10) ])
    }

    func testSkippedCellsBeforeFirstWrittenCellAreSpaces() {
        let block = makeBlock(cells: "\0\0delta")

        XCTAssertEqual(forwardMatches(for: "  delta", in: block), [ range(from: 0, to: 6) ])
    }

    func testTrailingUnwrittenCellsAreNotSpaces() {
        let block = makeBlock(cells: "gamma\0\0")

        XCTAssertEqual(forwardMatches(for: "gamma ", in: block), [])
        XCTAssertEqual(forwardMatches(for: "gamma", in: block), [ range(from: 0, to: 4) ])
    }
}
