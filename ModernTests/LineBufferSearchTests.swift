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
            var eol = screen_char_t()
            eol.code = unichar(EOL_HARD)
            block.appendLine(umbp.baseAddress!,
                             length: length,
                             partial: false,
                             width: 80,
                             metadata: iTermImmutableMetadataDefault(),
                             continuation: eol)
        }
        return block
    }

    // Searches backwards from the end of the block for every match of `needle`.
    private func backwardsMatches(for needle: String, in block: LineBlock) -> [ResultRange] {
        let results = NSMutableArray()
        var includesPartialLastLine = ObjCBool(false)
        let options = FindOptions(rawValue: FindOptions.optBackwards.rawValue | FindOptions.multipleResults.rawValue)
        block.findSubstring(needle,
                            options: options,
                            mode: .smartCaseSensitivity,
                            atOffset: -1,
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
}
