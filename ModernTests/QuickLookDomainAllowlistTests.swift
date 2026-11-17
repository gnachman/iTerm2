//
//  QuickLookDomainAllowlistTests.swift
//  ModernTests
//
//  Quick Look on hover only opens a popover for web URLs whose host matches the user’s
//  allowlist: an exact host or any subdomain of it. An empty list allows nothing. A secure
//  setting allows every public domain; private addresses always need an entry.
//

import XCTest
@testable import iTerm2SharedARC

final class QuickLookDomainAllowlistTests: XCTestCase {
    private func url(_ string: String) -> URL {
        return URL(string: string)!
    }

    private func list(_ entries: String..., allowAll: Bool = false) -> iTermQuickLookDomainAllowlist {
        return iTermQuickLookDomainAllowlist(entries: entries, allowsAllDomains: allowAll)
    }

    func testEmptyAllowsNothing() {
        let allowlist = list()
        XCTAssertFalse(allowlist.allows(url("https://example.com/x")))
        XCTAssertFalse(allowlist.allows(url("http://example.com/x")))
    }

    func testAllowAllAllowsPublicDomains() {
        let allowlist = list(allowAll: true)
        XCTAssertTrue(allowlist.allows(url("https://example.com/x")))
        XCTAssertTrue(allowlist.allows(url("http://93.184.216.34/")))
    }

    func testAllowAllRefusesPrivateHosts() {
        let allowlist = list(allowAll: true)
        for string in ["http://localhost:8080/",
                       "http://127.0.0.1/",
                       "http://10.1.2.3/",
                       "http://172.20.0.1/",
                       "http://192.168.1.1/admin",
                       "http://169.254.169.254/latest/meta-data",
                       "http://100.64.0.1/",
                       "http://0.0.0.0/",
                       "http://[::1]/",
                       "http://[fe80::1]/",
                       "http://[fd00::1]/",
                       "http://[::ffff:192.168.1.1]/",
                       "http://printer.local/",
                       "http://router/",
                       "http://app.localhost/",
                       "http://db.internal/",
                       "http://nas.home.arpa/"] {
            XCTAssertFalse(allowlist.allows(url(string)), string)
        }
        XCTAssertTrue(allowlist.allows(url("http://172.32.0.1/")), "just outside 172.16/12")
    }

    // WebKit reads these hosts as IPv4 addresses (shorthand, hex, octal) though Foundation's
    // URL.host leaves them as written.
    func testAllowAllRefusesIPv4ShorthandForPrivateAddresses() {
        let allowlist = list(allowAll: true)
        for string in ["http://127.1/",
                       "http://10.1/",
                       "http://192.168.1/",
                       "http://0x7f.0.0.1/",
                       "http://0X7F.0.0.1/",
                       "http://0177.0.0.1/",
                       "http://0x7f000001/",
                       "http://2130706433/",
                       "http://0/",
                       "http://169.254.43518/",
                       "http://127.0.0.1./",
                       "http://foo.127.1/",
                       "http://1.2.3.4.5/",
                       "http://256.0.0.1/",
                       "http://0x/"] {
            XCTAssertFalse(allowlist.allows(url(string)), string)
        }
    }

    func testAllowAllAllowsIPv4ShorthandForPublicAddresses() {
        let allowlist = list(allowAll: true)
        for string in ["http://8.8.2056/", "http://0x8.0x8.0x8.0x8/", "http://134744072/"] {
            XCTAssertTrue(allowlist.allows(url(string)), string)
        }
        XCTAssertTrue(allowlist.allows(url("http://1.2.3.example/")), "the last label isn’t a number")
        XCTAssertFalse(allowlist.allows(url("http://example.0x/")), "“0x” counts as a number, and the host doesn’t parse")
    }

    func testEntryAllowsAPrivateHostItNames() {
        let allowlist = list("192.168.1.1", "printer.local", allowAll: true)
        XCTAssertTrue(allowlist.allows(url("http://192.168.1.1/")))
        XCTAssertTrue(allowlist.allows(url("http://printer.local/")))
        XCTAssertFalse(allowlist.allows(url("http://192.168.1.2/")))
    }

    func testExactAndSubdomain() {
        let allowlist = list("linear.app", "github.com")
        XCTAssertTrue(allowlist.allows(url("https://linear.app/t/RD-1")))
        XCTAssertTrue(allowlist.allows(url("https://www.linear.app")))
        XCTAssertTrue(allowlist.allows(url("https://GitHub.com/a")))
        XCTAssertFalse(allowlist.allows(url("https://linear.app.evil.com")))
        XCTAssertFalse(allowlist.allows(url("https://evillinear.app")))
        XCTAssertFalse(allowlist.allows(url("https://example.com")))
    }

