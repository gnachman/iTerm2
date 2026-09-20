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
        var id: String { "process:\(pid):\(started.timeIntervalSince1970)" }
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
            let inputTTY = iTermLSOF.ttyRdev(forFileDescriptor: 0, ofProcess: pid)
            let tty = inputTTY != 0 ? inputTTY : iTermLSOF.ttyRdev(forFileDescriptor: 1, ofProcess: pid)
            // Exclude MCP servers and app-internal workers connected only through pipes.
            guard tty != 0 else { continue }
            var executable: NSString?
            guard let args = iTermLSOF.rawCommandLineArguments(forProcess: pid, execName: &executable),
                  let name = SessionDirectoryKey.harnessName(executable: args.first, arguments: args)
                    ?? SessionDirectoryKey.harnessName(executable: executable as String?, arguments: args),
                  let started = iTermLSOF.startTime(forProcess: pid) else { continue }
            var ancestors: [Int32] = []
            var parent = iTermLSOF.ppid(forPid: pid)
            while parent > 1 && !ancestors.contains(parent) && ancestors.count < 128 {
                ancestors.append(parent)
                parent = iTermLSOF.ppid(forPid: parent)
            }
            // Inspect only matched harness environments and retain only tmux identity.
            let environment = iTermLSOF.environment(forProcess: pid) ?? []
            let tmux = environment.first { $0.hasPrefix("TMUX=") }.map { String($0.dropFirst(5)) }
            var pane = environment.first { $0.hasPrefix("TMUX_PANE=") }.map { String($0.dropFirst(10)) }
            var socket = tmux.flatMap(socketPath)
            // Teerminal and other launchers may intentionally clear the pane environment.
            // Match a real pane PID (or its descendant) on an ancestor tmux server instead.
            if socket == nil || pane == nil {
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
            result.append(Harness(pid: pid, started: started, name: name,
                directory: iTermLSOF.workingDirectory(ofProcess: pid), ancestors: ancestors,
                tty: UInt64(tty), tmuxSocket: socket, tmuxPane: pane))
        }
        return deduplicated(result).sorted {
            $0.started == $1.started ? $0.pid < $1.pid : $0.started < $1.started
        }
    }

    struct ResumeTarget {
        let conversationID: String
        let transcript: String
        let commandPrefix: [String]
    }

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

    // Read only process-linked evidence. Never choose the most recent conversation by directory.
    static func resumeTarget(for harness: Harness) -> ResumeTarget? {
        guard iTermLSOF.startTime(forProcess: harness.pid) == harness.started else { return nil }
        var executableName: NSString?
        guard let arguments = iTermLSOF.rawCommandLineArguments(forProcess: harness.pid, execName: &executableName),
              let executable = executableName as String?, executable.hasPrefix("/") else { return nil }
        var prefix = [executable]
        if (executable as NSString).lastPathComponent == "node" {
            guard arguments.count > 1 else { return nil }
            prefix.append(arguments[1])
        }
        let environment = iTermLSOF.environment(forProcess: harness.pid) ?? []
        // Preserve provider-specific history locations, not unrelated process environment.
        let providerEnvironment = environment.filter {
            $0.hasPrefix("CODEX_HOME=") || $0.hasPrefix("CLAUDE_CONFIG_DIR=")
        }
        if !providerEnvironment.isEmpty { prefix = ["/usr/bin/env"] + providerEnvironment + prefix }
        let pids = (iTermLSOF.currentUserPids() ?? []).map { $0.int32Value }
        let parents = Dictionary(uniqueKeysWithValues: pids.map { ($0, iTermLSOF.ppid(forPid: $0)) })
        var descendants: Set<Int32> = [harness.pid]
        for _ in 0..<8 {
            let next = Set(pids.filter { parents[$0].map { descendants.contains($0) } ?? false })
            let before = descendants.count
            descendants.formUnion(next)
            if descendants.count == before { break }
        }
        var candidates: [String: String] = [:]
        for pid in descendants {
            let tty = iTermLSOF.ttyRdev(forFileDescriptor: 0, ofProcess: pid)
            guard pid == harness.pid || UInt64(tty) == harness.tty else { continue }
            for descriptor in iTermLSOF.fileDescriptors(forProcess: pid) ?? [] where descriptor.type == "file" {
                guard let path = descriptor.detail, let id = conversationID(harness: harness.name, path: path) else { continue }
                candidates[id] = path
            }
            if harness.name == "Claude" {
                let custom = environment.first { $0.hasPrefix("CLAUDE_CONFIG_DIR=") }.map { String($0.dropFirst(18)) }
                let root = URL(fileURLWithPath: custom ?? NSHomeDirectory() + "/.claude")
                let recordURL = root.appendingPathComponent("sessions/\(pid).json")
                guard let data = try? Data(contentsOf: recordURL),
                      let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      (record["pid"] as? NSNumber)?.int32Value == pid,
                      let id = record["sessionId"] as? String, UUID(uuidString: id) != nil,
                      let started = record["startedAt"] as? Double,
                      abs(started / 1000 - (iTermLSOF.startTime(forProcess: pid)?.timeIntervalSince1970 ?? 0)) < 10 else { continue }
                let projects = root.appendingPathComponent("projects")
                for directory in (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
                    let transcript = directory.appendingPathComponent(id + ".jsonl")
                    if FileManager.default.fileExists(atPath: transcript.path) { candidates[id.lowercased()] = transcript.path }
                }
            }
        }
        guard candidates.count == 1, let (id, path) = candidates.first,
              iTermLSOF.startTime(forProcess: harness.pid) == harness.started else { return nil }
        return ResumeTarget(conversationID: id, transcript: path, commandPrefix: prefix)
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
