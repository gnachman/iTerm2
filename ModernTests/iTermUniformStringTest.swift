//
//  iTermUniformStringTest.swift
//  iTerm2
//
//  Created by George Nachman on 4/29/25.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermUniformStringTest: XCTestCase {
    private func makeStyleChar(letter: UInt16 = 88) -> screen_char_t {
        // Default style, letter 'X' (88)
        var c = screen_char_t()
        c.code = letter
        c.foregroundColor = 2
        c.fgGreen = 2
        c.fgBlue = 2
        c.backgroundColor = 0
        c.bgGreen = 0
        c.bgBlue = 0
        c.foregroundColorMode = 1
        c.backgroundColorMode = 0
        c.complexChar = 0
        c.bold = 1
        c.italic = 0
        c.underline = 0
        c.rtlStatus = .unknown
        return c
    }

    func testCellCount_andCharacterAt() {
        let char = makeStyleChar(letter: 65)  // 'A'
        let length = 5
        let uni = iTermUniformString(char: char, length: length)

        XCTAssertEqual(uni.cellCount, length)
        for i in 0..<length {
            let c = uni.character(at: i)
            XCTAssertEqual(c.code, char.code)
            XCTAssertEqual(c.bold, char.bold)
            XCTAssertEqual(c.italic, char.italic)
            XCTAssertEqual(c.rtlStatus, .unknown)
        }
    }

    func testScreenCharArray_andHydrateRange() {
        let char = makeStyleChar(letter: 90) // 'Z'
        let uni = iTermUniformString(char: char, length: 3)
        let sca = uni.screenCharArray
        XCTAssertEqual(Int(sca.length), 3)
        XCTAssertEqual(sca.stringValue, "ZZZ")

        // hydrate(range:)
        let sub = uni.hydrate(range: NSRange(location: 1, length: 2))
        XCTAssertEqual(Int(sub.length), 2)
        XCTAssertEqual(sub.stringValue, "ZZ")
    }

    func testHydrateInto_andHasEqual() {
        let char = makeStyleChar(letter: 70) // 'F'
        let uni = iTermUniformString(char: char, length: 4)
        let msca = MutableScreenCharArray.emptyLine(ofLength: 6)
        // fill with dots
        msca.append("......", fg: makeStyleChar(), bg: makeStyleChar())

        // hydrate into index 2, range [1..3]
        uni.hydrate(into: msca, destinationIndex: 2, sourceRange: NSRange(location: 1, length: 2))
        let segment = msca.subArray(with: NSRange(location: 2, length: 2))
        XCTAssertEqual(segment.stringValue, "FF")

        // hasEqual
        var buf = [screen_char_t](repeating: char, count: 4)
        for i in 0..<4 { buf[i].code = char.code }
        let eq = buf.withUnsafeBufferPointer { ptr in
            uni.hasEqual(range: NSRange(location: 0, length: 4), to: ptr.baseAddress!)
        }
        XCTAssertTrue(eq)
    }

    func testHasEqualReturnsFalseWhenCharacterDiffers() {
        let char = makeStyleChar(letter: 65) // 'A'
        let uni = iTermUniformString(char: char, length: 3)

        // Build a matching buffer, then mutate one cell
        var buf = [screen_char_t](repeating: char, count: 3)
        buf[1].code = 66  // change middle from 'A' to 'B'

        let matches = buf.withUnsafeBufferPointer { ptr in
            uni.hasEqual(range: NSRange(location: 0, length: 3),
                         to: ptr.baseAddress!)
        }
        XCTAssertFalse(matches,
                       "hasEqual should be false when any character differs")
    }

    func testSubstring_andNested() {
        let char = makeStyleChar(letter: 77) // 'M'
        let uni = iTermUniformString(char: char, length: 6)

        let sub = uni.substring(range: NSRange(location: 2, length: 3))
        XCTAssertEqual(sub.cellCount, 3)
        XCTAssertEqual(sub.screenCharArray.stringValue, "MMM")

        let nested = sub.substring(range: NSRange(location: 1, length: 1))
        XCTAssertEqual(nested.cellCount, 1)
        XCTAssertEqual(nested.screenCharArray.stringValue, "M")
    }

    func testDeltaString_andBuildString() {
        let char = makeStyleChar(letter: 65) // 'A'
        let uni = iTermUniformString(char: char, length: 4)
        let full = NSRange(location: 0, length: uni.cellCount)
        let delta = uni.deltaString(range: full)
        XCTAssertEqual(delta.string as String, "AAAA")
        XCTAssertEqual(delta.length, Int32(4))
        XCTAssertEqual([Int](0..<4).map { _ in 0 }, delta.safeDeltas)

        let builder = DeltaStringBuilder(count: delta.length)
        uni.buildString(range: full, builder: builder)
        let built = builder.build()
        XCTAssertEqual(built.unsafeString as String, "AAAA")
    }

    func testUsedLength_isEmpty_doubleWidth() {
        let char = makeStyleChar()
        let uni = iTermUniformString(char: char, length: 3)
        let full = NSRange(location: 0, length: 3)
        XCTAssertEqual(uni.usedLength(range: full), 3)
        XCTAssertFalse(uni.isEmpty(range: full))
        XCTAssertTrue(uni.isEmpty(range: NSRange(location: 1, length: 0)))

        // doubleWidthIndexes always empty
        let dw = uni.doubleWidthIndexes(range: full, rebaseTo: 0)
        XCTAssertTrue(dw.isEmpty)
    }

    func testUsedLength_zeros() {
        let s = iTermUniformString(char: screen_char_t(), length: 5)
        XCTAssertEqual(s.usedLength(range: s.fullRange), 0)
    }

    func testRTL_andEquality() {
        let char = makeStyleChar()
        let uni = iTermUniformString(char: char, length: 5)
        let full = NSRange(location: 0, length: 5)
        let rtlSet = IndexSet([0,4])
        let rtlString = uni.stringBySettingRTL(in: full, rtlIndexes: rtlSet)
        for i in 0..<rtlString.cellCount {
            let c = rtlString.character(at: i)
            let expected: RTLStatus = rtlSet.contains(i) ? .RTL : .LTR
            XCTAssertEqual(c.rtlStatus, expected)
        }
        let unknown = uni.stringBySettingRTL(in: full, rtlIndexes: nil)
        for i in 0..<unknown.cellCount {
            XCTAssertEqual(unknown.character(at: i).rtlStatus, .unknown)
        }

        // isEqual(to:)
        let other = iTermUniformString(char: char, length: 5)
        XCTAssertTrue(uni.isEqual(to: other))
        let diff = iTermUniformString(char: char, length: 4)
        XCTAssertFalse(uni.isEqual(to: diff))
    }

    func testStringBySettingRTL_fullRangeAllRTL_returnsUniformRTL() {
        let char = makeStyleChar(letter: 77)
        let uni = iTermUniformString(char: char, length: 3)
        let full = NSRange(location: 0, length: 3)
        let rtlSet = IndexSet(0..<3)

        let result = uni.stringBySettingRTL(in: full, rtlIndexes: rtlSet)
        XCTAssertTrue(type(of: result) == iTermUniformString.self)
        for i in 0..<result.cellCount {
            XCTAssertEqual(result.character(at: i).rtlStatus, .RTL)
        }
    }

    func testStringBySettingRTL_emptyIndexSet_returnsUniformLTR() {
        let char = makeStyleChar(letter: 65)
        let uni = iTermUniformString(char: char, length: 4)
        let full = NSRange(location: 0, length: 4)
        let emptySet = IndexSet()

        let result = uni.stringBySettingRTL(in: full, rtlIndexes: emptySet)
        XCTAssertTrue(type(of: result) == iTermUniformString.self)
        for i in 0..<result.cellCount {
            XCTAssertEqual(result.character(at: i).rtlStatus, .LTR)
        }
    }

    func testStringBySettingRTL_mixedIndexSet_returnsNonASCIIString() {
        let char = makeStyleChar(letter: 90)
        let uni = iTermUniformString(char: char, length: 5)
        let full = NSRange(location: 0, length: 5)
        let mixed = IndexSet([0,2,4])

        let result = uni.stringBySettingRTL(in: full, rtlIndexes: mixed)

        // check that the resulting non-ASCII string has correct rtl statuses
        for i in 0..<result.cellCount {
            let c = result.character(at: i)
            let expected: RTLStatus = mixed.contains(i) ? .RTL : .LTR
            XCTAssertEqual(c.rtlStatus, expected)
        }
    }

    func testStringBySettingRTL_nilAndPartialRange_returnsUnknown() {
        let char = makeStyleChar(letter: 88)
        let uni = iTermUniformString(char: char, length: 4)
        let full = NSRange(location: 0, length: 4)
        let rtlSet = IndexSet([0])

        // Set the first character to rtl, converting to a non-uniform string.
        let mixed = uni.stringBySettingRTL(in: full, rtlIndexes: rtlSet)
        XCTAssertEqual(mixed.character(at: 0).rtlStatus, .RTL)

        // now call with nil and partial range
        let partial = NSRange(location: 1, length: 2)
        let result = mixed.stringBySettingRTL(in: partial, rtlIndexes: nil)
        for i in 0..<result.cellCount {
            XCTAssertEqual(result.character(at: i).rtlStatus, .unknown)
        }
    }

    func testStringBySettingRTL_nilOnFullRangeResetsToUnknown_whenAlreadyRTL() {
        let char = makeStyleChar(letter: 77)
        let uni = iTermUniformString(char: char, length: 3)
        let full = NSRange(location: 0, length: 3)
        // first, set all to RTL
        let rtlSet = IndexSet(0..<3)
        let rtlUni = uni.stringBySettingRTL(in: full, rtlIndexes: rtlSet) as! iTermUniformString
        XCTAssertTrue((0..<rtlUni.cellCount).allSatisfy { rtlUni.character(at: $0).rtlStatus == .RTL })

        // now nil on full range should reset to unknown
        let reset = rtlUni.stringBySettingRTL(in: full, rtlIndexes: nil)
        XCTAssertTrue(type(of: reset) == iTermUniformString.self)
        for i in 0..<reset.cellCount {
            XCTAssertEqual(reset.character(at: i).rtlStatus, .unknown)
        }
    }

    func testStringBySettingRTL_mixedWithComplexChar_setsComplexRange() {
        // create a char with complexChar=1
        var char = makeStyleChar(letter: 77)
        char.complexChar = 1
        let length = 4
        let uni = iTermUniformString(char: char, length: length)
        let full = NSRange(location: 0, length: length)
        // pick a mixed membership (not empty, not full)
        let mixed = IndexSet([1, 3])

        let result = uni.stringBySettingRTL(in: full, rtlIndexes: mixed)

        for i in 0..<length {
            let c = result.character(at: i)
            let expected: RTLStatus = mixed.contains(i) ? .RTL : .LTR
            XCTAssertEqual(c.rtlStatus, expected)
        }
    }

    func testDoubleWidthIndexes_true() {
        var c = screen_char_t()
        c.code = UInt16(DWC_RIGHT)
        let string = iTermUniformString(char: c, length: 10)
        let actual = string.doubleWidthIndexes(range: NSRange(location: 5, length: 2), rebaseTo: 3)
        let expected = IndexSet([3, 4])
        XCTAssertEqual(actual, expected)
    }

    func testIsEqualToNonUniformString_equalAndNotEqual() {
        let char = makeStyleChar(letter: 88) // 'X'
        let uniform = iTermUniformString(char: char, length: 4)

        // Case 1: identical content
        let asciiDataMatch = Data(repeating: UInt8(ascii: "X"), count: 4)
        let asciiMatch = iTermASCIIString(data: asciiDataMatch, style: makeStyleChar(), ea: nil)
        XCTAssertTrue(uniform.isEqual(to: asciiMatch),
                      "UniformString of 'XXXX' should equal ASCIIString 'XXXX'")

        // Case 2: one character differs
        let asciiDataDiff = Data("XXXY".utf8)
        let asciiDiff = iTermASCIIString(data: asciiDataDiff, style: makeStyleChar(), ea: nil)
        XCTAssertFalse(uniform.isEqual(to: asciiDiff),
                       "UniformString 'XXXX' should not equal ASCIIString 'XXXY'")
    }

    func testClone_andMutableClone() {
        let char = makeStyleChar()
        let uni = iTermUniformString(char: char, length: 3)
        let cloned = uni.clone()
        XCTAssertTrue(cloned.isEqual(to: uni))

        let m = uni.mutableClone() as! iTermMutableStringProtocolSwift
        XCTAssertTrue(m.isEqual(to: uni))
        m.delete(range: 0..<1)
        XCTAssertNotEqual(m.cellCount, uni.cellCount)
    }

    func testExternalAttributesIndex_andExternalAttributeAt() {
        let char = makeStyleChar()
        let uni = iTermUniformString(char: char, length: 2)
        XCTAssertNil(uni.externalAttributesIndex())
        XCTAssertNil(uni.externalAttribute(at: 0))
    }

    func testIsEqualRanges() {
        let char = makeStyleChar(letter: 80) // 'P'
        let uni = iTermUniformString(char: char, length: 5)
        let rhs = iTermUniformString(char: char, length: 3)

        XCTAssertTrue(uni.isEqual(lhsRange: NSRange(location: 0, length: 3),
                                  toString: rhs,
                                  startingAtIndex: 0))
        XCTAssertTrue(uni.isEqual(lhsRange: NSRange(location: 1, length: 3),
                                  toString: rhs,
                                  startingAtIndex: 0))
    }

    func testIsEqualRangeOutOfBoundsReturnsFalse() {
        let char = makeStyleChar()
        let uni = iTermUniformString(char: char, length: 3)
        let rhs = iTermUniformString(char: char, length: 3)
        XCTAssertFalse(uni.isEqual(lhsRange: NSRange(location: 5, length: 1),
                                   toString: rhs,
                                   startingAtIndex: 0))
    }
}
