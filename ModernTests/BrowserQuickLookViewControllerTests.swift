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

    private static let signInURL = "https://accounts.example.invalid/signin"
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

    private func requestPopup(navigationType: WKNavigationType,
                              url popupURL: String) throws -> WKWebView? {
        let action = FakeNavigationAction(url: try XCTUnwrap(URL(string: popupURL)),
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
        let child = try XCTUnwrap(try requestPopup(navigationType: .other, url: Self.signInURL))
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
        let child = try XCTUnwrap(try requestPopup(navigationType: .other, url: Self.signInURL))
        controller.webViewDidClose(child)
        XCTAssertTrue(controller.popupWebViews.isEmpty)
        XCTAssertFalse(child.window?.isVisible ?? false)
    }

    func testBlankLinkLoadsInPlace() throws {
        XCTAssertNil(try requestPopup(navigationType: .linkActivated, url: Self.signInURL))
        XCTAssertTrue(controller.popupWebViews.isEmpty)
    }

    func testTearDownClosesChildren() throws {
        let first = try XCTUnwrap(try requestPopup(navigationType: .other, url: Self.signInURL))
        let second = try XCTUnwrap(try requestPopup(navigationType: .other, url: Self.signInURL))
        XCTAssertEqual(controller.popupWebViews.count, 2)

        controller.tearDown()

        XCTAssertTrue(controller.popupWebViews.isEmpty)
        XCTAssertFalse(first.window?.isVisible ?? false)
        XCTAssertFalse(second.window?.isVisible ?? false)
    }

    // Only the suppressed path is exercised: the other one runs an app-modal dialog.
    func testHoverPreviewAnswersDialogsSilentlyUntilClicked() {
        controller.suppressesInterruptionsUntilClicked = true
        XCTAssertTrue(controller.suppressesInterruptions)
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
        XCTAssertFalse(controller.suppressesInterruptions, "after a click, dialogs show as usual")
    }

    func testDeliberatePreviewDoesNotSuppressDialogs() {
        XCTAssertFalse(controller.suppressesInterruptions)
    }

    func testOwnsItsPopupWindows() throws {
        let child = try XCTUnwrap(try requestPopup(navigationType: .other, url: Self.signInURL))
        XCTAssertTrue(controller.owns(window: child.window))
        XCTAssertFalse(controller.owns(window: NSWindow()))
        XCTAssertFalse(controller.owns(window: nil))
    }

    func testHoverPreviewRefusesPopupsUntilClicked() throws {
        controller.suppressesInterruptionsUntilClicked = true
        XCTAssertNil(try requestPopup(navigationType: .other, url: Self.signInURL), "no window before the user clicks in")
        XCTAssertTrue(controller.popupWebViews.isEmpty)

        controller.userDidClick()

        XCTAssertNotNil(try requestPopup(navigationType: .other, url: Self.signInURL), "sign-in pop-ups work after a click")
        XCTAssertEqual(controller.popupWebViews.count, 1)
    }

    func testBlankLinkToNonWebAddressIsDropped() throws {
        XCTAssertNil(try requestPopup(navigationType: .linkActivated, url: "file:///etc/passwd"))
        XCTAssertTrue(controller.popupWebViews.isEmpty)
        XCTAssertNil(controller.webView.url, "the preview did not navigate to it")
    }

    private func policy(for string: String) throws -> WKNavigationActionPolicy {
        let action = FakeNavigationAction(url: try XCTUnwrap(URL(string: string)), navigationType: .other)
        Self.fakesKeptAlive.append(action)
        return iTermBrowserQuickLookViewController.policy(for: action)
    }

    func testMainFrameNavigationAllowsOnlyWebAddresses() throws {
        XCTAssertEqual(try policy(for: "https://example.invalid/"), .allow)
        XCTAssertEqual(try policy(for: "HTTP://example.invalid/"), .allow)
        XCTAssertEqual(try policy(for: "about:blank"), .allow, "tearDown unloads the page with about:blank")
        XCTAssertEqual(try policy(for: "file:///etc/passwd"), .cancel)
        XCTAssertEqual(try policy(for: "zoommtg://zoom.us/join"), .cancel)
        XCTAssertEqual(try policy(for: "data:text/html,hi"), .cancel)
    }

    func testOnlyWebAddressesAreHandedOn() throws {
        let initial = try XCTUnwrap(URL(string: "https://example.invalid/start"))
        let moved = try XCTUnwrap(URL(string: "https://example.invalid/next"))
        XCTAssertEqual(iTermBrowserQuickLookViewController.urlToHandOn(current: moved, initial: initial), moved)
        XCTAssertEqual(iTermBrowserQuickLookViewController.urlToHandOn(current: nil, initial: initial), initial)
        XCTAssertEqual(iTermBrowserQuickLookViewController.urlToHandOn(current: URL(string: "about:blank"), initial: initial), initial)
        XCTAssertEqual(iTermBrowserQuickLookViewController.urlToHandOn(current: URL(string: "file:///etc/passwd"), initial: initial), initial)
    }
}
