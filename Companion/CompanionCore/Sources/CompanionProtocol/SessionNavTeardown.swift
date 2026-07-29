//
//  SessionNavTeardown.swift
//  CompanionCore
//
//  Pure rule for tearing down a conversation's shared state when it is popped
//  off a navigation stack. The app has two navigation stacks (one per tab) and
//  a SINGLE shared open-conversation/subscription state, and a conversation can
//  be mounted on both stacks at once (a reply-notification tap can push one onto
//  the sessions stack while another is open on the chats stack). So a chat must
//  only be unsubscribed / cleared once its LAST mount is gone across BOTH stacks
//  - never just because one stack lost it.
//

import Foundation

public enum SessionNavTeardown {
    /// Which conversation ids are now fully unmounted (and so should be
    /// unsubscribed / have their shared open state cleared) after a change to
    /// one navigation stack.
    ///
    /// - before: conversation ids in the changed stack before the change.
    /// - after: conversation ids in the changed stack after the change.
    /// - otherStack: conversation ids currently in the OTHER stack.
    ///
    /// A chat still present in the changed stack (a duplicate entry) or in the
    /// other stack is retained.
    public static func fullyRemoved(before: Set<String>,
                                    after: Set<String>,
                                    otherStack: Set<String>) -> Set<String> {
        before.subtracting(after).subtracting(otherStack)
    }
}
