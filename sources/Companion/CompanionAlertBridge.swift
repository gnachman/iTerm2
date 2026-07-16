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
            RLog("Companion alert: no chat database; dropping alert")
            return
        }
        let record = CompanionAlertRecord(seq: 0,
                                          uniqueID: UUID(),
                                          threadKey: threadKey,
                                          title: title,
                                          body: body,
                                          createdDate: Date())
        guard let seq = db.insertAlert(record) else {
            RLog("Companion alert: failed to persist alert")
            return
        }
        RLog("Companion alert: stored alert seq \(seq) for thread \(threadKey.prefix(8)); notifying wakeup coordinator")
        // An alert IS renderable content (it shows on the lock screen), so it goes
        // through the coordinator's content path: the global rate-limit coalesces it
        // with agent-message activity, and the render check sees it above the alert
        // floor. (Replaces this bridge's former alert-only cooldown.)
        CompanionWakeupCoordinator.shared.noteContentActivity(chatID: "alert:" + threadKey)
    }
}
