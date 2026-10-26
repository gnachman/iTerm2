//
//  ClaudeCodeRemoteHooks.swift
//  iTerm2SharedARC
//
//  Installs, checks and removes the Claude Code hook on a host reached through SSH Integration,
//  the remote counterpart of installHookFilesOnBackgroundQueue, hooksHealthyOnDisk and
//  stripCCStatusHooks. The edits themselves are ClaudeCodeHookSettings', with the remote rule for
//  which entries are ours.
//
//  File access goes through ClaudeCodeRemoteFiles so the logic is testable without a host. The
//  real one runs small Python functions through the framer (ClaudeCodeRemotePython).
//

import Foundation

enum ClaudeCodeRemoteRead: Equatable {
    case missing
    case contents(Data)
    /// Exists but could not be read; the string is the error's type name.
    case failed(String)

    init(pythonOutput output: String) {
        if output == "missing" {
            self = .missing
        } else if output.hasPrefix("ok:"), let data = Data(base64Encoded: String(output.dropFirst(3))) {
            self = .contents(data)
        } else if output.hasPrefix("error:") {
            self = .failed(String(output.dropFirst(6)))
        } else {
            self = .failed("unexpected output")
        }
    }
}

@MainActor
protocol ClaudeCodeRemoteFiles: AnyObject {
    func read(_ path: String) async -> ClaudeCodeRemoteRead
    /// Atomic, creating missing directories. False on any failure.
    func write(_ path: String, _ data: Data) async -> Bool
    func isExecutable(_ path: String) async -> Bool
    /// The machine-identity token of the host (see iTermMachineIdentity), or nil if unknown.
    func machineToken() async -> String?
}

/// Python function bodies for the framer's runpy. Paths and data travel base64-encoded, so nothing
/// needs shell or Python quoting. Each returns a short string with no newline.
enum ClaudeCodeRemotePython {
    static func read(path: String) -> String {
        return """
        import base64
        p = base64.b64decode("\(base64(path))").decode("utf-8")
        try:
            with open(p, "rb") as f:
                return "ok:" + base64.b64encode(f.read()).decode("ascii")
        except FileNotFoundError:
            return "missing"
        except Exception as e:
            return "error:" + type(e).__name__
        """
    }

    /// Writes through a temporary in the same directory and os.replace, so a reader never sees half
    /// a file. Follows a symlinked settings file to its target, so a dotfiles manager's link stays
    /// a link. Keeps an existing file's mode; a new one is 0600, since settings files can hold
    /// secrets.
    static func write(path: String, data: Data) -> String {
        return """
        import base64, os, tempfile
        p = os.path.realpath(base64.b64decode("\(base64(path))").decode("utf-8"))
        data = base64.b64decode("\(data.base64EncodedString())")
        d = os.path.dirname(p)
        os.makedirs(d, exist_ok=True)
        try:
            mode = os.stat(p).st_mode & 0o7777
        except FileNotFoundError:
            mode = 0o600
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".iterm2-settings.")
        try:
            os.fchmod(fd, mode)
            with os.fdopen(fd, "wb") as f:
                f.write(data)
            os.replace(tmp, p)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
        return "ok"
        """
    }

    static func isExecutable(path: String) -> String {
        return """
        import base64, os
        p = base64.b64decode("\(base64(path))").decode("utf-8")
        return "yes" if os.path.isfile(p) and os.access(p, os.X_OK) else "no"
        """
    }

    private static func base64(_ string: String) -> String {
        return Data(string.utf8).base64EncodedString()
    }
}

/// The real ClaudeCodeRemoteFiles, over a conductor's framer.
@MainActor
final class ConductorClaudeCodeRemoteFiles: ClaudeCodeRemoteFiles {
    /// A framer request that is aborted never completes, so every call has a deadline.
    static let deadline: TimeInterval = 30

    private weak var conductor: Conductor?

    init(conductor: Conductor) {
        self.conductor = conductor
    }

    func read(_ path: String) async -> ClaudeCodeRemoteRead {
        guard let output = await run(ClaudeCodeRemotePython.read(path: path)) else {
            return .failed("no answer")
        }
        return ClaudeCodeRemoteRead(pythonOutput: output)
    }

    func write(_ path: String, _ data: Data) async -> Bool {
        return await run(ClaudeCodeRemotePython.write(path: path, data: data)) == "ok"
    }

    func isExecutable(_ path: String) async -> Bool {
        return await run(ClaudeCodeRemotePython.isExecutable(path: path)) == "yes"
    }

    func machineToken() async -> String? {
        return await run(iTermMachineIdentity.pythonStatementsReturningToken())
    }

