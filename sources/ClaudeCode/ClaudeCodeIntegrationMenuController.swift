//
//  ClaudeCodeIntegrationMenuController.swift
//  iTerm2SharedARC
//

import AppKit

// Owns the iTerm2 menu's Install/Uninstall Claude Code Integration
// items: their actions, mutual visibility, and the multi-step flow
// behind the uninstall confirmation. Lives outside the app delegate
// to keep that monster file from absorbing more responsibility —
// the app delegate just forwards its IBActions and validateMenuItem
// cases through here.
@objc(iTermClaudeCodeIntegrationMenuController)
final class ClaudeCodeIntegrationMenuController: NSObject {
    @objc static let shared = ClaudeCodeIntegrationMenuController()

    private override init() {
        super.init()
    }

    // MARK: - Menu Actions

    @objc func install(_ sender: Any?) {
        ClaudeCodeOnboarding.show()
    }

    // Same code path as install — the onboarding is idempotent and
    // pre-marks completed steps. The reason this is a separate menu
    // item is the menu validation (see validateInstallMenuItem):
    // once the integration has previously been set up, Install is
    // hidden, so without a Reinstall entry the user has no way to
    // add a missing piece (Try-It-Now-only users who never installed
    // the hook, triggers-only users who never entered the workgroup)
    // or to repair a broken install (Claude Code stripped the hook,
    // hand edits, etc.) — Uninstall would be their only option.
    @objc func reinstall(_ sender: Any?) {
        ClaudeCodeOnboarding.show()
    }

    @objc func uninstall(_ sender: Any?) {
        // Menu actions arrive on the main thread.
        MainActor.assumeIsolated {
            reallyUninstall()
        }
    }

    /// A connection that can edit `host`'s files right now, if there is one.
    @MainActor
    private func liveConductor(forHost host: String) -> Conductor? {
        return ConductorRegistry.instance.conductors(forStringIdentifier: host).first { $0.framing }
    }

    /// True while the hosts are checked before the confirmation, so a second click while that
    /// runs doesn't queue a second dialog.
    private var preparingUninstall = false

    @MainActor
    private func reallyUninstall() {
        guard !preparingUninstall else {
            DLog("Uninstall: already preparing; ignoring")
            return
        }
        // The settings.json location was recorded at install time, so this is a
        // synchronous read (no shell spawn) and is the same path uninstallHooks
        // operates on below.
        let settingsPath = ClaudeCodeOnboarding.claudeSettingsURL().path
        // Nothing about remote hosts is kept on this Mac, and removing the hook means editing a
        // file on the host, so the hosts to look at are the ones connected through SSH
        // Integration now. Each one's own settings say whether the hook is there.
        let candidates = ClaudeCodeUninstallTargets.hosts(connections: ConductorRegistry.instance.conductors.values
            .flatMap { $0.compactMap(\.value) }
            .map { ($0.sshIdentity.stringIdentifier, $0.framing) })
        preparingUninstall = true
        Task { @MainActor [weak self] in
            // A host that is this Mac is left out of the dialog and the removal, as Install
            // refuses it.
            let hosts = await ClaudeCodeUninstallTargets.excludingThisMac(candidates) { [weak self] host in
                guard let conductor = self?.liveConductor(forHost: host) else {
                    return false
                }
                return await ClaudeCodeRemoteHooks.hostIsThisMac(files: ConductorClaudeCodeRemoteFiles(conductor: conductor))
            }
            self?.preparingUninstall = false
            self?.confirmAndUninstall(settingsPath: settingsPath, hosts: hosts)
        }
    }

