//
//  AgentConversationResumeTests.swift
//  iTerm2
//
//  Offers to resume AI coding agent conversations after a restart (issue 13171).
//

import XCTest
@testable import iTerm2SharedARC

final class AgentConversationRecordTests: XCTestCase {
    private let uuid = "7B9D396C-0FFB-4AB9-B36E-074717CC2CA5"

    func testAcceptsKnownAgentsAndCanonicalizesTheID() throws {
        let record = try XCTUnwrap(AgentConversationRecord(agent: "claude", conversationID: uuid, directory: "/tmp/x"))
        XCTAssertEqual(record.agent, .claude)
        XCTAssertEqual(record.conversationID, uuid.lowercased())
        XCTAssertEqual(record.directory, "/tmp/x")
        XCTAssertNotNil(AgentConversationRecord(agent: "codex", conversationID: uuid, directory: nil))
    }

    // The values arrive through the scripting API and end up typed into a shell.
    func testRejectsAnythingThatIsNotAnAgentAndAUUID() {
        XCTAssertNil(AgentConversationRecord(agent: "bash", conversationID: uuid, directory: nil))
        XCTAssertNil(AgentConversationRecord(agent: "claude", conversationID: "x; rm -rf ~", directory: nil))
        XCTAssertNil(AgentConversationRecord(agent: "claude", conversationID: "", directory: nil))
    }

    func testDropsDirectoriesThatAreRelativeOrHaveControlCharacters() {
        XCTAssertNil(AgentConversationRecord(agent: "claude", conversationID: uuid, directory: "relative")?.directory)
        XCTAssertNil(AgentConversationRecord(agent: "claude", conversationID: uuid, directory: "/tmp/a\nrm -rf ~")?.directory)
    }

    func testDictionaryRoundTrip() throws {
        let record = try XCTUnwrap(AgentConversationRecord(agent: "codex", conversationID: uuid, directory: "/tmp/x"))
        XCTAssertEqual(AgentConversationRecord(dictionary: record.dictionaryValue), record)
        let withTranscript = try XCTUnwrap(AgentConversationRecord(agent: "claude",
                                                                   conversationID: uuid,
                                                                   directory: "/tmp/x",
                                                                   transcript: "/tmp/x/t.jsonl"))
        let decoded = AgentConversationRecord(dictionary: withTranscript.dictionaryValue)
        XCTAssertEqual(decoded, withTranscript)
        XCTAssertEqual(decoded?.transcript, "/tmp/x/t.jsonl")
        XCTAssertNil(AgentConversationRecord(dictionary: ["agent": "claude"]))
    }

    func testCommandChangesDirectoryOnlyWhenTheShellStartsElsewhere() throws {
        let claude = try XCTUnwrap(AgentConversationRecord(agent: "claude", conversationID: uuid, directory: "/tmp/x"))
        let id = uuid.lowercased()
        XCTAssertEqual(claude.command(launchDirectory: "/tmp/x"), "claude --resume \(id)")
        XCTAssertEqual(claude.command(launchDirectory: "/tmp/x/"), "claude --resume \(id)")
        XCTAssertEqual(claude.command(launchDirectory: nil), "cd /tmp/x && claude --resume \(id)")

        let codex = try XCTUnwrap(AgentConversationRecord(agent: "codex", conversationID: uuid, directory: nil))
        XCTAssertEqual(codex.command(launchDirectory: "/tmp"), "codex resume \(id)")
    }

    func testCommandEscapesTheDirectory() throws {
        let record = try XCTUnwrap(AgentConversationRecord(agent: "claude", conversationID: uuid, directory: "/tmp/a b;c"))
        let command = record.command(launchDirectory: nil)
        XCTAssertTrue(command.hasPrefix("cd "), command)
        XCTAssertFalse(command.contains("/tmp/a b;c"), "the directory must be escaped: \(command)")
        XCTAssertTrue(command.hasSuffix(" && claude --resume \(uuid.lowercased())"), command)
    }

