//
//  FloatingPaneAPITests.swift
//  ModernTests
//
//  What the Python API sees of floats: their own list in ListSessions, and minimized sessions that
//  are only the tiled panes maximizing hid.
//

import XCTest
@testable import iTerm2SharedARC

final class FloatingPaneAPITests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private let floatFrame = NSRect(x: 60, y: 60, width: 300, height: 200)

    override func setUpWithError() throws {
        try super.setUpWithError()
        try OnscreenTestGate.skipUnlessEnabled()
        fixture = TerminalWindowTestFixture()
        var frame = fixture.window.frame
        frame.size = NSSize(width: 900, height: 650)
        fixture.window.setFrame(frame, display: true)
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

    private func leafGUIDs(_ node: ITMSplitTreeNode) -> [String] {
        var result = [String]()
        for case let link as ITMSplitTreeNode_SplitTreeLink in node.linksArray {
            if link.childOneOfCase == .session {
                result.append(link.session.uniqueIdentifier)
            } else {
                result.append(contentsOf: leafGUIDs(link.node))
            }
        }
        return result
    }

    func testFloatsAreListedBackToFrontAndNotInTheTree() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let back = fixture.addFloat(frame: floatFrame)
        let front = fixture.addFloat(frame: floatFrame.offsetBy(dx: 40, dy: 40))

        XCTAssertEqual(leafGUIDs(tab.rootSplitTreeNode()), [tiled.guid])
        let messages = tab.floatingPaneMessages() ?? []
        XCTAssertEqual(messages.map { $0.session.uniqueIdentifier }, [back.guid, front.guid])

        guard let message = messages.first, let pane = tab.floatingPane(for: back) else {
            XCTFail("No message")
            return
        }
        let visual = FloatingPaneLayout.visualOutlineFrame(of: pane)
        XCTAssertEqual(message.session.frame.origin.x, Int32(visual.origin.x))
        XCTAssertEqual(message.session.frame.origin.y, Int32(visual.origin.y), "y is down from the tab's top")
        XCTAssertEqual(message.session.frame.size.width, Int32(visual.size.width))
        XCTAssertEqual(message.session.gridSize.width, back.columns)
        XCTAssertEqual(message.session.gridSize.height, back.rows)
    }

    func testMinimizedSessionsAreOnlyTheHiddenTiledPanes() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let second = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(second)
        tab.maximize()
        XCTAssertEqual(tab.minimizedSessions, [tiled])

        // Activating the float leaves the maximized pane showing.
        tab.setActiveSession(float)
        XCTAssertEqual(tab.minimizedSessions, [tiled], "the maximized pane is not minimized")
        tab.perform(NSSelectorFromString("unmaximize"))
    }

    func testFloatsCannotBeLayoutLeaves() {
        let float = fixture.addFloat(frame: floatFrame)
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let environment = iTermLayoutEnvironment()
        XCTAssertTrue(environment.sessionIsFloating(float.guid))
        XCTAssertFalse(environment.sessionIsFloating(tiled.guid))
        XCTAssertEqual(environment.sessionGUIDs(inTab: "\(tab.uniqueId)"), [tiled.guid])
    }
}
