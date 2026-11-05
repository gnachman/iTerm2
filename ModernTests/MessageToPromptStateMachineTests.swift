//
//  MessageToPromptStateMachineTests.swift
//  iTerm2
//
//  Created by George Nachman on 11/5/26.
//

import XCTest
@testable import iTerm2SharedARC

/// The prompt built for a terminal command sent to AI Chat.
final class MessageToPromptStateMachineTests: XCTestCase {
    private func prompt(exitCode: Int32?) -> String {
        let command = TerminalCommand(username: nil,
                                      hostname: nil,
                                      directory: nil,
                                      command: "ls",
                                      output: "",
                                      exitCode: exitCode,
                                      url: URL(string: "iterm2:///command")!)
        return MessageToPromptStateMachine().prompt(terminalCommand: command)
    }

    func testExitedCommandReportsItsStatus() {
        XCTAssertTrue(prompt(exitCode: 3).contains("The exit status of the command was 3"))
    }

    /// An aborted command has no status. Reporting 0 would call it a success.
    func testAbortedCommandIsDescribedAsAborted() {
        let text = prompt(exitCode: nil)
        XCTAssertTrue(text.contains("aborted"))
        XCTAssertFalse(text.contains("exit status of the command was"))
    }
}
