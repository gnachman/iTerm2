//
//  ClaudeCodeIt2Reachability.swift
//  iTerm2SharedARC
//
//  Whether Claude Code on a host reached through SSH Integration can run `it2` by name. Its Bash
//  tool runs commands through `sh -c`, which sees only PATH, and the shell-integration scripts put
//  ~/.iterm2/bin (where iTerm2 uploads it2) first on PATH starting with the versions below.
//  Hooks are unaffected: they call it2 by its full path.
//
//  The minimums are fixed, not "the latest": a later script release must not start warning about
//  scripts that work.
//

import Foundation

enum ClaudeCodeIt2Reachability {
    static let minimumVersionByShell = ["zsh": 20, "bash": 23, "fish": 26, "tcsh": 10, "xonsh": 5]

    enum Verdict: Equatable {
        case current
        /// `shell` is nil for a script so old it named no shell; `minimum` is then nil too.
        case tooOld(shell: String?, version: Int, minimum: Int?)
        /// Nothing was reported, or the shell is not one the scripts cover. Not the same as old.
        case unknown
    }

    static func verdict(shell: String?, version: Int?) -> Verdict {
        guard let version else {
            return .unknown
        }
        guard let shell else {
            // Scripts have named their shell since long before any of them carried it2.
            return .tooOld(shell: nil, version: version, minimum: nil)
        }
        guard let minimum = minimumVersionByShell[shell] else {
            return .unknown
        }
        return version < minimum ? .tooOld(shell: shell, version: version, minimum: minimum) : .current
    }

    /// Most people never use the Claude Code integration and must never see this. So only where it
    /// is in use on that host: its hook installed there, or the session in the Claude Code
    /// workgroup (Try It Now, or the auto-enter trigger). And only over SSH Integration: on this
    /// Mac the native it2 is on PATH.
    static func shouldCheck(overSSHIntegration: Bool,
                            hookInstalledOnHost: Bool,
                            inClaudeCodeWorkgroup: Bool) -> Bool {
        return overSSHIntegration && (hookInstalledOnHost || inClaudeCodeWorkgroup)
    }
}

/// The once-per-connection bookkeeping for the warning, apart from the UI so it can be tested.
/// The health monitor feeds it each time claude starts or a session enters the Claude Code
/// workgroup, tells it when the health check finds the hook on a host, and asks it which
/// deferred checks to run again once a prompt is gone.
final class ClaudeCodeIt2CheckScheduler {
    struct Input {
        var connection: String
        var sessionGUID: String
        var shell: String?
        var version: Int?
        var inClaudeCodeWorkgroup: Bool
        /// The hook was found in the host's settings during this connection.
        var hookPresent: Bool
    }

    enum Action: Equatable {
        /// The integration is not in use on that host; nothing was decided, so ask again later.
        case notInUse
        case alreadyChecked
        /// Current, or nothing to go on. Done for this connection.
        case fine
        case warn
        /// Too old, but another prompt is up. Handed back by takeDeferred.
        case deferred
    }

    private var checkedConnections = Set<String>()
    // Connections whose host the health check found the hook on after an earlier evaluation.
    private var connectionsWithHook = Set<String>()
    private var deferredSessionByConnection = [String: String]()

    func hookFound(onConnection connection: String) {
        connectionsWithHook.insert(connection)
    }

    func evaluate(_ input: Input, promptBusy: Bool) -> Action {
        guard !checkedConnections.contains(input.connection) else {
            return .alreadyChecked
        }
        guard ClaudeCodeIt2Reachability.shouldCheck(
            overSSHIntegration: true,
            hookInstalledOnHost: input.hookPresent || connectionsWithHook.contains(input.connection),
            inClaudeCodeWorkgroup: input.inClaudeCodeWorkgroup) else {
            return .notInUse
        }
        switch ClaudeCodeIt2Reachability.verdict(shell: input.shell, version: input.version) {
        case .current, .unknown:
            checkedConnections.insert(input.connection)
            deferredSessionByConnection.removeValue(forKey: input.connection)
            return .fine
        case .tooOld:
            if promptBusy {
                deferredSessionByConnection[input.connection] = input.sessionGUID
                return .deferred
            }
            checkedConnections.insert(input.connection)
            deferredSessionByConnection.removeValue(forKey: input.connection)
            return .warn
        }
    }

    /// Sessions whose check was deferred, to run again now; each is handed back once.
    func takeDeferred() -> [String] {
        let sessions = deferredSessionByConnection.values.sorted()
        deferredSessionByConnection.removeAll()
        return sessions
    }
}

