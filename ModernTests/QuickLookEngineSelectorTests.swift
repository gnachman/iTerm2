//
//  QuickLookEngineSelectorTests.swift
//  ModernTests
//
//  Web Quick Look uses the built-in browser’s engine only when the user enabled it and the
//  Browser Plugin is available. The engine defaults are shared with the browser itself.
//

import XCTest
@testable import iTerm2SharedARC

final class QuickLookEngineSelectorTests: XCTestCase {
    func testSelectorMatrix() {
        XCTAssertEqual(iTermQuickLookEngineSelector.engine(settingEnabled: true, pluginAvailable: true), .browser)
        XCTAssertEqual(iTermQuickLookEngineSelector.engine(settingEnabled: true, pluginAvailable: false), .legacy)
        XCTAssertEqual(iTermQuickLookEngineSelector.engine(settingEnabled: false, pluginAvailable: true), .legacy)
        XCTAssertEqual(iTermQuickLookEngineSelector.engine(settingEnabled: false, pluginAvailable: false), .legacy)
    }

    func testSafariUserAgentContainsSafari() {
        let ua = iTermBrowserEngineDefaults.safariUserAgent()
        XCTAssertTrue(ua.contains("Safari/605.1.15"), ua)
        XCTAssertFalse(ua.contains("iTerm2"), ua)
    }

    func testRegularStoreIDIsStable() {
        XCTAssertEqual(iTermBrowserEngineDefaults.regularUserStoreID,
                       UUID(uuidString: "AC0E9812-7F88-478B-B361-5526082EDDB3")!)
    }
}
