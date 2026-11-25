//
//  ImageFoundMetadataCompatTests.swift
//  ModernTests
//
//  A line's metadata says whether it may hold a cell of an inline image
//  (imageFound). It travels with the line into history and back, like
//  rtlFound, so it is a sixth trailing scalar in the array encoding and a
//  trailing byte in the TLV encoding. Data from before the field existed
//  decodes as YES (“maybe”): the first check of such a line on screen scans
//  its cells and corrects the flag, so each old line is scanned at most once.
//  See BidiDirectionMetadataCompatTests for why older readers skip a trailing
//  field they don't know.
//

import XCTest
@testable import iTerm2SharedARC

final class ImageFoundMetadataCompatTests: XCTestCase {
    private func decodeArray(_ array: [Any]) -> iTermMetadata {
        var decoded = iTermMetadata()
        iTermMetadataInitFromArray(&decoded, array)
        return decoded
    }

    // MARK: - Array encoding

    func testArrayRoundTripPreservesImageFound() {
        for imageFound in [false, true] {
            var original = iTermMetadataDefault()
            original.imageFound = ObjCBool(imageFound)
            original.bidiDirection = .rightToLeft
            let decoded = decodeArray(iTermMetadataEncodeToArray(original))
            XCTAssertEqual(decoded.imageFound.boolValue, imageFound)
            XCTAssertEqual(decoded.bidiDirection, .rightToLeft)
            iTermMetadataRelease(decoded)
        }
    }

    // Before imageFound: [timestamp, eaDict, rtlFound, lineAttribute, bidiDirection].
    func testFiveElementArrayDecodesAsMaybeImage() {
        let legacy: [Any] = [NSNumber(value: 100.0), NSDictionary(), NSNumber(value: true), NSNumber(value: 1),
                             NSNumber(value: Int(iTermBidiDirection.rightToLeft.rawValue))]
        let decoded = decodeArray(legacy)
        XCTAssertTrue(decoded.imageFound.boolValue)
        XCTAssertEqual(decoded.bidiDirection, .rightToLeft)
        XCTAssertTrue(decoded.rtlFound.boolValue)
        iTermMetadataRelease(decoded)
    }

    // MARK: - TLV encoding

    func testDataRoundTripPreservesImageFound() {
        for imageFound in [false, true] {
            var original = iTermMetadataDefault()
            original.imageFound = ObjCBool(imageFound)
            original.bidiDirection = .leftToRight
            let decoded = iTermMetadataDecodedFromData(iTermMetadataEncodeToData(original))
            XCTAssertEqual(decoded.imageFound.boolValue, imageFound)
            XCTAssertEqual(decoded.bidiDirection, .leftToRight)
            iTermMetadataRelease(decoded)
        }
    }

    // Data written before the field existed ends after the direction.
    func testDataWithoutTrailingImageFoundDecodesAsMaybeImage() {
        var source = iTermMetadataDefault()
        source.imageFound = ObjCBool(false)
        source.bidiDirection = .rightToLeft
        let fullData = iTermMetadataEncodeToData(source)
        let legacyData = fullData.subdata(in: 0..<(fullData.count - 1))
        let decoded = iTermMetadataDecodedFromData(legacyData)
        XCTAssertTrue(decoded.imageFound.boolValue)
        XCTAssertEqual(decoded.bidiDirection, .rightToLeft)
        iTermMetadataRelease(decoded)
    }

    func testMetadataArrayFromDataCarriesImageFound() {
        var source = iTermMetadataDefault()
        source.imageFound = ObjCBool(true)
        guard let array = iTermMetadataArrayFromData(iTermMetadataEncodeToData(source)) else {
            return XCTFail("decode returned nil")
        }
        XCTAssertEqual((array[5] as? NSNumber)?.boolValue, true)
    }

    // MARK: - Combining metadata

    func testAppendingOrsImageFound() {
        var lhs = iTermMetadataDefault()
        var rhs = iTermMetadataDefault()
        rhs.imageFound = ObjCBool(true)
        var immutableRHS = iTermMetadataMakeImmutable(rhs)
        iTermMetadataAppend(&lhs, 10, &immutableRHS, 10)
        XCTAssertTrue(lhs.imageFound.boolValue, "joining a line with an image must keep the flag")

        var noImage = iTermMetadataMakeImmutable(iTermMetadataDefault())
        iTermMetadataAppend(&lhs, 20, &noImage, 10)
        XCTAssertTrue(lhs.imageFound.boolValue, "appending a line without an image must not clear the flag")
    }

    func testCopyingSubrangeKeepsImageFound() {
        var source = iTermMetadataDefault()
        source.imageFound = ObjCBool(true)
        var immutable = iTermMetadataMakeImmutable(source)
        var copy = iTermMetadata()
        iTermMetadataInitCopyingSubrange(&copy, &immutable, 5, 5)
        XCTAssertTrue(copy.imageFound.boolValue)
        iTermMetadataRelease(copy)
    }

    func testResetClearsImageFound() {
        var metadata = iTermMetadataDefault()
        metadata.imageFound = ObjCBool(true)
        iTermMetadataReset(&metadata)
        XCTAssertFalse(metadata.imageFound.boolValue)
    }

