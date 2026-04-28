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
// "Claude is running" is just the GlobalJobMonitor signal: "claude"
// appears in the session's foreground-job ancestry. We deliberately
// don't gate on tab status / iTermSessionTabStatus, because the
// thing that drives that status is the cc-status hook — and that
// hook only exists after the user has opted into the integration.
// Requiring it would mean a fresh user could never see the upsell.
//
// The user can dismiss the upsell forever via
// iTermUserDefaults.claudeCodeWorkgroupUpsellSuppressed.
@objc(iTermClaudeCodeModeController)
class ClaudeCodeModeController: NSObject {
    @objc static let instance = ClaudeCodeModeController()

    private static let monitoredJob = "claude"
    private static let announcementIdentifier = "ClaudeCodeWorkgroupUpsell"

    private var claudeSessionGUIDs = Set<String>()

    // Per-session: whether we've already shown the upsell during
    // this app run. Independent of the persistent "suppressed"
    // user default — even without persistence we don't want to
    // re-queue the announcement on every reconcile tick.
    private var shownThisRun = Set<String>()

    // Sessions whose CC workgroup was entered via the upsell's "Try
    // It Now" button. We hold these so we can auto-exit the
    // workgroup when claude leaves the foreground — that's the
    // implicit contract of the trial: enters with claude, leaves
    // with claude. Sessions where the user installed CC mode the
    // long way (triggers, menu, future "install CC mode" action)
    // aren't in this set, so this controller stays out of their
    // lifecycle and lets the user's own Exit Workgroup trigger /
    // menu handle it.
    private var trialSessionGUIDs = Set<String>()

    private override init() {
        super.init()
        _ = GlobalJobMonitor.instance

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(jobMonitorDidChange(_:)),
            name: GlobalJobMonitor.didChangeNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWillTerminate(_:)),
            name: NSNotification.Name.iTermSessionWillTerminate,
            object: nil)

        claudeSessionGUIDs = GlobalJobMonitor.instance.sessionGUIDs(runningJob: Self.monitoredJob)
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
            let claudeLeft = previous.contains(guid) && !sessions.contains(guid)
            if claudeLeft {
                // Clear the "already prompted" flag so the next
                // claude launch in this session can re-show the
                // upsell. Without this, anyone who saw the upsell
                // once (took the trial or dismissed it) would never
                // see it again until they closed the terminal.
                shownThisRun.remove(guid)
                // If the upsell is currently visible (or queued)
                // for this session, drop it: the offer to "try
                // Claude Code" while claude isn't running is
                // confusing.
                if let session = iTermController.sharedInstance()?.session(withGUID: guid) {
                    session.dismissAnnouncement(withIdentifier: Self.announcementIdentifier)
                }
                // If the workgroup was a trial entry, auto-exit it.
                // Doing this BEFORE reconcile means a hypothetical
                // "claude restarts immediately" race doesn't keep
                // the trial flag dangling on the next entry.
                autoExitTrialWorkgroupIfNeeded(guid: guid)
            }
            reconcile(guid: guid)
        }
    }

    @objc
    private func sessionWillTerminate(_ notification: Notification) {
        guard let session = notification.object as? PTYSession,
              let guid = session.guid else {
            return
        }
        claudeSessionGUIDs.remove(guid)
        shownThisRun.remove(guid)
        trialSessionGUIDs.remove(guid)
    }

    // Pulled out to keep jobMonitorDidChange readable. The active-
    // workgroup check guards against the user manually swapping the
    // session into a different workgroup mid-trial — we'd otherwise
    // tear down their replacement workgroup when claude exited.
    private func autoExitTrialWorkgroupIfNeeded(guid: String) {
        guard trialSessionGUIDs.remove(guid) != nil else { return }
        guard let session = iTermController.sharedInstance()?.session(withGUID: guid) else {
            return
        }
        guard let instance = session.workgroupInstance,
              instance.workgroupUniqueIdentifier == ClaudeCodeWorkgroupTemplate.ID.workgroup else {
            return
        }
        iTermWorkgroupController.instance.exit(on: session)
    }

    // MARK: - Upsell

    private func reconcile(guid: String) {
        guard !iTermUserDefaults.claudeCodeWorkgroupUpsellSuppressed else { return }
        // The upsell is an introduction to the feature. Once the user
        // has the workgroup in their config (via the installer, or via a
        // prior Try It Now), they've adopted it — don't keep nagging
        // when the trigger hasn't auto-entered yet, or when claude
        // started in a profile without the trigger installed. They
        // already know the workgroup exists; let them enter it the
        // way they've configured (trigger, menu, manual).
        guard !ClaudeCodeOnboarding.workgroupAlreadyInstalled() else { return }
        guard let session = iTermController.sharedInstance()?.session(withGUID: guid) else {
            return
        }
        // Don't offer to enter a workgroup if there's already one
        // active — the user already has the feature in use here.
        guard session.workgroupInstance == nil else { return }
        guard claudeSessionGUIDs.contains(guid) else { return }
        guard !shownThisRun.contains(guid) else { return }
        shownThisRun.insert(guid)
        showAnnouncement(on: session)
    }

    private func reconcileAll() {
        for guid in claudeSessionGUIDs {
            reconcile(guid: guid)
        }
    }

    private func showAnnouncement(on session: PTYSession) {
        let title = "Claude Code is running. Want to try the Claude Code integration?"
        let actions = ["Try It Now", "Don't Show Again"]
        let announcement = iTermAnnouncementViewController.announcement(
            withTitle: title,
            style: .kiTermAnnouncementViewStyleQuestion,
            withActions: actions) { [weak self, weak session] choice in
                switch choice {
                case 0:
                    if let session, let guid = session.guid {
                        // Tag the session as a trial entry BEFORE
                        // entering — the entry path is synchronous,
                        // but a paranoid order keeps the auto-exit
                        // contract clear (in the set means we own it).
                        self?.trialSessionGUIDs.insert(guid)
                        // The workgroup lives in user data now (no
                        // built-ins). Install it if missing so the
                        // trial works the first time someone clicks
                        // Try It Now without going through the installer.
                        ClaudeCodeOnboarding.installWorkgroupIfNeeded()
                        iTermWorkgroupController.instance.enter(
                            workgroupUniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.workgroup,
                            on: session)
                        // First-time trial users almost certainly
                        // want the cc-status hook so Claude's state
                        // appears in the toolbelt — open the installer
                        // directly instead of nagging with a second
                        // announcement. Skip when hooks are already
                        // installed; the installer would have nothing
                        // to add. Deferred so the upsell's dismiss
                        // animation and the workgroup-entry UI
                        // churn settle before the installer takes key.
                        if !ClaudeCodeOnboarding.hooksAlreadyInstalled() {
                            DispatchQueue.main.async {
                                ClaudeCodeOnboarding.show()
                            }
                        }
                    }
                case 1:
                    iTermUserDefaults.claudeCodeWorkgroupUpsellSuppressed = true
                default:
                    break
                }
            }
        session.queueAnnouncement(announcement,
                                  identifier: Self.announcementIdentifier)
    }

}
