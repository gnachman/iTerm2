//
//  ClaudeCodeModeController.swift
//  iTerm2SharedARC
//

import Foundation

// Detects when Claude Code is running in a session and offers to
// upsell the workgroup feature: a one-time per-session announcement
// asking the user if they'd like to enter the built-in Claude Code
// workgroup (or open Settings to configure their own). Does NOT
// auto-enter — that decision belongs to the user (via the trigger
// system, the menu, or this announcement).
//
// "Claude is running" is the conjunction of two signals:
//   • "claude" appears in the session's foreground-job ancestry
//     chain, per GlobalJobMonitor.
//   • The session has an active tab status (indicator or status
//     text), per SessionStatusController / iTermSessionTabStatus
//     notifications.
//
// The user can dismiss the upsell forever via
// iTermUserDefaults.claudeCodeWorkgroupUpsellSuppressed.
@objc(iTermClaudeCodeModeController)
class ClaudeCodeModeController: NSObject {
    @objc static let instance = ClaudeCodeModeController()

    private static let monitoredJob = "claude"
    private static let announcementIdentifier = "ClaudeCodeWorkgroupUpsell"

    private var claudeSessionGUIDs = Set<String>()
    private var statusSessionGUIDs = Set<String>()

    // Per-session: whether we've already shown the upsell during
    // this app run. Independent of the persistent "suppressed"
    // user default — even without persistence we don't want to
    // re-queue the announcement on every reconcile tick.
    private var shownThisRun = Set<String>()

    private override init() {
        super.init()
        _ = GlobalJobMonitor.instance
        _ = SessionStatusController.instance

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(jobMonitorDidChange(_:)),
            name: GlobalJobMonitor.didChangeNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionStatusDidChange(_:)),
            name: iTermSessionTabStatus.didChangeNotificationName,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWillTerminate(_:)),
            name: NSNotification.Name.iTermSessionWillTerminate,
            object: nil)

        claudeSessionGUIDs = GlobalJobMonitor.instance.sessionGUIDs(runningJob: Self.monitoredJob)
        for session in iTermController.sharedInstance()?.allSessions() ?? [] {
            if let status = session.tabStatus,
               status.hasActiveStatus,
               let guid = session.guid {
                statusSessionGUIDs.insert(guid)
            }
        }
        reconcileAll()
    }

    @objc
    static func start() {
        _ = instance
    }

    // MARK: - Notification handlers

    @objc
    private func jobMonitorDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let job = userInfo[GlobalJobMonitor.jobNameKey] as? String,
              job == Self.monitoredJob,
              let sessions = userInfo[GlobalJobMonitor.sessionGUIDsKey] as? Set<String> else {
            return
        }
        let previous = claudeSessionGUIDs
        claudeSessionGUIDs = sessions
        for guid in previous.symmetricDifference(sessions) {
            reconcile(guid: guid)
        }
    }

    @objc
    private func sessionStatusDidChange(_ notification: Notification) {
        guard let status = notification.object as? iTermSessionTabStatus else {
            return
        }
        let guid = status.sessionID
        let hadStatus = statusSessionGUIDs.contains(guid)
        let hasStatus = status.hasActiveStatus
        if hasStatus == hadStatus {
            return
        }
        if hasStatus {
            statusSessionGUIDs.insert(guid)
        } else {
            statusSessionGUIDs.remove(guid)
        }
        reconcile(guid: guid)
    }

    @objc
    private func sessionWillTerminate(_ notification: Notification) {
        guard let session = notification.object as? PTYSession,
              let guid = session.guid else {
            return
        }
        claudeSessionGUIDs.remove(guid)
        statusSessionGUIDs.remove(guid)
        shownThisRun.remove(guid)
    }

    // MARK: - Upsell

    private func reconcile(guid: String) {
        guard !iTermUserDefaults.claudeCodeWorkgroupUpsellSuppressed else { return }
        guard let session = iTermController.sharedInstance()?.session(withGUID: guid) else {
            return
        }
        // Don't offer to enter a workgroup if there's already one
        // active — the user already has the feature in use here.
        guard session.workgroupInstance == nil else { return }
        let claudeIsRunning = claudeSessionGUIDs.contains(guid) && statusSessionGUIDs.contains(guid)
        guard claudeIsRunning else { return }
        guard !shownThisRun.contains(guid) else { return }
        shownThisRun.insert(guid)
        showAnnouncement(on: session)
    }

    private func reconcileAll() {
        for guid in claudeSessionGUIDs.union(statusSessionGUIDs) {
            reconcile(guid: guid)
        }
    }

    private func showAnnouncement(on session: PTYSession) {
        let title = "Claude Code is running. Want to try the Claude Code integration?."
        let actions = ["Try It Now", "Customize…", "Don't Show Again"]
        let announcement = iTermAnnouncementViewController.announcement(
            withTitle: title,
            style: .kiTermAnnouncementViewStyleQuestion,
            withActions: actions) { [weak session] choice in
                switch choice {
                case 0:
                    if let session {
                        iTermWorkgroupController.instance.enter(
                            workgroupUniqueIdentifier: BuiltinWorkgroups.ID.claudeCode,
                            on: session)
                    }
                case 1:
                    let panel = PreferencePanel.sharedInstance()
                    panel.window?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                case 2:
                    iTermUserDefaults.claudeCodeWorkgroupUpsellSuppressed = true
                default:
                    break
                }
            }
        session.queueAnnouncement(announcement,
                                  identifier: Self.announcementIdentifier)
    }
}
