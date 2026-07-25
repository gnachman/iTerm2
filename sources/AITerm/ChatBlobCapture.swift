//
//  ChatBlobCapture.swift
//  iTerm2
//
//  Turns a chat's reconstructed [LLM.Message] history into stored per-round
//  ChatBlobs. Called at the true end of an agent turn (success, no tool call
//  outstanding), on the whole reconstructed history: it splits the history into
//  rounds and freezes any round not already stored, so it is both the normal
//  incremental capture (a blob-native chat freezes only the new round) and the
//  one-shot migration (a legacy chat with no blobs freezes its whole history) via
//  the SAME path. Idempotent: re-running captures nothing new.
//
//  Why the whole history rather than a delta of the live conversation: the
//  intermediate tool-loop items (assistant preamble, tool_use, tool_result) do
//  not survive on AIConversation.messages (only the final assistant message is
//  appended there); they persist only as display-log Messages, so the faithful
//  round is reconstructed from those via the same translate/aiMessagesForStructuredReplay
//  the reload path uses, and encodeRound's per-vendor coalescing folds the split
//  assistant preamble + tool_use back into one wire message.
//

import Foundation

enum ChatBlobCapture {
    /// Split a chat's reconstructed messages into rounds. A round begins at each
    /// user message and runs through the agent turn that follows it (every novel
    /// agent/tool item until the next user message). This is the unit one ChatBlob
    /// freezes. A leading non-user message (should not happen for a real chat)
    /// opens the first round so nothing is dropped.
    static func rounds(from messages: [LLM.Message]) -> [[LLM.Message]] {
        var result: [[LLM.Message]] = []
        for message in messages {
            if message.role == .user || result.isEmpty {
                result.append([message])
            } else {
                result[result.count - 1].append(message)
            }
        }
        return result
    }

    /// Freeze any rounds of `allMessages` not yet stored as blobs for `chatID`,
    /// appending them in order. Incremental and idempotent: with N rounds already
    /// stored (one blob per round) only rounds N.. are frozen. Returns the number
    /// of blobs appended (0 if nothing new). The caller stamps Chat.blobProtocol
    /// after the first successful capture (this function does not touch the Chat
    /// row).
    ///
    /// On an encode failure it stops rather than skipping a round, so the stored
    /// sequence never gets a hole; the un-captured tail is retried on the next turn.
    ///
    /// PRECONDITION: a blob is only replayable under the protocol it was frozen
    /// for, so on a protocol switch (the chat's bound model/provider changed mid
    /// conversation) the caller MUST re-freeze the whole history via
    /// ChatDatabase.replaceBlobs BEFORE calling this. This function defends the
    /// invariant anyway: if the chat already has blobs under a different protocol
    /// it refuses (returns 0) rather than append a mixed, unreplayable sequence.
    @discardableResult
    static func captureNewRounds(chatID: String,
                                 allMessages: [LLM.Message],
                                 api: iTermAIAPI,
                                 modelName: String?,
                                 hostedTools: HostedTools,
                                 database: ChatDatabase) -> Int {
        // Row count (not decoded-blob count): O(1)-ish and robust to rows this
        // build can't decode (a newer protocol), which would otherwise undercount
        // and re-freeze already-stored rounds.
        let existing = database.blobCount(inChat: chatID)
        if existing > 0 {
            let stored = database.storedBlobProtocol(inChat: chatID)
            if stored != Int(api.rawValue) {
                RLog("ChatBlobCapture: protocol mismatch for chat \(chatID): stored=\(String(describing: stored)) new=\(api.rawValue); refusing to append (a protocol switch must go through replaceBlobs)")
                return 0
            }
        }
        let allRounds = rounds(from: allMessages)
        guard allRounds.count > existing else {
            return 0
        }
        var appended = 0
        for round in allRounds[existing...] {
            let payload: Data
            do {
                payload = try ChatBlobWireEncoder.encodeRound(round, api: api,
                                                              modelName: modelName,
                                                              hostedTools: hostedTools)
            } catch {
                RLog("ChatBlobCapture: encodeRound failed for chat \(chatID) api \(api.rawValue): \(error); stopping to avoid a gap")
                return appended
            }
            // The round's server response id (Responses API fast path), if any:
            // the last message that carries one.
            let responseID = round.reversed().first { $0.responseID != nil }?.responseID
            let blob = ChatBlob(chatID: chatID,
                                blobProtocol: api,
                                role: .user,  // a round leads with a user message
                                payload: payload,
                                responseID: responseID)
            if database.appendBlob(blob) != nil {
                appended += 1
            } else {
                // A write failure would also gap the sequence; stop here.
                RLog("ChatBlobCapture: appendBlob failed for chat \(chatID); stopping")
                return appended
            }
        }
        return appended
    }
}
