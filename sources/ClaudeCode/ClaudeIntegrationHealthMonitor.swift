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
// but the hook is no longer present in ~/.claude/settings.json.
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
    // sessions launch in close succession. Cleared on dismiss.
    private var alertInFlight = false

    // One disk read per launch is enough. Set after the first
    // claude-launch evaluation that *completes* — prompted,
    // healthy, or skipped because the completed flag was off. The
    // "another warning is already on screen" bail does NOT set
    // this; we want to retry on the next notification rather than
    // burn the one-shot on whatever unrelated warning happened to
    // be up.
    //
    // Without this gate we'd re-parse ~/.claude/settings.json
    // every time claude appears in or disappears from any
    // session's ancestor chain — a few times a day for active
    // users, and a burst at window restoration. If Claude Code
    // strips the hook *after* we've already checked, we catch it
    // the next launch, which is good enough for a recovery prompt.
    private var hasEvaluated = false

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
        evaluateAndPromptIfBroken()
    }

    // Two-phase: cheap checks + disk-read kickoff stay on the main
    // thread, the read itself runs on diskQueue, and the prompt
    // dispatches back to main. Flip hasEvaluated and alertInFlight
    // *before* dispatching so notifications that arrive while the
    // background read is in flight don't queue a second one.
    private func evaluateAndPromptIfBroken() {
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
        hasEvaluated = true
        alertInFlight = true
        diskQueue.async { [weak self] in
            // Strict check: every event present, command path
            // points at an executable file. Catches partial
            // strips, stale paths, and dangling symlinks — not
            // just the wholesale "hook is gone" case. Reads disk
            // and follows symlinks, which is why it's off-main:
            // a wedged network mount could block forever.
            let healthy = ClaudeCodeOnboarding.hooksHealthyOnDiskForHealthCheck()
            DispatchQueue.main.async {
                self?.diskCheckCompleted(healthy: healthy)
            }
        }
    }

    private func diskCheckCompleted(healthy: Bool) {
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
            DLog("Health: another warning came up during disk read, deferring")
            alertInFlight = false
            hasEvaluated = false
            return
        }
        DLog("Health: integration completed but hook is missing on disk — prompting")
        let warning = iTermWarning()
        warning.heading = "Claude Code Integration Looks Broken"
        warning.title = "iTerm2\u{2019}s cc-status hook is no longer in "
            + "~/.claude/settings.json. This usually means Claude Code "
            + "rewrote that file. Reinstall the hook so per-tab status "
            + "indicators (\u{201C}Working\u{2026},\u{201D} "
            + "\u{201C}Waiting\u{2026}\u{201D}) work again?"
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        warning.identifier = Self.warningIdentifier
        warning.actionLabels = ["Reinstall", "Not Now"]
        // Without this, "Reinstall + Remember My Choice" would
        // preempt the dialog on every future broken-state launch
        // and silently open the onboarding window — almost
        // certainly not what a user means by "remember." Only the
        // dismiss path is rememberable; "Reinstall" always
        // requires a fresh click.
        warning.doNotRememberLabels = ["Reinstall"]
        warning.runModalAsync { [weak self] selection, _ in
            self?.alertInFlight = false
            if selection == .kiTermWarningSelection0 {
                ClaudeCodeOnboarding.show()
            }
        }
    }
}