    /// The function's return value, or nil when it raised, the connection is gone, or the deadline
    /// passed.
    private func run(_ statements: String) async -> String? {
        guard let conductor, conductor.framing else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            var resumed = false
            let finish = { (value: String?) in
                guard !resumed else {
                    return
                }
                resumed = true
                continuation.resume(returning: value)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.deadline) {
                finish(nil)
            }
            conductor.framerExecPythonStatements(statements: statements) { ok, output in
                DispatchQueue.main.async {
                    if !ok {
                        DLog("Remote python failed: \(output)")
                    }
                    finish(ok ? output : nil)
                }
            }
        }
    }
}

@MainActor
enum ClaudeCodeRemoteHooks {
    enum InstallResult: Equatable {
        case installed
        /// The host is this Mac (ssh to localhost): its settings belong to the local install.
        case thisMac
        /// The host's machine identity couldn't be read, so it might be this Mac.
        case identityUnknown
        /// ~/.iterm2/bin/it2 is not there, so every hook would fail.
        case it2Missing
        case unreadable
        case malformed
        case writeFailed
    }

    static func wrapperPath(home: String) -> String {
        var trimmed = home
        while trimmed.count > 1 && trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed + "/.iterm2/bin/it2"
    }

    enum HostIdentity: Equatable {
        /// This Mac reached over ssh (localhost, or this Mac by another name).
        case thisMac
        /// Positively another machine.
        case elsewhere
        /// The machine token couldn't be read (no answer, a Mac that couldn't compute it, or a
        /// version this Mac doesn't implement). It might be this Mac.
        case unknown
    }

