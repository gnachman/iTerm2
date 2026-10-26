//
//  RemoteGitState.swift
//  iTerm2SharedARC
//
//  Git state for a directory on a host reached through SSH Integration, for the status bar's git
//  component and the workgroup toolbar. Locally that comes from libgit2 in pidinfo; here
//  it2_git_state.py runs the git CLI on the host and reports the same fields with the same
//  meanings (RemoteGitStateParityTests holds the two to that).
//
//  The script runs as a framer background job (`run`), not through runpy: framer reads one
//  command at a time, and runpy runs in that loop, so a slow `git status` would hold up the
//  session's keystrokes. It is run by the Python that runs the framer, so no interpreter has to be
//  found, and it needs nothing from the framer beyond `run`, so a framer started by an older build
//  works too.
//

import Foundation

@objc(iTermRemoteGitState)
final class iTermRemoteGitState: NSObject {
    static let marker = "it2-git-state:"

    private static let scriptSource: String? = {
        guard let url = Bundle(for: iTermRemoteGitState.self).url(forResource: "it2_git_state",
                                                                   withExtension: "py") else {
            DLog("it2_git_state.py is missing from the bundle")
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    private static func shellQuote(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A command line for /bin/sh that runs the script with `python` on `path`. Everything
    /// variable travels base64-encoded, so no quoting can go wrong on the way.
    @objc(commandLineWithPython:path:gitBase:includeDiffStats:timeout:)
    static func commandLine(python: String,
                            path: String,
                            gitBase: String?,
                            includeDiffStats: Bool,
                            timeout: TimeInterval) -> String {
        var request: [String: Any] = ["path": path, "stats": includeDiffStats, "timeout": timeout]
        if let gitBase, !gitBase.isEmpty {
            request["base"] = gitBase
        }
        let requestData = (try? JSONSerialization.data(withJSONObject: request)) ?? Data()
        let script = Data((scriptSource ?? "").utf8).base64EncodedString()
        let bootstrap = "import base64;exec(compile(base64.b64decode('\(script)'),'it2_git_state.py','exec'))"
        return [shellQuote(python), "-c", shellQuote(bootstrap), shellQuote(requestData.base64EncodedString())]
            .joined(separator: " ")
    }

    /// The script's JSON object, from output that may carry anything else before or after it.
    private static func object(fromScriptOutput output: String) -> [String: Any]? {
        guard let line = output.components(separatedBy: .newlines).last(where: { $0.contains(marker) }),
              let range = line.range(of: marker) else {
            return nil
        }
        let encoded = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: encoded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    @objc(scriptOutputIsWellFormed:)
    static func scriptOutputIsWellFormed(_ output: String) -> Bool {
        guard let object = object(fromScriptOutput: output) else {
            return false
        }
        return object["error"] == nil
    }

    private static let kinds: [String: iTermGitFileChangeKind] = [
        "none": .none, "modified": .modified, "added": .added, "deleted": .deleted,
        "renamed": .renamed, "typechange": .typeChange, "untracked": .untracked,
        "conflicted": .conflicted
    ]

    private static let repoStates: [String: iTermGitRepoState] = [
        "none": .none, "merge": .merge, "revert": .revert, "cherrypick": .cherrypick,
        "bisect": .bisect, "rebase": .rebase, "apply": .apply
    ]

    /// The state, or nil when the path is in no repository, the script timed out (`timedOut` is
    /// set), or the output is not the script's.
    @objc(stateFromScriptOutput:timedOut:)
    static func state(fromScriptOutput output: String,
                      timedOut: UnsafeMutablePointer<ObjCBool>?) -> iTermGitState? {
        timedOut?.pointee = false
        guard let object = object(fromScriptOutput: output) else {
            DLog("Remote git state: no answer in \(output.prefix(500))")
            return nil
        }
        if object["timeout"] as? Bool == true {
            timedOut?.pointee = true
            return nil
        }
        if let error = object["error"] {
            DLog("Remote git state: script failed: \(error)")
            return nil
        }
        guard let branch = object["branch"] as? String else {
            return nil
        }
        let state = iTermGitState()
        state.creationTime = NSDate.it_timeSinceBoot()
        state.branch = branch
        state.ahead = object["ahead"] as? String ?? ""
        state.behind = object["behind"] as? String ?? ""
        state.dirty = object["dirty"] as? Bool ?? false
        state.adds = object["adds"] as? Int ?? 0
        state.deletes = object["deletes"] as? Int ?? 0
        state.repoState = repoStates[object["repoState"] as? String ?? ""] ?? .none
        if let stats = object["stats"] as? [String: Int] {
            state.filesAdded = stats["filesAdded"] ?? 0
            state.filesModified = stats["filesModified"] ?? 0
            state.filesDeleted = stats["filesDeleted"] ?? 0
            state.linesInserted = stats["linesInserted"] ?? 0
            state.linesDeleted = stats["linesDeleted"] ?? 0
        }
        if let files = object["files"] as? [[String]] {
            state.fileStatuses = files.compactMap { entry in
                guard entry.count == 3 else {
                    return nil
                }
                let status = iTermGitFileStatus()
                status.path = entry[0]
                status.indexStatus = kinds[entry[1]] ?? .none
                status.workdirStatus = kinds[entry[2]] ?? .none
                return status
            }
        }
        return state
    }
}

/// What the worker needs from a connection. Conductor provides it; tests substitute a fake.
@MainActor
protocol RemoteGitCommandRunning: AnyObject {
    /// The Python that runs the framer, or nil if it cannot be learned.
    func remoteGitPythonPath(_ completion: @escaping (String?) -> Void)
    /// Runs a /bin/sh command line in the background; its output, or nil if it could not run.
    func runRemoteGitCommand(_ commandLine: String, completion: @escaping (String?) -> Void)
}

/// One per connection. Like the shared local worker, it merges identical requests that are in
/// flight and reuses an answer for a second, so several pollers watching the same directory (a
/// status bar and a workgroup toolbar, say) cost one run. Keys never mix hosts because each
/// connection has its own worker.
@MainActor
@objc(iTermRemoteGitPollWorker)
final class iTermRemoteGitPollWorker: NSObject, @preconcurrency iTermGitPollWorkerProtocol {
    typealias Completion = (iTermGitState?, Bool) -> Void

    private weak var runner: RemoteGitCommandRunning?
    private var cache = [String: iTermGitState]()
    private var pending = [String: [Completion]]()
    // Bumped by invalidateCache(forPath:) so an answer already in flight is not cached.
    private var generation = 0
    private var python: String?
    private var pythonLookupFailedAt: TimeInterval?
    private var waitingForPython: [() -> Void]?

    private static let ttl: TimeInterval = 1
    private static let pythonRetryInterval: TimeInterval = 30

    /// Time allowed past the script's own git deadline before giving up on an answer.
    var extraDeadline: TimeInterval = 15
    var gitTimeoutOverride: TimeInterval?

    init(runner: RemoteGitCommandRunning) {
        self.runner = runner
    }

    private func key(path: String, gitBase: String?, includeDiffStats: Bool) -> String {
        let base = (gitBase == nil || gitBase == "" || gitBase == "HEAD") ? "" : gitBase!
        return [path, base, includeDiffStats ? "1" : "0"].joined(separator: "\u{0}")
    }

    func requestPath(_ path: String,
                     gitBase: String?,
                     includeDiffStats: Bool,
                     completion: @escaping Completion) {
        let key = key(path: path, gitBase: gitBase, includeDiffStats: includeDiffStats)
        if let cached = cache[key], NSDate.it_timeSinceBoot() - cached.creationTime < Self.ttl {
            completion(cached, false)
            return
        }
        if pending[key] != nil {
            pending[key]?.append(completion)
            return
        }
        pending[key] = [completion]
        withPython { [weak self] python in
            guard let self else {
                return
            }
            guard let python else {
                self.finish(key: key, generation: self.generation, state: nil, timedOut: false, cacheable: false)
                return
            }
            self.run(python: python, key: key, path: path, gitBase: gitBase, includeDiffStats: includeDiffStats)
        }
    }

    private func run(python: String, key: String, path: String, gitBase: String?, includeDiffStats: Bool) {
        guard let runner else {
            finish(key: key, generation: generation, state: nil, timedOut: false, cacheable: false)
            return
        }
        let timeout = gitTimeoutOverride ?? max(1, iTermAdvancedSettingsModel.gitTimeout())
        let command = iTermRemoteGitState.commandLine(python: python,
                                                      path: path,
                                                      gitBase: gitBase,
                                                      includeDiffStats: includeDiffStats,
                                                      timeout: timeout)
        let generation = self.generation
        var answered = false
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout + extraDeadline) { [weak self] in
            guard !answered else {
                return
            }
            answered = true
            DLog("Remote git state for \(path): no answer in time")
            self?.finish(key: key, generation: generation, state: nil, timedOut: true, cacheable: false)
        }
        runner.runRemoteGitCommand(command) { [weak self] output in
            guard !answered else {
                return
            }
            answered = true
            var timedOut = ObjCBool(false)
            let state = output.flatMap { iTermRemoteGitState.state(fromScriptOutput: $0, timedOut: &timedOut) }
            self?.finish(key: key,
                         generation: generation,
                         state: state,
                         timedOut: timedOut.boolValue,
                         cacheable: output != nil && !timedOut.boolValue)
        }
    }

    private func finish(key: String, generation: Int, state: iTermGitState?, timedOut: Bool, cacheable: Bool) {
        if cacheable && generation == self.generation, let state {
            cache[key] = state
        }
        let completions = pending.removeValue(forKey: key) ?? []
        for completion in completions {
            completion(state, timedOut)
        }
    }

    private func withPython(_ block: @escaping (String?) -> Void) {
        if let python {
            block(python)
            return
        }
        if let failedAt = pythonLookupFailedAt,
           NSDate.it_timeSinceBoot() - failedAt < Self.pythonRetryInterval {
            block(nil)
            return
        }
        if waitingForPython != nil {
            waitingForPython?.append { [weak self] in block(self?.python) }
            return
        }
        guard let runner else {
            block(nil)
            return
        }
        waitingForPython = [{ [weak self] in block(self?.python) }]
        runner.remoteGitPythonPath { [weak self] path in
            guard let self else {
                return
            }
            if let path, !path.isEmpty {
                self.python = path
                self.pythonLookupFailedAt = nil
            } else {
                DLog("Remote git state: could not learn the framer's python")
                self.pythonLookupFailedAt = NSDate.it_timeSinceBoot()
            }
            let waiters = self.waitingForPython ?? []
            self.waitingForPython = nil
            for waiter in waiters {
                waiter()
            }
        }
    }

    func invalidateCache(forPath path: String) {
        generation += 1
        cache = cache.filter { !$0.key.hasPrefix(path + "\u{0}") }
    }
}

extension iTermRemoteGitPollWorker {
    /// The worker for the connection a session's git state should come from, or nil to read this
    /// Mac (or the it2git variables). The session's reported host must be the one the connection
    /// runs on: after a plain `ssh` from inside an it2ssh session the path belongs to a host the
    /// connection cannot see, and git run on the middle host would describe the wrong repository.
    @objc(workerForScope:)
    static func worker(forScope scope: iTermVariableScope) -> iTermRemoteGitPollWorker? {
        guard let guid = scope.value(forVariableName: iTermVariableKeySessionID) as? String,
              let session = iTermController.sharedInstance()?.anySession(withGUID: guid),
              let conductor = session.hostConductor,
              conductor.framing else {
            return nil
        }
        let host = scope.value(forVariableName: iTermVariableKeySessionHostname) as? String
        let user = scope.value(forVariableName: iTermVariableKeySessionUsername) as? String
        guard conductor.sshIdentity.matches(host: host,
                                            user: user,
                                            discoveredHostname: conductor.discoveredHostname) else {
            DLog("Remote git state: session host \(host ?? "nil") is not the connection's \(conductor.sshIdentity.displayName)")
            return nil
        }
        return conductor.remoteGitPollWorker
    }
}

extension Conductor: RemoteGitCommandRunning {
    func remoteGitPythonPath(_ completion: @escaping (String?) -> Void) {
        guard framing else {
            completion(nil)
            return
        }
        framerExecPythonStatements(statements: "import sys\nreturn sys.executable") { ok, output in
            DispatchQueue.main.async {
                completion(ok ? output.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
            }
        }
    }

    func runRemoteGitCommand(_ commandLine: String, completion: @escaping (String?) -> Void) {
        guard framing else {
            completion(nil)
            return
        }
        runRemoteCommand(commandLine) { data, status in
            DispatchQueue.main.async {
                completion(status < 0 ? nil : String(decoding: data, as: UTF8.self))
            }
        }
    }
}
