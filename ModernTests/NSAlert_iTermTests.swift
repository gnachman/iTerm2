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

        // Close the window on the main queue. AppKit window teardown must happen
        // on the main thread, so we cannot close from a background queue. This
        // block is enqueued now and runs once runSheetModal(for:) enters its
        // nested modal run loop (which pumps the main queue), so
        // NSWindowWillCloseNotification is delivered on the main thread during
        // the modal, the observer fires abortModal, and the modal unwinds. No
        // background thread and no sleep-based timing, so it can't deadlock or
        // flake.
        DispatchQueue.main.async {
            window.close()
        }

        let response = alert.runSheetModal(for: window)
        // abortModal makes runModalForWindow: return .abort. The essential point
        // is that the call returned at all instead of blocking forever.
        XCTAssertEqual(response, .abort,
                       "Modal should abort when the parent window closes")
    }
}
