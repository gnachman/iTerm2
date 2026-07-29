//
//  SessionNavOpen.swift
//  CompanionCore
//
//  Pure decision for how a reply-notification tap should open a conversation on
//  a navigation stack so it ends up on top exactly once - never as a duplicate.
//  If the chat is already mounted (e.g. it sits below the session view from an
//  @-mention), pop back to it; otherwise push it above the session view.
//

import Foundation

public enum SessionNavOpen {
    public enum Action: Equatable {
        /// Already the sole top entry: nothing to do.
        case noChange
        /// Remove any existing occurrences of the chat (at these indices) and
        /// push it on top, so it ends up on top exactly once with the session
        /// view still BELOW it - satisfying "Back returns to the session view"
        /// without a duplicate entry. An empty removal list is a plain push.
        case moveToTop(removeIndices: [Int])
    }

    /// - conversationIDs: for each stack entry, its conversation id, or nil for a
    ///   non-conversation entry (e.g. a session or workgroup).
    /// - chatID: the conversation being opened.
    public static func action(forOpening chatID: String,
                              in conversationIDs: [String?]) -> Action {
        let occurrences = conversationIDs.enumerated().compactMap { $0.element == chatID ? $0.offset : nil }
        // Already the only entry and on top: don't churn the stack.
        if occurrences == [conversationIDs.count - 1] {
            return .noChange
        }
        return .moveToTop(removeIndices: occurrences)
    }

    /// The conversation the single shared open-chat state should point at for a
    /// stack: its LAST conversation entry, even if a session/workgroup is pushed
    /// above it. That covers the @-mention case (a session view sitting on top of
    /// the conversation it should still echo into), while for a conversation-
    /// topped stack it equals the visible top. nil when the stack holds no
    /// conversation. Used to resync when the selected tab changes so a
    /// conversation co-mounted on the other tab can't keep the shared state.
    public static func activeConversationID(in conversationIDs: [String?]) -> String? {
        conversationIDs.reversed().first(where: { $0 != nil }).flatMap { $0 }
    }
}
