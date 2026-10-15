//
//  iTermWarningKeyEquivalentTests.swift
//  iTerm2 ModernTests
//
//  iTermWarning gives each button that lacks a key equivalent an automatic
//  Cmd-<letter> shortcut taken from its label. These tests pin:
//
//    - When the accessory holds text the user can select or edit, the
//      automatic shortcuts never take Cmd-A, Cmd-C, Cmd-V, Cmd-X, or Cmd-Z, so
//      select all, copy, paste, cut, and undo reach the text (QA finding F-029).
//    - Without such an accessory, those letters are still available.
//    - Two buttons never get the same automatic shortcut, and an automatic
//      shortcut never repeats one the caller assigned (QA finding F-020).
//    - A shortcut the caller assigned is kept, even a text editing one.
//    - Showing the same warning again (as Permanently Forget Saved Selection
//      does) gives the same shortcuts: automatic ones keep the Command
//      modifier and Return still presses the default button (QA findings
//      F-028 and F-366).
//    - Automatic shortcuts never take Cmd-H, Cmd-Q, Cmd-W, or Cmd-M, which
//      macOS reserves for Hide, Quit, Close, and Minimize (QA finding F-337).
//
//  No alert is shown. The alert is built with makeAlertForRemoteAnswer.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class iTermWarningKeyEquivalentTests: XCTestCase {
    private static let textEditingKeys: Set<String> = ["a", "c", "v", "x", "z"]

    @MainActor
    private func makeAlert(labels: [String],
                           explicitKeys: [Int: String] = [:],
                           accessory: NSView? = nil) -> NSAlert {
        return makeWarning(labels: labels, explicitKeys: explicitKeys, accessory: accessory).makeAlertForRemoteAnswer()
    }

    @MainActor
    private func makeWarning(labels: [String],
                             explicitKeys: [Int: String] = [:],
                             accessory: NSView? = nil) -> iTermWarning {
        let warning = iTermWarning()
        warning.heading = "Heading"
        warning.title = "The main text."
        warning.warningActions = labels.enumerated().map { index, label in
            let action = iTermWarningAction(label: label, block: nil)
            action.keyEquivalent = explicitKeys[index]
            return action
        }
        warning.warningType = .kiTermWarningTypePersistent
        warning.accessory = accessory
        return warning
    }

    /// The Command-only shortcut on each button, or nil if it has none (for
    /// example Return or Escape).
    @MainActor
    private func commandLetters(_ alert: NSAlert) -> [String?] {
        return alert.buttons.map { button in
            guard button.keyEquivalentModifierMask == .command,
                  let first = button.keyEquivalent.unicodeScalars.first,
                  CharacterSet.letters.contains(first) else {
                return nil
            }
            return button.keyEquivalent
        }
    }

    /// The paste-with-tabs alert's accessory: a text field in a container view.
    @MainActor
    private func textFieldAccessory() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 50, height: 24))
        field.stringValue = "4"
        container.addSubview(field)
        return container
    }

    private let pasteWithTabsLabels = ["Paste with tabs", "Cancel", "Convert tabs to spaces", "Advanced…"]

    @MainActor
    func testTextFieldAccessoryKeepsTextEditingShortcutsForTheField() {
        let alert = makeAlert(labels: pasteWithTabsLabels + ["Verify", "Xylophone", "Zebra"],
                              accessory: textFieldAccessory())
        let letters = commandLetters(alert)
        for (index, letter) in letters.enumerated() {
            if let letter {
                XCTAssertFalse(Self.textEditingKeys.contains(letter),
                               "\(alert.buttons[index].title) took Cmd-\(letter)")
            }
        }
        // Buttons still get a shortcut from another letter in their label.
        XCTAssertEqual(letters[2], "o")  // Convert tabs to spaces
        XCTAssertEqual(letters[3], "d")  // Advanced…
        XCTAssertEqual(letters[4], "e")  // Verify
        XCTAssertEqual(letters[5], "y")  // Xylophone
        XCTAssertEqual(letters[6], "b")  // Zebra
    }

    /// Selectable but not editable text, such as a command shown for review,
    /// can still be selected and copied.
    @MainActor
    func testSelectableTextViewAccessoryKeepsTextEditingShortcuts() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        scrollView.documentView = textView
        let alert = makeAlert(labels: ["OK", "Copy Command"], accessory: scrollView)
        XCTAssertEqual(commandLetters(alert)[1], "o")
    }

    @MainActor
    func testNonTextAccessoryLeavesTextEditingLettersAvailable() {
        let checkbox = NSButton(checkboxWithTitle: "Option", target: nil, action: nil)
        let alert = makeAlert(labels: pasteWithTabsLabels, accessory: checkbox)
        let letters = commandLetters(alert)
        XCTAssertEqual(letters[2], "c")
        XCTAssertEqual(letters[3], "a")
    }

    @MainActor
    func testNoAccessoryLeavesTextEditingLettersAvailable() {
        let letters = commandLetters(makeAlert(labels: pasteWithTabsLabels))
        XCTAssertEqual(letters[2], "c")
        XCTAssertEqual(letters[3], "a")
    }

    /// A label made with NSTextField(labelWithString:) is not selectable, so it
    /// does not reserve the text editing letters.
    @MainActor
    func testStaticLabelAccessoryLeavesTextEditingLettersAvailable() {
        let label = NSTextField(labelWithString: "Just a label")
        let letters = commandLetters(makeAlert(labels: pasteWithTabsLabels, accessory: label))
        XCTAssertEqual(letters[3], "a")
    }

    @MainActor
    func testButtonsWithTheSameFirstLetterGetDifferentShortcuts() {
        let letters = commandLetters(makeAlert(labels: ["OK", "Disable", "Delete", "Dismiss"]))
        XCTAssertEqual(letters[1], "d")
        XCTAssertEqual(letters[2], "e")
        XCTAssertEqual(letters[3], "i")
    }

    @MainActor
    func testAutomaticShortcutDoesNotRepeatAnExplicitOne() {
        let alert = makeAlert(labels: ["OK", "Help", "Hide"], explicitKeys: [2: "h"])
        XCTAssertEqual(alert.buttons[2].keyEquivalent, "h")
        XCTAssertEqual(commandLetters(alert)[1], "e")
    }

    /// The caller chose this shortcut on purpose, so it stays even when the
    /// accessory holds editable text.
    @MainActor
    func testExplicitTextEditingShortcutIsKept() {
        let alert = makeAlert(labels: ["OK", "Copy"],
                              explicitKeys: [1: "c"],
                              accessory: textFieldAccessory())
        XCTAssertEqual(alert.buttons[1].keyEquivalent, "c")
    }

    /// Building the alert a second time for the same warning must not turn
    /// the first showing's Cmd-letter shortcuts into bare letters.
    @MainActor
    func testShowingTheSameWarningAgainKeepsCommandShortcuts() {
        let warning = makeWarning(labels: ["Paste", "Cancel", "Advanced…"])
        let first = warning.makeAlertForRemoteAnswer()
        let second = warning.makeAlertForRemoteAnswer()
        XCTAssertEqual(commandLetters(second), commandLetters(first))
        XCTAssertEqual(commandLetters(second)[2], "a")
        for button in second.buttons {
            let isLetter = button.keyEquivalent.unicodeScalars.first.map { CharacterSet.letters.contains($0) } ?? false
            if isLetter {
                XCTAssertEqual(button.keyEquivalentModifierMask, .command,
                               "\(button.title) has a bare-letter shortcut")
            }
        }
        XCTAssertEqual(second.buttons[0].keyEquivalent, "\r")
        XCTAssertEqual(second.buttons.map(\.keyEquivalent), first.buttons.map(\.keyEquivalent))
    }

    /// The caller's key equivalent is not overwritten by building the alert.
    @MainActor
    func testBuildingTheAlertDoesNotChangeTheActionsKeyEquivalents() {
        let warning = makeWarning(labels: ["OK", "Help", "Hide"], explicitKeys: [2: "h"])
        _ = warning.makeAlertForRemoteAnswer()
        XCTAssertEqual((warning.warningActions ?? []).map { $0.keyEquivalent }, [nil, nil, "h"])
    }

    /// Cmd-H must hide iTerm2, not press Help (QA finding F-337).
    @MainActor
    func testAutomaticShortcutsSkipSystemStandardLetters() {
        let letters = commandLetters(makeAlert(labels: ["Locate", "Help", "Cancel", "Quit", "Window", "Minimize"]))
        for letter in letters {
            if let letter {
                XCTAssertFalse(["h", "q", "w", "m"].contains(letter), "Took Cmd-\(letter)")
            }
        }
        XCTAssertEqual(letters[1], "e")  // Help
        XCTAssertEqual(letters[3], "u")  // Quit
        XCTAssertEqual(letters[4], "i")  // Window
        XCTAssertEqual(letters[5], "n")  // Minimize
    }

    /// A caller may still choose one of those letters on purpose.
    @MainActor
    func testExplicitSystemStandardShortcutIsKept() {
        let alert = makeAlert(labels: ["OK", "Hide"], explicitKeys: [1: "h"])
        XCTAssertEqual(alert.buttons[1].keyEquivalent, "h")
    }
}
