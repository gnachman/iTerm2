//
//  BidiDirectionMetadataCompatTests.swift
//  ModernTests
//
//  The per-line bidi direction (from SCP) is a fifth trailing scalar in the
//  array encoding of line metadata and a trailing int in the TLV encoding.
//  Both are optional. Data from before the field existed decodes with the
//  default, and a build from before it existed skips it: the array decoders
//  read by index, the line block decoder scans forward to the @[] delimiter
//  that precedes its bidi block, and the TLV decoders stop after the fields
//  they know. These tests cover a new build reading old data, and stand in for
//  the old readers by checking that trailing data a reader does not know is
//  ignored, which is the property those readers rely on.
//

import XCTest
@testable import iTerm2SharedARC

final class BidiDirectionMetadataCompatTests: XCTestCase {
    private let directions: [iTermBidiDirection] = [.default, .leftToRight, .rightToLeft]

    private func decodeArray(_ array: [Any]) -> iTermMetadata {
        var decoded = iTermMetadata()
        iTermMetadataInitFromArray(&decoded, array)
        return decoded
    }

    // MARK: - Array encoding

    func testArrayRoundTripPreservesDirection() {
        for direction in directions {
            var original = iTermMetadataDefault()
            original.rtlFound = ObjCBool(true)
            original.bidiDirection = direction
            let encoded = iTermMetadataEncodeToArray(original)
            XCTAssertEqual(encoded.count, 5)
            let decoded = decodeArray(encoded)
            XCTAssertEqual(decoded.bidiDirection, direction)
            XCTAssertTrue(decoded.rtlFound.boolValue)
            iTermMetadataRelease(decoded)
        }
    }

    // 3.7.x wrote [timestamp, eaDict, rtlFound, lineAttribute].
    func testFourElementArrayFromPreviousReleaseDecodesWithDefaultDirection() {
        let legacy: [Any] = [NSNumber(value: 100.0), NSDictionary(), NSNumber(value: true), NSNumber(value: 1)]
        let decoded = decodeArray(legacy)
        XCTAssertEqual(decoded.bidiDirection, .default)
        XCTAssertTrue(decoded.rtlFound.boolValue)
        XCTAssertEqual(decoded.lineAttribute.rawValue, 1)
        XCTAssertEqual(decoded.timestamp, 100.0, accuracy: 0.001)
        iTermMetadataRelease(decoded)
    }

    // 3.6.x wrote [timestamp, eaDict, rtlFound].
    func testThreeElementArrayFromOlderReleaseDecodesWithDefaultDirection() {
        let legacy: [Any] = [NSNumber(value: 100.0), NSDictionary(), NSNumber(value: true)]
        let decoded = decodeArray(legacy)
        XCTAssertEqual(decoded.bidiDirection, .default)
        XCTAssertTrue(decoded.rtlFound.boolValue)
        iTermMetadataRelease(decoded)
    }

    // A reader must ignore trailing elements it does not know. That is what a
    // 3.7.x build does with our fifth element, and what we will do with a sixth.
    func testExtraTrailingArrayElementsAreIgnored() {
        var original = iTermMetadataDefault()
        original.bidiDirection = .rightToLeft
        var encoded = iTermMetadataEncodeToArray(original)
        encoded.append(NSNumber(value: 42))
        encoded.append("future")
        let decoded = decodeArray(encoded)
        XCTAssertEqual(decoded.bidiDirection, .rightToLeft)
        iTermMetadataRelease(decoded)
    }

    // MARK: - TLV encoding (DVR frames, line info cache)

    func testDataRoundTripPreservesDirection() {
        for direction in directions {
            var original = iTermMetadataDefault()
            original.bidiDirection = direction
            original.rtlFound = ObjCBool(true)
            let decoded = iTermMetadataDecodedFromData(iTermMetadataEncodeToData(original))
            XCTAssertEqual(decoded.bidiDirection, direction)
            XCTAssertTrue(decoded.rtlFound.boolValue)
            iTermMetadataRelease(decoded)
        }
    }

    // Data written before the field existed ends after lineAttribute.
    func testDataWithoutTrailingDirectionDecodesWithDefault() {
        var source = iTermMetadataDefault()
        source.timestamp = 42.0
        source.rtlFound = ObjCBool(true)
        source.bidiDirection = .rightToLeft
        let fullData = iTermMetadataEncodeToData(source)
        let legacyData = fullData.subdata(in: 0..<(fullData.count - MemoryLayout<Int32>.size))
        let decoded = iTermMetadataDecodedFromData(legacyData)
        XCTAssertEqual(decoded.bidiDirection, .default)
        XCTAssertTrue(decoded.rtlFound.boolValue)
        XCTAssertEqual(decoded.timestamp, 42.0, accuracy: 0.001)
        iTermMetadataRelease(decoded)
    }

    // A TLV reader stops after the fields it knows, so a 3.7.x build reading
    // our data simply never looks at the direction. Stand in for it by giving
    // our reader more trailing bytes than it knows about.
    func testDataWithExtraTrailingBytesDecodes() {
        var source = iTermMetadataDefault()
        source.bidiDirection = .leftToRight
        var data = iTermMetadataEncodeToData(source)
        var future: Int32 = 7
        data.append(Data(bytes: &future, count: MemoryLayout<Int32>.size))
        let decoded = iTermMetadataDecodedFromData(data)
        XCTAssertEqual(decoded.bidiDirection, .leftToRight)
        iTermMetadataRelease(decoded)
    }

