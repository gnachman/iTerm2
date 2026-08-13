//
//  ComposerTabRouterTests.swift
//  iTerm2 ModernTests
//
//  Pins the @-address grammar for composer cross-tab routing. The
//  fall-through cases (@2fa/cli, @alligator, bare @2) are the contract
//  that keeps routing from hijacking ordinary composer text.
//

import XCTest
@testable import iTerm2SharedARC

class ComposerTabRouterTests: XCTestCase {
    func testRoutesToSingleTab() {
        let route = ComposerTabRouter.parse("@2 fix the failing test")
        XCTAssertEqual(route.kind, .tab)
        XCTAssertEqual(route.tabNumber, 2)
        XCTAssertEqual(route.payload, "fix the failing test")
    }

    func testRoutesToAll() {
        let route = ComposerTabRouter.parse("@all /compact")
        XCTAssertEqual(route.kind, .all)
        XCTAssertEqual(route.payload, "/compact")
    }

    func testZeroParsesAsTabZero() {
        // Resolution (not parsing) rejects out-of-range numbers like 0.
        let route = ComposerTabRouter.parse("@0 x")
        XCTAssertEqual(route.kind, .tab)
        XCTAssertEqual(route.tabNumber, 0)
    }

    func testEscapeSendsLiterally() {
        let route = ComposerTabRouter.parse("\\@2 x")
        XCTAssertEqual(route.kind, .escaped)
        XCTAssertEqual(route.payload, "@2 x")
    }

    func testScopedPackageFallsThrough() {
        let route = ComposerTabRouter.parse("@2fa/cli --help")
        XCTAssertEqual(route.kind, .none)
        XCTAssertEqual(route.payload, "@2fa/cli --help")
    }

    func testWordAddressFallsThrough() {
        XCTAssertEqual(ComposerTabRouter.parse("@alligator").kind, .none)
    }

    func testBareAddressFallsThrough() {
        XCTAssertEqual(ComposerTabRouter.parse("@2").kind, .none)
    }

    func testAddressWithOnlyWhitespaceFallsThrough() {
        XCTAssertEqual(ComposerTabRouter.parse("@2   ").kind, .none)
    }

    func testMultilinePayloadPreserved() {
        let route = ComposerTabRouter.parse("@2 first line\nsecond line")
        XCTAssertEqual(route.kind, .tab)
        XCTAssertEqual(route.payload, "first line\nsecond line")
    }

    func testNewlineSeparatorAccepted() {
        let route = ComposerTabRouter.parse("@2\nfoo")
        XCTAssertEqual(route.kind, .tab)
        XCTAssertEqual(route.tabNumber, 2)
        XCTAssertEqual(route.payload, "foo")
    }

    func testTabSeparatorAccepted() {
        let route = ComposerTabRouter.parse("@3\tls")
        XCTAssertEqual(route.kind, .tab)
        XCTAssertEqual(route.tabNumber, 3)
        XCTAssertEqual(route.payload, "ls")
    }

    func testExtraSpacesAfterAddressStripped() {
        let route = ComposerTabRouter.parse("@2   ls -l")
        XCTAssertEqual(route.payload, "ls -l")
    }

    func testPlainCommandFallsThrough() {
        let route = ComposerTabRouter.parse("ls -l")
        XCTAssertEqual(route.kind, .none)
        XCTAssertEqual(route.payload, "ls -l")
    }

    func testEmptyStringFallsThrough() {
        XCTAssertEqual(ComposerTabRouter.parse("").kind, .none)
    }

    func testUppercaseAllFallsThrough() {
        // @all is case-sensitive by design.
        XCTAssertEqual(ComposerTabRouter.parse("@ALL x").kind, .none)
    }

    func testAddressMidTextFallsThrough() {
        XCTAssertEqual(ComposerTabRouter.parse("ls\n@2 x").kind, .none)
    }

    func testHugeNumberFallsThrough() {
        // Doesn't fit in Int → treated as a near-miss, not an error.
        XCTAssertEqual(ComposerTabRouter.parse("@99999999999999999999 x").kind, .none)
    }
}
