//
//  SSHClientMonitor.swift
//  iTerm2SharedARC
//
//  Detects the death of an it2ssh process that would otherwise leave its SSH
//  Integration session's conductor hook installed forever (F-482).
//
//  When it2ssh runs on this Mac it fetches a secret from SecretServer's unix socket
//  with nc. The socket peer's ancestry, recorded at accept time, leads back to it2ssh,
//  so once the conductor hooks with that secret iTerm2 can watch the it2ssh process.
//  When it2ssh runs elsewhere (e.g., on a host reached by a plain ssh, or nested
//  within another SSH Integration session) it can't be watched, and the best sign of
//  its death is a prompt mark that arrives outside the conductor's framing.
//

import Foundation

protocol SSHClientProcessInspecting {
    // Returns 0 if unknown.
    func parentPID(of pid: pid_t) -> pid_t
    // Returns nil if the process does not exist.
    func startTime(of pid: pid_t) -> Date?
    func arguments(of pid: pid_t) -> [String]?
}

struct SystemSSHClientProcessInspector: SSHClientProcessInspecting {
    func parentPID(of pid: pid_t) -> pid_t {
        return iTermLSOF.ppid(forPid: pid)
    }

    func startTime(of pid: pid_t) -> Date? {
        return iTermLSOF.startTime(forProcess: pid)
    }

    func arguments(of pid: pid_t) -> [String]? {
        return iTermLSOF.commandLineArguments(forProcess: pid, execName: nil)
    }
}

// A process as it was when observed. The start time distinguishes it from a later
// process that reuses its pid.
@objc(iTermSSHClientProcessIdentity)
final class SSHClientProcessIdentity: NSObject {
    @objc let pid: pid_t
    let startTime: Date

    init(pid: pid_t, startTime: Date) {
        self.pid = pid
        self.startTime = startTime
    }

    override var description: String {
        return "<SSHClientProcessIdentity pid=\(pid) start=\(startTime)>"
    }
}

@objc(iTermSSHClientProcessLocator)
final class SSHClientProcessLocator: NSObject {
    // nc's parent is the subshell for it2ssh's command substitution, whose parent is
    // it2ssh. One more level tolerates an extra fork.
    private static let maximumAncestors = 3
    private static let it2sshName = "it2ssh"
    private let inspector: SSHClientProcessInspecting

    @objc(sharedInstance) static let shared = SSHClientProcessLocator(inspector: SystemSSHClientProcessInspector())

    init(inspector: SSHClientProcessInspecting) {
        self.inspector = inspector
    }

    // The nearest ancestors of the process at the other end of the secret socket.
    // This must be called while that process is still connected, since its ancestry
    // is lost once it exits.
    func ancestors(ofPeer peer: pid_t) -> [SSHClientProcessIdentity] {
        var result = [SSHClientProcessIdentity]()
        guard peer > 0 else {
            return result
        }
        var pid = inspector.parentPID(of: peer)
        while pid > 1 && result.count < Self.maximumAncestors {
            guard let startTime = inspector.startTime(of: pid) else {
                break
            }
            result.append(SSHClientProcessIdentity(pid: pid, startTime: startTime))
            pid = inspector.parentPID(of: pid)
        }
        return result
    }

    // Returns the pid of the outermost still-running it2ssh among `ancestors`, or 0.
    // The command substitution subshell has it2ssh's arguments too, but it has exited
    // by the time the conductor hooks; preferring the outermost match is a backstop.
    @objc(liveIT2SSHProcessAmong:)
    func liveIT2SSHProcess(among ancestors: [SSHClientProcessIdentity]) -> pid_t {
        var found: pid_t = 0
        for identity in ancestors {
            guard inspector.startTime(of: identity.pid) == identity.startTime else {
                continue
            }
            guard let args = inspector.arguments(of: identity.pid) else {
                continue
            }
            if args.contains(where: { ($0 as NSString).lastPathComponent == Self.it2sshName }) {
                found = identity.pid
            }
        }
        return found
    }
}

// Watches it2ssh processes and remembers which connections were already announced
// as possibly dead. Main thread only.
@objc(iTermSSHClientMonitor)
final class SSHClientMonitor: NSObject {
    private var sources = [String: DispatchSourceProcess]()
    private var announced = Set<String>()

    deinit {
        for source in sources.values {
            source.cancel()
        }
    }

    // Calls onExit once, on the main queue, when the process exits. If it has already
    // exited, onExit is called soon. Returns false if the pid is invalid.
    @discardableResult
    @objc(watchProcessID:clientUniqueID:onExit:)
    func watch(processID pid: pid_t,
               clientUniqueID: String,
               onExit: @escaping () -> Void) -> Bool {
        guard pid > 0 else {
            return false
        }
        stopWatching(clientUniqueID: clientUniqueID)
        let source = DispatchSource.makeProcessSource(identifier: pid,
                                                      eventMask: .exit,
                                                      queue: .main)
        sources[clientUniqueID] = source
        let fire = { [weak self, weak source] in
            guard let self, let source, self.sources[clientUniqueID] === source else {
                return
            }
            RLog("it2ssh process \(pid) for \(clientUniqueID) exited")
            self.stopWatching(clientUniqueID: clientUniqueID)
            onExit()
        }
        source.setEventHandler(handler: fire)
        source.resume()
        // A process that exited before the source was created never fires it.
        if kill(pid, 0) != 0 && errno == ESRCH {
            DispatchQueue.main.async(execute: fire)
        }
        RLog("Watching it2ssh process \(pid) for \(clientUniqueID)")
        return true
    }

    @objc(stopWatchingClientUniqueID:)
    func stopWatching(clientUniqueID: String) {
        if let source = sources.removeValue(forKey: clientUniqueID) {
            source.cancel()
        }
    }

    @objc(isWatchingClientUniqueID:)
    func isWatching(clientUniqueID: String) -> Bool {
        return sources[clientUniqueID] != nil
    }

    // Whether to offer Disconnect because a prompt mark appeared outside this
    // connection's framing. A watched it2ssh is still alive (or about to be
    // recovered from automatically), and each connection is announced only once.
    @objc(shouldAnnounceUnframedPromptForClientUniqueID:)
    func shouldAnnounceUnframedPrompt(clientUniqueID: String) -> Bool {
        if isWatching(clientUniqueID: clientUniqueID) {
            return false
        }
        return announced.insert(clientUniqueID).inserted
    }
}
