//
//  iTermWarningInitialFirstResponderTests.swift
//  iTerm2 ModernTests
//
//  A warning that asks for text (a name, a tmux command, the scp password) sets
//  initialFirstResponder to its field so typing lands there without a click.
//  iTermWarning hands that to the alert's window, and AppKit makes it first
//  responder when the alert (app-modal or sheet) is shown. QA confirmed at
//  runtime that this works for both kinds (QA findings F-018, F-030, F-031,
//  F-034). These tests pin the part iTermWarning owns: the alert's window names
//  the field as its initial first responder, the field is in that window (inside
//  the accessory wrapper), and the window can make it first responder.
//
//  No alert is shown. The alert is built with makeAlertForRemoteAnswer.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class iTermWarningInitialFirstResponderTests: XCTestCase {
    @MainActor
    private func makeAlert(accessory: NSView, initialFirstResponder: NSView?) -> NSAlert {
        let warning = iTermWarning()
        warning.heading = "Heading"
        warning.title = "The main text."
        warning.warningActions = ["OK", "Cancel"].map { iTermWarningAction(label: $0, block: nil) }
        warning.cancelLabel = "Cancel"
        warning.warningType = .kiTermWarningTypePersistent
        warning.accessory = accessory
        warning.initialFirstResponder = initialFirstResponder
        let alert = warning.makeAlertForRemoteAnswer()
        alert.layout()
        return alert
    }

    /// Asserts that `alert` will put focus in `field` when shown.
    @MainActor
    private func assertFocusGoes(to field: NSTextField,
                                 in alert: NSAlert,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        let window = alert.window
        XCTAssertTrue(window.initialFirstResponder === field,
                      "The alert's window should name the field as its initial first responder",
                      file: file, line: line)
        XCTAssertTrue(field.isDescendant(of: window.contentView!),
                      "The field should be in the alert's window",
                      file: file, line: line)
        XCTAssertTrue(field.acceptsFirstResponder, file: file, line: line)
        XCTAssertTrue(window.makeFirstResponder(window.initialFirstResponder),
                      file: file, line: line)
        // An editing text field hands first responder to its field editor.
        let editor = window.firstResponder as? NSText
        XCTAssertTrue(editor?.delegate === field,
                      "Typing should go to the field",
                      file: file, line: line)
    }

    @MainActor
    func testTextFieldAccessoryGetsFocus() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = "default name"
        let alert = makeAlert(accessory: field, initialFirstResponder: field)
        assertFocusGoes(to: field, in: alert)
    }

    /// The scp password prompt (FileTransferManager) uses a bare secure field.
    @MainActor
    func testSecureFieldAccessoryGetsFocus() {
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let alert = makeAlert(accessory: field, initialFirstResponder: field)
        assertFocusGoes(to: field, in: alert)
    }

    /// Prompts with several fields put them in a container and choose which one
    /// starts with focus, which need not be the first.
    @MainActor
    func testNestedFieldChosenAsInitialFirstResponderGetsFocus() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
        let username = NSTextField(frame: NSRect(x: 0, y: 32, width: 200, height: 24))
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        container.addSubview(username)
        container.addSubview(password)
        let alert = makeAlert(accessory: container, initialFirstResponder: password)
        assertFocusGoes(to: password, in: alert)
    }
}
