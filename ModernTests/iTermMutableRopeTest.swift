//
//  iTermLegacyMutableStringTest.swift
//  iTerm2
//
//  Created by George Nachman on 4/29/25.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermMutableRopeTests: XCTestCase {
    func testCellCountAndCharacter_atIndex() {
        let style = makeStyle()
        // initialize via width + character
        let firstCharCode = UInt16("H".utf16.first!)
        var char = style
        char.code = firstCharCode
        let count = 5
        let mutable = iTermMutableRope(iTermLegacyMutableString(width: count, character: char))
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
        let m = iTermMutableRope(iTermLegacyMutableString(width: 3))
        // initially all zero
        let full = NSRange(location: 0, length: m.cellCount)
        XCTAssertTrue(m.isEmpty(range: full))
        XCTAssertEqual(m.usedLength(range: full), 0)
    }

    func testStringValueAndScreenCharArray() {
        let text = "A漢B"
        let style = makeStyle()
        let msca = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca.append(text, fg: style, bg: style)
        let mutable = iTermMutableRope(iTermLegacyMutableString(msca))
        XCTAssertEqual(mutable.screenCharArray.stringValue, text)
        XCTAssertEqual(mutable.cellCount, Int(msca.length))
    }

    func testDoubleWidthIndexesAndHydrate() {
        let text = "A漢B"
        let style = makeStyle()
        let msca0 = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca0.append(text, fg: style, bg: style)
        let mutable = iTermMutableRope(iTermLegacyMutableString(msca0))
        let full = NSRange(location: 0, length: mutable.cellCount)
        let dw = mutable.doubleWidthIndexes(range: full, rebaseTo: 0)
        XCTAssertEqual(dw, IndexSet([2]))
        // hydrate
        let hyd = mutable.hydrate(range: NSRange(location: 1, length: 2))
        XCTAssertEqual(hyd.stringValue, "漢")
    }

    func testSubstringAndIsEqualRanges() {
        let style = makeStyle()
        let m = iTermMutableRope(iTermLegacyMutableString(width: 2))
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
        let m = iTermMutableRope(iTermLegacyMutableString(width: 0))
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
        let m = iTermMutableRope(iTermLegacyMutableString(width: 2))
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
        let m = iTermMutableRope(iTermLegacyMutableString(width: 4))
        m.replace(range: 0..<4, with: iTermASCIIString(data: Data("1234".utf8), style: style, ea: nil))
        m.objcDelete(range: NSRange(location: 1, length: 2)) // deletes "23"
        XCTAssertEqual(m.screenCharArray.stringValue, "14")
        // swift delete
        m.delete(range: 0..<1)
        XCTAssertEqual(m.screenCharArray.stringValue, "4")
    }

    func testDeleteFromStartAndEnd() {
        let style = makeStyle()
        let m = iTermMutableRope(iTermLegacyMutableString(width: 4))
        m.replace(range: 0..<4, with: iTermASCIIString(data: Data("WXYZ".utf8), style: style, ea: nil))
        m.deleteFromStart(1)
        XCTAssertEqual(m.screenCharArray.stringValue, "XYZ")
        m.deleteFromEnd(1)
        XCTAssertEqual(m.screenCharArray.stringValue, "XY")
    }

    func testAppendInsertReplace() {
        let style = makeStyle()
        let m = iTermMutableRope(iTermLegacyMutableString(width: 0))
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
        let m = iTermMutableRope(iTermLegacyMutableString(width: 3))
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

    func testInitWidthAndCharacter() {
        // width initializer
        let mstr = iTermMutableRope(iTermLegacyMutableString(width: 3))
        XCTAssertEqual(mstr.cellCount, 3)
        // width+character convenience init
        var style = makeStyle()
        style.code = UInt16("Z".utf16.first!)
        let mstr2 = iTermMutableRope(iTermLegacyMutableString(width: 5, character: style))
        XCTAssertEqual(mstr2.cellCount, 5)
        for i in 0..<5 {
            XCTAssertEqual(mstr2.character(at: i).code, style.code)
        }
    }

    func testDeleteRangeAndDeleteMethods() {
        // Helper to create a fresh mutable string from ASCII
        func makeMstr(_ s: String) -> iTermMutableRope {
            let style = makeStyle()
            let sca = MutableScreenCharArray.emptyLine(ofLength: 0)
            sca.append(s, fg: style, bg: style)
            return iTermMutableRope(iTermLegacyMutableString(sca))
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
        let base = iTermMutableRope(iTermLegacyMutableString(width: 3))
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

    func testResetRTLAndSetRTLIndexes() {
        let style = makeStyle()
        var styleA = style
        styleA.code = UInt16("A".utf16.first!)
        let sca = MutableScreenCharArray.emptyLine(ofLength: 3)
        sca.append("AAA", fg: style, bg: style)
        let mstr = iTermMutableRope(iTermLegacyMutableString(sca))
        mstr.setRTLIndexes(IndexSet([0,2]))
        XCTAssertEqual(mstr.character(at: 0).rtlStatus, .RTL)
        XCTAssertEqual(mstr.character(at: 1).rtlStatus, .LTR)
        XCTAssertEqual(mstr.character(at: 2).rtlStatus, .RTL)
        mstr.resetRTLStatus()
        for i in 0..<3 {
            XCTAssertEqual(mstr.character(at: i).rtlStatus, .unknown)
        }
    }

    func testIsEqualToString_DifferentLengths() {
        let m1 = iTermMutableRope(iTermLegacyMutableString(width: 2))
        let m2 = iTermMutableRope(iTermLegacyMutableString(width: 3))
        XCTAssertFalse(m1.isEqual(to: m2))
    }

    func testIsEqualRangeOutOfBoundsOrRhsTooShort() {
        let m = iTermMutableRope(iTermLegacyMutableString(width: 4))
        let rhs = iTermMutableRope(iTermLegacyMutableString(width: 2))
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
        let m = iTermMutableRope(iTermLegacyMutableString(width: 3))
        XCTAssertNil(m.externalAttribute(at: 1))
    }

    func testStringBySettingRTL_NilAndNonNil() {
        let charStyle = makeStyle()
        var ch = charStyle
        ch.code = UInt16("X".utf16.first!)
        let m = iTermMutableRope(iTermLegacyMutableString(width: 3, character: ch))
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
        let bufSca = MutableScreenCharArray.emptyLine(ofLength: 0)
        bufSca.append("1234", fg: style, bg: style)
        let m = iTermMutableRope(iTermLegacyMutableString(bufSca))
        let dest = MutableScreenCharArray.emptyLine(ofLength: 6)
        dest.append("......", fg: style, bg: style)
        // hydrate "23" into positions 2..<4
        m.hydrate(into: dest,
                  destinationIndex: 2,
                  sourceRange: NSRange(location: 1, length: 2))
        let sub = dest.subArray(with: NSRange(location: 2, length: 2))
        XCTAssertEqual(sub.stringValue, "23")
    }

    func testHasEqualTrueAndFalse() {
        // create string "XYZ"
        let style = makeStyle()
        let sca = MutableScreenCharArray.emptyLine(ofLength: 0)
        sca.append("XYZ", fg: style, bg: style)
        let m = iTermMutableRope(iTermLegacyMutableString(sca))
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

    func testUsedLengthOnEmptyString() {
        let m = iTermMutableRope(iTermLegacyMutableString(width: 0))
        XCTAssertEqual(m.cellCount, 0)
        let full = NSRange(location: 0, length: 0)
        XCTAssertEqual(m.usedLength(range: full), 0)
    }

    private func makeStyle() -> screen_char_t {
        var s = screen_char_t()
        s.foregroundColor = 1; s.fgGreen = 2; s.fgBlue = 3
        s.backgroundColor = 4; s.bgGreen = 5; s.bgBlue = 6
        s.foregroundColorMode = 1; s.backgroundColorMode = 2
        s.complexChar = 0; s.bold = 1; s.faint = 0; s.italic = 1
        s.blink = 0; s.underline = 1; s.image = 0; s.strikethrough = 1
        s.underlineStyle = .single
        s.invisible = 0; s.inverse = 1
        s.guarded = 0; s.virtualPlaceholder = 0; s.rtlStatus = .unknown
        return s
    }

    func testHeterogeneousAppendDeltaAndHydrate() {
        let style = makeStyle()

        // ASCII segment "AB"
        let ascii = iTermASCIIString(
            data: Data("AB".utf8),
            style: style,
            ea: nil
        )

        // Legacy segment "C"
        var c = style
        c.code = UInt16(Character("C").utf16.first!)
        let legacy = iTermLegacyStyleString(
            line: [c],
            eaIndex: nil
        )

        // Non-ASCII segment "DE"
        let D: UInt16 = UInt16(Character("D").utf16.first!)
        let E: UInt16 = UInt16(Character("E").utf16.first!)
        let codes = [D, E]
        let nonAscii = iTermNonASCIIString(
            codes: codes,
            complex: [],
            style: style,
            ea: nil)

        let rope = iTermMutableRope()
        rope.append(string: ascii)
        rope.append(string: legacy)
        rope.append(string: nonAscii)

        let full = rope.fullRange
        XCTAssertEqual(
            rope.cellCount,
            ascii.cellCount + legacy.cellCount + nonAscii.cellCount
        )

        // deltaString should be "AB" + "C" + "DE" = "ABCDE"
        let delta = rope.deltaString(range: full).string as String
        XCTAssertEqual(delta, "ABCDE")

        // hydrate into a MutableScreenCharArray
        let msca = MutableScreenCharArray.emptyLine(ofLength: Int32(rope.cellCount))
        rope.hydrate(
            into: msca,
            destinationIndex: 0,
            sourceRange: full
        )
        XCTAssertEqual(msca.stringValue, "ABCDE")
    }

    func testCrossSegmentDeleteFromStartAndEnd() {
        let style = makeStyle()
        let ascii1 = iTermASCIIString(data: Data("AB".utf8), style: style, ea: nil)
        var c = style; c.code = UInt16(Character("C").utf16.first!)
        let legacy = iTermLegacyStyleString(line: [c], eaIndex: nil)
        let ascii2 = iTermASCIIString(data: Data("DE".utf8), style: style, ea: nil)

        // deleteFromStart across segments
        let rope1 = iTermMutableRope([ascii1, legacy, ascii2])
        rope1.deleteFromStart(3)  // removes "ABC"
        XCTAssertEqual(rope1.deltaString(range: rope1.fullRange).string as String, "DE")

        // deleteFromEnd across segments
        let rope2 = iTermMutableRope([ascii1, legacy, ascii2])
        rope2.deleteFromEnd(3)  // removes "CDE"
        XCTAssertEqual(rope2.deltaString(range: rope2.fullRange).string as String, "AB")
    }

    func testDeleteRangeObjcAndSwift2() {
        let style = makeStyle()
        let ascii = iTermASCIIString(data: Data("12345".utf8), style: style, ea: nil)
        let rope = iTermMutableRope()
        rope.append(string: ascii)

        // objcDelete(range:)
        rope.objcDelete(range: NSRange(location: 1, length: 3))  // removes "234"
        XCTAssertEqual(rope.deltaString(range: rope.fullRange).string as String, "15")

        // swift delete(range:)
        rope.delete(range: 0..<1)  // removes "1"
        XCTAssertEqual(rope.deltaString(range: rope.fullRange).string as String, "5")
    }

    func testReplaceAndInsertAcrossSegments() {
        let style = makeStyle()
        let ascii1 = iTermASCIIString(data: Data("AB".utf8), style: style, ea: nil)
        let ascii2 = iTermASCIIString(data: Data("YZ".utf8), style: style, ea: nil)
        let rope = iTermMutableRope([ascii1])

        // append second segment
        rope.append(string: ascii2)  // rope = "ABYZ"

        // insert "C" at index 2
        var c = style; c.code = UInt16(Character("C").utf16.first!)
        let cStr = iTermASCIIString(data: Data("C".utf8), style: style, ea: nil)
        rope.insert(cStr, at: 2)     // "ABCYZ"
        XCTAssertEqual(rope.deltaString(range: rope.fullRange).string as String, "ABCYZ")

        // replace "BC" with "XY"
        let xy = iTermASCIIString(data: Data("XY".utf8), style: style, ea: nil)
        rope.replace(range: 1..<3, with: xy)  // "AXYYZ"
        let delta = rope.deltaString(range: rope.fullRange)
        XCTAssertEqual(delta.string as String, "AXYYZ")
    }

    func testCopyAndMutableCloneIndependence() {
        let style = makeStyle()
        let ascii = iTermASCIIString(data: Data("ABC".utf8), style: style, ea: nil)
        let original = iTermMutableRope([ascii])
        let clone = original.mutableClone() as! iTermMutableRope

        // mutate original
        original.deleteFromStart(1)
        XCTAssertEqual(original.deltaString(range: original.fullRange).string as String, "BC")
        XCTAssertEqual(clone.deltaString(range: clone.fullRange).string as String, "ABC")

        // mutate clone
        let clone2 = original.mutableClone() as! iTermMutableRope
        clone2.deleteFromEnd(1)
        XCTAssertEqual(clone2.deltaString(range: clone2.fullRange).string as String, "B")
        XCTAssertEqual(original.deltaString(range: original.fullRange).string as String, "BC")
    }

    func testResetRTLStatusAndSetRTLIndexesOnMutableRope() {
        let style = makeStyle()
        let ascii = iTermASCIIString(data: Data("XXX".utf8), style: style, ea: nil)
        let rope = iTermMutableRope([ascii])

        rope.setRTLIndexes(IndexSet([0,2]))
        for i in 0..<rope.cellCount {
            let status = rope.character(at: i).rtlStatus
            XCTAssertEqual(status,
                           [ .RTL, .LTR, .RTL ][i])
        }

        rope.resetRTLStatus()
        for i in 0..<rope.cellCount {
            XCTAssertEqual(rope.character(at: i).rtlStatus, .unknown)
        }
    }

    func testEmptyRopeEdgeCases() {
        let rope = iTermMutableRope()

        XCTAssertEqual(rope.cellCount, 0)
        let full = NSRange(location: 0, length: 0)
        XCTAssertTrue(rope.isEmpty(range: full))
        XCTAssertEqual(rope.usedLength(range: full), 0)

        // isEqual(lhsRange:toString:) on empty rope returns false unless both empty
        let ascii = iTermASCIIString(data: Data("".utf8), style: makeStyle(), ea: nil)
        XCTAssertTrue(rope.isEqual(lhsRange: full, toString: ascii, startingAtIndex: 0))
        XCTAssertFalse(rope.isEqual(lhsRange: NSRange(location: 1, length: 1), toString: ascii, startingAtIndex:0))
    }

    func testHydrateSmallRangesAcrossSegments() {
        let style = makeStyle()
        let ascii1 = iTermASCIIString(data: Data("123".utf8), style: style, ea: nil)
        let ascii2 = iTermASCIIString(data: Data("456".utf8), style: style, ea: nil)
        let rope = iTermMutableRope([ascii1, ascii2])  // "123456"

        // hydrate "345" = cells 2..<5
        let msca = MutableScreenCharArray.emptyLine(ofLength: 3)
        rope.hydrate(
            into: msca,
            destinationIndex: 0,
            sourceRange: NSRange(location: 2, length: 3)
        )
        XCTAssertEqual(msca.stringValue, "345")
    }

    func testDeleteAll() {
        let r = iTermMutableRope()
        r.append(string: iTermASCIIString(data: Data("Hello".utf8), style: screen_char_t(), ea: nil))
        r.deleteFromEnd(5)
        XCTAssertEqual(r.cellCount, 0)
        XCTAssertEqual(r, iTermMutableRope())
    }
}

class iTermMutableRopeReplaceTests: XCTestCase {
    private func ascii(_ s: String) -> iTermASCIIString {
        let style = makeStyle()
        return iTermASCIIString(data: Data(s.utf8), style: style, ea: nil)
    }

    private func rope(from s: String) -> iTermMutableRope {
        return iTermMutableRope([ascii(s)])
    }

    func testReplaceZeroLengthInsert() {
        let r = rope(from: "ABC")
        let x = ascii("X")
        r.replace(range: 1..<1, with: x)
        XCTAssertEqual(r.screenCharArray.stringValue, "AXBC")
    }

    func testReplaceEmptyReplacementDeletes() {
        let r = rope(from: "ABCDE")
        r.replace(range: 2..<4, with: ascii(""))
        XCTAssertEqual(r.screenCharArray.stringValue, "ABE")
    }

    func testReplaceEqualLengthSingleSegment() {
        let r = rope(from: "HelloWorld")
        let replacement = ascii("123456789") // length 9 replacing 1..<10
        r.replace(range: 1..<10, with: replacement)
        XCTAssertEqual(r.screenCharArray.stringValue, "H123456789")
    }

    func testReplaceShorterReplacementSingleSegment() {
        let r = rope(from: "ABCDEFG")
        let replacement = ascii("Z")
        r.replace(range: 2..<5, with: replacement)
        XCTAssertEqual(r.screenCharArray.stringValue, "ABZFG")
    }

    func testReplaceLongerReplacementSingleSegment() {
        let r = rope(from: "XYZ")
        let replacement = ascii("12345")
        r.replace(range: 1..<2, with: replacement)
        XCTAssertEqual(r.screenCharArray.stringValue, "X12345Z")
    }

    func testReplaceEntireRangeClears() {
        let r = rope(from: "DATA")
        r.replace(range: 0..<4, with: iTermASCIIString(data: Data(), style: makeStyle(), ea: nil))
        XCTAssertEqual(r.screenCharArray.stringValue, "")
        XCTAssertEqual(r.cellCount, 0)
    }

    func testReplaceAcrossSegmentsGeneralSplice() {
        let a1 = ascii("AB")
        let a2 = ascii("CD")
        let rope = iTermMutableRope([a1, a2])  // "ABCD"
        let replacement = ascii("XYZ")
        rope.replace(range: 1..<3, with: replacement) // replaces "BC"
        XCTAssertEqual(rope.screenCharArray.stringValue, "AXYZD")
    }

    func testObjcReplaceBehavesSame() {
        let r = rope(from: "HELLO")
        let repl = ascii("YY")
        r.objcReplace(range: NSRange(location: 1, length: 3), with: repl) // replace "ELL"
        XCTAssertEqual(r.screenCharArray.stringValue, "HYYO")
    }

    func testReplaceAtStartAndEnd() {
        let r = rope(from: "123456")
        // replace start
        r.replace(range: 0..<2, with: ascii("AB"))
        XCTAssertEqual(r.screenCharArray.stringValue, "AB3456")
        // replace end
        r.replace(range: 4..<6, with: ascii("CD"))
        XCTAssertEqual(r.screenCharArray.stringValue, "AB34CD")
    }
}
