//
//  LineBlockTests.swift
//  iTerm2
//
//  Created by George Nachman on 4/30/25.
//

import XCTest
@testable import iTerm2SharedARC

class LineBlockTests: XCTestCase {

    private func makeLineString(_ string: String,
                                eol: Int32 = EOL_HARD,
                                lineStringMetadata: iTermLineStringMetadata? = nil,
                                bidi: BidiDisplayInfoObjc? = nil,
                                externalAttribute: iTermExternalAttribute? = nil) -> iTermLineString {
        let content = { () -> any iTermString in
            if let data = string.data(using: .ascii) {
                return iTermASCIIString(data: data, style: screen_char_t(), ea: externalAttribute)
            } else {
                var buffer = Array<screen_char_t>(repeating: screen_char_t(), count: string.utf16.count * 3)
                return buffer.withUnsafeMutableBufferPointer { umbp in
                    var len = Int32(umbp.count)
                    StringToScreenChars(string, umbp.baseAddress!, screen_char_t(), screen_char_t(), &len, false, nil, nil, iTermUnicodeNormalization.none, 9, false, nil)
                    let eaIndex = externalAttribute.map { iTermUniformExternalAttributes.withAttribute($0) }
                    return iTermLegacyStyleString(chars: umbp.baseAddress!, count: Int(len), eaIndex: eaIndex)
                }
            }
        }()
        var continuation = screen_char_t()
        continuation.code = unichar(eol)
        return iTermLineString(content: content,
                               eol: eol,
                               continuation: continuation,
                               metadata: lineStringMetadata ?? iTermLineStringMetadata(timestamp: 0,
                                                                                       rtlFound: false),
                               bidi: bidi,
                               dirty: false)
    }
    // MARK: - Initialization

    func testInitWithRawBufferSizeCreatesEmptyBlock() {
        // Given a raw buffer size and absolute block number
        let size = Int32(1024)
        let block = LineBlock(rawBufferSize: size, absoluteBlockNumber: 0)

        // Then it should have no raw lines
        XCTAssertEqual(block.numRawLines(), 0, "Block should start with zero raw lines")

        // And the firstEntry (index of first valid raw line) should be 0
        XCTAssertEqual(block.firstEntry, 0, "firstEntry should be 0 on a new block")

        // And startOffset (bufferStartOffset) should be 0
        XCTAssertEqual(block.startOffset(), 0, "startOffset should be 0 on a new block")

        // And it should report as empty
        XCTAssertTrue(block.isEmpty(), "isEmpty should be true for a newly initialized block")

        // And rawSpaceUsed should be 0
        XCTAssertEqual(block.rawSpaceUsed(), 0, "rawSpaceUsed should be 0 for an empty block")

        // And numEntries should be 0
        XCTAssertEqual(block.numEntries(), 0, "numEntries should be 0 for an empty block")

        // And hasPartial should be false
        XCTAssertFalse(block.hasPartial(), "hasPartial should be false for a new block")
    }

    // MARK: - Append LineString

    // Append a LineString whose length <= free_space and continuation == EOL_HARD.
    // Expect return true, numRawLines == 1, is_partial == false.
    func testAppendLineStringSucceedsWithinCapacityHardEOL() {
        // Given a block with sufficient capacity (e.g. capacity = 10)
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a lineString shorter than capacity with a hard EOL
        // Implementer note: create a mock or real iTermLineStringReading instance
        // with content length 3, eol = EOL_HARD
        let lineString = makeLineString("abc")
        let width = Int32(5)

        // When appending the lineString
        let result = block.appendLineString(lineString, width: width)

        // Then it should succeed
        XCTAssertTrue(result, "appendLineString should return true when within capacity and using hard EOL")

        // And the block should have exactly one raw line
        XCTAssertEqual(block.numRawLines(), 1, "Block should contain one raw line after append")

        // And rawSpaceUsed should equal the length of the appended content (3)
        XCTAssertEqual(block.rawSpaceUsed(), 3, "rawSpaceUsed should match the appended line length")

        // And isPartial should be false (since EOL was hard)
        XCTAssertFalse(block.hasPartial(), "hasPartial should be false after appending a hard-EOL line")

        // And the first raw line should have length 3
        XCTAssertEqual(block.length(ofRawLine: 0), 3, "Length of the first raw line should equal content length")
    }

    func testAppendLineStringSucceedsWithinCapacitySoftEOL() {
        // Append a LineString partial (soft EOL) and then another to merge.
        // Verify they merge into one raw line and is_partial stays true until hard EOL.
        // Given a block with sufficient capacity (e.g. capacity = 10)
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a lineString shorter than capacity with a soft EOL
        let lineString = makeLineString("abc", eol: EOL_SOFT)
        let width: Int32 = 5

        // When appending the lineString
        let result = block.appendLineString(lineString, width: width)

        // Then it should succeed
        XCTAssertTrue(result, "appendLineString should return true when within capacity and using soft EOL")

        // And the block should have exactly one raw line
        XCTAssertEqual(block.numRawLines(), 1, "Block should contain one raw line after append")

        // And rawSpaceUsed should equal the length of the appended content (3)
        XCTAssertEqual(block.rawSpaceUsed(), 3, "rawSpaceUsed should match the appended line length")

        // And isPartial should be true (since EOL was soft)
        XCTAssertTrue(block.hasPartial(), "hasPartial should be true after appending a soft-EOL line")

        // And the first raw line should have length 3
        XCTAssertEqual(block.length(ofRawLine: 0), 3, "Length of the first raw line should equal content length")
    }


    func testAppendLineStringFailsWhenExceededCapacity() {
        // Create a block with small desiredCapacity and attempt to append a longer line.
        // Expect return false, no metadata change, numRawLines unchanged.

        // Given a block with limited capacity (e.g. capacity = 2)
        let capacity: Int32 = 2
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a lineString longer than capacity
        let lineString = makeLineString("abcd", eol: EOL_HARD)
        let width: Int32 = 5

        // When attempting to append the lineString
        let result = block.appendLineString(lineString, width: width)

        // Then it should fail
        XCTAssertFalse(result, "appendLineString should return false when content exceeds rawBufferSize capacity")

        // And the block should remain empty
        XCTAssertTrue(block.isEmpty(), "Block should still be empty after failed append")
        XCTAssertEqual(block.numRawLines(), 0, "numRawLines should be zero after failed append")
        XCTAssertEqual(block.rawSpaceUsed(), 0, "rawSpaceUsed should remain zero after failed append")
    }

    func testAppendToExistingPartialLinePathUpdatesCachedNumLines() {
        // Append a partial line, then append additional content to trigger the "is_partial & append" branch.
        // Verify cumulative_line_lengths updated, cached_numlines_width reset, generation incremented.

        // Given a block with sufficient capacity
        let capacity: Int32 = 20
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // Append an initial partial line (no hard EOL)
        let firstPart = makeLineString("Hello", eol: EOL_SOFT)
        let initialWidth: Int32 = 4
        XCTAssertTrue(block.appendLineString(firstPart, width: initialWidth), "Initial partial append should succeed")
        XCTAssertTrue(block.hasPartial(), "Block should be partial after first append with soft EOL")

        // Prime the wrapped-lines cache with a different width
        let cacheWidth: Int32 = 3
        _ = block.getNumLines(withWrapWidth: cacheWidth)
        // At this point, cached_numlines_width == cacheWidth

        // Record generation before second append
        let genBefore = block.generation

        // When appending additional content to the existing partial line with a different width
        let secondPart = makeLineString(" World", eol: EOL_SOFT)
        let newWidth: Int32 = 4
        XCTAssertTrue(block.appendLineString(secondPart, width: newWidth), "Appending to existing partial line should succeed")

        // Then cumulative_line_lengths for the first (and only) raw line should equal combined length
        let expectedLength = Int32(firstPart.content.cellCount + secondPart.content.cellCount)
        XCTAssertEqual(block.length(ofRawLine: 0), expectedLength,
                       "Raw line length should increase by the second append length")

        // And hasPartial remains true (still no hard EOL)
        XCTAssertTrue(block.hasPartial(), "Block should remain partial after second soft EOL append")

        // And generation should have incremented
        XCTAssertGreaterThan(block.generation, genBefore,
                             "Generation should increment after mutation")

        // Finally, the wrapped-lines cache width should have been invalidated (reset)
        // Since we cannot access internal cache directly, calling getNumLinesWithWrapWidth(newWidth)
        // should not throw and should return correct count for newWidth
        let wrappedCount = block.getNumLines(withWrapWidth: newWidth)
        XCTAssertGreaterThanOrEqual(wrappedCount, 1,
                                    "Wrapped lines count should be at least 1 after append")
    }
    // MARK: - Wrapping & Double-Width Characters

    func testWrappedLineStringWithoutDWCProducesCorrectSegments() {
        // Append raw lines without double-width chars. Call wrappedLineStringWithWrapWidth:lineNum:
        // for various lineNum to cover full, soft wrap, hard wrap cases.
    }

    func testWrappedLineStringWithDWCSoftAndHardEOL() {
        // Insert a known double-width char (e.g. Emoji + DWC_RIGHT). Set mayHaveDoubleWidthCharacter = true.
        // Verify that wrapping around DWC yields EOL_DWC when split across boundary, else EOL_SOFT/EOL_HARD.
        // Given a block with capacity to hold one raw line of length 5
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a single raw line "ABCDE" with a hard EOL
        let raw = "ABCDE"
        let lineString = makeLineString(raw, eol: EOL_HARD)
        let wrapWidth: Int32 = 3
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending 'ABCDE' should succeed")

        // When we ask for the number of wrapped lines at width=3
        let wrappedCount = block.getNumLines(withWrapWidth: wrapWidth)
        // Then it should split into 2 wrapped lines: "ABC" and "DE"
        XCTAssertEqual(wrappedCount, 2, "Expected 2 wrapped lines for raw length 5 at width 3")

        // And the first wrapped segment (index 0) should be "ABC" with a soft wrap continuation
        var lineNum = Int32(0)
        guard let firstSegment = block.wrappedLineString(withWrapWidth: wrapWidth, lineNum: &lineNum)?.screenCharArray(bidi: nil) else {
            XCTFail("wrappedLineAtIndex(0) returned nil")
            return
        }
        XCTAssertEqual(firstSegment.stringValue, "ABC",
                       "First wrapped segment should contain the first 3 characters")
        XCTAssertEqual(firstSegment.continuation.code, unichar(EOL_SOFT),
                       "Continuation code for a soft wrap should be EOL_SOFT")

        // And the second (final) wrapped segment (index 1) should be "DE" with a hard-EOL continuation
        lineNum = 1
        guard let secondSegment = block.wrappedLineString(withWrapWidth: wrapWidth, lineNum: &lineNum)?.screenCharArray(bidi: nil) else {
            XCTFail("wrappedLineAtIndex(1) returned nil")
            return
        }
        XCTAssertEqual(secondSegment.stringValue, "DE",
                       "Second wrapped segment should contain the remaining characters")
        XCTAssertEqual(secondSegment.continuation.code, unichar(EOL_HARD),
                       "Continuation code for the final segment should be the raw line’s hard EOL")
    }

    // MARK: - Line Count Caching

    func testGetNumLinesWithWrapWidthCachesResult() {
        // Call getNumLinesWithWrapWidth: twice for same width and verify cached_numlines_width,width and cached_numlines used.

        // Given a block with content that wraps across multiple lines at a specific width
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)
        let lineString = makeLineString("ABCDEFG", eol: EOL_HARD)
        let wrapWidth: Int32 = 3
        // Precondition: appending "ABCDEFG" should succeed
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending 'ABCDEFG' should succeed")

        // When calling getNumLines(withWrapWidth:) the first time
        let firstCount = block.getNumLines(withWrapWidth: wrapWidth)

        // Then it should return the correct number of wrapped lines (3 for lengths [3,3,1])
        XCTAssertEqual(firstCount, 3,
                       "Expected 3 wrapped lines for raw length 7 at width 3")

        // And calling it should not mutate the block, so generation remains unchanged
        let generationBefore = block.generation

        // When calling getNumLines(withWrapWidth:) a second time with the same width
        let secondCount = block.getNumLines(withWrapWidth: wrapWidth)

        // Then the returned count should be cached and equal to the first result
        XCTAssertEqual(secondCount, firstCount,
                       "Subsequent calls with the same width should return the cached line count")

