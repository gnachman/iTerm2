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
            let pane = environment.first { $0.hasPrefix("TMUX_PANE=") }.map { String($0.dropFirst(10)) }
            let socket = tmux.flatMap(socketPath)
            result.append(Harness(pid: pid, started: started, name: name,
                directory: iTermLSOF.workingDirectory(ofProcess: pid), ancestors: ancestors,
                tty: UInt64(tty), tmuxSocket: socket, tmuxPane: pane))
        }
        return deduplicated(result).sorted {
            $0.started == $1.started ? $0.pid < $1.pid : $0.started < $1.started
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
