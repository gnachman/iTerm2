//
//  FloatingPaneBuiltInFunctionTests.swift
//  ModernTests
//
//  The built-in functions behind the Python API's floating pane methods.
//

import XCTest
@testable import iTerm2SharedARC

final class FloatingPaneBuiltInFunctionTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private let floatFrame = NSRect(x: 60, y: 60, width: 300, height: 200)

    override func setUpWithError() throws {
        try super.setUpWithError()
        try OnscreenTestGate.skipUnlessEnabled()
        fixture = TerminalWindowTestFixture()
        var frame = fixture.window.frame
        frame.size = NSSize(width: 900, height: 650)
        fixture.window.setFrame(frame, display: true)
        if !iTermBuiltInFunctions.sharedInstance().haveFunction(withName: "raise_floating_pane",
                                                                 namespace: "iterm2",
                                                                 arguments: ["session"]) {
            FloatingPaneBuiltInFunctions.registerBuiltInFunctions()
        }
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

    /// Calls iterm2.<name> and waits for its result.
    @discardableResult
    private func call(_ name: String, _ parameters: [String: Any]) -> (Any?, Error?) {
        let done = expectation(description: name)
        var result: (Any?, Error?) = (nil, nil)
        iTermBuiltInFunctions.sharedInstance().callFunction(withName: name,
                                                            namespace: "iterm2",
                                                            parameters: parameters,
                                                            scope: iTermVariableScope(),
                                                            sideEffectsAllowed: true) { value, error in
            result = (value, error)
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        return result
    }

    func testRaiseAndLower() {
        let back = fixture.addFloat(frame: floatFrame)
        let front = fixture.addFloat(frame: floatFrame.offsetBy(dx: 40, dy: 40))

        XCTAssertNil(call("raise_floating_pane", ["session": back.guid]).1)
        XCTAssertEqual(tab.floatingSessions(), [front, back])
        XCTAssertNil(call("raise_floating_pane", ["session": back.guid, "to_front": false]).1)
        XCTAssertEqual(tab.floatingSessions(), [back, front])
    }

    func testSetFrameUsesVisualCoordinatesAndWholeCells() {
        let float = fixture.addFloat(frame: floatFrame)
        guard let pane = tab.floatingPane(for: float),
              let metrics = FloatingPaneLayout.metrics(for: float) else {
            XCTFail("No pane")
            return
        }
        XCTAssertNil(call("set_floating_pane_frame", ["session": float.guid,
                                                      "x": 30, "y": 40,
                                                      "width": 400, "height": 250]).1)
        let visual = FloatingPaneLayout.visualOutlineFrame(of: pane)
        XCTAssertEqual(visual.origin, NSPoint(x: 30, y: 40), "y is down from the tab's top")
        XCTAssertLessThanOrEqual(visual.width, 400)
        XCTAssertGreaterThan(visual.width + metrics.cellSize.width, 400, "within a cell of the request")
        XCTAssertLessThanOrEqual(visual.height, 250)
        XCTAssertGreaterThan(visual.height + metrics.cellSize.height, 250)
    }

    func testDock() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let float = fixture.addFloat(frame: floatFrame)
        XCTAssertNil(call("dock_floating_pane", ["session": float.guid]).1)
        XCTAssertEqual(tab.tiledSessions(), [tiled, float])
        XCTAssertTrue(tab.floatingSessions()?.isEmpty ?? false)
    }

    func testFunctionsRefuseATiledSession() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        XCTAssertNotNil(call("dock_floating_pane", ["session": tiled.guid]).1)
        XCTAssertNotNil(call("raise_floating_pane", ["session": tiled.guid]).1)
        XCTAssertNotNil(call("set_floating_pane_frame", ["session": tiled.guid,
                                                         "x": 0, "y": 0, "width": 100, "height": 100]).1)
    }

    func testCreate() {
        let (value, error) = call("create_floating_pane", ["tab_id": "\(tab.uniqueId)"])
        XCTAssertNil(error)
        guard let guid = value as? String else {
            XCTFail("No session ID")
            return
        }
        XCTAssertEqual(tab.floatingSessions()?.map { $0.guid }, [guid])
    }

    func testCreateIsRefusedWhenTheLayoutIsLocked() {
        fixture.terminal.perform(NSSelectorFromString("toggleLayoutLocked:"), with: nil)
        defer {
            fixture.terminal.perform(NSSelectorFromString("toggleLayoutLocked:"), with: nil)
        }
        XCTAssertNotNil(call("create_floating_pane", ["tab_id": "\(tab.uniqueId)"]).1)
        XCTAssertTrue(tab.floatingSessions()?.isEmpty ?? false)
    }
}