    @MainActor
    private func confirmAndUninstall(settingsPath: String, hosts: [String]) {
        let confirm = iTermWarning()
        confirm.heading = String(localized: "ClaudeCode.UninstallTitle", defaultValue: "Uninstall Claude Code Integration?", comment: "Title of the uninstall confirmation dialog")
        var lines = [String(localized: "ClaudeCode.UninstallBody", defaultValue: "This removes iTerm2\u{2019}s status hook from \(settingsPath), the Claude Code workgroup from your settings, and the Enter/Exit Workgroup triggers from every profile. You can set up the integration again any time from the iTerm2 menu.", comment: "Explanation of what uninstalling the Claude Code integration does; the interpolated value is the absolute path to settings.json")]
        for host in hosts {
            lines.append(String(localized: "ClaudeCode.UninstallConnectedHost", defaultValue: "It also removes the hook from Claude Code\u{2019}s settings on \(host), if it\u{2019}s there.", comment: "Line of the uninstall confirmation for a host connected through SSH Integration, whose settings will be checked and cleaned up; the value is the host"))
        }
        if !hosts.isEmpty {
            lines.append(String(localized: "ClaudeCode.UninstallDisconnectedHosts", defaultValue: "Hosts that aren\u{2019}t connected keep their hook. Connect to one with SSH Integration and uninstall again to remove it there.", comment: "Line of the uninstall confirmation explaining that hosts not currently connected through SSH Integration are not changed"))
        }
        confirm.title = lines.joined(separator: "\n\n")
        confirm.actionLabels = [String(localized: "ClaudeCode.Uninstall", defaultValue: "Uninstall", comment: "Button to confirm uninstalling the Claude Code integration"),
                                iTermLocalizedCancel()]
        confirm.cancelLabel = iTermLocalizedCancel()
        confirm.warningType = .kiTermWarningTypePersistent
        guard confirm.runModal() == .kiTermWarningSelection0 else { return }

        // Hooks first — they're the only step that can fail (disk).
        let hookResult = ClaudeCodeOnboarding.uninstallHooks()
        remoteHostsWithHook(hosts, found: []) { [weak self] withHook in
            guard let self else {
                return
            }
            // Asked before anything runs on the hosts, so the questions come together rather
            // than between removals. A grant may predate the install and other it2 use there may
            // rely on it.
            var revoke = [String: Bool]()
            for host in withHook where Conductor.hostGrantStore.grant(forHost: host) != nil {
                revoke[host] = self.askWhetherToStopAllowing(host)
            }
            self.uninstallRemoteHooks(withHook, revoke: revoke, failures: []) { [weak self] failures in
                self?.finishUninstall(hookResult: hookResult, settingsPath: settingsPath, remoteFailures: failures)
            }
        }
    }

    /// The hosts among `hosts` whose settings have the hook, or could not be read (so an uninstall
    /// there reports the failure rather than skipping it silently). One at a time.
    @MainActor
    private func remoteHostsWithHook(_ hosts: [String], found: [String], completion: @escaping ([String]) -> Void) {
        guard let host = hosts.first else {
            completion(found)
            return
        }
        let rest = Array(hosts.dropFirst())
        guard let conductor = liveConductor(forHost: host) else {
            remoteHostsWithHook(rest, found: found, completion: completion)
            return
        }
        ClaudeCodeOnboarding.remoteHookStatus(conductor: conductor) { [weak self] status in
            let keep = status != .notInstalled
            DLog("Uninstall: \(host) hook status \(status)")
            self?.remoteHostsWithHook(rest, found: keep ? found + [host] : found, completion: completion)
        }
    }

    @MainActor
    private func askWhetherToStopAllowing(_ host: String) -> Bool {
        let warning = iTermWarning()
        warning.heading = String(localized: "ClaudeCode.StopAllowingHostTitle", defaultValue: "Also Stop Always Allowing \(host) to Use the iTerm2 API?", comment: "Title of the question asked when uninstalling the Claude Code integration from a host that is always allowed to use the API; the value is the host")
        warning.title = String(localized: "ClaudeCode.StopAllowingHostBody", defaultValue: "Other uses of it2 on \(host) may rely on it. You can also change this later in Settings > General > Magic > API access over ssh.", comment: "Body of the question asked when uninstalling the Claude Code integration from an always-allowed host; the value is the host")
        warning.actionLabels = [String(localized: "ClaudeCode.StopAllowing", defaultValue: "Stop Allowing", comment: "Button that revokes a remote host\u{2019}s always-allow grant during uninstall"),
                                String(localized: "ClaudeCode.KeepAllowing", defaultValue: "Keep Allowing", comment: "Button that keeps a remote host\u{2019}s always-allow grant during uninstall")]
        warning.warningType = .kiTermWarningTypePersistent
        return warning.runModal() == .kiTermWarningSelection0
    }