    static func hostIdentity(files: ClaudeCodeRemoteFiles) async -> HostIdentity {
        switch iTermMachineIdentity.locality(forToken: await files.machineToken()) {
        case .localhost:
            return .thisMac
        case .remote:
            return .elsewhere
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    /// Whether the host is known to be this Mac, reached over ssh. False when that couldn't be
    /// told, so callers that edit the host's files must use hostIdentity instead.
    static func hostIsThisMac(files: ClaudeCodeRemoteFiles) async -> Bool {
        return await hostIdentity(files: files) == .thisMac
    }

    static func install(files: ClaudeCodeRemoteFiles,
                        settingsPath: String,
                        home: String,
                        descriptor: AgentHookDescriptor = .claudeCode) async -> InstallResult {
        // The local install owns this Mac's settings, and adopting its entries would replace the
        // local hook command with the remote wrapper.
        switch await hostIdentity(files: files) {
        case .thisMac:
            RLog("Remote hook install refused: the host is this Mac")
            return .thisMac
        case .unknown:
            // It might be this Mac, whose settings the remote install must not touch.
            RLog("Remote hook install refused: could not tell whether the host is this Mac")
            return .identityUnknown
        case .elsewhere:
            break
        }
        guard await files.isExecutable(wrapperPath(home: home)) else {
            RLog("Remote hook install refused: the it2 wrapper is missing on the host")
            return .it2Missing
        }
        var settings: [String: Any]
        switch await files.read(settingsPath) {
        case .missing:
            settings = [:]
        case .failed(let reason):
            RLog("Remote hook install: could not read settings (\(reason))")
            return .unreadable
        case .contents(let data):
            // An unparseable file is not treated as empty: it is the user's, and overwriting it
            // would lose whatever was in it. A blank one is empty, as on this Mac.
            guard let parsed = ClaudeCodeHookSettings.settingsObjectIfValid(from: data) else {
                RLog("Remote hook install: settings are not a JSON object")
                return .malformed
            }
            settings = parsed
        }
        settings["hooks"] = ClaudeCodeHookSettings.merged(
            (settings["hooks"] as? [String: Any]) ?? [:],
            command: ClaudeCodeHookSettings.remoteHookCommand(descriptor: descriptor),
            descriptor: descriptor,
            isOurs: { ClaudeCodeHookSettings.isRemoteHookCommand($0, home: home) })
        guard let data = try? ClaudeCodeHookSettings.serialized(settings),
              await files.write(settingsPath, data) else {
            RLog("Remote hook install: could not write settings")
            return .writeFailed
        }
        return .installed
    }

    enum HookStatus: Equatable {
        /// Every event has our entry and the wrapper it runs is there.
        case healthy
        /// Some of our entries are there, but not all, or the wrapper is gone.
        case broken
        case notInstalled
        /// The settings could not be read or parsed, so nothing can be said.
        case unknown
    }

    /// What the host's own settings say. Nothing about remote hosts is kept on this Mac, so this
    /// is the only answer to "is the hook installed there?"
    static func status(files: ClaudeCodeRemoteFiles,
                       settingsPath: String,
                       home: String,
                       descriptor: AgentHookDescriptor = .claudeCode) async -> HookStatus {
        let settings: [String: Any]
        switch await files.read(settingsPath) {
        case .missing:
            return .notInstalled
        case .failed:
            return .unknown
        case .contents(let data):
            guard let parsed = ClaudeCodeHookSettings.settingsObjectIfValid(from: data) else {
                return .unknown
            }
            settings = parsed
        }
        let isOurs: (String) -> Bool = { ClaudeCodeHookSettings.isRemoteHookCommand($0, home: home) }
        // Something to strip means at least one of our entries is there.
        guard ClaudeCodeHookSettings.stripped(settings, descriptor: descriptor, isOurs: isOurs) != nil else {
            return .notInstalled
        }
        guard ClaudeCodeHookSettings.ourCommandsCoveringEveryEvent(settings,
                                                                   descriptor: descriptor,
                                                                   isOurs: isOurs) != nil,
              await files.isExecutable(wrapperPath(home: home)) else {
            return .broken
        }
        return .healthy
    }

    static func uninstall(files: ClaudeCodeRemoteFiles,
                          settingsPath: String,
                          home: String,
                          descriptor: AgentHookDescriptor = .claudeCode) async -> ClaudeCodeUninstallHooksResult {
        // As in install: this Mac's settings belong to the local uninstall, which has already
        // handled them. Nothing to do here.
        switch await hostIdentity(files: files) {
        case .thisMac:
            RLog("Remote hook uninstall skipped: the host is this Mac")
            return .success
        case .unknown:
            RLog("Remote hook uninstall refused: could not tell whether the host is this Mac")
            return .hostIdentityUnknown
        case .elsewhere:
            break
        }
        let settings: [String: Any]
        switch await files.read(settingsPath) {
        case .missing:
            return .success
        case .failed:
            return .unreadable
        case .contents(let data):
            guard let parsed = ClaudeCodeHookSettings.settingsObjectIfValid(from: data) else {
                return .malformed
            }
            settings = parsed
        }
        guard let stripped = ClaudeCodeHookSettings.stripped(
            settings,
            descriptor: descriptor,
            isOurs: { ClaudeCodeHookSettings.isRemoteHookCommand($0, home: home) }) else {
            return .success
        }
        guard let data = try? ClaudeCodeHookSettings.serialized(stripped),
              await files.write(settingsPath, data) else {
            return .writeFailed
        }
        return .success
    }
}

// MARK: - Per-host install, health and uninstall

extension ClaudeCodeOnboarding {
    /// CLAUDE_CONFIG_DIR on `conductor`'s host as its login shell reports it, looked up once per
    /// connection, with one lookup at a time. nil when the lookup failed: the caller must not
    /// guess. Delivers on the main thread.
    @MainActor
    static func remoteConfigDirectory(conductor: Conductor,
                                      facts: ClaudeCodeRemoteConnectionFacts = .shared,
                                      completion: @escaping (String?) -> Void) {
        facts.configDirectory(for: conductor,
                              lookUp: { [weak conductor] done in
            guard let conductor else {
                done(nil)
                return
            }
            resolveRemoteConfigDirectory(conductor: conductor, completion: done)
        },
                              completion: completion)
    }

    /// Where Claude Code keeps its settings on `conductor`'s host, or nil when that couldn't be
    /// found out. Status and uninstall then say they don't know, rather than read the default
    /// location and wrongly conclude the hook isn't there. Delivers on the main thread.
    @MainActor
    static func remoteSettingsPath(conductor: Conductor,
                                   facts: ClaudeCodeRemoteConnectionFacts = .shared,
                                   completion: @escaping (String?) -> Void) {
        guard let home = conductor.homeDirectory, !home.isEmpty else {
            completion(nil)
            return
        }
        remoteConfigDirectory(conductor: conductor, facts: facts) { directory in
            guard let directory else {
                RLog("Remote Claude Code settings: the config directory lookup failed")
                completion(nil)
                return
            }
            completion(ClaudeCodeRemoteConnectionFacts.settingsPath(configDirectory: directory, home: home))
        }
    }

    /// Installs the hook on the host `conductor` reaches, into `configDirectory` (resolved by
    /// resolveRemoteConfigDirectory). Nothing is recorded on this Mac beyond this connection.
    ///
    /// `grantAlwaysAllow` also mints an always-allow grant, so later connections' hooks are not
    /// met by the authorization prompt. That lets anything on the host see and control the
    /// user's terminal through the API without asking, which nobody would guess from "install the
    /// Claude Code integration". So it is a required argument, and the caller must have told the
    /// user exactly that and had them agree.
    ///
    /// `files` and `facts` are for tests; production passes neither.
    @MainActor
    static func installHooksRemotely(conductor: Conductor,
                                     configDirectory: String,
                                     grantAlwaysAllow: Bool,
                                     files: ClaudeCodeRemoteFiles? = nil,
                                     facts: ClaudeCodeRemoteConnectionFacts = .shared,
                                     completion: @escaping (ClaudeCodeRemoteHooks.InstallResult) -> Void) {
        guard let home = conductor.homeDirectory, !home.isEmpty else {
            RLog("Remote hook install: the remote home is unknown")
            completion(.unreadable)
            return
        }
        let access = files ?? ConductorClaudeCodeRemoteFiles(conductor: conductor)
        let settingsPath = ClaudeCodeRemoteConnectionFacts.settingsPath(configDirectory: configDirectory, home: home)
        Task { @MainActor in
            let result = await ClaudeCodeRemoteHooks.install(files: access,
                                                              settingsPath: settingsPath,
                                                              home: home)
            if result == .installed {
                facts.setConfigDirectory(configDirectory, for: conductor)
                facts.setHookPresent(true, for: conductor)
                if grantAlwaysAllow {
                    conductor.mintHostGrant()
                }
                RLog("Remote hook install complete (always-allow \(grantAlwaysAllow ? "granted" : "not granted"))")
            }
            completion(result)
        }
    }

    /// Whether `conductor`'s host is this Mac. Delivers on the main thread.
    @MainActor
    static func remoteHostIsThisMac(conductor: Conductor,
                                    files: ClaudeCodeRemoteFiles? = nil,
                                    completion: @escaping (Bool) -> Void) {
        let access = files ?? ConductorClaudeCodeRemoteFiles(conductor: conductor)
        Task { @MainActor in
            completion(await ClaudeCodeRemoteHooks.hostIsThisMac(files: access))
        }
    }

    /// The hook's state on `conductor`'s host, read from the host. Delivers on the main thread.
    @MainActor
    static func remoteHookStatus(conductor: Conductor,
                                 files: ClaudeCodeRemoteFiles? = nil,
                                 facts: ClaudeCodeRemoteConnectionFacts = .shared,
                                 completion: @escaping (ClaudeCodeRemoteHooks.HookStatus) -> Void) {
        remoteSettingsPath(conductor: conductor, facts: facts) { [weak conductor] settingsPath in
            guard let conductor, let settingsPath, let home = conductor.homeDirectory else {
                completion(.unknown)
                return
            }
            let access = files ?? ConductorClaudeCodeRemoteFiles(conductor: conductor)
            Task { @MainActor in
                let status = await ClaudeCodeRemoteHooks.status(files: access, settingsPath: settingsPath, home: home)
                switch status {
                case .healthy, .broken:
                    facts.setHookPresent(true, for: conductor)
                case .notInstalled:
                    facts.setHookPresent(false, for: conductor)
                case .unknown:
                    break
                }
                completion(status)
            }
        }
    }

    /// Whether the hook on `conductor`'s host is complete and runnable.
    @MainActor
    static func remoteHooksHealthy(conductor: Conductor,
                                   completion: @escaping (Bool) -> Void) {
        remoteHookStatus(conductor: conductor) { status in
            completion(status == .healthy)
        }
    }

    /// Removes the hook from `conductor`'s host. `revokeAlwaysAllow` also revokes the host's
    /// always-allow grant. Required, because the user must be asked: the grant may predate the
    /// install, and other uses of it2 on that host may depend on it.
    @MainActor
    static func uninstallHooksRemotely(conductor: Conductor,
                                       revokeAlwaysAllow: Bool,
                                       files: ClaudeCodeRemoteFiles? = nil,
                                       facts: ClaudeCodeRemoteConnectionFacts = .shared,
                                       completion: @escaping (ClaudeCodeUninstallHooksResult) -> Void) {
        let host = conductor.sshIdentity.stringIdentifier
        remoteSettingsPath(conductor: conductor, facts: facts) { [weak conductor] settingsPath in
            guard let conductor, let settingsPath, let home = conductor.homeDirectory else {
                completion(.unreadable)
                return
            }
            let access = files ?? ConductorClaudeCodeRemoteFiles(conductor: conductor)
            Task { @MainActor in
                let result = await ClaudeCodeRemoteHooks.uninstall(files: access, settingsPath: settingsPath, home: home)
                if result == .success {
                    facts.setHookPresent(false, for: conductor)
                    if revokeAlwaysAllow {
                        Conductor.hostGrantStore.revoke(host: host)
                    }
                }
                completion(result)
            }
        }
    }
}