    // People write entries the way they see them elsewhere.
    func testCommonEntryFormsNormalize() {
        let forms = ["*.github.com",
                     ".github.com",
                     "https://github.com",
                     "https://github.com/",
                     "github.com/some/path?q=1",
                     "github.com:443",
                     "  GitHub.com.  ",
                     "user@github.com"]
        for form in forms {
            XCTAssertEqual(iTermQuickLookDomainAllowlist.normalizedEntry(form), "github.com", form)
            let allowlist = list(form)
            XCTAssertTrue(allowlist.allows(url("https://github.com/a")), form)
            XCTAssertTrue(allowlist.allows(url("https://api.github.com/a")), form)
            XCTAssertFalse(allowlist.allows(url("https://evilgithub.com/a")), form)
        }
        XCTAssertEqual(iTermQuickLookDomainAllowlist.normalizedEntry("[::1]:8080"), "::1")
    }

    func testCaseAndTrailingDot() {
        XCTAssertTrue(list("Linear.App.").allows(url("https://linear.app/")))
    }

    func testNonWebSchemeDenied() {
        for allowlist in [list("linear.app"), list(allowAll: true)] {
            XCTAssertFalse(allowlist.allows(url("file:///tmp/x")))
            XCTAssertFalse(allowlist.allows(url("mailto:a@linear.app")))
        }
    }

    func testIDN() {
        let allowlist = list("bücher.de")
        XCTAssertTrue(allowlist.allows(url("https://xn--bcher-kva.de/")))
        XCTAssertFalse(allowlist.allows(url("https://example.de/")))
    }

    func testUnnormalizableEntriesAreDropped() {
        for entry in [".", "*.", "", "   ", "https://"] {
            XCTAssertNil(iTermQuickLookDomainAllowlist.normalizedEntry(entry), entry)
        }
        let allowlist = list(".", "linear.app")
        XCTAssertTrue(allowlist.allows(url("https://linear.app/x")))
        XCTAssertFalse(allowlist.allows(url("https://example.com")))
    }

    // The part before "@" is user info, so the host here is evil.com.
    func testUserInfoDoesNotSpoofHost() {
        let allowlist = list("linear.app")
        XCTAssertFalse(allowlist.allows(url("https://linear.app@evil.com/")))
        XCTAssertFalse(allowlist.allows(url("https://user:linear.app@evil.com/")))
    }

    // The domain offered after the allowlist refused a link: its host, without “www.”.
    func testDomainToOffer() {
        XCTAssertEqual(iTermQuickLookDomainAllowlist.domainToOffer(for: url("https://www.GitHub.com/a")), "github.com")
        XCTAssertEqual(iTermQuickLookDomainAllowlist.domainToOffer(for: url("https://api.github.com/a")), "api.github.com")
        XCTAssertEqual(iTermQuickLookDomainAllowlist.domainToOffer(for: url("http://192.168.1.1:8080/")), "192.168.1.1")
        XCTAssertEqual(iTermQuickLookDomainAllowlist.domainToOffer(for: url("https://user@www.example.com/")), "example.com")
        XCTAssertNil(iTermQuickLookDomainAllowlist.domainToOffer(for: url("file:///tmp/x")))
    }

    func testDefaultsAreOff() {
        XCTAssertEqual(iTermPreferences.defaultObject(forKey: kPreferenceKeyQuickLookUsesBrowserEngine) as? Bool, false)
        XCTAssertEqual(iTermPreferences.defaultObject(forKey: kPreferenceKeyQuickLookHoverMode) as? Int, 0)
        XCTAssertEqual(iTermPreferences.defaultObject(forKey: kPreferenceKeyQuickLookHoverDelay) as? Double, 0.75)
        XCTAssertEqual(iTermPreferences.defaultObject(forKey: kPreferenceKeyQuickLookHoverAutoCloseDelay) as? Double, 1.5)
        XCTAssertEqual(iTermPreferences.defaultObject(forKey: kPreferenceKeyQuickLookHoverDomainAllowlist) as? [String], [])
        XCTAssertFalse(SecureUserDefaults.instance.quickLookHoverAllowsAllDomains.defaultValue)
        XCTAssertEqual(iTermQuickLookHoverMode.off.rawValue, 0)
        XCTAssertEqual(iTermQuickLookHoverMode.hover.rawValue, 1)
        XCTAssertEqual(iTermQuickLookHoverMode.commandHover.rawValue, 2)
    }
}
