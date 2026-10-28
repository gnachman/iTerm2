//
//  CompanionKeyboardInputViewTests.swift
//  iTerm2CompanionTests
//
//  The session's hidden pass-through text view. The system keyboard only auto-repeats
//  a held Delete key while the focused document has text before the caret, so pass-
//  through mode keeps an invisible sentinel there. These tests pin that the sentinel
//  is always present while passing through and never leaks into what the session or
//  the composer sees.
//

import XCTest
@testable import iTerm2Companion

@MainActor
final class CompanionKeyboardInputViewTests: XCTestCase {
    private var view: CompanionKeyboardInputView!
    private var controller: SessionKeyboardController!
    private var sent: [CompanionKeyEvent] = []
    private var composerSends: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        sent = []
        composerSends = []
        controller = SessionKeyboardController()
        controller.send = { [unowned self] in self.sent.append($0) }
        view = CompanionKeyboardInputView()
        view.controller = controller
        view.onSendComposerText = { [unowned self] in self.composerSends.append($0) }
    }

    private var backspaceCount: Int {
        sent.filter { $0.key == .special(.backspace) }.count
    }

    // MARK: Delete auto-repeat context

    func test_passthrough_hasTextBeforeCaret() {
        XCTAssertGreaterThan(view.selectedRange.location, 0,
                             "the keyboard only repeats Delete when there is text before the caret")
    }

    func test_passthrough_backspaceForwardsAndKeepsTextBeforeCaret() {
        view.deleteBackward()
        view.deleteBackward()
        view.deleteBackward()
        XCTAssertEqual(backspaceCount, 3)
        XCTAssertGreaterThan(view.selectedRange.location, 0)
    }

    func test_passthrough_typingForwardsAndLeavesDocumentAlone() {
        let before = view.text
        view.insertText("a")
        XCTAssertEqual(sent.map(\.key), [.text("a")])
        XCTAssertEqual(view.text, before)
        XCTAssertGreaterThan(view.selectedRange.location, 0)
    }

    func test_exitComposerClearingDraft_restoresTextBeforeCaret() {
        view.enterComposer()
        view.insertText("ab")
        view.exitComposer(clearDraft: true)
        XCTAssertGreaterThan(view.selectedRange.location, 0)
        view.deleteBackward()
        XCTAssertEqual(backspaceCount, 1)
    }

    // MARK: The sentinel never leaks

    func test_composer_startsWithEmptyDraft() {
        view.enterComposer()
        XCTAssertEqual(view.draftText, "")
    }

    func test_composer_emptyDraftSendsNothing() {
        view.enterComposer()
        XCTAssertFalse(view.sendComposerDraft())
        XCTAssertEqual(composerSends, [])
    }

    func test_composer_sendOmitsSentinel() {
        view.enterComposer()
        view.insertText("ls")
        XCTAssertTrue(view.sendComposerDraft())
        XCTAssertEqual(composerSends, ["ls"])
    }

    func test_composer_draftKeptAcrossCloseOmitsSentinel() {
        view.enterComposer()
        view.insertText("echo")
        view.exitComposer(clearDraft: false)
        view.enterComposer()
        XCTAssertEqual(view.draftText, "echo")
    }
}