    // The DVR path decodes TLV data into the array form.
    func testMetadataArrayFromDataCarriesDirection() {
        var source = iTermMetadataDefault()
        source.bidiDirection = .rightToLeft
        guard let array = iTermMetadataArrayFromData(iTermMetadataEncodeToData(source)) else {
            return XCTFail("decode returned nil")
        }
        XCTAssertEqual(array.count, 5)
        XCTAssertEqual((array[4] as? NSNumber)?.intValue, Int(iTermBidiDirection.rightToLeft.rawValue))
    }

    // MARK: - Line block metadata entries

    private func makeArray(direction: iTermBidiDirection) -> LineBlockMetadataArray {
        let array = LineBlockMetadataArray(capacity: 1, useDWCCache: false)
        array.increaseCapacity(to: 1)
        var metadata = iTermMetadataDefault()
        metadata.rtlFound = ObjCBool(true)
        metadata.bidiDirection = direction
        array.append(iTermMetadataMakeImmutable(metadata), continuation: screen_char_t())
        return array
    }

    // The single encoded entry of a one-line array.
    private func encodedEntry(direction: iTermBidiDirection) -> [Any] {
        let encoded = makeArray(direction: direction).encodedArray()
        XCTAssertEqual(encoded.count, 1)
        return encoded[0] as! [Any]
    }

    private func decodeEntry(_ components: [Any]) -> LineBlockMetadataArray {
        let array = LineBlockMetadataArray(capacity: 1, useDWCCache: false)
        array.increaseCapacity(to: 1)
        array.setEntry(0, fromComponents: components, migrationIndex: nil, startOffset: 0, length: 0)
        return array
    }

    func testLineBlockEntryRoundTripPreservesDirection() {
        for direction in directions {
            let restored = decodeEntry(encodedEntry(direction: direction))
            let metadata = restored.immutableLineMetadata(at: 0)
            XCTAssertEqual(metadata.bidiDirection, direction)
            XCTAssertTrue(metadata.rtlFound.boolValue)
        }
    }

    // An entry is five continuation scalars, then the metadata scalars, then an
    // optional @[] delimiter and bidi dictionary. Every reader since 3.6.11
    // scans forward to the delimiter, so scalars it does not know are skipped.
    // Simulate that reader on our output by adding a scalar it will not know.
    func testLineBlockEntryWithUnknownScalarBeforeDelimiterStillFindsBidiBlock() {
        let savedBidi = iTermPreferences.bool(forKey: kPreferenceKeyBidi)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        defer { iTermPreferences.setBool(savedBidi, forKey: kPreferenceKeyBidi) }

        var entry = encodedEntry(direction: .rightToLeft)
        // 5 continuation scalars + [timestamp, eaDict, rtlFound, lineAttribute, bidiDirection].
        XCTAssertEqual(entry.count, 10)
        entry.append(NSNumber(value: 99))  // a scalar from some later version
        entry.append([Any]())              // the delimiter
        entry.append(["lut": [Int32](), "rtlIndexes": [NSValue](), "mirroredIndexes": [NSValue](), "paragraphIsRTL": true])
        let restored = decodeEntry(entry)
        XCTAssertEqual(restored.immutableLineMetadata(at: 0).bidiDirection, .rightToLeft)
        XCTAssertNotNil(restored.bidiInfo(at: 0), "the bidi block after the delimiter must still be found")
    }

    // 3.7.x entries: four metadata scalars, then the delimiter and bidi block.
    func testLineBlockEntryFromPreviousReleaseDecodesWithDefaultDirection() {
        let savedBidi = iTermPreferences.bool(forKey: kPreferenceKeyBidi)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        defer { iTermPreferences.setBool(savedBidi, forKey: kPreferenceKeyBidi) }

        var entry = Array(encodedEntry(direction: .rightToLeft).prefix(9))
        entry.append([Any]())
        entry.append(["lut": [Int32](), "rtlIndexes": [NSValue](), "mirroredIndexes": [NSValue](), "paragraphIsRTL": false])
        let restored = decodeEntry(entry)
        let metadata = restored.immutableLineMetadata(at: 0)
        XCTAssertEqual(metadata.bidiDirection, .default)
        XCTAssertTrue(metadata.rtlFound.boolValue)
        XCTAssertNotNil(restored.bidiInfo(at: 0))
    }

    // 3.6.11 entries: rtlFound is the last metadata scalar and the delimiter
    // sits exactly where lineAttribute would be. Neither lineAttribute nor the
    // direction may consume the delimiter.
    func testLineBlockEntryFrom3611DecodesWithDefaultDirection() {
        let savedBidi = iTermPreferences.bool(forKey: kPreferenceKeyBidi)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyBidi)
        defer { iTermPreferences.setBool(savedBidi, forKey: kPreferenceKeyBidi) }

        var entry = Array(encodedEntry(direction: .rightToLeft).prefix(8))
        entry.append([Any]())
        entry.append(["lut": [Int32](), "rtlIndexes": [NSValue](), "mirroredIndexes": [NSValue](), "paragraphIsRTL": false])
        let restored = decodeEntry(entry)
        let metadata = restored.immutableLineMetadata(at: 0)
        XCTAssertEqual(metadata.bidiDirection, .default)
        XCTAssertEqual(metadata.lineAttribute, .singleWidth)
        XCTAssertTrue(metadata.rtlFound.boolValue)
        XCTAssertNotNil(restored.bidiInfo(at: 0))
    }

    // MARK: - Grid line info (arrangements)

    func testLineInfoEncodedMetadataRoundTripsDirection() {
        let lineInfo = VT100LineInfo(width: 80)!
        lineInfo.setRTLFound(true)
        lineInfo.setBidiDirection(.rightToLeft)
        let restored = VT100LineInfo(width: 80)!
        restored.decodeMetadataArray(lineInfo.encodedMetadata())
        XCTAssertEqual(restored.bidiDirection(), .rightToLeft)
        XCTAssertTrue(restored.rtlFound())
    }
}
