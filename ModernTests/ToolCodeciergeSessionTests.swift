//
//  ToolCodeciergeSessionTests.swift
//  iTerm2
//
//  Created by George Nachman on 11/4/26.
//

import XCTest
@testable import iTerm2SharedARC

/// Codecierge keeps per-terminal-session state in ToolCodecierge.Session. A goal in progress is
/// what has the terminal session capture its commands' output, and stopping the goal releases what
/// it accumulated. Stopping acts on the session it was asked about, not on whichever session the
/// toolbelt happens to show.
final class ToolCodeciergeSessionTests: XCTestCase {
    func testOutputIsCapturedOnlyWhileAGoalIsRunning() {
        let guid = UUID().uuidString
        let session = ToolCodecierge.Session(guid)
        XCTAssertFalse(CommandOutput.hasConsumers(forSessionReferences: [guid]),
                       "Nothing is captured before a goal starts")
        session.running = true
        XCTAssertTrue(CommandOutput.hasConsumers(forSessionReferences: [guid]))
        session.running = true
        XCTAssertTrue(CommandOutput.hasConsumers(forSessionReferences: [guid]),
                      "Setting the same value keeps the registration")
        session.running = false
        XCTAssertFalse(CommandOutput.hasConsumers(forSessionReferences: [guid]),
                       "Stopping ends the capture")
    }

    func testStoppingReleasesWhatTheGoalAccumulated() {
        let session = ToolCodecierge.Session(UUID().uuidString)
        session.running = true
        session.pendingCompletion = { _ in }
        session.running = false
        XCTAssertNil(session.pendingCompletion)
    }

    /// A reply to a goal that has since stopped is dropped, even when a new goal has started by the
    /// time it arrives: it must not install the old goal's conversation over the new one or call
    /// back as though it were the new goal's reply.
    func testReplyToAStoppedGoalIsDropped() {
        let session = ToolCodecierge.Session(UUID().uuidString)
        session.running = true
        let staleGeneration = session.goalGeneration
        session.running = false
        session.running = true
        let reply = AIConversation(registrationProvider: nil,
                                   messages: [AITermController.Message(role: .assistant, content: "old answer")])
        var calledBack = false
        session.didComplete(.success(reply), sentUnderGeneration: staleGeneration) { _ in
            calledBack = true
        }
        XCTAssertFalse(calledBack, "The reply belongs to the stopped goal")
        XCTAssertNil(session.conversation, "The new goal’s conversation must be left alone")

        session.didComplete(.success(reply), sentUnderGeneration: session.goalGeneration) { _ in
            calledBack = true
        }
        XCTAssertTrue(calledBack, "A reply to the current goal is delivered")
        XCTAssertEqual(session.conversation?.messages.last?.content, "old answer")
    }

    /// What the model is told about a command's status: a nonzero exit is a failure, an aborted
    /// command (no status) is described as aborted rather than as a success.
    func testMessageDescribesTheCommandsStatus() {
        let session = ToolCodecierge.Session(UUID().uuidString)
        func message(exitCode: Int32?) -> String {
            session.message(forCommand: TerminalCommand(username: nil,
                                                        hostname: nil,
                                                        directory: nil,
                                                        command: "ls",
                                                        output: "",
                                                        exitCode: exitCode,
                                                        url: URL(string: "iterm2:///command")!))
        }
        XCTAssertFalse(message(exitCode: 0).contains("exit code"))
        XCTAssertFalse(message(exitCode: 0).contains("aborted"))
        XCTAssertTrue(message(exitCode: 2).contains("failed with exit code 2"))
        XCTAssertTrue(message(exitCode: nil).contains("aborted"))
        XCTAssertFalse(message(exitCode: nil).contains("exit code"))
    }

    func testAbortStopsTheSessionItWasAskedAbout() {
        let guid = UUID().uuidString
        let session = ToolCodecierge.Session(guid)
        session.state = .running
        session.running = true
        session.abort()
        XCTAssertFalse(session.running)
        XCTAssertEqual(session.state, .goalSetting)
        XCTAssertEqual(session.commandCount, 0)
        XCTAssertFalse(CommandOutput.hasConsumers(forSessionReferences: [guid]))
    }
}