    // MARK: - Line block metadata entries

    private func encodedEntry(imageFound: Bool) -> [Any] {
        let array = LineBlockMetadataArray(capacity: 1, useDWCCache: false)
        array.increaseCapacity(to: 1)
        var metadata = iTermMetadataDefault()
        metadata.imageFound = ObjCBool(imageFound)
        array.append(iTermMetadataMakeImmutable(metadata), continuation: screen_char_t())
        let encoded = array.encodedArray()
        XCTAssertEqual(encoded.count, 1)
        return encoded[0] as! [Any]
    }

    private func decodeEntry(_ components: [Any]) -> LineBlockMetadataArray {
        let array = LineBlockMetadataArray(capacity: 1, useDWCCache: false)
        array.increaseCapacity(to: 1)
        array.setEntry(0, fromComponents: components, migrationIndex: nil, startOffset: 0, length: 0)
        return array
    }

    func testLineBlockEntryRoundTripPreservesImageFound() {
        for imageFound in [false, true] {
            let restored = decodeEntry(encodedEntry(imageFound: imageFound))
            XCTAssertEqual(restored.immutableLineMetadata(at: 0).imageFound.boolValue, imageFound)
        }
    }

    // Before imageFound an entry had five continuation scalars and five metadata scalars.
    func testLineBlockEntryFromPreviousReleaseDecodesAsMaybeImage() {
        let entry = Array(encodedEntry(imageFound: false).prefix(10))
        let restored = decodeEntry(entry)
        XCTAssertTrue(restored.immutableLineMetadata(at: 0).imageFound.boolValue)
    }

    // MARK: - Grid line info

    func testLineInfoEncodedMetadataRoundTripsImageFound() {
        let lineInfo = VT100LineInfo(width: 80)!
        lineInfo.mayContainImage = true
        let restored = VT100LineInfo(width: 80)!
        restored.decodeMetadataArray(lineInfo.encodedMetadata())
        XCTAssertTrue(restored.mayContainImage)
    }

    func testLineInfoCopyKeepsImageFound() {
        let lineInfo = VT100LineInfo(width: 80)!
        lineInfo.mayContainImage = true
        let copy = lineInfo.copy() as! VT100LineInfo
        XCTAssertTrue(copy.mayContainImage)
    }

    // MARK: - Line buffer

    /// A line popped back out of history keeps the flag, so the grid knows it holds an image
    /// without scanning it.
    func testLinePoppedFromLineBufferKeepsImageFound() {
        let lineBuffer = LineBuffer()
        let width: Int32 = 10
        var chars = [screen_char_t](repeating: screen_char_t(), count: Int(width))
        for i in 0..<chars.count {
            chars[i].code = unichar(UInt8(ascii: "a"))
        }
        var metadata = iTermMetadataDefault()
        metadata.imageFound = ObjCBool(true)
        var continuation = screen_char_t()
        continuation.code = unichar(EOL_HARD)
        lineBuffer.appendLine(&chars,
                              length: width,
                              partial: false,
                              width: width,
                              metadata: iTermMetadataMakeImmutable(metadata),
                              continuation: continuation)

        var popped = [screen_char_t](repeating: screen_char_t(), count: Int(width) + 1)
        var eol: Int32 = 0
        var poppedMetadata = iTermImmutableMetadataDefault()
        var poppedContinuation = screen_char_t()
        XCTAssertTrue(lineBuffer.popAndCopyLastLine(into: &popped,
                                                    width: width,
                                                    includesEndOfLine: &eol,
                                                    metadata: &poppedMetadata,
                                                    continuation: &poppedContinuation))
        XCTAssertTrue(poppedMetadata.imageFound.boolValue)
    }

    /// Popping part of a raw line longer than the width (one wrapped line of it) keeps the flag.
    func testPartOfLongLinePoppedFromLineBufferKeepsImageFound() {
        let lineBuffer = LineBuffer()
        let width: Int32 = 10
        var chars = [screen_char_t](repeating: screen_char_t(), count: 25)
        for i in 0..<chars.count {
            chars[i].code = unichar(UInt8(ascii: "a"))
        }
        var metadata = iTermMetadataDefault()
        metadata.imageFound = ObjCBool(true)
        var continuation = screen_char_t()
        continuation.code = unichar(EOL_HARD)
        lineBuffer.appendLine(&chars,
                              length: Int32(chars.count),
                              partial: false,
                              width: width,
                              metadata: iTermMetadataMakeImmutable(metadata),
                              continuation: continuation)

        var popped = [screen_char_t](repeating: screen_char_t(), count: Int(width) + 1)
        var eol: Int32 = 0
        var poppedMetadata = iTermImmutableMetadataDefault()
        var poppedContinuation = screen_char_t()
        XCTAssertTrue(lineBuffer.popAndCopyLastLine(into: &popped,
                                                    width: width,
                                                    includesEndOfLine: &eol,
                                                    metadata: &poppedMetadata,
                                                    continuation: &poppedContinuation))
        XCTAssertTrue(poppedMetadata.imageFound.boolValue)
        XCTAssertEqual(lineBuffer.numLines(withWidth: width), 2, "premise: only the last wrapped line was popped")
    }