    func testRecognizesTheAgentInTheSavedAncestry() throws {
        let claude = try XCTUnwrap(AgentConversationRecord(agent: "claude", conversationID: uuid, directory: nil))
        XCTAssertTrue(claude.wasRunning(inForegroundJobAncestry: ["git", "claude"]))
        // npm installs run a native binary, sometimes started by path.
        XCTAssertTrue(claude.wasRunning(inForegroundJobAncestry: ["/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe", "node"]))
        // A node or bun job is some other program, such as a dev server started after the agent ended.
        XCTAssertFalse(claude.wasRunning(inForegroundJobAncestry: ["node", "sh", "npm"]))
        XCTAssertFalse(claude.wasRunning(inForegroundJobAncestry: ["bun"]))
        XCTAssertFalse(claude.wasRunning(inForegroundJobAncestry: ["vim"]))
        XCTAssertFalse(claude.wasRunning(inForegroundJobAncestry: []))
        let codex = try XCTUnwrap(AgentConversationRecord(agent: "codex", conversationID: uuid, directory: nil))
        XCTAssertTrue(codex.wasRunning(inForegroundJobAncestry: ["codex-aarch64-apple-darwin"]))
        XCTAssertFalse(codex.wasRunning(inForegroundJobAncestry: ["claude"]))
    }
}

@MainActor
final class AgentConversationResumeOffersTests: XCTestCase {
    private var offers: AgentConversationResumeOffers!
    private var typed: [(PTYSession, String)] = []
    private var disabled = false
    private var notAtPrompt = [PTYSession]()
    private var directory: String!

    override func setUp() {
        super.setUp()
        offers = AgentConversationResumeOffers()
        typed = []
        disabled = false
        offers.isEnabled = { [unowned self] in !self.disabled }
        offers.disable = { [unowned self] in self.disabled = true }
        offers.typeText = { [unowned self] session, text in self.typed.append((session, text)) }
        offers.isReadyForInput = { [unowned self] session in !self.notAtPrompt.contains { $0 === session } }
        directory = (NSTemporaryDirectory() as NSString).standardizingPath
    }

    private func relaunchedSession(conversation: String,
                                   directory: String? = nil,
                                   transcript: String? = nil,
                                   ancestors: [String]? = ["2.1.309", "claude"]) -> PTYSession {
        let session = PTYSession(synthetic: false)!
        session.agentConversation = AgentConversationRecord(agent: "claude",
                                                            conversationID: conversation,
                                                            directory: directory ?? self.directory,
                                                            transcript: transcript)
        offers.sessionDidRelaunch(session, launchDirectory: self.directory, foregroundJobAncestors: ancestors)
        return session
    }

    private let first = "11111111-1111-4111-8111-111111111111"
    private let second = "22222222-2222-4222-8222-222222222222"

    func testOffersWaitForRestorationAndOfferResumeAllWhenThereAreSeveral() {
        let a = relaunchedSession(conversation: first)
        let b = relaunchedSession(conversation: second)
        XCTAssertNil(offers.actionsOffered(in: a), "nothing is shown until restoration finishes")

        offers.sessionsDidFinishRestoring()
        XCTAssertEqual(offers.actionsOffered(in: a), [.resume, .resumeAll, .dontAskAgain])
        XCTAssertEqual(offers.actionsOffered(in: b), [.resume, .resumeAll, .dontAskAgain])
    }

    func testASingleOfferHasNoResumeAll() {
        let a = relaunchedSession(conversation: first)
        offers.sessionsDidFinishRestoring()
        XCTAssertEqual(offers.actionsOffered(in: a), [.resume, .dontAskAgain])
    }

    func testResumeTypesTheCommandAndForgetsTheConversation() {
        let a = relaunchedSession(conversation: first)
        offers.sessionsDidFinishRestoring()

        offers.perform(.resume, in: a)
        XCTAssertEqual(typed.count, 1)
        XCTAssertTrue(typed.first?.0 === a)
        XCTAssertEqual(typed.first?.1, "claude --resume \(first)\n")
        XCTAssertNil(a.agentConversation)
        XCTAssertNil(offers.actionsOffered(in: a))
    }