    /// One host at a time, so each finishes before the next starts. Delivers the failures.
    @MainActor
    private func uninstallRemoteHooks(_ hosts: [String],
                                      revoke: [String: Bool],
                                      failures: [(String, ClaudeCodeUninstallHooksResult)],
                                      completion: @escaping ([(String, ClaudeCodeUninstallHooksResult)]) -> Void) {
        guard let host = hosts.first else {
            completion(failures)
            return
        }
        let rest = Array(hosts.dropFirst())
        guard let conductor = liveConductor(forHost: host) else {
            // Disconnected since the confirmation.
            uninstallRemoteHooks(rest, revoke: revoke, failures: failures + [(host, .unreadable)], completion: completion)
            return
        }
        ClaudeCodeOnboarding.uninstallHooksRemotely(conductor: conductor,
                                                    revokeAlwaysAllow: revoke[host] ?? false) { [weak self] result in
            let failed = result == .success ? failures : failures + [(host, result)]
            self?.uninstallRemoteHooks(rest, revoke: revoke, failures: failed, completion: completion)
        }
    }

    private func remoteFailureDetail(host: String, result: ClaudeCodeUninstallHooksResult) -> String {
        switch result {
        case .malformed:
            return String(localized: "ClaudeCode.RemoteHookMalformed", defaultValue: "Claude Code\u{2019}s settings on \(host) couldn\u{2019}t be parsed as JSON.", comment: "Detail shown when the Claude Code settings on a remote host are not valid JSON during uninstall; the value is the host")
        case .writeFailed:
            return String(localized: "ClaudeCode.RemoteHookWriteFailed", defaultValue: "Couldn\u{2019}t write Claude Code\u{2019}s settings on \(host).", comment: "Detail shown when the Claude Code settings on a remote host could not be written during uninstall; the value is the host")
        case .unreadable, .success:
            return String(localized: "ClaudeCode.RemoteHookUnreadable", defaultValue: "Couldn\u{2019}t read Claude Code\u{2019}s settings on \(host).", comment: "Detail shown when the Claude Code settings on a remote host could not be read, or the host disconnected, during uninstall; the value is the host")
        @unknown default:
            return ""
        }
    }

