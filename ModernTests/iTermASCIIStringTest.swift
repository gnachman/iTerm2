//
//  iTermASCIIStringTest.swift
//  iTerm2
//
//  Created by George Nachman on 4/29/25.
//

import XCTest
@testable import iTerm2SharedARC

// Helper to build a non-zero style
func makeStyle() -> screen_char_t {
    var style = screen_char_t()
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

final class iTermASCIIStringTest: XCTestCase {

    func testCellCountAndCharacter_atIndex() throws {
        let s = "Hello"
        let data = Data(s.utf8)
        let style = makeStyle()
        let string = iTermASCIIString(data: data, style: style, ea: nil)

        // cellCount
        XCTAssertEqual(string.cellCount, s.count)

        // character(at:)
        for i in 0..<s.count {
            let c = string.character(at: i)
            let expectedCode = Int(s.utf8[s.index(s.startIndex, offsetBy: i)])
            XCTAssertEqual(Int(c.code), expectedCode)

            // style fields must propagate
            XCTAssertEqual(c.bold, style.bold)
            XCTAssertEqual(c.italic, style.italic)
            XCTAssertEqual(c.inverse, style.inverse)
            XCTAssertEqual(c.rtlStatus, .unknown)
        }
    }

    func testHydrateRange_andScreenCharArray() {
        let s = "abcd"
        let data = Data(s.utf8)
        let style = makeStyle()
        let string = iTermASCIIString(data: data, style: style, ea: nil)

        let range = NSRange(location: 1, length: 2)
        let sca = string.hydrate(range: range)

        // length and content
        XCTAssertEqual(Int(sca.length), range.length)
        XCTAssertEqual(sca.stringValue, "bc")

        // style on each hydrated cell
        for i in 0..<range.length {
            let cell = sca.line[i]
            let expectedCode = Int(s.utf8[s.index(s.startIndex, offsetBy: range.location + i)])
            XCTAssertEqual(Int(cell.code), expectedCode)
            XCTAssertEqual(cell.underline, style.underline)
        }

        // screenCharArray property should be full-line match
        let full = string.screenCharArray
        XCTAssertEqual(Int(full.length), s.count)
        XCTAssertEqual(full.stringValue, s)
    }

    func testHasEqual_trueAndFalse() {
        let s = "XYZ"
        let data = Data(s.utf8)
        let style = makeStyle()
        let string = iTermASCIIString(data: data, style: style, ea: nil)

        // build a matching buffer
        var buf = [screen_char_t](repeating: style, count: s.count)
        for i in 0..<s.count {
            buf[i].code = s.utf16[s.index(s.startIndex, offsetBy: i)]
        }
        let match = buf.withUnsafeBufferPointer { ptr in
            string.hasEqual(range: NSRange(location: 0, length: s.count),
                            to: ptr.baseAddress!)
        }
        XCTAssertTrue(match)

        // mutate one entry
        buf[1].code = 0
        let mismatch = buf.withUnsafeBufferPointer { ptr in
            string.hasEqual(range: NSRange(location: 0, length: s.count),
                            to: ptr.baseAddress!)
        }
        XCTAssertFalse(mismatch)
    }

    func testExternalAttributesIndex_andExternalAttributeAt() {
        let s = "Test"
        let data = Data(s.utf8)
        let style = makeStyle()
        let attr = iTermExternalAttribute(havingUnderlineColor: true, underlineColor: VT100TerminalColorValue(red: 1, green: 1, blue: 1, mode: ColorModeNormal), url: nil, blockIDList: nil, controlCode: nil)
        let string = iTermASCIIString(data: data, style: style, ea: attr)

        // externalAttributesIndex must exist
        guard let eaIndex = string.externalAttributesIndex() else {
            return XCTFail("Expected non-nil externalAttributesIndex")
        }

        // should have one entry per cell
        XCTAssertEqual(eaIndex.attributes.count, s.count)
        for i in 0..<s.count {
            let key = NSNumber(value: i)
            XCTAssertNotNil(eaIndex.attributes[key])
            XCTAssertEqual(eaIndex.attributes[key], attr)
            XCTAssertEqual(string.externalAttribute(at: i), attr)
        }

        // if ea was nil, index should be nil
        let noEA = iTermASCIIString(data: data, style: style, ea: nil)
        XCTAssertNil(noEA.externalAttributesIndex())
    }

    func testIsEmpty_andUsedLength() {
        let s = "ABC"
        let data = Data(s.utf8)
        let style = makeStyle()
        let string = iTermASCIIString(data: data, style: style, ea: nil)

        // no nulls ⇒ usedLength == range.length
        let fullRange = NSRange(location: 0, length: string.cellCount)
        XCTAssertEqual(string.usedLength(range: fullRange),
                       Int32(fullRange.length))

        // non-empty ⇒ isEmpty == false
        XCTAssertFalse(string.isEmpty(range: fullRange))

        // zero-length range isEmpty == true
        let zeroRange = NSRange(location: 1, length: 0)
        XCTAssertTrue(string.isEmpty(range: zeroRange))
    }

    func testDoubleWidthIndexes_isAlwaysEmpty() {
        let s = "wide?"
        let data = Data(s.utf8)
        let style = makeStyle()
        let string = iTermASCIIString(data: data, style: style, ea: nil)

        let full = NSRange(location: 0, length: string.cellCount)
        let dw = string.doubleWidthIndexes(range: full, rebaseTo: 42)
        XCTAssertTrue(dw.isEmpty)
    }

    func testStringBySettingRTL_inAndNil() {
        let s = "RTL"
        let data = Data(s.utf8)
        let style = makeStyle()
        let string = iTermASCIIString(data: data, style: style, ea: nil)
        let full = NSRange(location: 0, length: string.cellCount)

        // set some to RTL, rest to LTR
        let rtlSet = IndexSet([0, 2])
        let rtlString = string.stringBySettingRTL(in: full, rtlIndexes: rtlSet)
        for i in 0..<rtlString.cellCount {
            let c = rtlString.character(at: i)
            if rtlSet.contains(i) {
                XCTAssertEqual(c.rtlStatus, .RTL)
            } else {
                XCTAssertEqual(c.rtlStatus, .LTR)
            }
        }

        // nil ⇒ all unknown
        let unknown = rtlString.stringBySettingRTL(in: full, rtlIndexes: nil)
        for i in 0..<unknown.cellCount {
            XCTAssertEqual(unknown.character(at: i).rtlStatus, .unknown)
        }
    }

    func testDeltaString() {
        let s = "Hi!"
        let data = Data(s.utf8)
        let style = makeStyle()
        let string = iTermASCIIString(data: data, style: style, ea: nil)

        // The full-range deltaString should round-trip via DeltaStringBuilder
        let fullRange = NSRange(location: 0, length: string.cellCount)
        let delta = string.deltaString(range: fullRange)
        XCTAssertEqual(delta.length, Int32(fullRange.length))
        XCTAssertEqual(delta.string as String, s)
        XCTAssertEqual(delta.safeDeltas, [0, 0, 0])
    }

    func testBuildString() {
        let s = "Hi!"
        let data = Data(s.utf8)
        let style = makeStyle()
        let string = iTermASCIIString(data: data, style: style, ea: nil)

        let builder = DeltaStringBuilder(count: 2)
        string.buildString(range: NSRange(location: 1, length: 2), builder: builder)
        let deltaString = builder.build()
        XCTAssertEqual(deltaString.unsafeString as String, "i!")
        XCTAssertEqual(deltaString.safeDeltas, [0, 0])
    }

    func testClone_andMutableClone_areIndependent() {
        let s = "Clone"
        let data = Data(s.utf8)
        let style = makeStyle()
        let string = iTermASCIIString(data: data, style: style, ea: nil)

        let c1 = string.clone()
        XCTAssertTrue(c1.isEqual(to: string))
        XCTAssertTrue(string.isEqual(to: c1))

        let m = string.mutableClone() as! iTermMutableStringProtocolSwift
        XCTAssertFalse(m === string)
        XCTAssertTrue(m.isEqual(to: string))

        // mutating the mutable clone must not affect the original
        m.insert(iTermASCIIString(data: Data([0]), style: screen_char_t(), ea: nil), at: 0)
        XCTAssertNotEqual(m.cellCount, string.cellCount)
    }

    func testSubstring_andIsEqualRanges() {
        let s = "SubstringTest"
        let data = Data(s.utf8)
        let style = makeStyle()
        let string = iTermASCIIString(data: data, style: style, ea: nil)

        let subRange = NSRange(location: 3, length: 6)
        let sub = string.substring(range: subRange)
        XCTAssertEqual(sub.cellCount, subRange.length)
        XCTAssertEqual(sub.screenCharArray.stringValue, (s as NSString).substring(with: subRange))

        // isEqual(lhsRange:…)
        // lhs = "SubstringTest", rhs = "string"
        //        0123456789abc
        let lhsRange = NSRange(location: 3, length: 4)
        let rhs = iTermASCIIString(data: Data("string".utf8), style: style, ea: nil)
        XCTAssertTrue(string.isEqual(lhsRange: lhsRange, toString: rhs, startingAtIndex: 0))
        XCTAssertFalse(string.isEqual(lhsRange: lhsRange, toString: rhs, startingAtIndex: 1))
    }

    func testIsEqualToString() {
        let style = makeStyle()
        let ea = iTermExternalAttribute(havingUnderlineColor: true, underlineColor: VT100TerminalColorValue(red: 2, green: 3, blue: 4, mode: ColorModeNormal), url: nil, blockIDList: nil, controlCode: nil)

        let a = iTermASCIIString(data: Data("Equal".utf8), style: style, ea: ea)
        let b = iTermASCIIString(data: Data("Equal".utf8), style: style, ea: ea)
        let c = iTermASCIIString(data: Data("Diff".utf8), style: style, ea: ea)

        XCTAssertTrue(a.isEqual(to: b))
        XCTAssertTrue(b.isEqual(to: a))
        XCTAssertFalse(a.isEqual(to: c))
    }

    func testStringBySettingRTL_nilResetsToUnknown() {
        let s = "ABC"
        let data = Data(s.utf8)
        let style = makeStyle()
        let string = iTermASCIIString(data: data, style: style, ea: nil)
        let full = NSRange(location: 0, length: string.cellCount)

        let reset = string.stringBySettingRTL(in: full, rtlIndexes: nil)
        for i in 0..<reset.cellCount {
            XCTAssertEqual(reset.character(at: i).rtlStatus, .unknown)
        }
    }

    func testIsEqualOutOfBoundsRangeReturnsFalse() {
        let s = "HELLO"
        let data = Data(s.utf8)
        let style = makeStyle()
        let string = iTermASCIIString(data: data, style: style, ea: nil)

        let rhs = iTermASCIIString(data: Data("HELLO".utf8), style: style, ea: nil)
        // lhsRange starts beyond string.cellCount
        XCTAssertFalse(string.isEqual(lhsRange: NSRange(location: 10, length: 1),
                                      toString: rhs,
                                      startingAtIndex: 0))
    }

    func testRoundTrip() throws {
        let ea = iTermExternalAttribute(
            havingUnderlineColor: true,
            underlineColor: VT100TerminalColorValue(red: 1, green: 0, blue: 0, mode: ColorModeNormal),
            url: nil,
            blockIDList: nil,
            controlCode: nil
        )
        let original = iTermASCIIString(data: Data([65, 66, 67]),
                                        style: makeStyle(),
                                        ea: ea)

        // Encode
        var encoder = EfficientEncoder()
        original.encodeEfficiently(encoder: &encoder)
        let encodedData = encoder.data

        var decoder = EfficientDecoder(encodedData)
        let decoded = try iTermASCIIString.create(efficientDecoder: &decoder)

        // Verify round-trip equality
        XCTAssertTrue(original.isEqual(to: decoded))
    }
}
