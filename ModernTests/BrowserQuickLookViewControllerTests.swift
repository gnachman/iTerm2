//
//  BrowserQuickLookViewControllerTests.swift
//  ModernTests
//
//  Web Quick Look on the browser engine must share the built-in browser’s login store and user
//  agent, and must service script-opened popups so OAuth sign-in can complete.
//

import XCTest
import WebKit
@testable import iTerm2SharedARC

final class BrowserQuickLookViewControllerTests: XCTestCase {
    // WebKit objects created with plain init() must outlive the test, as in BrowserViewSourceTests.
    private static var fakesKeptAlive = [NSObject]()

    private final class FakeNavigationAction: WKNavigationAction {
        private let fakeRequest: URLRequest
        private let fakeNavigationType: WKNavigationType
        init(url: URL, navigationType: WKNavigationType) {
            fakeRequest = URLRequest(url: url)
            fakeNavigationType = navigationType
            super.init()
        }
        override var request: URLRequest { fakeRequest }
        override var targetFrame: WKFrameInfo? { nil }
        override var navigationType: WKNavigationType { fakeNavigationType }
        override var modifierFlags: NSEvent.ModifierFlags { [] }
    }

    private let url = URL(string: "https://example.invalid/page")!
    private var controller: iTermBrowserQuickLookViewController!

    override func setUp() {
        super.setUp()
        controller = iTermBrowserQuickLookViewController(url: url)
    }

    override func tearDown() {
        controller.tearDown()
        controller = nil
        super.tearDown()
    }

    private func requestPopup(navigationType: WKNavigationType) -> WKWebView? {
        let action = FakeNavigationAction(url: URL(string: "https://accounts.example.invalid/signin")!,
                                          navigationType: navigationType)
        let features = WKWindowFeatures()
        Self.fakesKeptAlive.append(action)
        Self.fakesKeptAlive.append(features)
        return controller.webView(controller.webView,
                                  createWebViewWith: controller.webView.configuration,
                                  for: action,
                                  windowFeatures: features)
    }

    func testUsesSharedStoreAndSafariUA() {
        if #available(macOS 14, *) {
            XCTAssertEqual(controller.webView.configuration.websiteDataStore.identifier,
                           iTermBrowserEngineDefaults.regularUserStoreID)
        }
        XCTAssertTrue(controller.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(controller.webView.customUserAgent, iTermBrowserEngineDefaults.safariUserAgent())
        XCTAssertTrue(controller.webView.uiDelegate === controller)
    }

    func testPopupCreatesChildWebView() throws {
        let child = try XCTUnwrap(requestPopup(navigationType: .other))
        XCTAssertFalse(child === controller.webView)
        if #available(macOS 14, *) {
            XCTAssertEqual(child.configuration.websiteDataStore.identifier,
                           iTermBrowserEngineDefaults.regularUserStoreID)
        }
        XCTAssertEqual(child.customUserAgent, iTermBrowserEngineDefaults.safariUserAgent())
        XCTAssertTrue(child.uiDelegate === controller)
        XCTAssertEqual(controller.popupWebViews.count, 1)
        XCTAssertNotNil(child.window)
        XCTAssertTrue(child.window?.isVisible ?? false)
    }

    func testPopupClosesWhenPageClosesIt() throws {
        let child = try XCTUnwrap(requestPopup(navigationType: .other))
        controller.webViewDidClose(child)
        XCTAssertTrue(controller.popupWebViews.isEmpty)
        XCTAssertFalse(child.window?.isVisible ?? false)
    }

    func testBlankLinkLoadsInPlace() {
        XCTAssertNil(requestPopup(navigationType: .linkActivated))
        XCTAssertTrue(controller.popupWebViews.isEmpty)
    }

    func testTearDownClosesChildren() throws {
        let first = try XCTUnwrap(requestPopup(navigationType: .other))
        let second = try XCTUnwrap(requestPopup(navigationType: .other))
        XCTAssertEqual(controller.popupWebViews.count, 2)

        controller.tearDown()

        XCTAssertTrue(controller.popupWebViews.isEmpty)
        XCTAssertFalse(first.window?.isVisible ?? false)
        XCTAssertFalse(second.window?.isVisible ?? false)
    }

    // Only the suppressed path is exercised: the other one runs an app-modal dialog.
    func testHoverPreviewAnswersDialogsSilentlyUntilClicked() {
        controller.suppressesJavaScriptDialogsUntilClicked = true
        XCTAssertTrue(controller.suppressesJavaScriptDialogs)
        let frame = WKFrameInfo()
        Self.fakesKeptAlive.append(frame)

        var alertCompleted = false
        controller.webView(controller.webView,
                           runJavaScriptAlertPanelWithMessage: "hi",
                           initiatedByFrame: frame) {
            alertCompleted = true
        }
        XCTAssertTrue(alertCompleted, "the alert completes at once, without a dialog")

        var confirmResult: Bool?
        controller.webView(controller.webView,
                           runJavaScriptConfirmPanelWithMessage: "sure?",
                           initiatedByFrame: frame) { result in
            confirmResult = result
        }
        XCTAssertEqual(confirmResult, false, "the confirm is declined at once, without a dialog")

        var interacted = false
        controller.onUserInteraction = {
            interacted = true
        }
        controller.userDidClick()
        XCTAssertTrue(interacted)
        XCTAssertFalse(controller.suppressesJavaScriptDialogs, "after a click, dialogs show as usual")
    }

    func testDeliberatePreviewDoesNotSuppressDialogs() {
        XCTAssertFalse(controller.suppressesJavaScriptDialogs)
    }

    func testOwnsItsPopupWindows() throws {
        let child = try XCTUnwrap(requestPopup(navigationType: .other))
        XCTAssertTrue(controller.owns(window: child.window))
        XCTAssertFalse(controller.owns(window: NSWindow()))
        XCTAssertFalse(controller.owns(window: nil))
    }
}
