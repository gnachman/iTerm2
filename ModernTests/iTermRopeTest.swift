//
//  iTermRopeTest.swift
//  iTerm2
//
//  Created by George Nachman on 4/29/25.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermRopeTests: XCTestCase {
    private func makeASCII(_ s: String) -> iTermASCIIString {
        let data = Data(s.utf8)
        let style = makeStyle()
        return iTermASCIIString(data: data, style: style, ea: nil)
    }

    private func makeUniform(letter: UInt16, length: Int) -> iTermUniformString {
        var c = screen_char_t()
        c.code = letter
        c.foregroundColor = 1; c.fgGreen = 1; c.fgBlue = 1
        c.foregroundColorMode = 1; c.backgroundColorMode = 0
        c.complexChar = 0; c.bold = 0; c.rtlStatus = .unknown
        return iTermUniformString(char: c, length: length)
    }

    func testInitEmpty() {
        let rope = iTermRope([iTermString]())
        XCTAssertEqual(rope.cellCount, 0)
        XCTAssertTrue(rope.isEmpty(range: NSRange(location: 0, length: 0)))
    }

    func testSingleSegmentBehavesLikeUnderlying() {
        let s = makeASCII("abc")
        let rope = iTermRope(s)
        XCTAssertEqual(rope.cellCount, s.cellCount)
        XCTAssertEqual(rope.screenCharArray.stringValue, "abc")
        XCTAssertTrue(rope.isEqual(to: s))
    }

    func testMultipleSegmentsConcatenation() {
        let a = makeASCII("ab")
        let b = makeASCII("cd")
        let rope = iTermRope([a, b])
        XCTAssertEqual(rope.cellCount, 4)
        XCTAssertEqual(rope.screenCharArray.stringValue, "abcd")
        let combined = "abcd"
        for i in 0..<4 {
            let expected = UInt16(combined.utf16[combined.index(combined.startIndex, offsetBy: i)])
            XCTAssertEqual(rope.character(at: i).code, expected)
        }
    }

    func testIndexOfSegmentAndGlobalRange() {
        let a = makeASCII("123")    // indices 0..<3
        let b = makeASCII("XYZW")   // 3..<7
        let rope = iTermRope([a, b])

        XCTAssertEqual(rope.indexOfSegment(for: 0), 0)
        XCTAssertEqual(rope.indexOfSegment(for: 2), 0)
        XCTAssertEqual(rope.indexOfSegment(for: 3), 1)
        XCTAssertEqual(rope.indexOfSegment(for: 6), 1)

        XCTAssertEqual(rope.globalSegmentRange(index: 0), 0..<3)
        XCTAssertEqual(rope.globalSegmentRange(index: 1), 3..<7)
    }

    func testSubstringAcrossSegments() {
        let a = makeASCII("12")
        let b = makeASCII("3456")
        let rope = iTermRope([a, b])
        // take "2345" => range 1..<5
        let sub = rope.substring(range: NSRange(location: 1, length: 4))
        XCTAssertEqual(sub.cellCount, 4)
        XCTAssertEqual(sub.screenCharArray.stringValue, "2345")
        // substring of substring
        let nested = sub.substring(range: NSRange(location: 1, length: 2))
        XCTAssertEqual(nested.screenCharArray.stringValue, "34")
    }

    func testIsEqualToStringAndRanges() {
        let a = makeASCII("foo")
        let b = makeASCII("BAR")
        let rope = iTermRope([a, b])       // "fooBAR"
        let other = makeASCII("fooBAR")
        XCTAssertTrue(rope.isEqual(to: other))
        XCTAssertFalse(rope.isEqual(to: makeASCII("fooBA")))

        // range equality across segments: "oBA" at 2..<5
        let rhs = makeASCII("oBA")
        XCTAssertTrue(rope.isEqual(lhsRange: NSRange(location: 2, length: 3),
                                   toString: rhs,
                                   startingAtIndex: 0))
    }

    func testHydrateRangeAndHydrateInto() {
        let a = makeASCII("XYZ")
        let b = makeASCII("1234")
        let rope = iTermRope([a, b])
        // hydrate range 1..<4 => "YZ1"
        let hyd = rope.hydrate(range: NSRange(location: 1, length: 3))
        XCTAssertEqual(hyd.stringValue, "YZ1")

        // hydrate into msca
        let msca = MutableScreenCharArray.emptyLine(ofLength: 5)
        msca.append(".....", fg: makeStyle(), bg: makeStyle())
        rope.hydrate(into: msca, destinationIndex: 1, sourceRange: NSRange(location: 2, length: 4))
        let seg = msca.subArray(with: NSRange(location: 1, length: 4))
        XCTAssertEqual(seg.stringValue, "Z123")
    }

    func testDeltaStringAndBuildStringAcrossSegments() {
        let a = makeASCII("ab")
        let b = makeASCII("cd")
        let rope = iTermRope([a, b])

        let full = NSRange(location: 0, length: rope.cellCount)
        let delta = rope.deltaString(range: full)
        XCTAssertEqual(delta.string as String, "abcd")

        let builder = DeltaStringBuilder(count: delta.length)
        rope.buildString(range: full, builder: builder)
        let rebuilt = builder.build()
        XCTAssertEqual(rebuilt.unsafeString as String, "abcd")
    }

    func testUsedLengthAcrossSegments() {
        // first uniform zeros, then ASCII
        let zero = iTermUniformString(char: screen_char_t(), length: 3)
        let abc = makeASCII("abc")
        let rope = iTermRope([abc, zero])
        let full = NSRange(location: 0, length: rope.cellCount)
        XCTAssertEqual(rope.usedLength(range: full), 3)
        // sub-range covering only zeros
        XCTAssertEqual(rope.usedLength(range: NSRange(location: 3, length: 2)), 0)
    }

    private func legacy(string: String) -> iTermLegacyStyleString {
        var buffer = Array<screen_char_t>(repeating: screen_char_t(), count: string.utf16.count * 3)
        return buffer.withUnsafeMutableBufferPointer { umbp in
            var len = Int32(umbp.count)
            StringToScreenChars(string, umbp.baseAddress!, screen_char_t(), screen_char_t(), &len, false, nil, nil, iTermUnicodeNormalization.none, 9, false, nil)
            return iTermLegacyStyleString(chars: umbp.baseAddress!, count: Int(len), eaIndex: nil)
        }
    }

    func testUsedLengthSubrange() {
        let segments = [
            legacy(string: "Mac:/Users/gnachman% cat git/iterm2-alt2/tests/arabic"),
            legacy(string: "لرحيم ألم تر كيف فعل ربك بأصحاب الفيل ألم"),
            legacy(string: ""),
            legacy(string: "beginning لرحيم ألم تر كيف فعل ربك بأصحاب الفيل ألم end"),
            legacy(string: ""),
            legacy(string: "ألملرحيم english at the end"),
            legacy(string: ""),
            legacy(string: "english at the beginning ألملرحيم"),
            legacy(string: ""),
            legacy(string: "english before ألملرحيم and after"),
            legacy(string: ""),
            legacy(string: "ألملرحيم english in the middle ألملرحيم"),
            legacy(string: ""),
            legacy(string: "URL:"),
            legacy(string: "ألملرحيم"),
            legacy(string: ""),
            legacy(string: ""),
            legacy(string: ""),
            legacy(string: ""),
            legacy(string: ""),
            legacy(string: ""),
            legacy(string: ""),
            legacy(string: ""),
            legacy(string: ""),
            legacy(string: ""),
        ]
        let rope = iTermRope(segments)
        let actual = rope.usedLength(range: NSRange(location: 53, length: 41))
        XCTAssertEqual(actual, 41)
    }

    func testStringBySettingRTLAcrossSegments() {
        let a = makeASCII("AA")   // indices 0,1
        let b = makeASCII("BB")   // 2,3
        let rope = iTermRope([a, b])
        let full = NSRange(location: 0, length: rope.cellCount)
        let rtlSet = IndexSet([1,2])
        let result = rope.stringBySettingRTL(in: full, rtlIndexes: rtlSet)
        // result should be a rope of two segments
        XCTAssertTrue(result is iTermRope)
        for i in 0..<result.cellCount {
            let c = result.character(at: i)
            let expected: RTLStatus = rtlSet.contains(i) ? .RTL : .LTR
            XCTAssertEqual(c.rtlStatus, expected)
        }
    }

    func testDoubleWidthIndexesAcrossSegments() {
        let dwc: UInt16 = UInt16(DWC_RIGHT)
        let z = makeUniform(letter: dwc, length: 2)  // sentinel,2 cells
        let y = makeASCII("XY")                    // 2 cells normal
        let rope = iTermRope([z, y])                // total 4 cells
        // globalRange 1..<3 covers second cell of z and first of y
        let dw = rope.doubleWidthIndexes(range: NSRange(location: 1, length: 2), rebaseTo: 0)
        // z at index1 is placeholder; y has no dwc
        XCTAssertEqual(dw, IndexSet([0]))
    }

    func testIsEmptyAcrossSegments() {
        let empty = iTermUniformString(char: screen_char_t(), length: 2)
        let abc = makeASCII("abc")
        let rope = iTermRope([empty, abc])
        XCTAssertFalse(rope.isEmpty(range: NSRange(location: 0, length: 5)))
        XCTAssertTrue(rope.isEmpty(range: NSRange(location: 0, length: 2)))
    }

    func testHasEqualAcrossSegments() {
        let a = makeASCII("12")
        let b = makeASCII("34")
        let rope = iTermRope([a, b])

        // build buffer [1,2,3,4]
        var buf = [screen_char_t](repeating: screen_char_t(), count: 4)
        for i in 0..<4 { buf[i] = rope.character(at: i) }
        let eq = buf.withUnsafeBufferPointer { ptr in
            rope.hasEqual(range: NSRange(location: 0, length: 4), to: ptr.baseAddress!)
        }
        XCTAssertTrue(eq)
        buf[2].code = 0
        let neq = buf.withUnsafeBufferPointer { ptr in
            rope.hasEqual(range: NSRange(location: 0, length: 4), to: ptr.baseAddress!)
        }
        XCTAssertFalse(neq)
    }

    func testExternalAttributesIndexAndAttributeAt() {
        let a = makeASCII("AA")
        // give EA only on "BB" segment
        let ea = iTermExternalAttribute(havingUnderlineColor: true,
                                        underlineColor: VT100TerminalColorValue(red:1,green:1,blue:1,mode:ColorModeNormal),
                                        url: nil, blockIDList: nil, controlCode: nil)
        let bWithEA = iTermASCIIString(data: Data("BB".utf8), style: makeStyle(), ea: ea)
        let rope = iTermRope([a, bWithEA])
        guard let idx = rope.externalAttributesIndex() else {
            return XCTFail("Expected externalAttributesIndex")
        }
        // indices 0,1 have no EA, 2,3 have ea
        XCTAssertNil(idx[0])
        XCTAssertNil(rope.externalAttribute(at: 1))
        XCTAssertEqual(idx[2], ea)
        XCTAssertEqual(rope.externalAttribute(at: 3), ea)
    }

    func testCloneIndependence() {
        let a = makeASCII("A")
        let b = makeASCII("B")
        let rope = iTermRope([a, b])
        let copy = rope.clone()
        XCTAssertTrue(copy.isEqual(to: rope))
        // mutate original via mutableClone
        let m = rope.mutableClone() as! iTermMutableStringProtocolSwift
        m.delete(range: 0..<1)
        XCTAssertNotEqual(m.cellCount, rope.cellCount)
        XCTAssertEqual(copy.cellCount, rope.cellCount)
    }

    func testEmptySegmentHandling() {
        let empty = makeASCII("")
        let nonEmpty = makeASCII("X")
        let rope = iTermRope([empty, nonEmpty, empty])
        // should skip zero-length segments
        XCTAssertEqual(rope.cellCount, 1)
        XCTAssertEqual(rope.screenCharArray.stringValue, "X")
        XCTAssertEqual(rope.character(at: 0).code,
                       UInt16("X".utf16.first!))
        // hydrate and substring ignore empties
        let sub = rope.substring(range: NSRange(location: 0, length: 1))
        XCTAssertEqual(sub.screenCharArray.stringValue, "X")
        let hyd = rope.hydrate(range: NSRange(location: 0, length: 1))
        XCTAssertEqual(hyd.stringValue, "X")
    }

    func testCopyConstructorAndDeepClone() {
        let a = makeASCII("ab")
        let b = makeASCII("cd")
        let rope1 = iTermRope([a, b])
        // copy init
        let rope2 = iTermRope(rope1)
        XCTAssertTrue(rope2.isEqual(to: rope1))
        // mutate rope1 via mutableClone
        let m1 = rope1.mutableClone() as! iTermMutableStringProtocolSwift
        m1.delete(range: 0..<1)
        // rope2 unaffected
        XCTAssertEqual(rope2.cellCount, 4)
        // NSCopying
        let rope3 = rope1.copy() as! iTermRope
        XCTAssertTrue(rope3.isEqual(to: rope1))
        // mutableCopy
        let m3 = rope1.mutableCopy() as! iTermMutableStringProtocolSwift
        XCTAssertTrue(m3.isEqual(to: rope1))
    }

    func testDeltaStringCaching() {
        let rope = iTermRope([makeASCII("hello"), makeASCII("world")])
        let full = NSRange(location: 0, length: rope.cellCount)
        let d1 = rope.deltaString(range: full)
        let d2 = rope.deltaString(range: full)
        XCTAssertEqual(d1.string as String, d2.string as String)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: d1.deltas, count: Int(d1.length))),
                       Array(UnsafeBufferPointer(start: d2.deltas, count: Int(d2.length))))
    }

    func testUsedLengthWithTrailingZeroSegments() {
        // zeros then ascii
        let zeroUniform = makeUniform(letter: 0, length: 5)
        let ascii = makeASCII("abc")
        let rope = iTermRope([ascii, zeroUniform])
        let full = NSRange(location: 0, length: rope.cellCount)
        XCTAssertEqual(rope.usedLength(range: full), 3)
        // range in zero-only part
        XCTAssertEqual(rope.usedLength(range: NSRange(location: 3, length: 2)), 0)
    }

    func testIsEqualCharactersDiffer() {
        let rope = iTermRope([makeASCII("abc")])
        let other = makeASCII("abd")
        XCTAssertFalse(rope.isEqual(to: other))
    }

    func testIsEqualRhsShorterThanRangeLength() {
        let rope = iTermRope([makeASCII("abcd")])
        let rhs = makeASCII("ab")
        XCTAssertFalse(
            rope.isEqual(lhsRange: NSRange(location: 0, length: 3),
                         toString: rhs,
                         startingAtIndex: 0)
        )
    }

    func testUsedLengthMultipleSegmentsTraversed() {
        let seg0 = makeASCII("AB")           // length 2, all used
        let zeroSeg = makeUniform(letter: 0, length: 3) // length 3, all zeros
        var c = screen_char_t()
        c.code = UInt16("C".utf16.first!)     // 'C'
        c.foregroundColorMode = 1
        let seg2 = iTermUniformString(char: c, length: 1) // length 1, used
        let rope = iTermRope([seg0, zeroSeg, seg2])
        let full = NSRange(location: 0, length: rope.cellCount)
        // should traverse through seg2 (used=1), seg1 (count=3), seg0 (count=2) => sum = 6
        XCTAssertEqual(rope.usedLength(range: full), Int32(6))
    }

    func testUsedLengthTrailingSegmentExcluded() {
        let seg0 = makeASCII("AB")   // used=2
        let zeroSeg = makeUniform(letter: 0, length: 3) // zeros
        let rope = iTermRope([seg0, zeroSeg])
        // range covers both segments (length 5)
        let full = NSRange(location: 0, length: rope.cellCount)
        XCTAssertEqual(rope.usedLength(range: full), Int32(2))
        // range only covers zeros (last 3 cells)
        let onlyZeros = NSRange(location: 2, length: 3)
        XCTAssertEqual(rope.usedLength(range: onlyZeros), Int32(0))
    }
    
    func testBoundaryAlignedRanges() {
        let rope = iTermRope([makeASCII("ab"), makeASCII("cd")]) // "abcd"
        // substring exactly at boundary 2..<2
        let sub = rope.substring(range: NSRange(location: 2, length: 2))
        XCTAssertEqual(sub.screenCharArray.stringValue, "cd")
        let hyd = rope.hydrate(range: NSRange(location: 2, length: 2))
        XCTAssertEqual(hyd.stringValue, "cd")
        let rhs = makeASCII("cd")
        XCTAssertTrue(rope.isEqual(lhsRange: NSRange(location: 2, length: 2),
                                   toString: rhs,
                                   startingAtIndex: 0))
    }

    func testFullRtlAndDoubleWidthNilIndexes() {
        // DWC then ascii
        let dwc: UInt16 = UInt16(DWC_RIGHT)
        let dz = makeUniform(letter: dwc, length: 2)
        let ef = makeASCII("ef")
        let rope = iTermRope([dz, ef]) // 4 cells
        let full = NSRange(location: 0, length: rope.cellCount)
        let result = rope.stringBySettingRTL(in: full, rtlIndexes: nil)
        for i in 0..<result.cellCount {
            XCTAssertEqual(result.character(at: i).rtlStatus, .unknown)
        }
    }

    func testIsEmptyOnPartialRanges() {
        let zeros = makeUniform(letter: 0, length: 2)
        let gh = makeASCII("gh")
        let rope = iTermRope([zeros, gh]) // 4 cells
        XCTAssertTrue(rope.isEmpty(range: NSRange(location: 0, length: 2)))
        XCTAssertFalse(rope.isEmpty(range: NSRange(location: 1, length: 3)))
    }

    func testHasEqualWithOffsetSegments() {
        let rope = iTermRope([makeASCII("12"), makeASCII("34")]) // "1234"
        // buffer matching only "34"
        var buf = [screen_char_t](repeating: screen_char_t(), count: 2)
        buf[0] = rope.character(at: 2)
        buf[1] = rope.character(at: 3)
        let eq = buf.withUnsafeBufferPointer { ptr in
            rope.hasEqual(range: NSRange(location: 2, length: 2), to: ptr.baseAddress!)
        }
        XCTAssertTrue(eq)
        // buffer mismatched across boundary
        buf[0].code = 0
        let neq = buf.withUnsafeBufferPointer { ptr in
            rope.hasEqual(range: NSRange(location: 2, length: 2), to: ptr.baseAddress!)
        }
        XCTAssertFalse(neq)
    }
}
