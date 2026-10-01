//
//  iTermBrowserBasicAuthStoreTests.swift
//  ModernTests
//
//  Covers the pure logic of iTermBrowserBasicAuthStore: the account-name derivation used
//  to key password-manager entries, and the decision of whether to retry a remembered
//  credential or prompt the user. The password-manager I/O itself is not exercised here.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermBrowserBasicAuthStoreTests: XCTestCase {
    // MARK: - accountName

    func testAccountNameIncludesRealmWhenPresent() {
        XCTAssertEqual(iTermBrowserBasicAuthStore.accountName(scheme: "https", host: "example.com", port: 443, realm: "Secure Area"),
                       "https://example.com (Secure Area)")
    }

    func testAccountNameOmitsDefaultPort() {
        XCTAssertEqual(iTermBrowserBasicAuthStore.accountName(scheme: "https", host: "example.com", port: 443, realm: ""),
                       "https://example.com")
        XCTAssertEqual(iTermBrowserBasicAuthStore.accountName(scheme: "http", host: "example.com", port: 80, realm: ""),
                       "http://example.com")
    }

    func testAccountNameIncludesNonDefaultPort() {
        XCTAssertEqual(iTermBrowserBasicAuthStore.accountName(scheme: "http", host: "example.com", port: 8080, realm: "Secure"),
                       "http://example.com:8080 (Secure)")
    }

    func testAccountNameDistinguishesRealms() {
        let a = iTermBrowserBasicAuthStore.accountName(scheme: "https", host: "example.com", port: 443, realm: "Admin")
        let b = iTermBrowserBasicAuthStore.accountName(scheme: "https", host: "example.com", port: 443, realm: "Users")
        XCTAssertNotEqual(a, b)
    }

    func testAccountNameDistinguishesSchemeAndPort() {
        // The same host+realm on http vs https, or on two ports, must not collide.
        let https = iTermBrowserBasicAuthStore.accountName(scheme: "https", host: "example.com", port: 443, realm: "Secure")
        let http = iTermBrowserBasicAuthStore.accountName(scheme: "http", host: "example.com", port: 80, realm: "Secure")
        let http8080 = iTermBrowserBasicAuthStore.accountName(scheme: "http", host: "example.com", port: 8080, realm: "Secure")
        XCTAssertNotEqual(https, http)
        XCTAssertNotEqual(http, http8080)
        XCTAssertNotEqual(https, http8080)
    }

    // The accept/reject/persist decision logic that used to live in
    // iTermBrowserManager.basicAuthResponseAction now lives in BrowserBasicAuthCoordinator and is
    // covered by BrowserBasicAuthCoordinatorTests.
}
