//
//  CompanionAgentActivityNotifierTests.swift
//  iTerm2 ModernTests
//
//  The Mac-side detector that decides when an away phone gets a push: completed
//  agent turns (streamed via .commit, or non-streamed visible replies, debounced
//  per chat) and permission / session-selection requests (which bypass the
//  debounce). Driven entirely through injected clock/gate/resolve/send, so no
//  broker, ChatListModel, or network is involved.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class CompanionAgentActivityNotifierTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000)
    private var gateOpen = true
    private var resolveResult: Message?
    private var sends: [String] = []

    private func makeNotifier(debounce: TimeInterval = 30) -> CompanionAgentActivityNotifier {
        CompanionAgentActivityNotifier(
            debounceInterval: debounce,
            clock: { self.now },
            gate: { self.gateOpen },
            resolve: { _, _ in self.resolveResult },
            send: { self.sends.append($0) })
    }

    private func msg(_ content: Message.Content, author: Participant = .agent) -> Message {
        Message(chatID: "c", author: author, content: content, sentDate: Date(), uniqueID: UUID())
    }

    // MARK: Turn completion

    func testStreamedCommit_firesWhenTargetVisibleAndNonEmpty() {
        resolveResult = msg(.markdown("the finished reply"))
        makeNotifier().handle(message: msg(.commit(UUID())), chatID: "c", partial: false)
        XCTAssertEqual(sends, ["c"])
    }

    func testStreamedCommit_doesNotFireWhenTargetMissing() {
        resolveResult = nil
        makeNotifier().handle(message: msg(.commit(UUID())), chatID: "c", partial: false)
        XCTAssertTrue(sends.isEmpty)
    }

    func testStreamedCommit_doesNotFireWhenTargetEmpty() {
        resolveResult = msg(.markdown(""))
        makeNotifier().handle(message: msg(.commit(UUID())), chatID: "c", partial: false)
        XCTAssertTrue(sends.isEmpty)
    }

    func testStreamedCommit_doesNotFireWhenTargetHidden() {
        resolveResult = msg(.setPermissions([]))   // hiddenFromClient == true
        makeNotifier().handle(message: msg(.commit(UUID())), chatID: "c", partial: false)
        XCTAssertTrue(sends.isEmpty)
    }

    func testNonStreamedFinal_fires() {
        makeNotifier().handle(message: msg(.markdown("hello")), chatID: "c", partial: false)
        XCTAssertEqual(sends, ["c"])
    }

    func testStreamedBegin_doesNotFire() {
        // A streamed turn's opening message is a visible agent .markdown but
        // partial:true; it must not fire (its .commit will).
        makeNotifier().handle(message: msg(.markdown("hello")), chatID: "c", partial: true)
        XCTAssertTrue(sends.isEmpty)
    }

    func testMidStreamAppend_doesNotFire() {
        makeNotifier().handle(message: msg(.append(string: "x", uuid: UUID())), chatID: "c", partial: true)
        XCTAssertTrue(sends.isEmpty)
    }

    func testUserMessage_doesNotFire() {
        makeNotifier().handle(message: msg(.markdown("hi"), author: .user), chatID: "c", partial: false)
        XCTAssertTrue(sends.isEmpty)
    }

    func testHiddenAgentMessage_doesNotFire() {
        makeNotifier().handle(message: msg(.setPermissions([])), chatID: "c", partial: false)
        XCTAssertTrue(sends.isEmpty)
    }

    func testStreamedCommit_doesNotFireWhenTargetIsSubstanceFreeMultipart() {
        let cases: [Message.Content] = [
            .multipart([], vectorStoreID: nil),
            .multipart([.context("just context")], vectorStoreID: nil),
            .multipart([.attachment(LLM.Message.Attachment(
                inline: true, id: "s",
                type: .statusUpdate(.reasoningSummaryUpdate("thinking"))))], vectorStoreID: nil),
        ]
        for content in cases {
            sends = []
            resolveResult = msg(content)
            makeNotifier().handle(message: msg(.commit(UUID())), chatID: "c", partial: false)
            XCTAssertTrue(sends.isEmpty, "tool-only / empty multipart must not fire: \(content)")
        }
    }

    func testNonStreamedMultipart_firesOnRealSubstance() {
        // A file attachment renders as "📄 name" - real, displayable content.
        let file = LLM.Message.Attachment.AttachmentType.File(
            name: "report.pdf", content: Data(), mimeType: "application/pdf", localPath: nil)
        let withFile = Message.Content.multipart(
            [.attachment(LLM.Message.Attachment(inline: true, id: "f", type: .file(file)))],
            vectorStoreID: nil)
        makeNotifier().handle(message: msg(withFile), chatID: "c", partial: false)
        XCTAssertEqual(sends, ["c"])

        sends = []
        let withText = Message.Content.multipart([.markdown("here you go")], vectorStoreID: nil)
        makeNotifier().handle(message: msg(withText), chatID: "c", partial: false)
        XCTAssertEqual(sends, ["c"])
    }

    // MARK: Permission / input requests

    func testSessionSelectionRequest_fires() {
        let inner = msg(.markdown("needs a session"))
        makeNotifier().handle(message: msg(.selectSessionRequest(inner, terminal: true)),
                              chatID: "c", partial: false)
        XCTAssertEqual(sends, ["c"])
        // .remoteCommandRequest takes the identical switch arm.
    }

    // MARK: Debounce

    func testTurnCompleteDebouncedPerChat() {
        let n = makeNotifier(debounce: 30)
        n.handle(message: msg(.markdown("a")), chatID: "c", partial: false)
        XCTAssertEqual(sends, ["c"])
        now = now.addingTimeInterval(10)   // within the window
        n.handle(message: msg(.markdown("b")), chatID: "c", partial: false)
        XCTAssertEqual(sends, ["c"], "second turn within debounce is suppressed")
        now = now.addingTimeInterval(25)   // now 35s past the first
        n.handle(message: msg(.markdown("c")), chatID: "c", partial: false)
        XCTAssertEqual(sends, ["c", "c"], "after the window it fires again")
    }

    func testUserActionRequiredBypassesDebounce() {
        let n = makeNotifier(debounce: 30)
        n.handle(message: msg(.markdown("done")), chatID: "c", partial: false)
        XCTAssertEqual(sends, ["c"])
        // Same chat, well within the debounce: a permission request must still fire.
        let inner = msg(.markdown("approve?"))
        n.handle(message: msg(.selectSessionRequest(inner, terminal: true)), chatID: "c", partial: false)
        XCTAssertEqual(sends, ["c", "c"])
    }

    // MARK: Gating

    func testGateClosedSuppressesEverything() {
        gateOpen = false
        let n = makeNotifier()
        resolveResult = msg(.markdown("done"))
        n.handle(message: msg(.commit(UUID())), chatID: "c", partial: false)
        n.handle(message: msg(.markdown("done")), chatID: "c", partial: false)
        let inner = msg(.markdown("approve?"))
        n.handle(message: msg(.selectSessionRequest(inner, terminal: true)), chatID: "c", partial: false)
        XCTAssertTrue(sends.isEmpty)
    }
}
