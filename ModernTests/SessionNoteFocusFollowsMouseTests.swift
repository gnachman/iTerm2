//
//  SessionNoteFocusFollowsMouseTests.swift
//  ModernTests
//
//  A session note that takes focus while the pointer is elsewhere must keep focus against
//  focus-follows-mouse until the pointer enters it. Otherwise crossing another pane steals focus
//  and an empty note closes.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

private final class HoldingView: NSView {
    var holds = true
    override func it_focusFollowsMouseHoldsFocus() -> Bool {
        return holds
    }
}

@MainActor
final class SessionNoteFocusFollowsMouseTests: XCTestCase {
    private var window: NSWindow!
    private var note: SessionNoteView!

    override func setUp() {
        super.setUp()
        // Place the window far outside any screen so the real pointer is never inside the note.
        window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 300),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.isReleasedWhenClosed = false
        note = SessionNoteView(frame: NSRect(x: 10, y: 10, width: 200, height: 150),
                               model: SessionNoteModel())
        window.contentView?.addSubview(note)
    }

    override func tearDown() {
        note.removeFromSuperview()
        window.close()
        note = nil
        window = nil
        super.tearDown()
    }

    private func enterEvent() -> NSEvent {
        return NSEvent.enterExitEvent(with: .mouseEntered,
                                      location: .zero,
                                      modifierFlags: [],
                                      timestamp: 0,
                                      windowNumber: window.windowNumber,
                                      context: nil,
                                      eventNumber: 0,
                                      trackingNumber: 0,
                                      userData: nil)!
    }

    private var firstResponderHoldsFocus: Bool {
        return window.firstResponder?.it_focusFollowsMouseHoldsFocusInHierarchy() ?? false
    }

    func testPlainViewsDoNotHoldFocus() {
        let view = NSView()
        XCTAssertFalse(view.it_focusFollowsMouseHoldsFocus())
        XCTAssertFalse(view.it_focusFollowsMouseHoldsFocusInHierarchy())
    }

    func testHoldIsFoundOnAncestor() {
        let holder = HoldingView()
        let child = NSView()
        holder.addSubview(child)
        XCTAssertTrue(child.it_focusFollowsMouseHoldsFocusInHierarchy())
        holder.holds = false
        XCTAssertFalse(child.it_focusFollowsMouseHoldsFocusInHierarchy())
    }

    func testNoteIsImmune() {
        XCTAssertTrue(note.it_focusFollowsMouseImmune())
    }

    func testUnfocusedNoteDoesNotHoldFocus() {
        XCTAssertFalse(note.it_focusFollowsMouseHoldsFocus())
    }

    func testNoteFocusedWithPointerOutsideHoldsFocus() {
        note.focus()
        XCTAssertTrue(note.it_focusFollowsMouseHoldsFocus())
        XCTAssertTrue(firstResponderHoldsFocus)
    }

    func testPointerEnteringNoteReleasesHold() {
        note.focus()
        note.mouseEntered(with: enterEvent())
        XCTAssertFalse(note.it_focusFollowsMouseHoldsFocus())
        XCTAssertFalse(firstResponderHoldsFocus)
    }

    func testRefocusingNoteHoldsFocusAgain() {
        note.focus()
        note.mouseEntered(with: enterEvent())
        window.makeFirstResponder(nil)
        note.focus()
        XCTAssertTrue(firstResponderHoldsFocus)
    }
}
