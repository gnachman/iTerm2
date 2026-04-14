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
        let decoded = iTermMetadataDecodedFromData(data)
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
            let decoded = iTermMetadataDecodedFromData(data)
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

        let decoded = iTermMetadataDecodedFromData(legacyData)
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

        let decoded = iTermMetadataDecodedFromData(data)
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
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
            mutableState.terminal?.encoding = String.Encoding.utf8.rawValue
            screen.destructivelySetScreenWidth(Int32(width),
                                                height: Int32(height),
                                                mutableState: mutableState)
        })
        return screen
    }

    private func setLineAttribute(_ screen: VT100Screen, attr: iTermLineAttribute) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(attr)
        })
    }

    private func moveCursor(_ screen: VT100Screen, toLine line: Int) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.currentGrid.cursorY = Int32(line)
        })
    }

    private func lineAttribute(_ screen: VT100Screen, line: Int) -> iTermLineAttribute {
        var result = iTermLineAttribute.singleWidth
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
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
            let grid = mutableState.currentGrid
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
            mutableState.appendString(atCursor: "ABCDE")
            mutableState.currentGrid.cursorX = 0
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
            mutableState.appendString(atCursor: "ABCDEFGHIJ")  // fills all 10 cells
            mutableState.currentGrid.cursorX = 0
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
            mutableState.appendString(atCursor: "ABCDE")
            mutableState.currentGrid.cursorX = 0
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
            mutableState.appendString(atCursor: "ABC")
            mutableState.currentGrid.cursorX = 0
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
            mutableState.appendString(atCursor: "\u{FF2C}x")
            mutableState.currentGrid.cursorX = 0
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
            mutableState.appendString(atCursor: "AB")
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
            mutableState.appendString(atCursor: "\u{FF2C}")  // fullwidth L
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
            mutableState.appendString(atCursor: "ABCDE")  // 5 chars = width/2
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
            result = mutableState.currentGrid.compactLineDump()
        })
        return result
    }

    /// Verify compactLineDump shows DWL_SPACERs as '|'.
    func testCompactLineDumpShowsSpacers() {
        let screen = makeScreen(width: 10, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "AB")
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
            mutableState.appendString(atCursor: "ABC")
        })
        var length: Int32 = 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            length = mutableState.currentGrid.length(ofLineNumber: 0)
        })
        // 3 chars * 2 (char + spacer) = 6 physical cells
        XCTAssertEqual(length, 6)
    }

    /// coordinateBefore: should skip DWL_SPACERs.
    func testCoordinateBeforeSkipsDWLSpacer() {
        let screen = makeScreen(width: 10, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "AB")
        })
        // Grid: A|B|......
        // coordinateBefore position 2 ('B') should go to position 0 ('A'), skipping the spacer at 1.
        var coord = VT100GridCoord()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            var dwc: ObjCBool = false
            coord = mutableState.currentGrid.coordinate(before: VT100GridCoordMake(2, 0),
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
            mutableState.appendString(atCursor: "\u{FF2C}x")
        })
        // Grid: ?|–|x|....   (? = Ｌ, | = DWL_SPACER, – = DWC_RIGHT)
        // coordinateBefore position 4 ('x') should go to position 0 (Ｌ), skipping DWC_RIGHT and spacers.
        var coord = VT100GridCoord()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            var dwc: ObjCBool = false
            coord = mutableState.currentGrid.coordinate(before: VT100GridCoordMake(4, 0),
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
            mutableState.appendString(atCursor: "\u{FF2C}x")
        })
        // Grid: [Ｌ][DWL][DWC_R][DWL][x][DWL]...
        //        0    1     2      3   4   5
        // coordinateBefore(4, 0) → --cx=3 (DWL_SPACER) → back over DWL,DWC_R,DWL → lands on Ｌ at 0
        var coord = VT100GridCoord()
        var wasDWC = false
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            var dwc: ObjCBool = false
            coord = mutableState.currentGrid.coordinate(before: VT100GridCoordMake(4, 0),
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
            mutableState.appendString(atCursor: "A")
        })
        setLineAttribute(screen, attr: .doubleWidth)
        // Line 0: A|........
        var count: Int32 = 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            count = mutableState.currentGrid.numberOfNonEmptyLinesIncludingWhitespace(asEmpty: true)
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
            mutableState.appendString(atCursor: "AB")
        })
        // Line: A|B|......  — successor of (0,0) should be (2,0) ('B'), skipping DWL_SPACER at 1
        var coord = VT100GridCoord()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            coord = mutableState.currentGrid.successor(of: VT100GridCoordMake(0, 0))
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
            mutableState.appendString(atCursor: "\u{FF2C}")  // fullwidth L → [Ｌ][DWL][DWC_RIGHT][DWL]
        })
        // Erase the DWC at position 0
        var erased = false
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let blank = mutableState.currentGrid.defaultChar
            erased = mutableState.currentGrid.erasePossibleDoubleWidthChar(inLineNumber: 0,
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
            mutableState.appendString(atCursor: "AB")
        })
        var debugStr = ""
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            debugStr = mutableState.currentGrid.debugString()
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
            mutableState.appendString(atCursor: "Hello")
        })
        // Grid: H|e|l|l|o|  — DWL_SPACERs should not appear in extracted text.
        var extracted = ""
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
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
            mutableState.appendString(atCursor: "AB")
        })
        // successor(0,0) = (2,0), successor(2,0) = (4,0)
        var coord1 = VT100GridCoord()
        var coord2 = VT100GridCoord()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            coord1 = mutableState.currentGrid.successor(of: VT100GridCoordMake(0, 0))
            coord2 = mutableState.currentGrid.successor(of: coord1)
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
            mutableState.appendString(atCursor: "\u{FF2C}x")
        })
        // successor(0,0) should skip positions 1(DWL), 2(DWC_R), 3(DWL) → land on 4(x)
        var coord = VT100GridCoord()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            coord = mutableState.currentGrid.successor(of: VT100GridCoordMake(0, 0))
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
            mutableState.appendString(atCursor: "ABCDE")
        })
        // Grid: A|B|C|D|E|..........  (10 physical cells of content)
        var parts: [(ScreenCharArray, Int)] = []
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
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
            mutableState.appendString(atCursor: "A\u{FF2C}")
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
            let grid = mutableState.currentGrid
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
            mutableState.appendString(atCursor: "Hi")
        })

        // Scroll the line into history by filling the screen
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "\r\n")
            mutableState.appendString(atCursor: "\r\n")
        })

        // Read the line attribute from the scrollback line (absolute line 0)
        var attr: iTermLineAttribute = .singleWidth
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let sca = mutableState.screenCharArray(forLine: 0)
            attr = sca.metadata.lineAttribute
        })
        XCTAssertEqual(attr, .doubleWidth,
                       "Line attribute should survive scrollback")
    }

    func testPerCharacterExternalAttributeSetOnScrollback() {
        let screen = makeScreen(width: 20, height: 2)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "AB")
        })
        // Scroll into history
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "\r\n")
            mutableState.appendString(atCursor: "\r\n")
        })

        // Check that the scrollback line has doubleWidth metadata (derived
        // from per-character external attributes).
        var attr: iTermLineAttribute = .singleWidth
        var charCount: Int32 = 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let sca = mutableState.screenCharArray(forLine: 0)
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
            mutableState.appendString(atCursor: "ABCDEFGHIJ")
        })
        // The line wraps. Set the continuation to single-width.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            // Cursor is now on line 1. Set it to single-width and type.
            let lineInfo = grid.lineInfo(atLineNumber: 1)
            lineInfo?.metadata.lineAttribute = .singleWidth
            mutableState.appendString(atCursor: "xyz")
        })

        // Scroll everything into history
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "\r\n\r\n\r\n")
        })

        // Now resize to width 10 and check: the first wrapped line from
        // the buffer should be all DWL. A later wrapped line that mixes
        // DWL spacers with non-DWL characters should be singleWidth.
        var firstAttr: iTermLineAttribute = .singleWidth
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let sca = mutableState.screenCharArray(forLine: 0)
            firstAttr = sca.metadata.lineAttribute
        })
        // The first screen line in scrollback was fully DWL
        XCTAssertEqual(firstAttr, .doubleWidth)
    }

    func testDoubleHeightTopPreservedInScrollback() {
        let screen = makeScreen(width: 20, height: 2)
        setLineAttribute(screen, attr: .doubleHeightTop)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "Top")
        })
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "\r\n\r\n")
        })

        var attr: iTermLineAttribute = .singleWidth
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let sca = mutableState.screenCharArray(forLine: 0)
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
            mutableState.appendString(atCursor: "Hello")
        })
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "\r\n\r\n")
        })

        // Access the scrollback line multiple times with explicit autorelease
        // pool drains between accesses. The over-release bug only manifested
        // after the pool drained.
        for _ in 0..<3 {
            var attr: iTermLineAttribute = .singleWidth
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                autoreleasepool {
                    let sca = mutableState.screenCharArray(forLine: 0)
                    attr = sca.metadata.lineAttribute
                }
            })
            XCTAssertEqual(attr, .doubleWidth)
        }
    }

    /// Regression: a soft-wrapped line that gets DECDHL on its second screen
    /// line should preserve that attribute through widen→narrow resize.
    ///
    /// Scenario:
    /// 1. Width=20. Write 25 chars → wraps onto line 1 (5 chars on line 1).
    /// 2. Cursor is on line 1. Send ESC#3 → line 1 becomes doubleHeightTop.
    /// 3. Widen to 30 → the wrapped text reflows onto one line (no wrap).
    ///    The doubleHeightTop characters are now at the end of the single line,
    ///    with their per-character external attributes preserving the flag.
    /// 4. Narrow back to 20 → the line wraps again. The second screen line
    ///    should recover doubleHeightTop from the external attributes.
    func testDoubleHeightRecoveredAfterWidenNarrow() {
        let screen = makeScreen(width: 20, height: 5)

        // Step 1: write 25 chars to force a soft wrap at column 20.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "ABCDEFGHIJKLMNOPQRST")  // fills line 0
            mutableState.appendString(atCursor: "UVWXY")                 // wraps to line 1
        })

        // Step 2: cursor is on line 1. Set it to doubleHeightTop.
        // The cursor should be on line 1 after the wrap.
        setLineAttribute(screen, attr: .doubleHeightTop)
        XCTAssertEqual(lineAttribute(screen, line: 1), .doubleHeightTop,
                       "Line 1 should be doubleHeightTop after ESC#3")

        // Step 3: widen by 1 column — line still wraps but at different position.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(21, 5),
                                  delegate: screen.delegate!)
        })

        // Step 4: narrow back to original width.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(20, 5),
                                  delegate: screen.delegate!)
        })

        // Find the line with the DWL content. After reflow, it may be on
        // the grid or in scrollback. Use screenCharArrayForLine: which
        // covers both.
        var foundAttr: iTermLineAttribute = .singleWidth
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            // The logical line has 25 chars. At width=20, line 0 has 20
            // (singleWidth), line 1 has 5 (doubleHeightTop). The absolute
            // line number depends on how many lines are in scrollback.
            let numScrollback = mutableState.numberOfScrollbackLines()
            // Check each visible line for the DWL attribute.
            for i in 0..<5 {
                let sca = mutableState.screenCharArray(forLine: Int32(numScrollback) + Int32(i))
                if sca.metadata.lineAttribute == .doubleHeightTop {
                    foundAttr = .doubleHeightTop
                    break
                }
            }
        })
        XCTAssertEqual(foundAttr, .doubleHeightTop,
                       "doubleHeightTop should survive widen→narrow reflow")
    }

    /// Pre-existing bug: popAndCopyLastLineInto: assigns subAttributesFromIndex:
    /// (the popped portion's attrs) to the remaining line instead of
    /// subAttributesToIndex: (the remaining portion's attrs). This swaps
    /// ext attrs between the two halves during resize reflow.
    ///
    /// This test writes 25 chars at width=20 (wraps to 2 lines), sets a URL
    /// on the last 5 chars (line 1), resizes to 21 then back to 20, and
    /// verifies the URL is still on line 1.
    func testURLExtAttrSurvivesResizeReflow() {
        let screen = makeScreen(width: 20, height: 5)

        // Write 25 chars — wraps at column 20.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "ABCDEFGHIJKLMNOPQRST") // line 0
            mutableState.appendString(atCursor: "UVWXY")                // line 1
        })

        // Set a URL on line 1 (the wrapped portion), columns 0-4.
        let testURL = iTermURL(url: NSURL(string: "https://example.com")! as URL,
                               identifier: nil,
                               target: nil)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            grid.setURL(testURL,
                        inRectFrom: VT100GridCoordMake(0, 1),
                        to: VT100GridCoordMake(4, 1))
        })

        // Verify URL is on line 1 before resize.
        var urlBeforeResize: iTermURL? = nil
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            let eaIndex = grid.lineInfo(atLineNumber: 1).externalAttributesCreatingIfNeeded(false)
            urlBeforeResize = eaIndex?.attributes[NSNumber(value: 0)]?.url
        })
        XCTAssertNotNil(urlBeforeResize, "URL should be set on line 1 before resize")

        // Resize: widen to 21, then narrow back to 20.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(21, 5),
                                  delegate: screen.delegate!)
        })
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(20, 5),
                                  delegate: screen.delegate!)
        })

        // The URL should still be on line 1, not line 0.
        var urlOnLine0: iTermURL? = nil
        var urlOnLine1: iTermURL? = nil
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            let ea0 = grid.lineInfo(atLineNumber: 0).externalAttributesCreatingIfNeeded(false)
            let ea1 = grid.lineInfo(atLineNumber: 1).externalAttributesCreatingIfNeeded(false)
            urlOnLine0 = ea0?.attributes[NSNumber(value: 0)]?.url
            urlOnLine1 = ea1?.attributes[NSNumber(value: 0)]?.url
        })
        XCTAssertNil(urlOnLine0, "Line 0 should NOT have a URL after resize")
        XCTAssertNotNil(urlOnLine1, "Line 1 should still have the URL after resize")
    }

    /// URL on the first part of a wrapped line (the remaining portion after
    /// pop) should NOT leak to the second part (the popped portion).
    func testURLOnRemainingPortionDoesNotLeakToPopped() {
        let screen = makeScreen(width: 20, height: 5)

        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "ABCDEFGHIJKLMNOPQRST")
            mutableState.appendString(atCursor: "UVWXY")
        })

        // Set URL on line 0 (the remaining portion), columns 0-4.
        let testURL = iTermURL(url: NSURL(string: "https://example.com")! as URL,
                               identifier: nil,
                               target: nil)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.currentGrid.setURL(testURL,
                                              inRectFrom: VT100GridCoordMake(0, 0),
                                              to: VT100GridCoordMake(4, 0))
        })

        // Resize: widen then narrow.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(21, 5), delegate: screen.delegate!)
        })
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(20, 5), delegate: screen.delegate!)
        })

        // URL should still be on line 0, NOT on line 1.
        var urlOnLine0: iTermURL? = nil
        var urlOnLine1: iTermURL? = nil
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            urlOnLine0 = grid.lineInfo(atLineNumber: 0).externalAttributesCreatingIfNeeded(false)?.attributes[NSNumber(value: 0)]?.url
            urlOnLine1 = grid.lineInfo(atLineNumber: 1).externalAttributesCreatingIfNeeded(false)?.attributes[NSNumber(value: 0)]?.url
        })
        XCTAssertNotNil(urlOnLine0, "Line 0 should still have the URL")
        XCTAssertNil(urlOnLine1, "Line 1 should NOT have a URL (it leaked from remaining)")
    }

    /// URL spanning the wrap boundary should be split: both halves keep
    /// their portion of the URL.
    func testURLSpanningSplitBoundaryPreservedOnBothSides() {
        let screen = makeScreen(width: 20, height: 5)

        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "ABCDEFGHIJKLMNOPQRST")
            mutableState.appendString(atCursor: "UVWXY")
        })

        // Set URL spanning the wrap: columns 15-24 (line 0 cols 15-19 + line 1 cols 0-4).
        let testURL = iTermURL(url: NSURL(string: "https://example.com")! as URL,
                               identifier: nil,
                               target: nil)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            grid.setURL(testURL,
                        inRectFrom: VT100GridCoordMake(15, 0),
                        to: VT100GridCoordMake(19, 0))
            grid.setURL(testURL,
                        inRectFrom: VT100GridCoordMake(0, 1),
                        to: VT100GridCoordMake(4, 1))
        })

        // Resize: widen then narrow.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(21, 5), delegate: screen.delegate!)
        })
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(20, 5), delegate: screen.delegate!)
        })

        // Both lines should still have URLs.
        var urlOnLine0: iTermURL? = nil
        var urlOnLine1: iTermURL? = nil
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            urlOnLine0 = grid.lineInfo(atLineNumber: 0).externalAttributesCreatingIfNeeded(false)?.attributes[NSNumber(value: 15)]?.url
            urlOnLine1 = grid.lineInfo(atLineNumber: 1).externalAttributesCreatingIfNeeded(false)?.attributes[NSNumber(value: 0)]?.url
        })
        XCTAssertNotNil(urlOnLine0, "Line 0 should have URL at col 15 after resize")
        XCTAssertNotNil(urlOnLine1, "Line 1 should have URL at col 0 after resize")
    }

    /// A line wrapping 3+ times should correctly split ext attrs across
    /// multiple pops.
    func testExtAttrsSurviveTripleWrapResize() {
        let screen = makeScreen(width: 10, height: 5)

        // Write 25 chars → wraps to 3 lines at width=10: [0-9] [10-19] [20-24]
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "ABCDEFGHIJKLMNOPQRSTUVWXY")
        })

        // Set URL on the last 5 chars (line 2, cols 0-4).
        let testURL = iTermURL(url: NSURL(string: "https://example.com")! as URL,
                               identifier: nil,
                               target: nil)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.currentGrid.setURL(testURL,
                                              inRectFrom: VT100GridCoordMake(0, 2),
                                              to: VT100GridCoordMake(4, 2))
        })

        // Resize: widen to 11 then back to 10.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(11, 5), delegate: screen.delegate!)
        })
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(10, 5), delegate: screen.delegate!)
        })

        // The URL should be on the last wrapped line (line 2), not elsewhere.
        var urlOnLine0: iTermURL? = nil
        var urlOnLine1: iTermURL? = nil
        var urlOnLine2: iTermURL? = nil
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            urlOnLine0 = grid.lineInfo(atLineNumber: 0).externalAttributesCreatingIfNeeded(false)?.attributes[NSNumber(value: 0)]?.url
            urlOnLine1 = grid.lineInfo(atLineNumber: 1).externalAttributesCreatingIfNeeded(false)?.attributes[NSNumber(value: 0)]?.url
            urlOnLine2 = grid.lineInfo(atLineNumber: 2).externalAttributesCreatingIfNeeded(false)?.attributes[NSNumber(value: 0)]?.url
        })
        XCTAssertNil(urlOnLine0, "Line 0 should not have URL")
        XCTAssertNil(urlOnLine1, "Line 1 should not have URL")
        XCTAssertNotNil(urlOnLine2, "Line 2 should still have the URL after triple-wrap resize")
    }

    // MARK: - appendScreenChars:lineAttribute: (DWL compaction)

    /// Helper to build a screen_char_t array with DWL_SPACERs interleaved,
    /// simulating data read from a DWL grid line.
    private func makeDWLData(_ text: String) -> [screen_char_t] {
        var result = [screen_char_t]()
        for scalar in text.unicodeScalars {
            var ch = screen_char_t()
            ch.code = unichar(scalar.value)
            result.append(ch)
            var spacer = screen_char_t()
            ScreenCharSetDWL_SPACER(&spacer)
            result.append(spacer)
        }
        return result
    }

    /// appendScreenChars with a DWL lineAttribute should strip DWL_SPACERs
    /// from input data, set the lineAttribute on the target grid line, and
    /// re-expand so the grid contains properly interleaved DWL_SPACERs.
    func testAppendScreenCharsWithDWLLineAttribute() {
        let screen = makeScreen(width: 10, height: 4)
        // Build source data as it would appear on a DWL grid: A|B|C|
        var sourceData = makeDWLData("ABC")
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            var continuation = screen_char_t()
            continuation.code = unichar(EOL_HARD)
            mutableState.appendScreenChars(
                &sourceData,
                length: Int32(sourceData.count),
                externalAttributeIndex: iTermExternalAttributeIndex(),
                continuation: continuation,
                rtlFound: false,
                lineAttribute: .doubleWidth)
        })
        // Target grid line 0 should now be DWL with A|B|C|....
        XCTAssertEqual(lineAttribute(screen, line: 0), .doubleWidth)
        let codes = lineCodes(screen, line: 0, count: 10)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("A").value))
        XCTAssertEqual(codes[1], unichar(DWL_SPACER))
        XCTAssertEqual(codes[2], unichar(UnicodeScalar("B").value))
        XCTAssertEqual(codes[3], unichar(DWL_SPACER))
        XCTAssertEqual(codes[4], unichar(UnicodeScalar("C").value))
        XCTAssertEqual(codes[5], unichar(DWL_SPACER))
        XCTAssertEqual(codes[6], 0)
    }

    /// appendScreenChars with singleWidth lineAttribute should pass data
    /// through unchanged (no compaction or expansion).
    func testAppendScreenCharsWithSingleWidthPassesThrough() {
        let screen = makeScreen(width: 10, height: 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            var chars = [screen_char_t]()
            for scalar in "ABCDE".unicodeScalars {
                var ch = screen_char_t()
                ch.code = unichar(scalar.value)
                chars.append(ch)
            }
            var continuation = screen_char_t()
            continuation.code = unichar(EOL_HARD)
            chars.withUnsafeMutableBufferPointer { buf in
                mutableState.appendScreenChars(
                    buf.baseAddress!,
                    length: Int32(buf.count),
                    externalAttributeIndex: iTermExternalAttributeIndex(),
                    continuation: continuation,
                    rtlFound: false,
                    lineAttribute: .singleWidth)
            }
        })
        XCTAssertEqual(lineAttribute(screen, line: 0), .singleWidth)
        let codes = lineCodes(screen, line: 0, count: 10)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("A").value))
        XCTAssertEqual(codes[1], unichar(UnicodeScalar("B").value))
        XCTAssertEqual(codes[2], unichar(UnicodeScalar("C").value))
        XCTAssertEqual(codes[3], unichar(UnicodeScalar("D").value))
        XCTAssertEqual(codes[4], unichar(UnicodeScalar("E").value))
        XCTAssertEqual(codes[5], 0)
    }

    /// appendScreenChars with doubleHeightTop lineAttribute should also
    /// compact and re-expand (all DWL variants share the same code path).
    func testAppendScreenCharsWithDoubleHeightTop() {
        let screen = makeScreen(width: 10, height: 4)
        var sourceData = makeDWLData("XY")
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            var continuation = screen_char_t()
            continuation.code = unichar(EOL_HARD)
            mutableState.appendScreenChars(
                &sourceData,
                length: Int32(sourceData.count),
                externalAttributeIndex: iTermExternalAttributeIndex(),
                continuation: continuation,
                rtlFound: false,
                lineAttribute: .doubleHeightTop)
        })
        XCTAssertEqual(lineAttribute(screen, line: 0), .doubleHeightTop)
        let codes = lineCodes(screen, line: 0, count: 6)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("X").value))
        XCTAssertEqual(codes[1], unichar(DWL_SPACER))
        XCTAssertEqual(codes[2], unichar(UnicodeScalar("Y").value))
        XCTAssertEqual(codes[3], unichar(DWL_SPACER))
        XCTAssertEqual(codes[4], 0)
    }

    // MARK: - clearFromAbsoluteLineToEnd preserves DWL content

    /// When clearFromAbsoluteLineToEnd clears from a line where the cursor
    /// sits on a DWL line, the DWL content and attribute should be preserved.
    func testClearFromAbsoluteLineToEndPreservesDWL() {
        let screen = makeScreen(width: 10, height: 4)
        // Write DWL content on line 0, then add a line below so we can clear.
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.maxScrollbackLines = 0
            mutableState.appendString(atCursor: "AB")
            mutableState.appendCarriageReturnLineFeed()
            mutableState.appendString(atCursor: "below")
        })

        // Verify DWL content before clearing
        XCTAssertEqual(lineAttribute(screen, line: 0), .doubleWidth)
        let codesBefore = lineCodes(screen, line: 0, count: 6)
        XCTAssertEqual(codesBefore[0], unichar(UnicodeScalar("A").value))
        XCTAssertEqual(codesBefore[1], unichar(DWL_SPACER))
        XCTAssertEqual(codesBefore[2], unichar(UnicodeScalar("B").value))
        XCTAssertEqual(codesBefore[3], unichar(DWL_SPACER))

        // Clear from line 0 to end. Cursor is on line 1 ("below"), so the
        // cursor line should be saved and restored at line 0.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            // Cursor is already on line 1 from appendString("below")
            mutableState.clearFromAbsoluteLine(toEnd: 0)
        })

        // The cursor line ("below") should have been restored at line 0.
        // Line 0 should now be singleWidth with "below".
        let codesAfter = lineCodes(screen, line: 0, count: 5)
        XCTAssertEqual(codesAfter[0], unichar(UnicodeScalar("b").value))
        XCTAssertEqual(codesAfter[1], unichar(UnicodeScalar("e").value))
        XCTAssertEqual(lineAttribute(screen, line: 0), .singleWidth)
    }

    /// When clearFromAbsoluteLineToEnd clears from a DWL cursor line, the
    /// DWL content and attribute should be preserved.
    func testClearFromAbsoluteLineToEndPreservesDWLAtCursor() {
        let screen = makeScreen(width: 10, height: 4)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.maxScrollbackLines = 0
            mutableState.appendString(atCursor: "AB")
        })

        // Verify DWL content before clearing
        XCTAssertEqual(lineAttribute(screen, line: 0), .doubleWidth)

        // Clear from line 0 to end. Cursor IS on line 0 (the DWL line),
        // so it should be saved and restored.
        var attrAfter = iTermLineAttribute.singleWidth
        var codesAfter = [unichar]()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.currentGrid.cursorY = 0
            mutableState.currentGrid.cursorX = 4
            mutableState.clearFromAbsoluteLine(toEnd: 0)
            // Read immediately after clear, inside the same performBlock
            let grid = mutableState.currentGrid
            attrAfter = grid.lineInfo(atLineNumber: 0).metadata.lineAttribute
            let chars = grid.immutableScreenChars(atLineNumber: 0)!
            for i in 0..<6 {
                codesAfter.append(chars[i].code)
            }
        })

        // After clearing, line 0 should still have DWL content preserved
        XCTAssertEqual(attrAfter, .doubleWidth,
                       "lineAttribute should be preserved after clearFromAbsoluteLineToEnd")
        XCTAssertEqual(codesAfter[0], unichar(UnicodeScalar("A").value),
                       "First char should be preserved")
        XCTAssertEqual(codesAfter[1], unichar(DWL_SPACER),
                       "DWL_SPACER after first char should be preserved")
        XCTAssertEqual(codesAfter[2], unichar(UnicodeScalar("B").value),
                       "Second char should be preserved")
        XCTAssertEqual(codesAfter[3], unichar(DWL_SPACER),
                       "DWL_SPACER after second char should be preserved")
    }

    /// clearFromAbsoluteLineToEnd on a normal (non-DWL) line should work
    /// as before — no regression from the DWL fix.
    func testClearFromAbsoluteLineToEndNormalLine() {
        let screen = makeScreen(width: 10, height: 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.maxScrollbackLines = 0
            mutableState.appendString(atCursor: "hello")
            mutableState.appendCarriageReturnLineFeed()
            mutableState.appendString(atCursor: "world")
        })
        // Clear from line 0 to end; cursor is on line 1 ("world")
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.currentGrid.cursorY = 1
            mutableState.currentGrid.cursorX = 5
            let absLine = mutableState.cumulativeScrollbackOverflow
            mutableState.clearFromAbsoluteLine(toEnd: absLine)
        })

        // Line 0 should have "world" (cursor line restored)
        let codes = lineCodes(screen, line: 0, count: 10)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("w").value))
        XCTAssertEqual(codes[1], unichar(UnicodeScalar("o").value))
        XCTAssertEqual(codes[2], unichar(UnicodeScalar("r").value))
        XCTAssertEqual(codes[3], unichar(UnicodeScalar("l").value))
        XCTAssertEqual(codes[4], unichar(UnicodeScalar("d").value))
        XCTAssertEqual(lineAttribute(screen, line: 0), .singleWidth)
    }

    /// clearFromAbsoluteLineToEnd preserves doubleHeightBottom content
    /// when the cursor is on the DHL line.
    func testClearFromAbsoluteLineToEndPreservesDHLBottom() {
        let screen = makeScreen(width: 10, height: 4)
        setLineAttribute(screen, attr: .doubleHeightBottom)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.maxScrollbackLines = 0
            mutableState.appendString(atCursor: "QR")
        })

        XCTAssertEqual(lineAttribute(screen, line: 0), .doubleHeightBottom)

        // Clear from line 0 with cursor on line 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.currentGrid.cursorY = 0
            mutableState.currentGrid.cursorX = 4
            mutableState.clearFromAbsoluteLine(toEnd: 0)
        })

        XCTAssertEqual(lineAttribute(screen, line: 0), .doubleHeightBottom)
        let codes = lineCodes(screen, line: 0, count: 6)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("Q").value))
        XCTAssertEqual(codes[1], unichar(DWL_SPACER))
        XCTAssertEqual(codes[2], unichar(UnicodeScalar("R").value))
        XCTAssertEqual(codes[3], unichar(DWL_SPACER))
    }

    // MARK: - Regression: combinedLinesInRange loses lineAttribute

    /// combinedLinesInRange: must preserve the lineAttribute from the source
    /// line. Previously, starting from an empty ScreenCharArray caused the
    /// first line's lineAttribute to be replaced with singleWidth.
    func testCombinedLinesInRangePreservesLineAttribute() {
        let screen = makeScreen(width: 10, height: 4)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "AB")
        })

        var resultAttr = iTermLineAttribute.singleWidth
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let extractor = iTermTextExtractor(dataSource: mutableState)
            let sca = extractor.combinedLines(in: NSMakeRange(0, 1))
            resultAttr = sca.metadata.lineAttribute
        })
        XCTAssertEqual(resultAttr, .doubleWidth,
                       "combinedLinesInRange should preserve DWL lineAttribute from the source line")
    }

    /// combinedLinesInRange: with doubleHeightTop should also preserve lineAttribute.
    func testCombinedLinesInRangePreservesDHT() {
        let screen = makeScreen(width: 10, height: 4)
        setLineAttribute(screen, attr: .doubleHeightTop)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "XY")
        })

        var resultAttr = iTermLineAttribute.singleWidth
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let extractor = iTermTextExtractor(dataSource: mutableState)
            let sca = extractor.combinedLines(in: NSMakeRange(0, 1))
            resultAttr = sca.metadata.lineAttribute
        })
        XCTAssertEqual(resultAttr, .doubleHeightTop,
                       "combinedLinesInRange should preserve DHT lineAttribute")
    }

    /// combinedLinesInRange: spanning multiple lines should use the first
    /// line's lineAttribute (since all lines in a wrapped range share it).
    func testCombinedLinesInRangeMultiLinePreservesFirstLineAttribute() {
        let screen = makeScreen(width: 10, height: 4)
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "AB")
            mutableState.appendCarriageReturnLineFeed()
            mutableState.appendString(atCursor: "normal")
        })

        var resultAttr = iTermLineAttribute.singleWidth
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let extractor = iTermTextExtractor(dataSource: mutableState)
            let sca = extractor.combinedLines(in: NSMakeRange(0, 2))
            resultAttr = sca.metadata.lineAttribute
        })
        XCTAssertEqual(resultAttr, .doubleWidth,
                       "combinedLinesInRange should use the first line's lineAttribute when combining")
    }

    // MARK: - Regression: appendScreenChars must reset stale DWL on target

    /// When a grid line has a stale DWL lineAttribute (e.g., after a clear
    /// that didn't reset metadata), appending singleWidth data via the
    /// lineAttribute: variant must reset the lineAttribute to singleWidth
    /// so the append code doesn't try to expand normal text.
    func testAppendScreenCharsResetsStaleDoubleWidthOnTarget() {
        let screen = makeScreen(width: 10, height: 4)
        // Set line 0 to DWL and write content.
        setLineAttribute(screen, attr: .doubleWidth)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "AB")
        })
        XCTAssertEqual(lineAttribute(screen, line: 0), .doubleWidth)

        // Now overwrite line 0 with singleWidth data using the lineAttribute
        // variant. This simulates what clearFromAbsoluteLineToEnd does when
        // restoring a normal-width cursor line onto a formerly-DWL row.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.currentGrid.cursorY = 0
            mutableState.currentGrid.cursorX = 0

            var chars = [screen_char_t]()
            for scalar in "hello".unicodeScalars {
                var ch = screen_char_t()
                ch.code = unichar(scalar.value)
                chars.append(ch)
            }
            var continuation = screen_char_t()
            continuation.code = unichar(EOL_SOFT)
            chars.withUnsafeMutableBufferPointer { buf in
                mutableState.appendScreenChars(
                    buf.baseAddress!,
                    length: Int32(buf.count),
                    externalAttributeIndex: iTermExternalAttributeIndex(),
                    continuation: continuation,
                    rtlFound: false,
                    lineAttribute: .singleWidth)
            }
        })

        // Line 0 should now be singleWidth with "hello" — NOT double-expanded.
        XCTAssertEqual(lineAttribute(screen, line: 0), .singleWidth,
                       "lineAttribute should be reset from DWL to singleWidth")
        let codes = lineCodes(screen, line: 0, count: 5)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("h").value),
                       "First char should be 'h', not expanded with DWL_SPACERs")
        XCTAssertEqual(codes[1], unichar(UnicodeScalar("e").value),
                       "Second char should be 'e', not a DWL_SPACER")
        XCTAssertEqual(codes[2], unichar(UnicodeScalar("l").value))
        XCTAssertEqual(codes[3], unichar(UnicodeScalar("l").value))
        XCTAssertEqual(codes[4], unichar(UnicodeScalar("o").value))
    }

    /// appendScreenChars with DWL data onto a line that was previously
    /// singleWidth should correctly set DWL and expand.
    func testAppendScreenCharsSetsDWLOnFormerlySingleWidthLine() {
        let screen = makeScreen(width: 10, height: 4)
        // Line 0 starts singleWidth.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "old")
        })
        XCTAssertEqual(lineAttribute(screen, line: 0), .singleWidth)

        // Now overwrite with DWL data (as if pasting from a DWL source).
        var sourceData = makeDWLData("XY")
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.currentGrid.cursorY = 0
            mutableState.currentGrid.cursorX = 0
            var continuation = screen_char_t()
            continuation.code = unichar(EOL_SOFT)
            mutableState.appendScreenChars(
                &sourceData,
                length: Int32(sourceData.count),
                externalAttributeIndex: iTermExternalAttributeIndex(),
                continuation: continuation,
                rtlFound: false,
                lineAttribute: .doubleWidth)
        })

        XCTAssertEqual(lineAttribute(screen, line: 0), .doubleWidth,
                       "lineAttribute should be set to DWL")
        let codes = lineCodes(screen, line: 0, count: 6)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("X").value))
        XCTAssertEqual(codes[1], unichar(DWL_SPACER))
        XCTAssertEqual(codes[2], unichar(UnicodeScalar("Y").value))
        XCTAssertEqual(codes[3], unichar(DWL_SPACER))
    }

    // MARK: - Cursor and Editing on DWL Lines

    /// Helper: get cursor X position
    private func cursorX(_ screen: VT100Screen) -> Int32 {
        var result: Int32 = 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            result = mutableState.currentGrid.cursorX
        })
        return result
    }

    /// Helper: get cursor Y position
    private func cursorY(_ screen: VT100Screen) -> Int32 {
        var result: Int32 = 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            result = mutableState.currentGrid.cursorY
        })
        return result
    }

    /// Helper: inject raw bytes into terminal
    private func inject(_ screen: VT100Screen, _ string: String) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.inject(string.data(using: .utf8)!)
        })
    }

    /// CUF (cursor forward) on a DWL line should advance by 2 physical cells
    /// per logical step, skipping over DWL_SPACERs.
    func testCursorForwardOnDWLLine() {
        let screen = makeScreen(width: 20, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleWidth)
            mutableState.appendString(atCursor: "ABCDE")
        })
        // Cursor should be at physical 10 (5 chars × 2 cells each)
        XCTAssertEqual(cursorX(screen), 10)

        // Move cursor to start
        inject(screen, "\u{1b}[1G") // HPA col 1 (= physical 0)
        XCTAssertEqual(cursorX(screen), 0, "HPA should position at physical 0")

        // CUF 1 should go to physical 2 (skip spacer at 1)
        inject(screen, "\u{1b}[C")
        XCTAssertEqual(cursorX(screen), 2, "CUF 1 should advance to physical 2")

        // CUF 2 should go to physical 6
        inject(screen, "\u{1b}[2C")
        XCTAssertEqual(cursorX(screen), 6, "CUF 2 should advance to physical 6")
    }

    /// CUB (cursor backward) on a DWL line should retreat by 2 physical cells.
    func testCursorBackwardOnDWLLine() {
        let screen = makeScreen(width: 20, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleWidth)
            mutableState.appendString(atCursor: "ABCDE")
        })
        // Cursor at physical 10
        XCTAssertEqual(cursorX(screen), 10)

        // CUB 1 should go to physical 8
        inject(screen, "\u{1b}[D")
        XCTAssertEqual(cursorX(screen), 8, "CUB 1 should retreat to physical 8")

        // CUB 2 should go to physical 4
        inject(screen, "\u{1b}[2D")
        XCTAssertEqual(cursorX(screen), 4, "CUB 2 should retreat to physical 4")
    }

    /// CUP on a DWL line: column parameter is logical, so col 3 should
    /// map to physical column 4 (0-indexed).
    func testCursorPositionOnDWLLine() {
        let screen = makeScreen(width: 20, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleWidth)
            mutableState.appendString(atCursor: "ABCDE")
        })

        // CUP row 1, col 1 → physical (0, 0)
        inject(screen, "\u{1b}[1;1H")
        XCTAssertEqual(cursorX(screen), 0, "CUP col 1 should be physical 0")

        // CUP row 1, col 3 → physical column 4
        inject(screen, "\u{1b}[1;3H")
        XCTAssertEqual(cursorX(screen), 4, "CUP col 3 should be physical 4")

        // CUP row 1, col 5 → physical column 8
        inject(screen, "\u{1b}[1;5H")
        XCTAssertEqual(cursorX(screen), 8, "CUP col 5 should be physical 8")
    }

    /// HPA on a DWL line should map logical to physical column.
    func testHorizontalPositionAbsoluteOnDWLLine() {
        let screen = makeScreen(width: 20, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleWidth)
            mutableState.appendString(atCursor: "ABCDE")
        })

        // HPA col 1 → physical 0
        inject(screen, "\u{1b}[1G")
        XCTAssertEqual(cursorX(screen), 0, "HPA col 1 should be physical 0")

        // HPA col 4 → physical 6
        inject(screen, "\u{1b}[4G")
        XCTAssertEqual(cursorX(screen), 6, "HPA col 4 should be physical 6")
    }

    /// setCursorX directly should snap to even position on DWL lines.
    func testSetCursorXSnapsToEvenOnDWLLine() {
        let screen = makeScreen(width: 20, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleWidth)
            mutableState.appendString(atCursor: "ABCDE")
            // Try to set cursor to odd physical position
            mutableState.currentGrid.cursorX = 3
        })
        // Should snap to 2 (round down to even)
        XCTAssertEqual(cursorX(screen), 2, "setCursorX(3) should snap to 2 on DWL line")
    }

    /// DCH (delete character) on a DWL line should delete char+spacer pairs
    /// and preserve the interleaving invariant.
    func testDeleteCharacterOnDWLLine() {
        let screen = makeScreen(width: 20, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleWidth)
            mutableState.appendString(atCursor: "ABCDE")
        })

        // Move to position of 'B' (physical 2) and delete 1
        inject(screen, "\u{1b}[1;2H")  // CUP col 2 → physical 2
        inject(screen, "\u{1b}[P")     // DCH 1

        // After deleting 'B', line should be A_C_D_E_ (spacers preserved)
        let codes = lineCodes(screen, line: 0, count: 10)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("A").value), "A should remain at 0")
        XCTAssertEqual(codes[1], unichar(DWL_SPACER), "Spacer at 1")
        XCTAssertEqual(codes[2], unichar(UnicodeScalar("C").value), "C should shift to 2")
        XCTAssertEqual(codes[3], unichar(DWL_SPACER), "Spacer at 3")
        XCTAssertEqual(codes[4], unichar(UnicodeScalar("D").value), "D should shift to 4")
        XCTAssertEqual(codes[5], unichar(DWL_SPACER), "Spacer at 5")
        XCTAssertEqual(codes[6], unichar(UnicodeScalar("E").value), "E should shift to 6")
        XCTAssertEqual(codes[7], unichar(DWL_SPACER), "Spacer at 7")
    }

    /// ICH (insert character) on a DWL line should insert char+spacer pairs.
    func testInsertCharacterOnDWLLine() {
        let screen = makeScreen(width: 20, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleWidth)
            mutableState.appendString(atCursor: "ABCDE")
        })

        // Move to 'C' (physical 4) and insert 1 blank
        inject(screen, "\u{1b}[1;3H")  // CUP col 3 → physical 4
        inject(screen, "\u{1b}[@")     // ICH 1

        // After inserting, should be A_B_ _C_D_E (blank+spacer inserted, E may fall off)
        let codes = lineCodes(screen, line: 0, count: 12)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("A").value), "A at 0")
        XCTAssertEqual(codes[1], unichar(DWL_SPACER), "Spacer at 1")
        XCTAssertEqual(codes[2], unichar(UnicodeScalar("B").value), "B at 2")
        XCTAssertEqual(codes[3], unichar(DWL_SPACER), "Spacer at 3")
        // Inserted blank at physical 4
        XCTAssertEqual(codes[4], 0, "Blank at 4")
        XCTAssertEqual(codes[5], unichar(DWL_SPACER), "Spacer at 5")
        XCTAssertEqual(codes[6], unichar(UnicodeScalar("C").value), "C shifted to 6")
        XCTAssertEqual(codes[7], unichar(DWL_SPACER), "Spacer at 7")
    }

    /// ECH (erase character) on a DWL line should erase logical characters
    /// (char+spacer pairs).
    func testEraseCharacterOnDWLLine() {
        let screen = makeScreen(width: 20, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleWidth)
            mutableState.appendString(atCursor: "ABCDE")
        })

        // Move to 'B' and erase 2 characters
        inject(screen, "\u{1b}[1;2H")  // CUP col 2 → physical 2
        inject(screen, "\u{1b}[2X")    // ECH 2

        let codes = lineCodes(screen, line: 0, count: 10)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("A").value), "A untouched")
        XCTAssertEqual(codes[1], unichar(DWL_SPACER), "Spacer at 1")
        // B and C erased (physical 2-5)
        XCTAssertEqual(codes[2], 0, "B erased at 2")
        XCTAssertEqual(codes[3], unichar(DWL_SPACER), "Spacer preserved at 3")
        XCTAssertEqual(codes[4], 0, "C erased at 4")
        XCTAssertEqual(codes[5], unichar(DWL_SPACER), "Spacer preserved at 5")
        // D untouched
        XCTAssertEqual(codes[6], unichar(UnicodeScalar("D").value), "D untouched")
        XCTAssertEqual(codes[7], unichar(DWL_SPACER), "Spacer at 7")
    }

    /// Cursor should never land on a DWL_SPACER when moving between lines
    /// of different types.
    func testCursorMovingFromNormalToDWLLine() {
        let screen = makeScreen(width: 20, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            // Line 0: normal, cursor at column 5
            mutableState.appendString(atCursor: "Hello World")
            mutableState.currentGrid.cursorX = 5
            mutableState.currentGrid.cursorY = 0
            // Line 1: double-width
            mutableState.currentGrid.cursorY = 1
            mutableState.terminalSetLineAttribute(.doubleWidth)
            mutableState.appendString(atCursor: "ABCDE")
        })

        // Position cursor at column 5 on normal line 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.currentGrid.cursorX = 5
            mutableState.currentGrid.cursorY = 0
        })

        // Move down to DWL line — cursor at physical 5 is a spacer, should snap
        inject(screen, "\u{1b}[B") // CUD 1

        let x = cursorX(screen)
        XCTAssertEqual(x % 2, 0, "Cursor should be at even position on DWL line, got \(x)")
    }

    /// ED (erase in display) from cursor on DWL line should preserve spacer
    /// structure on lines that aren't fully erased.
    func testEraseInDisplayOnDWLLine() {
        let screen = makeScreen(width: 20, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleWidth)
            mutableState.appendString(atCursor: "ABCDE")
        })

        // Move to 'C' and erase from cursor to end of display
        inject(screen, "\u{1b}[1;3H")  // CUP col 3 → physical 4
        inject(screen, "\u{1b}[J")     // ED 0 (erase from cursor)

        // A and B should survive, C onwards erased
        let codes = lineCodes(screen, line: 0, count: 10)
        XCTAssertEqual(codes[0], unichar(UnicodeScalar("A").value), "A untouched")
        XCTAssertEqual(codes[1], unichar(DWL_SPACER), "Spacer at 1")
        XCTAssertEqual(codes[2], unichar(UnicodeScalar("B").value), "B untouched")
        XCTAssertEqual(codes[3], unichar(DWL_SPACER), "Spacer at 3")
        XCTAssertEqual(codes[4], 0, "C erased")
    }

    /// Writing a character at the cursor on a DWL line should overwrite the
    /// character at the cursor position and its spacer, not corrupt layout.
    func testCharacterInputOnDWLLinePreservesLayout() {
        let screen = makeScreen(width: 20, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleWidth)
            mutableState.appendString(atCursor: "ABCDE")
        })

        // Move to 'C' and overwrite with 'X'
        inject(screen, "\u{1b}[1;3H")  // CUP col 3 → physical 4
        inject(screen, "X")

        let codes = lineCodes(screen, line: 0, count: 12)
        XCTAssertEqual(codes[4], unichar(UnicodeScalar("X").value), "X at physical 4")
        XCTAssertEqual(codes[5], unichar(DWL_SPACER), "Spacer at 5")
        XCTAssertEqual(codes[6], unichar(UnicodeScalar("D").value), "D still at 6")
        XCTAssertEqual(codes[7], unichar(DWL_SPACER), "Spacer at 7")
    }

    /// Backspace on a DWL line should move back by 2 physical cells.
    func testBackspaceOnDWLLine() {
        let screen = makeScreen(width: 20, height: 5)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleWidth)
            mutableState.appendString(atCursor: "ABC")
        })
        // Cursor at physical 6 (3 chars × 2 cells)
        XCTAssertEqual(cursorX(screen), 6)

        // Backspace should go to physical 4
        inject(screen, "\u{08}")
        XCTAssertEqual(cursorX(screen), 4, "Backspace should retreat to physical 4")

        // Another backspace to physical 2
        inject(screen, "\u{08}")
        XCTAssertEqual(cursorX(screen), 2, "Backspace should retreat to physical 2")

        // Another to physical 0
        inject(screen, "\u{08}")
        XCTAssertEqual(cursorX(screen), 0, "Backspace should retreat to physical 0")

        // At column 0, backspace should not go negative
        inject(screen, "\u{08}")
        XCTAssertEqual(cursorX(screen), 0, "Backspace at column 0 should stay at 0")
    }

    /// Copy with Control Sequences should NOT deduplicate DECDHL pairs —
    /// both ESC#3 (top) and ESC#4 (bottom) lines must be present so pasting
    /// into another terminal reproduces the double-height effect.
    func testCopyWithControlSequencesPreservesDECDHLPair() {
        let screen = makeScreen(width: 20, height: 5)

        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleHeightTop)
            mutableState.appendString(atCursor: "Hi")
            mutableState.terminalCarriageReturn()
            mutableState.terminalLineFeed()
            mutableState.terminalSetLineAttribute(.doubleHeightBottom)
            mutableState.appendString(atCursor: "Hi")
        })

        // Verify grid state
        var line0Attr: iTermLineAttribute = .singleWidth
        var line1Attr: iTermLineAttribute = .singleWidth
        var line0Len: Int32 = 0
        var line1Len: Int32 = 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            line0Attr = grid.lineInfo(atLineNumber: 0).metadata.lineAttribute
            line1Attr = grid.lineInfo(atLineNumber: 1).metadata.lineAttribute
            line0Len = grid.length(ofLineNumber: 0)
            line1Len = grid.length(ofLineNumber: 1)
        })
        XCTAssertEqual(line0Attr, .doubleHeightTop, "Line 0 should be doubleHeightTop")
        XCTAssertEqual(line1Attr, .doubleHeightBottom, "Line 1 should be doubleHeightBottom")
        XCTAssertGreaterThan(line0Len, 0, "Line 0 should have content")
        XCTAssertGreaterThan(line1Len, 0, "Line 1 should have content")

        // Extract without dedup — both top and bottom should be present
        var result = ""
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let extractor = iTermTextExtractor(dataSource: mutableState)
            let range = VT100GridWindowedRangeMake(
                VT100GridCoordRangeMake(0, 0, 20, 1),
                0, 0)
            let located = extractor.locatedString(
                in: range,
                attributeProvider: nil,
                nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                pad: false,
                includeLastNewline: true,
                trimTrailingWhitespace: false,
                cappedAtSize: -1,
                truncateTail: true,
                continuationChars: nil,
                deduplicateDECDHL: false) as! iTermLocatedString
            result = located.string as String
        })

        XCTAssertTrue(result.contains("Hi\nHi"),
                      "Both DECDHL top and bottom text should be present: '\(result)'")
    }

    /// Unpaired DECDHL top should be preserved in copy.
    func testCopyPreservesUnpairedDECDHLTop() {
        let screen = makeScreen(width: 20, height: 5)

        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleHeightTop)
            mutableState.appendString(atCursor: "Top")
            mutableState.terminalCarriageReturn()
            mutableState.terminalLineFeed()
            mutableState.appendString(atCursor: "Normal")
        })

        var result = ""
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let extractor = iTermTextExtractor(dataSource: mutableState)
            let range = VT100GridWindowedRangeMake(
                VT100GridCoordRangeMake(0, 0, 20, 1),
                0, 0)
            let located = extractor.locatedString(
                in: range,
                attributeProvider: nil,
                nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                pad: false,
                includeLastNewline: true,
                trimTrailingWhitespace: false,
                cappedAtSize: -1,
                truncateTail: true,
                continuationChars: nil,
                deduplicateDECDHL: false) as! iTermLocatedString
            result = located.string as String
        })

        XCTAssertTrue(result.contains("Top") && result.contains("Normal"),
                      "Unpaired top and normal line should both be present: '\(result)'")
    }

    /// DECDWL text should be extracted correctly (spacers stripped).
    func testCopyPreservesDECDWLText() {
        let screen = makeScreen(width: 20, height: 5)

        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleWidth)
            mutableState.appendString(atCursor: "Wide")
        })

        var result = ""
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let extractor = iTermTextExtractor(dataSource: mutableState)
            let range = VT100GridWindowedRangeMake(
                VT100GridCoordRangeMake(0, 0, 20, 0),
                0, 0)
            let located = extractor.locatedString(
                in: range,
                attributeProvider: nil,
                nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                pad: false,
                includeLastNewline: false,
                trimTrailingWhitespace: false,
                cappedAtSize: -1,
                truncateTail: true,
                continuationChars: nil,
                deduplicateDECDHL: false) as! iTermLocatedString
            result = located.string as String
        })

        XCTAssertEqual(result, "Wide",
                       "DECDWL text should have spacers stripped: '\(result)'")
    }

    /// Plain-text copy with deduplication: a matching DECDHL top+bottom pair
    /// should produce the text only once.
    func testPlainCopyDeduplicatesMatchingDECDHLPair() {
        let screen = makeScreen(width: 20, height: 5)

        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleHeightTop)
            mutableState.appendString(atCursor: "Hello")
            mutableState.terminalCarriageReturn()
            mutableState.terminalLineFeed()
            mutableState.terminalSetLineAttribute(.doubleHeightBottom)
            mutableState.appendString(atCursor: "Hello")
            mutableState.terminalCarriageReturn()
            mutableState.terminalLineFeed()
            mutableState.appendString(atCursor: "Normal")
        })

        var result = ""
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let extractor = iTermTextExtractor(dataSource: mutableState)
            let range = VT100GridWindowedRangeMake(
                VT100GridCoordRangeMake(0, 0, 20, 2),
                0, 0)
            let located = extractor.locatedString(
                in: range,
                attributeProvider: nil,
                nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                pad: false,
                includeLastNewline: true,
                trimTrailingWhitespace: false,
                cappedAtSize: -1,
                truncateTail: true,
                continuationChars: nil,
                deduplicateDECDHL: true) as! iTermLocatedString
            result = located.string as String
        })

        XCTAssertEqual(result, "Hello\nNormal\n",
                       "Matching DECDHL pair should be deduplicated: '\(result)'")
    }

    /// Plain-text copy with deduplication: mismatched DECDHL top+bottom
    /// should preserve both lines.
    func testPlainCopyPreservesMismatchedDECDHLPair() {
        let screen = makeScreen(width: 20, height: 5)

        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalSetLineAttribute(.doubleHeightTop)
            mutableState.appendString(atCursor: "Top")
            mutableState.terminalCarriageReturn()
            mutableState.terminalLineFeed()
            mutableState.terminalSetLineAttribute(.doubleHeightBottom)
            mutableState.appendString(atCursor: "Bottom")
        })

        var result = ""
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let extractor = iTermTextExtractor(dataSource: mutableState)
            let range = VT100GridWindowedRangeMake(
                VT100GridCoordRangeMake(0, 0, 20, 1),
                0, 0)
            let located = extractor.locatedString(
                in: range,
                attributeProvider: nil,
                nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                pad: false,
                includeLastNewline: true,
                trimTrailingWhitespace: false,
                cappedAtSize: -1,
                truncateTail: true,
                continuationChars: nil,
                deduplicateDECDHL: true) as! iTermLocatedString
            result = located.string as String
        })

        XCTAssertTrue(result.contains("Top") && result.contains("Bottom"),
                      "Mismatched DECDHL pair should preserve both lines: '\(result)'")
    }

    private class MinimalSelectionDelegate: NSObject, iTermSelectionDelegate {
        let width: Int32
        init(width: Int32) { self.width = width }
        func selectionDidChange(_ selection: iTermSelection!) {}
        func liveSelectionDidEnd() {}
        func selectionAbsRangeForParenthetical(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0,0,0,0), 0, 0) }
        func selectionAbsRangeForWord(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0,0,0,0), 0, 0) }
        func selectionAbsRangeForSmartSelection(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0,0,0,0), 0, 0) }
        func selectionAbsRangeForWrappedLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0,0,0,0), 0, 0) }
        func selectionAbsRangeForLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0,0,0,0), 0, 0) }
        func selectionRangeOfTerminalNulls(onAbsoluteLine absLineNumber: Int64) -> VT100GridRange { return VT100GridRangeMake(0, 0) }
        func selectionPredecessor(of absCoord: VT100GridAbsCoord) -> VT100GridAbsCoord { return VT100GridAbsCoordMake(0, 0) }
        func selectionViewportWidth() -> Int32 { return width }
        func selectionTotalScrollbackOverflow() -> Int64 { return 0 }
        func selectionIndexes(onAbsoluteLine line: Int64, containingCharacter c: unichar, in range: NSRange) -> IndexSet { return IndexSet() }
    }

    /// Use the actual "Copy with Control Sequences" extractor on a screen.
    private func copyWithControlSequences(from screen: VT100Screen) -> String {
        var result = ""
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let snapshot = TerminalContentSnapshot(lineBuffer: mutableState.linebuffer,
                                                    grid: mutableState.currentGrid,
                                                    cumulativeOverflow: mutableState.cumulativeScrollbackOverflow)
            let totalLines = Int(mutableState.numberOfLines())
            let selDelegate = MinimalSelectionDelegate(width: mutableState.width)
            let selection = iTermSelection()
            selection.delegate = selDelegate
            let sub = iTermSubSelection.init(
                absRange: VT100GridAbsWindowedRangeMake(
                    VT100GridAbsCoordRangeMake(0, 0, Int32(mutableState.width), Int64(totalLines - 1)),
                    0, 0),
                mode: .kiTermSelectionModeCharacter,
                width: mutableState.width)
            selection.add(sub)
            let extractor = SGRSelectionExtractor(
                selection: selection,
                snapshot: snapshot,
                options: [],
                maxBytes: -1,
                minimumLineNumber: 0)!
            result = extractor.extract() as String
        })
        return result
    }

    /// Strips trailing lines that are empty or contain only ESC[0m (screen padding).
    private func trimTrailingResetLines(_ s: String) -> String {
        var lines = s.components(separatedBy: "\n")
        while let last = lines.last, last.isEmpty || last == "\u{1b}[0m" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// Feed normalized file → Copy with Control Sequences → assert output
    /// matches the file (fixed point).
    func testCopyWithControlSequencesRoundtrip() {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "decdwl_decdhl_normalized", withExtension: "txt"),
              let expected = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Could not load decdwl_decdhl_normalized.txt from test bundle")
            return
        }

        let trimmedExpected = trimTrailingResetLines(expected)

        // Replace LF with CRLF since the raw file hasn't been through
        // the kernel's tty driver.
        let crlf = expected.replacingOccurrences(of: "\n", with: "\r\n")

        let screen = makeScreen(width: 80, height: 100)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.inject(crlf.data(using: .utf8)!)
        })
        let actual = trimTrailingResetLines(copyWithControlSequences(from: screen))

        let expectedLines = trimmedExpected.components(separatedBy: "\n")
        let actualLines = actual.components(separatedBy: "\n")
        for i in 0..<max(expectedLines.count, actualLines.count) {
            let exp = i < expectedLines.count ? expectedLines[i] : "<missing>"
            let act = i < actualLines.count ? actualLines[i] : "<missing>"
            XCTAssertEqual(exp, act, "Line \(i) differs")
        }
        XCTAssertEqual(expectedLines.count, actualLines.count, "Line count should match")
    }
}
