//
//  CockpitSkippedTargetsTests.swift
//  ModernTests
//
//  QA finding F-396: a Cockpit send that skipped a closed target ran two
//  sentences together (“Sent to 1 session Skipped targets that no longer
//  exist: FOUR  ⌥⌘2”), named the closed window with its stale window
//  shortcut, and left the gone chip in the composer so every later send
//  skipped it again.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class CockpitSkippedTargetsTests: XCTestCase {
    private let font = NSFont.systemFont(ofSize: 12)

    private func chip(_ guid: String, _ name: String) -> NSAttributedString {
        return ChatSessionMentionAttachment.attributedString(guid: guid,
                                                             displayName: name,
                                                             font: font,
                                                             color: .linkColor)
    }

    private func chipGuids(_ attributed: NSAttributedString) -> [String] {
        var guids: [String] = []
        attributed.enumerateAttribute(.attachment,
                                      in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if let mention = value as? ChatSessionMentionAttachment {
                guids.append(mention.guid)
            }
        }
        return guids
    }

    // MARK: - Status message

    func testSkippedStatusIsPunctuatedSentences() {
        let status = CockpitWindowController.sentStatus(sent: 2, skippedNames: ["FOUR"])
        XCTAssertEqual(status, "Sent to 2 sessions. Skipped targets that no longer exist: FOUR")
    }

    func testSkippedStatusSingularStillEndsTheFirstSentence() {
        let status = CockpitWindowController.sentStatus(sent: 1, skippedNames: ["FOUR", "THREE"])
        XCTAssertEqual(status, "Sent to 1 session. Skipped targets that no longer exist: FOUR, THREE")
    }

    func testStatusWithoutSkipsIsJustTheCount() {
        XCTAssertEqual(CockpitWindowController.sentStatus(sent: 3, skippedNames: []),
                       "Sent to 3 sessions")
    }

    // MARK: - Gone chips leave the composer

    func testGoneChipIsRemovedWithItsSpace() throws {
        let field = NSMutableAttributedString()
        field.append(chip("win:FOUR", "FOUR"))
        field.append(NSAttributedString(string: " "))
        field.append(chip("ptys_ONE", "ONE"))
        field.append(NSAttributedString(string: " echo GONE4"))
        let result = try XCTUnwrap(CockpitWindowController.removingChips(["win:FOUR"], from: field,
                                                                                   selection: NSRange(location: field.length, length: 0)))
        XCTAssertEqual(chipGuids(result.text), ["ptys_ONE"])
        XCTAssertEqual(result.text.length, field.length - 2)
        XCTAssertTrue(result.text.string.hasSuffix(" echo GONE4"))
        XCTAssertEqual(result.selection, NSRange(location: result.text.length, length: 0))
    }

    func testRemovesEveryCopyOfAGoneChip() throws {
        let field = NSMutableAttributedString()
        field.append(chip("tab:7", "Tab"))
        field.append(NSAttributedString(string: " ls "))
        field.append(chip("tab:7", "Tab"))
        let result = try XCTUnwrap(CockpitWindowController.removingChips(["tab:7"], from: field,
                                                                                   selection: NSRange(location: 0, length: 0)))
        XCTAssertEqual(chipGuids(result.text), [])
        XCTAssertEqual(result.text.string, "ls ")
    }

    func testNothingToRemoveReturnsNil() {
        let field = NSMutableAttributedString()
        field.append(chip("ptys_ONE", "ONE"))
        field.append(NSAttributedString(string: " ls"))
        let caret = NSRange(location: 0, length: 0)
        XCTAssertNil(CockpitWindowController.removingChips(["win:FOUR"], from: field, selection: caret))
        XCTAssertNil(CockpitWindowController.removingChips([], from: field, selection: caret))
    }

    // Sending a selection leaves the field as it was, so removing a gone
    // chip before the selection keeps the same text selected.
    func testSelectionAfterGoneChipStillCoversTheSameText() throws {
        let field = NSMutableAttributedString()
        field.append(chip("win:FOUR", "FOUR"))
        field.append(NSAttributedString(string: " echo A\necho B"))
        let selected = (field.string as NSString).range(of: "echo B")
        let result = try XCTUnwrap(CockpitWindowController.removingChips(["win:FOUR"], from: field,
                                                                         selection: selected))
        XCTAssertEqual((result.text.string as NSString).substring(with: result.selection), "echo B")
    }

    func testSelectionSpanningGoneChipShrinks() throws {
        let field = NSMutableAttributedString(string: "ls ")
        field.append(chip("win:FOUR", "FOUR"))
        field.append(NSAttributedString(string: " pwd"))
        let result = try XCTUnwrap(CockpitWindowController.removingChips(["win:FOUR"], from: field,
                                                                         selection: NSRange(location: 0, length: field.length)))
        XCTAssertEqual(result.text.string, "ls pwd")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 6))
    }

    func testSelectionBeforeGoneChipIsUnchanged() throws {
        let field = NSMutableAttributedString(string: "echo A ")
        field.append(chip("win:FOUR", "FOUR"))
        field.append(NSAttributedString(string: " ls"))
        let selected = NSRange(location: 0, length: 6)
        let result = try XCTUnwrap(CockpitWindowController.removingChips(["win:FOUR"], from: field,
                                                                         selection: selected))
        XCTAssertEqual(result.text.string, "echo A ls")
        XCTAssertEqual(result.selection, selected)
    }

    func testAdjacentGoneChipsShiftSelectionByBoth() throws {
        let field = NSMutableAttributedString()
        field.append(chip("win:FOUR", "FOUR"))
        field.append(NSAttributedString(string: " "))
        field.append(chip("ptys_ONE", "ONE"))
        field.append(chip("tab:3", "Tab"))
        field.append(NSAttributedString(string: " pwd"))
        let selected = (field.string as NSString).range(of: "pwd")
        let result = try XCTUnwrap(CockpitWindowController.removingChips(["win:FOUR", "tab:3"], from: field,
                                                                         selection: selected))
        XCTAssertEqual(chipGuids(result.text), ["ptys_ONE"])
        XCTAssertEqual((result.text.string as NSString).substring(with: result.selection), "pwd")
    }

    func testUnknownTokensMapToChipGuids() {
        XCTAssertEqual(CockpitWindowController.chipGuids(forTokens: ["@win:FOUR", "@ptys_ONE", "tab:3"]),
                       ["win:FOUR", "ptys_ONE", "tab:3"])
    }

    // MARK: - Chips don't carry a window or tab shortcut

    func testContainerChipNameOmitsShortcut() throws {
        let node = ChatMentionPickerController.Node(kind: .window,
                                                    title: "FOUR",
                                                    shortcut: "⌥⌘2",
                                                    session: nil,
                                                    children: [],
                                                    containerToken: "win:FOUR")
        XCTAssertEqual(node.title, "FOUR  ⌥⌘2")
        let choice = try XCTUnwrap(ChatMentionPickerController.choice(for: node,
                                                                      allowsContainerSelection: true))
        XCTAssertEqual(choice.guid, "win:FOUR")
        XCTAssertEqual(choice.displayName, "FOUR")
    }

    func testContainerNotPickableWithoutOptIn() {
        let node = ChatMentionPickerController.Node(kind: .tab,
                                                    title: "Tab",
                                                    shortcut: "⌘1",
                                                    session: nil,
                                                    children: [],
                                                    containerToken: "tab:1")
        XCTAssertNil(ChatMentionPickerController.choice(for: node, allowsContainerSelection: false))
    }
}
