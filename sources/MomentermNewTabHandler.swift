//
//  MomentermNewTabHandler.swift
//  iTerm2
//
//  Created by MomenTerm on 2026-04-19.
//
//  Handles new tab / new window behavior:
//  - Preserves current working directory when opening new tab/window
//  - Checks for Claude Code / Codex updates on open
//
//  Integration: call MomentermNewTabHandler.applyCurrentDirectoryIfNeeded(to:)
//  from PseudoTerminal when creating a new tab/window.
//

import AppKit
import Foundation

@objc(MomentermNewTabHandler)
final class MomentermNewTabHandler: NSObject {

    @objc static let shared = MomentermNewTabHandler()

    /// Whether to check AI tools when a new tab/window opens.
    @objc var checkAIToolsOnOpen: Bool {
        get { iTermUserDefaults.userDefaults().bool(forKey: "MomentermCheckAIToolsOnOpen") }
        set { iTermUserDefaults.userDefaults().set(newValue, forKey: "MomentermCheckAIToolsOnOpen") }
    }

    // Track whether we've already shown the AI check this launch
    private var hasShownAICheckThisLaunch = false

    // MARK: - Public API

    /// Returns the shell command to inject into a new tab/window to navigate
    /// to the same directory as the source session.
    @objc func cdCommandForCurrentSession() -> String? {
        guard let cwd = currentSessionWorkingDirectory() else { return nil }
        return "cd \"\(cwd.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    /// Called by PseudoTerminal when a new tab is opened.
    /// Returns an optional command to inject (e.g. `cd /current/path`).
    @objc func commandForNewTab(preservingDirectory preserve: Bool) -> String? {
        guard preserve else { return nil }
        return cdCommandForCurrentSession()
    }

    /// Called by PseudoTerminal when a new window is opened.
    @objc func commandForNewWindow(preservingDirectory preserve: Bool) -> String? {
        guard preserve else { return nil }
        return cdCommandForCurrentSession()
    }

    /// Shows the AI tools check dialog (once per session unless forced).
    @objc func checkAIToolsIfNeeded(force: Bool = false) {
        guard checkAIToolsOnOpen || force else { return }
        guard !hasShownAICheckThisLaunch || force else { return }
        hasShownAICheckThisLaunch = true

        DispatchQueue.global(qos: .background).async {
            let claudeAvailable = self.isCommandAvailable("claude")
            let codexAvailable = self.isCommandAvailable("codex")

            DispatchQueue.main.async {
                self.showAIToolsStatus(claudeAvailable: claudeAvailable, codexAvailable: codexAvailable)
            }
        }
    }

    // MARK: - Private helpers

    private func currentSessionWorkingDirectory() -> String? {
        // Primary: read from frontmost session's CWD via the notification system
        // This is the same mechanism iTerm2 uses for smart selection
        if let frontWindow = NSApp.keyWindow,
           let wc = frontWindow.windowController as? PseudoTerminal,
           let session = wc.currentSession(),
           let cwd = session.currentLocalWorkingDirectory {
            return cwd
        }
        // Fallback: read from process environment
        return ProcessInfo.processInfo.environment["PWD"]
    }

    private func isCommandAvailable(_ command: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [command]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func showAIToolsStatus(claudeAvailable: Bool, codexAvailable: Bool) {
        guard claudeAvailable || codexAvailable else { return }

        var available: [String] = []
        if claudeAvailable { available.append("Claude Code") }
        if codexAvailable { available.append("Codex") }

        let toolList = available.joined(separator: " and ")

        let alert = NSAlert()
        alert.messageText = "\(toolList) \(available.count > 1 ? "are" : "is") installed"
        alert.informativeText = "Would you like to launch \(toolList) in the current directory?"
        alert.addButton(withTitle: "Launch")
        alert.addButton(withTitle: "Skip")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Send launch command to active session
        var cmds: [String] = []
        if claudeAvailable { cmds.append("claude") }
        if codexAvailable { cmds.append("codex") }

        for cmd in cmds {
            sendToActiveSession(cmd)
        }
    }

    private func sendToActiveSession(_ text: String) {
        guard let frontWindow = NSApp.keyWindow,
              let wc = frontWindow.windowController as? PseudoTerminal,
              let session = wc.currentSession() else { return }
        session.writeTask(text + "\n")
    }
}
