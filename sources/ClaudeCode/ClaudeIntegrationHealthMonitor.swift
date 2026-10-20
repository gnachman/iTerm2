//
//  ClaudeIntegrationHealthMonitor.swift
//  iTerm2SharedARC
//

import Foundation

// Watches for claude launches and surfaces a one-shot repair prompt
// when a previously-completed Claude Code integration looks broken.
//
// "Broken" means: the user once successfully installed the cc-status
// hook (so iTermUserDefaults.claudeCodeIntegrationCompleted is true)
// but some event no longer has a working cc-status hook in Claude Code's settings.json
// (resolved from $CLAUDE_CONFIG_DIR, defaulting to ~/.claude — see
// ClaudeCodeOnboarding.claudeSettingsURL).
// Claude Code itself rewrites that file periodically and has been
// observed to drop our hook entry; we have no way to prevent that,
// so the recovery story is "notice it the next time claude runs and
// offer to reinstall."
//
// The trigger is a fresh claude launch — surfacing this at app
// startup would nag users who happen to have a stale completed flag
// but no current intent to use claude. The notification fires
// frequently (every ancestor-chain change), so we gate on a one-
// shot in-flight flag plus iTermWarning.identifier to give the user
// "Don't ask again" without us having to track that ourselves.
@objc(iTermClaudeIntegrationHealthMonitor)
final class ClaudeIntegrationHealthMonitor: NSObject {
    @objc static let instance = ClaudeIntegrationHealthMonitor()
    private static let warningIdentifier =
        "NoSyncSuppressClaudeCodeIntegrationRepairPrompt"

    // Off-main queue for the settings.json read. The user's home
    // directory may be on a network mount; a stat or read on a
    // wedged share blocks indefinitely. Keep that off the main
    // thread so a hung NFS/SMB doesn't freeze the app.
    private let diskQueue = DispatchQueue(
        label: "com.iterm2.claude-integration-health",
        qos: .utility)

    // Guards against stacking the alert when multiple claude
    // sessions launch in close succession. Cleared on dismiss, which
    // also runs any it2 check that waited for it.
    private var alertInFlight = false {
        didSet {
            if oldValue && !alertInFlight {
                DispatchQueue.main.async { [weak self] in
                    self?.retryDeferredIt2Checks()
                }
            }
        }
    }

    // One disk read per launch is enough. Set after the first
    // claude-launch evaluation that *completes* — prompted,
    // healthy, or skipped because the completed flag was off. The
    // "another warning is already on screen" bail does NOT set
    // this; we want to retry on the next notification rather than
    // burn the one-shot on whatever unrelated warning happened to
    // be up.
    //
    // Without this gate we'd re-parse Claude Code's settings.json
    // every time claude appears in or disappears from any
    // session's ancestor chain — a few times a day for active
    // users, and a burst at window restoration. If Claude Code
    // strips the hook *after* we've already checked, we catch it
    // the next launch, which is good enough for a recovery prompt.
    private var hasEvaluated = false

    // Hosts reached through SSH Integration are checked once per connection rather than once per
    // launch: a check is one round trip over that connection, not a disk read, so there is no
    // reason to make a user relaunch to have a host looked at again. Keyed by the conductor's
    // guid. A connection whose prompt could not be shown is removed again so the next claude
    // launch on it retries.
    private var evaluatedConnections = ClaudeRemoteCheckGate()
    private static let remoteWarningIdentifier =
        "NoSyncSuppressClaudeCodeRemoteIntegrationPrompt"

    // Which connections' shell-integration version has been judged for Claude Code's use of it2
    // (see ClaudeCodeIt2Reachability).
    private let it2Scheduler = ClaudeCodeIt2CheckScheduler()
    private static let it2WarningIdentifier =
        "NoSyncSuppressClaudeCodeShellIntegrationTooOldPrompt"

    private override init() {
        super.init()
    }

