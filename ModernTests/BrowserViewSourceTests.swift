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

    private static var fakesKeptAlive = [WKNavigationAction]()

    private final class FakeFrameInfo: WKFrameInfo {
        private let fakeIsMainFrame: Bool
        init(mainFrame: Bool) {
            self.fakeIsMainFrame = mainFrame
            super.init()
        }
        override var isMainFrame: Bool { fakeIsMainFrame }
    }

    private final class FakeNavigationAction: WKNavigationAction {
        private let fakeRequest: URLRequest
        private let fakeTargetFrame: WKFrameInfo
        init(url: URL, mainFrame: Bool) {
            fakeRequest = URLRequest(url: url)
            fakeTargetFrame = FakeFrameInfo(mainFrame: mainFrame)
            super.init()
        }
        override var request: URLRequest { fakeRequest }
        override var targetFrame: WKFrameInfo? { fakeTargetFrame }
        override var navigationType: WKNavigationType { .other }
        override var modifierFlags: NSEvent.ModifierFlags { [] }
    }

    // Starts showing `source` and, before WebKit asks for iterm2-about:source,
    // reports another navigation to the manager. Returns the text the source
    // page ends up showing.
    private func sourceShown(afterInterveningNavigationInMainFrame mainFrame: Bool,
                             source: String) throws -> String {
        let manager = try makeManager()
        let webView = try XCTUnwrap(manager.webView)
        manager.showSourceInBrowser(htmlSource: source,
                                    url: try XCTUnwrap(URL(string: "http://example.invalid/old")))
        // WebKit can't call back until the run loop turns, so this always
        // happens before the source page is requested.
        var decision: WKNavigationActionPolicy?
        let action = FakeNavigationAction(
            url: try XCTUnwrap(URL(string: "http://example.invalid/new")),
            mainFrame: mainFrame)
        // WebKit's API objects crash in dealloc when they have no backing
        // object, so the fakes are never freed.
        Self.fakesKeptAlive.append(action)
        manager.webView(webView,
                        decidePolicyFor: action,
                        decisionHandler: { policy in decision = policy })
        XCTAssertEqual(decision, .allow)
        waitForLoad(of: iTermBrowserSourceHandler.sourceURL, in: webView)
        return try XCTUnwrap(
            evaluate("document.querySelector('.source-code').textContent", in: webView))
    }

    // A View Source that another main-frame navigation superseded must not leave
    // its source behind to be served by a later visit to iterm2-about:source.
    func testSupersededViewSourceDoesNotLeaveStaleSource() throws {
        let shown = try sourceShown(afterInterveningNavigationInMainFrame: true,
                                    source: "<p>STALE_SOURCE_387</p>")
        XCTAssertFalse(shown.contains("STALE_SOURCE_387"), shown)
        XCTAssertTrue(shown.contains("No source available"), shown)
    }

    // A subframe navigation in the current page doesn't supersede View Source.
    func testSubframeNavigationKeepsPendingSource() throws {
        let shown = try sourceShown(afterInterveningNavigationInMainFrame: false,
                                    source: "<p>KEPT_SOURCE_387</p>")
        XCTAssertTrue(shown.contains("<p>KEPT_SOURCE_387</p>"), shown)
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

    private struct ShownSource {
        var text: String
        // [href, text] for each link, in document order.
        var links: [[String]]
        var injected: Bool
    }

    private func show(source: String, pageURL: String) throws -> ShownSource {
        let manager = try makeManager()
        let webView = try XCTUnwrap(manager.webView)
        manager.showSourceInBrowser(htmlSource: source,
                                    url: try XCTUnwrap(URL(string: pageURL)))
        waitForLoad(of: iTermBrowserSourceHandler.sourceURL, in: webView)
        // Newlines are shown as <br> elements, which textContent omits.
        let text = try XCTUnwrap(
            evaluate("document.querySelector('.source-code').textContent", in: webView))
        let linksJSON = try XCTUnwrap(evaluate(
            "JSON.stringify(Array.from(document.querySelectorAll('.source-code a')).map(a => [a.getAttribute('href'), a.textContent]))",
            in: webView))
        let links = try JSONDecoder().decode([[String]].self, from: Data(linksJSON.utf8))
        let injected = evaluate(
            "document.querySelector('.source-code img, .source-code b, .source-code script') ? 'yes' : 'no'",
            in: webView) == "yes"
        return ShownSource(text: text, links: links, injected: injected)
    }

    // A linkified URL with an ampersand must stay a working link and must not
    // spill markup into the displayed source.
    func testLinksContainingAmpersandsWork() throws {
        let source = """
            <html><head><link href="style.css" rel="stylesheet"></head>
            <body><a href="rel.html">r</a><img src="img/p.png">
            <a href="http://example.invalid/white.html?a=1&b=2">abs</a>
            <a href="q?c=3&amp;d=4">ent</a>
            <a href="r?a=1&region=us&param=2&copy=3">legacy</a></body></html>
            """
        let shown = try show(source: source, pageURL: "http://example.invalid/a&b/?x=1&y=2")
        XCTAssertEqual(shown.text, source.replacingOccurrences(of: "\n", with: ""))
        XCTAssertEqual(shown.links, [
            ["http://example.invalid/a&b/style.css", "style.css"],
            ["http://example.invalid/a&b/rel.html", "rel.html"],
            ["http://example.invalid/a&b/img/p.png", "img/p.png"],
            ["http://example.invalid/white.html?a=1&b=2", "http://example.invalid/white.html?a=1&b=2"],
            ["http://example.invalid/a&b/q?c=3&d=4", "q?c=3&amp;d=4"],
            ["http://example.invalid/a&b/r?a=1&region=us&param=2&copy=3", "r?a=1&region=us&param=2&copy=3"],
        ])
        XCTAssertFalse(shown.injected)
    }

    // T-95: innerHTML leaves quotes in text unescaped, so attribute values must be matched by
    // their plain quotes to be highlighted. Highlighting must not turn the source into markup.
    func testAttributeValuesAreHighlighted() throws {
        let source = """
            <div class="a b" title='t' id=x>v</div>
            <p title='"><img src=y onerror=alert(1)>' data-x="'<b>">w</p>
            """
        let manager = try makeManager()
        let webView = try XCTUnwrap(manager.webView)
        manager.showSourceInBrowser(htmlSource: source,
                                    url: try XCTUnwrap(URL(string: "http://example.invalid/")))
        waitForLoad(of: iTermBrowserSourceHandler.sourceURL, in: webView)
        let text = try XCTUnwrap(
            evaluate("document.querySelector('.source-code').textContent", in: webView))
        XCTAssertEqual(text, source.replacingOccurrences(of: "\n", with: ""))
        let valuesJSON = try XCTUnwrap(evaluate(
            "JSON.stringify(Array.from(document.querySelectorAll('.source-code .attr-value')).map(e => e.textContent))",
            in: webView))
        let values = try JSONDecoder().decode([String].self, from: Data(valuesJSON.utf8))
        XCTAssertEqual(values, ["\"a b\"", "'t'"])
        XCTAssertEqual(evaluate(
            "document.querySelector('.source-code img, .source-code b, .source-code script') ? 'yes' : 'no'",
            in: webView), "no")
    }

    // A local file's relative links become file links.
    func testFilePageLinksToFiles() throws {
        let source = "<a href=\"y.html\">y</a>"
        let shown = try show(source: source, pageURL: "file:///tmp/a&b/x.html")
        XCTAssertEqual(shown.links, [["file:///tmp/a&b/y.html", "y.html"]])
    }

    // URLs in the source stay text, and script URLs don't become links.
    func testLinkifyingDoesNotInjectMarkupOrScriptLinks() throws {
        let source = """
            <a href="JavaScript:alert(1)">j</a>
            <a href=" javascript:alert(2)">k</a>
            <a href="x&lt;img src=y onerror=alert(3)&gt;">l</a>
            <a href="&lt;b&gt;bold&lt;/b&gt;">m</a>
            <a href="file:///etc/passwd">f</a>
            """
        let shown = try show(source: source, pageURL: "http://example.invalid/")
        XCTAssertEqual(shown.text, source.replacingOccurrences(of: "\n", with: ""))
        XCTAssertFalse(shown.injected)
        XCTAssertEqual(shown.links.count, 2, "\(shown.links)")
        for link in shown.links {
            XCTAssertTrue(link[0].hasPrefix("http://example.invalid/"), "\(link)")
        }
    }
}
