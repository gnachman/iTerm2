//
//  BrowserWebViewColorSchemeTests.swift
//  iTerm2
//

import AppKit
import WebKit
import XCTest
@testable import iTerm2SharedARC

// A browser tab must re-render pages that support both color schemes when its
// effective appearance changes at runtime (for example, a theme change). WebKit
// learns of the change in -[WKWebView viewDidChangeEffectiveAppearance], so an
// override that skips super leaves the page in its old scheme.
@MainActor
final class BrowserWebViewColorSchemeTests: XCTestCase {
    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        let expectation: XCTestExpectation
        init(_ expectation: XCTestExpectation) {
            self.expectation = expectation
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            expectation.fulfill()
        }
    }

    private func prefersDark(_ webView: WKWebView) async throws -> Bool {
        let result = try await webView.evaluateJavaScript(
            "window.matchMedia('(prefers-color-scheme: dark)').matches")
        return try XCTUnwrap(result as? Bool)
    }

    func testRuntimeAppearanceChangeReachesPage() async throws {
        let webView = iTermBrowserWebView(frame: NSRect(x: 0, y: 0, width: 200, height: 200),
                                          configuration: WKWebViewConfiguration(),
                                          pointerController: PointerController())
        webView.appearance = NSAppearance(named: .aqua)
        let loaded = expectation(description: "loaded")
        let waiter = LoadWaiter(loaded)
        webView.navigationDelegate = waiter
        webView.loadHTMLString("<html><body>x</body></html>", baseURL: URL(string: "about:blank")!)
        await fulfillment(of: [loaded], timeout: 30)

        let initiallyDark = try await prefersDark(webView)
        XCTAssertFalse(initiallyDark)

        webView.appearance = NSAppearance(named: .darkAqua)
        let nowDark = try await prefersDark(webView)
        XCTAssertTrue(nowDark)

        webView.appearance = NSAppearance(named: .aqua)
        let lightAgain = try await prefersDark(webView)
        XCTAssertFalse(lightAgain)
        webView.navigationDelegate = nil
    }
}
