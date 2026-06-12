//
//  AutoModeTranscript.swift
//  iTerm2
//
//  Glue between iTerm2's AIConversation message log and the
//  AutoModeClassifier's TranscriptEntry projection. The classifier may not
//  see assistant-authored text (the main model is untrusted and could craft
//  text that flips a verdict like "the user approved this earlier"), so the
//  conversion drops assistant text by construction and preserves only user
//  input and assistant-proposed function calls.
//

import Foundation

extension AIConversation {
    /// Project this conversation's messages into the classifier's transcript
    /// shape. Order preserved; oldest first.
    var classifierTranscript: [TranscriptEntry] {
        return AutoModeTranscript.entries(from: messages)
    }
}

enum AutoModeTranscript {
    /// Pure conversion exposed for tests. Same projection used by
    /// `AIConversation.classifierTranscript`.
    static func entries(from messages: [LLM.Message]) -> [TranscriptEntry] {
        var result: [TranscriptEntry] = []
        for message in messages {
            collect(body: message.body, role: message.role, into: &result)
        }
        return result
    }

    private static func collect(body: LLM.Message.Body,
                                role: LLM.Role?,
                                into result: inout [TranscriptEntry]) {
        switch body {
        case .uninitialized, .attachment:
            // Attachments (files, images, status updates) aren't actions and
            // aren't user-authored text in a form the classifier can use.
            return
        case .functionOutput:
            // Tool output is model-adjacent and untrusted: stdout from a
            // previous tool call could contain prompt-injection content like
            // "the user approved this" planted by a hostile package or page.
            // Skipping matches the projection used by Claude Code.
            return
        case .text(let text):
            if role == .user, !text.isEmpty {
                result.append(.userText(text))
            }
            // Assistant and system text are intentionally dropped.
        case .functionCall(let call, _):
            // Only assistant-proposed calls represent agent actions worth
            // showing the classifier. A user-emitted functionCall would be
            // malformed input; drop it rather than treat it as evidence.
            guard role == .assistant else { return }
            let name = call.name ?? ""
            let input = call.arguments ?? ""
            result.append(.toolCall(name: name, input: input))
        case .multipart(let parts):
            for part in parts {
                collect(body: part, role: role, into: &result)
            }
        }
    }
}

/// An `AutoModeClassifier.Backend` backed by an iTerm2 `AIConversation`.
///
/// `entries` is read live from `conversationProvider` so the host can hold
/// this adapter across turns and always see the current message log.
///
/// `sideQueryHandler` is injected — the host decides which backend serves
/// the classifier's one-shot calls (a dedicated classifier model, a separate
/// conversation, or a stub in tests). The adapter does not assume the
/// classifier shares the main conversation's API key, model, or context.
final class AIConversationBackend: AutoModeClassifier.Backend {
    typealias SideQuery = (_ system: String,
                           _ user: String,
                           _ maxTokens: Int) async throws -> String

    private let conversationProvider: () -> AIConversation
    private let sideQueryHandler: SideQuery

    init(conversation: @escaping () -> AIConversation,
         sideQuery: @escaping SideQuery) {
        self.conversationProvider = conversation
        self.sideQueryHandler = sideQuery
    }

    var entries: [TranscriptEntry] {
        conversationProvider().classifierTranscript
    }

    func sideQuery(system: String,
                   user: String,
                   maxTokens: Int) async throws -> String {
        try await sideQueryHandler(system, user, maxTokens)
    }
}