    func testResumeChangesDirectoryWhenTheAgentRanElsewhere() throws {
        let elsewhere = (directory as NSString).deletingLastPathComponent
        let a = relaunchedSession(conversation: first, directory: elsewhere)
        offers.sessionsDidFinishRestoring()

        offers.perform(.resume, in: a)
        let text = try XCTUnwrap(typed.first?.1)
        XCTAssertTrue(text.hasPrefix("cd "), text)
        XCTAssertTrue(text.hasSuffix("&& claude --resume \(first)\n"), text)
    }

    func testResumeAllTypesIntoEverySessionOnce() {
        let a = relaunchedSession(conversation: first)
        let b = relaunchedSession(conversation: second)
        offers.sessionsDidFinishRestoring()

        offers.perform(.resumeAll, in: b)
        XCTAssertEqual(typed.count, 2)
        XCTAssertEqual(Set(typed.map { $0.1 }), ["claude --resume \(first)\n", "claude --resume \(second)\n"])
        XCTAssertTrue(typed.contains { $0.0 === a })
        XCTAssertTrue(typed.contains { $0.0 === b })

        offers.perform(.resume, in: a)
        XCTAssertEqual(typed.count, 2, "an offer already acted on does nothing")
    }

    func testDontAskAgainTurnsOffersOffAndTypesNothing() {
        let a = relaunchedSession(conversation: first)
        offers.sessionsDidFinishRestoring()
        offers.perform(.dontAskAgain, in: a)
        XCTAssertTrue(disabled)
        XCTAssertTrue(typed.isEmpty)

        let b = relaunchedSession(conversation: second)
        XCTAssertNil(offers.actionsOffered(in: b))
    }

    // The hook re-reporting the same conversation means the user resumed it by hand.
    func testTheSameConversationReportedAgainWithdrawsTheOffer() {
        let a = relaunchedSession(conversation: first)
        offers.sessionsDidFinishRestoring()

        offers.setConversation(AgentConversationRecord(agent: "claude", conversationID: first, directory: directory), in: a)
        XCTAssertNil(offers.actionsOffered(in: a))
        offers.perform(.resume, in: a)
        XCTAssertTrue(typed.isEmpty, "the agent is already running")
        XCTAssertEqual(a.agentConversation?.conversationID, first)
    }

    func testResumeBeforeTheFirstPromptWaitsForIt() {
        let a = relaunchedSession(conversation: first)
        notAtPrompt = [a]
        offers.sessionsDidFinishRestoring()

        offers.perform(.resume, in: a)
        XCTAssertTrue(typed.isEmpty)
        XCTAssertTrue(offers.isAwaitingPrompt(a))
        XCTAssertNotNil(a.agentConversation, "the conversation is kept while waiting")

        offers.sessionDidShowPrompt(a)
        XCTAssertEqual(typed.map { $0.1 }, ["claude --resume \(first)\n"])
        XCTAssertFalse(offers.isAwaitingPrompt(a))

        offers.sessionDidShowPrompt(a)
        XCTAssertEqual(typed.count, 1, "typed once")
    }

    func testAnAgentStartedWhileWaitingCancelsTheResume() {
        let a = relaunchedSession(conversation: first)
        notAtPrompt = [a]
        offers.sessionsDidFinishRestoring()
        offers.perform(.resume, in: a)

        offers.setConversation(AgentConversationRecord(agent: "claude", conversationID: first, directory: directory), in: a)
        offers.sessionDidShowPrompt(a)
        XCTAssertTrue(typed.isEmpty)
    }

    func testNoOfferWhenTheAgentWasNotRunningAtSave() {
        let a = relaunchedSession(conversation: first, ancestors: ["vim"])
        let b = relaunchedSession(conversation: second, ancestors: nil)
        offers.sessionsDidFinishRestoring()
        XCTAssertNil(offers.actionsOffered(in: a))
        XCTAssertNil(offers.actionsOffered(in: b))
        XCTAssertNil(a.agentConversation, "a stale conversation is forgotten")
    }

    func testANewConversationWithdrawsTheOffer() {
        let a = relaunchedSession(conversation: first)
        offers.sessionsDidFinishRestoring()

        offers.setConversation(AgentConversationRecord(agent: "claude", conversationID: second, directory: directory), in: a)
        XCTAssertEqual(a.agentConversation?.conversationID, second)
        offers.perform(.resume, in: a)
        XCTAssertTrue(typed.isEmpty, "the offer was for a conversation the session has moved on from")
    }

