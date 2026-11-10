//
//  iTermExternalAttributeIndexEqualityTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class iTermExternalAttributeIndexEqualityTests: XCTestCase {
    private func hyperlink(_ string: String) -> iTermExternalAttribute {
        let url = iTermURL(url: URL(string: string)!, identifier: nil, target: nil)
        return iTermExternalAttribute(underlineColor: VT100TerminalColorValue(),
                                      url: url,
                                      blockIDList: nil,
                                      controlCode: nil)
    }

    // An attribute whose only non-default field is a dual-mode foreground
    // color. Every other field matches nil, so comparing it against nil
    // reaches the dual-mode check.
    private func dualModeForeground() -> iTermExternalAttribute {
        var color = iTermDualModeColor()
        color.valid = true
        color.light.red = 255
        color.dark.blue = 255
        return iTermExternalAttribute(havingUnderlineColor: false,
                                      underlineColor: VT100TerminalColorValue(),
                                      url: nil,
                                      blockIDList: nil,
                                      controlCode: nil,
                                      dualModeForeground: color,
                                      dualModeBackground: iTermDualModeColor())!
    }

    private func index(_ attribute: iTermExternalAttribute, at column: Int32) -> iTermExternalAttributeIndex {
        let index = iTermExternalAttributeIndex()
        index.setAttributes(attribute, at: column, count: 1)
        return index
    }

    // MARK: - Sparse indexes

    func testDifferentAttributesAtSameColumnAreNotEqual() {
        let lhs = index(hyperlink("https://a.example.com"), at: 3)
        let rhs = index(hyperlink("https://b.example.com"), at: 3)
        XCTAssertFalse(lhs.isEqual(toExternalAttributeIndex: rhs))
        XCTAssertFalse(rhs.isEqual(toExternalAttributeIndex: lhs))
        XCTAssertFalse(iTermExternalAttributeIndex.externalAttributeIndex(lhs, isEqualToIndex: rhs))
    }

    // iTermURL compares by identity, so share one attribute.
    func testSameAttributesAreEqual() {
        let attribute = hyperlink("https://a.example.com")
        let lhs = index(attribute, at: 3)
        let rhs = index(attribute, at: 3)
        XCTAssertTrue(lhs.isEqual(toExternalAttributeIndex: rhs))
        XCTAssertTrue(iTermExternalAttributeIndex.externalAttributeIndex(lhs, isEqualToIndex: rhs))
    }

    func testAttributeInOnlyOneIndexIsNotEqual() {
        let lhs = index(hyperlink("https://a.example.com"), at: 3)
        let rhs = index(hyperlink("https://a.example.com"), at: 4)
        XCTAssertFalse(lhs.isEqual(toExternalAttributeIndex: rhs))
        XCTAssertFalse(rhs.isEqual(toExternalAttributeIndex: lhs))
    }

    // Used to crash dereferencing nil in -isEqualToExternalAttribute:.
    func testDualModeAttributeMissingFromOtherIndexDoesNotCrash() {
        let lhs = index(dualModeForeground(), at: 0)
        let rhs = index(hyperlink("https://a.example.com"), at: 1)
        XCTAssertFalse(lhs.isEqual(toExternalAttributeIndex: rhs))
        XCTAssertFalse(rhs.isEqual(toExternalAttributeIndex: lhs))
        XCTAssertFalse(lhs.isEqual(toExternalAttributeIndex: iTermExternalAttributeIndex()))
        XCTAssertFalse(iTermExternalAttributeIndex().isEqual(toExternalAttributeIndex: lhs))
        XCTAssertFalse(iTermExternalAttributeIndex.externalAttributeIndex(lhs, isEqualToIndex: nil))
        XCTAssertFalse(iTermExternalAttributeIndex.externalAttributeIndex(nil, isEqualToIndex: lhs))
    }

    func testAttributeIsNotEqualToNil() {
        XCTAssertFalse(dualModeForeground().isEqual(to: nil as iTermExternalAttribute?))
        XCTAssertFalse(hyperlink("https://a.example.com").isEqual(to: nil as iTermExternalAttribute?))
    }

    func testEmptyIndexEqualsNil() {
        XCTAssertTrue(iTermExternalAttributeIndex.externalAttributeIndex(iTermExternalAttributeIndex(),
                                                                         isEqualToIndex: nil))
    }

    // MARK: - Uniform indexes

    func testUniformIndexesWithDifferentAttributesAreNotEqual() {
        let lhs = iTermUniformExternalAttributes.withAttribute(hyperlink("https://a.example.com"))
        let rhs = iTermUniformExternalAttributes.withAttribute(hyperlink("https://b.example.com"))
        XCTAssertFalse(lhs.isEqual(toExternalAttributeIndex: rhs))
        XCTAssertFalse(rhs.isEqual(toExternalAttributeIndex: lhs))
    }

    func testUniformIndexesWithSameAttributeAreEqual() {
        let attribute = hyperlink("https://a.example.com")
        let lhs = iTermUniformExternalAttributes.withAttribute(attribute)
        let rhs = iTermUniformExternalAttributes.withAttribute(attribute)
        XCTAssertTrue(lhs.isEqual(toExternalAttributeIndex: rhs))
    }

    func testNonEmptyUniformIndexIsNotEqualToNil() {
        let uniform = iTermUniformExternalAttributes.withAttribute(hyperlink("https://a.example.com"))
        XCTAssertFalse(iTermExternalAttributeIndex.externalAttributeIndex(uniform, isEqualToIndex: nil))
        XCTAssertFalse(iTermExternalAttributeIndex.externalAttributeIndex(nil, isEqualToIndex: uniform))
    }

    func testUniformIndexIsNotEqualToSparseIndex() {
        let attribute = hyperlink("https://a.example.com")
        let uniform = iTermUniformExternalAttributes.withAttribute(attribute)
        let sparse = index(attribute, at: 0)
        XCTAssertFalse(uniform.isEqual(toExternalAttributeIndex: sparse))
        XCTAssertFalse(sparse.isEqual(toExternalAttributeIndex: uniform))
        XCTAssertFalse(uniform.isEqual(toExternalAttributeIndex: iTermExternalAttributeIndex()))
        XCTAssertFalse(iTermExternalAttributeIndex().isEqual(toExternalAttributeIndex: uniform))
    }
}
