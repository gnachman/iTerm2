//
//  BrowserPopupUserContentControllerTests.swift
//  iTerm2
//
//  Found while fixing QA finding F-412. A browser tab opened from another one (a
//  target=_blank link or window.open) got a copy of its opener's configuration, including
//  the opener's WKUserContentController. Its scripts carried the opener's secrets and posted
//  to the opener's handlers, which acted on the opener's page (selection, hover links, find,
//  autofill, the password manager, named marks), and its URL scheme tasks went to the
//  opener's manager, so they were dropped once the opener closed.
//

import AppKit
import WebKit
import XCTest
@testable import iTerm2SharedARC

@MainActor
final class BrowserPopupUserContentControllerTests: XCTestCase {
    private var managers = [iTermBrowserManager]()

    override func tearDown() {
        managers = []
        super.tearDown()
    }

    // MARK: - WebKit behavior the fix relies on

    private final class Recorder: NSObject, WKScriptMessageHandler {
        var messages = [(body: String, webView: WKWebView?)]()
        var onMessage: (() -> Void)?
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            messages.append(("\(message.body)", message.webView))
            onMessage?()
        }
    }

    private final class PopupMaker: NSObject, WKUIDelegate, WKNavigationDelegate {
        let popupController = WKUserContentController()
        var popup: WKWebView?
        var popupCreated: XCTestExpectation?
        var openerLoaded: XCTestExpectation?

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            configuration.userContentController = popupController
            let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  configuration: configuration)
            self.popup = popup
            popupCreated?.fulfill()
            return popup
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            openerLoaded?.fulfill()
        }
    }

    // WebKit accepts a web view for createWebViewWith that was built from the configuration
    // it passed but with another user content controller, and the opener keeps its own.
    func testWebKitAcceptsPopupWithItsOwnUserContentController() async throws {
        let openerRecorder = Recorder()
        let popupRecorder = Recorder()
        let maker = PopupMaker()
        maker.popupController.add(popupRecorder, name: "probe")

        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.add(openerRecorder, name: "probe")
        let opener = WKWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100),
                               configuration: configuration)
        opener.uiDelegate = maker
        opener.navigationDelegate = maker

        maker.openerLoaded = expectation(description: "opener loaded")
        opener.loadHTMLString("<html><body>opener</body></html>", baseURL: URL(string: "about:blank")!)
        await fulfillment(of: [maker.openerLoaded!], timeout: 30)

        maker.popupCreated = expectation(description: "popup created")
        _ = try await opener.evaluateJavaScript("window.open('about:blank', '_blank'); true")
        await fulfillment(of: [maker.popupCreated!], timeout: 30)

        let popup = try XCTUnwrap(maker.popup)
        let popupMessage = expectation(description: "popup message")
        popupRecorder.onMessage = { popupMessage.fulfill() }
        _ = try await popup.evaluateJavaScript("window.webkit.messageHandlers.probe.postMessage('from popup'); true")
        await fulfillment(of: [popupMessage], timeout: 30)
        XCTAssertEqual(popupRecorder.messages.map(\.body), ["from popup"])
        XCTAssertTrue(popupRecorder.messages.allSatisfy { $0.webView === popup })

        let openerMessage = expectation(description: "opener message")
        openerRecorder.onMessage = { openerMessage.fulfill() }
        _ = try await opener.evaluateJavaScript("window.webkit.messageHandlers.probe.postMessage('from opener'); true")
        await fulfillment(of: [openerMessage], timeout: 30)
        XCTAssertEqual(openerRecorder.messages.map(\.body), ["from opener"])
        XCTAssertTrue(openerRecorder.messages.allSatisfy { $0.webView === opener })
    }

    // MARK: - iTermBrowserManager

    private func makeManager(configuration: WKWebViewConfiguration?) throws -> iTermBrowserManager {
        let user = iTermBrowserUser.devNull
        let navigationState = iTermBrowserNavigationState()
        let sessionGuid = UUID().uuidString
        let model = try XCTUnwrap(ProfileModel.sharedInstance())
        let profileGuid = try XCTUnwrap(model.defaultBookmark()?[KEY_GUID] as? String)
        let manager = iTermBrowserManager(
            user: user,
            configuration: configuration,
            sessionGuid: sessionGuid,
            historyController: iTermBrowserHistoryController(user: user,
                                                             sessionGuid: sessionGuid,
                                                             navigationState: navigationState),
            navigationState: navigationState,
            profileObserver: iTermProfilePreferenceObserver(guid: profileGuid, model: model),
            profileMutator: iTermProfilePreferenceMutator(model: model, guid: profileGuid),
            pointerController: PointerController())
        managers.append(manager)
        return manager
    }

    // The configuration a target=_blank link hands to the new tab.
    private func popupConfiguration(from opener: iTermBrowserManager) throws -> WKWebViewConfiguration {
        let configuration = try XCTUnwrap(opener.webView.configuration.copy() as? WKWebViewConfiguration)
        return configuration
    }

    func testPopupGetsItsOwnUserContentControllerAndScripts() throws {
        let opener = try makeManager(configuration: nil)
        let openerController = opener.webView.configuration.userContentController
        let openerScriptCount = openerController.userScripts.count
        XCTAssertGreaterThan(openerScriptCount, 0)

        let popup = try makeManager(configuration: try popupConfiguration(from: opener))
        let popupController = popup.webView.configuration.userContentController
        XCTAssertFalse(popupController === openerController)
        XCTAssertEqual(popupController.userScripts.count, openerScriptCount)
        XCTAssertEqual(openerController.userScripts.count, openerScriptCount)
        // The scripts embed per-manager secrets, so the popup's must not be the opener's.
        XCTAssertNotEqual(try selectionMonitorSecret(in: popup),
                          try selectionMonitorSecret(in: opener))
    }

    private func selectionMonitorSecret(in manager: iTermBrowserManager) throws -> String {
        let regex = try NSRegularExpression(
            pattern: #"iTermSelectionMonitor\.postMessage\(\{[^}]*sessionSecret: "([0-9a-fA-F]+)""#)
        for script in manager.webView.configuration.userContentController.userScripts {
            let source = script.source
            if let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
               let range = Range(match.range(at: 1), in: source) {
                return String(source[range])
            }
        }
        XCTFail("No selection monitor script")
        return ""
    }

    // WebKit's API objects crash in dealloc when they have no backing object, so the fakes
    // are never freed.
    private static var fakesKeptAlive = [WKScriptMessage]()

    private final class FakeScriptMessage: WKScriptMessage {
        private let fakeName: String
        private let fakeBody: Any
        private weak var fakeWebView: WKWebView?

        init(name: String, body: Any, webView: WKWebView) {
            fakeName = name
            fakeBody = body
            fakeWebView = webView
            super.init()
        }

        override var name: String { fakeName }
        override var body: Any { fakeBody }
        override var webView: WKWebView? { fakeWebView }
    }

    private func postSelection(to manager: iTermBrowserManager, from webView: WKWebView) throws {
        // An empty selection so that “copy on select” doesn't touch the pasteboard.
        let message = FakeScriptMessage(name: iTermBrowserSelectionMonitor.messageHandlerName,
                                        body: ["selection": "",
                                               "sessionSecret": try selectionMonitorSecret(in: manager)],
                                        webView: webView)
        Self.fakesKeptAlive.append(message)
        manager.userContentController(manager.webView.configuration.userContentController,
                                      didReceive: message)
    }

    // A message that some other web view sent must never act on the manager's own page.
    func testManagerIgnoresMessagesFromOtherWebViews() throws {
        let opener = try makeManager(configuration: nil)
        let popup = try makeManager(configuration: try popupConfiguration(from: opener))

        try postSelection(to: opener, from: popup.webView)
        XCTAssertNil(opener.webView.currentSelection)
        XCTAssertNil(popup.webView.currentSelection)

        try postSelection(to: opener, from: opener.webView)
        XCTAssertEqual(opener.webView.currentSelection, "")
    }

    private final class FakeSchemeHandler: NSObject, WKScriptMessageHandler, WKURLSchemeHandler {
        var started = 0
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {}
        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            started += 1
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
    }

    private final class FakeSchemeTask: NSObject, WKURLSchemeTask {
        let request = URLRequest(url: URL(string: "iterm2-about:source")!)
        var error: Error?
        func didReceive(_ response: URLResponse) {}
        func didReceive(_ data: Data) {}
        func didFinish() {}
        func didFailWithError(_ error: any Error) {
            self.error = error
        }
    }

    // A browser web view without a manager must not have its pages served by the manager that
    // owns the scheme handler (its opener's), which would answer from its own pages.
    func testSchemeTaskForOrphanedBrowserWebViewFails() {
        let proxy = iTermBrowserWebViewHandlerProxy()
        let openerHandler = FakeSchemeHandler()
        proxy.delegate = openerHandler
        let orphan = iTermBrowserWebView(frame: .zero,
                                         configuration: WKWebViewConfiguration(),
                                         pointerController: PointerController())
        let task = FakeSchemeTask()
        proxy.webView(orphan, start: task)
        XCTAssertEqual(openerHandler.started, 0)
        XCTAssertNotNil(task.error)

        // A plain web view still goes to the delegate.
        let plain = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        proxy.webView(plain, start: FakeSchemeTask())
        XCTAssertEqual(openerHandler.started, 1)
    }

    private func waitForLoad(of url: URL, in webView: WKWebView) {
        let done = expectation(description: "loaded \(url.absoluteString)")
        var fulfilled = false
        let check = { (webView: WKWebView) in
            if !fulfilled && !webView.isLoading && webView.url == url {
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

    // The popup's iterm2-about: pages are served by its own manager, so they still load
    // after the opener's tab is gone.
    func testPopupServesLocalPagesAfterOpenerIsFreed() throws {
        weak var weakOpener: iTermBrowserManager?
        let popup: iTermBrowserManager
        do {
            let opener = try makeManager(configuration: nil)
            weakOpener = opener
            popup = try makeManager(configuration: try popupConfiguration(from: opener))
            managers.removeAll { $0 === opener }
        }
        XCTAssertNil(weakOpener, "The opener's manager should be freed for this test to mean anything")

        popup.showSourceInBrowser(htmlSource: "<p>POPUP_SOURCE_412</p>",
                                  url: try XCTUnwrap(URL(string: "http://example.invalid/page")))
        waitForLoad(of: iTermBrowserSourceHandler.sourceURL, in: popup.webView)
        let shown = try XCTUnwrap(evaluate("document.querySelector('.source-code').textContent",
                                           in: popup.webView))
        XCTAssertTrue(shown.contains("POPUP_SOURCE_412"), shown)
    }
}
