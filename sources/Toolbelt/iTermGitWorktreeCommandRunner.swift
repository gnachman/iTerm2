import Foundation

// The Foundation scanner has no application bridging dependencies. Keep the native
// command runner and the existing advanced preference at this adapter boundary.
private final class iTermGitWorktreeCommandRunner: iTermGitWorktreeCommandExecuting {
    private let executable: String

    init(searchPath: String) {
        let firstDirectory = searchPath.components(separatedBy: ":").first ?? ""
        executable = firstDirectory.isEmpty ? "/usr/bin/git" :
            (firstDirectory as NSString).appendingPathComponent("git")
    }

    func run(arguments: [String], directory: String, timeout: TimeInterval) -> iTermGitWorktreeCommandResult {
        it_assert(!Thread.isMainThread, "Git worktree commands must run off the main thread")
        let runner = iTermBufferedCommandRunner(command: executable, withArguments: arguments, path: directory)
        runner.discardStandardError = true
        runner.terminatesProcessGroup = true
        runner.maximumOutputSize = NSNumber(value: 1024 * 1024)
        runner.terminateWhenOutputExceedsMaximum = true
        // Session environment overrides must not redirect discovery to another repo,
        // and neither Git nor a configured credential helper may prompt interactively.
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        runner.environment = environment
        let status = runner.blockingRun(withTimeout: timeout)
        if status != 0 || runner.timedOut || runner.truncated {
            DLog("Git worktree read failed: status=\(status), timeout=\(runner.timedOut), truncated=\(runner.truncated)")
        }
        return .init(output: runner.output ?? Data(), status: status,
                     timedOut: runner.timedOut, truncated: runner.truncated)
    }
}

extension iTermGitWorktreeScanner {
    @nonobjc convenience override init() {
        self.init(executor: iTermGitWorktreeCommandRunner(searchPath: iTermAdvancedSettingsModel.gitSearchPath()))
    }
}
