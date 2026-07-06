//
//  CompanionChatMuteRegistry.swift
//  iTerm2
//
//  The set of chats the phone's user has muted, reported over the companion
//  protocol (.setChatMuted) and persisted here because the mac is the side
//  that decides whether to push, possibly while the phone is unreachable. The
//  agent-activity notifier skips muted chats (no wakeup fires for them) and
//  the syncSince responder omits their messages (a wakeup fired for another
//  chat must not surface a muted chat's messages on the lock screen).
//  Destroyed with the rest of the pairing state on unpair.
//

import Foundation

@MainActor
enum CompanionChatMuteRegistry {
    // NoSync: device-local state tied to the paired phone, not configuration.
    private static let mutedChatIDsKey = "NoSyncCompanionMutedChatIDs"

    static var mutedChatIDs: Set<String> {
        Set(iTermUserDefaults.userDefaults().stringArray(forKey: mutedChatIDsKey) ?? [])
    }

    static func isMuted(chatID: String) -> Bool {
        mutedChatIDs.contains(chatID)
    }

    static func setMuted(_ muted: Bool, chatID: String) {
        var ids = mutedChatIDs
        if muted {
            ids.insert(chatID)
        } else {
            ids.remove(chatID)
        }
        store(ids)
        RLog("Companion mute: \(muted ? "muted" : "unmuted") chat \(chatID) (\(ids.count) muted)")
    }

    /// The chat is gone; its mute entry must not linger (a recreated chat with
    /// a recycled id would inherit it).
    static func forget(chatID: String) {
        var ids = mutedChatIDs
        guard ids.remove(chatID) != nil else { return }
        store(ids)
    }

    /// Called on unpair: mute state is the paired phone's preference, so a
    /// fresh pairing starts with nothing muted.
    static func clear() {
        iTermUserDefaults.userDefaults().removeObject(forKey: mutedChatIDsKey)
    }

    private static func store(_ ids: Set<String>) {
        iTermUserDefaults.userDefaults().set(ids.sorted(), forKey: mutedChatIDsKey)
    }
}
