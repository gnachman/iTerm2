import Foundation

/// Shared, read-only discovery of terminal-backed harnesses, independent of this app's sessions.
final class HarnessProcessDiscovery {
    struct Harness: Equatable {
        let pid: Int32
        let started: Date
        let name: String
        let directory: String?
        let ancestors: [Int32]
        let tty: UInt64
        let tmuxSocket: String?
        let tmuxPane: String?
        // A multiplexer is evident (ancestor or environment) but no pane was proven. Never
        // treat such a harness as native: stopping it could close the pane that hosts it.
        var tmuxUnverified: Bool = false
        var id: String { "process:\(pid):\(started.timeIntervalSince1970)" }
        var isNative: Bool { tmuxSocket == nil && !tmuxUnverified }
    }

    /// Why a native harness cannot be transferred. Associated values are names only, never values.
    enum TransferBlock: Error, Equatable {
        case processChanged
        case unsupportedHarness
        case identityUnavailable
        case busy
        case insideMultiplexer
        case hostedByITerm
        case unsupportedArguments([String])
        case credentialEnvironment([String])
        case didNotExit
    }

    struct ConversationIdentity: Equatable {
        let conversationID: String
        let transcript: String
    }

    struct ResumeTarget: Equatable {
        let conversationID: String
        let transcript: String
        /// Complete argv for the replacement, including resume arguments and carried options.
        let command: [String]
    }

    static let shared = HarnessProcessDiscovery()
    private(set) var harnesses: [Harness] = []
    private var pending = false
    private var lastScan = Date.distantPast

    func refreshIfNeeded() {
        guard !pending, Date().timeIntervalSince(lastScan) >= 2 else { return }
        pending = true
        DispatchQueue.global(qos: .utility).async {
            let result = Self.scan()
            DispatchQueue.main.async {
                self.harnesses = result
                self.lastScan = Date()
                self.pending = false
            }
        }
    }

    static func scan() -> [Harness] {
        var result: [Harness] = []
        var serverPanes: [Int32: [HarnessTmuxProbe.ServerPane]] = [:]
        for number in iTermLSOF.currentUserPids() ?? [] {
            let pid = number.int32Value
            guard pid > 0 else { continue }
            let tty = terminalDevice(of: pid)
            // Exclude MCP servers and app-internal workers connected only through pipes.
            guard tty != 0 else { continue }
            var executable: NSString?
            guard let args = iTermLSOF.rawCommandLineArguments(forProcess: pid, execName: &executable),
                  let name = SessionDirectoryKey.harnessName(executable: args.first, arguments: args)
                    ?? SessionDirectoryKey.harnessName(executable: executable as String?, arguments: args),
                  let started = iTermLSOF.startTime(forProcess: pid) else { continue }
            let ancestors = ancestors(of: pid)
            // Inspect only matched harness environments and retain only tmux identity.
            let environment = inspectableEnvironment(pid)
            var pane = environment?.first { $0.hasPrefix("TMUX_PANE=") }.map { String($0.dropFirst(10)) }
            var socket = environment?.first { $0.hasPrefix("TMUX=") }.flatMap { socketPath(String($0.dropFirst(5))) }
            // Teerminal and other launchers may intentionally clear the pane environment.
            // Match a real pane PID (or its descendant) on an ancestor tmux server instead.
            if socket == nil || pane == nil {
                socket = nil
                pane = nil
                for ancestor in ancestors {
                    let panes: [HarnessTmuxProbe.ServerPane]
                    if let cached = serverPanes[ancestor] { panes = cached }
                    else {
                        panes = HarnessTmuxProbe.serverPanes(pid: ancestor)
                        serverPanes[ancestor] = panes
                    }
                    if let match = panes.first(where: { $0.pid == pid || ancestors.contains($0.pid) }) {
                        socket = match.socket
                        pane = match.id
                        break
                    }
                }
            }
            let proven = socket != nil && pane != nil
            let evident = multiplexerEvident(ancestorNames: ancestors.map(processName), environment: environment)
            result.append(Harness(pid: pid, started: started, name: name,
                directory: iTermLSOF.workingDirectory(ofProcess: pid), ancestors: ancestors,
                tty: tty, tmuxSocket: proven ? socket : nil, tmuxPane: proven ? pane : nil,
                tmuxUnverified: evident && !proven))
        }
        return deduplicated(result).sorted {
            $0.started == $1.started ? $0.pid < $1.pid : $0.started < $1.started
        }
    }