    func testNoOfferWhenTheDirectoryIsGone() {
        let a = relaunchedSession(conversation: first, directory: "/nonexistent-\(UUID().uuidString)")
        offers.sessionsDidFinishRestoring()
        XCTAssertNil(offers.actionsOffered(in: a))
        XCTAssertNil(a.agentConversation)
    }

    // The agent writes the transcript only once the conversation has a message. A conversation
    // quit before then can't be resumed (the agent says no conversation was found).
    func testNoOfferWhenTheTranscriptWasNeverWritten() {
        let a = relaunchedSession(conversation: first,
                                  transcript: (directory as NSString).appendingPathComponent("missing-\(UUID().uuidString).jsonl"))
        offers.sessionsDidFinishRestoring()
        XCTAssertNil(offers.actionsOffered(in: a))
        XCTAssertNil(a.agentConversation)
    }

    func testOfferWhenTheTranscriptExists() throws {
        let transcript = (directory as NSString).appendingPathComponent("transcript-\(UUID().uuidString).jsonl")
        try Data("{}\n".utf8).write(to: URL(fileURLWithPath: transcript))
        defer { try? FileManager.default.removeItem(atPath: transcript) }
        let a = relaunchedSession(conversation: first, transcript: transcript)
        offers.sessionsDidFinishRestoring()
        XCTAssertNotNil(offers.actionsOffered(in: a))
    }

    // What iterm2.set_agent_conversation passes on from the hook.
    func testAStartReportRecordsTheConversationAndNonsenseRecordsNothing() {
        let session = PTYSession(synthetic: false)!
        offers.conversationDidStart(first, agent: "claude", directory: directory, transcript: nil, in: session)
        XCTAssertEqual(session.agentConversation?.conversationID, first)
        offers.conversationDidStart("not a uuid", agent: "claude", directory: nil, transcript: nil, in: session)
        XCTAssertNil(session.agentConversation)
        offers.conversationDidStart(first, agent: "bash", directory: nil, transcript: nil, in: session)
        XCTAssertNil(session.agentConversation)
    }

    // Only the user quitting that same conversation forgets it. Being killed (as at shutdown)
    // keeps it, and on /clear the old conversation's end can arrive after the new one's start.
    func testOnlyQuittingTheSameConversationForgetsIt() {
        let session = PTYSession(synthetic: false)!
        offers.conversationDidStart(first, agent: "claude", directory: directory, transcript: nil, in: session)
        offers.conversationDidEnd(first, userQuit: false, in: session)
        XCTAssertEqual(session.agentConversation?.conversationID, first)
        offers.conversationDidEnd(second, userQuit: true, in: session)
        XCTAssertEqual(session.agentConversation?.conversationID, first)
        offers.conversationDidEnd(first.uppercased(), userQuit: true, in: session)
        XCTAssertNil(session.agentConversation)
    }

    func testRelaunchAfterRestorationFinishedIsOfferedRightAway() {
        offers.sessionsDidFinishRestoring()
        let a = relaunchedSession(conversation: first)
        XCTAssertEqual(offers.actionsOffered(in: a), [.resume, .dontAskAgain])
    }

    // Restoration reports that it finished before every relaunched session is done starting, so
    // offers can arrive one at a time after it. A banner already up gains Resume All, and
    // replacing it doesn't count as declining.
    func testAnOfferArrivingLaterAddsResumeAllToTheOneAlreadyUp() {
        offers.sessionsDidFinishRestoring()
        let a = relaunchedSession(conversation: first)
        let b = relaunchedSession(conversation: second)
        XCTAssertEqual(offers.actionsOffered(in: a), [.resume, .resumeAll, .dontAskAgain])
        XCTAssertEqual(offers.actionsOffered(in: b), [.resume, .resumeAll, .dontAskAgain])
        XCTAssertNotNil(a.agentConversation)

        offers.perform(.resumeAll, in: b)
        XCTAssertEqual(typed.map { $0.1 }.sorted(), ["claude --resume \(first)\n", "claude --resume \(second)\n"])
    }
}