        // And the block’s generation should not have changed (no hidden mutations)
        XCTAssertEqual(block.generation, generationBefore,
                       "getNumLines(withWrapWidth:) should not mutate the block or bump its generation")
    }

    func testTotallyUncachedNumLinesBypassesCache() {
        // Call totallyUncachedNumLinesWithWrapWidth: to force recompute even if width matches cached.

        // Given a block with content that wraps across multiple lines at a specific width
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a single raw line "ABCDEFG" with a hard EOL
        let lineString = makeLineString("ABCDEFG", eol: EOL_HARD)
        let wrapWidth: Int32 = 3
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending 'ABCDEFG' should succeed")

        // When calling getNumLines(withWrapWidth:) the first time to prime the cache
        let cachedCount = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(cachedCount, 3,
                       "Expected 3 wrapped lines for raw length 7 at width 3")

        // Record the generation so we can ensure no mutation happens
        let generationBefore = block.generation

        // When calling the uncached variant
        let uncachedCount = block.totallyUncachedNumLines(withWrapWidth: wrapWidth)

        // Then it should recompute and return the same correct count
        XCTAssertEqual(uncachedCount, cachedCount,
                       "totallyUncachedNumLines(withWrapWidth:) should match getNumLines(withWrapWidth:)")

        // And it should not mutate the block (generation remains unchanged)
        XCTAssertEqual(block.generation, generationBefore,
                       "totallyUncachedNumLines should not bump the mutation generation")
    }

    func testHasCachedNumLinesForWidth() {
        // After getNumLinesWithWrapWidth: assert hasCachedNumLinesForWidth returns true; for other width false.

        // Given a block with capacity sufficient for one raw line
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a raw line "ABCDEFG" that will wrap at width 3 into 3 segments
        let lineString = makeLineString("ABCDEFG", eol: EOL_HARD)
        let wrapWidth: Int32 = 3
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending 'ABCDEFG' should succeed")

        // PRE: no cache should exist for any width yet
        XCTAssertFalse(block.hasCachedNumLines(forWidth: wrapWidth),
                       "Before calling getNumLines(withWrapWidth:), cache flag should be false for that width")
        XCTAssertFalse(block.hasCachedNumLines(forWidth: wrapWidth + 1),
                       "Cache flag should also be false for other widths")

        // When priming the cache by fetching wrapped‐line count
        let count = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(count, 3, "Expected 3 wrapped lines for 'ABCDEFG' at width 3")

        // Then the cache flag flips on for that exact width…
        XCTAssertTrue(block.hasCachedNumLines(forWidth: wrapWidth),
                      "After calling getNumLines(withWrapWidth:), cache flag should be true for that width")

        // …but remains off for any other width
        XCTAssertFalse(block.hasCachedNumLines(forWidth: wrapWidth + 2),
                       "Cache flag should remain false for a different width")
    }
    // MARK: - Pop & Remove Last Lines

    func testPopLastLineUpToWidthSplitsLongRawLine() {
        // Append a raw line longer than width. Pop up to width, ensure correct substring is returned,
        // is_partial toggles, cumulative lengths shrink, metadata updated.

        // Given a block with capacity to hold the full raw line
        let capacity: Int32 = 12
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a single raw line "ABCDEFGHIJ" (10 chars) with a hard EOL
        let original = "ABCDEFGHIJ"
        let originalLine = makeLineString(original, eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(originalLine, width: 10),
                      "Precondition: appending full raw line should succeed")
        XCTAssertEqual(block.numRawLines(), 1,
                       "Should have exactly one raw line before popping")
        XCTAssertEqual(block.rawSpaceUsed(), Int32(original.count),
                       "rawSpaceUsed should equal the full length before popping")
        XCTAssertFalse(block.hasPartial(),
                       "hasPartial should be false on a hard-EOL raw line")

        // When we pop the last wrapped line at width = 4 ("IJ")
        let popWidth: Int32 = 4
        guard let popped = block.popLastLineUp(toWidth: popWidth, forceSoftEOL: false) else {
            XCTFail("popLastLineUpToWidth should not return nil")
            return
        }

        // Then the popped segment should be the final wrapped piece ("IJ")
        XCTAssertEqual(popped.content.cellCount, 2,
                       "Popped cellCount should equal the length of the last wrapped segment (2)")
        let poppedArray = popped.content.screenCharArray
        XCTAssertEqual(poppedArray.stringValue, "IJ",
                       "Popped string should be the last 2 characters")

        // The line was appended with a hard EOL so we should get that back.
        XCTAssertEqual(popped.eol, EOL_HARD,
                       "Continuation code for a popped wrapped line should be EOL_HARD")

        // And the block should still have exactly one raw line (the head "ABCDEFGH")
        XCTAssertEqual(block.numRawLines(), 1,
                       "After popping, there should still be one raw line (the remainder)")

        // And rawSpaceUsed should now be original.count - 2
        let expectedRemaining = Int32(original.count - 2)
        XCTAssertEqual(block.rawSpaceUsed(), expectedRemaining,
                       "rawSpaceUsed should shrink by the popped segment length")

        // And the remaining raw line length should equal the head length (8)
        XCTAssertEqual(block.length(ofRawLine: 0), expectedRemaining,
                       "Remaining raw line should have length \(expectedRemaining)")

        // And hasPartial remains false (we didn’t change the original raw EOL)
        XCTAssertTrue(block.hasPartial(),
                      "hasPartial should remain false after splitting a hard-EOL line")
    }

    func testPopLastLineUpToWidthReturnsWholeLineWhenShort() {
        // Append a raw line shorter than or equal to width. Pop and ensure entire raw line returned,
        // block empties or resets correctly.

        // Given a block with capacity at least as large as the content
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a single raw line "Hello" (5 chars) with a hard EOL
        let original = "Hello"
        let originalLine = makeLineString(original, eol: EOL_HARD)
        let width: Int32 = 10
        XCTAssertTrue(block.appendLineString(originalLine, width: width),
                      "Precondition: appending 'Hello' should succeed")

        // Precondition sanity: one raw line, full space used, no partial flag
        XCTAssertEqual(block.numRawLines(), 1, "Should have exactly one raw line before popping")
        XCTAssertEqual(block.rawSpaceUsed(), Int32(original.count),
                       "rawSpaceUsed should equal the content length before popping")
        XCTAssertFalse(block.hasPartial(), "hasPartial should be false on a hard-EOL raw line")

        // When we pop the last line with a width that fully contains it
        guard let popped = block.popLastLineUp(toWidth: width, forceSoftEOL: false) else {
            XCTFail("popLastLineUpToWidth should not return nil for a short line")
            return
        }

        // Then the popped LineString should contain the entire raw line
        XCTAssertEqual(popped.content.cellCount, original.count,
                       "Popped cellCount should equal the full raw line length")
        let poppedArray = popped.content.screenCharArray
        XCTAssertEqual(poppedArray.stringValue, original,
                       "Popped content should match the original string")
        XCTAssertEqual(popped.eol, EOL_HARD,
                       "EOL of the popped LineString should match the raw line’s hard EOL")

        // And the block should now be empty
        XCTAssertEqual(block.numRawLines(), 0,
                       "After popping the entire line, numRawLines should be zero")
        XCTAssertTrue(block.isEmpty(),
                      "Block should report empty after removing its only raw line")
        XCTAssertEqual(block.rawSpaceUsed(), 0,
                       "rawSpaceUsed should be zero after popping the line")

        // Invariants: bufferStartOffset, firstEntry, and numEntries reset to zero
        XCTAssertEqual(block.startOffset(), 0, "startOffset should reset to 0 on empty block")
        XCTAssertEqual(block.firstEntry, 0, "firstEntry should reset to 0 on empty block")
        XCTAssertEqual(block.numEntries(), 0, "numEntries should be 0 on empty block")

        // And hasPartial remains false
        XCTAssertFalse(block.hasPartial(), "hasPartial should remain false after popping a hard-EOL line")
    }

    func testRemoveLastWrappedLinesWithinSingleBlock() {
        // Append multiple raw lines, wrapped count > N. Call removeLastWrappedLines:N < total.
        // Verify only that many wrapped lines removed and raw lines remain.

        // Given a block with capacity to hold one raw line that will wrap into multiple segments
        let capacity: Int32 = 20
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a single raw line "ABCDEFGHIJ" (10 chars) with a hard EOL
        let raw = "ABCDEFGHIJ"
        let originalLine = makeLineString(raw, eol: EOL_HARD)
        let wrapWidth: Int32 = 3
        XCTAssertTrue(block.appendLineString(originalLine, width: wrapWidth),
                      "Precondition: appending 'ABCDEFGHIJ' should succeed")

        // Precondition: it wraps into 4 segments of lengths [3,3,3,1]
        let originalWrapped = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(originalWrapped, 4,
                       "Expected 4 wrapped lines for raw length 10 at width 3")

        // And the raw buffer remains a single raw line of length 10
        let originalRawLines = block.numRawLines()
        XCTAssertEqual(originalRawLines, 1, "Expected one raw line before removing wrapped lines")
        let originalRawSpace = block.rawSpaceUsed()
        XCTAssertEqual(originalRawSpace, Int32(raw.count),
                       "Expected rawSpaceUsed to equal the full raw length before removal")

        // When removing 2 wrapped lines (N < total wrapped lines) within the same block
        let linesToRemove: Int32 = 2
        block.removeLastWrappedLines(linesToRemove, width: wrapWidth)
        let cellsRemoved = 4

        // Then the number of wrapped lines should drop by N
        let newWrapped = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(newWrapped, originalWrapped - linesToRemove,
                       "Wrapped line count should decrease by the number removed")

        // And the raw buffer should remain unchanged (still one raw line of length 10)
        XCTAssertEqual(block.numRawLines(), originalRawLines,
                       "numRawLines should remain unchanged after removing wrapped lines")
        XCTAssertEqual(block.rawSpaceUsed(), originalRawSpace - Int32(cellsRemoved),
                       "rawSpaceUsed should go down")
        XCTAssertEqual(block.length(ofRawLine: 0), Int32(raw.count - cellsRemoved),
                       "Length of the raw line should go down")

        // Block becomes partial since we cut off the end of a line
        XCTAssertTrue(block.hasPartial(),
                      "hasPartial should become true when truncating the last line")
    }
    func testRemoveLastWrappedLinesRemovesEntireBlockWhenExactCount() {
        // Call removeLastWrappedLines:equal to block getNumLinesWithWrapWidth. Expect block.isEmpty.

        // Given a block containing a single raw line that wraps into multiple segments
        let capacity: Int32 = 20
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And that raw line is "ABCDEFGHIJ" (10 chars) with a hard EOL
        let raw = "ABCDEFGHIJ"
        let lineString = makeLineString(raw, eol: EOL_HARD)
        let wrapWidth: Int32 = 3
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending 'ABCDEFGHIJ' should succeed")

        // Precondition: it should wrap into 4 segments of lengths [3,3,3,1]
        let initialWrapped = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(initialWrapped, 4,
                       "Expected 4 wrapped lines for raw length 10 at width 3")

        // When we remove exactly that many wrapped lines
        block.removeLastWrappedLines(initialWrapped, width: wrapWidth)

        // Then the block should be entirely emptied
        XCTAssertTrue(block.isEmpty(), "Block should report empty when all wrapped lines are removed")
        XCTAssertEqual(block.numRawLines(), 0, "numRawLines should be zero after removing all lines")
        XCTAssertEqual(block.rawSpaceUsed(), 0, "rawSpaceUsed should be zero when the block is empty")
        XCTAssertFalse(block.hasPartial(), "hasPartial should be false on an empty block")

        // And all internal indices/counters should reset
        XCTAssertEqual(block.numEntries(), 0, "numEntries should reset to 0 on empty block")
        XCTAssertEqual(block.firstEntry, 0, "firstEntry should reset to 0 on empty block")
        XCTAssertEqual(block.startOffset(), 0, "startOffset should reset to 0 on empty block")
    }
    // MARK: - Raw Line Removal

    func testRemoveLastRawLineWithMultipleEntries() {
        // Append two raw lines. removeLastRawLine should drop last raw line only,
        // leaving one entry, metadata and bufferStartOffset unchanged.

        // Given a block with capacity to hold multiple raw lines
        let capacity: Int32 = 20
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)
        let width: Int32 = 10

        // And two hard-EOL raw lines appended in sequence
        let firstLineString = makeLineString("FirstLine", eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(firstLineString, width: width),
                      "Precondition: appending the first hard-EOL line should succeed")
        let secondLineString = makeLineString("SecondLine", eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(secondLineString, width: width),
                      "Precondition: appending the second hard-EOL line should succeed")

        // Sanity check: the block now contains two raw lines
        XCTAssertEqual(block.numRawLines(), 2, "Block should have two raw lines before removal")
        XCTAssertEqual(block.numEntries(), 2, "numEntries should equal the number of raw lines before removal")
        XCTAssertEqual(block.startOffset(), 0, "startOffset should remain 0 before removal")
        XCTAssertEqual(block.firstEntry, 0, "firstEntry should remain 0 before removal")
        let expectedTotal = Int32(firstLineString.content.cellCount + secondLineString.content.cellCount)
        XCTAssertEqual(block.rawSpaceUsed(), expectedTotal,
                       "rawSpaceUsed should equal the sum of both lines' lengths before removal")

        // When removing the last raw line
        block.removeLastRawLine()

        // Then exactly one raw line should remain
        XCTAssertEqual(block.numRawLines(), 1,
                       "Block should contain one raw line after removing the last raw line")
        XCTAssertEqual(block.numEntries(), 1,
                       "numEntries should update to reflect one remaining entry")
        XCTAssertEqual(block.startOffset(), 0,
                       "startOffset should remain unchanged after removal")
        XCTAssertEqual(block.firstEntry, 0,
                       "firstEntry should remain unchanged after removal")
        // And the remaining space used should equal only the first line's length
        let firstLen = Int32(firstLineString.content.cellCount)
        XCTAssertEqual(block.rawSpaceUsed(), firstLen,
                       "rawSpaceUsed should equal the first line's length after removal")
        // And the length of the remaining raw line should be correct
        XCTAssertEqual(block.length(ofRawLine: 0), firstLen,
                       "Length of the remaining raw line should match the first line's length")
        // And partial/EOL state of the block should reflect the hard EOL of the remaining line
        XCTAssertFalse(block.hasPartial(),
                       "hasPartial should be false after removing a hard-EOL raw line")
        XCTAssertFalse(block.isEmpty(),
                       "isEmpty should be false when there is still one raw line left")
    }

    func testRemoveLastRawLineOnSingleEntryResetsBlock() {
        // Append one raw line. removeLastRawLine should clear block, reset bufferStartOffset, firstEntry.

        // Given a block with capacity to hold one raw line
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)
        let width: Int32 = 8

        // And a single hard-EOL raw line appended
        let lineString = makeLineString("Test", eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(lineString, width: width),
                      "Precondition: appending a single hard-EOL line should succeed")
        XCTAssertEqual(block.numRawLines(), 1, "Should have exactly one raw line before removal")
        XCTAssertFalse(block.isEmpty(), "Block should not be empty after append")
        XCTAssertEqual(block.rawSpaceUsed(), Int32(lineString.content.cellCount),
                       "rawSpaceUsed should equal the appended line length before removal")

        // When removing the last raw line
        block.removeLastRawLine()

        // Then the block should be entirely emptied
        XCTAssertTrue(block.isEmpty(), "Block should report empty after removing its only raw line")
        XCTAssertEqual(block.numRawLines(), 0, "numRawLines should be zero after removal")
        XCTAssertEqual(block.rawSpaceUsed(), 0, "rawSpaceUsed should reset to zero after removal")

        // And all internal indices/counters should reset
        XCTAssertEqual(block.startOffset(), 0, "startOffset should reset to 0 on empty block")
        XCTAssertEqual(block.firstEntry, 0, "firstEntry should reset to 0 on empty block")
        XCTAssertEqual(block.numEntries(), 0, "numEntries should be 0 on empty block")

        // And the partial flag should be cleared
        XCTAssertFalse(block.hasPartial(), "hasPartial should be false after removing the only raw line")
    }

    // MARK: - Line Lengths

    func testLengthOfLastLine() {
        // Append multiple raw lines. Verify lengthOfLastLine returns correct length of last raw line.

        // Given a block with capacity to hold multiple raw lines
        let capacity: Int32 = 20
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)
        let width: Int32 = 15

        // And two hard-EOL raw lines appended in sequence
        let firstLine = makeLineString("Hello", eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(firstLine, width: width),
                      "Precondition: appending the first hard-EOL line should succeed")
        // After first append, lengthOfLastLine should equal the length of "Hello"
        XCTAssertEqual(block.lengthOfLastLine(), Int32(firstLine.content.cellCount),
                       "lengthOfLastLine() should match the first raw line's length")

        let secondLine = makeLineString("WorldWide", eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(secondLine, width: width),
                      "Precondition: appending the second hard-EOL line should succeed")
        // After second append, lengthOfLastLine should update to the length of "WorldWide"
        XCTAssertEqual(block.lengthOfLastLine(), Int32(secondLine.content.cellCount),
                       "lengthOfLastLine() should update to the second raw line's length")

        // And numRawLines() should be 2
        XCTAssertEqual(block.numRawLines(), 2,
                       "Block should contain two raw lines after two successful appends")
    }
    func testLengthOfLastLineWrappedToWidthCalculatesCorrectSegments() {
        // Append raw line that wraps to multiple segments. lengthOfLastLineWrappedToWidth should return the wrapped segment length.

        // Append a raw line that wraps into multiple segments and verify the last segment’s length.
        //
        // Given a block with enough capacity for a 10‐character raw line
        let capacity: Int32 = 20
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a hard-EOL raw line "ABCDEFGHIJ" (10 chars)
        let raw = "ABCDEFGHIJ"
        let lineString = makeLineString(raw, eol: EOL_HARD)

        // Precondition: appending should succeed
        let wrapWidth1: Int32 = 4
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth1),
                      "Should be able to append a 10-char line into a fresh block")

        // When wrapping to width 4, the segments are [4,4,2], so the last segment length is 2
        XCTAssertEqual(block.lengthOfLastLineWrapped(toWidth: wrapWidth1),
                       3,
                       "Expected last wrapped segment length of 3 for raw length 10 at width 4")

        // And if we choose a width that divides evenly, e.g. 5 → segments [5,5], last segment length is 5
        let wrapWidth2: Int32 = 5
        XCTAssertEqual(block.lengthOfLastLineWrapped(toWidth: wrapWidth2),
                       2,
                       "Expected last wrapped segment length of 2 for raw length 10 at width 5")

        // Also verify a width larger than the line gives the full length back
        let wrapWidth3: Int32 = 20
        XCTAssertEqual(block.lengthOfLastLineWrapped(toWidth: wrapWidth3),
                       1,
                       "When wrap width exceeds line length, lengthOfLastLineWrappedToWidth should return the full raw line length")
    }

    // MARK: - dropLines

    func testDropLinesLessThanSpansAdjustsFirstEntryAndBufferStartOffset() {
        // Append lines to exceed width, drop a wrapped count less than spans of first raw line.
        // Verify bufferStartOffset and firstEntry increment, charsDropped correct.

        // Given a block whose single raw line wraps into multiple segments
        let capacity: Int32 = 20
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a hard‐EOL raw line "ABCDEFGHIJ" (10 chars)
        let raw = "ABCDEFGHIJ"
        let lineString = makeLineString(raw, eol: EOL_HARD)
        let wrapWidth: Int32 = 3
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending 'ABCDEFGHIJ' should succeed")

        // Precondition: it should wrap into 4 segments of lengths [3,3,3,1]
        let totalSpans = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(totalSpans, 4,
                       "Expected 4 wrapped lines for raw length 10 at width 3")

        // When dropping fewer wrapped lines than spans (e.g. 2 of the 4 segments)
        var charsDropped: Int32 = 0
        // ABC
        // DEF
        // GHI
        // J
        let wrappedLinesDropped = block.dropLines(2, withWidth: wrapWidth, chars: &charsDropped)
        // GHI
        // J

        // Then no entire raw lines should be removed
        XCTAssertEqual(wrappedLinesDropped, 2,
                       "dropLines should return 2 lines removed")

        // And the number of cells dropped should equal dropCount * wrapWidth (2 * 3 = 6)
        XCTAssertEqual(charsDropped, 6,
                       "charsDropped should equal the number of wrapped cells removed")

        // And bufferStartOffset should advance by the same amount
        XCTAssertEqual(block.startOffset(), charsDropped,
                       "startOffset should advance by the number of dropped cells")

        // And firstEntry should remain at 0 (we are still within the first raw line)
        XCTAssertEqual(block.firstEntry, 0,
                       "firstEntry should remain 0 when dropping only wrapped segments of the first raw line")

        // Dropping does not recover space
        XCTAssertEqual(block.rawSpaceUsed(), Int32(raw.count),
                       "rawSpaceUsed should not decrease")

        // And the length of the remaining raw line should now be 4
        XCTAssertEqual(block.length(ofRawLine: 0), Int32(raw.count) - charsDropped,
                       "length(ofRawLine: 0) should reflect the truncated raw line")
    }

    func testDropLinesEqualToSpansEmptiesBlockEntry() {
        // Drop lines equal to full raw-line spans, so the first (and only) raw line is removed,
        // leaving an empty block.

        // Given a block whose single raw line wraps into multiple segments
        let capacity: Int32 = 20
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a hard-EOL raw line "ABCDEFGHIJ" (10 chars) appended
        let raw = "ABCDEFGHIJ"
        let lineString = makeLineString(raw, eol: EOL_HARD)
        let wrapWidth: Int32 = 3
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending '\(raw)' should succeed")

        // Precondition: it should wrap into 4 segments of lengths [3,3,3,1]
        let totalSpans = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(totalSpans, 4,
                       "Expected 4 wrapped lines for raw length \(raw.count) at width \(wrapWidth)")

        // When dropping exactly that many wrapped lines
        var charsDropped: Int32 = 0
        let dropped = block.dropLines(totalSpans, withWidth: wrapWidth, chars: &charsDropped)

        // Then dropLines should return the number of wrapped lines removed
        XCTAssertEqual(dropped, totalSpans,
                       "dropLines should return the total number of wrapped lines removed")

        // charsDropped should equal the full raw line length (10)
        XCTAssertEqual(charsDropped, Int32(raw.count),
                       "charsDropped should equal the total raw line length")

        // The block should now be empty
        XCTAssertTrue(block.isEmpty(), "Block should report empty after dropping all wrapped lines")
        XCTAssertEqual(block.numRawLines(), 0,
                       "numRawLines should be zero after dropping the entire raw line")
        XCTAssertEqual(block.rawSpaceUsed(), 0,
                       "rawSpaceUsed should be zero when the block is empty")
        XCTAssertFalse(block.hasPartial(),
                       "hasPartial should be false for an empty block")

        // Internal indices/counters should reset
        XCTAssertEqual(block.startOffset(), 0,
                       "startOffset should reset to 0 on an emptied block")
        XCTAssertEqual(block.firstEntry, 0,
                       "firstEntry should reset to 0 on an emptied block")
        XCTAssertEqual(block.numEntries(), 0,
                       "numEntries should be zero when the block contains no entries")
    }

    func testDropLinesMoreThanAvailableDropsEntireBuffer() {
        // dropLines with n > total wrapped lines should remove everything and reset the block.

        // Given a block whose single raw line wraps into multiple segments
        let capacity: Int32 = 20
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a hard-EOL raw line "ABCDEFGHIJ" (10 chars) appended
        let raw = "ABCDEFGHIJ"
        let lineString = makeLineString(raw, eol: EOL_HARD)
        let wrapWidth: Int32 = 3
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending '\(raw)' should succeed")

        // Precondition: it should wrap into 4 segments of lengths [3,3,3,1]
        let totalSpans = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(totalSpans, 4,
                       "Expected 4 wrapped lines for raw length \(raw.count) at width \(wrapWidth)")

        // When dropping more wrapped lines than are present (e.g. totalSpans + 2)
        var charsDropped: Int32 = 0
        let dropped = block.dropLines(totalSpans + 2, withWidth: wrapWidth, chars: &charsDropped)

        // Then dropLines should report removing only the available lines
        XCTAssertEqual(dropped, totalSpans,
                       "dropLines should return the actual number of wrapped lines removed when asked for more than available")

        // And charsDropped should equal the full raw line length (10)
        XCTAssertEqual(charsDropped, Int32(raw.count),
                       "charsDropped should equal the total raw line length when everything is dropped")

        // And the block should now be empty
        XCTAssertTrue(block.isEmpty(), "Block should report empty after dropping all wrapped lines")
        XCTAssertEqual(block.numRawLines(), 0,
                       "numRawLines should be zero after dropping the entire raw line")
        XCTAssertEqual(block.rawSpaceUsed(), 0,
                       "rawSpaceUsed should be zero when the block is empty")
        XCTAssertFalse(block.hasPartial(),
                       "hasPartial should be false for an empty block")

        // Internal indices/counters should reset
        XCTAssertEqual(block.startOffset(), 0,
                       "startOffset should reset to 0 on an emptied block")
        XCTAssertEqual(block.firstEntry, 0,
                       "firstEntry should reset to 0 on an emptied block")
        XCTAssertEqual(block.numEntries(), 0,
                       "numEntries should be zero when the block contains no entries")
    }
    // MARK: - Empty Checks

    func testIsEmptyAndAllLinesAreEmptyWhenNoEntries() {
        // After init, isEmpty==true, allLinesAreEmpty==true.

        // Given a newly initialized LineBlock with no entries
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 0)

        // Then it should report as empty
        XCTAssertTrue(block.isEmpty(), "isEmpty should be true for a newly initialized block with no entries")

        // And allLinesAreEmpty should also be true when there are no raw lines
        XCTAssertTrue(block.allLinesAreEmpty(), "allLinesAreEmpty should be true when the block contains zero raw lines")
    }

    func testAllLinesAreEmptyWhenEntriesZeroLength() {
        // Append only zero-length lines. isEmpty should be false (entries exist),
        // but allLinesAreEmpty should be true (no character content).

        // Given a block initialized with some capacity
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 0)
        let width: Int32 = 5

        // Precondition: block is empty before any appends
        XCTAssertTrue(block.isEmpty(), "Block should start empty before any appends")
        XCTAssertTrue(block.allLinesAreEmpty(), "allLinesAreEmpty should be true when there are no entries")

        // When we append several zero-length lines
        let numberOfLines = 3
        for _ in 1...numberOfLines {
            let emptyLine = makeLineString("", eol: EOL_HARD)
            XCTAssertTrue(block.appendLineString(emptyLine, width: width),
                          "Appending a zero-length line should succeed")
        }

        // Then the block should no longer be considered empty (entries exist)
        XCTAssertFalse(block.isEmpty(), "isEmpty should be false once zero-length entries have been appended")

        // And the number of raw lines should equal the number of appends
        XCTAssertEqual(block.numRawLines(), Int32(numberOfLines),
                       "numRawLines should match the number of zero-length lines appended")

        // And rawSpaceUsed should remain zero, since no characters were added
        XCTAssertEqual(block.rawSpaceUsed(), 0,
                       "rawSpaceUsed should be zero when all entries are zero-length")

        // Finally, allLinesAreEmpty should return true, because every entry is empty
        XCTAssertTrue(block.allLinesAreEmpty(),
                      "allLinesAreEmpty should be true when every raw line has zero length")
    }

    // MARK: - Raw Line Retrieval

    func testNumRawLinesStartOffsetAndOffsets() {
        // Append several raw lines. Verify numRawLines, startOffset, offsetOfRawLine, and rawLine content.

        // Given a LineBlock with ample capacity
        let capacity: Int32 = 100
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)
        let width: Int32 = 80

        // And three hard‐EOL lines appended in sequence
        let firstText = "Apple"
        let secondText = "Banana"
        let thirdText = "Cherry"
        XCTAssertTrue(block.appendLineString(makeLineString(firstText,  eol: EOL_HARD), width: width),
                      "Should be able to append first hard‐EOL line")
        XCTAssertTrue(block.appendLineString(makeLineString(secondText, eol: EOL_HARD), width: width),
                      "Should be able to append second hard‐EOL line")
        XCTAssertTrue(block.appendLineString(makeLineString(thirdText,  eol: EOL_HARD), width: width),
                      "Should be able to append third hard‐EOL line")

        // Then numRawLines should report 3
        XCTAssertEqual(block.numRawLines(), 3, "Block should contain three raw lines")

        // And since we haven't dropped anything, startOffset should be 0
        XCTAssertEqual(block.startOffset(), 0, "startOffset should be zero before any drops")

        // Compute expected cumulative offsets
        let expectedOffsets: [Int32] = [
            0,
            Int32(firstText.utf16.count),
            Int32(firstText.utf16.count + secondText.utf16.count)
        ]

        // And offsetOfRawLine should match cumulative lengths
        for i in 0..<3 {
            let off = block.offset(ofRawLine: Int32(i))
            XCTAssertEqual(off, expectedOffsets[Int(i)],
                           "offsetOfRawLine(\(i)) should be \(expectedOffsets[Int(i)])")
        }

        // Finally, rawLine(i) should return the correct ScreenCharArray content
        let raw0 = block.rawLine(0)
        XCTAssertNotNil(raw0)
        XCTAssertEqual(raw0?.screenCharArray(bidi: nil).stringValue, firstText,
                       "rawLine(0) should return the first appended string")
        let raw1 = block.rawLine(1)
        XCTAssertNotNil(raw1)
        XCTAssertEqual(raw1?.screenCharArray(bidi: nil).stringValue, secondText,
                       "rawLine(1) should return the second appended string")
        let raw2 = block.rawLine(2)
        XCTAssertNotNil(raw2)
        XCTAssertEqual(raw2?.screenCharArray(bidi: nil).stringValue, thirdText,
                       "rawLine(2) should return the third appended string")
    }

    // MARK: - Serialization

    func testDictionaryRoundTripPreservesContents() {
        // Append lines, set metadata flags, generate dictionary and new blockWithDictionary:
        // Ensure round-trip equality via isEqual: and rope content.

        // Given a LineBlock with a specific rawBufferSize and absoluteBlockNumber
        let capacity: Int32 = 50
        let originalBlock = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 123)
        let ea = iTermExternalAttribute.init(underlineColor: VT100TerminalColorValue(), url: nil, blockIDList: "Test", controlCode: nil)

        // And some raw lines appended with mixed EOL types
        let line1 = makeLineString("One", eol: EOL_HARD, externalAttribute: ea)
        XCTAssertTrue(originalBlock.appendLineString(line1, width: 10),
                      "Precondition: appending 'One' should succeed")
        let line2 = makeLineString("TwoTwo", eol: EOL_SOFT)
        XCTAssertTrue(originalBlock.appendLineString(line2, width: 10),
                      "Precondition: appending 'TwoTwo' (soft EOL) should succeed")
        let line3 = makeLineString("Three", eol: EOL_HARD)
        XCTAssertTrue(originalBlock.appendLineString(line3, width: 10),
                      "Precondition: appending 'Three' should succeed")

        // When we serialize to a dictionary...
        let dict = originalBlock.dictionary()

        // ...and recreate a new block from that dictionary
        guard let roundTripBlock = LineBlock(dictionary: dict, absoluteBlockNumber: 0) else {
            return XCTFail("block(withDictionary:absoluteBlockNumber:) returned nil")
        }

        // Then the new block should be equal to the original
        XCTAssertTrue(originalBlock.isEqual(roundTripBlock),
                      "Round-tripped block should be equal to the original via isEqual:")

        // And key invariants should match
        XCTAssertEqual(roundTripBlock.numRawLines(), originalBlock.numRawLines(),
                       "numRawLines should be preserved")
        XCTAssertEqual(roundTripBlock.rawSpaceUsed(), originalBlock.rawSpaceUsed(),
                       "rawSpaceUsed should be preserved")
        XCTAssertEqual(roundTripBlock.hasPartial(), originalBlock.hasPartial(),
                       "hasPartial should be preserved")
        XCTAssertEqual(roundTripBlock.firstEntry, originalBlock.firstEntry,
                       "firstEntry should be preserved")
        XCTAssertEqual(roundTripBlock.startOffset(), originalBlock.startOffset(),
                       "startOffset should be preserved")
        XCTAssertEqual(roundTripBlock.numEntries(), originalBlock.numEntries(),
                       "numEntries should be preserved")

        // And each raw line's text content should match
        let count = originalBlock.numRawLines()
        for i in 0..<count {
            let originalScreen = originalBlock.rawLine(i)?.screenCharArray(bidi: nil)
            let roundTripScreen = roundTripBlock.rawLine(i)?.screenCharArray(bidi: nil)
            XCTAssertEqual(roundTripScreen?.stringValue,
                           originalScreen?.stringValue,
                           "Raw line \(i) content should match after round-trip")
            XCTAssertTrue(
                iTermExternalAttributeIndex.externalAttributeIndex(
                    roundTripScreen?.eaIndex,
                    isEqualToIndex: originalScreen?.eaIndex),
                "\((roundTripScreen?.eaIndex).d) != \((originalScreen?.eaIndex).d)")
        }
    }

    // MARK: - Empty Line Counts

    func testNumberOfLeadingEmptyLines() {
        // Append empty/raw lines then content. Verify numberOfLeadingEmptyLines correct.

        // Given a fresh LineBlock and a wrap width
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)
        let width: Int32 = 5

        // When we append two empty (zero‐length) raw lines...
        let emptyLine1 = makeLineString("", eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(emptyLine1, width: width),
                      "Appending the first empty line should succeed")
        let emptyLine2 = makeLineString("", eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(emptyLine2, width: width),
                      "Appending the second empty line should succeed")

        // ...and then append one non‐empty raw line
        let contentLine = makeLineString("abc", eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(contentLine, width: width),
                      "Appending a non‐empty raw line should succeed")

        // Then numberOfLeadingEmptyLines() should count only the two empty raw lines at the front
        let leadingEmpty = block.numberOfLeadingEmptyLines()
        XCTAssertEqual(leadingEmpty, 2,
                       "numberOfLeadingEmptyLines should return 2 for the two initial empty raw lines")

        // And it should not count any empty lines after the first non‐empty line
        // To verify, append another empty line after non‐empty and ensure it isn't counted
        let trailingEmpty = makeLineString("", eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(trailingEmpty, width: width),
                      "Appending an empty line after content should succeed")
        XCTAssertEqual(block.numberOfLeadingEmptyLines(), 2,
                       "Leading empty count should remain 2 even if empty lines follow non‐empty content")
    }

    func testNumberOfTrailingEmptyLines() {
        // Append content then empty/raw lines. Verify numberOfTrailingEmptyLines correct.
        // Given a block with capacity and a wrap width
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)
        let width: Int32 = 5
        // Append a non-empty raw line
        XCTAssertTrue(block.appendLineString(makeLineString("abc", eol: EOL_HARD), width: width),
                      "Appending a non-empty raw line should succeed")

        // Append two empty raw lines
        XCTAssertTrue(block.appendLineString(makeLineString("", eol: EOL_HARD), width: width),
                      "Appending the first empty line should succeed")
        XCTAssertTrue(block.appendLineString(makeLineString("", eol: EOL_HARD), width: width),
                      "Appending the second empty line should succeed")

        // Then the trailing empty count should be 2
        XCTAssertEqual(block.numberOfTrailingEmptyLines(), 2,
                       "numberOfTrailingEmptyLines should return 2 for the two ending empty raw lines")

        // When we append a non-empty line after the empties
        XCTAssertTrue(block.appendLineString(makeLineString("xyz", eol: EOL_HARD), width: width),
                      "Appending a non-empty raw line after empties should succeed")

        // Then the trailing empty count should reset to 0
        XCTAssertEqual(block.numberOfTrailingEmptyLines(), 0,
                       "numberOfTrailingEmptyLines should reset to 0 after appending a non-empty raw line")
    }

    func testContainsAnyNonEmptyLine() {
        // Verify containsAnyNonEmptyLine toggles correctly for empty vs non-empty.

        // Given a new block with no entries
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 0)
        let width: Int32 = 5

        // Initially, with zero entries, there should be no non‐empty lines
        XCTAssertFalse(block.containsAnyNonEmptyLine(),
                       "A freshly initialized block with no entries should report no non-empty lines")

        // When we append several empty lines (zero-length content)
        for _ in 0..<3 {
            let emptyLine = makeLineString("", eol: EOL_HARD)
            XCTAssertTrue(block.appendLineString(emptyLine, width: width),
                          "Appending an empty line should succeed")
        }

        // It still should not report any non-empty lines
        XCTAssertFalse(block.containsAnyNonEmptyLine(),
                       "Block with only empty lines should still report no non-empty lines")

        // When we append one non-empty line
        let nonEmpty = makeLineString("hello", eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(nonEmpty, width: width),
                      "Appending a non-empty line should succeed")

        // Then it must report that it contains at least one non-empty line
        XCTAssertTrue(block.containsAnyNonEmptyLine(),
                      "After appending a non-empty line, containsAnyNonEmptyLine should return true")

        // When we remove that non-empty raw line
        block.removeLastRawLine()

        // Only empty lines remain, so it should revert to reporting no non-empty lines
        XCTAssertFalse(block.containsAnyNonEmptyLine(),
                       "After removing the only non-empty line, containsAnyNonEmptyLine should return false again")
    }

    // MARK: - Copy-on-Write & Generation

    func testCopyDeepProducesIndependentBlock() {
        // Create an original block, append content, deep-copy it, then mutate original and copy
        // to verify they do not affect each other.

        // Given an original LineBlock with some raw lines
        let capacity: Int32 = 20
        let original = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 42)
        let width: Int32 = 10

        // Append some lines
        let hardLine = makeLineString("First", eol: EOL_HARD)
        XCTAssertTrue(original.appendLineString(hardLine, width: width),
                      "Precondition: appending a hard-EOL line should succeed")
        let softLine = makeLineString("Partial", eol: EOL_HARD)
        XCTAssertTrue(original.appendLineString(softLine, width: width),
                      "Precondition: appending a soft-EOL line should succeed")

        // Capture original state
        let originalRawCount = original.numRawLines()
        let originalSpaceUsed = original.rawSpaceUsed()
        let originalPartialState = original.hasPartial()
        let originalGen = original.generation

        // When we deep-copy the block
        let copy = original.copy(withAbsoluteBlockNumber: 0)

        // Then the copy should start with the same content and state
        XCTAssertEqual(copy.numRawLines(), originalRawCount,
                       "Deep copy should preserve the number of raw lines")
        XCTAssertEqual(copy.rawSpaceUsed(), originalSpaceUsed,
                       "Deep copy should preserve rawSpaceUsed")
        XCTAssertEqual(copy.hasPartial(), originalPartialState,
                       "Deep copy should preserve the partial flag")
        XCTAssertEqual(copy.generation, originalGen,
                       "Deep copy’s generation should match original at time of copy")

        // When we mutate the original after copying
        let extraLine = makeLineString("Extra", eol: EOL_HARD)
        XCTAssertTrue(original.appendLineString(extraLine, width: width),
                      "Appending to the original should succeed")
        // The original should reflect the mutation...
        XCTAssertEqual(original.numRawLines(), originalRawCount + 1,
                       "Original raw line count should increment after mutation")
        XCTAssertEqual(original.rawSpaceUsed(), originalSpaceUsed + Int32(extraLine.content.cellCount),
                       "Original rawSpaceUsed should increase after mutation")
        XCTAssertTrue(original.generation > originalGen,
                      "Original generation should advance on mutation")

        // ...but the deep copy must remain unchanged
        XCTAssertEqual(copy.numRawLines(), originalRawCount,
                       "Copy’s raw line count should not change when original is mutated")
        XCTAssertEqual(copy.rawSpaceUsed(), originalSpaceUsed,
                       "Copy’s rawSpaceUsed should not change when original is mutated")
        XCTAssertEqual(copy.hasPartial(), originalPartialState,
                       "Copy’s partial flag should not change when original is mutated")
        XCTAssertEqual(copy.generation, originalGen,
                       "Copy’s generation should not change when original is mutated")

        // Now mutate the copy independently
        let fillerLine = makeLineString("Filler", eol: EOL_HARD)
        XCTAssertTrue(copy.appendLineString(fillerLine, width: width),
                      "Appending to the copy should succeed")
        // And verify that the copy has changed...
        XCTAssertEqual(copy.numRawLines(), originalRawCount + 1,
                       "Copy raw line count should increment after its own mutation")
        XCTAssertEqual(copy.rawSpaceUsed(), originalSpaceUsed + Int32(fillerLine.content.cellCount),
                       "Copy rawSpaceUsed should increase after its own mutation")
        // ...but the original remains as it was post-original-mutation
        XCTAssertEqual(original.numRawLines(), originalRawCount + 1,
                       "Original raw line count should remain unchanged by copy’s mutation")
        XCTAssertEqual(original.rawSpaceUsed(), originalSpaceUsed + Int32(extraLine.content.cellCount),
                       "Original rawSpaceUsed should remain unchanged by copy’s mutation")

        // Finally, remove the last raw line from the copy and verify original is unaffected
        copy.removeLastRawLine()
        XCTAssertEqual(copy.numRawLines(), originalRawCount,
                       "After removing from copy, its raw line count should decrement")
        XCTAssertEqual(original.numRawLines(), originalRawCount + 1,
                       "Original raw line count should stay the same after copy’s removal")
    }
    func testCowCopySetsHasBeenCopiedAndProgenitor() {
        // After cowCopy, both objects hasBeenCopied==true, copy.progenitor==original, original.clients contains copy.

        // Given a fresh LineBlock
        let capacity: Int32 = 16
        let original = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 0)

        // Precondition: hasBeenCopied should start false on a new block
        XCTAssertFalse(original.hasBeenCopied,
                       "A newly initialized block should not yet be marked as having been copied")

        // When we perform a copy-on-write copy
        let copy = original.cowCopy()

        // Then both the original and the copy should now report hasBeenCopied == true
        XCTAssertTrue(original.hasBeenCopied,
                      "After cowCopy, the original must be marked as having been copied")
        XCTAssertTrue(copy.hasBeenCopied,
                      "After cowCopy, the new copy must also be marked as having been copied")

        // And the copy’s progenitor should point back to the original
        XCTAssertTrue(copy.progenitor === original,
                      "The copy’s progenitor should be the original block instance")
    }


    // MARK: - OffsetOfWrappedLine

    func testOffsetOfWrappedLineSimpleMultiplicationPath() {
        // For a simple mono-width buffer with no double-width characters,
        // OffsetOfWrappedLine should return startOffset + n * width.

        // Given a block with enough capacity for one raw line
        let capacity: Int32 = 20
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a single raw line "ABCDEFGHIJ" (10 chars) with a hard EOL
        let raw = "ABCDEFGHIJ"
        let lineString = makeLineString(raw, eol: EOL_HARD)
        let wrapWidth: Int32 = 3
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending a 10-char line should succeed")

        // Precondition: at width=3 it wraps into 4 segments
        let wrappedCount = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(wrappedCount, 4,
                       "Expected 4 wrapped lines for raw length 10 at width 3")

        // The startOffset for the first raw line is:
        let startOffset = block.offset(ofRawLine: 0)

        // When we query OffsetOfWrappedLine for each wrapped segment index n
        for n in Int32(0)..<wrappedCount {
            // Then it should equal startOffset + n * wrapWidth
            let expected = startOffset + n * wrapWidth
            let rawLength = Int32(block.length(ofRawLine: 0))
            let actual = OffsetOfWrappedLine(block,
                                             startOffset,
                                             n,
                                             rawLength,
                                             wrapWidth,
                                             false /* mayHaveDwc */)
            XCTAssertEqual(actual, expected,
                           "OffsetOfWrappedLine for segment \(n) should be \(expected), got \(actual)")
        }

        // And for a width larger than the raw length, there is only one wrapped line at offset = startOffset
        let bigWidth: Int32 = 20
        let bigCount = block.getNumLines(withWrapWidth: bigWidth)
        XCTAssertEqual(bigCount, 1,
                       "At width \(bigWidth) there should be a single wrapped line")
        let bigActual = OffsetOfWrappedLine(block,
                                            startOffset,
                                            0,
                                            Int32(raw.count),
                                            bigWidth,
                                            false)
        XCTAssertEqual(bigActual, startOffset,
                       "OffsetOfWrappedLine for the only segment at large width should be startOffset (\(startOffset))")
    }


    func testOffsetOfWrappedLineWithDWCPath() {
        // With mayHaveDoubleWidthCharacter=true and a DWC that would straddle the boundary,
        // OffsetOfWrappedLine must avoid splitting the double-width character.
        //
        // For raw "AB中DEF", the cells become:
        //   [0]='A', [1]='B',
        //   [2]='中', [3]=DWC_RIGHT,
        //   [4]='D', [5]='E', [6]='F'
        // At wrapWidth=3:
        //   segment0 = cells[0..<2] ("AB")  → offset = startOffset + 0
        //   segment1 = cells[2..<5] ("中<D>")→ offset = startOffset + 2 (not +3!)
        //   segment2 = cells[5..<7] ("EF")  → offset = startOffset + 5

        // Given a block and enable DWC path
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)
        block.mayHaveDoubleWidthCharacter = true

        // And a line containing a double-width character
        let raw = "AB中DEF"
        let lineString = makeLineString(raw, eol: EOL_HARD)
        let wrapWidth: Int32 = 3
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Should successfully append 'AB中DEF'")

        // Precondition: there should be 3 wrapped segments at width=3
        let wrappedCount = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(wrappedCount, 3,
                       "Expected 3 wrapped lines for raw 'AB中DEF' at width 3")

        let startOffset = block.offset(ofRawLine: 0)
        let rawLength = Int32(block.length(ofRawLine: 0))

        // Segment 0: no DWC splitting
        let off0 = OffsetOfWrappedLine(block,
                                       startOffset,
                                       0,
                                       rawLength,
                                       wrapWidth,
                                       true)
        XCTAssertEqual(off0, startOffset,
                       "First segment should start at startOffset")

        // Segment 1: DWC falls at cell 2–3, so it must be moved intact → offset = startOffset + 2
        let off1 = OffsetOfWrappedLine(block,
                                       startOffset,
                                       1,
                                       rawLength,
                                       wrapWidth,
                                       true)
        XCTAssertEqual(off1, startOffset + 2,
                       "Second segment must skip the DWC group and start at cell 2")

        // Segment 2: follows segment1’s 3 cells → offset = startOffset + 2 + 3 = startOffset + 5
        let off2 = OffsetOfWrappedLine(block,
                                       startOffset,
                                       2,
                                       rawLength,
                                       wrapWidth,
                                       true)
        XCTAssertEqual(off2, startOffset + 5,
                       "Third segment should start 5 cells in")
    }

    // MARK: - NumberOfFullLines

    func testNumberOfFullLinesFromOffsetSimpleDivision() {
        // width > length or mayHaveDWC=false: (length-1)/width.

        // Given a LineBlock (the rope content is irrelevant for this calculation)
        let block = LineBlock(rawBufferSize: 0, absoluteBlockNumber: 0)
        // Ensure we take the “simple division” path by disabling DWC handling
        block.mayHaveDoubleWidthCharacter = false

        // When length=10, width=3 → (10 - 1) / 3 = 3 full lines
        let fullLines = block.numberOfFullLines(fromOffset: 0, length: 10, width: 3)
        XCTAssertEqual(fullLines, 3,
                       "Expected (10 - 1) / 3 = 3 full lines when mayHaveDoubleWidthCharacter is false")

        // When width > length (width=20, length=10) → (10 - 1) / 20 = 0
        let zeroFullLines = block.numberOfFullLines(fromOffset: 0, length: 10, width: 20)
        XCTAssertEqual(zeroFullLines, 0,
                       "Expected (10 - 1) / 20 = 0 full lines when width exceeds length")

        // When length=0 → MAX(0, (0 - 1) / width) = 0
        let emptyFullLines = block.numberOfFullLines(fromOffset: 0, length: 0, width: 5)
        XCTAssertEqual(emptyFullLines, 0,
                       "Expected zero full lines for an empty raw line")

        // Also verify width=1 edge-case: (10 - 1) / 1 = 9
        let widthOneLines = block.numberOfFullLines(fromOffset: 0, length: 10, width: 1)
        XCTAssertEqual(widthOneLines, 9,
                       "Expected (10 - 1) / 1 = 9 full lines when width is 1")
    }

    func testNumberOfFullLinesFromOffsetDWCImpl() {
        // With mayHaveDoubleWidthCharacter = true and a known double-width character in the content,
        // numberOfFullLines(fromOffset:length:width:) should take the slower, DWC-aware path
        // and group the double-width character so it isn’t split across a “full” line boundary.
        //
        // In this example, the string "AB中DEF" produces the following cell sequence:
        //   [0]='A', [1]='B',
        //   [2]='中', [3]=DWC_RIGHT placeholder,
        //   [4]='D', [5]='E', [6]='F'
        // At wrapWidth = 3, a naive division would give (7-1)/3 = 2 full lines,
        // but because the double-width character at indices 2–3 must travel together,
        // only one truly “full” 3-cell segment can be formed:
        //   segment0 = cells[0..<2] ("AB")  → not full (length 2)
        //   segment1 = cells[2..<5] ("中<D>")→ full   (length 3)
        //   segment2 = cells[5..<7] ("EF")  → not full (length 2)
        //
        // Therefore we expect numberOfFullLines = 1.
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 0)

        // Enable the double-width–aware path
        block.mayHaveDoubleWidthCharacter = true

        // Append the line containing the CJK ideogram “中” (which StringToScreenChars will mark double-width)
        let lineString = makeLineString("AB中DEF", eol: EOL_HARD)
        let wrapWidth: Int32 = 3
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending 'AB中DEF' should succeed")

        // Now compute how many full-width segments fit entirely before the last partial segment
        let fullLines = block.numberOfFullLines(fromOffset: 0,
                                                length: block.rawSpaceUsed(),
                                                width: wrapWidth)

        // There will be two full lines when wrapped at 3 because it should go:
        // AB
        // 中-D
        // EF
        // A full line is a line that uses all the available space on its wrapped line.
        // Since EF does not use the third cell, it dosen't count as a full line.
        XCTAssertEqual(fullLines, 2,
                       "Expected 1 full line for 'AB中DEF' at width 3 when honoring the double-width character boundary")
    }
    // MARK: - locationOfRawLineForWidth

    func testLocationOfRawLineForWidthConsumesWrappedLines() {
        // Multiple raw lines with varying lengths. Call with successive lineNum to traverse raw lines.

        // Given a block with several raw lines of varying lengths
        let capacity: Int32 = 100
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)
        let wrapWidth: Int32 = 3

        // Append three hard‐EOL raw lines:
        // “One”   → 3 chars → wraps into [3]             (1 segment)
        // “Four”  → 4 chars → wraps into [3, 1]         (2 segments)
        // “Hello” → 5 chars → wraps into [3, 2]         (2 segments)
        let texts = ["One", "Four", "Hello"]
        for text in texts {
            let ls = makeLineString(text, eol: EOL_HARD)
            XCTAssertTrue(block.appendLineString(ls, width: wrapWidth),
                          "Precondition: appending '\(text)' should succeed")
        }

        // When we ask how many wrapped lines there are at width=3
        let wrappedCount = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(wrappedCount, 1 + 2 + 2,
                       "Expected 5 wrapped lines for segments [1,2,2]")

        // Compute the expected raw‐line start offsets in the rope:
        // rawLine0 starts at 0
        // rawLine1 starts at 3  (length of “One”)
        // rawLine2 starts at 3 + 4 = 7  (length of “One” + “Four”)
        let expectedRawStarts: [Int32] = [0, 3, 7]

        // Then for each wrapped‐line index, locationOfRawLine should return
        // the start offset of the raw line that wrapped segment belongs to.
        for wrappedLineIndex in 0..<wrappedCount {
            var temp = wrappedLineIndex
            let rawStart = block.locationOfRawLine(forWidth: wrapWidth,
                                                   lineNum: &temp)
            let expectedStart: Int32
            if wrappedLineIndex < 1 {
                // inside the first raw line
                expectedStart = expectedRawStarts[0]
            } else if wrappedLineIndex < 1 + 2 {
                // inside the second raw line
                expectedStart = expectedRawStarts[1]
            } else {
                // inside the third raw line
                expectedStart = expectedRawStarts[2]
            }
            XCTAssertEqual(rawStart.prev, expectedStart,
                           "Wrapped line \(wrappedLineIndex) should map to raw‐line start at offset \(expectedStart)")
        }
    }

    func testLocationOfRawLineForWidthHandlesEmptyLinesAndNumEmptyLines() {
        // Include empty raw lines interspersed with non-empty lines and verify that:
        // 1. `prev` (the start offset of the raw line in the rope) stays the same for zero-length lines
        //    and advances by the cumulative cell count when non-empty lines are appended.
        // 2. `numEmptyLines` is zero for empty raw lines, and for each non-empty raw line it equals
        //    the number of immediately preceding empty raw lines.
        //
        // We use a wrapWidth large enough (== capacity) so that no wrapping occurs and each raw line
        // corresponds to exactly one wrapped line.

        // Given a block with ample capacity
        let capacity: Int32 = 100
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)
        let wrapWidth: Int32 = capacity

        // Append two empty raw lines
        XCTAssertTrue(block.appendLineString(makeLineString("", eol: EOL_HARD), width: wrapWidth))
        XCTAssertTrue(block.appendLineString(makeLineString("", eol: EOL_HARD), width: wrapWidth))

        // Append a non-empty raw line "A"
        XCTAssertTrue(block.appendLineString(makeLineString("A", eol: EOL_HARD), width: wrapWidth))

        // Append another empty raw line
        XCTAssertTrue(block.appendLineString(makeLineString("", eol: EOL_HARD), width: wrapWidth))

        // Append a second non-empty raw line "BC"
        XCTAssertTrue(block.appendLineString(makeLineString("BC", eol: EOL_HARD), width: wrapWidth))

        // Precondition: there should be 5 raw lines (and hence 5 wrapped lines)
        let totalLines = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(totalLines, 5, "Should have 5 wrapped lines (one per raw line, no wrapping)")

        // Expected start offsets in the rope for each raw line:
        //   line0 (empty) -> offset 0
        //   line1 (empty) -> offset 0
        //   line2 ("A")   -> offset 0
        //   line3 (empty) -> offset 1
        //   line4 ("BC")  -> offset 1
        let expectedPrev: [Int32] = [0, 0, 0, 1, 1]

        // Expected numEmptyLines for each raw line:
        //   line0: empty     -> 0
        //   line1: empty     -> 0
        //   line2: "A"       -> 2 (two empties before)
        //   line3: empty     -> 0
        //   line4: "BC"      -> 1 (one empty immediately before)
        // See the note in the implementation. I think this is wrong but I don't want to risk breaking things.
        // I vaguely recall that there were some VT100Screen tests that exercised this, probably with
        // regard to selections and resizing. It would be nice to bring back those tests and see how
        // they handle this case.
        let expectedNumEmpty: [Int32] = [0, 1, 2, 1, 1]
        print(block.dumpString())
        // Verify for each wrapped-line index
        for wrappedIndex in 0..<totalLines {
            var idx = wrappedIndex
            let loc = block.locationOfRawLine(forWidth: wrapWidth, lineNum: &idx)
            XCTAssertEqual(loc.prev,
                           expectedPrev[Int(wrappedIndex)],
                           "Wrapped line \(wrappedIndex) should map to raw-start offset \(expectedPrev[Int(wrappedIndex)])")
            XCTAssertEqual(loc.numEmptyLines,
                           expectedNumEmpty[Int(wrappedIndex)],
                           "Wrapped line \(wrappedIndex) should have numEmptyLines == \(expectedNumEmpty[Int(wrappedIndex)])")
        }
    }
    // MARK: - getPositionOfLine

    func testGetPositionOfLineMapsOffsetBasic() {
        // For a known rawBuffer, verify getPositionOfLine gives correct x,y for position within line.

        // Given a block with sufficient capacity for a single raw line
        let capacity: Int32 = 20
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)

        // And a hard‐EOL raw line "ABCDEFGHIJ" (10 chars) appended
        let text = "ABCDEFGHIJ"
        let lineString = makeLineString(text, eol: EOL_HARD)
        let wrapWidth: Int32 = 5
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending a 10‐char hard‐EOL line should succeed")

        // When we ask for the (x,y) coordinate of a given raw‐buffer offset
        // e.g. offset 7 should map to the 8th character in the wrapped‐line grid:
        //   0:'A' 1:'B' 2:'C' 3:'D' 4:'E'  ← first wrapped line (y=0)
        //   5:'F' 6:'G' 7:'H' 8:'I' 9:'J'  ← second wrapped line (y=1)
        let targetOffset: Int32 = 7
        var x: Int32 = -1
        var y: Int32 = -1

        // Call the conversion method
        let success = block.convertPosition(targetOffset,
                                            withWidth: wrapWidth,
                                            wrapOnEOL: true,
                                            toX: &x,
                                            toY: &y)
        XCTAssertTrue(success, "convertPosition should succeed for a valid offset")

        // Then we expect:
        //  • y = floor(offset / wrapWidth) = floor(7 / 5) = 1
        //  • x = offset % wrapWidth         = 7 % 5 = 2
        XCTAssertEqual(y, 1, "Y coordinate should be the wrapped‐line index (7/5 = 1)")
        XCTAssertEqual(x, 2, "X coordinate should be the in‐line index (7%5 = 2)")
    }

    func testGetPositionOfLineWrapOnEOLTrueAtHardEOL() {
        // x beyond length with wrapOnEOL=true should set extendsPtr=true and pos at end-of-line.

        // Given a block with a single hard-EOL raw line
        let text = "Hello"
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 0)
        let wrapWidth: Int32 = 10
        let lineString = makeLineString(text, eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending a hard-EOL line should succeed")
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending a hard-EOL line should succeed")

        // When we convert a position that lies exactly at the end of that line
        let offsetAtEOL: Int32 = Int32(text.utf16.count)    // one past the last character
        var x: Int32 = -1
        var y: Int32 = -1

        // wrapOnEOL = true should allow us to map offsets beyond the line length
        let success = block.convertPosition(offsetAtEOL,
                                            withWidth: wrapWidth,
                                            wrapOnEOL: true,
                                            toX: &x,
                                            toY: &y)
        XCTAssertTrue(success, "convertPosition should succeed even for offsets at or beyond EOL when wrapOnEOL=true")

        // Since wrapOnEOL was true, expect the cursor to be at the start of the second line, not at the end of the first line.
        XCTAssertEqual(y, 1, "Y coordinate should stay on the only wrapped line (index 0)")
        XCTAssertEqual(x, 0,
                       "X coordinate should be clamped to the end of line (character count) when wrapOnEOL=true")
    }

    func testGetPositionOfLineWrapOnEOLFalseAtHardEOL() {
        // x beyond length with wrapOnEOL=true should set extendsPtr=true and pos at end-of-line.

        // Given a block with a single hard-EOL raw line
        let text = "Hello"
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 0)
        let wrapWidth: Int32 = 10
        let lineString = makeLineString(text, eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending a hard-EOL line should succeed")
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending a hard-EOL line should succeed")

        // When we convert a position that lies exactly at the end of that line
        let offsetAtEOL: Int32 = Int32(text.utf16.count)    // one past the last character
        var x: Int32 = -1
        var y: Int32 = -1

        // wrapOnEOL = true should allow us to map offsets beyond the line length
        let success = block.convertPosition(offsetAtEOL,
                                            withWidth: wrapWidth,
                                            wrapOnEOL: false,
                                            toX: &x,
                                            toY: &y)
        XCTAssertTrue(success, "convertPosition should succeed even for offsets at or beyond EOL when wrapOnEOL=true")

        // Since wrapOnEOL was false, expect the cursor to be at the end of the first line.
        XCTAssertEqual(y, 0, "Y coordinate should stay on the only wrapped line (index 0)")
        XCTAssertEqual(x, 5,
                       "X coordinate should be clamped to the end of line (character count) when wrapOnEOL=true")
    }

    struct RandomEvent: Codable, Equatable {
        enum Action: String, Codable, Equatable {
            case beginOuterLoop
            case append
            case drop
            case pop
            case stepEmpty
            case stepPos
        }

        let outer: Int
        let step: Int?
        let action: Action
        // optional payloads
        let length: Int?
        let eol: Int?
        let count: Int?
        let x: Int?
        let y: Int?
        let pos: Int?
        let width: Int?
        let yOffset: Int?
        let extendsRight: Bool?
    }
    /*
     func testWriteRandom() throws {
     // ——————————————————————
     // 1) set up LCG and block
     // ——————————————————————
     struct LCG64 {
     private var state: UInt64
     init(seed: UInt64) { self.state = seed != 0 ? seed : 1 }
     mutating func next() -> Int64 {
     state = 6364136223846793005 &* state &+ 1
     return Int64(bitPattern: state & 0x7FFF_FFFF_FFFF_FFFF)
     }
     }

     let block = LineBlock(rawBufferSize: 1000, absoluteBlockNumber: 0)
     let base = Array(repeating: "ABCDEFGHIJKLMNOPRQSTUVWXYZ", count: 500).joined()
     let hardEOL = unichar(EOL_HARD)
     let softEOL = unichar(EOL_SOFT)

     var rng = LCG64(seed: 0)
     var step = 0
     var events = [RandomEvent]()

     // ——————————————————————
     // 2) run loops, record events
     // ——————————————————————
     for outer in 0..<100 {
     events.append(.init(
     outer: outer,
     step: nil,
     action: .beginOuterLoop,
     length: nil, eol: nil, count: nil,
     x: nil, y: nil, pos: nil,
     width: nil, yOffset: nil, extendsRight: nil
     ))

     let width = 2 + Int(rng.next() % 10)

     for _ in 0..<100 {
     let v = rng.next()
     switch v % 3 {
     case 0:
     let len = Int(1 + rng.next() % 20)
     let eolVal = Int((rng.next() & 5) > 3 ? hardEOL : softEOL)
     let substr = String(base.prefix(len))
     let lineString = makeLineString(substr, eol: Int32(eolVal))
     block.appendLineString(lineString, width: Int32(width))
     events.append(.init(
     outer: outer, step: step,
     action: .append,
     length: len, eol: eolVal,
     count: nil, x: nil, y: nil, pos: nil,
     width: width, yOffset: nil, extendsRight: nil
     ))

     case 1:
     var droppedChars: Int32 = 0
     let cnt = Int32(rng.next() % 3) + 1
     block.dropLines(cnt, withWidth: Int32(width), chars: &droppedChars)
     events.append(.init(
     outer: outer, step: step,
     action: .drop,
     length: nil, eol: nil,
     count: Int(cnt),
     x: nil, y: nil, pos: nil,
     width: width, yOffset: nil, extendsRight: nil
     ))

     default:
     block.popLastLineUp(toWidth: Int32(width), forceSoftEOL: false)
     events.append(.init(
     outer: outer, step: step,
     action: .pop,
     length: nil, eol: nil, count: nil,
     x: nil, y: nil, pos: nil,
     width: width, yOffset: nil, extendsRight: nil
     ))
     }

     let numLines = Int(block.getNumLines(withWrapWidth: Int32(width)))
     if numLines == 0 {
     events.append(.init(
     outer: outer, step: step,
     action: .stepEmpty,
     length: nil, eol: nil, count: nil,
     x: nil, y: nil, pos: nil,
     width: width, yOffset: nil, extendsRight: nil
     ))
     } else {
     let x = Int(rng.next() % Int64(max(1, width)))
     let y = Int(rng.next() % Int64(numLines))
     var line = Int32(y)
     var yOffset = Int32(0)
     var extends = ObjCBool(false)
     let pos = Int(block.getPositionOfLine(
     &line,
     atX: Int32(x),
     withWidth: Int32(width),
     yOffset: &yOffset,
     extends: &extends
     ))
     events.append(.init(
     outer: outer, step: step,
     action: .stepPos,
     length: nil, eol: nil, count: nil,
     x: x, y: y, pos: pos,
     width: width,
     yOffset: Int(yOffset),
     extendsRight: extends.boolValue
     ))
     }
     step += 1
     }
     }

     // ——————————————————————
     // 3) write JSON to disk
     // ——————————————————————
     let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
     .appendingPathComponent("testRandomOutput.json")

     let encoder = JSONEncoder()
     encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
     let data = try encoder.encode(events)
     try data.write(to: outputURL)

     // if you like, assert the file exists:
     XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path),
     "Couldn’t write JSON to \(outputURL.path)")
     // and you can even log where it went:
     print("Wrote random-test output to: \(outputURL.path)")
     }
     */

    func testGetPositionOfLineStartOfWrappedLineIncrementsYOffset() {
        // Given a block whose single raw line wraps into multiple segments
        // For example, content "ABCDE" with wrapWidth = 2 → wrapped segments: ["AB","CD","E"]
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 0)
        let wrapWidth: Int32 = 2
        let content = "ABCDE"
        let lineString = makeLineString(content, eol: EOL_HARD)
        let emptyString = makeLineString("", eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending \"\(content)\" should succeed")
        XCTAssertTrue(block.appendLineString(emptyString, width: wrapWidth),
                      "Precondition: appending \"\(content)\" should succeed")
        XCTAssertTrue(block.appendLineString(lineString, width: wrapWidth),
                      "Precondition: appending \"\(content)\" should succeed")

        struct Result: Equatable {
            var x: Int32
            var y: Int32
            var line: Int32
            var pos: Int32
            var yo: Int32
            var ex: Bool
        }
        var actual = [Result]()
        for y in 0..<8 {
            for x in 0..<2 {
                var yo = Int32(0)
                var ex = ObjCBool(false)
                var line = Int32(y)
                let pos = block.getPositionOfLine(&line,
                                                  atX: Int32(x),
                                                  withWidth: wrapWidth,
                                                  yOffset: &yo,
                                                  extends: &ex)
                actual.append(Result(x: Int32(x),
                                     y: Int32(y),
                                     line: line,
                                     pos: pos,
                                     yo: yo,
                                     ex: ex.boolValue))
            }
        }
        let expected = [
            Result(x: 0, y: 0, line: 0, pos: 0, yo: 0, ex: false),
            Result(x: 1, y: 0, line: 0, pos: 1, yo: 0, ex: false),
            Result(x: 0, y: 1, line: 0, pos: 2, yo: 0, ex: false),
            Result(x: 1, y: 1, line: 0, pos: 3, yo: 0, ex: false),
            Result(x: 0, y: 2, line: 0, pos: 4, yo: 0, ex: false),
            Result(x: 1, y: 2, line: 0, pos: 5, yo: 0, ex: true),
            Result(x: 0, y: 3, line: 0, pos: 5, yo: 1, ex: false),
            Result(x: 1, y: 3, line: 0, pos: 5, yo: 1, ex: true),
            Result(x: 0, y: 4, line: 0, pos: 5, yo: 2, ex: false),
            Result(x: 1, y: 4, line: 0, pos: 6, yo: 0, ex: false),
            Result(x: 0, y: 5, line: 0, pos: 7, yo: 0, ex: false),
            Result(x: 1, y: 5, line: 0, pos: 8, yo: 0, ex: false),
            Result(x: 0, y: 6, line: 0, pos: 9, yo: 0, ex: false),
            Result(x: 1, y: 6, line: 0, pos: 10, yo: 0, ex: true),
            Result(x: 0, y: 7, line: 0, pos: -1, yo: 0, ex: false),
            Result(x: 1, y: 7, line: 0, pos: -1, yo: 0, ex: false),
        ]
        XCTAssertEqual(actual, expected)
    }

    // Golden data was verified against the current production version of the app. Uncomment the
    // "writer" test above it you need to regenerate it. It will log the output file. Then copy that
    // into ModernTests/LineBlockRandomGetPositionTestData.json.
    func testRandomMatchesGoldenData() throws {
        // 1) load expected events from bundle
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(
            forResource: "LineBlockRandomGetPositionTestData",
            withExtension: "json"
        ) else {
            XCTFail("Couldn’t find LineBlockRandomGetPositionTestData.json in bundle")
            return
        }
        let data = try Data(contentsOf: url)
        let expectedEvents = try JSONDecoder().decode([RandomEvent].self, from: data)

        // 2) generate actual events
        struct LCG64 {
            private var state: UInt64
            init(seed: UInt64) { self.state = seed != 0 ? seed : 1 }
            mutating func next() -> Int64 {
                state = 6364136223846793005 &* state &+ 1
                return Int64(bitPattern: state & 0x7FFF_FFFF_FFFF_FFFF)
            }
        }

        let block = LineBlock(rawBufferSize: 1000, absoluteBlockNumber: 0)
        let base = Array(repeating: "ABCDEFGHIJKLMNOPRQSTUVWXYZ", count: 500).joined()
        let hardEOL = unichar(EOL_HARD)
        let softEOL = unichar(EOL_SOFT)

        var rng = LCG64(seed: 0)
        var step = 0
        var actualEvents = [RandomEvent]()

        for outer in 0..<100 {
            actualEvents.append(.init(
                outer: outer,
                step: nil,
                action: .beginOuterLoop,
                length: nil, eol: nil, count: nil,
                x: nil, y: nil, pos: nil,
                width: nil, yOffset: nil, extendsRight: nil
            ))

            let width = 2 + Int(rng.next() % 10)

            for _ in 0..<100 {
                let v = rng.next()
                switch v % 3 {
                case 0:
                    let len = Int(1 + rng.next() % 20)
                    let eolVal = Int((rng.next() & 5) > 3 ? hardEOL : softEOL)
                    let substr = String(base.prefix(len))
                    let lineString = makeLineString(substr, eol: Int32(eolVal))
                    block.appendLineString(lineString, width: Int32(width))
                    actualEvents.append(.init(
                        outer: outer, step: step,
                        action: .append,
                        length: len, eol: eolVal,
                        count: nil, x: nil, y: nil, pos: nil,
                        width: width, yOffset: nil, extendsRight: nil
                    ))

                case 1:
                    var droppedChars: Int32 = 0
                    let cnt = Int32(rng.next() % 3) + 1
                    block.dropLines(cnt, withWidth: Int32(width), chars: &droppedChars)
                    actualEvents.append(.init(
                        outer: outer, step: step,
                        action: .drop,
                        length: nil, eol: nil,
                        count: Int(cnt),
                        x: nil, y: nil, pos: nil,
                        width: width, yOffset: nil, extendsRight: nil
                    ))

                default:
                    block.popLastLineUp(toWidth: Int32(width), forceSoftEOL: false)
                    actualEvents.append(.init(
                        outer: outer, step: step,
                        action: .pop,
                        length: nil, eol: nil, count: nil,
                        x: nil, y: nil, pos: nil,
                        width: width, yOffset: nil, extendsRight: nil
                    ))
                }

                let numLines = Int(block.getNumLines(withWrapWidth: Int32(width)))
                if numLines == 0 {
                    actualEvents.append(.init(
                        outer: outer, step: step,
                        action: .stepEmpty,
                        length: nil, eol: nil, count: nil,
                        x: nil, y: nil, pos: nil,
                        width: width, yOffset: nil, extendsRight: nil
                    ))
                } else {
                    let x = Int(rng.next() % Int64(max(1, width)))
                    let y = Int(rng.next() % Int64(numLines))
                    var line = Int32(y)
                    var yOffset = Int32(0)
                    var extends = ObjCBool(false)
                    let pos = Int(block.getPositionOfLine(
                        &line,
                        atX: Int32(x),
                        withWidth: Int32(width),
                        yOffset: &yOffset,
                        extends: &extends
                    ))
                    actualEvents.append(.init(
                        outer: outer, step: step,
                        action: .stepPos,
                        length: nil, eol: nil, count: nil,
                        x: x, y: y, pos: pos,
                        width: width,
                        yOffset: Int(yOffset),
                        extendsRight: extends.boolValue
                    ))
                }
                step += 1
            }
        }

        // 3) compare
        XCTAssertEqual(
            actualEvents.count,
            expectedEvents.count,
            "Event count mismatch: got \(actualEvents.count), expected \(expectedEvents.count)"
        )
        for (i, (actual, expected)) in zip(actualEvents, expectedEvents).enumerated() {
            XCTAssertEqual(
                actual,
                expected,
                "Mismatch at event \(i):\n  actual: \(actual)\n  expected: \(expected)"
            )
        }
    }

    // MARK: - findSubstring

    func testFindSubstringPlainForwardSingleResult() {
        // Plain substring search forwards with multipleResults = false.
        // Given a block containing a single raw line "hello world"
        let block = LineBlock(rawBufferSize: 100, absoluteBlockNumber: 0)
        let width: Int32 = 80
        let text = "hello world"
        let lineString = makeLineString(text, eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(lineString, width: width),
                      "Precondition: appending 'hello world' should succeed")

        // When searching for "hello" starting at offset 0, forwards, single result
        let results = NSMutableArray()
        var includesPartialLastLine = ObjCBool(false)
        block.findSubstring("hello",
                            options: [],
                            mode: .smartCaseSensitivity,
                            atOffset: 0,
                            results: results,
                            multipleResults: false,
                            includesPartialLastLine: &includesPartialLastLine)

        // Then exactly one match should be returned
        XCTAssertEqual(results.count, 1, "Expected exactly one match when multipleResults=false")

        // And it should point to the first occurrence at position 0 with the correct length
        let match = results[0] as! ResultRange
        XCTAssertEqual(match.position, 0, "Match should start at offset 0")
        XCTAssertEqual(match.length, Int32("hello".utf16.count), "Match length should equal the length of 'hello'")

        // And we should not include a partial last‐line flag for this input
        XCTAssertFalse(includesPartialLastLine.boolValue,
                       "includesPartialLastLine should be false for a single‐line, hard-EOL search")
    }
    func testFindSubstringPlainBackwardMultipleResults() {
        // Plain substring search backwards with multipleResults=true.
        // Given a block containing a single raw line with three occurrences of "foo"
        let block = LineBlock(rawBufferSize: 100, absoluteBlockNumber: 0)
        let width: Int32 = 80
        let text = "foo bar foo baz foo"
        let lineString = makeLineString(text, eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(lineString, width: width),
                      "Precondition: appending '\(text)' should succeed")

        // When searching for "foo" backwards with multipleResults enabled
        // and starting at the end of the buffer
        let options = FindOptions(rawValue: FindOptions.optBackwards.rawValue | FindOptions.multipleResults.rawValue)
        var includesPartialLastLine = ObjCBool(false)
        let results = NSMutableArray()
        block.findSubstring("foo",
                            options: options,
                            mode: .smartCaseSensitivity,
                            atOffset: Int32(block.rawSpaceUsed() - 1),
                            results: results,
                            multipleResults: true,
                            includesPartialLastLine: &includesPartialLastLine)

        // Then we expect three matches in reverse order of occurrence
        XCTAssertEqual(results.count, 3, "Expected three matches when multipleResults=true")

        // Extract the match positions
        let positions = results
            .compactMap { $0 as? ResultRange }
            .map { $0.position }

        // In "foo bar foo baz foo", "foo" occurs at offsets 0, 8, and 17
        // Backward search should return them in [17, 8, 0]
        XCTAssertEqual(positions, [16, 8, 0],
                       "Backward multiple-results search should yield positions [17, 8, 0]")

        // And since this is a single hard-EOL line, includesPartialLastLine should be false
        XCTAssertFalse(includesPartialLastLine.boolValue,
                       "includesPartialLastLine should be false for a hard-EOL single-line search")
    }
    func testFindSubstringRegexCaseInsensitive() {
        // Regex mode case-insensitive search; include special chars $ and ^ in needle.

        // Given a block containing a single raw line whose text has mixed case
        let block = LineBlock(rawBufferSize: 100, absoluteBlockNumber: 0)
        let width: Int32 = 100
        let text = "FoObAr"
        let lineString = makeLineString(text, eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(lineString, width: width),
                      "Precondition: appending mixed-case 'FoObAr' should succeed")

        // When searching with a regex that anchors the entire line, in case-insensitive mode
        let pattern = "^foobar$"
        let results = NSMutableArray()
        var includesPartialLastLine = ObjCBool(false)
        block.findSubstring(pattern,
                            options: [],
                            mode: .caseInsensitiveRegex,
                            atOffset: 0,
                            results: results,
                            multipleResults: false,
                            includesPartialLastLine: &includesPartialLastLine)

        // Then exactly one match should be returned
        XCTAssertEqual(results.count, 1,
                       "Regex search should find one match for '^foobar$' ignoring case")

        // And it should cover the entire raw line (position 0, length 6)
        let match = results[0] as! ResultRange
        XCTAssertEqual(match.position, 0, "Match should start at offset 0")
        XCTAssertEqual(match.length, Int32(text.utf16.count),
                       "Match length should equal the full raw line length")

        // And we should not set includesPartialLastLine for a hard-EOL single line
        XCTAssertFalse(includesPartialLastLine.boolValue,
                       "includesPartialLastLine should be false for a single hard-EOL line")
    }

    func testFindSubstringMultiLineMode() {
        // Split needle on \n, search multi-line within a single raw line; verify combined matching logic.

        // Given a block containing two raw lines "foo" (hard EOL) and "bar" (hard EOL),
        // which in the rope appear as "foobar".
        let block = LineBlock(rawBufferSize: 100, absoluteBlockNumber: 0)
        let width: Int32 = 80
        XCTAssertTrue(block.appendLineString(makeLineString("foo", eol: EOL_HARD), width: width),
                      "Precondition: appending 'foo' should succeed")
        XCTAssertTrue(block.appendLineString(makeLineString("bar", eol: EOL_HARD), width: width),
                      "Precondition: appending 'bar' should succeed")
        // When searching for the multi-line pattern "foo\nbar" in multi-line mode:
        //   - We include the literal newline in the needle
        //   - We set FindOptMultiLine so that the search may span across raw-line boundaries
        let needle = "foo\nbar"
        let options: FindOptions = .optMultiLine
        let results = NSMutableArray()
        var includesPartialLastLine = ObjCBool(false)
        block.findSubstring(needle,
                            options: options,
                            mode: .caseSensitiveSubstring,
                            atOffset: 0,
                            results: results,
                            multipleResults: false,
                            includesPartialLastLine: &includesPartialLastLine)
        // Then exactly one match should be returned covering the concatenation of both lines
        XCTAssertEqual(results.count, 1,
                       "Multi-line mode should allow a single match spanning the EOL between 'foo' and 'bar'")
        let match = results[0] as! ResultRange
        // 'foo' is 3 chars, newline is conceptual (zero-width in rope), 'bar' is 3 chars → total length 6
        XCTAssertEqual(match.position, 0,
                       "Match should start at the very beginning of the rope")
        XCTAssertEqual(match.length, 6,
                       "Match length should cover 'foo' + 'bar' across the line break (6 cells total)")
        XCTAssertFalse(includesPartialLastLine.boolValue,
                       "includesPartialLastLine should remain false for hard-EOL termination")
    }

    // MARK: - Metadata Invariants

    func testMetadataArrayNumEntriesEqualsCLLEntriesAfterAppendAndPop() {
        // After appending raw lines (which grows both the metadata array and the cumulative_line_lengths),
        // and then popping the last raw line, metadataArray.numEntries (exposed as block.numEntries())
        // should always equal the internal count of cumulative_line_lengths entries.

        // Given a LineBlock with capacity for several raw lines
        let capacity: Int32 = 50
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)
        let width: Int32 = 10

        // When we append two hard-EOL raw lines
        XCTAssertTrue(block.appendLineString(makeLineString("First", eol: EOL_HARD), width: width),
                      "Appending the first raw line should succeed")
        XCTAssertTrue(block.appendLineString(makeLineString("Second", eol: EOL_HARD), width: width),
                      "Appending the second raw line should succeed")

        // Then metadataArray.numEntries should equal 2 (one per raw line)
        XCTAssertEqual(block.numEntries(), 2,
                       "After two appends, metadata entries count should match the number of raw lines")

        // When we pop (remove) the last raw line
        block.removeLastRawLine()

        // Then metadataArray.numEntries should have decremented by one (now 1)
        XCTAssertEqual(block.numEntries(), 1,
                       "After popping the last raw line, metadata entries count should decrement accordingly")

        // And as a sanity check, numRawLines() (the number of accessible raw lines)
        // plus firstEntry (dropped prefix count) should also equal metadataArray.numEntries.
        let expectedEntries = block.numRawLines() + block.firstEntry
        XCTAssertEqual(block.numEntries(), expectedEntries,
                       "metadata entries (numEntries) should equal rawLines + firstEntry (cumulative_line_lengths entries)")
    }

    // MARK: - Invalidation

    func testInvalidateMarksBlockInvalidated() {
        // Call invalidate() and verify invalidated property set, isSynchronizedWithProgenitor fails.

        // Given a fresh LineBlock with some content so that invalidation has something to mark
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)
        let width: Int32 = 5
        XCTAssertTrue(block.appendLineString(makeLineString("abc", eol: EOL_HARD), width: width),
                      "Precondition: appending a hard-EOL line should succeed")

        // Precondition: the block should not yet be marked invalid
        XCTAssertFalse(block.invalidated, "Before calling invalidate(), `invalidated` should be false")

        // When we invalidate the block
        block.invalidate()

        // Then the block’s `invalidated` flag should be set
        XCTAssertTrue(block.invalidated, "Calling invalidate() should set `invalidated = true`")

        // And it should no longer be considered synchronized with any progenitor
        XCTAssertFalse(block.isSynchronizedWithProgenitor(),
                       "After invalidation, `isSynchronizedWithProgenitor()` should return false")
    }

    // MARK: - Regression

    func testAppendAfterRemoveLastRawLine() {
        // Append a raw line, remove it, then append a shorter line and verify wrapping and state reset.
        //
        // Given a block with capacity to hold at least one raw line
        let capacity: Int32 = 10
        let block = LineBlock(rawBufferSize: capacity, absoluteBlockNumber: 1)
        let wrapWidth: Int32 = 4

        // And an initial raw line "ABCDEFG" (7 chars) with a hard EOL
        let original = "ABCDEFG"
        let originalLine = makeLineString(original, eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(originalLine, width: wrapWidth),
                      "Precondition: appending 'ABCDEFG' should succeed")

        // Precondition: it should wrap into 2 segments of lengths [4,3]
        let initialWrapped = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(initialWrapped, 2,
                       "Expected 2 wrapped lines for raw length 7 at width 4")

        // When we remove the last raw line entirely
        block.removeLastRawLine()

        // Then the block should be empty and all state reset
        XCTAssertTrue(block.isEmpty(), "Block should be empty after removing its only raw line")
        XCTAssertEqual(block.numRawLines(), 0, "numRawLines should be zero after removal")
        XCTAssertEqual(block.rawSpaceUsed(), 0, "rawSpaceUsed should reset to zero after removal")
        XCTAssertEqual(block.startOffset(), 0, "startOffset should reset to 0 on empty block")
        XCTAssertEqual(block.firstEntry, 0, "firstEntry should reset to 0 on empty block")
        XCTAssertEqual(block.numEntries(), 0, "numEntries should be 0 on empty block")
        XCTAssertFalse(block.hasPartial(), "hasPartial should be false on an empty block")

        // When we append a shorter raw line "XYZ" (3 chars) with a hard EOL
        let newLine = makeLineString("XYZ", eol: EOL_HARD)
        XCTAssertTrue(block.appendLineString(newLine, width: wrapWidth),
                      "Appending 'XYZ' should succeed on a reset block")

        // Then it should wrap into exactly 1 segment of length 3
        let newWrapped = block.getNumLines(withWrapWidth: wrapWidth)
        XCTAssertEqual(newWrapped, 1,
                       "Expected 1 wrapped line for raw length 3 at width 4")

        // And the content of that wrapped line should be "XYZ" with a hard-EOL continuation
        var wrappedIndex: Int32 = 0
        guard let segment = block.wrappedLineString(withWrapWidth: wrapWidth, lineNum: &wrappedIndex)?
            .screenCharArray(bidi: nil) else {
            return XCTFail("wrappedLineString returned nil after appending 'XYZ'")
        }
        XCTAssertEqual(segment.stringValue, "XYZ",
                       "Wrapped segment should contain the new line's characters")
        XCTAssertEqual(segment.continuation.code, unichar(EOL_HARD),
                       "Continuation code for the wrapped segment should be EOL_HARD")

        // And raw-space used and raw line count reflect the new line only
        XCTAssertEqual(block.numRawLines(), 1, "Block should contain one raw line after re-append")
        XCTAssertEqual(block.rawSpaceUsed(), Int32(newLine.content.cellCount),
                       "rawSpaceUsed should match the length of the new line")
    }
}
