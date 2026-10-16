//
//  BidiDisplayInfoPropertyListTests.swift
//  iTerm2
//
//  Created by George Nachman on 10/16/26.
//

import XCTest
@testable import iTerm2SharedARC

// Session archives and window arrangements saved to a file are property lists.
// Bidi info used to encode its ranges as NSValue, which a property list can't
// hold, so lines with right-to-left text broke them. Issue 13143.
final class BidiDisplayInfoPropertyListTests: XCTestCase {
    private var savedBidi = false

    // Setting a preference refreshes its cached value synchronously.
    private func setBidiPreference(_ enabled: Bool) {
        iTermPreferences.setBool(enabled, forKey: kPreferenceKeyBidi)
        XCTAssertEqual(iTermPreferences.bidiEnabled(), enabled, "Precondition")
    }

    override func setUp() {
        super.setUp()
        savedBidi = iTermPreferences.bool(forKey: kPreferenceKeyBidi)
        setBidiPreference(true)
    }

    override func tearDown() {
        setBidiPreference(savedBidi)
        super.tearDown()
    }

    // Mixed text so there are both left-to-right and right-to-left runs, and
    // parentheses so some cells are mirrored.
    private func makeInfo() throws -> BidiDisplayInfoObjc {
        let sca = screenCharArrayWithDefaultStyle("abc \u{05D0} (\u{05D1}) \u{05D2} def", eol: EOL_HARD)
        return try XCTUnwrap(BidiDisplayInfoObjc(sca))
    }

    func testDictionaryValueIsValidPropertyList() throws {
        let info = try makeInfo()
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: info.dictionaryValue,
                                                            format: .binary,
                                                            options: 0))
    }

    func testRoundTripsThroughPropertyList() throws {
        let info = try makeInfo()
        XCTAssertFalse(info.rtlIndexes.isEmpty, "Precondition")
        let data = try PropertyListSerialization.data(fromPropertyList: info.dictionaryValue,
                                                      format: .binary,
                                                      options: 0)
        let decoded = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? NSDictionary)
        let restored = try XCTUnwrap(BidiDisplayInfoObjc(decoded))
        XCTAssertEqual(restored, info)
    }

    // Saves written before ranges were stored as number pairs used NSValue.
    // They must still restore.
    func testDecodesLegacyNSValueRanges() throws {
        let info = try makeInfo()
        var legacy = info.dictionaryValue
        legacy["rtlIndexes"] = info.rtlIndexes.rangeView.map { NSValue(range: NSRange($0)) }
        var mirrored = [NSValue]()
        for i in 0..<info.numberOfCells where info.mirrorsSourceCell(i) {
            mirrored.append(NSValue(range: NSRange(location: Int(i), length: 1)))
        }
        XCTAssertFalse(mirrored.isEmpty, "Precondition")
        legacy["mirroredIndexes"] = mirrored
        let restored = try XCTUnwrap(BidiDisplayInfoObjc(legacy as NSDictionary))
        XCTAssertEqual(restored, info)
    }

    // A corrupt or hand-edited file must not crash restoration. Ranges whose
    // end overflows, or that are malformed, are dropped and the rest kept.
    func testDropsInvalidRanges() throws {
        let info = try makeInfo()
        let valid = info.rtlIndexes.rangeView.map { [$0.lowerBound, $0.count] }
        var dict = info.dictionaryValue
        dict["rtlIndexes"] = valid + [[Int.max, 1], [-1, 2], [3], "junk"] as [Any]
        dict["mirroredIndexes"] = [NSValue(range: NSRange(location: Int.max, length: 1))]
        let restored = try XCTUnwrap(BidiDisplayInfoObjc(dict as NSDictionary))
        XCTAssertEqual(restored.rtlIndexes, info.rtlIndexes)
        for i in 0..<restored.numberOfCells {
            XCTAssertFalse(restored.mirrorsSourceCell(i))
        }
    }
}