    // MARK: - Process facts

    private static func terminalDevice(of pid: Int32) -> UInt64 {
        let input = iTermLSOF.ttyRdev(forFileDescriptor: 0, ofProcess: pid)
        return UInt64(UInt32(bitPattern: input != 0 ? input : iTermLSOF.ttyRdev(forFileDescriptor: 1, ofProcess: pid)))
    }

    private static func ancestors(of pid: Int32) -> [Int32] {
        var result: [Int32] = []
        var parent = iTermLSOF.ppid(forPid: pid)
        while parent > 1 && !result.contains(parent) && result.count < 128 {
            result.append(parent)
            parent = iTermLSOF.ppid(forPid: parent)
        }
        return result
    }

    private static func processName(_ pid: Int32) -> String {
        var executable: NSString?
        let args = iTermLSOF.rawCommandLineArguments(forProcess: pid, execName: &executable) ?? []
        return [executable as String?, args.first].compactMap { $0 }.joined(separator: "\u{1f}")
    }

    /// nil when the environment cannot be read. An empty block is treated the same: a harness
    /// always has one, and a failed or truncated read proves nothing about tmux or credentials.
    static func inspectableEnvironment(_ environment: [String]?) -> [String]? {
        guard let environment, !environment.isEmpty else { return nil }
        return environment
    }

    private static func inspectableEnvironment(_ pid: Int32) -> [String]? {
        inspectableEnvironment(iTermLSOF.environment(forProcess: pid))
    }

