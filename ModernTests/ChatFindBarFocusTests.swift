//
//  ChatFindBarFocusTests.swift
//  iTerm2
//
//  Closing the AI chat find bar with Escape must not leave the window with
//  no first responder. QA finding F-094.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

@MainActor
final class ChatFindBarFocusTests: XCTestCase {
    // Escape in the search field closes the bar; the chat view controller uses
    // this to move focus back to the input instead of leaving none.
    func testContainsFirstResponderWhileSearchFieldIsFocused() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let bar = ChatFindBarView(frame: NSRect(x: 0, y: 0, width: 600, height: ChatFindBarView.barHeight))
        window.contentView?.addSubview(bar)
        XCTAssertFalse(bar.containsFirstResponder)
        bar.focusSearchField()
        XCTAssertTrue(bar.containsFirstResponder)
        window.makeFirstResponder(nil)
        XCTAssertFalse(bar.containsFirstResponder)
    }
}
