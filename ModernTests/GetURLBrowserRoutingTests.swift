//
//  GetURLBrowserRoutingTests.swift
//  iTerm2 ModernTests
//
//  When the OS (or `open -a iTerm <url>`, Velja, vim gx, etc.) hands iTerm2 a URL
//  via the GetURL Apple event, the handler must decide whether the scheme should
//  open in the built-in web browser. Only http/https/file qualify: ftp does not
//  because the built-in browser cannot display it. See issue 12431.
//

import XCTest
@testable import iTerm2SharedARC

final class GetURLBrowserRoutingTests: XCTestCase {
    func testWebSchemesRouteToBuiltInBrowser() {
        XCTAssertTrue(iTermBrowserGateway.schemeRoutesToBuiltInBrowser("http"))
        XCTAssertTrue(iTermBrowserGateway.schemeRoutesToBuiltInBrowser("https"))
        XCTAssertTrue(iTermBrowserGateway.schemeRoutesToBuiltInBrowser("file"))
    }

    func testSchemeMatchingIsCaseInsensitive() {
        XCTAssertTrue(iTermBrowserGateway.schemeRoutesToBuiltInBrowser("HTTPS"))
        XCTAssertTrue(iTermBrowserGateway.schemeRoutesToBuiltInBrowser("File"))
    }

    func testFtpDoesNotRouteToBuiltInBrowser() {
        XCTAssertFalse(iTermBrowserGateway.schemeRoutesToBuiltInBrowser("ftp"))
    }

    func testNonWebSchemesDoNotRoute() {
        XCTAssertFalse(iTermBrowserGateway.schemeRoutesToBuiltInBrowser("ssh"))
        XCTAssertFalse(iTermBrowserGateway.schemeRoutesToBuiltInBrowser("telnet"))
        XCTAssertFalse(iTermBrowserGateway.schemeRoutesToBuiltInBrowser("iterm2"))
        XCTAssertFalse(iTermBrowserGateway.schemeRoutesToBuiltInBrowser(nil))
        XCTAssertFalse(iTermBrowserGateway.schemeRoutesToBuiltInBrowser(""))
    }
}
