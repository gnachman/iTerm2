//
//  WebQuickLookCoordinatorWindowTests.swift
//  ModernTests
//
//  A hover open fires on a timer. By then the text view may have left its window (a key equivalent
//  switched tabs, the session ended) without any event reaching it. NSPopover raises for a
//  positioning view with no window, so the coordinator must refuse, and a view leaving its window
//  must drop its pending hover and its popover.
//

import XCTest
@testable import iTerm2SharedARC

final class WebQuickLookCoordinatorWindowTests: XCTestCase {
    private var host: FakeWebQuickLookHost!
    private var view: NSView!
    private var coordinator: iTermWebQuickLookCoordinator!
    private let url = URL(string: "https://example.com/")!

    override func setUp() {
        super.setUp()
        host = FakeWebQuickLookHost()
        view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        coordinator = iTermWebQuickLookCoordinator(view: view, host: host)
    }

    override func tearDown() {
        coordinator.popover = nil
        coordinator.tearDown()
        coordinator = nil
        view = nil
        host = nil
        super.tearDown()
    }

    private func offscreenWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    func testHoverOpenIsRefusedForAViewWithNoWindow() {
        XCTAssertNil(view.window)
        XCTAssertFalse(coordinator.hoverControllerOpenPreview(url: url, linkRects: [], at: NSPoint(x: 10, y: 10)))
        XCTAssertNil(coordinator.popover)
    }

    // The timer was started while the window was key; it may not be any more.
    func testHoverOpenIsRefusedWhenTheWindowIsNotActive() {
        let window = offscreenWindow()
        window.contentView = view
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(coordinator.hoverControllerOpenPreview(url: url, linkRects: [], at: NSPoint(x: 10, y: 10)))
        XCTAssertNil(coordinator.popover)
    }

    func testForcePressOpenIsRefusedForAViewWithNoWindow() {
        coordinator.show(url: url, atPointInWindow: NSPoint(x: 10, y: 10), openedByHover: false)
        XCTAssertNil(coordinator.popover)
    }

    func testLeavingTheWindowClosesThePopover() {
        let window = offscreenWindow()
        window.contentView = view
        coordinator.popover = NSPopover()
        coordinator.popoverOpenedByHover = true
        coordinator.viewWillMove(toWindow: nil)
        XCTAssertNil(coordinator.popover)
    }

    func testStayingInTheSameWindowKeepsThePopover() {
        let window = offscreenWindow()
        window.contentView = view
        let popover = NSPopover()
        coordinator.popover = popover
        coordinator.viewWillMove(toWindow: window)
        XCTAssertTrue(coordinator.popover === popover)
    }
}
