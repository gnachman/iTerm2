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
// We do wait until the run of claude looks like an interactive
// session, judged by its command line and its tty's mode (see
// ClaudeInteractivityPolicy), so `claude -p` and the like don't
// trigger it.
//
// The user can dismiss the upsell forever via
// iTermUserDefaults.claudeCodeWorkgroupUpsellSuppressed.
@objc(iTermClaudeCodeModeController)
class ClaudeCodeModeController: NSObject {
    @objc static let instance = ClaudeCodeModeController()

    private static let monitoredJob = "claude"
    private static let announcementIdentifier = "ClaudeCodeWorkgroupUpsell"

    // One run of claude in a session that we haven't yet decided is an
    // interactive Claude Code session. Non-interactive runs (`claude -p`,
    // `claude plugin list`, possibly from a script) don't get the upsell.
    // See ClaudeInteractivityPolicy.
    private final class PendingCheck {
        let startTime = ProcessInfo.processInfo.systemUptime
        let ttyModeReader: ClaudeTTYModeReading
        var workItem: DispatchWorkItem?
        private(set) var cancelled = false

        init(ttyModeReader: ClaudeTTYModeReading) {
            self.ttyModeReader = ttyModeReader
        }

        var elapsed: TimeInterval {
            ProcessInfo.processInfo.systemUptime - startTime
        }

        // A tmux tty read may still be outstanding; its reply sees this.
        func cancel() {
            cancelled = true
            workItem?.cancel()
        }
    }