    private func finishUninstall(hookResult: ClaudeCodeUninstallHooksResult,
                                 settingsPath: String,
                                 remoteFailures: [(String, ClaudeCodeUninstallHooksResult)]) {
        // If the hook removal fails, ask before touching the rest: the
        // user may want to bail out and fix the underlying problem
        // (nothing removed, retryable), or push through and clean up the
        // iTerm-side state anyway (cc-status will keep firing until they
        // fix settingsPath by hand).
        if hookResult != .success || !remoteFailures.isEmpty {
            var details = [String]()
            let detail: String
            switch hookResult {
            case .unreadable:
                detail = String(localized: "ClaudeCode.HookUnreadable", defaultValue: "Could not read \(settingsPath) — check the file\u{2019}s permissions.", comment: "Detail shown when the Claude Code settings file could not be read; the interpolated value is the absolute path to settings.json")
            case .malformed:
                detail = String(localized: "ClaudeCode.HookMalformed", defaultValue: "\(settingsPath) couldn\u{2019}t be parsed as JSON. Open it in a text editor and check it for syntax errors.", comment: "Detail shown when the Claude Code settings file is not valid JSON; the interpolated value is the absolute path to settings.json")
            case .writeFailed:
                detail = String(localized: "ClaudeCode.HookWriteFailed", defaultValue: "Could not write to \(settingsPath) — check the file\u{2019}s permissions.", comment: "Detail shown when the Claude Code settings file could not be written; the interpolated value is the absolute path to settings.json")
            case .success:
                detail = ""
            @unknown default:
                detail = ""
            }
            if !detail.isEmpty {
                details.append(detail)
            }
            details += remoteFailures.map { remoteFailureDetail(host: $0.0, result: $0.1) }
            let failure = iTermWarning()
            failure.heading = String(localized: "ClaudeCode.HookRemovalFailedTitle", defaultValue: "Couldn\u{2019}t Remove Hooks", comment: "Title shown when Claude Code hook removal failed")
            let joinedDetails = details.joined(separator: "\n")
            failure.title = String(localized: "ClaudeCode.HookRemovalFailedBody", defaultValue: "\(joinedDetails) Continue removing the workgroup and triggers anyway? iTerm2\u{2019}s status hook will keep running until you fix the underlying issue and try again.", comment: "Body shown when hook removal failed, asking whether to continue uninstalling")
            failure.actionLabels = [String(localized: "General.Continue", defaultValue: "Continue", comment: "Continue button"),
                                    iTermLocalizedCancel()]
            failure.cancelLabel = iTermLocalizedCancel()
            failure.warningType = .kiTermWarningTypePersistent
            guard failure.runModal() == .kiTermWarningSelection0 else { return }
        } else {
            warnAboutKeptHookCommands(settingsPath: settingsPath)
        }

        ClaudeCodeOnboarding.uninstallWorkgroup()
        ClaudeCodeOnboarding.uninstallTriggers()

        // Clear the "user once completed setup" sticky flag so the
        // broken-install nag doesn't fire after an explicit uninstall.
        // Set again on the next successful install.
        iTermUserDefaults.claudeCodeIntegrationCompleted = false

        // The installer turned the Python API on, but the user might
        // rely on it for unrelated scripts/AI integrations now.
        // Don't flip it off behind their back — ask. Skip the prompt
        // entirely if the API is already off (uninstall has nothing
        // to offer).
        if iTermAPIHelper.isEnabled() {
            let apiAlert = iTermWarning()
            apiAlert.heading = String(localized: "ClaudeCode.DisableAPITitle", defaultValue: "Disable the Python API?", comment: "Title asking whether to disable the Python API during uninstall")
            apiAlert.title = String(localized: "ClaudeCode.DisableAPIBody", defaultValue: "The installer enabled iTerm2\u{2019}s Python API. Other scripts or integrations may be using it now. Leave it enabled, or turn it off?", comment: "Explanation shown when asking whether to disable the Python API during uninstall")
            apiAlert.actionLabels = [String(localized: "ClaudeCode.LeaveEnabled", defaultValue: "Leave Enabled", comment: "Button to leave the Python API enabled"),
                                     String(localized: "ClaudeCode.Disable", defaultValue: "Disable", comment: "Button to disable the Python API")]
            apiAlert.warningType = .kiTermWarningTypePersistent
            if apiAlert.runModal() == .kiTermWarningSelection1 {
                iTermAPIHelper.setEnabled(false)
            }
        }
    }

