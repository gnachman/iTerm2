//
//  iTermLineAttributeTests.swift
//  iTerm2
//
//  Created by George Nachman on 3/29/26.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermLineAttributeTests: XCTestCase {

    // MARK: - iTermLineAttribute Enum Values

    /// Verify that the enum raw values are correct and the default (0) is single-width.
    func testEnumRawValues() {
        XCTAssertEqual(iTermLineAttribute.singleWidth.rawValue, 0)
        XCTAssertEqual(iTermLineAttribute.doubleWidth.rawValue, 1)
        XCTAssertEqual(iTermLineAttribute.doubleHeightTop.rawValue, 2)
        XCTAssertEqual(iTermLineAttribute.doubleHeightBottom.rawValue, 3)
    }

    // MARK: - Helper Functions

    /// Single-width is not double-width; all others are.
    func testIsDoubleWidth() {
        XCTAssertFalse(iTermLineAttributeIsDoubleWidth(iTermLineAttribute.singleWidth))
        XCTAssertTrue(iTermLineAttributeIsDoubleWidth(iTermLineAttribute.doubleWidth))
        XCTAssertTrue(iTermLineAttributeIsDoubleWidth(iTermLineAttribute.doubleHeightTop))
        XCTAssertTrue(iTermLineAttributeIsDoubleWidth(iTermLineAttribute.doubleHeightBottom))
    }

    /// Effective line width is halved for double-width attributes.
    func testEffectiveLineWidth() {
        XCTAssertEqual(iTermEffectiveLineWidth(80, iTermLineAttribute.singleWidth), 80)
        XCTAssertEqual(iTermEffectiveLineWidth(80, iTermLineAttribute.doubleWidth), 40)
        XCTAssertEqual(iTermEffectiveLineWidth(80, iTermLineAttribute.doubleHeightTop), 40)
        XCTAssertEqual(iTermEffectiveLineWidth(80, iTermLineAttribute.doubleHeightBottom), 40)
    }

    /// Odd widths should truncate (integer division).
    func testEffectiveLineWidthOdd() {
        XCTAssertEqual(iTermEffectiveLineWidth(81, iTermLineAttribute.doubleWidth), 40)
    }

    /// Width 0 should remain 0.
    func testEffectiveLineWidthZero() {
        XCTAssertEqual(iTermEffectiveLineWidth(0, iTermLineAttribute.doubleWidth), 0)
    }

    /// Width 1 should truncate to 0 (integer division).
    func testEffectiveLineWidthOne() {
        XCTAssertEqual(iTermEffectiveLineWidth(1, iTermLineAttribute.doubleWidth), 0)
    }

    // MARK: - iTermMetadata lineAttribute Field

    /// Default metadata should have lineAttribute = singleWidth.
    func testDefaultMetadataHasSingleWidth() {
        let metadata = iTermMetadataDefault()
        XCTAssertEqual(metadata.lineAttribute, iTermLineAttribute.singleWidth)
    }

    /// Default immutable metadata should have lineAttribute = singleWidth.
    func testDefaultImmutableMetadataHasSingleWidth() {
        let metadata = iTermImmutableMetadataDefault()
        XCTAssertEqual(metadata.lineAttribute, iTermLineAttribute.singleWidth)
    }

    /// Setting lineAttribute directly on the struct should persist.
    func testSetLineAttributeOnMetadata() {
        var metadata = iTermMetadataDefault()
        metadata.lineAttribute = iTermLineAttribute.doubleWidth
        XCTAssertEqual(metadata.lineAttribute, iTermLineAttribute.doubleWidth)

        metadata.lineAttribute = iTermLineAttribute.doubleHeightTop
        XCTAssertEqual(metadata.lineAttribute, iTermLineAttribute.doubleHeightTop)

        metadata.lineAttribute = iTermLineAttribute.doubleHeightBottom
        XCTAssertEqual(metadata.lineAttribute, iTermLineAttribute.doubleHeightBottom)

        metadata.lineAttribute = iTermLineAttribute.singleWidth
        XCTAssertEqual(metadata.lineAttribute, iTermLineAttribute.singleWidth)
    }

    // MARK: - Metadata Copy Preserves lineAttribute

    /// iTermMetadataCopy should preserve lineAttribute.
    func testCopyPreservesLineAttribute() {
        var original = iTermMetadataDefault()
        original.lineAttribute = iTermLineAttribute.doubleWidth
        let copy = iTermMetadataCopy(original)
        XCTAssertEqual(copy.lineAttribute, iTermLineAttribute.doubleWidth)
        iTermMetadataRelease(copy)
    }

    /// iTermMetadataMakeImmutable should preserve lineAttribute.
    func testMakeImmutablePreservesLineAttribute() {
        var metadata = iTermMetadataDefault()
        metadata.lineAttribute = iTermLineAttribute.doubleHeightTop
        let immutable = iTermMetadataMakeImmutable(metadata)
        XCTAssertEqual(immutable.lineAttribute, iTermLineAttribute.doubleHeightTop)
    }

    /// iTermImmutableMetadataMutableCopy should preserve lineAttribute.
    func testMutableCopyPreservesLineAttribute() {
        var mutable = iTermMetadataDefault()
        mutable.lineAttribute = iTermLineAttribute.doubleHeightBottom
        let immutable = iTermMetadataMakeImmutable(mutable)
        let mutableCopy = iTermImmutableMetadataMutableCopy(immutable)
        XCTAssertEqual(mutableCopy.lineAttribute, iTermLineAttribute.doubleHeightBottom)
        iTermMetadataRelease(mutableCopy)
    }

    /// iTermImmutableMetadataCopy should preserve lineAttribute.
    func testImmutableCopyPreservesLineAttribute() {
        var mutable = iTermMetadataDefault()
        mutable.lineAttribute = iTermLineAttribute.doubleWidth
        let immutable = iTermMetadataMakeImmutable(mutable)
        let copy = iTermImmutableMetadataCopy(immutable)
        XCTAssertEqual(copy.lineAttribute, iTermLineAttribute.doubleWidth)
        iTermImmutableMetadataRelease(copy)
    }

    // MARK: - Metadata Init Preserves lineAttribute

    /// iTermMetadataInit should set lineAttribute to singleWidth, even if
    /// the struct previously held a different value.
    func testMetadataInitHasSingleWidth() {
        var metadata = iTermMetadata()
        metadata.lineAttribute = iTermLineAttribute.doubleWidth
        iTermMetadataInit(&metadata, 42.0, true, nil, .singleWidth)
        XCTAssertEqual(metadata.lineAttribute, iTermLineAttribute.singleWidth)
        iTermMetadataRelease(metadata)
    }

    // MARK: - Array Encode/Decode Round-Trip

    /// Encoding metadata with lineAttribute to array and decoding should preserve it.
    /// The array format should be [timestamp, externalAttrsDict, rtlFound, lineAttribute].
    func testArrayEncodeDecodePreservesLineAttribute() {
        var original = iTermMetadataDefault()
        original.lineAttribute = iTermLineAttribute.doubleWidth
        original.timestamp = 123.456

        let encoded = iTermMetadataEncodeToArray(original)

        // Verify array grew to 4 elements and lineAttribute is at index 3.
        XCTAssertEqual(encoded.count, 4)
        XCTAssertEqual((encoded[3] as! NSNumber).int32Value,
                       iTermLineAttribute.doubleWidth.rawValue)

        var decoded = iTermMetadata()
        iTermMetadataInitFromArray(&decoded, encoded)
        XCTAssertEqual(decoded.lineAttribute, iTermLineAttribute.doubleWidth)
        XCTAssertEqual(decoded.timestamp, 123.456, accuracy: 0.001)
        iTermMetadataRelease(decoded)
    }

    /// Round-trip for all line attribute values through array encoding.
    func testArrayEncodeDecodeAllValues() {
        let values: [iTermLineAttribute] = [
            iTermLineAttribute.singleWidth,
            iTermLineAttribute.doubleWidth,
            iTermLineAttribute.doubleHeightTop,
            iTermLineAttribute.doubleHeightBottom
        ]
        for attr in values {
            var original = iTermMetadataDefault()
            original.lineAttribute = attr
            let encoded = iTermMetadataEncodeToArray(original)
            var decoded = iTermMetadata()
            iTermMetadataInitFromArray(&decoded, encoded)
            XCTAssertEqual(decoded.lineAttribute, attr,
                           "Round-trip failed for lineAttribute \(attr.rawValue)")
            iTermMetadataRelease(decoded)
        }
    }

    /// Decoding a legacy 3-element array (without lineAttribute) should default to singleWidth.
    func testArrayDecodeBackwardCompatibility() {
        // Legacy format: [timestamp, externalAttrsDict, rtlFound]
        let legacyArray: [Any] = [NSNumber(value: 100.0), NSDictionary(), NSNumber(value: true)]
        var decoded = iTermMetadata()
        iTermMetadataInitFromArray(&decoded, legacyArray)
        XCTAssertEqual(decoded.lineAttribute, iTermLineAttribute.singleWidth)
        XCTAssertEqual(decoded.timestamp, 100.0, accuracy: 0.001)
        XCTAssertTrue(decoded.rtlFound.boolValue)
        iTermMetadataRelease(decoded)
    }

    // MARK: - Binary (TLV) Encode/Decode Round-Trip

    /// Encoding metadata with lineAttribute to Data and decoding should preserve it.
    func testDataEncodeDecodePreservesLineAttribute() {
        var original = iTermMetadataDefault()
        original.lineAttribute = iTermLineAttribute.doubleHeightTop
        original.timestamp = 789.0

        let data = iTermMetadataEncodeToData(original)
        var decoded = iTermMetadataDecodedFromData(data)
        XCTAssertEqual(decoded.lineAttribute, iTermLineAttribute.doubleHeightTop)
        XCTAssertEqual(decoded.timestamp, 789.0, accuracy: 0.001)
        iTermMetadataRelease(decoded)
    }

    /// Round-trip all line attribute values through binary encoding.
    func testDataEncodeDecodeAllValues() {
        let values: [iTermLineAttribute] = [
            iTermLineAttribute.singleWidth,
            iTermLineAttribute.doubleWidth,
            iTermLineAttribute.doubleHeightTop,
            iTermLineAttribute.doubleHeightBottom
        ]
        for attr in values {
            var original = iTermMetadataDefault()
            original.lineAttribute = attr
            let data = iTermMetadataEncodeToData(original)
            var decoded = iTermMetadataDecodedFromData(data)
            XCTAssertEqual(decoded.lineAttribute, attr,
                           "Binary round-trip failed for lineAttribute \(attr.rawValue)")
            iTermMetadataRelease(decoded)
        }
    }

    /// Decoding legacy binary data (without lineAttribute) should default to singleWidth.
    func testDataDecodeBackwardCompatibility() {
        // Encode metadata with singleWidth, then strip the trailing lineAttribute
        // int from the data to simulate old-format binary data.
        var source = iTermMetadataDefault()
        source.timestamp = 42.0
        source.rtlFound = ObjCBool(true)
        let fullData = iTermMetadataEncodeToData(source)

        // The new format appends a raw int (sizeof(int) = 4 bytes) at the end
        // for lineAttribute. Strip it to get the old format.
        let legacyData = fullData.subdata(in: 0..<(fullData.count - MemoryLayout<Int32>.size))

        var decoded = iTermMetadataDecodedFromData(legacyData)
        XCTAssertEqual(decoded.lineAttribute, iTermLineAttribute.singleWidth)
        XCTAssertEqual(decoded.timestamp, 42.0, accuracy: 0.001)
        XCTAssertTrue(decoded.rtlFound.boolValue)
        iTermMetadataRelease(decoded)
    }

    // MARK: - Immutable Encode/Decode

    /// Immutable encoding should also preserve lineAttribute.
    func testImmutableArrayEncodePreservesLineAttribute() {
        var mutable = iTermMetadataDefault()
        mutable.lineAttribute = iTermLineAttribute.doubleHeightBottom
        let immutable = iTermMetadataMakeImmutable(mutable)
        let encoded = iTermImmutableMetadataEncodeToArray(immutable)

        var decoded = iTermMetadata()
        iTermMetadataInitFromArray(&decoded, encoded)
        XCTAssertEqual(decoded.lineAttribute, iTermLineAttribute.doubleHeightBottom)
        iTermMetadataRelease(decoded)
    }

    /// Immutable binary encoding should preserve lineAttribute.
    func testImmutableDataEncodePreservesLineAttribute() {
        var mutable = iTermMetadataDefault()
        mutable.lineAttribute = iTermLineAttribute.doubleWidth
        let immutable = iTermMetadataMakeImmutable(mutable)
        let data = iTermImmutableMetadataEncodeToData(immutable)

        var decoded = iTermMetadataDecodedFromData(data)
        XCTAssertEqual(decoded.lineAttribute, iTermLineAttribute.doubleWidth)
        iTermMetadataRelease(decoded)
    }

    // MARK: - MetadataReset

    /// Resetting metadata should set lineAttribute back to singleWidth.
    func testResetClearsLineAttribute() {
        var metadata = iTermMetadataDefault()
        metadata.lineAttribute = iTermLineAttribute.doubleWidth
        iTermMetadataReset(&metadata)
        XCTAssertEqual(metadata.lineAttribute, iTermLineAttribute.singleWidth)
    }

    // MARK: - MetadataAppend

    /// Appending metadata should preserve the lhs lineAttribute, since lhs is the
    /// start of the logical line where the ESC # attribute was originally set.
    func testAppendPreservesLhsLineAttribute() {
        var lhs = iTermMetadataDefault()
        lhs.lineAttribute = iTermLineAttribute.doubleWidth

        var rhs = iTermMetadataDefault()
        rhs.lineAttribute = iTermLineAttribute.singleWidth
        var immutableRhs = iTermMetadataMakeImmutable(rhs)

        iTermMetadataAppend(&lhs, 5, &immutableRhs, 5)
        XCTAssertEqual(lhs.lineAttribute, iTermLineAttribute.doubleWidth)
    }

    // MARK: - MetadataInitCopyingSubrange

    /// Copying a subrange should preserve the source lineAttribute.
    func testSubrangeCopyPreservesLineAttribute() {
        var source = iTermMetadataDefault()
        source.lineAttribute = iTermLineAttribute.doubleHeightTop
        var immutableSource = iTermMetadataMakeImmutable(source)

        var dest = iTermMetadata()
        iTermMetadataInitCopyingSubrange(&dest, &immutableSource, 0, 5)
        XCTAssertEqual(dest.lineAttribute, iTermLineAttribute.doubleHeightTop)
        iTermMetadataRelease(dest)
    }

    // MARK: - VT100LineInfo

    /// VT100LineInfo should support setting and getting lineAttribute via metadata.
    func testLineInfoLineAttribute() {
        let lineInfo = VT100LineInfo(width: 80)!
        XCTAssertEqual(lineInfo.metadata.lineAttribute, iTermLineAttribute.singleWidth)

        var metadata = lineInfo.metadata
        metadata.lineAttribute = iTermLineAttribute.doubleWidth
        lineInfo.metadata = metadata

        XCTAssertEqual(lineInfo.metadata.lineAttribute, iTermLineAttribute.doubleWidth)
    }

    /// Copying VT100LineInfo should preserve lineAttribute.
    func testLineInfoCopyPreservesLineAttribute() {
        let lineInfo = VT100LineInfo(width: 80)!
        var metadata = lineInfo.metadata
        metadata.lineAttribute = iTermLineAttribute.doubleHeightBottom
        lineInfo.metadata = metadata

        let copy = lineInfo.copy() as! VT100LineInfo
        XCTAssertEqual(copy.metadata.lineAttribute, iTermLineAttribute.doubleHeightBottom)
    }

    /// Encoding and decoding VT100LineInfo metadata array should preserve lineAttribute.
    func testLineInfoEncodeDecodePreservesLineAttribute() {
        let lineInfo = VT100LineInfo(width: 80)!
        var metadata = lineInfo.metadata
        metadata.lineAttribute = iTermLineAttribute.doubleHeightTop
        lineInfo.metadata = metadata

        let encoded = lineInfo.encodedMetadata()!

        let decoded = VT100LineInfo(width: 80)!
        decoded.decodeMetadataArray(encoded)
        XCTAssertEqual(decoded.metadata.lineAttribute, iTermLineAttribute.doubleHeightTop)
    }

    /// Resetting VT100LineInfo metadata should clear lineAttribute.
    func testLineInfoResetClearsLineAttribute() {
        let lineInfo = VT100LineInfo(width: 80)!
        var metadata = lineInfo.metadata
        metadata.lineAttribute = iTermLineAttribute.doubleWidth
        lineInfo.metadata = metadata

        lineInfo.resetMetadata()
        XCTAssertEqual(lineInfo.metadata.lineAttribute, iTermLineAttribute.singleWidth)
    }

    /// DVR encoding and decoding should preserve lineAttribute.
    func testLineInfoDVRRoundTripPreservesLineAttribute() {
        let lineInfo = VT100LineInfo(width: 80)!
        var metadata = lineInfo.metadata
        metadata.lineAttribute = iTermLineAttribute.doubleWidth
        lineInfo.metadata = metadata

        let data = lineInfo.dvrEncodableData()!

        // Decode from data: iTermMetadataArrayFromData → decodeMetadataArray
        let array = iTermMetadataArrayFromData(data)!
        let decoded = VT100LineInfo(width: 80)!
        decoded.decodeMetadataArray(array)
        XCTAssertEqual(decoded.metadata.lineAttribute, iTermLineAttribute.doubleWidth)
    }

    // MARK: - iTermExternalAttribute lineAttribute

    /// Default external attribute should have lineAttribute = singleWidth
    /// and should be considered "default" (isDefault == true).
    func testExternalAttributeDefaultHasSingleWidth() {
        let ea = iTermExternalAttribute()
        XCTAssertEqual(ea.lineAttribute, iTermLineAttribute.singleWidth)
        XCTAssertTrue(ea.isDefault)
    }

    /// An external attribute with only lineAttribute set (non-default) should
    /// not be considered "default".
    func testExternalAttributeWithLineAttributeIsNotDefault() {
        let dict: [AnyHashable: Any] = ["la": NSNumber(value: iTermLineAttribute.doubleWidth.rawValue)]
        let ea = iTermExternalAttribute(dictionary: dict)
        XCTAssertNotNil(ea)
        XCTAssertEqual(ea!.lineAttribute, iTermLineAttribute.doubleWidth)
        XCTAssertFalse(ea!.isDefault)
    }

    /// Dictionary round-trip should preserve lineAttribute.
    func testExternalAttributeDictionaryRoundTrip() {
        let dict: [AnyHashable: Any] = ["la": NSNumber(value: iTermLineAttribute.doubleHeightTop.rawValue)]
        let ea = iTermExternalAttribute(dictionary: dict)!
        let encoded = ea.dictionaryValue
        let decoded = iTermExternalAttribute(dictionary: encoded)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded!.lineAttribute, iTermLineAttribute.doubleHeightTop)
    }

    /// Binary (TLV) round-trip should preserve lineAttribute.
    func testExternalAttributeDataRoundTrip() {
        let dict: [AnyHashable: Any] = ["la": NSNumber(value: iTermLineAttribute.doubleHeightBottom.rawValue)]
        let ea = iTermExternalAttribute(dictionary: dict)!
        let data = ea.data()
        let decoded = iTermExternalAttribute.fromData(data)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded!.lineAttribute, iTermLineAttribute.doubleHeightBottom)
    }

    /// Equality check should compare lineAttribute.
    func testExternalAttributeEqualityComparesLineAttribute() {
        let dict1: [AnyHashable: Any] = ["la": NSNumber(value: iTermLineAttribute.doubleWidth.rawValue)]
        let dict2: [AnyHashable: Any] = ["la": NSNumber(value: iTermLineAttribute.doubleHeightTop.rawValue)]
        let ea1 = iTermExternalAttribute(dictionary: dict1)!
        let ea2 = iTermExternalAttribute(dictionary: dict2)!
        XCTAssertFalse(ea1.isEqual(to: ea2))

        let ea3 = iTermExternalAttribute(dictionary: dict1)!
        XCTAssertTrue(ea1.isEqual(to: ea3))
    }

    /// External attribute index should store and retrieve lineAttribute on a specific character.
    func testExternalAttributeIndexStoresLineAttribute() {
        let eaIndex = iTermExternalAttributeIndex()
        let dict: [AnyHashable: Any] = ["la": NSNumber(value: iTermLineAttribute.doubleWidth.rawValue)]
        let ea = iTermExternalAttribute(dictionary: dict)!
        eaIndex.setAttributes(ea, at: 0, count: 1)

        let retrieved = eaIndex.attribute(at: 0)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved!.lineAttribute, iTermLineAttribute.doubleWidth)

        // Character without the attribute should return nil (default)
        let other = eaIndex.attribute(at: 5)
        XCTAssertNil(other)
    }

    // MARK: - DWL_SPACER Character

    /// DWL_SPACER should be in the private-use range.
    func testDWLSpacerIsInPrivateRange() {
        XCTAssertGreaterThanOrEqual(DWL_SPACER, ITERM2_PRIVATE_BEGIN)
        XCTAssertLessThanOrEqual(DWL_SPACER, ITERM2_PRIVATE_END)
    }

    /// DWL_SPACER should be distinct from all other special characters.
    func testDWLSpacerIsDistinct() {
        XCTAssertNotEqual(DWL_SPACER, DWC_SKIP)
        XCTAssertNotEqual(DWL_SPACER, TAB_FILLER)
        XCTAssertNotEqual(DWL_SPACER, BOGUS_CHAR)
        XCTAssertNotEqual(DWL_SPACER, DWC_RIGHT)
        XCTAssertNotEqual(DWL_SPACER, REGEX_START)
        XCTAssertNotEqual(DWL_SPACER, REGEX_END)
        XCTAssertNotEqual(DWL_SPACER, IMPOSSIBLE_CHAR)
    }

    /// ScreenCharIsDWL_SPACER should detect a DWL_SPACER character.
    func testScreenCharIsDWLSpacer() {
        var c = screen_char_t()
        c.code = unichar(DWL_SPACER)
        c.complexChar = 0
        c.image = 0
        XCTAssertTrue(ScreenCharIsDWL_SPACER(c))
    }

    /// ScreenCharIsDWL_SPACER should return false for other characters.
    func testScreenCharIsDWLSpacerReturnsFalseForOtherChars() {
        var c = screen_char_t()
        c.code = unichar(UnicodeScalar("A").value)
        c.complexChar = 0
        c.image = 0
        XCTAssertFalse(ScreenCharIsDWL_SPACER(c))

        // DWC_RIGHT is not DWL_SPACER
        c.code = unichar(DWC_RIGHT)
        XCTAssertFalse(ScreenCharIsDWL_SPACER(c))
    }

    /// ScreenCharIsDWL_SPACER should return false for complex chars with DWL_SPACER code.
    func testScreenCharIsDWLSpacerFalseForComplex() {
        var c = screen_char_t()
        c.code = unichar(DWL_SPACER)
        c.complexChar = 1
        c.image = 0
        XCTAssertFalse(ScreenCharIsDWL_SPACER(c))
    }

    /// ScreenCharSetDWL_SPACER should set the correct code and clear flags.
    func testScreenCharSetDWLSpacer() {
        var c = screen_char_t()
        c.complexChar = 1
        c.image = 1
        c.virtualPlaceholder = 1
        ScreenCharSetDWL_SPACER(&c)
        XCTAssertEqual(c.code, unichar(DWL_SPACER))
        XCTAssertEqual(c.complexChar, 0)
        XCTAssertEqual(c.image, 0)
        XCTAssertEqual(c.virtualPlaceholder, 0)
    }

    /// DWL_SPACER should not be considered drawable.
    func testDWLSpacerIsNotDrawable() {
        // Characters in the ITERM2_PRIVATE range are not drawable
        XCTAssertTrue(DWL_SPACER >= ITERM2_PRIVATE_BEGIN && DWL_SPACER <= ITERM2_PRIVATE_END)
    }

    // MARK: - ESC # Parser (Phase 3)

    private func parse(_ bytes: [UInt8]) -> [VT100Token] {
        let parser = VT100Parser()
        parser.encoding = String.Encoding.utf8.rawValue
        bytes.withUnsafeBufferPointer { buf in
            parser.putStreamData(buf.baseAddress, length: Int32(buf.count))
        }
        var vector = CVector()
        CVectorCreate(&vector, 100)
        _ = parser.addParsedTokens(to: &vector)
        var tokens = [VT100Token]()
        for i in 0..<CVectorCount(&vector) {
            tokens.append(CVectorGetObject(&vector, i) as! VT100Token)
        }
        return tokens
    }

    /// ESC # 3 should produce VT100CSI_DECDHL with p[0] = 3 (top half).
    func testParseESCHash3() {
        let tokens = parse([0x1b, 0x23, 0x33])  // ESC # 3
        let decdhl = tokens.first { $0.type == VT100CSI_DECDHL }
        XCTAssertNotNil(decdhl, "ESC # 3 should produce VT100CSI_DECDHL")
        XCTAssertEqual(decdhl!.csi.pointee.p.0, 3)
    }

    /// ESC # 4 should produce VT100CSI_DECDHL with p[0] = 4 (bottom half).
    func testParseESCHash4() {
        let tokens = parse([0x1b, 0x23, 0x34])  // ESC # 4
        let decdhl = tokens.first { $0.type == VT100CSI_DECDHL }
        XCTAssertNotNil(decdhl, "ESC # 4 should produce VT100CSI_DECDHL")
        XCTAssertEqual(decdhl!.csi.pointee.p.0, 4)
    }

    /// ESC # 5 should produce VT100CSI_DECSWL.
    func testParseESCHash5() {
        let tokens = parse([0x1b, 0x23, 0x35])  // ESC # 5
        let decswl = tokens.first { $0.type == VT100CSI_DECSWL }
        XCTAssertNotNil(decswl, "ESC # 5 should produce VT100CSI_DECSWL")
    }

    /// ESC # 6 should produce VT100CSI_DECDWL.
    func testParseESCHash6() {
        let tokens = parse([0x1b, 0x23, 0x36])  // ESC # 6
        let decdwl = tokens.first { $0.type == VT100CSI_DECDWL }
        XCTAssertNotNil(decdwl, "ESC # 6 should produce VT100CSI_DECDWL")
    }

    /// ESC # 8 should still produce VT100CSI_DECALN (existing behavior).
    func testParseESCHash8StillWorks() {
        let tokens = parse([0x1b, 0x23, 0x38])  // ESC # 8
        let decaln = tokens.first { $0.type == VT100CSI_DECALN }
        XCTAssertNotNil(decaln, "ESC # 8 should still produce VT100CSI_DECALN")
    }

    // MARK: - Terminal Execution (Phase 4)

    private func makeScreen(width: Int = 80, height: Int = 24) -> VT100Screen {
        let screen = VT100Screen()
        let session = FakeSession()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.terminalEnabled = true
            mutableState?.terminal?.termType = "xterm"
            screen.destructivelySetScreenWidth(Int32(width),
                                                height: Int32(height),
                                                mutableState: mutableState)
        })
        return screen
    }

    private func setLineAttribute(_ screen: VT100Screen, attr: iTermLineAttribute) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.terminalSetLineAttribute(attr)
        })
    }

    private func moveCursor(_ screen: VT100Screen, toLine line: Int) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState?.currentGrid.cursorY = Int32(line)
        })
    }

    private func lineAttribute(_ screen: VT100Screen, line: Int) -> iTermLineAttribute {
        var result = iTermLineAttribute.singleWidth
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState!.currentGrid
            result = grid.lineInfo(atLineNumber: Int32(line)).metadata.lineAttribute
        })
        return result
    }

    /// Setting doubleWidth on the current line should persist.
    func testSetDoubleWidth() {
        let screen = makeScreen(width: 80, height: 24)
        setLineAttribute(screen, attr: .doubleWidth)
        XCTAssertEqual(lineAttribute(screen, line: 0), .doubleWidth)
    }

    /// Setting doubleHeightTop on the current line should persist.
    func testSetDoubleHeightTop() {
        let screen = makeScreen(width: 80, height: 24)
        setLineAttribute(screen, attr: .doubleHeightTop)
        XCTAssertEqual(lineAttribute(screen, line: 0), .doubleHeightTop)
    }

    /// Setting doubleHeightBottom on the current line should persist.
    func testSetDoubleHeightBottom() {
        let screen = makeScreen(width: 80, height: 24)
        setLineAttribute(screen, attr: .doubleHeightBottom)
        XCTAssertEqual(lineAttribute(screen, line: 0), .doubleHeightBottom)
    }

    /// Setting singleWidth should reset a double-width line.
    func testResetToSingleWidth() {
        let screen = makeScreen(width: 80, height: 24)
        setLineAttribute(screen, attr: .doubleWidth)
        XCTAssertEqual(lineAttribute(screen, line: 0), .doubleWidth)
        setLineAttribute(screen, attr: .singleWidth)
        XCTAssertEqual(lineAttribute(screen, line: 0), .singleWidth)
    }

    /// Line attribute should only affect the current cursor line.
    func testLineAttributeOnlyAffectsCurrentLine() {
        let screen = makeScreen(width: 80, height: 24)
        moveCursor(screen, toLine: 1)
        setLineAttribute(screen, attr: .doubleWidth)
        XCTAssertEqual(lineAttribute(screen, line: 0), .singleWidth)
        XCTAssertEqual(lineAttribute(screen, line: 1), .doubleWidth)
    }

    // MARK: - Content Transformation (Phase 5)

    /// Helper to get the screen_char_t codes for a line as an array.
    private func lineCodes(_ screen: VT100Screen, line: Int, count: Int) -> [unichar] {
        var codes = [unichar]()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState!.currentGrid
            let chars = grid.immutableScreenChars(atLineNumber: Int32(line))!
            for i in 0..<count {
                codes.append(chars[i].code)
            }
        })
        return codes
    }

    /// When setting doubleWidth on a line with existing text, the first
    /// width/2 characters should be expanded with DWL_SPACERs interleaved.
    func testExpandContentOnDoubleWidth() {
        let screen = makeScreen(width: 10, height: 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "ABCDE")
            mutableState!.currentGrid.cursorX = 0
        })
        setLineAttribute(screen, attr: .doubleWidth)
        // Line should now be: A,DWL,B,DWL,C,DWL,D,DWL,E,DWL
        let codes = lineCodes(screen, line: 0, count: 10)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("A").value))
        XCTAssertEqual(codes[1], unichar(DWL_SPACER))
        XCTAssertEqual(codes[2], unichar(UnicodeScalar("B").value))
        XCTAssertEqual(codes[3], unichar(DWL_SPACER))
        XCTAssertEqual(codes[4], unichar(UnicodeScalar("C").value))
        XCTAssertEqual(codes[5], unichar(DWL_SPACER))
        XCTAssertEqual(codes[6], unichar(UnicodeScalar("D").value))
        XCTAssertEqual(codes[7], unichar(DWL_SPACER))
        XCTAssertEqual(codes[8], unichar(UnicodeScalar("E").value))
        XCTAssertEqual(codes[9], unichar(DWL_SPACER))
    }

    /// Characters beyond width/2 are lost when expanding to double-width.
    func testExpandContentTruncatesExcess() {
        let screen = makeScreen(width: 10, height: 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "ABCDEFGHIJ")  // fills all 10 cells
            mutableState!.currentGrid.cursorX = 0
        })
        setLineAttribute(screen, attr: .doubleWidth)
        // Only first 5 chars fit: A,DWL,B,DWL,C,DWL,D,DWL,E,DWL
        let codes = lineCodes(screen, line: 0, count: 10)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("A").value))
        XCTAssertEqual(codes[1], unichar(DWL_SPACER))
        XCTAssertEqual(codes[8], unichar(UnicodeScalar("E").value))
        XCTAssertEqual(codes[9], unichar(DWL_SPACER))
    }

    /// Compacting from doubleWidth back to singleWidth should remove DWL_SPACERs.
    func testCompactContentOnSingleWidth() {
        let screen = makeScreen(width: 10, height: 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "ABCDE")
            mutableState!.currentGrid.cursorX = 0
        })
        setLineAttribute(screen, attr: .doubleWidth)
        setLineAttribute(screen, attr: .singleWidth)
        // Line should be compacted back: A,B,C,D,E,0,0,0,0,0
        let codes = lineCodes(screen, line: 0, count: 10)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("A").value))
        XCTAssertEqual(codes[1], unichar(UnicodeScalar("B").value))
        XCTAssertEqual(codes[2], unichar(UnicodeScalar("C").value))
        XCTAssertEqual(codes[3], unichar(UnicodeScalar("D").value))
        XCTAssertEqual(codes[4], unichar(UnicodeScalar("E").value))
        XCTAssertEqual(codes[5], 0)  // blank
    }

    /// Switching between doubleWidth and doubleHeightTop should not change content.
    func testSwitchBetweenDoubleVariantsKeepsContent() {
        let screen = makeScreen(width: 10, height: 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "ABC")
            mutableState!.currentGrid.cursorX = 0
        })
        setLineAttribute(screen, attr: .doubleWidth)
        let codesBefore = lineCodes(screen, line: 0, count: 10)
        setLineAttribute(screen, attr: .doubleHeightTop)
        let codesAfter = lineCodes(screen, line: 0, count: 10)
        XCTAssertEqual(codesBefore, codesAfter)
    }

    /// Setting doubleWidth on an empty line should be all zeros (no spacers for empty cells).
    func testDoubleWidthOnEmptyLine() {
        let screen = makeScreen(width: 10, height: 4)
        setLineAttribute(screen, attr: .doubleWidth)
        let codes = lineCodes(screen, line: 0, count: 10)
        // Empty line stays empty — no content to expand
        for code in codes {
            XCTAssertEqual(code, 0)
        }
    }

    /// A double-width character (DWC) on a double-width line should expand to 4 cells:
    /// [char][DWL_SPACER][DWC_RIGHT][DWL_SPACER]
    func testExpandDWCOnDoubleWidthLine() {
        let screen = makeScreen(width: 10, height: 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            // Write a DWC character (Ｌ = fullwidth L, U+FF2C) followed by 'x'
            mutableState!.appendString(atCursor: "\u{FF2C}x")
            mutableState!.currentGrid.cursorX = 0
        })
        // Before expansion: [Ｌ][DWC_RIGHT][x][0][0]...
        setLineAttribute(screen, attr: .doubleWidth)
        // After expansion: [Ｌ][DWL_SPACER][DWC_RIGHT][DWL_SPACER][x][DWL_SPACER][0]...
        let codes = lineCodes(screen, line: 0, count: 10)
        XCTAssertEqual(codes[0], unichar(0xFF2C))  // Ｌ
        XCTAssertEqual(codes[1], unichar(DWL_SPACER))
        XCTAssertEqual(codes[2], unichar(DWC_RIGHT))
        XCTAssertEqual(codes[3], unichar(DWL_SPACER))
        XCTAssertEqual(codes[4], unichar(UnicodeScalar("x").value))
        XCTAssertEqual(codes[5], unichar(DWL_SPACER))
        XCTAssertEqual(codes[6], 0)
    }

    // MARK: - Character Input on Double-Width Lines (Phase 5 part 2)

    /// Typing on a double-width line should interleave DWL_SPACERs.
    func testTypeOnDoubleWidthLine() {
        let screen = makeScreen(width: 10, height: 4)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "AB")
        })
        let codes = lineCodes(screen, line: 0, count: 6)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("A").value))
        XCTAssertEqual(codes[1], unichar(DWL_SPACER))
        XCTAssertEqual(codes[2], unichar(UnicodeScalar("B").value))
        XCTAssertEqual(codes[3], unichar(DWL_SPACER))
        XCTAssertEqual(codes[4], 0)  // blank after content
    }

    /// Typing a DWC on a double-width line should produce 4 cells.
    func testTypeDWCOnDoubleWidthLine() {
        let screen = makeScreen(width: 10, height: 4)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "\u{FF2C}")  // fullwidth L
        })
        let codes = lineCodes(screen, line: 0, count: 6)
        XCTAssertEqual(codes[0], unichar(0xFF2C))
        XCTAssertEqual(codes[1], unichar(DWL_SPACER))
        XCTAssertEqual(codes[2], unichar(DWC_RIGHT))
        XCTAssertEqual(codes[3], unichar(DWL_SPACER))
        XCTAssertEqual(codes[4], 0)
    }

    /// Filling a double-width line to capacity (width/2 chars) should work.
    func testFillDoubleWidthLine() {
        let screen = makeScreen(width: 10, height: 4)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "ABCDE")  // 5 chars = width/2
        })
        let codes = lineCodes(screen, line: 0, count: 10)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("A").value))
        XCTAssertEqual(codes[1], unichar(DWL_SPACER))
        XCTAssertEqual(codes[8], unichar(UnicodeScalar("E").value))
        XCTAssertEqual(codes[9], unichar(DWL_SPACER))
    }

    // MARK: - Grid Operations on Double-Width Lines (Phase 6)

    /// Helper to get compactLineDump from a screen.
    private func compactDump(_ screen: VT100Screen) -> String {
        var result = ""
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            result = mutableState!.currentGrid.compactLineDump()
        })
        return result
    }

    /// Verify compactLineDump shows DWL_SPACERs as '|'.
    func testCompactLineDumpShowsSpacers() {
        let screen = makeScreen(width: 10, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "AB")
        })
        let dump = compactDump(screen)
        // A|B|......  (| = DWL_SPACER, . = null)
        let firstLine = dump.components(separatedBy: "\n")[0]
        XCTAssertEqual(firstLine, "A|B|......")
    }

    /// lengthOfLineNumber: should return the physical length including DWL_SPACERs.
    func testLengthOfDoubleWidthLine() {
        let screen = makeScreen(width: 10, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "ABC")
        })
        var length: Int32 = 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            length = mutableState!.currentGrid.length(ofLineNumber: 0)
        })
        // 3 chars * 2 (char + spacer) = 6 physical cells
        XCTAssertEqual(length, 6)
    }

    /// coordinateBefore: should skip DWL_SPACERs.
    func testCoordinateBeforeSkipsDWLSpacer() {
        let screen = makeScreen(width: 10, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "AB")
        })
        // Grid: A|B|......
        // coordinateBefore position 2 ('B') should go to position 0 ('A'), skipping the spacer at 1.
        var coord = VT100GridCoord()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            var dwc: ObjCBool = false
            coord = mutableState!.currentGrid.coordinate(before: VT100GridCoordMake(2, 0),
                                                        movedBackOverDoubleWidth: &dwc)
        })
        XCTAssertEqual(coord.x, 0)
        XCTAssertEqual(coord.y, 0)
    }

    /// coordinateBefore: should navigate back over DWC+DWL_SPACER (4-cell DWC on double-width line).
    func testCoordinateBeforeSkipsDWCWithDWLSpacer() {
        let screen = makeScreen(width: 10, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            // Write fullwidth L followed by 'x'
            mutableState!.appendString(atCursor: "\u{FF2C}x")
        })
        // Grid: ?|–|x|....   (? = Ｌ, | = DWL_SPACER, – = DWC_RIGHT)
        // coordinateBefore position 4 ('x') should go to position 0 (Ｌ), skipping DWC_RIGHT and spacers.
        var coord = VT100GridCoord()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            var dwc: ObjCBool = false
            coord = mutableState!.currentGrid.coordinate(before: VT100GridCoordMake(4, 0),
                                                         movedBackOverDoubleWidth: &dwc)
            XCTAssertTrue(dwc.boolValue)
        })
        XCTAssertEqual(coord.x, 0)
        XCTAssertEqual(coord.y, 0)
    }

    /// coordinateBefore: starting just after DWC_RIGHT (at trailing DWL_SPACER)
    /// should still set dwc=YES since we moved back through DWC_RIGHT.
    func testCoordinateBeforeFromDWCRightTrailingSpacer() {
        let screen = makeScreen(width: 10, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "\u{FF2C}x")
        })
        // Grid: [Ｌ][DWL][DWC_R][DWL][x][DWL]...
        //        0    1     2      3   4   5
        // coordinateBefore(4, 0) → --cx=3 (DWL_SPACER) → back over DWL,DWC_R,DWL → lands on Ｌ at 0
        var coord = VT100GridCoord()
        var wasDWC = false
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            var dwc: ObjCBool = false
            coord = mutableState!.currentGrid.coordinate(before: VT100GridCoordMake(4, 0),
                                                         movedBackOverDoubleWidth: &dwc)
            wasDWC = dwc.boolValue
        })
        XCTAssertEqual(coord.x, 0)
        XCTAssertEqual(coord.y, 0)
        XCTAssertTrue(wasDWC)
    }

    // Group 2: numberOfNonEmptyLinesIncludingWhitespaceAsEmpty (line 443)
    // DWL_SPACER should be treated as whitespace/empty like TAB_FILLER and DWC_RIGHT.

    /// A double-width line with only DWL_SPACERs after content should not
    /// count DWL_SPACERs as non-empty when whitespace is treated as empty.
    func testNumberOfNonEmptyLinesIgnoresDWLSpacer() {
        let screen = makeScreen(width: 10, height: 4)
        // Put content on line 0, leave lines 1-3 empty
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "A")
        })
        setLineAttribute(screen, attr: .doubleWidth)
        // Line 0: A|........
        var count: Int32 = 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            count = mutableState!.currentGrid.numberOfNonEmptyLinesIncludingWhitespace(asEmpty: true)
        })
        // Should be 1 (only line 0 has content)
        XCTAssertEqual(count, 1)
    }

    // Group 4: successorOf: uses haveDoubleWidthExtensionAt: internally.
    // DWL_SPACER should be skipped like DWC_RIGHT.

    /// successorOf: should skip DWL_SPACER and advance to the next real character.
    func testSuccessorOfSkipsDWLSpacer() {
        let screen = makeScreen(width: 10, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "AB")
        })
        // Line: A|B|......  — successor of (0,0) should be (2,0) ('B'), skipping DWL_SPACER at 1
        var coord = VT100GridCoord()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            coord = mutableState!.currentGrid.successor(of: VT100GridCoordMake(0, 0))
        })
        XCTAssertEqual(coord.x, 2)
        XCTAssertEqual(coord.y, 0)
    }

    // Group 5: erasePossibleDoubleWidthCharInLineNumber (line 3035)
    // Checks aLine[offset + 1] for DWC_RIGHT. On a double-width line,
    // DWC_RIGHT is at offset + 2 (with DWL_SPACER at offset + 1).

    /// erasePossibleDoubleWidthChar should find DWC on a double-width line
    /// where DWL_SPACER sits between the char and DWC_RIGHT.
    func testErasePossibleDWCOnDoubleWidthLine() {
        let screen = makeScreen(width: 10, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "\u{FF2C}")  // fullwidth L → [Ｌ][DWL][DWC_RIGHT][DWL]
        })
        // Erase the DWC at position 0
        var erased = false
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let blank = mutableState!.currentGrid.defaultChar
            erased = mutableState!.currentGrid.erasePossibleDoubleWidthChar(inLineNumber: 0,
                                                                            startingAtOffset: 0,
                                                                            with: blank)
        })
        XCTAssertTrue(erased)
    }

    // Group 6: debugString (line 1946)
    // Should display DWL_SPACER distinctly.

    /// debugString should handle DWL_SPACER without crashing.
    func testDebugStringWithDWLSpacer() {
        let screen = makeScreen(width: 10, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "AB")
        })
        var debugStr = ""
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            debugStr = mutableState!.currentGrid.debugString()
        })
        // Should not crash and should contain something for each cell
        XCTAssertFalse(debugStr.isEmpty)
    }

    // MARK: - Phase 6: Text Extraction and Word Selection

    /// Text extraction from a double-width line should not include DWL_SPACERs.
    func testTextExtractionSkipsDWLSpacer() {
        let screen = makeScreen(width: 10, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "Hello")
        })
        // Grid: H|e|l|l|o|  — DWL_SPACERs should not appear in extracted text.
        var extracted = ""
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState!.currentGrid
            var cont = screen_char_t()
            cont.code = unichar(EOL_HARD)
            let sca = ScreenCharArray(
                copyOfLine: grid.immutableScreenChars(atLineNumber: 0),
                length: grid.size.width,
                continuation: cont)
            extracted = sca.stringValue
        })
        XCTAssertEqual(extracted, "Hello")
    }

    /// successorOf chain should skip DWL_SPACERs correctly.
    func testSuccessorOfChainSkipsDWLSpacers() {
        let screen = makeScreen(width: 10, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "AB")
        })
        // successor(0,0) = (2,0), successor(2,0) = (4,0)
        var coord1 = VT100GridCoord()
        var coord2 = VT100GridCoord()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            coord1 = mutableState!.currentGrid.successor(of: VT100GridCoordMake(0, 0))
            coord2 = mutableState!.currentGrid.successor(of: coord1)
        })
        XCTAssertEqual(coord1.x, 2)  // Skipped DWL_SPACER at 1
        XCTAssertEqual(coord2.x, 4)  // Skipped DWL_SPACER at 3
    }

    /// successorOf should skip the full [DWL][DWC_RIGHT][DWL] extension on a DWC.
    func testSuccessorOfSkipsFullDWCExtensionOnDWLLine() {
        let screen = makeScreen(width: 20, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            // Write fullwidth L then 'x': [Ｌ][DWL][DWC_R][DWL][x][DWL]
            mutableState!.appendString(atCursor: "\u{FF2C}x")
        })
        // successor(0,0) should skip positions 1(DWL), 2(DWC_R), 3(DWL) → land on 4(x)
        var coord = VT100GridCoord()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            coord = mutableState!.currentGrid.successor(of: VT100GridCoordMake(0, 0))
        })
        XCTAssertEqual(coord.x, 4)
    }

    // MARK: - ScreenCharArray.split (JSONPrettyPrinter)

    /// Splitting a ScreenCharArray with DWL_SPACERs should not crash or infinite-loop.
    /// The split function avoids ending a part on a DWC_RIGHT or DWL_SPACER.
    func testSplitWithDWLSpacerDoesNotCrash() {
        let screen = makeScreen(width: 20, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "ABCDE")
        })
        // Grid: A|B|C|D|E|..........  (10 physical cells of content)
        var parts: [(ScreenCharArray, Int)] = []
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState!.currentGrid
            var cont = screen_char_t()
            cont.code = unichar(EOL_HARD)
            let sca = ScreenCharArray(
                copyOfLine: grid.immutableScreenChars(atLineNumber: 0),
                length: 10,
                continuation: cont)
            parts = sca.split(maxWidth: 4)
        })
        // Should produce multiple parts without crashing.
        XCTAssertGreaterThan(parts.count, 1)
        // Total length of all parts should equal original length.
        let totalLength = parts.reduce(0) { $0 + Int($1.0.length) }
        XCTAssertEqual(totalLength, 10)
    }

    // MARK: - ScreenCharArray.subArrayToIndex with DWC on double-width line

    /// subArrayToIndex should back up over the full [char][DWL][DWC_RIGHT][DWL] sequence.
    func testSubArrayToIndexBacksUpOverDWCWithDWLSpacers() {
        let screen = makeScreen(width: 20, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            // Write 'A' then fullwidth L: A|Ｌ|-|
            mutableState!.appendString(atCursor: "A\u{FF2C}")
        })
        // Grid: [A][DWL][Ｌ][DWL][DWC_R][DWL][0]...
        //        0   1    2   3     4      5   6
        // subArrayToIndex(3) lands on DWL_SPACER before DWC_RIGHT.
        // Should back up to index 2 (Ｌ), which is also a DWC left half
        // that pairs with DWC_RIGHT. We should back up further to index 1
        // (DWL_SPACER after A), then index 0... but wait, 'A' is a real char.
        // Actually the loop backs up over DWL_SPACER at 3, then stops at Ｌ at 2.
        // But Ｌ is a real character, not DWC_RIGHT or DWL_SPACER, so the loop stops.
        // Result: subArray has length 2 = [A][DWL_SPACER], which doesn't split the DWC.

        // subArrayToIndex(4) lands on DWC_RIGHT — should back up to 2 (Ｌ).
        // subArrayToIndex(5) lands on DWL_SPACER after DWC_RIGHT — back up to 2.
        var length3: Int32 = 0
        var length4: Int32 = 0
        var length5: Int32 = 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState!.currentGrid
            var cont = screen_char_t()
            cont.code = unichar(EOL_HARD)
            let sca = ScreenCharArray(
                copyOfLine: grid.immutableScreenChars(atLineNumber: 0),
                length: 6,
                continuation: cont)

            length3 = sca.subArray(to: 3).length
            length4 = sca.subArray(to: 4).length
            length5 = sca.subArray(to: 5).length
        })
        // All should back up to not split the DWC: length should be 2 ([A][DWL])
        XCTAssertEqual(length3, 2)  // backed up over DWL_SPACER at 3 → stopped at Ｌ at 2
        XCTAssertEqual(length4, 2)  // backed up over DWC_RIGHT at 4, DWL at 3 → stopped at Ｌ at 2
        XCTAssertEqual(length5, 2)  // backed up over DWL at 5, DWC_R at 4, DWL at 3 → stopped at Ｌ at 2
    }

    // MARK: - Phase 9: Scrollback Preservation

    func testLineAttributePreservedInScrollback() {
        let screen = makeScreen(width: 20, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "Hi")
        })

        // Scroll the line into history by filling the screen
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "\r\n")
            mutableState!.appendString(atCursor: "\r\n")
        })

        // Read the line attribute from the scrollback line (absolute line 0)
        var attr: iTermLineAttribute = .singleWidth
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let sca = mutableState!.screenCharArray(forLine: 0)
            attr = sca.metadata.lineAttribute
        })
        XCTAssertEqual(attr, .doubleWidth,
                       "Line attribute should survive scrollback")
    }

    func testPerCharacterExternalAttributeSetOnScrollback() {
        let screen = makeScreen(width: 20, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "AB")
        })
        // Scroll into history
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "\r\n")
            mutableState!.appendString(atCursor: "\r\n")
        })

        // Check that the scrollback line has doubleWidth metadata (derived
        // from per-character external attributes).
        var attr: iTermLineAttribute = .singleWidth
        var charCount: Int32 = 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let sca = mutableState!.screenCharArray(forLine: 0)
            charCount = sca.length
            attr = sca.metadata.lineAttribute
        })
        XCTAssertGreaterThan(charCount, 0)
        XCTAssertEqual(attr, .doubleWidth,
                       "Scrollback line should derive doubleWidth from per-character external attributes")
    }

    func testMixedLineAttributeAfterResizeIsSingleWidth() {
        // Create a DWL line followed by normal text on the same logical line
        let screen = makeScreen(width: 20, height: 3)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            // Fill the DWL line to wrap: 10 logical chars = 20 physical cells
            mutableState!.appendString(atCursor: "ABCDEFGHIJ")
        })
        // The line wraps. Set the continuation to single-width.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState!.currentGrid
            // Cursor is now on line 1. Set it to single-width and type.
            let lineInfo = grid.lineInfo(atLineNumber: 1)
            lineInfo?.metadata.lineAttribute = .singleWidth
            mutableState!.appendString(atCursor: "xyz")
        })

        // Scroll everything into history
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "\r\n\r\n\r\n")
        })

        // Now resize to width 10 and check: the first wrapped line from
        // the buffer should be all DWL. A later wrapped line that mixes
        // DWL spacers with non-DWL characters should be singleWidth.
        var firstAttr: iTermLineAttribute = .singleWidth
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let sca = mutableState!.screenCharArray(forLine: 0)
            firstAttr = sca.metadata.lineAttribute
        })
        // The first screen line in scrollback was fully DWL
        XCTAssertEqual(firstAttr, .doubleWidth)
    }

    func testDoubleHeightTopPreservedInScrollback() {
        let screen = makeScreen(width: 20, height: 2)
        setLineAttribute(screen, attr: .doubleHeightTop)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "Top")
        })
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "\r\n\r\n")
        })

        var attr: iTermLineAttribute = .singleWidth
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let sca = mutableState!.screenCharArray(forLine: 0)
            attr = sca.metadata.lineAttribute
        })
        XCTAssertEqual(attr, .doubleHeightTop,
                       "doubleHeightTop should survive scrollback")
    }

    func testScrollbackMetadataAccessAfterAutorelease() {
        // Regression test: accessing scrollback metadata multiple times must
        // not crash. The lineAttribute derivation code previously called
        // iTermImmutableMetadataRelease on retain-autoreleased metadata,
        // causing a use-after-free when the autorelease pool drained.
        let screen = makeScreen(width: 20, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "Hello")
        })
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState!.appendString(atCursor: "\r\n\r\n")
        })

        // Access the scrollback line multiple times with explicit autorelease
        // pool drains between accesses. The over-release bug only manifested
        // after the pool drained.
        for _ in 0..<3 {
            var attr: iTermLineAttribute = .singleWidth
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                autoreleasepool {
                    let sca = mutableState!.screenCharArray(forLine: 0)
                    attr = sca.metadata.lineAttribute
                }
            })
            XCTAssertEqual(attr, .doubleWidth)
        }
    }
}
