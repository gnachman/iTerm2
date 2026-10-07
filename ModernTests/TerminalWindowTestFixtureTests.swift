//
//  TerminalWindowTestFixtureTests.swift
//  ModernTests
//
//  Checks that the window fixture and the mouse event synthesizer behave like the real thing, so
//  later tests built on them can be trusted.
//

import XCTest
@testable import iTerm2SharedARC

private final class MouseRecordingView: NSView {
    struct Record: Equatable {
        var type: NSEvent.EventType
        var location: NSPoint
        var modifiers: NSEvent.ModifierFlags
        var clickCount: Int

        static func == (lhs: Record, rhs: Record) -> Bool {
            return lhs.type == rhs.type &&
                lhs.location == rhs.location &&
                lhs.modifiers == rhs.modifiers &&
                lhs.clickCount == rhs.clickCount
        }
    }
    var records = [Record]()

    private func record(_ event: NSEvent) {
        records.append(Record(type: event.type,
                              location: convert(event.locationInWindow, from: nil),
                              modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
                              clickCount: event.clickCount))
    }

    override func mouseDown(with event: NSEvent) { record(event) }
    override func mouseDragged(with event: NSEvent) { record(event) }
    override func mouseUp(with event: NSEvent) { record(event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class TerminalWindowTestFixtureTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
    }

    override func tearDown() {
        fixture.close()
        fixture = nil
        super.tearDown()
    }

    func testOpensWindowWithOneSession() {
        let sessions = fixture.terminal.allSessions() ?? []
        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions.first?.view?.window === fixture.window)
    }

    func testSplitAddsSecondPaneToTheSameTab() {
        guard let first = fixture.terminal.currentSession() else {
            XCTFail("No session")
            return
        }
        let second = fixture.split(first, vertically: true)
        let tab = fixture.terminal.currentTab()
        XCTAssertEqual(tab?.sessions()?.count, 2)
        XCTAssertTrue(second.view?.window === fixture.window)
        guard let firstFrame = first.view?.frame, let secondFrame = second.view?.frame else {
            XCTFail("Missing views")
            return
        }
        XCTAssertFalse(firstFrame.intersects(secondFrame), "split panes must tile")
    }

    func testClickingAPaneMakesItActive() {
        guard let first = fixture.terminal.currentSession() else {
            XCTFail("No session")
            return
        }
        let second = fixture.split(first, vertically: true)
        let tab = fixture.terminal.currentTab()
        tab?.setActiveSession(second)
        XCTAssertTrue(tab?.activeSession === second)

        guard let textView = first.textview else {
            XCTFail("No text view")
            return
        }
        fixture.mouse.click(at: fixture.center(of: textView))
        XCTAssertTrue(tab?.activeSession === first, "a click in a pane must make it the active session")
    }

    func testDragIsRoutedToTheViewThatTookTheMouseDown() {
        guard let contentView = fixture.window.contentView else {
            XCTFail("No content view")
            return
        }
        let recorder = MouseRecordingView(frame: NSRect(x: 20, y: 20, width: 100, height: 100))
        contentView.addSubview(recorder)
        defer { recorder.removeFromSuperview() }

        let start = recorder.convert(NSPoint(x: 50, y: 50), to: nil)
        // The drag ends outside the view; AppKit must still deliver it to the view that took the
        // mouse-down.
        let end = recorder.convert(NSPoint(x: 250, y: 50), to: nil)
        fixture.mouse.drag(from: start, to: end, steps: 4, modifiers: [.control])

        XCTAssertEqual(recorder.records.map(\.type),
                       [.leftMouseDown, .leftMouseDragged, .leftMouseDragged, .leftMouseDragged,
                        .leftMouseDragged, .leftMouseUp])
        XCTAssertEqual(recorder.records.first?.location, NSPoint(x: 50, y: 50))
        XCTAssertEqual(recorder.records.last?.location, NSPoint(x: 250, y: 50))
        XCTAssertEqual(recorder.records.map(\.location.x), [50, 100, 150, 200, 250, 250])
        XCTAssertTrue(recorder.records.allSatisfy { $0.modifiers == [.control] })
    }

    func testDoubleClickCarriesClickCount() {
        guard let contentView = fixture.window.contentView else {
            XCTFail("No content view")
            return
        }
        let recorder = MouseRecordingView(frame: NSRect(x: 20, y: 20, width: 100, height: 100))
        contentView.addSubview(recorder)
        defer { recorder.removeFromSuperview() }

        fixture.mouse.doubleClick(at: recorder.convert(NSPoint(x: 10, y: 10), to: nil))
        XCTAssertEqual(recorder.records.map(\.clickCount), [1, 1, 2, 2])
    }
}
