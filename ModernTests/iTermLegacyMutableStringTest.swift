//
//  iTermLegacyMutableStringTest.swift
//  iTerm2
//
//  Created by George Nachman on 4/29/25.
//

import XCTest
@testable import iTerm2SharedARC

func makeStyleChar(letter: UInt16) -> screen_char_t {
    var style = screen_char_t()
    style.code = letter
    style.foregroundColor = 1
    style.fgGreen = 2
    style.fgBlue = 3
    style.backgroundColor = 4
    style.bgGreen = 5
    style.bgBlue = 6
    style.foregroundColorMode = 1
    style.backgroundColorMode = 2
    style.complexChar = 0
    style.bold = 1
    style.faint = 0
    style.italic = 1
    style.blink = 0
    style.underline = 1
    style.image = 0
    style.strikethrough = 1
    style.underlineStyle = .single
    style.invisible = 0
    style.inverse = 1
    style.guarded = 0
    style.virtualPlaceholder = 0
    style.rtlStatus = .unknown
    return style
}

final class iTermLegacyMutableStringTests: XCTestCase {
    // Ported from iTermLegacyStyleString tests
    func testCellCountAndCharacter_atIndex() {
        let style = makeStyle()
        // initialize via width + character
        let firstCharCode = UInt16("H".utf16.first!)
        var char = style
        char.code = firstCharCode
        let count = 5
        let mutable = iTermLegacyMutableString(width: count, character: char)
        XCTAssertEqual(mutable.cellCount, count)

        // character at index 0 is repeated char
        for i in 0..<count {
            let c = mutable.character(at: i)
            XCTAssertEqual(c.code, firstCharCode)
            XCTAssertEqual(c.bold, style.bold)
            XCTAssertEqual(c.italic, style.italic)
            XCTAssertEqual(c.inverse, style.inverse)
            XCTAssertEqual(c.rtlStatus, .unknown)
        }
    }

    func testIsEmpty_andUsedLength() {
        let m = iTermLegacyMutableString(width: 3)
        // initially all zero
        let full = NSRange(location: 0, length: m.cellCount)
        XCTAssertTrue(m.isEmpty(range: full))
        XCTAssertEqual(m.usedLength(range: full), 0)
        // set code at index 2
        m.eraseCode(at: 0) // still zeros
        var style = makeStyle()
        style.code = UInt16("X".utf16.first!)
        m.sca.mutableLine[2] = style
        XCTAssertFalse(m.isEmpty(range: full))
        XCTAssertEqual(m.usedLength(range: full), 3)
    }

    func testStringValueAndScreenCharArray() {
        let text = "A漢B"
        let style = makeStyle()
        let msca = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca.append(text, fg: style, bg: style)
        let mutable = iTermLegacyMutableString(msca)
        XCTAssertEqual(mutable.screenCharArray.stringValue, text)
        XCTAssertEqual(mutable.cellCount, Int(msca.length))
    }

    func testDoubleWidthIndexesAndHydrate() {
        let text = "A漢B"
        let style = makeStyle()
        let msca0 = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca0.append(text, fg: style, bg: style)
        let mutable = iTermLegacyMutableString(msca0)
        let full = NSRange(location: 0, length: mutable.cellCount)
        let dw = mutable.doubleWidthIndexes(range: full, rebaseTo: 0)
        XCTAssertEqual(dw, IndexSet([2]))
        // hydrate
        let hyd = mutable.hydrate(range: NSRange(location: 1, length: 2))
        XCTAssertEqual(hyd.stringValue, "漢")
    }

    func testSubstringAndIsEqualRanges() {
        let text = "ABC"
        let style = makeStyle()
        let m = iTermLegacyMutableString(width: 2)
        m.erase(defaultChar: makeStyleChar(letter: UInt16("A".utf16.first!)))
        // substring from 1 to length 1
        let sub = m.substring(range: NSRange(location: 1, length: 1))
        XCTAssertEqual(sub.screenCharArray.stringValue, "A")
        // compare to ascii string
        let rhs = iTermASCIIString(data: Data("A".utf8), style: style, ea: nil)
        XCTAssertTrue(m.isEqual(lhsRange: NSRange(location: 1, length: 1), toString: rhs, startingAtIndex: 0))
    }

