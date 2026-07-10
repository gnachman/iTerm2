//
//  RemoteCommand+Mac.swift
//  iTerm2
//
//  Mac-only behavior for RemoteCommand: the AI safety check (gatekeeper,
//  warnings, preferences) and the permission-category user-defaults mapping.
//  Split from RemoteCommand.swift, which is shared with the iOS companion app.
//

import Foundation

extension RemoteCommand {
    // `force` makes the safety check mandatory regardless of the user
    // preference (used for orchestration chats, where autonomous command
    // execution always gets checked). `transcript` is recent chat history
    // for the classifier, so it can tell a risky command the user asked for
    // from one it didn't; empty by default for callers that have none.
    @MainActor
    func isSafe(force: Bool, transcript: [TranscriptEntry] = []) async -> Bool {
        switch content {
        case .isAtPrompt, .getLastExitStatus, .getCommandHistory, .getLastCommand,
                .getCommandBeforeCursor, .searchCommandHistory, .getCommandOutput,
                .getTerminalSize, .getShellType, .detectSSHSession, .getRemoteHostname,
                .getUserIdentity, .getCurrentDirectory, .setClipboard,
                .deleteCurrentLine, .getManPage, .createFile, .searchBrowser,
                .loadURL, .webSearch, .getURL, .readWebPage, .insertTextAtCursor:
            return true
        case .executeCommand(let command):
            // The safety check uses the configured conversation model, so it is
            // available whenever AI is set up (not tied to any specific vendor
            // or OS version).
            if iTermAITermGatekeeper.allowed {
                // Orchestration chats are checked unconditionally, so don't nag
                // about the opt-in preference there.
                if !force {
                    let nagKey = kPreferenceKeyAISafetyCheckNagComplete
                    if iTermUserDefaults.userDefaults().object(forKey: kPreferenceKeyAISafetyCheck) == nil &&
                        !iTermUserDefaults.userDefaults().bool(forKey: nagKey) {
                        let selection = iTermWarning.show(
                            withTitle: "iTerm2 can use AI to check the safety of commands suggested by your AI agent. Would you like to enable safety checking?\n\nWhen enabled, each proposed command will be sent to your configured AI provider for a safety check.",
                            actions: ["OK", "Cancel"],
                            accessory: nil,
                            identifier: nil,
                            silenceable: .kiTermWarningTypePersistent,
                            heading: "Enable Command Safety Checking?",
                            window: nil)
                        iTermPreferences.setBool(true, forKey: nagKey)
                        if selection == .kiTermWarningSelection0 {
                            iTermPreferences.setBool(true, forKey: kPreferenceKeyAISafetyCheck)
                        }
                    }
                }
                if force || iTermPreferences.bool(forKey: kPreferenceKeyAISafetyCheck) {
                    if !force {
                        Self.maybePromptToSwitchSafetyProvider()
                    }
                    return await CommandSafetyChecker.check(command.command,
                                                            transcript: transcript)
                }
            }
            return true
        }
    }

    // Users who enabled the safety check while it ran on-device via Apple
    // Intelligence (free) are asked once, before the next checked command,
    // whether to switch to the configured model (more accurate, but may incur
    // provider charges). Declining keeps Apple Intelligence. The migration in
    // iTermMigrationHelper sets the pending flag and the Apple default.
    @MainActor
    private static func maybePromptToSwitchSafetyProvider() {
        let defaults = iTermUserDefaults.userDefaults()
        guard defaults.bool(forKey: kPreferenceKeyAISafetyCheckProviderSwitchPending) else {
            return
        }
        // Only present the choice when on-device is actually available here.
        // If it is not (the pref synced from an Apple Intelligence Mac, or the
        // model is temporarily not ready), leave the prompt pending so we do
        // not offer "Keep Apple Intelligence" where it cannot work. Until then
        // the side-query fails closed rather than falling back to the cloud.
        guard AIAvailabilityProbe.check() else {
            return
        }
        defaults.set(false, forKey: kPreferenceKeyAISafetyCheckProviderSwitchPending)
        let selection = iTermWarning.show(
            withTitle: "Until now, iTerm2 checked the safety of AI-suggested commands on your Mac using Apple Intelligence, at no cost. It can now use your configured AI model instead, which is more accurate but sends each checked command to your AI provider and may incur charges.\n\nSwitch to your configured model? If you decline, iTerm2 keeps using Apple Intelligence.",
            actions: ["Switch to My Model", "Keep Apple Intelligence"],
            accessory: nil,
            identifier: nil,
            silenceable: .kiTermWarningTypePersistent,
            heading: "Command Safety Checking Has Changed",
            window: nil)
        // Selection 0 == switch to the configured model; 1 == keep Apple.
        defaults.set(selection != .kiTermWarningSelection0,
                     forKey: kPreferenceKeyAISafetyCheckUsesAppleIntelligence)
    }
}

extension RemoteCommand.Content.PermissionCategory {
    var userDefaultsKey: String {
        switch self {
        case .checkTerminalState: kPreferenceKeyAIPermissionCheckTerminalState
        case .runCommands: kPreferenceKeyAIPermissionRunCommands
        case .viewHistory: kPreferenceKeyAIPermissionViewHistory
        case .writeToClipboard: kPreferenceKeyAIPermissionWriteToClipboard
        case .typeForYou: kPreferenceKeyAIPermissionTypeForYou
        case .viewManpages: kPreferenceKeyAIPermissionViewManpages
        case .writeToFilesystem: kPreferenceKeyAIPermissionWriteToFilesystem
        case .actInWebBrowser: kPreferenceKeyAIPermissionActInWebBrowser
        }
    }
}
