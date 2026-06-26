//
//  CompanionAlertBridge.swift
//  iTerm2
//
//  The single entry point the desktop's alert sources (the "Post Notification"
//  trigger and "alert on next mark") call to also notify the paired phone. It
//  persists the alert in the chat DB's CompanionAlert table (giving it a global
//  alert seq) and fires one content-free wakeup; the phone's NSE then fetches the
//  alert over Noise via the unified syncSince. Gated so it is a no-op unless a
//  revision-2 phone is paired and can be notified.
//
//  ObjC-facing (@objc) so PTYSession.m can call it directly with full session
//  context. Main-actor: its callers (screenDidAddMark, the trigger side effect)
//  run on the main thread.
//

import Foundation

@MainActor
@objc(iTermCompanionAlertBridge)
final class CompanionAlertBridge: NSObject {
    /// Coalesce a burst of alerts (e.g. several triggers firing at once) into few
    /// wakeups: the wakeup is content-free and the NSE fetches EVERY new alert, so
    /// one trailing wakeup after a burst covers them all.
    private static let coalesceInterval: TimeInterval = 2
    private static var cooldownActive = false
    private static var pendingTrailing = false

    /// Whether the desktop should even offer "send to phone" right now: a
    /// revision-2 phone is paired and a notification could be delivered. The UI
    /// gates its controls on this (ObjC-callable).
    @objc static var canSendToPhone: Bool {
        CompanionPushRegistry.canSendAlertsToPhone
    }

    /// Persist a terminal alert and nudge the phone. `threadKey` groups a session's
    /// alerts on the phone (today the session guid). A no-op when no eligible phone
    /// is paired.
    @objc static func postTerminalAlert(title: String, body: String, threadKey: String) {
        guard CompanionPushRegistry.canSendAlertsToPhone else {
            return
        }
        guard let db = ChatDatabase.instance else {
            DLog("Companion alert: no chat database; dropping alert")
            return
        }
        let record = CompanionAlertRecord(seq: 0,
                                          uniqueID: UUID(),
                                          threadKey: threadKey,
                                          title: title,
                                          body: body,
                                          createdDate: Date())
        guard db.insertAlert(record) != nil else {
            DLog("Companion alert: failed to persist alert")
            return
        }
        DLog("Companion alert: stored alert for thread \(threadKey.prefix(8)); scheduling wakeup")
        scheduleWakeup()
    }

    /// Fire a wakeup immediately when idle; if more alerts arrive during the
    /// cooldown, fire exactly one trailing wakeup afterward (which fetches all of
    /// them), repeating while the burst continues.
    private static func scheduleWakeup() {
        if cooldownActive {
            pendingTrailing = true
            return
        }
        cooldownActive = true
        CompanionPushSender.dispatchPush(chatID: nil)
        armCooldown()
    }

    private static func armCooldown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + coalesceInterval) {
            if pendingTrailing {
                pendingTrailing = false
                CompanionPushSender.dispatchPush(chatID: nil)
                armCooldown()
            } else {
                cooldownActive = false
            }
        }
    }
}