    func testDeltaStringAndBuildString() {
        let text = "Hi"
        let style = makeStyle()
        // Start with an empty mutable string and append "Hi"
        let m = iTermLegacyMutableString(width: 0)
        let ascii = iTermASCIIString(data: Data(text.utf8), style: style, ea: nil)
        m.append(string: ascii)

        let full = NSRange(location: 0, length: m.cellCount)
        let delta = m.deltaString(range: full)
        XCTAssertEqual(delta.string as String, "Hi")

        let builder = DeltaStringBuilder(count: delta.length)
        m.buildString(range: full, builder: builder)
        let built = builder.build()
        XCTAssertEqual(built.unsafeString as String, "Hi")
    }

    func testCloneAndMutableCloneIndependence() {
        let style = makeStyle()
        let m = iTermLegacyMutableString(width: 2)
        var char = style
        char.code = UInt16("X".utf16.first!)
        m.erase(defaultChar: char)
        let clone = m.clone()
        XCTAssertTrue(clone.isEqual(to: m))
        let mut = m.mutableClone() as! iTermMutableStringProtocolSwift
        XCTAssertTrue(mut.isEqual(to: m))
        mut.delete(range: 0..<1)
        XCTAssertNotEqual(mut.cellCount, m.cellCount)
    }

    // MARK: - mutation tests
    func testDeleteRangeObjcAndSwift() {
        let style = makeStyle()
        let m = iTermLegacyMutableString(width: 4)
        m.replace(range: 0..<4, with: iTermASCIIString(data: Data("1234".utf8), style: style, ea: nil))
        m.objcDelete(range: NSRange(location: 1, length: 2)) // deletes "23"
        XCTAssertEqual(m.screenCharArray.stringValue, "14")
        // swift delete
        m.delete(range: 0..<1)
        XCTAssertEqual(m.screenCharArray.stringValue, "4")
    }

    func testDeleteFromStartAndEnd() {
        let style = makeStyle()
        let m = iTermLegacyMutableString(width: 4)
        m.replace(range: 0..<4, with: iTermASCIIString(data: Data("WXYZ".utf8), style: style, ea: nil))
        m.deleteFromStart(1)
        XCTAssertEqual(m.screenCharArray.stringValue, "XYZ")
        m.deleteFromEnd(1)
        XCTAssertEqual(m.screenCharArray.stringValue, "XY")
    }

    func testAppendInsertReplace() {
        let style = makeStyle()
        let m = iTermLegacyMutableString(width: 0)
        let a = iTermASCIIString(data: Data("AB".utf8), style: style, ea: nil)
        m.append(string: a)
        XCTAssertEqual(m.screenCharArray.stringValue, "AB")
        // swift insert
        let b = iTermASCIIString(data: Data("C".utf8), style: style, ea: nil)
        m.insert(b, at: 1)
        XCTAssertEqual(m.screenCharArray.stringValue, "ACB")
        // replace
        let d = iTermASCIIString(data: Data("D".utf8), style: style, ea: nil)
        m.replace(range: 1..<2, with: d)
        XCTAssertEqual(m.screenCharArray.stringValue, "ADB")
    }

    func testResetRTLStatusAndSetRTLIndexes() {
        let style = makeStyle()
        var sct = style
        sct.code = UInt16("Z".utf16.first!)
        let m = iTermLegacyMutableString(width: 3)
        m.erase(defaultChar: sct)
        let idx = IndexSet([0,2])
        m.setRTLIndexes(idx)
        for i in 0..<m.cellCount {
            let c = m.character(at: i)
            XCTAssertEqual(c.rtlStatus, idx.contains(i) ? .RTL : .LTR)
        }
        m.resetRTLStatus()
        for i in 0..<m.cellCount {
            XCTAssertEqual(m.character(at: i).rtlStatus, .unknown)
        }
    }

    func testEAIndexCreateAndSetAndExternalAttribute() {
        let style = makeStyle()
        let m = iTermLegacyMutableString(width: 2)
        XCTAssertNil(m.eaIndex)
        let ea = iTermExternalAttribute(havingUnderlineColor: true,
                                        underlineColor: VT100TerminalColorValue(red:1,green:0,blue:0,mode:ColorModeNormal),
                                        url: nil, blockIDList: nil, controlCode: nil)
        let idx = m.eaIndex(createIfNeeded: true)!
        idx.setAttributes(ea, at: 1, count: 1)
        XCTAssertEqual(m.externalAttribute(at: 1), ea)
    }

    func testInitWidthAndCharacter() {
        // width initializer
        let mstr = iTermLegacyMutableString(width: 3)
        XCTAssertEqual(mstr.cellCount, 3)
        // width+character convenience init
        var style = makeStyle()
        style.code = UInt16("Z".utf16.first!)
        let mstr2 = iTermLegacyMutableString(width: 5, character: style)
        XCTAssertEqual(mstr2.cellCount, 5)
        for i in 0..<5 {
            XCTAssertEqual(mstr2.character(at: i).code, style.code)
        }
    }

