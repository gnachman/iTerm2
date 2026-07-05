//
//  NSAlert_iTermTests.swift
//  iTerm2 ModernTests
//
//  Verifies that -[NSAlert(iTerm) runSheetModalForWindow:] does not
//  hang when the parent window is destroyed while the sheet is shown.
//

import XCTest
@testable import iTerm2SharedARC

final class NSAlert_iTermTests: XCTestCase {

    func test_modalReturnsWhenParentWindowCloses() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)

        let alert = NSAlert()
        alert.messageText = "test"
        alert.addButton(withTitle: "OK")

        // Close the window from a background queue shortly after the
        // modal begins.  The nested run loop inside runModalForWindow:
        // will deliver NSWindowWillCloseNotification, our observer
        // will fire abortModal, and the modal must unwind — proving
        // we are not deadlocked.
        DispatchQueue.global().async {
            // Give the modal a moment to enter its run loop.
            Thread.sleep(forTimeInterval: 0.1)
            window.close()
        }

        let response = alert.runSheetModalForWindow(window)
        // Any return value means the fix is working — the call did not
        // block forever.
        XCTAssertNotEqual(response, NSModalResponseContinue,
                          "Modal should not return NSModalResponseContinue when aborted")
    }
}
