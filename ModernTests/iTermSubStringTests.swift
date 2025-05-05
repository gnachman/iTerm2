//
//  iTermSubStringTests.swift
//  iTerm2
//
//  Created by George Nachman on 4/29/25.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermSubStringTests: XCTestCase {
    private func makeStyle() -> screen_char_t {
        var style = screen_char_t()
        style.foregroundColor = 1
        style.fgGreen = 1
        style.fgBlue = 1
        style.backgroundColor = 0
        style.bgGreen = 0
        style.bgBlue = 0
        style.foregroundColorMode = 1
        style.backgroundColorMode = 0
        style.complexChar = 0
        style.bold = 0
        style.italic = 0
        style.rtlStatus = .unknown
        return style
    }

    func testSubstringRangeAndCount_characterAt() {
        let text = "ABCDE"
        let data = Data(text.utf8)
        let style = makeStyle()
        let base = iTermASCIIString(data: data, style: style, ea: nil)

        // Range<Int> initializer
        let subRange = 1..<4  // "BCD"
        let sub1 = iTermSubString(base: base, range: subRange)
        XCTAssertEqual(sub1.cellCount, subRange.count)
        XCTAssertEqual(sub1.screenCharArray.stringValue, "BCD")
        for i in 0..<sub1.cellCount {
            let c = sub1.character(at: i)
            XCTAssertEqual(Int(c.code), Int(text.utf8[text.index(text.startIndex, offsetBy: i+1)]))
        }

        // NSRange initializer
        let nsRange = NSRange(location: 2, length: 2) // "CD"
        let sub2 = iTermSubString(base: base, range: nsRange)
        XCTAssertEqual(sub2.cellCount, 2)
        XCTAssertEqual(sub2.screenCharArray.stringValue, "CD")
        XCTAssertEqual(sub2.character(at: 0).code, UInt16(text.utf8[text.index(text.startIndex, offsetBy: 2)]))
    }

    func testNestedSubstring_doesNotNestRanges() {
        let text = "WXYZ"
        let data = Data(text.utf8)
        let style = makeStyle()
        let base = iTermASCIIString(data: data, style: style, ea: nil)

        let sub = base.substring(range: NSRange(location: 1, length: 3)) // "XYZ"
        // substring of substring should refer to original base
        let nested = sub.substring(range: NSRange(location: 1, length: 1)) // "Y"
        XCTAssertEqual(nested.cellCount, 1)
        XCTAssertEqual(nested.screenCharArray.stringValue, "Y")
    }

    func testHydrateOnSubstring() {
        let text = "12345"
        let data = Data(text.utf8)
        let style = makeStyle()
        let base = iTermASCIIString(data: data, style: style, ea: nil)
        let sub = base.substring(range: NSRange(location: 2, length: 3)) // "345"

        // hydrate(range:) on sub
        let h = sub.hydrate(range: NSRange(location: 1, length: 2))
        XCTAssertEqual(Int(h.length), 2)
        XCTAssertEqual(h.stringValue, "45")

        // hydrate(into:destinationIndex:sourceRange:)
        let msca = MutableScreenCharArray.emptyLine(ofLength: 5)
        msca.append(".....", fg: style, bg: style)
        sub.hydrate(into: msca, destinationIndex: 0, sourceRange: NSRange(location: 0, length: 3))
        let segment = msca.subArray(with: NSRange(location: 0, length: 3))
        XCTAssertEqual(segment.stringValue, "345")
    }

    func testDeltaString_buildString_onSubstring() {
        let text = "mnopq"
        let data = Data(text.utf8)
        let style = makeStyle()
        let base = iTermASCIIString(data: data, style: style, ea: nil)
        let sub = base.substring(range: NSRange(location: 1, length: 3)) // "nop"

        let delta = sub.deltaString(range: NSRange(location: 0, length: sub.cellCount))
        XCTAssertEqual(delta.string as String, "nop")

        let builder = DeltaStringBuilder(count: delta.length)
        sub.buildString(range: NSRange(location: 0, length: sub.cellCount), builder: builder)
        let built = builder.build()
        XCTAssertEqual(built.unsafeString as String, "nop")
    }

    func testHasEqual_usedLength_isEmpty() {
        let text = "ZZZ"
        let data = Data(text.utf8)
        let style = makeStyle()
        let base = iTermASCIIString(data: data, style: style, ea: nil)
        let sub = base.substring(range: NSRange(location: 0, length: 2)) // "ZZ"

        // hasEqual
        var buf = [screen_char_t](repeating: style, count: 2)
        buf[0].code = UInt16(text.utf8[text.startIndex])
        buf[1].code = UInt16(text.utf8[text.startIndex])
        let eq = buf.withUnsafeBufferPointer { ptr in
            sub.hasEqual(range: NSRange(location: 0, length: 2), to: ptr.baseAddress!)
        }
        XCTAssertTrue(eq)

        // usedLength == length
        XCTAssertEqual(sub.usedLength(range: NSRange(location: 0, length: 2)), 2)
        XCTAssertFalse(sub.isEmpty(range: NSRange(location: 0, length: 2)))

        // empty range
        XCTAssertTrue(sub.isEmpty(range: NSRange(location: 1, length: 0)))

        // Different length
        XCTAssertFalse(sub.isEqual(to: base))
        XCTAssertFalse(sub.isEqual(lhsRange: NSRange(location: 0, length: 2),
                                   toString: base,
                                   startingAtIndex: 2))
    }

    func testIsEqualToString_andIsEqualRanges_andRTL() {
        let text = "HELLO"
        let data = Data(text.utf8)
        let style = makeStyle()
        let base = iTermASCIIString(data: data, style: style, ea: nil)
        let sub = base.substring(range: NSRange(location: 1, length: 3)) // "ELL"

        // isEqual(other)
        let same = iTermASCIIString(data: Data("ELL".utf8), style: style, ea: nil)
        XCTAssertTrue(sub.isEqual(to: same))

        let diff = iTermASCIIString(data: Data("LLL".utf8), style: style, ea: nil)
        XCTAssertFalse(sub.isEqual(to: diff))

        // isEqual(lhsRange: toString:)
        let rhs = iTermASCIIString(data: Data("ZELLQ".utf8), style: style, ea: nil)
        XCTAssertTrue(sub.isEqual(lhsRange: NSRange(location: 0, length: 3),
                                  toString: rhs,
                                  startingAtIndex: 1))
        XCTAssertFalse(sub.isEqual(lhsRange: NSRange(location: 0, length: 3),
                                   toString: rhs,
                                   startingAtIndex: 0))

        // RTL
        let full = NSRange(location: 0, length: sub.cellCount)
        let rtlSet = IndexSet([0,2])
        let rtlSub = sub.stringBySettingRTL(in: full, rtlIndexes: rtlSet)
        for i in 0..<rtlSub.cellCount {
            let c = rtlSub.character(at: i)
            XCTAssertEqual(c.rtlStatus,
                           rtlSet.contains(i) ? .RTL : .LTR)
        }
    }

    func testClone_mutableClone() {
        let text = "1234"
        let data = Data(text.utf8)
        let style = makeStyle()
        let base = iTermASCIIString(data: data, style: style, ea: nil)
        let sub = base.substring(range: NSRange(location: 1, length: 2)) // "23"

        let cloned = sub.clone()
        XCTAssertTrue(cloned.isEqual(to: sub))

        let m = sub.mutableClone() as! iTermMutableStringProtocolSwift
        XCTAssertTrue(m.isEqual(to: sub))
        m.delete(range: 1..<2)
        XCTAssertNotEqual(m.cellCount, sub.cellCount)
    }

    func testExternalAttributesIndex_isSparse() {
        let text = "WXYZ"
        let data = Data(text.utf8)
        let style = makeStyle()
        // supply base with ea on only some cells
        let ea = iTermExternalAttribute(havingUnderlineColor: true,
                                        underlineColor: VT100TerminalColorValue(red: 1, green: 2, blue: 3, mode: ColorModeNormal),
                                        url: nil, blockIDList: nil, controlCode: nil)
        let eaIndex = iTermExternalAttributeIndex()
        eaIndex.setAttributes(ea, at: 0, count: 1)
        let base = iTermASCIIString(data: data, style: style, ea: nil)
        // manually set attributes on base
        let mutable = base.mutableClone() as! iTermMutableStringProtocolSwift
        mutable.resetRTLStatus()
        mutable.setRTLIndexes(IndexSet())

        // substring should reflect sparsity
        let sub = base.substring(range: NSRange(location: 1, length: 2))
        // default attributes not stored => attributes index may be nil
        XCTAssertNil(sub.externalAttributesIndex())
    }

    func testExternalAttributeAtAndDoubleWidthOnSubstring() {
        // base = wide char at index 1 => DWC at 2
        let text = "A漢B"
        let style = makeStyle()
        let msca = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca.append(text, fg: style, bg: style)
        let base = iTermLegacyStyleString(line: Array(UnsafeBufferPointer(start: msca.line, count: Int(msca.length))),
                                          eaIndex: msca.eaIndex)
        let sub = base.substring(range: NSRange(location: 1, length: 2)) // covers '漢' cells

        // doubleWidthIndexes on sub rebaseTo 0 should yield index 1 (placeholder)
        let dw = sub.doubleWidthIndexes(range: NSRange(location: 0, length: sub.cellCount), rebaseTo: 0)
        XCTAssertEqual(dw, IndexSet([1]))

        // externalAttribute(at:) – none in this example
        XCTAssertNil(sub.externalAttribute(at: 0))
    }

    func testStringBySettingRTL_nilResetsToUnknownOnSubstring() {
        let text = "1234"
        let style = makeStyle()
        let base = iTermASCIIString(data: Data(text.utf8), style: style, ea: nil)
        let sub = base.substring(range: NSRange(location: 1, length: 2))

        let reset = sub.stringBySettingRTL(in: NSRange(location: 0, length: sub.cellCount), rtlIndexes: nil)
        for i in 0..<reset.cellCount {
            XCTAssertEqual(reset.character(at: i).rtlStatus, .unknown)
        }
    }

    func testDoubleWidthIndexes_true() {
        let empty = UInt16(0)
        let dwc = UInt16(DWC_RIGHT)
        let base = iTermNonASCIIString(codes: [empty, empty] + Array(repeating: dwc, count: 10) + [empty, empty],
                                       complex: IndexSet(),
                                       style: screen_char_t(),
                                       ea: nil)
        let string = base.substring(range: NSRange(location: 2, length: 10))
        let actual = string.doubleWidthIndexes(range: NSRange(location: 5, length: 2), rebaseTo: 3)
        let expected = IndexSet([3, 4])
        XCTAssertEqual(actual, expected)
    }

    func testRoundTrip_uniform() throws {
        let base = iTermUniformString(char: makeStyle(), length: 5)

        let original = iTermSubString(base: base, range: NSRange(location: 1, length: 2))

        // Encode
        var encoder = EfficientEncoder()
        original.encodeEfficiently(encoder: &encoder)
        let encodedData = encoder.data

        var decoder = EfficientDecoder(encodedData)
        let decoded = try iTermSubString.create(efficientDecoder: &decoder)

        // Verify round-trip equality
        XCTAssertTrue(original.isEqual(to: decoded))
    }

    func testRoundTrip_legacyStyle() throws {
        let style = makeStyle()
        let sca = MutableScreenCharArray.emptyLine(ofLength: 2)
        sca.append("ABCD", fg: style, bg: style)

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
        sca.setMetadata(metadata)

        let base = iTermLegacyStyleString(sca)
        let original = iTermSubString(base: base, range: NSRange(location: 1, length: 2))

        // Encode
        var encoder = EfficientEncoder()
        original.encodeEfficiently(encoder: &encoder)
        let encodedData = encoder.data

        var decoder = EfficientDecoder(encodedData)
        let decoded = try iTermSubString.create(efficientDecoder: &decoder)

        // Verify round-trip equality
        XCTAssertTrue(original.isEqual(to: decoded))
    }

    func testRoundTrip_ASCII() throws {
        let ea = iTermExternalAttribute(
            havingUnderlineColor: true,
            underlineColor: VT100TerminalColorValue(red: 1, green: 0, blue: 0, mode: ColorModeNormal),
            url: nil,
            blockIDList: nil,
            controlCode: nil
        )
        let base = iTermASCIIString(data: Data([65, 66, 67, 68]),
                                        style: makeStyle(),
                                        ea: ea)
        let original = iTermSubString(base: base, range: NSRange(location: 1, length: 2))

        // Encode
        var encoder = EfficientEncoder()
        original.encodeEfficiently(encoder: &encoder)
        let encodedData = encoder.data

        var decoder = EfficientDecoder(encodedData)
        let decoded = try iTermSubString.create(efficientDecoder: &decoder)

        // Verify round-trip equality
        XCTAssertTrue(original.isEqual(to: decoded))
    }

    func testRoundTrip_nonASCII() throws {
        let ea = iTermExternalAttribute(
            havingUnderlineColor: true,
            underlineColor: VT100TerminalColorValue(red: 1, green: 0, blue: 0, mode: ColorModeNormal),
            url: nil,
            blockIDList: nil,
            controlCode: nil
        )

        let baseStyle = makeStyle()
        let msca = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca.append("a❤️b", fg: baseStyle, bg: baseStyle)
        let count = Int(msca.length)

        var codes = [UInt16]()
        var complexSet = IndexSet()
        for i in 0..<count {
            let c = msca.line[i]
            codes.append(UInt16(truncatingIfNeeded: c.code))
            if c.complexChar != 0 {
                complexSet.insert(i)
            }
        }
        let base = iTermNonASCIIString(codes: codes, complex: complexSet, style: baseStyle, ea: ea)
        let original = iTermSubString(base: base, range: NSRange(location: 1, length: 2))

        // Encode
        var encoder = EfficientEncoder()
        original.encodeEfficiently(encoder: &encoder)
        let encodedData = encoder.data

        var decoder = EfficientDecoder(encodedData)
        let decoded = try iTermSubString.create(efficientDecoder: &decoder)

        // Verify round-trip equality
        XCTAssertTrue(original.isEqual(to: decoded))
    }
}
