//
//  PTYTabContainerTests.swift
//  ModernTests
//
//  Every tab has a container view between the tab view item and the root split view, so that
//  floating panes can be siblings of the root. These tests use a real terminal window.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYTabContainerTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try OnscreenTestGate.skipUnlessEnabled()
        fixture = TerminalWindowTestFixture()
    }

    override func tearDown() {
        fixture?.close()
        fixture = nil
        super.tearDown()
    }

    private var tab: PTYTab {
        guard let tab = fixture.terminal.currentTab() else {
            it_fatalError("No tab")
        }
        return tab
    }

    private func assertRootFillsContainer(file: StaticString = #filePath, line: UInt = #line) {
        guard let container = tab.realRootView, let root = tab.rootView else {
            XCTFail("Missing views", file: file, line: line)
            return
        }
        XCTAssertTrue(root.superview === container, "the root is in the container", file: file, line: line)
        XCTAssertEqual(root.frame, container.bounds, "the root fills the container", file: file, line: line)
    }

    func testTabViewItemViewIsTheContainer() {
        let container = tab.realRootView
        XCTAssertNotNil(container)
        XCTAssertTrue(tab.tabViewItem?.view === container)
        XCTAssertFalse(container === tab.rootView, "the container is not the root")
        assertRootFillsContainer()
    }

    func testContainerFillsTheTabView() {
        guard let container = tab.realRootView, let tabView = container.superview else {
            XCTFail("The container is not installed")
            return
        }
        XCTAssertEqual(container.frame.size, tabView.bounds.size)
    }

    func testRootFillsContainerAfterWindowResize() {
        var frame = fixture.window.frame
        frame.size.width += 120
        frame.size.height += 60
        fixture.window.setFrame(frame, display: true)
        assertRootFillsContainer()

        frame.size.width -= 200
        frame.size.height -= 100
        fixture.window.setFrame(frame, display: true)
        assertRootFillsContainer()
    }

    func testRootFillsContainerAfterSplit() {
        guard let first = fixture.terminal.currentSession() else {
            XCTFail("No session")
            return
        }
        fixture.split(first, vertically: true)
        assertRootFillsContainer()
    }

    func testMaximizeReplacesOnlyTheRoot() {
        guard let first = fixture.terminal.currentSession(), let container = tab.realRootView else {
            XCTFail("No session")
            return
        }
        fixture.split(first, vertically: true)
        let sibling = NSView(frame: NSRect(x: 10, y: 10, width: 50, height: 50))
        container.addSubview(sibling)

        let rootBefore = tab.rootView
        tab.maximize()
        XCTAssertTrue(tab.isMaximized)
        XCTAssertFalse(tab.rootView === rootBefore, "maximize installs a new root")
        XCTAssertTrue(sibling.superview === container, "maximize must not remove the container's other views")
        XCTAssertTrue(container.subviews.first === tab.rootView, "the root stays below the container's other views")
        assertRootFillsContainer()

        tab.perform(NSSelectorFromString("unmaximize"))
        XCTAssertFalse(tab.isMaximized)
        XCTAssertTrue(sibling.superview === container, "unmaximize must not remove the container's other views")
        XCTAssertTrue(container.subviews.first === tab.rootView)
        XCTAssertEqual(tab.sessions()?.count, 2)
        assertRootFillsContainer()
    }
}
