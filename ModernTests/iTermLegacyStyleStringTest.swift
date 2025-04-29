//
//  iTermLegacyStyleStringTest.swift
//  iTerm2
//
//  Created by George Nachman on 4/29/25.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermLegacyStyleStringTest: XCTestCase {
    func screenChars(from string: String, style: screen_char_t) -> [screen_char_t] {
        return string.map {
            var c = style
            c.code = $0.utf16.first!
            return c
        }
    }

    func testCellCountAndCharacter_atIndex() throws {
        let s = "Hello"
        let style = makeStyle()
        let string = iTermLegacyStyleString(line: screenChars(from: s, style: style), eaIndex: nil)

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

    func testIsEmpty_andUsedLength() {
        let s = "ABC"
        let chars = s.map { c in
            var sct = screen_char_t()
            sct.code =  c.utf16.first!
            return sct
        }
        let string = iTermLegacyStyleString(line: chars,
                                            eaIndex: nil)

        // no nulls ⇒ usedLength == range.length
        let fullRange = NSRange(location: 0, length: string.cellCount)
        XCTAssertEqual(string.usedLength(range: fullRange),
                       Int32(fullRange.length))

        // non-empty ⇒ isEmpty == false
        XCTAssertFalse(string.isEmpty(range: fullRange))

        let zeroRange = NSRange(location: 1, length: 0)
        XCTAssertTrue(string.isEmpty(range: zeroRange))

        XCTAssertTrue(iTermLegacyStyleString(line: [screen_char_t()], eaIndex: nil).isEmpty(range: NSRange(location: 0, length: 1)))
    }

    func testCellCountAndStringValue() {
        let text = "A漢B"
        let style = makeStyle()
        // Build via MutableScreenCharArray
        let msca = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca.append(text, fg: style, bg: style)

        // Create legacy-style string
        let lineArray = Array(UnsafeBufferPointer(start: msca.line,
                                                  count: Int(msca.length)))
        let legacy = iTermLegacyStyleString(line: lineArray,
                                            eaIndex: msca.eaIndex)

        // Cell count should match underlying array length
        XCTAssertEqual(legacy.cellCount, Int(msca.length))
        // screenCharArray.stringValue should equal original text
        XCTAssertEqual(legacy.screenCharArray.stringValue, text)
    }

    func testDoubleWidthIndexesAndHydrate() {
        let text = "A漢B"
        let style = makeStyle()
        let msca = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca.append(text, fg: style, bg: style)
        let lineArray = Array(UnsafeBufferPointer(start: msca.line,
                                                  count: Int(msca.length)))
        let legacy = iTermLegacyStyleString(line: lineArray,
                                            eaIndex: msca.eaIndex)

        let fullRange = NSRange(location: 0,
                                length: legacy.cellCount)
        // Double-width char at index 1
        let dw = legacy.doubleWidthIndexes(range: fullRange,
                                           rebaseTo: 0)
        XCTAssertEqual(dw, IndexSet([2]))
        XCTAssertTrue(ScreenCharIsDWC_RIGHT(legacy.line[2]))

        // Hydrate the two cells representing the wide char
        let hyd = legacy.hydrate(range: NSRange(location: 1, length: 2))
        // length and stringValue should compress to single unicode char
        XCTAssertEqual(Int(hyd.length), 2)
        XCTAssertEqual(hyd.stringValue, "漢")
    }

    func testSubstringAndIsEqualRanges() {
        let text = "A漢B"
        let style = makeStyle()
        let msca = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca.append(text, fg: style, bg: style)
        let lineArray = Array(UnsafeBufferPointer(start: msca.line,
                                                  count: Int(msca.length)))
        let legacy = iTermLegacyStyleString(line: lineArray,
                                            eaIndex: msca.eaIndex)

        // Substring of the wide character cell-pair
        let sub = legacy.substring(range: NSRange(location: 1, length: 2))
        XCTAssertEqual(sub.screenCharArray.stringValue, "漢")

        // Compare range of original to a simple string
        let rhs = iTermASCIIString(data: Data("B".utf8),
                                   style: style,
                                   ea: nil)
        XCTAssertTrue(legacy.isEqual(lhsRange: NSRange(location: 3, length: 1),
                                     toString: rhs,
                                     startingAtIndex: 0))
        XCTAssertFalse(legacy.isEqual(lhsRange: NSRange(location: 2, length: 1),
                                      toString: rhs,
                                      startingAtIndex: 0))
    }

    func testDeltaStringAndBuildString() {
        let text = "A漢B"
        let style = makeStyle()
        let msca = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca.append(text, fg: style, bg: style)
        let lineArray = Array(UnsafeBufferPointer(start: msca.line,
                                                  count: Int(msca.length)))
        let legacy = iTermLegacyStyleString(line: lineArray,
                                            eaIndex: msca.eaIndex)

        let fullRange = NSRange(location: 0,
                                length: legacy.cellCount)
        let delta = legacy.deltaString(range: fullRange)
        XCTAssertEqual(delta.string as String, text)

        let builder = DeltaStringBuilder(count: delta.length)
        legacy.buildString(range: fullRange, builder: builder)
        let rebuilt = builder.build()
        XCTAssertEqual(rebuilt.unsafeString as String, text)
    }

    func testCloneAndMutableCloneIndependence() {
        let text = "X中Y"
        let style = makeStyle()
        let msca = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca.append(text, fg: style, bg: style)
        let lineArray = Array(UnsafeBufferPointer(start: msca.line,
                                                  count: Int(msca.length)))
        let legacy = iTermLegacyStyleString(line: lineArray,
                                            eaIndex: msca.eaIndex)

        let cloned = legacy.clone()
        XCTAssertTrue(cloned.isEqual(to: legacy))

        let m = legacy.mutableClone() as! iTermMutableStringProtocolSwift
        XCTAssertTrue(m.isEqual(to: legacy))

        // Delete first cell should diverge
        m.delete(range: 0..<1)
        XCTAssertNotEqual(m.cellCount, legacy.cellCount)
    }

    func testIsEqualToString() {
        let style = makeStyle()
        let msca1 = MutableScreenCharArray.emptyLine(ofLength: 0)
        let msca2 = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca1.append("漢", fg: style, bg: style)
        msca2.append("漢", fg: style, bg: style)
        let arr1 = Array(UnsafeBufferPointer(start: msca1.line, count: Int(msca1.length)))
        let arr2 = Array(UnsafeBufferPointer(start: msca2.line, count: Int(msca2.length)))
        let s1 = iTermLegacyStyleString(line: arr1, eaIndex: msca1.eaIndex)
        let s2 = iTermLegacyStyleString(line: arr2, eaIndex: msca2.eaIndex)
        XCTAssertTrue(s1.isEqual(to: s2))
        XCTAssertFalse(s1.isEqual(to: s2.substring(range: NSRange(location: 0, length: 1))))
    }

    func testHydrateIntoCopiesExternalAttributes() {
        // build a source with an external attribute at index 1
        let style = makeStyle()
        let msrc = MutableScreenCharArray.emptyLine(ofLength: 0)
        msrc.append("XY", style: style, continuation: style) // X,Y
        let ea = iTermExternalAttribute(havingUnderlineColor: true,
                                        underlineColor: VT100TerminalColorValue(red:1,green:0,blue:0,mode:ColorModeNormal),
                                        url: nil,
                                        blockIDList: nil,
                                        controlCode: nil)
        let eaIndex = iTermExternalAttributeIndex()
        eaIndex.setAttributes(ea, at: 1, count: 1)
        msrc.setExternalAttributesIndex(eaIndex)
        let srcLine = Array(UnsafeBufferPointer(start: msrc.line, count: Int(msrc.length)))
        let legacy = iTermLegacyStyleString(line: srcLine, eaIndex: msrc.eaIndex)

        // hydrate into a fresh msca
        let mdest = MutableScreenCharArray.emptyLine(ofLength: 4)
        legacy.hydrate(into: mdest, destinationIndex: 1, sourceRange: NSRange(location: 0, length: 2))
        let destEA = mdest.eaIndexCreatingIfNeeded()
        // only dest index 1+1=2 should carry the attribute from src index 1
        XCTAssertNil(destEA.attribute(at: 1))
        XCTAssertEqual(destEA.attribute(at: 2), ea)
    }

    func testExternalAttributesIndex_andExternalAttributeAt() {
        let style = makeStyle()
        let msrc = MutableScreenCharArray.emptyLine(ofLength: 0)
        msrc.append("AB", style: style, continuation: style)
        let ea = iTermExternalAttribute(havingUnderlineColor: true,
                                        underlineColor: VT100TerminalColorValue(red:2,green:2,blue:2,mode:ColorModeNormal),
                                        url: nil, blockIDList: nil, controlCode: nil)
        let eaIndex = iTermExternalAttributeIndex()
        eaIndex.setAttributes(ea, at: 0, count: 1)
        msrc.setExternalAttributesIndex(eaIndex)
        let lineArray = Array(UnsafeBufferPointer(start: msrc.line, count: Int(msrc.length)))
        let legacy = iTermLegacyStyleString(line: lineArray, eaIndex: msrc.eaIndex)

        let idx = legacy.externalAttributesIndex()!
        XCTAssertEqual(idx.attribute(at: 0), ea)
        XCTAssertNil(legacy.externalAttribute(at: 1))
    }

    func testIsEqualDifferentLengths() {
        let style = makeStyle()
        let a = iTermASCIIString(data: Data("ABC".utf8), style: style, ea: nil)
        let b = iTermASCIIString(data: Data("AB".utf8), style: style, ea: nil)
        XCTAssertFalse(a.isEqual(to: b))
    }

    func testStringBySettingRTL_nilAndPartial() {
        let style = makeStyle()
        let msrc = MutableScreenCharArray.emptyLine(ofLength: 0)
        msrc.append("HIJ", style: style, continuation: style)
        let src = iTermLegacyStyleString(line: Array(UnsafeBufferPointer(start: msrc.line, count: Int(msrc.length))),
                                         eaIndex: msrc.eaIndex)
        let full = NSRange(location: 0, length: src.cellCount)

        let allUnknown = src.stringBySettingRTL(in: full, rtlIndexes: nil)
        for i in 0..<allUnknown.cellCount {
            XCTAssertEqual(allUnknown.character(at: i).rtlStatus, .unknown)
        }

        let rtlSet = IndexSet([0,2])
        let partial = src.stringBySettingRTL(in: full, rtlIndexes: rtlSet)
        XCTAssertEqual(partial.character(at: 0).rtlStatus, .RTL)
        XCTAssertEqual(partial.character(at: 1).rtlStatus, .LTR)
    }

    func testIsEqualOutOfBoundsRangeReturnsFalse() {
        let line = iTermLegacyStyleString(line: [makeStyle(), makeStyle()], eaIndex: nil)
        let rhs = line.clone()
        XCTAssertFalse(line.isEqual(lhsRange: NSRange(location: 5, length: 1),
                                    toString: rhs,
                                    startingAtIndex: 0))
    }

    func testStringBySettingRTL_nilResetsToUnknown() {
        let style = makeStyle()
        let msca = MutableScreenCharArray.emptyLine(ofLength: 0)
        msca.append("ABC", style: style, continuation: style)
        let lineArray = Array(UnsafeBufferPointer(start: msca.line, count: Int(msca.length)))
        let legacy = iTermLegacyStyleString(line: lineArray, eaIndex: msca.eaIndex)

        let full = NSRange(location: 0, length: legacy.cellCount)
        let reset = legacy.stringBySettingRTL(in: full, rtlIndexes: nil)
        for i in 0..<reset.cellCount {
            XCTAssertEqual(reset.character(at: i).rtlStatus, .unknown)
        }
    }

    func testDoubleWidthIndexes_true() {
        var c = screen_char_t()
        c.code = UInt16(DWC_RIGHT)
        let string = iTermLegacyStyleString(line: Array(repeating: c, count: 10), eaIndex: nil)
        let actual = string.doubleWidthIndexes(range: NSRange(location: 5, length: 2), rebaseTo: 3)
        let expected = IndexSet([3, 4])
        XCTAssertEqual(actual, expected)
    }
}