    // Per-session pending check, started when claude arrives and
    // cancelled when it leaves before we decide.
    private var pendingChecks = [String: PendingCheck]()

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
                pendingChecks.removeValue(forKey: guid)?.cancel()
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
            } else {
                startChecking(guid: guid)
            }
        }
    }

    @objc
    private func sessionWillTerminate(_ notification: Notification) {
        guard let session = notification.object as? PTYSession else {
            return
        }
        let guid = session.guid
        claudeSessionGUIDs.remove(guid)
        shownThisRun.remove(guid)
        trialSessionGUIDs.remove(guid)
        pendingChecks.removeValue(forKey: guid)?.cancel()
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

    // The session to show the upsell on, or nil if it shouldn't be shown
    // there now, whether or not claude turns out to be interactive.
    private func sessionEligibleForUpsell(guid: String) -> PTYSession? {
        guard !iTermUserDefaults.claudeCodeWorkgroupUpsellSuppressed else { return nil }
        // The upsell is an introduction to the feature. Once the user
        // has the workgroup in their config (via the installer, or via a
        // prior Try It Now), they've adopted it — don't keep nagging
        // when the trigger hasn't auto-entered yet, or when claude
        // started in a profile without the trigger installed. They
        // already know the workgroup exists; let them enter it the
        // way they've configured (trigger, menu, manual).
        guard !ClaudeCodeOnboarding.workgroupAlreadyInstalled() else { return nil }
        guard let session = iTermController.sharedInstance()?.session(withGUID: guid) else {
            return nil
        }
        // Don't offer to enter a workgroup if there's already one
        // active — the user already has the feature in use here.
        guard session.workgroupInstance == nil else { return nil }
        guard claudeSessionGUIDs.contains(guid) else { return nil }
        guard !shownThisRun.contains(guid) else { return nil }
        return session
    }

    private func reconcile(guid: String) {
        guard let session = sessionEligibleForUpsell(guid: guid) else { return }
        shownThisRun.insert(guid)
        showAnnouncement(on: session)
    }

    private func reconcileAll() {
        for guid in claudeSessionGUIDs {
            startChecking(guid: guid)
        }
    }

    // Starts deciding whether this run of claude is an interactive
    // session, and reconciles once it is. Cancelling on exit keeps a
    // quick exit-then-relaunch from inheriting the first run's check.
    private func startChecking(guid: String) {
        pendingChecks.removeValue(forKey: guid)?.cancel()
        // Skip the checks, which for a tmux pane run a command on the
        // server's host, when the answer couldn't change anything.
        guard let session = sessionEligibleForUpsell(guid: guid) else { return }
        let check = PendingCheck(ttyModeReader: session.makeClaudeTTYModeReader())
        pendingChecks[guid] = check
        scheduleCheck(check, guid: guid, after: ClaudeInteractivityPolicy.checkInterval)
    }

    private func scheduleCheck(_ check: PendingCheck, guid: String, after delay: TimeInterval) {
        // check holds the item, so the item holds check weakly. pendingChecks keeps a live check
        // alive; once it's removed, the check is freed and a pending item does nothing.
        let item = DispatchWorkItem { [weak self, weak check] in
            guard let self, let check else { return }
            performCheck(check, guid: guid)
        }
        check.workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func performCheck(_ check: PendingCheck, guid: String) {
        guard !check.cancelled, pendingChecks[guid] === check else { return }
        guard let session = sessionEligibleForUpsell(guid: guid) else {
            pendingChecks.removeValue(forKey: guid)
            return
        }
        // Read every time: the process info may not have had claude's
        // command line the first time.
        let invocation = session.claudeInvocation()
        if invocation == .nonInteractive {
            DLog("claude in \(guid) is a non-interactive run; not offering the upsell")
            pendingChecks.removeValue(forKey: guid)
            return
        }
        check.ttyModeReader.read { [weak self] reading in
            guard let self, !check.cancelled, pendingChecks[guid] === check else { return }
            let elapsed = check.elapsed
            let decision = ClaudeInteractivityPolicy.decide(invocation: invocation,
                                                            reading: reading,
                                                            elapsed: elapsed)
            DLog("claude in \(guid): \(reading) after \(elapsed)s -> \(decision)")
            switch decision {
            case .offer:
                pendingChecks.removeValue(forKey: guid)
                reconcile(guid: guid)
            case .decline:
                pendingChecks.removeValue(forKey: guid)
            case .checkAgain(after: let delay):
                scheduleCheck(check, guid: guid, after: delay)
            }
        }
    }

    private func showAnnouncement(on session: PTYSession) {
        let title = String(localized: "ClaudeCodeMode.OfferTitle", defaultValue: "Claude Code is running. Want to try the Claude Code integration?", comment: "Announcement offering to enable the Claude Code integration")
        let actions = [String(localized: "ClaudeCodeMode.TryItNow", defaultValue: "Try It Now", comment: "Button to enable the Claude Code integration now"), String(localized: "ClaudeCodeMode.DontShowAgain", defaultValue: "Don't Show Again", comment: "Button to dismiss the offer permanently")]
        let announcement = iTermAnnouncementViewController.announcement(
            withTitle: title,
            style: .kiTermAnnouncementViewStyleQuestion,
            withActions: actions) { [weak self, weak session] choice in
                switch choice {
                case 0:
                    if let session {
                        let guid = session.guid
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
                            on: session,
                            mechanism: .onboarding)
                        // First-time trial users almost certainly
                        // want the cc-status hook so Claude's state
                        // appears in the toolbelt — open the installer
                        // directly instead of nagging with a second
                        // announcement. Skip when hooks are already
                        // installed; the installer would have nothing
                        // to add. Deferred so the upsell's dismiss
                        // animation and the workgroup-entry UI
                        // churn settle before the installer takes key.
                        // Check the directory this session's claude actually reads, from disk,
                        // rather than a cached flag: the flag is reconciled from the
                        // recorded-or-default path and reads true when another instance's hooks
                        // happen to be sitting there, in which case the installer never opens and
                        // nothing ever reports status.
                        ClaudeCodeOnboarding.hooksHealthyForSession(session) { [weak session] healthy in
                            guard !healthy else {
                                return
                            }
                            ClaudeCodeOnboarding.show(session: session)
                        }
                    }
                case 1:
                    iTermUserDefaults.claudeCodeWorkgroupUpsellSuppressed = true
                default:
                    break
                }
            }
        if let announcement {
            session.queueAnnouncement(announcement,
                                      identifier: Self.announcementIdentifier)
        }
    }

}
