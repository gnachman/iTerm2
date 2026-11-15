//
//  QuickLookDomainAllowlistTests.swift
//  ModernTests
//
//  Quick Look on hover only opens a popover for web URLs whose host matches the user’s
//  allowlist: an exact host or any subdomain of it. An empty list allows every web URL.
//

import XCTest
@testable import iTerm2SharedARC

final class QuickLookDomainAllowlistTests: XCTestCase {
    private func url(_ string: String) -> URL {
        return URL(string: string)!
    }

    func testEmptyAllowsAnyWebURL() {
        for list in ["", " , ,"] {
            let allowlist = iTermQuickLookDomainAllowlist(string: list)
            XCTAssertTrue(allowlist.isEmpty, list)
            XCTAssertTrue(allowlist.allows(url("https://example.com/x")), list)
            XCTAssertTrue(allowlist.allows(url("http://example.com/x")), list)
        }
    }

    func testExactAndSubdomain() {
        let allowlist = iTermQuickLookDomainAllowlist(string: "linear.app, github.com")
        XCTAssertFalse(allowlist.isEmpty)
        XCTAssertTrue(allowlist.allows(url("https://linear.app/t/RD-1")))
        XCTAssertTrue(allowlist.allows(url("https://www.linear.app")))
        XCTAssertTrue(allowlist.allows(url("https://GitHub.com/a")))
        XCTAssertFalse(allowlist.allows(url("https://linear.app.evil.com")))
        XCTAssertFalse(allowlist.allows(url("https://evillinear.app")))
        XCTAssertFalse(allowlist.allows(url("https://example.com")))
    }

    func testWhitespaceSeparatedEntries() {
        let allowlist = iTermQuickLookDomainAllowlist(string: "linear.app\ngithub.com")
        XCTAssertTrue(allowlist.allows(url("https://github.com/a")))
        XCTAssertTrue(allowlist.allows(url("https://linear.app/a")))
    }

    func testCaseAndTrailingDot() {
        let allowlist = iTermQuickLookDomainAllowlist(string: "Linear.App.")
        XCTAssertTrue(allowlist.allows(url("https://linear.app/")))
    }

    func testNonWebSchemeDenied() {
        for list in ["linear.app", ""] {
            let allowlist = iTermQuickLookDomainAllowlist(string: list)
            XCTAssertFalse(allowlist.allows(url("file:///tmp/x")), list)
            XCTAssertFalse(allowlist.allows(url("mailto:a@linear.app")), list)
        }
    }

    func testIDN() {
        let allowlist = iTermQuickLookDomainAllowlist(string: "bücher.de")
        XCTAssertTrue(allowlist.allows(url("https://xn--bcher-kva.de/")))
        XCTAssertFalse(allowlist.allows(url("https://example.de/")))
    }

    // "." is empty once its trailing dot is removed, so it is dropped as unusable.
    func testUnnormalizableEntryFailsClosed() {
        let allowlist = iTermQuickLookDomainAllowlist(string: ".")
        XCTAssertFalse(allowlist.isEmpty)
        XCTAssertFalse(allowlist.allows(url("https://example.com")))
        XCTAssertFalse(allowlist.allows(url("http://example.com")))
    }

    func testUnnormalizableEntryDoesNotDropUsableOnes() {
        let allowlist = iTermQuickLookDomainAllowlist(string: "., linear.app")
        XCTAssertTrue(allowlist.allows(url("https://linear.app/x")))
        XCTAssertFalse(allowlist.allows(url("https://example.com")))
    }

    // The part before "@" is user info, so the host here is evil.com.
    func testUserInfoDoesNotSpoofHost() {
        let allowlist = iTermQuickLookDomainAllowlist(string: "linear.app")
        XCTAssertFalse(allowlist.allows(url("https://linear.app@evil.com/")))
        XCTAssertFalse(allowlist.allows(url("https://user:linear.app@evil.com/")))
    }

    func testDefaultsAreOff() {
        XCTAssertEqual(iTermPreferences.defaultObject(forKey: kPreferenceKeyQuickLookUsesBrowserEngine) as? Bool, false)
        XCTAssertEqual(iTermPreferences.defaultObject(forKey: kPreferenceKeyQuickLookHoverMode) as? Int, 0)
        XCTAssertEqual(iTermPreferences.defaultObject(forKey: kPreferenceKeyQuickLookHoverDelay) as? Double, 0.75)
        XCTAssertEqual(iTermPreferences.defaultObject(forKey: kPreferenceKeyQuickLookHoverAutoCloseDelay) as? Double, 1.5)
        XCTAssertEqual(iTermPreferences.defaultObject(forKey: kPreferenceKeyQuickLookHoverDomainAllowlist) as? String, "")
        XCTAssertEqual(iTermQuickLookHoverMode.off.rawValue, 0)
        XCTAssertEqual(iTermQuickLookHoverMode.hover.rawValue, 1)
        XCTAssertEqual(iTermQuickLookHoverMode.commandHover.rawValue, 2)
    }
}
