//
//  CompanionAgentActivityNotifierTests.swift
//  iTerm2 ModernTests
//
//  The Mac-side detector that classifies a broker delivery into content (a completed
//  agent turn, streamed via .commit or a non-streamed visible reply), a nudge (a
//  genuine .classic permission / session request), or nothing (streaming deltas, user
//  messages, and .external orchestration tool calls). Coalescing is the global
//  coordinator's job, so there is no per-chat debounce here. Driven entirely through
//  injected gate/muted/resolve/send, so no broker, ChatListModel, or network.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class CompanionAgentActivityNotifierTests: XCTestCase {
    private var gateOpen = true
    private var mutedChatIDs: Set<String> = []
    private var resolveResult: Message?
    private var sends: [String] = []

    private func makeNotifier() -> CompanionAgentActivityNotifier {
        CompanionAgentActivityNotifier(
            gate: { self.gateOpen },
            muted: { self.mutedChatIDs.contains($0) },
            resolve: { _, _ in self.resolveResult },
            send: { _, chatID in self.sends.append(chatID) })
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
    }

    // MARK: Remote command payloads (.classic nudges, .external is ignored)

    private func classicCommand() -> Message.Content {
        .remoteCommandRequest(
            .classic(RemoteCommand(llmMessage: LLM.Message(role: .assistant, content: nil),
                                   content: .executeCommand(.init(command: "ls -la")))),
            safe: nil)
    }

    private func externalCommand() -> Message.Content {
        .remoteCommandRequest(
            .external(ExternalRemoteCommand(llmMessage: LLM.Message(role: .assistant, content: nil),
                                            name: "scroll_wheel",
                                            argsJSON: "{}",
                                            markdownDescription: "scrolling")),
            safe: nil)
    }

    func testClassicCommandFiresNudge() {
        // A .classic request has Allow/Deny and genuinely blocks on the user.
        makeNotifier().handle(message: msg(classicCommand()), chatID: "c", partial: false)
        XCTAssertEqual(sends, ["c"])
    }

    func testExternalCommandIsIgnored() {
        // An .external orchestration tool call is auto-executed, not a user block, so
        // it must not nudge (this was the source of the push flood + silent placeholders).
        makeNotifier().handle(message: msg(externalCommand()), chatID: "c", partial: false)
        XCTAssertTrue(sends.isEmpty)
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

    // MARK: Muting

    func testMutedChatSuppressesEverything() {
        mutedChatIDs = ["c"]
        let n = makeNotifier()
        resolveResult = msg(.markdown("done"))
        n.handle(message: msg(.commit(UUID())), chatID: "c", partial: false)
        n.handle(message: msg(.markdown("done")), chatID: "c", partial: false)
        // Even a permission request stays silent in a muted chat.
        let inner = msg(.markdown("approve?"))
        n.handle(message: msg(.selectSessionRequest(inner, terminal: true)), chatID: "c", partial: false)
        XCTAssertTrue(sends.isEmpty)
    }

    func testMuteIsPerChat() {
        mutedChatIDs = ["muted"]
        let n = makeNotifier()
        n.handle(message: msg(.markdown("a")), chatID: "muted", partial: false)
        n.handle(message: msg(.markdown("b")), chatID: "other", partial: false)
        XCTAssertEqual(sends, ["other"])
    }
}