    func testDeleteRangeAndDeleteMethods() {
        // Helper to create a fresh mutable string from ASCII
        func makeMstr(_ s: String) -> iTermLegacyMutableString {
            let style = makeStyle()
            let sca = MutableScreenCharArray.emptyLine(ofLength: 0)
            sca.append(s, fg: style, bg: style)
            return iTermLegacyMutableString(sca)
        }

        // objcDelete
        let mstr2 = makeMstr("ABCD")
        mstr2.objcDelete(range: NSRange(location: 1, length: 2))
        XCTAssertEqual(mstr2.cellCount, 2)
        XCTAssertEqual(mstr2.screenCharArray.stringValue, "AD")

        // delete(range:)
        let mstr3 = makeMstr("ABCD")
        mstr3.delete(range: 1..<3)
        XCTAssertEqual(mstr3.screenCharArray.stringValue, "AD")

        // deleteFromStart
        let mstr4 = makeMstr("ABCD")
        mstr4.deleteFromStart(2)
        XCTAssertEqual(mstr4.screenCharArray.stringValue, "CD")

        // deleteFromEnd
        let mstr5 = makeMstr("ABCD")
        mstr5.deleteFromEnd(2)
        XCTAssertEqual(mstr5.screenCharArray.stringValue, "AB")
    }

    func testReplaceAndInsertAndAppend() {
        let style = makeStyle()
        let base = iTermLegacyMutableString(width: 3)
        // populate with 'AAA'
        var defaultChar = style
        defaultChar.code = UInt16("A".utf16.first!)
        base.erase(defaultChar: defaultChar)

        // insert 'B' at index 1
        let bstr = iTermASCIIString(data: Data("B".utf8), style: style, ea: nil)
        base.insert(bstr, at: 1)
        XCTAssertEqual(base.screenCharArray.stringValue, "ABAA")

        // replace range [1..<3] with 'XY'
        let xysrc = iTermASCIIString(data: Data("XY".utf8), style: style, ea: nil)
        base.replace(range: 1..<3, with: xysrc)
        XCTAssertEqual(base.screenCharArray.stringValue, "AXYA")

        // objcReplace
        base.objcReplace(range: NSRange(location: 0, length: 1), with: bstr)
        XCTAssertEqual(base.screenCharArray.stringValue, "BXYA")

        // append string
        base.append(string: bstr)
        XCTAssertEqual(base.screenCharArray.stringValue, "BXYAB")
    }

    func testSetDWCSkipAndEraseCode() {
        let style = makeStyle()
        var c = style
        c.code = UInt16(DWC_RIGHT)
        let sca = MutableScreenCharArray.emptyLine(ofLength: 2)
        sca.setCharacter(style, in: NSRange(location: 0, length: 2))
        let mstr = iTermLegacyMutableString(sca)
        // set DWCSKIP at index 1
        mstr.setDWCSkip(at: 1)
        XCTAssertTrue(ScreenCharIsDWC_SKIP(mstr.character(at: 1)))
        // eraseCode at index 0
        mstr.eraseCode(at: 0)
        XCTAssertEqual(mstr.character(at: 0).code, 0)
        XCTAssertEqual(mstr.character(at: 0).complexChar, 0)
    }

    func testResetRTLAndSetRTLIndexes() {
        let style = makeStyle()
        var styleA = style
        styleA.code = UInt16("A".utf16.first!)
        let sca = MutableScreenCharArray.emptyLine(ofLength: 3)
        sca.append("AAA", fg: style, bg: style)
        let mstr = iTermLegacyMutableString(sca)
        mstr.setRTLIndexes(IndexSet([0,2]))
        XCTAssertEqual(mstr.character(at: 0).rtlStatus, .RTL)
        XCTAssertEqual(mstr.character(at: 1).rtlStatus, .LTR)
        XCTAssertEqual(mstr.character(at: 2).rtlStatus, .RTL)
        mstr.resetRTLStatus()
        for i in 0..<3 {
            XCTAssertEqual(mstr.character(at: i).rtlStatus, .unknown)
        }
    }