    // MARK: - Old history on the grid

    /// A line buffer with one line whose first four cells are image `code` (or text if `code` is
    /// nil), with metadata decoded from an array saved before imageFound existed.
    private func lineBufferWithOldLine(width: Int32, code: unichar?) -> LineBuffer {
        let lineBuffer = LineBuffer()
        var chars = [screen_char_t](repeating: screen_char_t(), count: Int(width))
        for i in 0..<4 {
            if let code {
                chars[i].image = 1
                chars[i].code = code
            } else {
                chars[i].code = unichar(UInt8(ascii: "a"))
            }
        }
        let legacy: [Any] = [NSNumber(value: 100.0), NSDictionary(), NSNumber(value: false), NSNumber(value: 0),
                             NSNumber(value: 0)]
        let metadata = decodeArray(legacy)
        var continuation = screen_char_t()
        continuation.code = unichar(EOL_HARD)
        lineBuffer.appendLine(&chars,
                              length: width,
                              partial: false,
                              width: width,
                              metadata: iTermMetadataMakeImmutable(metadata),
                              continuation: continuation)
        iTermMetadataRelease(metadata)
        return lineBuffer
    }

    private func makeGrid(width: Int32) -> VT100Grid {
        return VT100Grid(size: VT100GridSize(width: width, height: 4), delegate: nil)!
    }

    /// Making the window taller pulls history back onto the screen. In a session restored from
    /// an older build, the release scan must still see the image there, or it releases it while
    /// it's visible.
    func testImageLineFromOldHistoryRestoredOntoGridIsSeen() {
        let width: Int32 = 10
        let code: unichar = 42
        let lineBuffer = lineBufferWithOldLine(width: width, code: code)
        let grid = makeGrid(width: width)
        grid.restoreScreen(from: lineBuffer, withDefaultChar: grid.defaultChar, maxLinesToRestore: 4)
        XCTAssertEqual(lineBuffer.numLines(withWidth: width), 0, "premise: the line should have left history")
        XCTAssertTrue(grid.imageCodesOnScreen().contains(Int(code)))
    }

    func testImageLineFromOldHistoryScrolledDownOntoGridIsSeen() {
        let width: Int32 = 10
        let code: unichar = 42
        let lineBuffer = lineBufferWithOldLine(width: width, code: code)
        let grid = makeGrid(width: width)
        XCTAssertEqual(grid.scrollWholeScreenDown(byLines: 1, poppingFrom: lineBuffer), 1,
                       "premise: one line should come back from history")
        XCTAssertTrue(grid.imageCodesOnScreen().contains(Int(code)))
    }

    /// An old line without an image is scanned the first time it's checked, and the flag is
    /// cleared then, so it's never scanned again.
    func testOldTextLineIsScannedOnceThenCleared() {
        let width: Int32 = 10
        let lineBuffer = lineBufferWithOldLine(width: width, code: nil)
        let grid = makeGrid(width: width)
        XCTAssertEqual(grid.scrollWholeScreenDown(byLines: 1, poppingFrom: lineBuffer), 1,
                       "premise: one line should come back from history")
        XCTAssertTrue(grid.lineInfo(atLineNumber: 0).mayContainImage, "premise: an old line may hold an image")
        XCTAssertEqual(grid.imageCodesOnScreen().count, 0)
        XCTAssertFalse(grid.lineInfo(atLineNumber: 0).mayContainImage)
    }

    /// Resetting timestamps leaves the cells alone, so it must not forget that a line may hold
    /// an image.
    func testResettingTimestampsKeepsMayContainImage() {
        let grid = makeGrid(width: 10)
        grid.setMayContainImage(true, onLine: 1)
        grid.resetTimestamps()
        XCTAssertTrue(grid.lineInfo(atLineNumber: 1).mayContainImage)
        XCTAssertFalse(grid.lineInfo(atLineNumber: 0).mayContainImage)
    }

    // MARK: - Screen char arrays

    private func screenCharArray(imageFound: Bool) -> ScreenCharArray {
        var chars = [screen_char_t](repeating: screen_char_t(), count: 4)
        for i in 0..<chars.count {
            chars[i].code = unichar(UInt8(ascii: "a"))
        }
        var metadata = iTermMetadataDefault()
        metadata.imageFound = ObjCBool(imageFound)
        var continuation = screen_char_t()
        continuation.code = unichar(EOL_HARD)
        let data = chars.withUnsafeBufferPointer { Data(buffer: $0) }
        return ScreenCharArray(data: data,
                               metadata: iTermMetadataMakeImmutable(metadata),
                               continuation: continuation)
    }

    func testAppendingScreenCharArraysOrsImageFound() {
        let withImage = screenCharArray(imageFound: true)
        let without = screenCharArray(imageFound: false)
        XCTAssertTrue(withImage.appending(without).metadata.imageFound.boolValue)
        XCTAssertTrue(without.appending(withImage).metadata.imageFound.boolValue)
        XCTAssertFalse(without.appending(without).metadata.imageFound.boolValue)
    }
}
