//
//  ComposerTabRouterTests.swift
//  iTerm2 ModernTests
//
//  Pins the @-address grammar for composer cross-tab routing. The
//  fall-through cases (@2fa/cli, @alligator, bare @2) are the contract
//  that keeps routing from hijacking ordinary composer text. v2 adds
//  pane (@2.3), window (@w3[.tab[.pane]]), and @wall addressing;
//  -1 means “unspecified” (current window / active tab / active pane).
//

import XCTest
@testable import iTerm2SharedARC

class ComposerTabRouterTests: XCTestCase {
    func testRoutesToSingleTab() {
        let route = ComposerTabRouter.parse("@2 fix the failing test")
        XCTAssertEqual(route.kind, .target)
        XCTAssertEqual(route.windowNumber, -1)
        XCTAssertEqual(route.tabNumber, 2)
        XCTAssertEqual(route.paneNumber, -1)
        XCTAssertEqual(route.payload, "fix the failing test")
    }

    func testRoutesToTabPane() {
        let route = ComposerTabRouter.parse("@2.3 restart the dev server")
        XCTAssertEqual(route.kind, .target)
        XCTAssertEqual(route.windowNumber, -1)
        XCTAssertEqual(route.tabNumber, 2)
        XCTAssertEqual(route.paneNumber, 3)
        XCTAssertEqual(route.payload, "restart the dev server")
    }

    func testRoutesToWindow() {
        let route = ComposerTabRouter.parse("@w3 ls")
        XCTAssertEqual(route.kind, .target)
        XCTAssertEqual(route.windowNumber, 3)
        XCTAssertEqual(route.tabNumber, -1)
        XCTAssertEqual(route.paneNumber, -1)
        XCTAssertEqual(route.payload, "ls")
    }

    func testRoutesToWindowTab() {
        let route = ComposerTabRouter.parse("@w3.2 ls")
        XCTAssertEqual(route.kind, .target)
        XCTAssertEqual(route.windowNumber, 3)
        XCTAssertEqual(route.tabNumber, 2)
        XCTAssertEqual(route.paneNumber, -1)
    }

    func testRoutesToWindowTabPane() {
        let route = ComposerTabRouter.parse("@w3.2.1 ls")
        XCTAssertEqual(route.kind, .target)
        XCTAssertEqual(route.windowNumber, 3)
        XCTAssertEqual(route.tabNumber, 2)
        XCTAssertEqual(route.paneNumber, 1)
    }

    func testRoutesToAll() {
        let route = ComposerTabRouter.parse("@all /compact")
        XCTAssertEqual(route.kind, .all)
        XCTAssertEqual(route.payload, "/compact")
    }

    func testRoutesToAllWindows() {
        let route = ComposerTabRouter.parse("@wall /compact")
        XCTAssertEqual(route.kind, .allWindows)
        XCTAssertEqual(route.payload, "/compact")
    }

    func testZeroParsesAsTabZero() {
        // Resolution (not parsing) rejects out-of-range numbers like 0.
        let route = ComposerTabRouter.parse("@0 x")
        XCTAssertEqual(route.kind, .target)
        XCTAssertEqual(route.tabNumber, 0)
    }

    func testExplicitWindowZeroParses() {
        // “No window 0” comes from resolution, not the parser.
        let route = ComposerTabRouter.parse("@w0 x")
        XCTAssertEqual(route.kind, .target)
        XCTAssertEqual(route.windowNumber, 0)
        XCTAssertEqual(route.tabNumber, -1)
    }

    func testExplicitPaneZeroParses() {
        let route = ComposerTabRouter.parse("@2.0 x")
        XCTAssertEqual(route.kind, .target)
        XCTAssertEqual(route.tabNumber, 2)
        XCTAssertEqual(route.paneNumber, 0)
    }

    func testHereClearsDefaultAndRunsLocally() {
        let route = ComposerTabRouter.parse("@. ls -l")
        XCTAssertEqual(route.kind, .here)
        XCTAssertEqual(route.payload, "ls -l")
    }

    func testBareHereFallsThrough() {
        XCTAssertEqual(ComposerTabRouter.parse("@.").kind, .none)
        XCTAssertEqual(ComposerTabRouter.parse("@.   ").kind, .none)
    }

    func testDoubleDotFallsThrough() {
        XCTAssertEqual(ComposerTabRouter.parse("@.. x").kind, .none)
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

    func testTooManyComponentsFallsThrough() {
        XCTAssertEqual(ComposerTabRouter.parse("@2.3.4 x").kind, .none)
        XCTAssertEqual(ComposerTabRouter.parse("@w2.1.3.4 x").kind, .none)
    }

    func testEmptyComponentsFallThrough() {
        XCTAssertEqual(ComposerTabRouter.parse("@2. x").kind, .none)
        XCTAssertEqual(ComposerTabRouter.parse("@2..3 x").kind, .none)
        XCTAssertEqual(ComposerTabRouter.parse("@.2 x").kind, .none)
    }

    func testBareWFallsThrough() {
        XCTAssertEqual(ComposerTabRouter.parse("@w x").kind, .none)
    }

    func testNonDigitWindowFallsThrough() {
        XCTAssertEqual(ComposerTabRouter.parse("@walls x").kind, .none)
        XCTAssertEqual(ComposerTabRouter.parse("@w2a x").kind, .none)
    }

    func testMultilinePayloadPreserved() {
        let route = ComposerTabRouter.parse("@2 first line\nsecond line")
        XCTAssertEqual(route.kind, .target)
        XCTAssertEqual(route.payload, "first line\nsecond line")
    }

    func testNewlineSeparatorAccepted() {
        let route = ComposerTabRouter.parse("@2\nfoo")
        XCTAssertEqual(route.kind, .target)
        XCTAssertEqual(route.tabNumber, 2)
        XCTAssertEqual(route.payload, "foo")
    }

    func testTabSeparatorAccepted() {
        let route = ComposerTabRouter.parse("@3\tls")
        XCTAssertEqual(route.kind, .target)
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
        // @all / @wall are case-sensitive by design.
        XCTAssertEqual(ComposerTabRouter.parse("@ALL x").kind, .none)
        XCTAssertEqual(ComposerTabRouter.parse("@WALL x").kind, .none)
    }

    func testAddressMidTextFallsThrough() {
        XCTAssertEqual(ComposerTabRouter.parse("ls\n@2 x").kind, .none)
    }

    func testHugeNumberFallsThrough() {
        // Doesn't fit in Int → treated as a near-miss, not an error.
        XCTAssertEqual(ComposerTabRouter.parse("@99999999999999999999 x").kind, .none)
    }
}
