//
//  ClaudeCodeModeController.swift
//  iTerm2SharedARC
//

import Foundation

// Keeps each PTYSession's claudeCodeModeEnabled flag synchronized with two
// signals:
//   • "claude" is in the session's foreground-job ancestry chain, per
//     GlobalJobMonitor.
//   • The session has an active tab status (indicator or status text), per
//     SessionStatusController / iTermSessionTabStatus notifications.
//
// The flag is YES iff both signals are true.
@objc(iTermClaudeCodeModeController)
class ClaudeCodeModeController: NSObject {
    @objc static let instance = ClaudeCodeModeController()

    private static let monitoredJob = "claude"

    // Sessions with "claude" in their foreground-job ancestry.
    private var claudeSessionGUIDs = Set<String>()

    // Sessions with an active (non-empty) tab status.
    private var statusSessionGUIDs = Set<String>()

    private override init() {
        super.init()

        // Ensure upstream singletons are running so we receive notifications.
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

        // Seed state from what's already tracked.
        claudeSessionGUIDs = GlobalJobMonitor.instance.sessionGUIDs(runningJob: Self.monitoredJob)
        for session in iTermController.sharedInstance()?.allSessions() ?? [] {
            if let status = session.tabStatus, status.hasActiveStatus, let guid = session.guid {
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
    }

    // MARK: - Reconciliation

    private func reconcile(guid: String) {
        guard let session = iTermController.sharedInstance()?.session(withGUID: guid) else {
            return
        }
        let shouldEnable = claudeSessionGUIDs.contains(guid) && statusSessionGUIDs.contains(guid)
        let isActive =
            iTermWorkgroupController.instance.workgroupInstance(on: session)?
                .workgroupUniqueIdentifier == BuiltinWorkgroups.ID.claudeCode
        if shouldEnable && !isActive {
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: BuiltinWorkgroups.ID.claudeCode,
                on: session)
        } else if !shouldEnable && isActive {
            iTermWorkgroupController.instance.exit(on: session)
        }
    }

    private func reconcileAll() {
        for guid in claudeSessionGUIDs.union(statusSessionGUIDs) {
            reconcile(guid: guid)
        }
    }
}
