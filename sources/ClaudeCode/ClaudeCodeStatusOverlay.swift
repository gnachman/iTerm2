//
//  ClaudeCodeStatusOverlay.swift
//  iTerm2SharedARC
//
//  Claude Code reports its own status through the Program Status Protocol (OSC 7501), and its
//  hook (`it2 handle-agent-hook`) knows things the reports leave out. While both are present
//  neither writes the tab status: the report is the base, the hook's writes are kept only as
//  facts, and this decides what the two add up to. It is a pure function of both, so the answer
//  does not depend on which arrived first, and with no facts it is the report unchanged.
//

import Foundation

/// What the Claude Code hook has said about a session, kept apart from what is displayed.
struct ClaudeCodeHookFacts: Equatable {
    /// Whether the session's own turn is open, or nil when the hook has not said.
    var turnOpen: Bool?
    /// Background agents and shells the hook last counted as still running.
    var backgroundTasks: Int
    /// The last message of the most recent turn the hook saw end, until the next turn opens.
    var lastMessage: String?

    static let none = ClaudeCodeHookFacts(turnOpen: nil, backgroundTasks: 0, lastMessage: nil)
}

enum ClaudeCodeStatusOverlay {
    enum Resolution: Equatable {
        /// Show what Claude Code reported.
        case asReported
        /// The turn is over, so the session will take input, but work it started is still
        /// running. Claude Code has no state for this: with background agents it goes on saying
        /// working, and with background shells it says done.
        case background(count: Int)
        /// Show the reported state with this detail: the last message of the turn that ended.
        /// Claude Code's done carries no message.
        case detail(String)
    }

    /// The detail line for background. Localization unneeded: this is word for word what the
    /// hook writes when it drives the status by itself (AgentHookDetail.backgroundDetail in it2,
    /// which is not localized), so the tab reads the same whichever is driving.
    static func backgroundDetail(count: Int) -> String {
        return count == 1 ? "1 background task running" : "\(count) background tasks running"
    }

    /// - Parameters:
    ///   - state: The state of the record that would be shown.
    ///   - isRoot: Whether that record is Claude Code's own, as opposed to one of its agents'.
    ///   - hasMessage: Whether that record carries a message (msg) of its own.
    static func resolve(state: ProgramStatusReport.State,
                        isRoot: Bool,
                        hasMessage: Bool,
                        facts: ClaudeCodeHookFacts) -> Resolution {
        switch state {
        case .blocked, .error:
            // Whatever needs the user is never covered.
            return .asReported
        case .clear:
            // Not a state a record is ever in; a clear removes the record.
            return .asReported
        case .working, .done, .idle:
            break
        }
        // Unknown is not closed: a turn the hook has said nothing about is Claude Code's to
        // describe. Everything the hook adds is about a turn it saw end.
        guard facts.turnOpen == false else {
            return .asReported
        }
        if facts.backgroundTasks > 0 {
            // This describes the session, whichever of its records is the most urgent.
            return .background(count: facts.backgroundTasks)
        }
        // The message is the session's own turn's, so only its own record takes it. Done turns
        // idle once the user has seen the result, and the message stays with it, as it does
        // when the hook drives alone.
        if state == .done || state == .idle, isRoot, !hasMessage, let message = facts.lastMessage, !message.isEmpty {
            return .detail(message)
        }
        return .asReported
    }
}
