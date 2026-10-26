//
//  BrowserContextMenuMonitorTests.swift
//  iTerm2
//

import AppKit
import WebKit
import XCTest
@testable import iTerm2SharedARC

// QA finding F-412: a browser tab opened by a target=_blank link showed no context menu. Its web
// view shares the opener's configuration, so the context menu script's messages reach the opener's
// iTermBrowserManager, which opened the menu in the opener's web view (in a hidden tab) instead of
// the one that was right-clicked.
@MainActor
final class BrowserContextMenuMonitorTests: XCTestCase {
    private final class FakeScriptMessage: WKScriptMessage {
        private let fakeBody: Any
        private weak var fakeWebView: WKWebView?

        init(body: Any, webView: WKWebView) {
            fakeBody = body
            fakeWebView = webView
            super.init()
        }

        override var body: Any { fakeBody }
        override var webView: WKWebView? { fakeWebView }
        override var name: String { iTermBrowserContextMenuMonitor.messageHandlerName }
    }

    private func makeWebView(configuration: WKWebViewConfiguration) -> iTermBrowserWebView {
        return iTermBrowserWebView(frame: NSRect(x: 0, y: 0, width: 200, height: 200),
                                   configuration: configuration,
                                   pointerController: PointerController())
    }

    private func secret(of monitor: iTermBrowserContextMenuMonitor) throws -> String {
        let regex = try NSRegularExpression(pattern: #"sessionSecret: "([0-9a-fA-F]+)""#)
        let js = monitor.javascript
        let match = try XCTUnwrap(regex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)))
        return try XCTUnwrap(Range(match.range(at: 1), in: js).map { String(js[$0]) })
    }

    // The selections are empty so that “copy on select” doesn't touch the pasteboard.
    func testMessageFromPopupGoesToPopupWebView() throws {
        let monitor = try XCTUnwrap(iTermBrowserContextMenuMonitor())
        let configuration = WKWebViewConfiguration()
        let opener = makeWebView(configuration: configuration)
        let popup = makeWebView(configuration: configuration)
        let message = FakeScriptMessage(body: ["x": NSNumber(value: 10),
                                               "y": NSNumber(value: 20),
                                               "sessionSecret": try secret(of: monitor),
                                               "selection": ""],
                                        webView: popup)
        monitor.handleMessage(message)
        XCTAssertEqual(popup.currentSelection, "")
        XCTAssertNil(opener.currentSelection)
    }

    func testMessageWithWrongSecretIsIgnored() throws {
        let monitor = try XCTUnwrap(iTermBrowserContextMenuMonitor())
        let popup = makeWebView(configuration: WKWebViewConfiguration())
        let message = FakeScriptMessage(body: ["x": NSNumber(value: 10),
                                               "y": NSNumber(value: 20),
                                               "sessionSecret": "wrong",
                                               "selection": ""],
                                        webView: popup)
        monitor.handleMessage(message)
        XCTAssertNil(popup.currentSelection)
    }
}
