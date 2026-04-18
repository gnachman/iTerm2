//
//  MomentermAIToolChecker.swift
//  iTerm2
//
//  Created by MomenTerm on 2026-04-19.
//
//  Checks if Claude Code / Codex are installed and prompts the user on open.
//

import AppKit

enum MomentermAIToolChecker {

    // MARK: - Check and prompt

    /// Checks AI tool availability for a project and optionally prompts to launch.
    static func checkAndPromptIfNeeded(for project: MomentermProject, completion: @escaping (Bool) -> Void) {
        switch project.aiTool {
        case .none:
            completion(true)
        case .claudeCode:
            checkTool("claude", displayName: "Claude Code", installHint: "npm install -g @anthropic-ai/claude-code", completion: completion)
        case .codex:
            checkTool("codex", displayName: "Codex", installHint: "npm install -g @openai/codex", completion: completion)
        case .both:
            checkBothTools(completion: completion)
        }
    }

    // MARK: - Private helpers

    private static func checkTool(_ command: String, displayName: String, installHint: String, completion: @escaping (Bool) -> Void) {
        isCommandAvailable(command) { available in
            DispatchQueue.main.async {
                if available {
                    checkForUpdate(command: command, displayName: displayName, completion: completion)
                } else {
                    showNotFoundAlert(displayName, installHint: installHint, completion: completion)
                }
            }
        }
    }

    private static func checkBothTools(completion: @escaping (Bool) -> Void) {
        isCommandAvailable("claude") { claudeAvailable in
            isCommandAvailable("codex") { codexAvailable in
                DispatchQueue.main.async {
                    let msg: String
                    if claudeAvailable && codexAvailable {
                        msg = "Claude Code and Codex are both installed. Launch both?"
                    } else if claudeAvailable {
                        msg = "Claude Code is installed. Codex not found. Launch Claude Code?"
                    } else if codexAvailable {
                        msg = "Codex is installed. Claude Code not found. Launch Codex?"
                    } else {
                        msg = "Neither Claude Code nor Codex is installed."
                        showInfoAlert(msg) { completion(true) }
                        return
                    }

                    let alert = NSAlert()
                    alert.messageText = "AI Tools Ready"
                    alert.informativeText = msg
                    alert.addButton(withTitle: "Yes, Launch")
                    alert.addButton(withTitle: "Open Without AI")
                    if alert.runModal() == .alertSecondButtonReturn {
                        completion(false)
                    } else {
                        completion(true)
                    }
                }
            }
        }
    }

    private static func checkForUpdate(command: String, displayName: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .background).async {
            // Get current version
            let currentVersion = getCommandOutput(command, args: ["--version"])
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .joined()
                .prefix(10)
                .description

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "\(displayName) is installed"
                alert.informativeText = "Version: \(currentVersion.isEmpty ? "unknown" : currentVersion)\n\nWould you like to launch \(displayName) now?"
                alert.addButton(withTitle: "Launch Now")
                alert.addButton(withTitle: "Skip")

                if alert.runModal() == .alertFirstButtonReturn {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }

    private static func showNotFoundAlert(_ toolName: String? = nil, installHint: String, completion: @escaping (Bool) -> Void) {
        let tool = toolName ?? "AI tool"
        let alert = NSAlert()
        alert.messageText = "\(tool) not found"
        alert.informativeText = "Install it to get the full AI development experience.\n\n\(installHint)\n\nOpen project without \(tool)?"
        alert.addButton(withTitle: "Open Without AI")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            completion(false)
        } else {
            completion(false)
        }
    }

    private static func showInfoAlert(_ message: String, completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completion()
    }

    // MARK: - Shell helpers

    private static func isCommandAvailable(_ command: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let result = runProcess("/usr/bin/which", args: [command])
            completion(result.exitCode == 0)
        }
    }

    private static func getCommandOutput(_ command: String, args: [String]) -> String {
        let result = runProcess(findExecutable(command) ?? command, args: args)
        return result.output
    }

    private static func findExecutable(_ command: String) -> String? {
        let paths = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
        for dir in paths {
            let full = (dir as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: full) {
                return full
            }
        }
        return nil
    }

    private static func runProcess(_ executable: String, args: [String]) -> (output: String, exitCode: Int32) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ("", 1)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", task.terminationStatus)
    }
}
