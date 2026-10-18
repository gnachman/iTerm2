//
//  BrowserViewSourceTests.swift
//  ModernTests
//
//  View Source must show the page's source. The source page is served from
//  iterm2-about:source, and navigating there drops the local page contexts in
//  decidePolicyFor before the scheme handler runs, so the source has to survive
//  that.
//

import XCTest
import WebKit
@testable import iTerm2SharedARC

@MainActor
final class BrowserViewSourceTests: XCTestCase {
    private var manager: iTermBrowserManager?

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    private func makeManager() throws -> iTermBrowserManager {
        let user = iTermBrowserUser.devNull
        let navigationState = iTermBrowserNavigationState()
        let sessionGuid = UUID().uuidString
        let model = try XCTUnwrap(ProfileModel.sharedInstance())
        let profileGuid = try XCTUnwrap(model.defaultBookmark()?[KEY_GUID] as? String)
        let manager = iTermBrowserManager(
            user: user,
            configuration: nil,
            sessionGuid: sessionGuid,
            historyController: iTermBrowserHistoryController(user: user,
                                                             sessionGuid: sessionGuid,
                                                             navigationState: navigationState),
            navigationState: navigationState,
            profileObserver: iTermProfilePreferenceObserver(guid: profileGuid, model: model),
            profileMutator: iTermProfilePreferenceMutator(model: model, guid: profileGuid),
            pointerController: PointerController())
        self.manager = manager
        return manager
    }

    // Waits until the web view has finished loading `url`.
    private func waitForLoad(of url: URL?,
                             in webView: WKWebView,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        let done = expectation(description: "loaded \(url?.absoluteString ?? "page")")
        var fulfilled = false
        let check = { (webView: WKWebView) in
            if !fulfilled && !webView.isLoading && (url == nil || webView.url == url) {
                fulfilled = true
                done.fulfill()
            }
        }
        let loadingObservation = webView.observe(\.isLoading, options: [.initial, .new]) { webView, _ in
            MainActor.assumeIsolated { check(webView) }
        }
        let urlObservation = webView.observe(\.url, options: [.new]) { webView, _ in
            MainActor.assumeIsolated { check(webView) }
        }
        wait(for: [done], timeout: 30)
        loadingObservation.invalidate()
        urlObservation.invalidate()
    }

    private func evaluate(_ script: String, in webView: WKWebView) -> String? {
        let done = expectation(description: "evaluate")
        var value: String?
        webView.evaluateJavaScript(script) { result, _ in
            value = result as? String
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        return value
    }

    func testViewSourceShowsThePageSourceEscaped() throws {
        let manager = try makeManager()
        let webView = try XCTUnwrap(manager.webView)
        let marker = "VIEW_SOURCE_MARKER_387"
        let pageHTML = "<html><head></head><body><h1>\(marker) &amp; friends</h1></body></html>"

        // A page with no http(s) URL, so View Source takes the page's DOM rather
        // than refetching it from the network. Both paths end in the same
        // showSourcePage call, which is where the source used to get lost.
        let started = expectation(description: "page load started")
        var startedFulfilled = false
        let startObservation = webView.observe(\.isLoading, options: [.new]) { webView, _ in
            MainActor.assumeIsolated {
                if webView.isLoading && !startedFulfilled {
                    startedFulfilled = true
                    started.fulfill()
                }
            }
        }
        webView.loadHTMLString(pageHTML, baseURL: URL(string: "about:blank"))
        wait(for: [started], timeout: 30)
        startObservation.invalidate()
        waitForLoad(of: nil, in: webView)
        XCTAssertEqual(evaluate("document.querySelector('h1').textContent", in: webView),
                       "\(marker) & friends")

        // Drive the real View Source path (the context menu's action).
        manager.perform(NSSelectorFromString("viewPageSource"))
        waitForLoad(of: iTermBrowserSourceHandler.sourceURL, in: webView)

        let shownText = try XCTUnwrap(
            evaluate("document.querySelector('.source-code').textContent", in: webView))
        XCTAssertTrue(shownText.contains("<h1>\(marker) &amp; friends</h1>"), shownText)
        XCTAssertFalse(shownText.contains("No source available"), shownText)

        // The source is shown as text: it did not become markup in the source page.
        let shownHTML = try XCTUnwrap(
            evaluate("document.querySelector('.source-code').innerHTML", in: webView))
        XCTAssertFalse(shownHTML.contains("<h1>"), shownHTML)
        XCTAssertNil(evaluate("document.querySelector('.source-code h1') ? 'found' : null", in: webView))
    }
}
