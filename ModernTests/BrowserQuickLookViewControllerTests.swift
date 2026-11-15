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

    func testOwnsItsPopupWindows() throws {
        let child = try XCTUnwrap(requestPopup(navigationType: .other))
        XCTAssertTrue(controller.owns(window: child.window))
        XCTAssertFalse(controller.owns(window: NSWindow()))
        XCTAssertFalse(controller.owns(window: nil))
    }
}