    func testSetExternalAttributesViaMetadata() {
        let style = makeStyle()
        let sca = MutableScreenCharArray.emptyLine(ofLength: 2)
        sca.append("AB", fg: style, bg: style)
        let mstr = iTermLegacyMutableString(sca)

        // create EA index and attach via metadata
        let eaIndex = iTermExternalAttributeIndex()
        let ea = iTermExternalAttribute(havingUnderlineColor: true,
                                        underlineColor: VT100TerminalColorValue(red:1,green:0,blue:0,mode:ColorModeNormal),
                                        url: nil, blockIDList: nil, controlCode: nil)
        eaIndex.setAttributes(ea, at: 1, count: 1)
        // set into metadata
        var metadata = iTermMetadataDefault()
        iTermMetadataSetExternalAttributes(&metadata, eaIndex)
        mstr.set(metadata: metadata)

        // now externalAttributesIndex should reflect that
        guard let idx = mstr.externalAttributesIndex() else {
            return XCTFail("Expected external attributes index")
        }
        XCTAssertNil(idx[0])
        XCTAssertEqual(idx[1], ea)
    }

    func testIsEqualToString_DifferentLengths() {
        let m1 = iTermLegacyMutableString(width: 2)
        let m2 = iTermLegacyMutableString(width: 3)
        XCTAssertFalse(m1.isEqual(to: m2))
    }

    func testIsEqualRangeOutOfBoundsOrRhsTooShort() {
        let m = iTermLegacyMutableString(width: 4)
        let rhs = iTermLegacyMutableString(width: 2)
        // lhsRange out of bounds
        XCTAssertFalse(m.isEqual(lhsRange: NSRange(location: 5, length: 1),
                                 toString: rhs,
                                 startingAtIndex: 0))
        // rhs too short for startingAtIndex + length
        XCTAssertFalse(m.isEqual(lhsRange: NSRange(location: 0, length: 2),
                                 toString: rhs,
                                 startingAtIndex: 2))
    }

    func testExternalAttributeAtWithoutEAIndex() {
        let m = iTermLegacyMutableString(width: 3)
        XCTAssertNil(m.externalAttribute(at: 1))
    }

    func testStringBySettingRTL_NilAndNonNil() {
        let charStyle = makeStyle()
        var ch = charStyle
        ch.code = UInt16("X".utf16.first!)
        let m = iTermLegacyMutableString(width: 3, character: ch)
        let full = NSRange(location: 0, length: m.cellCount)
        // non-nil RTL set
        let rtlSet = IndexSet([0,2])
        let r1 = m.stringBySettingRTL(in: full, rtlIndexes: rtlSet)
        for i in 0..<r1.cellCount {
            let status = r1.character(at: i).rtlStatus
            XCTAssertEqual(status, rtlSet.contains(i) ? .RTL : .LTR)
        }
        // nil ⇒ all unknown
        let r2 = m.stringBySettingRTL(in: full, rtlIndexes: nil)
        for i in 0..<r2.cellCount {
            XCTAssertEqual(r2.character(at: i).rtlStatus, .unknown)
        }
    }

    func testHydrateIntoMutableScreenCharArray() {
        // prepare source mutable string "1234"
        let style = makeStyle()
        var bufSca = MutableScreenCharArray.emptyLine(ofLength: 0)
        bufSca.append("1234", fg: style, bg: style)
        let m = iTermLegacyMutableString(bufSca)
        let dest = MutableScreenCharArray.emptyLine(ofLength: 6)
        dest.append("......", fg: style, bg: style)
        // hydrate "23" into positions 2..<4
        m.hydrate(into: dest,
                  destinationIndex: 2,
                  sourceRange: NSRange(location: 1, length: 2))
        let sub = dest.subArray(with: NSRange(location: 2, length: 2))
        XCTAssertEqual(sub.stringValue, "23")
    }

    func testHydrateIntoRawBufferAndExternalAttributes() {
        // make mutable with EA at index 1
        let style = makeStyle()
        var sca = MutableScreenCharArray.emptyLine(ofLength: 3)
        sca.append("ABC", fg: style, bg: style)
        let eaIndex = iTermExternalAttributeIndex()
        let ea = iTermExternalAttribute(havingUnderlineColor: true,
                                        underlineColor: VT100TerminalColorValue(red:1,green:2,blue:3,mode:ColorModeNormal),
                                        url: nil, blockIDList: nil, controlCode: nil)
        eaIndex.setAttributes(ea, at: 1, count: 1)
        sca.setExternalAttributesIndex(eaIndex)
        let m = iTermLegacyMutableString(sca)
        // raw buffer
        var buffer = [screen_char_t](repeating: screen_char_t(), count: 3)
        var destEA = iTermExternalAttributeIndex()
        let offset: Int32 = 5
        m.hydrate(into: &buffer,
                  eaIndex: destEA,
                  offset: offset,
                  range: NSRange(location: 0, length: 3))
        // buffer copied
        XCTAssertEqual(buffer[1].code, m.character(at: 1).code)
        // EA should be copied into destEA
        XCTAssertEqual(destEA.attribute(at: 1), ea)
    }