    /// Device number of a terminal path such as PTYSession.tty, for protected-terminal checks.
    static func ttyRdev(path: String) -> UInt64? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFCHR else { return nil }
        return UInt64(UInt32(bitPattern: info.st_rdev))
    }

    private static let multiplexers: Set<String> = ["tmux", "screen", "zellij", "dtach", "abduco"]
    private static let multiplexerVariables = ["TMUX=", "TMUX_PANE=", "STY=", "ZELLIJ=", "ZELLIJ_SESSION_NAME="]

    /// True when any ancestor looks like a terminal multiplexer or the environment names one.
    /// Ancestor names may hold several candidates (executable path and argv[0]) joined by U+001F.
    /// An uninspectable environment (nil) counts as evidence, so the harness is never assumed native.
    static func multiplexerEvident(ancestorNames: [String], environment: [String]?) -> Bool {
        guard let environment else { return true }
        if environment.contains(where: { variable in multiplexerVariables.contains { variable.hasPrefix($0) } }) {
            return true
        }
        return ancestorNames.contains { names in
            names.split(separator: "\u{1f}").contains { candidate in
                // argv[0] may be "tmux: server", "-tmux", or "SCREEN".
                let word = candidate.split(separator: " ").first.map(String.init) ?? ""
                var base = (word as NSString).lastPathComponent.lowercased()
                while base.hasPrefix("-") { base.removeFirst() }
                while base.hasSuffix(":") { base.removeLast() }
                return multiplexers.contains(base)
            }
        }
    }

    // MARK: - Conversation identity

    static func conversationID(harness: String, path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let stem = url.deletingPathExtension().lastPathComponent
        let candidate: String
        switch harness {
        case "Codex":
            guard path.contains("/sessions/"), url.pathExtension == "jsonl", stem.hasPrefix("rollout-") else { return nil }
            candidate = String(stem.suffix(36))
        case "Claude":
            guard path.contains("/projects/"), url.pathExtension == "jsonl" else { return nil }
            candidate = stem
        case "Antigravity":
            guard path.contains("/conversations/"), url.pathExtension == "db" else { return nil }
            candidate = stem
        default: return nil
        }
        return UUID(uuidString: candidate)?.uuidString.lowercased()
    }

    /// Accept a Claude session record only when the live process corroborates it: the record
    /// names this PID and start time, was updated during this run, and the process holds the
    /// record's messaging socket. Claude rewrites sessionId in this record on /clear.
    static func claudeRecordSessionID(_ record: [String: Any], pid: Int32, processStart: Date,
                                      heldSockets: Set<String>) -> Result<String, TransferBlock> {
        guard (record["pid"] as? NSNumber)?.int32Value == pid,
              let id = record["sessionId"] as? String, let uuid = UUID(uuidString: id),
              let started = (record["startedAt"] as? NSNumber)?.doubleValue,
              abs(started / 1000 - processStart.timeIntervalSince1970) < 10,
              let updated = (record["updatedAt"] as? NSNumber)?.doubleValue,
              updated / 1000 >= processStart.timeIntervalSince1970 - 1,
              let socket = record["messagingSocketPath"] as? String, socket.hasPrefix("/"),
              heldSockets.contains(socket) || heldSockets.contains((socket as NSString).resolvingSymlinksInPath) else {
            return .failure(.identityUnavailable)
        }
        guard record["status"] as? String == "idle" else { return .failure(.busy) }
        return .success(uuid.uuidString.lowercased())
    }

    private static func heldSockets(_ pid: Int32) -> Set<String> {
        Set((iTermLSOF.fileDescriptors(forProcess: pid) ?? []).flatMap { descriptor -> [String] in
            guard descriptor.type == "unix", let path = descriptor.detail, path.hasPrefix("/") else { return [] }
            return [path, (path as NSString).resolvingSymlinksInPath]
        })
    }

    // Read only process-linked evidence. Never choose the most recent conversation by directory or mtime.
    static func conversationIdentity(for harness: Harness) -> Result<ConversationIdentity, TransferBlock> {
        guard iTermLSOF.startTime(forProcess: harness.pid) == harness.started else { return .failure(.processChanged) }
        // CLAUDE_CONFIG_DIR locates the session record; without the environment the root is unknown.
        guard let environment = inspectableEnvironment(harness.pid) else { return .failure(.identityUnavailable) }
        let pids = (iTermLSOF.currentUserPids() ?? []).map { $0.int32Value }
        let parents = Dictionary(pids.map { ($0, iTermLSOF.ppid(forPid: $0)) }, uniquingKeysWith: { first, _ in first })
        var descendants: Set<Int32> = [harness.pid]
        for _ in 0..<8 {
            let next = Set(pids.filter { parents[$0].map { descendants.contains($0) } ?? false })
            let before = descendants.count
            descendants.formUnion(next)
            if descendants.count == before { break }
        }
        var candidates: [String: String] = [:]
        for pid in descendants {
            guard pid == harness.pid || terminalDevice(of: pid) == harness.tty else { continue }
            for descriptor in iTermLSOF.fileDescriptors(forProcess: pid) ?? [] where descriptor.type == "file" {
                guard let path = descriptor.detail, let id = conversationID(harness: harness.name, path: path) else { continue }
                candidates[id] = path
            }
            if harness.name == "Claude" {
                let custom = environment.first { $0.hasPrefix("CLAUDE_CONFIG_DIR=") }.map { String($0.dropFirst(18)) }
                let root = URL(fileURLWithPath: custom ?? NSHomeDirectory() + "/.claude")
                guard let data = try? Data(contentsOf: root.appendingPathComponent("sessions/\(pid).json")),
                      let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let start = iTermLSOF.startTime(forProcess: pid) else { continue }
                let id: String
                switch claudeRecordSessionID(record, pid: pid, processStart: start, heldSockets: heldSockets(pid)) {
                case .success(let value): id = value
                case .failure(.busy): return .failure(.busy)
                case .failure: continue
                }
                let projects = root.appendingPathComponent("projects")
                var transcripts: [String] = []
                for directory in (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
                    let transcript = directory.appendingPathComponent(id + ".jsonl")
                    if FileManager.default.fileExists(atPath: transcript.path) { transcripts.append(transcript.path) }
                }
                // A corroborated record whose transcript is missing or duplicated is not proof.
                guard transcripts.count == 1 else { return .failure(.identityUnavailable) }
                if let existing = candidates[id], existing != transcripts[0] { return .failure(.identityUnavailable) }
                candidates[id] = transcripts[0]
            }
        }
        guard candidates.count == 1, let (id, path) = candidates.first,
              iTermLSOF.startTime(forProcess: harness.pid) == harness.started else {
            return .failure(.identityUnavailable)
        }
        return .success(ConversationIdentity(conversationID: id, transcript: path))
    }

    // MARK: - Launch arguments

    private enum Arity {
        case flag
        case value
        case optionalValue
        case list
    }

    private struct LaunchPolicy {
        let aliases: [String: String]
        let carry: [String: Arity]
        let strip: [String: Arity]
        let allowedValues: [String: Set<String>]
        let absolutePaths: Set<String>
        // Go's flag package accepts -name as well as --name.
        let singleDashLong: Bool
        let resumeSubcommand: String?
    }

    // Carry only options listed by the harness's own resume help. Options that change permissions
    // beyond prompting, choose another launch mode, or supply a prompt are refused.
    private static func launchPolicy(_ harness: String) -> LaunchPolicy? {
        switch harness {
        case "Claude":
            // Verified with Claude Code 2.1.281 `claude --help`; options apply alongside --resume.
            return LaunchPolicy(
                aliases: ["-c": "--continue", "-r": "--resume",
                          "--allowed-tools": "--allowedTools", "--disallowed-tools": "--disallowedTools"],
                carry: ["--model": .value, "--permission-mode": .value, "--settings": .value,
                        "--effort": .value, "--fallback-model": .value,
                        "--add-dir": .list, "--allowedTools": .list, "--disallowedTools": .list,
                        "--mcp-config": .list, "--strict-mcp-config": .flag, "--verbose": .flag,
                        "--ide": .flag, "--chrome": .flag, "--no-chrome": .flag],
                strip: ["--continue": .flag, "--resume": .optionalValue, "--session-id": .value,
                        "--fork-session": .flag],
                allowedValues: ["--permission-mode": ["default", "acceptEdits", "plan", "auto"]],
                absolutePaths: [], singleDashLong: false, resumeSubcommand: nil)
        case "Codex":
            // Verified with codex-cli 0.156.1 `codex resume --help`.
            return LaunchPolicy(
                aliases: ["-m": "--model", "-p": "--profile", "-c": "--config",
                          "-s": "--sandbox", "-a": "--ask-for-approval"],
                carry: ["--model": .value, "--profile": .value, "--config": .value,
                        "--enable": .value, "--disable": .value, "--local-provider": .value,
                        "--sandbox": .value, "--ask-for-approval": .value, "--add-dir": .value,
                        "--oss": .flag, "--search": .flag, "--no-alt-screen": .flag, "--strict-config": .flag],
                strip: ["--last": .flag, "--all": .flag, "--include-non-interactive": .flag],
                allowedValues: ["--sandbox": ["read-only", "workspace-write"],
                                "--ask-for-approval": ["untrusted", "on-request", "on-failure"]],
                absolutePaths: ["--add-dir"], singleDashLong: false, resumeSubcommand: "resume")
        case "Antigravity":
            // Verified with `agy --help`; --conversation is a top-level option.
            return LaunchPolicy(
                aliases: ["-c": "--continue"],
                carry: ["--model": .value, "--agent": .value, "--effort": .value, "--mode": .value,
                        "--project": .value, "--add-dir": .value, "--sandbox": .flag],
                strip: ["--continue": .flag, "--conversation": .value],
                allowedValues: ["--effort": ["low", "medium", "high"], "--mode": ["accept-edits", "plan"]],
                absolutePaths: ["--add-dir"], singleDashLong: true, resumeSubcommand: nil)
        default:
            return nil
        }
    }

    // Codex config keys that grant what a refused permission flag would.
    private static func codexConfigAllowed(_ value: String) -> Bool {
        let key = value.split(separator: "=", maxSplits: 1).first.map { $0.lowercased() } ?? ""
        return !["sandbox", "approval", "permission", "danger", "bypass", "trust"].contains { key.contains($0) }
    }

    static let promptArgument = "<prompt>"

    /// Options from the original launch that the replacement must keep. Anything not verified
    /// safe with resume is refused by name so the caller can explain it; values are never reported.
    static func carriedArguments(harness: String, arguments: [String]) -> Result<[String], TransferBlock> {
        guard let policy = launchPolicy(harness) else { return .failure(.unsupportedHarness) }
        var carried: [String] = []
        var refused: [String] = []
        func refuse(_ name: String) { if !refused.contains(name) { refused.append(name) } }
        var sawPositional = false
        var sawSubcommand = false
        var sawSubcommandID = false
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            index += 1
            guard token.hasPrefix("-"), token != "-" else {
                // The first positional may be the resume subcommand; its single session ID is replaced.
                if let subcommand = policy.resumeSubcommand, !sawPositional, token == subcommand {
                    sawSubcommand = true
                } else if sawSubcommand && !sawSubcommandID {
                    sawSubcommandID = true
                } else {
                    refuse(promptArgument)
                }
                sawPositional = true
                continue
            }
            if token == "--" {
                refuse(promptArgument)
                break
            }
            var name = token
            var inline: String?
            if let equals = token.firstIndex(of: "="), token.hasPrefix("--") || policy.singleDashLong {
                name = String(token[..<equals])
                inline = String(token[token.index(after: equals)...])
            }
            if policy.singleDashLong, !name.hasPrefix("--"), name.count > 2 { name = "-" + name }
            let canonical = policy.aliases[name] ?? name
            let isStripped = policy.strip[canonical] != nil
            guard let arity = policy.strip[canonical] ?? policy.carry[canonical] else {
                refuse(name)
                continue
            }
            var values: [String] = []
            switch arity {
            case .flag:
                if inline != nil { refuse(name) }
            case .value:
                if let inline {
                    values = [inline]
                } else if index < arguments.count {
                    values = [arguments[index]]
                    index += 1
                } else {
                    refuse(name)
                }
            case .optionalValue:
                if let inline {
                    values = [inline]
                } else if index < arguments.count, !arguments[index].hasPrefix("-") {
                    values = [arguments[index]]
                    index += 1
                }
            case .list:
                if let inline { values = [inline] }
                while index < arguments.count, !arguments[index].hasPrefix("-") {
                    values.append(arguments[index])
                    index += 1
                }
                if values.isEmpty { refuse(name) }
            }
            if isStripped { continue }
            let valid = values.allSatisfy { value in
                (policy.allowedValues[canonical]?.contains(value) ?? true) &&
                    (!policy.absolutePaths.contains(canonical) || value.hasPrefix("/")) &&
                    (harness != "Codex" || canonical != "--config" || codexConfigAllowed(value))
            }
            guard valid else {
                refuse(name)
                continue
            }
            carried.append(token)
            if inline == nil { carried += values }
        }
        return refused.isEmpty ? .success(carried) : .failure(.unsupportedArguments(refused))
    }

    static func resumeArguments(harness: String, conversationID: String, carried: [String]) -> [String]? {
        // Require a specific identity, never an option or an implicit latest conversation.
        guard let uuid = UUID(uuidString: conversationID)?.uuidString.lowercased() else { return nil }
        switch harness {
        case "Codex": return ["resume"] + carried + [uuid]
        case "Claude": return carried + ["--resume", uuid]
        case "Antigravity": return carried + ["--conversation", uuid]
        default: return nil
        }
    }

    // MARK: - Environment

    // Non-secret provider routing. The replacement gets exactly the original's values, and
    // variables the original lacked are removed so iTerm2's own environment cannot change routing.
    private static let routingVariables = ["CODEX_HOME", "CLAUDE_CONFIG_DIR", "ANTHROPIC_BASE_URL",
        "ANTHROPIC_MODEL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "AWS_PROFILE",
        "AWS_REGION", "OPENAI_BASE_URL"]
    // Credentials are never copied into a command line. They must already match iTerm2's environment.
    private static let credentialVariables = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN",
        "CLAUDE_CODE_OAUTH_TOKEN", "OPENAI_API_KEY", "CODEX_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY",
        "GOOGLE_APPLICATION_CREDENTIALS", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY",
        "AWS_SESSION_TOKEN", "AWS_BEARER_TOKEN_BEDROCK"]

    /// Returns the /usr/bin/env arguments (without the executable) that reproduce the original's
    /// provider environment, or the names of credentials the replacement could not reproduce.
    static func environmentArguments(original: [String], app: [String: String]) -> Result<[String], TransferBlock> {
        var values: [String: String] = [:]
        for entry in original {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            values[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }
        var unset: [String] = []
        var assignments: [String] = []
        var mismatched: [String] = []
        for name in credentialVariables {
            if let value = values[name] {
                if app[name] != value { mismatched.append(name) }
            } else if app[name] != nil {
                unset += ["-u", name]
            }
        }
        guard mismatched.isEmpty else { return .failure(.credentialEnvironment(mismatched)) }
        for name in routingVariables {
            if let value = values[name] {
                assignments.append(name + "=" + value)
            } else if app[name] != nil {
                unset += ["-u", name]
            }
        }
        return .success(unset + assignments)
    }

    // MARK: - Transfer

    private static func hostingBlock(_ harness: Harness, protectedTTYs: Set<UInt64>) -> TransferBlock? {
        let current = terminalDevice(of: harness.pid)
        if protectedTTYs.contains(harness.tty) || (current != 0 && protectedTTYs.contains(current)) ||
            ancestors(of: harness.pid).contains(getpid()) {
            return .hostedByITerm
        }
        return nil
    }

    private static func multiplexerBlock(_ harness: Harness, environment: [String]?) -> TransferBlock? {
        if !harness.isNative ||
            multiplexerEvident(ancestorNames: ancestors(of: harness.pid).map(processName), environment: environment) {
            return .insideMultiplexer
        }
        return nil
    }

    /// Blocking; call off the main thread. Proves identity, launch options and environment,
    /// and refuses anything it cannot reproduce or that iTerm2 or a multiplexer hosts.
    static func resumeTarget(for harness: Harness, protectedTTYs: Set<UInt64>) -> Result<ResumeTarget, TransferBlock> {
        guard iTermLSOF.startTime(forProcess: harness.pid) == harness.started else { return .failure(.processChanged) }
        guard launchPolicy(harness.name) != nil else { return .failure(.unsupportedHarness) }
        if let block = hostingBlock(harness, protectedTTYs: protectedTTYs) {
            return .failure(block)
        }
        // Fail closed: without the environment neither native status nor credentials can be proven.
        guard let originalEnvironment = inspectableEnvironment(harness.pid) else {
            return .failure(multiplexerBlock(harness, environment: []) ?? .identityUnavailable)
        }
        if let block = multiplexerBlock(harness, environment: originalEnvironment) {
            return .failure(block)
        }
        var executableName: NSString?
        guard let arguments = iTermLSOF.rawCommandLineArguments(forProcess: harness.pid, execName: &executableName),
              let executable = executableName as String?, executable.hasPrefix("/") else {
            return .failure(.processChanged)
        }
        var prefix = [executable]
        var harnessArguments = Array(arguments.dropFirst())
        if (executable as NSString).lastPathComponent == "node" {
            guard let script = harnessArguments.first, script.hasPrefix("/") else { return .failure(.unsupportedHarness) }
            prefix.append(script)
            harnessArguments.removeFirst()
        }
        let carried: [String]
        switch carriedArguments(harness: harness.name, arguments: harnessArguments) {
        case .success(let value): carried = value
        case .failure(let block): return .failure(block)
        }
        let environment: [String]
        switch environmentArguments(original: originalEnvironment,
                                     app: ProcessInfo.processInfo.environment) {
        case .success(let value): environment = value
        case .failure(let block): return .failure(block)
        }
        let identity: ConversationIdentity
        switch conversationIdentity(for: harness) {
        case .success(let value): identity = value
        case .failure(let block): return .failure(block)
        }
        guard let resume = resumeArguments(harness: harness.name, conversationID: identity.conversationID,
                                           carried: carried) else {
            return .failure(.identityUnavailable)
        }
        let envPrefix = environment.isEmpty ? [] : ["/usr/bin/env"] + environment
        return .success(ResumeTarget(conversationID: identity.conversationID, transcript: identity.transcript,
                                     command: envPrefix + prefix + resume))
    }

    /// Called only after the user chooses Transfer and a recovery record has been saved.
    /// Re-proves the whole target, then sends SIGTERM only. Never signals a terminal shell,
    /// tmux server, process group, or a reused PID, and never force-kills.
    static func stopForTransfer(_ harness: Harness, target: ResumeTarget, protectedTTYs: Set<UInt64>,
                                completion: @escaping (Result<Void, TransferBlock>) -> Void) {
        func finish(_ result: Result<Void, TransferBlock>) { DispatchQueue.main.async { completion(result) } }
        DispatchQueue.global(qos: .utility).async {
            switch resumeTarget(for: harness, protectedTTYs: protectedTTYs) {
            case .failure(let block):
                finish(.failure(block))
                return
            case .success(let current):
                guard current == target,
                      let size = try? FileManager.default.attributesOfItem(atPath: target.transcript)[.size] as? NSNumber,
                      size.intValue > 0 else {
                    finish(.failure(.identityUnavailable))
                    return
                }
            }
            // Include the actual native harness behind an npm launcher, but not its tools.
            var targets: [(Int32, Date)] = [(harness.pid, harness.started)]
            for number in iTermLSOF.currentUserPids() ?? [] {
                let pid = number.int32Value
                var parent = iTermLSOF.ppid(forPid: pid)
                var seen = Set<Int32>()
                while parent > 1 && parent != harness.pid && seen.insert(parent).inserted {
                    parent = iTermLSOF.ppid(forPid: parent)
                }
                guard parent == harness.pid,
                      terminalDevice(of: pid) == harness.tty,
                      let args = iTermLSOF.rawCommandLineArguments(forProcess: pid, execName: nil),
                      SessionDirectoryKey.harnessName(executable: args.first, arguments: args) == harness.name,
                      let started = iTermLSOF.startTime(forProcess: pid),
                      !targets.contains(where: { $0.0 == pid }) else { continue }
                targets.append((pid, started))
            }
            guard signalTransferProcesses(targets) else {
                finish(.failure(.processChanged))
                return
            }
            waitForTransferExit(targets, deadline: .now() + 15) { exited in
                completion(exited ? .success(()) : .failure(.didNotExit))
            }
        }
    }

    static func signalTransferProcesses(_ targets: [(Int32, Date)]) -> Bool {
        // Validate the entire snapshot before signaling any process.
        guard !targets.isEmpty, targets.allSatisfy({ pid, started in
            pid > 1 && pid != getpid() && iTermLSOF.startTime(forProcess: pid) == started
        }) else { return false }
        for (pid, started) in targets.reversed() {
            guard iTermLSOF.startTime(forProcess: pid) == started else { continue }
            if kill(pid, SIGTERM) != 0 && errno != ESRCH { return false }
        }
        return true
    }

    static func waitForTransferExit(_ targets: [(Int32, Date)], deadline: DispatchTime,
                                    completion: @escaping (Bool) -> Void) {
        let exited = targets.allSatisfy { iTermLSOF.startTime(forProcess: $0.0) != $0.1 }
        if exited || DispatchTime.now() >= deadline {
            DispatchQueue.main.async { completion(exited) }
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) {
            waitForTransferExit(targets, deadline: deadline, completion: completion)
        }
    }

    static func socketPath(_ tmux: String) -> String? {
        let fields = tmux.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count >= 3 else { return nil }
        let path = fields.dropLast(2).joined(separator: ",")
        return path.hasPrefix("/") ? path : nil
    }

    static func deduplicated(_ items: [Harness]) -> [Harness] {
        // The npm launcher and its native executable share a terminal and represent one run.
        items.filter { item in
            !items.contains { parent in
                parent.name == item.name && parent.tty == item.tty && item.ancestors.contains(parent.pid)
            }
        }
    }
}
