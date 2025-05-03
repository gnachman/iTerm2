//
//  iTermNonASCIIStringTest.swift
//  iTerm2
//
//  Created by George Nachman on 4/29/25.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermNonASCIIStringTest: XCTestCase {
    private func makeBaseStyle() -> screen_char_t {
        var s = screen_char_t()
        s.foregroundColor = 10
        s.fgGreen = 20
        s.fgBlue = 30
        s.backgroundColor = 40
        s.bgGreen = 50
        s.bgBlue = 60
        s.foregroundColorMode = 1
        s.backgroundColorMode = 1
        s.bold = 0
        s.italic = 0
        s.underline = 0
        s.rtlStatus = .unknown
        return s
    }

    func testCellCount_characterAndScreenCharArray() {
        // "A漢B" represented as ["A", "漢", placeholder, "B"]
        let A: UInt16 = 65
        let han: UInt16 = 0x6F22  // '漢'
        let ph: UInt16 = UInt16(DWC_RIGHT)
        let B: UInt16 = 66
        let codes: [UInt16] = [A, han, ph, B]
        let complex = IndexSet()

        let nonAscii = iTermNonASCIIString(codes: codes,
                                           complex: complex,
                                           style: makeBaseStyle(),
                                           ea: nil)
        print(nonAscii.deltaString(range: nonAscii.fullRange))
        XCTAssertEqual(nonAscii.cellCount, codes.count)
        // stringValue should compress placeholder to actual char
        XCTAssertEqual(nonAscii.screenCharArray.stringValue, "A漢B")
        // character codes: at index 1 = han, at 2 = placeholder
        XCTAssertEqual(nonAscii.character(at: 1).code, han)
        XCTAssertEqual(nonAscii.character(at: 2).code, ph)
    }

    func testDoubleWidthIndexes_andHydrate() {
        let A: UInt16 = 65
        let han: UInt16 = 0x6F22
        let ph: UInt16 = UInt16(DWC_RIGHT)
        let B: UInt16 = 66
        let codes: [UInt16] = [A, han, ph, B]
        let s = iTermNonASCIIString(codes: codes, complex: IndexSet(), style: makeBaseStyle(), ea: nil)
        let full = NSRange(location: 0, length: s.cellCount)
        // placeholder is at index 2 => wide char marker
        let dw = s.doubleWidthIndexes(range: full, rebaseTo: 0)
        XCTAssertEqual(dw, IndexSet([2]))
        // hydrate wide pair [1..2]
        let hyd = s.hydrate(range: NSRange(location: 1, length: 2))
        XCTAssertEqual(Int(hyd.length), 2)
        XCTAssertEqual(hyd.stringValue, "漢")
    }

    func testHydrateIntoMutable_andHasEqual() {
        let codes: [UInt16] = [65, 66, 67]
        let s = iTermNonASCIIString(codes: codes, complex: IndexSet(), style: makeBaseStyle(), ea: nil)

        let msca = MutableScreenCharArray.emptyLine(ofLength: 5)
        // fill some existing data
        msca.append("XXXXX", fg: makeBaseStyle(), bg: makeBaseStyle())
        // hydrate into position 1
        s.hydrate(into: msca, destinationIndex: 1, sourceRange: NSRange(location: 0, length: 3))
        let sub = msca.subArray(with: NSRange(location: 1, length: 3))
        XCTAssertEqual(sub.stringValue, "ABC")

        // hasEqual: compare range in s
        var buf = [screen_char_t](repeating: makeBaseStyle(), count: 3)
        for i in 0..<3 { buf[i].code = codes[i] }
        let eq = buf.withUnsafeBufferPointer { ptr in
            s.hasEqual(range: NSRange(location: 0, length: 3), to: ptr.baseAddress!)
        }
        XCTAssertTrue(eq)
    }

    func testHydrateComplexCharacter() {
        let baseStyle = makeBaseStyle()
        let msca = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca.append("❤️b", fg: baseStyle, bg: baseStyle)
        let fullStr = msca.stringValue as String
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
        let s = iTermNonASCIIString(codes: codes, complex: complexSet, style: makeBaseStyle(), ea: nil)
        let actual = s.hydrate(range: s.fullRange)
        XCTAssertEqual(actual, msca)
    }

    func testSubstring_andIsEqualRanges() {
        let codes: [UInt16] = [65, 66, 67, 68]
        let s = iTermNonASCIIString(codes: codes, complex: IndexSet(), style: makeBaseStyle(), ea: nil)

        // substring [1..2]
        let sub = s.substring(range: NSRange(location: 1, length: 2))
        XCTAssertEqual(sub.screenCharArray.stringValue, "BC")

        // isEqual lhsRange [0..2] to rhs "ABC"
        let rhs = iTermASCIIString(data: Data("ABC".utf8), style: makeBaseStyle(), ea: nil)
        XCTAssertTrue(s.isEqual(lhsRange: NSRange(location: 0, length: 3), toString: rhs, startingAtIndex: 0))
        XCTAssertFalse(s.isEqual(lhsRange: NSRange(location: 0, length: 3), toString: rhs, startingAtIndex: 1))
    }

    func testClone_mutableClone_andMutation() {
        let codes: [UInt16] = [65, 66]
        let s = iTermNonASCIIString(codes: codes, complex: IndexSet(), style: makeBaseStyle(), ea: nil)

        let cloned = s.clone()
        XCTAssertTrue(cloned.isEqual(to: s))

        let m = s.mutableClone() as! iTermMutableStringProtocolSwift
        XCTAssertTrue(m.isEqual(to: s))
        // delete first cell
        m.delete(range: 0..<1)
        XCTAssertNotEqual(m.cellCount, s.cellCount)
    }

    func testDeltaString_andBuildString_andRTL() {
        // simple ascii run
        let codes: [UInt16] = [65, 66, 67]
        let s = iTermNonASCIIString(codes: codes, complex: IndexSet(), style: makeBaseStyle(), ea: nil)

        let full = NSRange(location: 0, length: 3)
        let delta = s.deltaString(range: full)
        XCTAssertEqual(delta.string as String, "ABC")
        let builder = DeltaStringBuilder(count: delta.length)
        s.buildString(range: full, builder: builder)
        let reb = builder.build()
        XCTAssertEqual(reb.unsafeString as String, "ABC")

        // RTL setting
        let rtlSet = IndexSet([1])
        let rtlStr = s.stringBySettingRTL(in: full, rtlIndexes: rtlSet)
        for i in 0..<rtlStr.cellCount {
            let c = rtlStr.character(at: i)
            XCTAssertEqual(c.rtlStatus,
                           rtlSet.contains(i) ? .RTL : .LTR)
        }
        // nil => all unknown
        let unk = s.stringBySettingRTL(in: full, rtlIndexes: nil)
        for i in 0..<unk.cellCount {
            XCTAssertEqual(unk.character(at: i).rtlStatus, .unknown)
        }
    }

    func testExternalAttributesIndex_distribution() {
        let codes: [UInt16] = [65, 66, 67, 68]
        let underlineColor = VT100TerminalColorValue(red: 1, green: 1, blue: 1, mode: ColorModeNormal)
        let ea = iTermExternalAttribute(underlineColor: underlineColor, url: nil, blockIDList: nil, controlCode: nil)
        let s = iTermNonASCIIString(codes: codes, complex: IndexSet(), style: makeBaseStyle(), ea: ea)
        guard let idx = s.externalAttributesIndex() else {
            return XCTFail("Expected attributes index")
        }
        for i in 0..<4 {
            let attr = idx.attributes[NSNumber(value:i)]
            XCTAssertEqual(attr, ea)
        }
    }

    func testHydrateIntoCopiesExtendedAttributes() {
        let A: UInt16 = 65
        let codes: [UInt16] = [A, A]
        // give an extended URL attr at index 1
        let url = iTermURL(url: URL(string: "https://x")!, identifier: nil)
        let ea = iTermExternalAttribute(havingUnderlineColor: false,
                                        underlineColor: VT100TerminalColorValue(),
                                        url: url,
                                        blockIDList: nil,
                                        controlCode: nil)
        let s = iTermNonASCIIString(codes: codes, complex: IndexSet(), style: makeBaseStyle(), ea: ea)

        let md = MutableScreenCharArray.emptyLine(ofLength: 4)
        s.hydrate(into: md, destinationIndex: 1, sourceRange: NSRange(location: 0, length: 2))
        let eaIndex = md.eaIndexCreatingIfNeeded()
        XCTAssertEqual(eaIndex.attribute(at: 1), ea)
        XCTAssertEqual(eaIndex.attribute(at: 2), ea)
    }

    func testHydrateIntoCopiesExtendedAttributes_destHasIndexButSourceDoesNot() {
        let A: UInt16 = 65
        let codes: [UInt16] = [A, A]
        let s = iTermNonASCIIString(codes: codes, complex: IndexSet(), style: makeBaseStyle(), ea: nil)

        let msca = MutableScreenCharArray.emptyLine(ofLength: 4)
        let eaIndex = iTermExternalAttributeIndex()
        let ea2 = iTermExternalAttribute(havingUnderlineColor: true,
                                         underlineColor: VT100TerminalColorValue(red:2,green:2,blue:2,mode:ColorModeNormal),
                                         url: nil, blockIDList: nil, controlCode: nil)
        eaIndex.setAttributes(ea2, at: 0, count: 2)
        msca.setExternalAttributesIndex(eaIndex)
        s.hydrate(into: msca, destinationIndex: 1, sourceRange: NSRange(location: 0, length: 2))
        let ea = msca.eaIndexCreatingIfNeeded()
        XCTAssertEqual(ea.attribute(at: 1), nil)
        XCTAssertEqual(ea.attribute(at: 2), nil)
    }

    func testUsedLengthCountsNonZero() {
        // codes include a zero
        let codes: [UInt16] = [65, 67, 0]
        let s = iTermNonASCIIString(codes: codes, complex: IndexSet(), style: makeBaseStyle(), ea: nil)

        let full = NSRange(location: 0, length: 3)
        XCTAssertEqual(s.usedLength(range: full), 2)
    }

    func testIsEqualOutOfBoundsRangeReturnsFalse() {
        let codes: [UInt16] = [65,66]
        let s = iTermNonASCIIString(codes: codes, complex: IndexSet(), style: makeBaseStyle(), ea: nil)
        let rhs = s.clone()
        XCTAssertFalse(s.isEqual(lhsRange: NSRange(location: 10, length: 1),
                                 toString: rhs,
                                 startingAtIndex: 0))
    }

    func testDoubleWidthIndexes_true() {
        let string = iTermNonASCIIString(codes: Array(repeating: UInt16(DWC_RIGHT), count: 10),
                                         complex: IndexSet(),
                                         style: makeBaseStyle(),
                                         ea: nil)
        let actual = string.doubleWidthIndexes(range: NSRange(location: 5, length: 2), rebaseTo: 3)
        let expected = IndexSet([3, 4])
        XCTAssertEqual(actual, expected)
    }
}