    @objc func start() {
        DLog("ClaudeIntegrationHealthMonitor.start()")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(jobMonitorDidChange(_:)),
            name: GlobalJobMonitor.didChangeNotification,
            object: nil)
        // Try It Now enters the Claude Code workgroup after claude has already started, so the
        // it2 check also runs on entry.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(workgroupDidEnter(_:)),
            name: iTermWorkgroupController.didEnterNotification,
            object: nil)
        // Ask the upstream monitor to re-emit current state so we
        // see restored claude sessions even though we may have
        // registered after another observer triggered the
        // singleton's seed-on-init. Idempotent across observers
        // (see replayCurrentState's docs).
        GlobalJobMonitor.instance.replayCurrentState()
    }

    @objc
    private func jobMonitorDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let job = userInfo[GlobalJobMonitor.jobNameKey] as? String,
              job == "claude",
              let sessions = userInfo[GlobalJobMonitor.sessionGUIDsKey] as? Set<String>,
              !sessions.isEmpty else {
            return
        }
        // claude on a remote host reads that host's settings, so it says nothing about this Mac's
        // and is checked separately, once per host. hostConductor covers a tmux pane over ssh.
        // Notifications are posted on the main thread.
        MainActor.assumeIsolated {
            var local = Set<String>()
            var remote = [String: PTYSession]()
            for guid in sessions {
                guard let session = iTermController.sharedInstance().session(withGUID: guid),
                      let conductor = session.hostConductor, conductor.framing else {
                    local.insert(guid)
                    continue
                }
                let host = conductor.sshIdentity.stringIdentifier
                if remote[host] == nil {
                    remote[host] = session
                }
            }
            for guid in sessions.subtracting(local).sorted() {
                if let session = iTermController.sharedInstance().session(withGUID: guid) {
                    checkIt2Reachability(session: session)
                }
            }
            if !local.isEmpty {
                evaluateAndPromptIfBroken(sessionGUIDs: local)
            }
            for host in remote.keys.sorted() {
                if let session = remote[host] {
                    evaluateRemote(host: host, session: session)
                }
            }
        }
    }

    // MARK: - it2 on PATH for Claude Code

    @objc
    private func workgroupDidEnter(_ notification: Notification) {
        guard let session = notification.object as? PTYSession,
              notification.userInfo?[iTermWorkgroupController.workgroupIDKey] as? String ==
                ClaudeCodeWorkgroupTemplate.ID.workgroup else {
            return
        }
        MainActor.assumeIsolated {
            checkIt2Reachability(session: session)
        }
    }

    // Claude Code runs it2 by name from `sh -c`, so on a remote host it needs the shell's
    // integration script to have put ~/.iterm2/bin on PATH. Only where the integration is in use
    // there; see ClaudeCodeIt2Reachability.shouldCheck.
    @MainActor
    private func checkIt2Reachability(session: PTYSession) {
        guard let conductor = session.hostConductor, conductor.framing else {
            return
        }
        let host = conductor.sshIdentity.stringIdentifier
        let reported = session.reportedShellIntegration
        let input = ClaudeCodeIt2CheckScheduler.Input(
            connection: conductor.guid,
            sessionGUID: session.guid,
            shell: reported?.shell,
            version: reported?.version,
            inClaudeCodeWorkgroup: Self.inClaudeCodeWorkgroup(session),
            hookPresent: ClaudeCodeRemoteConnectionFacts.shared.hookPresent(for: conductor) == true)
        let action = it2Scheduler.evaluate(input, promptBusy: alertInFlight || iTermWarning.showingWarning())
        DLog("it2 check: \(host) reported \(String(describing: reported)) workgroup=\(input.inClaudeCodeWorkgroup) hook=\(input.hookPresent): \(action)")
        if action == .warn {
            showShellIntegrationTooOld(host: host, session: session)
        }
    }

    @MainActor
    private func retryDeferredIt2Checks() {
        for guid in it2Scheduler.takeDeferred() {
            if let session = iTermController.sharedInstance().anySession(withGUID: guid) {
                checkIt2Reachability(session: session)
            }
        }
    }

    private func showShellIntegrationTooOld(host: String, session: PTYSession) {
        RLog("it2 check: shell integration on a remote host is too old for Claude Code to run it2")
        alertInFlight = true
        let warning = iTermWarning()
        warning.heading = String(localized: "ClaudeHealthMonitor.ShellIntegrationTooOldHeading", defaultValue: "Update Shell Integration on \(host)?", comment: "Heading of the warning shown when shell integration on a remote host is too old for Claude Code to run it2; the value is the host")
        warning.title = String(localized: "ClaudeHealthMonitor.ShellIntegrationTooOldTitle", defaultValue: "Claude Code on \(host) can\u{2019}t find the it2 command, which features such as Code Review ask it to run. The shell integration installed on \(host) is too old to make it available. To update it, exit Claude Code and choose iTerm2 > Install Shell Integration in that session.", comment: "Body of the warning shown when shell integration on a remote host is too old for Claude Code to run it2; the value is the host")
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        warning.identifier = Self.it2WarningIdentifier
        warning.actionLabels = [iTermLocalizedOK()]
        warning.window = session.view?.window
        warning.runModalAsync { [weak self] _, _ in
            self?.alertInFlight = false
        }
    }

    /// For tests: what the it2 check would conclude for `session`, or nil if it would not check.
    @MainActor
    static func it2Verdict(for session: PTYSession) -> ClaudeCodeIt2Reachability.Verdict? {
        guard let conductor = session.hostConductor, conductor.framing else {
            return nil
        }
        let reported = session.reportedShellIntegration
        return ClaudeCodeIt2Reachability.verdict(shell: reported?.shell, version: reported?.version)
    }

    private static func inClaudeCodeWorkgroup(_ session: PTYSession) -> Bool {
        return session.workgroupInstance?.workgroup.uniqueIdentifier == ClaudeCodeWorkgroupTemplate.ID.workgroup
    }

    // MARK: - Remote hosts

    @MainActor
    private func evaluateRemote(host: String, session: PTYSession) {
        guard let conductor = session.hostConductor, conductor.framing else {
            DLog("Health: remote session \(session.guid) has no framing connection; skipping")
            return
        }
        let connection = conductor.guid
        guard !evaluatedConnections.hasChecked(connection) else {
            DLog("Health: \(host) already checked on this connection; skipping")
            return
        }
        guard !alertInFlight else {
            DLog("Health: alert already in flight, skipping \(host)")
            return
        }
        guard !iTermWarning.showingWarning() else {
            DLog("Health: another warning is on-screen, skipping \(host)")
            return
        }
        // Only for someone who uses the integration: set up on this Mac, or this session is in the
        // Claude Code workgroup. Nothing about the host is remembered, so whether the hook is
        // there is always read from the host.
        guard evaluatedConnections.shouldCheck(connection,
                                               integrationInUse: iTermUserDefaults.claudeCodeIntegrationCompleted || Self.inClaudeCodeWorkgroup(session)) else {
            DLog("Health: the integration is not in use; not checking \(host)")
            return
        }
        DLog("Health: checking \(host)")
        alertInFlight = true
        ClaudeCodeOnboarding.remoteHostIsThisMac(conductor: conductor) { [weak self, weak conductor, weak session] isThisMac in
            guard let self else {
                return
            }
            // This Mac reached over ssh: the local install covers it, and a remote install would
            // only be refused.
            guard !isThisMac, let conductor else {
                DLog("Health: \(host) is this Mac or disconnected; not checking")
                self.alertInFlight = false
                return
            }
            ClaudeCodeOnboarding.remoteHookStatus(conductor: conductor) { [weak self, weak session] status in
                self?.remoteCheckCompleted(host: host, connection: connection, status: status, session: session)
            }
        }
    }

    private func remoteCheckCompleted(host: String, connection: String,
                                      status: ClaudeCodeRemoteHooks.HookStatus,
                                      session: PTYSession?) {
        let installed: Bool
        switch status {
        case .unknown:
            DLog("Health: couldn't read \(host)'s settings; nothing to say")
            alertInFlight = false
            // Perhaps the lookup of where the settings are timed out: the next launch looks again.
            evaluatedConnections.forget(connection)
            return
        case .healthy:
            DLog("Health: \(host) is healthy")
            // The hook is there, so the integration is in use on this host and its shell
            // integration matters.
            it2Scheduler.hookFound(onConnection: connection)
            alertInFlight = false
            if let session {
                MainActor.assumeIsolated {
                    checkIt2Reachability(session: session)
                }
            }
            return
        case .broken:
            it2Scheduler.hookFound(onConnection: connection)
            installed = true
        case .notInstalled:
            installed = false
        }
        if iTermWarning.showingWarning() {
            RLog("Health: another warning came up during the remote check, deferring")
            alertInFlight = false
            evaluatedConnections.forget(connection)
            return
        }
        RLog("Health: Claude Code hook \(installed ? "broken" : "not installed") on a remote host; prompting")
        let warning = iTermWarning()
        let actionLabel: String
        if installed {
            warning.heading = String(localized: "ClaudeHealthMonitor.RemoteBrokenHeading", defaultValue: "Claude Code Integration on \(host) Looks Broken", comment: "Heading of the warning shown when the Claude Code hook on a remote host is incomplete; the value is the host")
            warning.title = String(localized: "ClaudeHealthMonitor.RemoteBrokenTitle", defaultValue: "iTerm2\u{2019}s hook is no longer complete in Claude Code\u{2019}s settings on \(host). This usually means Claude Code rewrote that file. Reinstall the hook so per-tab status indicators (\u{201C}Working\u{2026},\u{201D} \u{201C}Waiting\u{2026}\u{201D}) work again?", comment: "Body of the warning shown when the Claude Code hook on a remote host is incomplete; the value is the host")
            actionLabel = String(localized: "ClaudeHealthMonitor.Reinstall", defaultValue: "Reinstall", comment: "Button to reinstall the Claude Code status hook")
        } else {
            warning.heading = String(localized: "ClaudeHealthMonitor.RemoteNotInstalledHeading", defaultValue: "Install Claude Code Integration on \(host)?", comment: "Heading of the prompt offering to install the Claude Code hook on a remote host where claude is running; the value is the host")
            warning.title = String(localized: "ClaudeHealthMonitor.RemoteNotInstalledTitle", defaultValue: "Claude Code is running on \(host), but iTerm2\u{2019}s hook isn\u{2019}t installed there, so its status won\u{2019}t appear in the Session Status tool. Install it?", comment: "Body of the prompt offering to install the Claude Code hook on a remote host where claude is running; the value is the host")
            actionLabel = String(localized: "ClaudeHealthMonitor.Install", defaultValue: "Install", comment: "Button to install the Claude Code status hook on a remote host")
        }
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        warning.identifier = Self.remoteWarningIdentifier
        warning.actionLabels = [actionLabel, String(localized: "ClaudeHealthMonitor.NotNow", defaultValue: "Not Now", comment: "Button to dismiss the reinstall prompt for now")]
        // As for the local prompt: only declining can be remembered.
        warning.doNotRememberLabels = [actionLabel]
        warning.runModalAsync { [weak self, weak session] selection, _ in
            self?.alertInFlight = false
            if selection == .kiTermWarningSelection0 {
                ClaudeCodeOnboarding.showRemoteInstall(session: session)
            }
        }
    }

    // Two-phase: cheap checks + disk-read kickoff stay on the main
    // thread, the read itself runs on diskQueue, and the prompt
    // dispatches back to main. Flip hasEvaluated and alertInFlight
    // *before* dispatching so notifications that arrive while the
    // background read is in flight don't queue a second one.
    private func evaluateAndPromptIfBroken(sessionGUIDs: Set<String>) {
        guard !hasEvaluated else { return }
        guard !alertInFlight else {
            DLog("Health: alert already in flight, skipping")
            return
        }
        guard !iTermWarning.showingWarning() else {
            DLog("Health: another warning is on-screen, skipping")
            return
        }
        guard iTermUserDefaults.claudeCodeIntegrationCompleted else {
            hasEvaluated = true
            return
        }
        // Only Not Now can be remembered (see doNotRememberLabels
        // below), so a silenced warning would just be dismissed.
        // Skip the disk read and any shell launch, unless the user
        // asked to see alerts with remembered selections anyway.
        guard !iTermWarning.identifierIsSilenced(Self.warningIdentifier) ||
                iTermWarning.showRememberedAlerts else {
            DLog("Health: repair prompt is silenced, skipping")
            hasEvaluated = true
            return
        }
        hasEvaluated = true
        alertInFlight = true
        // Strict check: every event present, command resolves to
        // an executable file. Catches partial strips, stale paths,
        // and dangling symlinks — not just the wholesale "hook is
        // gone" case. The disk work runs on diskQueue; the user's
        // shell is launched only if a hook command uses $HOME or
        // the like (see ClaudeCodeOnboarding.withHookEnvironment).
        ClaudeCodeOnboarding.checkHooksHealth(on: diskQueue) { [weak self] healthy in
            self?.diskCheckCompleted(healthy: healthy, sessionGUIDs: sessionGUIDs)
        }
    }

    private func diskCheckCompleted(healthy: Bool, sessionGUIDs: Set<String>) {
        if healthy {
            alertInFlight = false
            return
        }
        // Re-check on completion — we let go of the main thread
        // for the disk read and an unrelated iTermWarning could
        // have come up in the interim. Without this, the broken-
        // install alert would stack on top of it. Clear
        // hasEvaluated (already set in the kickoff path) so the
        // next claude-launch notification retries; the broken
        // state is real and the user should still see the prompt.
        if iTermWarning.showingWarning() {
            RLog("Health: another warning came up during disk read, deferring")
            alertInFlight = false
            hasEvaluated = false
            return
        }
        RLog("Health: integration completed but no working hook on disk — prompting")
        // Synchronous, main-safe read of the install-time-recorded path.
        let path = ClaudeCodeOnboarding.claudeSettingsURL().path
        let warning = iTermWarning()
        warning.heading = String(localized: "ClaudeHealthMonitor.BrokenHeading", defaultValue: "Claude Code Integration Looks Broken", comment: "Heading of the warning shown when the Claude Code status hook is missing")
        warning.title = String(localized: "ClaudeHealthMonitor.HookNotWorkingTitle", defaultValue: "iTerm2 couldn\u{2019}t find a working cc-status hook for every Claude Code event in \(path). Reinstall the hook so per-tab status indicators (\u{201C}Working\u{2026},\u{201D} \u{201C}Waiting\u{2026}\u{201D}) work again?", comment: "Body of the warning shown when the Claude Code status hook is missing from settings.json or points at a file that can\u{2019}t run; the interpolated value is the absolute path to settings.json")
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        warning.identifier = Self.warningIdentifier
        let reinstall = String(localized: "ClaudeHealthMonitor.Reinstall", defaultValue: "Reinstall", comment: "Button to reinstall the Claude Code status hook")
        warning.actionLabels = [reinstall, String(localized: "ClaudeHealthMonitor.NotNow", defaultValue: "Not Now", comment: "Button to dismiss the reinstall prompt for now")]
        // Without this, "Reinstall + Remember My Choice" would
        // preempt the dialog on every future broken-state launch
        // and silently open the onboarding window — almost
        // certainly not what a user means by "remember." Only the
        // dismiss path is rememberable; "Reinstall" always
        // requires a fresh click.
        warning.doNotRememberLabels = [reinstall]
        // Reinstall opens the onboarding window on this Mac.
        warning.notOfferedRemotelyLabels = [reinstall]
        warning.runModalAsync { [weak self] selection, _ in
            self?.alertInFlight = false
            if selection == .kiTermWarningSelection0 {
                // Any of the sessions running claude will do: the reinstall
                // resolves CLAUDE_CONFIG_DIR for that session's profile.
                let session = sessionGUIDs.lazy
                    .compactMap { iTermController.sharedInstance().session(withGUID: $0) }
                    .first
                ClaudeCodeOnboarding.show(session: session)
            }
        }
    }
}

/// Which SSH Integration connections the health monitor has checked for Claude Code's hook. A
/// connection seen while the integration is not in use is not counted, so it is checked once the
/// user sets the integration up or enters the Claude Code workgroup.
struct ClaudeRemoteCheckGate {
    private var checked = Set<String>()

    func hasChecked(_ connection: String) -> Bool {
        return checked.contains(connection)
    }

    /// Whether to check `connection` now; if so, it counts as checked.
    mutating func shouldCheck(_ connection: String, integrationInUse: Bool) -> Bool {
        guard integrationInUse, !checked.contains(connection) else {
            return false
        }
        checked.insert(connection)
        return true
    }

    /// Its prompt could not be shown, so the next claude launch on it checks again.
    mutating func forget(_ connection: String) {
        checked.remove(connection)
    }
}
