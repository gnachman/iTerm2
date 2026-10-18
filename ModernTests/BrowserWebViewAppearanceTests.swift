//
//  BrowserWebViewAppearanceTests.swift
//  iTerm2
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

// In the Minimal theme a browser session's view is light or dark to match the
// page's background color. The web view must not inherit that, or a dark page
// makes the next page render its dark variant, which keeps the session dark.
@MainActor
final class BrowserWebViewAppearanceTests: XCTestCase {
    private let aqua = NSAppearance(named: .aqua)!
    private let darkAqua = NSAppearance(named: .darkAqua)!

    private func makeHierarchy(sessionAppearance: NSAppearance) -> (session: NSView, webView: NSView) {
        let session = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        session.appearance = sessionAppearance
        let webView = NSView(frame: session.bounds)
        session.addSubview(webView)
        return (session, webView)
    }

    func testMinimalThemeWebViewFollowsAppNotDarkSession() {
        let (_, webView) = makeHierarchy(sessionAppearance: darkAqua)
        iTermBrowserWebViewAppearance.update(webView: webView, minimalTheme: true, appAppearance: aqua)
        XCTAssertEqual(webView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
    }

    func testMinimalThemeWebViewFollowsDarkApp() {
        let (_, webView) = makeHierarchy(sessionAppearance: aqua)
        iTermBrowserWebViewAppearance.update(webView: webView, minimalTheme: true, appAppearance: darkAqua)
        XCTAssertEqual(webView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
    }

    // Other themes don't tint the session view, so the web view inherits as
    // before, including after leaving the Minimal theme.
    func testOtherThemesInherit() {
        let (_, webView) = makeHierarchy(sessionAppearance: darkAqua)
        iTermBrowserWebViewAppearance.update(webView: webView, minimalTheme: true, appAppearance: aqua)
        iTermBrowserWebViewAppearance.update(webView: webView, minimalTheme: false, appAppearance: aqua)
        XCTAssertNil(webView.appearance)
        XCTAssertEqual(webView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
    }
}
