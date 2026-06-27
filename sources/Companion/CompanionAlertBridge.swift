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

    /// Whether the "send to phone" checkbox should be enabled: a revision-2 phone
    /// is paired. Notification permission is NOT required - enabling it requests it.
    @objc static var canEnableAlertsToPhone: Bool {
        CompanionPushRegistry.canEnableAlertsToPhone
    }

    /// A short, always-present status line shown UNDER the checkbox to guide the
    /// user to a working setup. Covers each step (pair -> open/update the app ->
    /// allow notifications) and confirms when it is ready, since the checkbox's
    /// enabled state alone no longer conveys the notification-permission step.
    @objc static var sendToPhoneStatusMessage: String {
        if !CompanionPushRegistry.devicePaired {
            return "Pair an iPhone running iTerm2 Buddy to use this."
        }
        if !CompanionPushRegistry.supportsContentlessWakeup {
            // Either the phone hasn't connected since pairing (so its revision isn't
            // known yet) or it is too old for terminal alerts.
            return "Open iTerm2 Buddy on your paired iPhone (update it if needed)."
        }
        switch CompanionPushRegistry.authorization {
        case .authorized:
            return "Alerts will be delivered to your paired iPhone."
        case .denied:
            return "Turn on notifications for iTerm2 Buddy in iOS Settings."
        case .notDetermined:
            return "Turn this on to allow notifications on your iPhone."
        }
    }

    /// Called when the user turns ON "send alerts to my iPhone". Requests
    /// notification permission from the phone now (if connected) or on its next
    /// connection. Until permission is granted, postTerminalAlert simply won't
    /// push - the control is enabled regardless so opting in can drive the prompt.
    @objc static func userEnabledAlertsToPhone() {
        CompanionPairingController.shared.requestPushPermissionForAlerts()
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
