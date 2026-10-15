//
//  UndoSafetyLogRedactionTests.swift
//  iTerm2 ModernTests
//
//  NSTextView+iTermUndoSafety writes a debug log line whenever an undo-enabled
//  text view leaves its window. That includes the field editor of a secure text
//  field, so the line must never contain the text being edited. It used to log
//  the NSTextStorage with %@, whose description is the full string, and so
//  password manager and KeePassXC passwords landed in the debug log (QA
//  finding F-341).
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class UndoSafetyLogRedactionTests: XCTestCase {
    private let secret = "Zq7SecretNEWpw"

    func testScrubLogMessageOmitsTextContents() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        textView.string = secret
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: true)
        window.isReleasedWhenClosed = false
        let undoManager = UndoManager()
        let textStorage = textView.textStorage!

        // Sanity check: the storage's own description does contain the secret,
        // which is why it must not be logged with %@.
        XCTAssertTrue(textStorage.description.contains(secret))

        let message = iTermUndoSafetyScrubLogMessage(textStorage, undoManager, textView, window)
        XCTAssertFalse(message.contains(secret), message)
        XCTAssertFalse(message.contains("Zq7"), message)
        XCTAssertTrue(message.hasPrefix("iTermUndoSafety: scrub textStorage"), message)
        XCTAssertTrue(message.contains("length=\(secret.utf16.count)"), message)
        XCTAssertTrue(message.contains("NSTextView"), message)
    }

    func testScrubLogMessageOmitsTextOfFieldEditorSubclassWithCustomDescription() {
        // A text view subclass whose description includes its text must not
        // leak either, since the message describes the view by class and address.
        final class ChattyTextView: NSTextView {
            override var description: String { "<Chatty \(string)>" }
        }
        let textView = ChattyTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        textView.string = secret
        let message = iTermUndoSafetyScrubLogMessage(textView.textStorage!, UndoManager(), textView, nil)
        XCTAssertFalse(message.contains(secret), message)
    }
}
