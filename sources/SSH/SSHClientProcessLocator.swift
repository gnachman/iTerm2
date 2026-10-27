//
//  SSHClientProcessLocator.swift
//  iTerm2SharedARC
//
//  Finds out whether a session's job still runs an it2ssh or ssh client, such as after
//  iTerm2 restarted and reattached to it (F-786).
//

import Foundation

protocol SSHClientProcessInspecting {
    func arguments(of pid: pid_t) -> [String]?
    // Returns [] if unknown.
    func childPIDs(of pid: pid_t) -> [pid_t]
}

struct SystemSSHClientProcessInspector: SSHClientProcessInspecting {
    func arguments(of pid: pid_t) -> [String]? {
        return iTermLSOF.commandLineArguments(forProcess: pid, execName: nil)
    }

    func childPIDs(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 256)
        let count = buffer.withUnsafeMutableBytes { pointer in
            proc_listchildpids(pid, pointer.baseAddress, Int32(pointer.count))
        }
        // A full buffer may have dropped some children.
        guard count > 0, Int(count) < buffer.count else {
            return []
        }
        return Array(buffer.prefix(Int(count)))
    }
}

@objc(iTermSSHClientProcessLocator)
final class SSHClientProcessLocator: NSObject {
    private static let it2sshName = "it2ssh"
    private let inspector: SSHClientProcessInspecting

    @objc(sharedInstance) static let shared = SSHClientProcessLocator(inspector: SystemSSHClientProcessInspector())

    init(inspector: SSHClientProcessInspecting) {
        self.inspector = inspector
    }

    // Whether an it2ssh or ssh client runs under `root`, such as a session's job after
    // iTerm2 restarted. Reattaching to the job proves only that its shell survived (F-786).
    @objc(hasSSHClientAmongDescendantsOf:)
    func hasSSHClient(amongDescendantsOf root: pid_t) -> Bool {
        guard root > 0 else {
            return false
        }
        if let args = inspector.arguments(of: root), Self.isSSHClient(arguments: args) {
            // An SSH profile's session runs it2ssh itself.
            return true
        }
        // A login shell under login, it2ssh under the shell, and ssh under it2ssh, with room
        // for a wrapper or two.
        let maximumDepth = 6
        var frontier = [root]
        var visited = Set<pid_t>()
        for _ in 0..<maximumDepth {
            var next = [pid_t]()
            for pid in frontier where !visited.contains(pid) {
                visited.insert(pid)
                for child in inspector.childPIDs(of: pid) {
                    if let args = inspector.arguments(of: child),
                       Self.isSSHClient(arguments: args) {
                        return true
                    }
                    next.append(child)
                }
            }
            frontier = next
        }
        return false
    }

    private static func isSSHClient(arguments args: [String]) -> Bool {
        if let first = args.first, (first as NSString).lastPathComponent == "ssh" {
            return true
        }
        return args.contains { ($0 as NSString).lastPathComponent == it2sshName }
    }
}