    func testHasEqualTrueAndFalse() {
        // create string "XYZ"
        let style = makeStyle()
        let sca = MutableScreenCharArray.emptyLine(ofLength: 0)
        sca.append("XYZ", fg: style, bg: style)
        let m = iTermLegacyMutableString(sca)
        // build matching buffer
        var buf = [screen_char_t](repeating: screen_char_t(), count: 3)
        for i in 0..<3 { buf[i] = m.character(at: i) }
        let eq = buf.withUnsafeBufferPointer { ptr in
            m.hasEqual(range: NSRange(location: 0, length: 3), to: ptr.baseAddress!)
        }
        XCTAssertTrue(eq)
        // mutate one entry
        buf[1].code = 0
        let neq = buf.withUnsafeBufferPointer { ptr in
            m.hasEqual(range: NSRange(location: 0, length: 3), to: ptr.baseAddress!)
        }
        XCTAssertFalse(neq)
    }

    func testSetExternalAttributesSetterNilAndNonNil() {
        // initial no EA
        let m = iTermLegacyMutableString(width: 2)
        XCTAssertNil(m.externalAttributesIndex())
        // set non-nil
        let eaSrc = iTermExternalAttributeIndex()
        let ea = iTermExternalAttribute(havingUnderlineColor: true,
                                        underlineColor: VT100TerminalColorValue(red:3,green:4,blue:5,mode:ColorModeNormal),
                                        url: nil, blockIDList: nil, controlCode: nil)
        eaSrc.setAttributes(ea, at: 0, count: 1)
        m.set(externalAttributes: eaSrc)
        let idx = m.externalAttributesIndex()!
        XCTAssertEqual(idx.attribute(at: 0), ea)
        // reset to nil
        m.set(externalAttributes: nil)
        XCTAssertNil(m.externalAttributesIndex())
        // setting nil again should remain nil and not crash
        m.set(externalAttributes: nil)
        XCTAssertNil(m.externalAttributesIndex())
    }

    func testUsedLengthOnEmptyString() {
        let m = iTermLegacyMutableString(width: 0)
        XCTAssertEqual(m.cellCount, 0)
        let full = NSRange(location: 0, length: 0)
        XCTAssertEqual(m.usedLength(range: full), 0)
    }

    func testRoundTrip() throws {
        // Construct original string
        let style = makeStyle()
        let sca = MutableScreenCharArray.emptyLine(ofLength: 2)
        sca.append("AB", fg: style, bg: style)
        let original = iTermLegacyMutableString(sca)

        // Attach external attributes metadata
        let eaIndex = iTermExternalAttributeIndex()
        let ea = iTermExternalAttribute(
            havingUnderlineColor: true,
            underlineColor: VT100TerminalColorValue(red: 1, green: 0, blue: 0, mode: ColorModeNormal),
            url: nil,
            blockIDList: nil,
            controlCode: nil
        )
        eaIndex.setAttributes(ea, at: 1, count: 1)
        var metadata = iTermMetadataDefault()
        metadata.timestamp = 1234.0
        metadata.rtlFound = true
        iTermMetadataSetExternalAttributes(&metadata, eaIndex)
        original.set(metadata: metadata)

        // Encode
        var encoder = EfficientEncoder()
        original.encodeEfficiently(encoder: &encoder)
        let encodedData = encoder.data

        var decoder = EfficientDecoder(encodedData)
        let decoded = try iTermLegacyMutableString.create(efficientDecoder: &decoder)

        // Verify round-trip equality
        XCTAssertTrue(original.isEqual(to: decoded))
    }

    func testTLVEncoder() throws {
        enum CodingKeys: Int32, TLVTag {
            case metadata
        }
        var tlvEncoder = EfficientTLVEncoder<CodingKeys>()
        let data = Data([1,2,3])
        tlvEncoder.put(tag: .metadata, value: data)

        var decoder = EfficientDecoder(tlvEncoder.data)
        var tlvDecoder: EfficientTLVDecoder<CodingKeys> = decoder.tlvDecoder()
        var dict = try tlvDecoder.decodeAll(required: Set([.metadata]))
        let decoded = try Data.create(efficientDecoder: &(dict[.metadata]!))

        XCTAssertEqual(data, decoded)
    }
}
