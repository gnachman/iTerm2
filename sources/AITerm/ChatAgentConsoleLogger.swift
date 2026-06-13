//
//  ChatAgentConsoleLogger.swift
//  iTerm2SharedARC
//
//  Optional developer-only trace of chat-agent traffic to the system
//  console. Buffers streaming chunks so the per-turn entries read as
//  coherent units interleaved chronologically with tool dispatch
//  rather than per-stream-chunk noise. Off by default; toggle via
//  the advanced setting "aiChatVerboseConsoleLogging".
//
//  Not coupled to orchestration mode: any chat agent can produce
//  these traces, useful for debugging session-bound tool calls too.
//
//  Uses NSFuckingLog (not NSLog) so long agent replies aren't
//  truncated by the system console pipe.
//
//  Lifetime: one instance per ChatAgent; the agent owns it and
//  routes its three logging touchpoints through:
//      - logUserMessage(_:)            (just before the LLM round-trip)
//      - appendStreamChunk(_:)         (streaming text from the LLM)
//      - logAgentReply(fallback:isError:)  (at turn completion)
//      - flushPendingAgentText()       (called by callers before
//        tool-dispatch entries so prefix text lands first)
//

import Foundation

@MainActor
final class ChatAgentConsoleLogger {
    private let chatID: String
    private var pendingAgentText: String = ""
    private var loggedAnyAgentText: Bool = false

    init(chatID: String) {
        self.chatID = chatID
    }

    var isEnabled: Bool {
        return iTermAdvancedSettingsModel.aiChatVerboseConsoleLogging()
    }

    // Reset per-turn state and emit the "→ user:" entry. Call at the
    // start of every LLM round-trip the agent issues.
    func beginTurn(userBody: String) {
        guard isEnabled else { return }
        pendingAgentText = ""
        loggedAnyAgentText = false
        NSFuckingLog("[ChatAgent %@] → user: %@", chatID,
                     ChatAgentConsoleLogger.snippet(of: userBody))
    }

    // Append a streaming chunk to the pending buffer.
    func appendStreamChunk(_ chunk: String) {
        guard isEnabled else { return }
        pendingAgentText += chunk
    }

    // Emit any buffered agent text as an "← agent:" entry. Called
    // before each tool-dispatch entry so the buffered prefix lands
    // first, preserving chronological order in the log.
    func flushPendingAgentText() {
        guard isEnabled, !pendingAgentText.isEmpty else { return }
        NSFuckingLog("[ChatAgent %@] ← agent: %@", chatID,
                     ChatAgentConsoleLogger.snippet(of: pendingAgentText))
        loggedAnyAgentText = true
        pendingAgentText = ""
    }

    // Emit a final "← agent:" entry at turn completion if streaming
    // didn't already produce one. Pass the last assistant body as
    // `fallbackText` for the non-streaming path.
    func logAgentReply(fallbackText: String) {
        guard isEnabled else { return }
        flushPendingAgentText()
        if !loggedAnyAgentText, !fallbackText.isEmpty {
            NSFuckingLog("[ChatAgent %@] ← agent: %@", chatID,
                         ChatAgentConsoleLogger.snippet(of: fallbackText))
        }
    }

    // Emit an error entry at turn completion.
    func logAgentError(_ description: String) {
        guard isEnabled else { return }
        NSFuckingLog("[ChatAgent %@] ← agent ERROR: %@", chatID, description)
    }

    // Tool-call entries. Direction is "→" for the outbound request
    // and "←" for the response; name is the tool name; body is the
    // args (request) or result (response) string.
    enum ToolDirection {
        case request
        case response
    }

    func logTool(_ direction: ToolDirection, name: String, body: String) {
        guard isEnabled else { return }
        let arrow: String
        switch direction {
        case .request:  arrow = "→"
        case .response: arrow = "←"
        }
        NSFuckingLog("[ChatAgent %@] %@ tool %@ %@", chatID, arrow, name,
                     ChatAgentConsoleLogger.snippet(of: body))
    }

    // Truncate to a console-friendly length so a single huge tool
    // result doesn't blow up the log. NSFuckingLog avoids the system
    // console pipe truncation, but the snippet here is for human
    // readability — the full payload is in the broker history.
    static func snippet(of string: String, maxLength: Int = 4096) -> String {
        let collapsed = string.replacingOccurrences(of: "\n", with: "\\n")
        if collapsed.count <= maxLength {
            return collapsed
        }
        let head = String(collapsed.prefix(maxLength))
        return "\(head)... (\(collapsed.count - maxLength) more chars)"
    }
}
