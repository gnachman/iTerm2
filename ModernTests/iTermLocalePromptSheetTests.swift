//
//  iTermLocalePromptSheetTests.swift
//  iTerm2 ModernTests
//
//  The “no valid UNIX locale” prompt must not be shown as a sheet on a window
//  the user can’t see. A dedicated hotkey window is ordered in with an alpha of
//  0 while its first session launches; a sheet on it was invisible and blocked
//  the hotkey window from appearing (QA finding F-306).
//

import XCTest
@testable import iTerm2SharedARC

final class iTermLocalePromptSheetTests: XCTestCase {

    // MARK: - Decision logic

    func test_visibleOpaqueWindowUsesSheet() {
        XCTAssertTrue(iTermLocalePrompt.shouldPresentAsSheet(isVisible: true,
                                                             alphaValue: 1,
                                                             isMiniaturized: false))
    }

    func test_partiallyTransparentWindowUsesSheet() {
        // A window mid-fade or with transparency is still visible to the user.
        XCTAssertTrue(iTermLocalePrompt.shouldPresentAsSheet(isVisible: true,
                                                             alphaValue: 0.5,
                                                             isMiniaturized: false))
    }

    func test_orderedInButFullyTransparentWindowDoesNotUseSheet() {
        // This is the hotkey window before it rolls in.
        XCTAssertFalse(iTermLocalePrompt.shouldPresentAsSheet(isVisible: true,
                                                              alphaValue: 0,
                                                              isMiniaturized: false))
    }

    func test_orderedOutWindowDoesNotUseSheet() {
        XCTAssertFalse(iTermLocalePrompt.shouldPresentAsSheet(isVisible: false,
                                                              alphaValue: 1,
                                                              isMiniaturized: false))
    }

    func test_miniaturizedWindowDoesNotUseSheet() {
        XCTAssertFalse(iTermLocalePrompt.shouldPresentAsSheet(isVisible: true,
                                                              alphaValue: 1,
                                                              isMiniaturized: true))
    }

    // MARK: - Window wrapper

    func test_nilWindowHasNoSheetParent() {
        XCTAssertNil(iTermLocalePrompt.sheetParent(for: nil))
    }

    func test_neverOrderedInWindowHasNoSheetParent() {
        let window = makeWindow()
        defer { window.close() }
        XCTAssertFalse(window.isVisible)
        XCTAssertNil(iTermLocalePrompt.sheetParent(for: window))
    }

    func test_visibleButTransparentWindowHasNoSheetParent() {
        // The hotkey window before roll-in: ordered in (visible) with alpha 0.
        let window = makeWindow(pretendVisible: true)
        defer { window.close() }
        window.alphaValue = 0
        XCTAssertNil(iTermLocalePrompt.sheetParent(for: window))
    }

    func test_visibleOpaqueWindowIsSheetParent() {
        let window = makeWindow(pretendVisible: true)
        defer { window.close() }
        window.alphaValue = 1
        XCTAssertTrue(iTermLocalePrompt.sheetParent(for: window) === window)
    }

    // MARK: - Alert presentation path

    func test_alertOnTransparentWindowIsAppModal() {
        let window = makeWindow(pretendVisible: true)
        defer { window.close() }
        window.alphaValue = 0
        XCTAssertNil(presentationParent(window: window))
    }

    func test_alertOnVisibleOpaqueWindowIsSheet() {
        let window = makeWindow(pretendVisible: true)
        defer { window.close() }
        window.alphaValue = 1
        XCTAssertTrue(presentationParent(window: window) === window)
    }

    func test_alertWithNoWindowIsAppModal() {
        XCTAssertNil(presentationParent(window: nil))
    }

    // Runs the locale alert with a fake presenter and returns the sheet parent it was asked to
    // use (nil means app-modal).
    private func presentationParent(window: NSWindow?) -> NSWindow? {
        let alert = iTermLocalePromptAlert(languages: ["en-US"],
                                           profileName: nil,
                                           encoding: .utf8)
        var calls = 0
        var parent: NSWindow?
        alert.presenter = { _, sheetParent in
            calls += 1
            parent = sheetParent
            return .alertSecondButtonReturn
        }
        _ = alert.run(window: window, cancelUsesC: true)
        XCTAssertEqual(calls, 1)
        return parent
    }

    func test_orderedInTransparentWindowHasNoSheetParent() throws {
        try OnscreenTestGate.skipUnlessEnabled()
        let window = makeWindow()
        window.alphaValue = 0
        window.orderFront(nil)
        defer { window.close() }
        XCTAssertTrue(window.isVisible)
        XCTAssertNil(iTermLocalePrompt.sheetParent(for: window))
    }

    func test_orderedInOpaqueWindowIsSheetParent() throws {
        try OnscreenTestGate.skipUnlessEnabled()
        let window = makeWindow()
        window.alphaValue = 1
        window.orderFront(nil)
        defer { window.close() }
        XCTAssertTrue(iTermLocalePrompt.sheetParent(for: window) === window)
    }

    private func makeWindow(pretendVisible: Bool = false) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: 100, height: 100)
        let window: NSWindow
        if pretendVisible {
            window = PretendVisibleWindow(contentRect: rect,
                                          styleMask: [.titled],
                                          backing: .buffered,
                                          defer: true)
        } else {
            window = NSWindow(contentRect: rect,
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: false)
        }
        window.isReleasedWhenClosed = false
        return window
    }
}

// Reports itself as ordered in without putting anything on screen.
private final class PretendVisibleWindow: NSWindow {
    override var isVisible: Bool { true }
}
