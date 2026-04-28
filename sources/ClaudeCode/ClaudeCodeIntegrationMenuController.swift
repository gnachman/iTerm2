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

    @objc func uninstall(_ sender: Any?) {
        let confirm = NSAlert()
        confirm.messageText = "Uninstall Claude Code Integration?"
        confirm.informativeText = "This removes the cc-status hook from "
            + "~/.claude/settings.json, the Claude Code workgroup from your "
            + "settings, and the Enter/Exit Workgroup triggers from every "
            + "profile. You can reinstall any time using iTerm2 > Install Claude Code Integration."
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Uninstall")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        // Hooks first — they're the only step that can fail (disk).
        // If the hook removal fails, ask before touching the rest:
        // the user may want to bail out and fix the underlying
        // problem (nothing removed, retryable), or push through and
        // clean up the iTerm-side state anyway (cc-status will keep
        // firing until they fix ~/.claude/settings.json by hand).
        let hookResult = ClaudeCodeOnboarding.uninstallHooks()
        if hookResult != .success {
            let detail: String
            switch hookResult {
            case .unreadable:
                detail = "Could not read ~/.claude/settings.json — check "
                    + "the file\u{2019}s permissions."
            case .malformed:
                detail = "~/.claude/settings.json couldn\u{2019}t be parsed "
                    + "as JSON. Open it in a text editor and check it for "
                    + "syntax errors."
            case .writeFailed:
                detail = "Could not write to ~/.claude/settings.json — "
                    + "check the file\u{2019}s permissions."
            case .success:
                detail = ""  // unreachable; covered by outer guard
            @unknown default:
                detail = ""
            }
            let failure = NSAlert()
            failure.messageText = "Couldn\u{2019}t Remove Hooks"
            failure.informativeText = "\(detail) Continue removing the "
                + "workgroup and triggers anyway? cc-status will keep "
                + "running until you fix the underlying issue and try again."
            failure.alertStyle = .warning
            failure.addButton(withTitle: "Continue")
            failure.addButton(withTitle: "Cancel")
            guard failure.runModal() == .alertFirstButtonReturn else { return }
        }

        ClaudeCodeOnboarding.uninstallWorkgroup()
        ClaudeCodeOnboarding.uninstallTriggers()

        // The installer turned the Python API on, but the user might
        // rely on it for unrelated scripts/AI integrations now.
        // Don't flip it off behind their back — ask. Skip the prompt
        // entirely if the API is already off (uninstall has nothing
        // to offer).
        if iTermAPIHelper.isEnabled() {
            let apiAlert = NSAlert()
            apiAlert.messageText = "Disable the Python API?"
            apiAlert.informativeText = "The installer enabled iTerm2\u{2019}s "
                + "Python API. Other scripts or integrations may be using "
                + "it now. Leave it enabled, or turn it off?"
            apiAlert.addButton(withTitle: "Leave Enabled")
            apiAlert.addButton(withTitle: "Disable")
            if apiAlert.runModal() == .alertSecondButtonReturn {
                iTermAPIHelper.setEnabled(false)
            }
        }
    }

    // MARK: - Menu Validation

    // Mutually exclusive with validateUninstallMenuItem(_:): exactly
    // one of the two menu items is visible at any time, computed
    // from "are any of {hooks, workgroup, triggers} installed?".
    @objc func validateInstallMenuItem(_ item: NSMenuItem) -> Bool {
        item.isHidden = anyArtifactInstalled
        return true
    }

    @objc func validateUninstallMenuItem(_ item: NSMenuItem) -> Bool {
        item.isHidden = !anyArtifactInstalled
        return true
    }

    private var anyArtifactInstalled: Bool {
        return ClaudeCodeOnboarding.hooksAlreadyInstalled()
            || ClaudeCodeOnboarding.workgroupAlreadyInstalled()
            || ClaudeCodeOnboarding.triggersAlreadyInstalled()
    }
}
