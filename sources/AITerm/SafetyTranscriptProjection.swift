//
//  SafetyTranscriptProjection.swift
//  iTerm2SharedARC
//
//  Projects a chat's [Message] history into the [TranscriptEntry] the AI
//  safety classifier consumes, so a command being vetted is judged with the
//  context of what the user actually asked for (the classifier's policy: only
//  a direct, unambiguous user request can override a block).
//
//  Security invariant: assistant free text (markdown prose the untrusted main
//  model wrote) is NEVER projected. TranscriptEntry can't represent it, and
//  this projection won't manufacture it, because such prose could be crafted
//  to argue the classifier into flipping its verdict. Only user input and the
//  agent's proposed tool calls survive - the same shape AutoModeClassifier is
//  designed around.
//
//  Callers cap the result via AutoModeClassifier's count/size budget; this
//  projection does no capping of its own.
//

import Foundation

enum SafetyTranscript {
    static func project(_ messages: [Message]) -> [TranscriptEntry] {
        var out: [TranscriptEntry] = []
        for message in messages {
            switch message.content {
            case .plainText(let text, context: _):
                // Only user-authored text is intent. The context field
                // (terminal state) is deliberately dropped: it's large and may
                // carry secrets that have no place in the safety prompt.
                appendUserText(text, from: message.author, to: &out)

            case .markdown(let text):
                // User messages can be stored as markdown; agent markdown is
                // free prose and must not leak in (the invariant above).
                appendUserText(text, from: message.author, to: &out)

            case .multipart(let subparts, vectorStoreID: _):
                guard message.author == .user else { break }
                let text = subparts.compactMap { subpart -> String? in
                    switch subpart {
                    case .plainText(let s): return s
                    case .markdown(let s): return s
                    case .attachment, .context: return nil
                    }
                }.joined(separator: "\n")
                if !text.isEmpty { out.append(.userText(text)) }

            case .remoteCommandRequest(let payload, safe: _):
                // The agent's proposed tool call, in either mode. Its name and
                // human description are our own rendering of the call, not
                // agent prose, so they're safe to include and are exactly the
                // action context the classifier is designed to weigh.
                out.append(.toolCall(name: payload.name,
                                     input: payload.markdownDescription))

            default:
                // Everything else (agent responses, streaming fragments,
                // permissions, watcher events, system plumbing) has no bearing
                // on user intent and is dropped.
                break
            }
        }
        return out
    }

    private static func appendUserText(_ text: String,
                                       from author: Participant,
                                       to out: inout [TranscriptEntry]) {
        guard author == .user, !text.isEmpty else { return }
        out.append(.userText(text))
    }

    // Recent history for a chat, projected and ready for the safety
    // classifier. Reads the client-side ChatListModel by chatID (MainActor,
    // since that store is main-isolated). Thin glue over the unit-tested
    // `project`; shared by the orchestrator dispatcher and the session-bound
    // ChatAgent so both seed the classifier the same way.
    @MainActor
    static func forChat(_ chatID: String) -> [TranscriptEntry] {
        let messages = ChatListModel.instance?.messages(forChat: chatID,
                                                         createIfNeeded: false)
        return project(messages.map(Array.init) ?? [])
    }
}