    // Uninstall leaves a hook command that runs other programs as well as
    // cc-status, since removing it would stop those too. Say so, or the
    // user would think cc-status is gone while it keeps running. The list
    // is every command that keeps hooksAlreadyInstalled true, so it also
    // explains why Reinstall and Uninstall stay in the menu. Some of them
    // may not actually run cc-status (its path is gone, or it's only an
    // argument), so the text doesn't claim they do.
    private func warnAboutKeptHookCommands(settingsPath: String) {
        let kept = ClaudeCodeOnboarding.ccStatusCommandsOnDisk()
        guard !kept.isEmpty else {
            return
        }
        RLog("Uninstall left \(kept.count) cc-status hook command(s) in place")
        let commands = kept.joined(separator: "\n")
        let warning = iTermWarning()
        warning.heading = String(localized: "ClaudeCode.HookCommandsKeptTitle", defaultValue: "Some Hooks Were Left in Place", comment: "Title shown after uninstalling when some Claude Code hook commands were not removed")
        warning.title = String(localized: "ClaudeCode.HookCommandsKeptBody", defaultValue: "Some hook commands in \(settingsPath) refer to iTerm2\u{2019}s status hook but also run other programs, so Uninstall didn\u{2019}t remove them. If you don\u{2019}t want them anymore, edit the file by hand:\n\n\(commands)", comment: "Body shown after uninstalling when some Claude Code hook commands were not removed. The first interpolated value is the absolute path to settings.json; the second is the list of hook commands, one per line, shown verbatim")
        warning.actionLabels = [iTermLocalizedOK()]
        warning.warningType = .kiTermWarningTypePersistent
        warning.runModal()
    }

    // MARK: - Menu Validation

    // The three Claude Code menu items partition by install state:
    // never set up → only Install is visible; previously set up
    // → Reinstall and Uninstall are both visible (Install is hidden).
    //
    // The "previously set up" predicate is OR-of-two-signals:
    // (a) live artifacts on disk (hooks / workgroup / triggers),
    // (b) the sticky claudeCodeIntegrationCompleted flag,
    // (c) an install on any host reached through SSH Integration, which is
    // only recorded here (its files are on the host).
    //
    // (b) matters because the wholesale-strip case — Claude Code
    // rewriting ~/.claude/settings.json and removing the cc-status
    // entry — leaves (a) false. A user in that state isn't doing
    // a fresh Install; they're recovering. Reinstall is the right
    // label, and Uninstall stays available so the user can clear
    // the sticky flag and silence the broken-install prompt
    // permanently if they no longer want the integration.
    @objc func validateInstallMenuItem(_ item: NSMenuItem) -> Bool {
        item.isHidden = integrationKnownToHaveExisted
        return true
    }

    @objc func validateReinstallMenuItem(_ item: NSMenuItem) -> Bool {
        item.isHidden = !integrationKnownToHaveExisted
        return true
    }

    @objc func validateUninstallMenuItem(_ item: NSMenuItem) -> Bool {
        item.isHidden = !integrationKnownToHaveExisted
        return !preparingUninstall
    }

    private var integrationKnownToHaveExisted: Bool {
        return anyArtifactInstalled
            || iTermUserDefaults.claudeCodeIntegrationCompleted
            || ClaudeCodeRemoteConnectionFacts.shared.anyHookPresent
    }

    private var anyArtifactInstalled: Bool {
        return ClaudeCodeOnboarding.hooksAlreadyInstalled()
            || ClaudeCodeOnboarding.workgroupAlreadyInstalled()
            || ClaudeCodeOnboarding.triggersAlreadyInstalled()
    }
}

/// The hosts an uninstall can look at: one entry per host with a framing SSH Integration
/// connection, sorted so the confirmation reads the same each time.
enum ClaudeCodeUninstallTargets {
    static func hosts(connections: [(host: String, framing: Bool)]) -> [String] {
        return Set(connections.filter(\.framing).map(\.host)).sorted()
    }

    /// `hosts` without those that are this Mac reached over ssh. Install refuses those, and their
    /// settings are this Mac's, which the local uninstall handles. Keeps the order. The hosts are
    /// asked at once, so the wait is the slowest one's rather than the sum.
    @MainActor
    static func excludingThisMac(_ hosts: [String],
                                 isThisMac: @escaping @MainActor (String) async -> Bool) async -> [String] {
        let checks = hosts.map { host in
            (host, Task { @MainActor in await isThisMac(host) })
        }
        var result = [String]()
        for (host, check) in checks {
            if await check.value {
                DLog("Uninstall: \(host) is this Mac; not offering it")
                continue
            }
            result.append(host)
        }
        return result
    }
}
