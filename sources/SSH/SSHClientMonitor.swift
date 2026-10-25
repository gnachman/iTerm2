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
    // Returns [] if unknown.
    func childPIDs(of pid: pid_t) -> [pid_t]
    // Whether the process listens on a unix-domain socket, as an ssh ControlMaster
    // does. Returns nil if unknown.
    func hasListeningUnixSocket(_ pid: pid_t) -> Bool?
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

    func hasListeningUnixSocket(_ pid: pid_t) -> Bool? {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else {
            return nil
        }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride)
        let bytes = fds.withUnsafeMutableBytes { pointer in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, pointer.baseAddress, Int32(pointer.count))
        }
        // A full buffer may have dropped descriptors opened since it was sized.
        guard bytes > 0, Int(bytes) < fds.count * stride else {
            return nil
        }
        for fd in fds.prefix(Int(bytes) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let infoSize = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, infoSize) == infoSize else {
                return nil
            }
            if info.psi.soi_family == AF_UNIX && (Int32(info.psi.soi_options) & SO_ACCEPTCONN) != 0 {
                return true
            }
        }
        return false
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

// An it2ssh and the ssh client it ran, as they were while it2ssh was alive (F-351).
private struct SSHClientRecord {
    var it2ssh: SSHClientProcessIdentity
    var ssh: SSHClientProcessIdentity
    var sshArguments: [String]
}

// Watches it2ssh processes and remembers which connections were already announced
// as possibly dead. Main thread only.
@objc(iTermSSHClientMonitor)
final class SSHClientMonitor: NSObject {
    private static let sshName = "ssh"
    private var sources = [String: DispatchSourceProcess]()
    private var announced = Set<String>()
    private var clients = [String: SSHClientRecord]()
    private let inspector: SSHClientProcessInspecting
    private let signaler: (pid_t, Int32) -> Void

    init(inspector: SSHClientProcessInspecting,
         signaler: @escaping (pid_t, Int32) -> Void) {
        self.inspector = inspector
        self.signaler = signaler
    }

    override convenience init() {
        self.init(inspector: SystemSSHClientProcessInspector()) { pid, signal in
            kill(pid, signal)
        }
    }

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
        recordSSHClient(ofIT2SSHProcessID: pid, clientUniqueID: clientUniqueID)
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

    // Remembers it2ssh's ssh child so it can be hung up if it2ssh dies and leaves it
    // running (F-351). it2ssh runs ssh as a child (not with exec) for the whole
    // connection, so it must be alive now. Records nothing unless exactly one child
    // is ssh.
    func recordSSHClient(ofIT2SSHProcessID pid: pid_t, clientUniqueID: String) {
        clients.removeValue(forKey: clientUniqueID)
        guard let it2sshStart = inspector.startTime(of: pid) else {
            DLog("it2ssh \(pid) is gone; not recording its ssh client")
            return
        }
        let candidates = inspector.childPIDs(of: pid).compactMap { child -> (SSHClientProcessIdentity, [String])? in
            guard let args = inspector.arguments(of: child),
                  let name = args.first,
                  (name as NSString).lastPathComponent == Self.sshName,
                  let start = inspector.startTime(of: child) else {
                return nil
            }
            return (SSHClientProcessIdentity(pid: child, startTime: start), args)
        }
        guard candidates.count == 1, let (ssh, args) = candidates.first else {
            RLog("Not recording an ssh client for it2ssh \(pid): \(candidates.count) candidates")
            return
        }
        RLog("it2ssh \(pid) for \(clientUniqueID) runs ssh \(ssh)")
        clients[clientUniqueID] = SSHClientRecord(it2ssh: SSHClientProcessIdentity(pid: pid, startTime: it2sshStart),
                                                  ssh: ssh,
                                                  sshArguments: args)
    }

    // The connection ended normally, so its ssh client exits on its own.
    @objc(forgetSSHClientForClientUniqueID:)
    func forgetSSHClient(clientUniqueID: String) {
        clients.removeValue(forKey: clientUniqueID)
    }

    // Sends SIGHUP to the ssh client recorded for this connection if its it2ssh has
    // exited and the very same ssh process is still running. Once the connection has
    // been abandoned nothing else needs the record, so it is forgotten even when
    // nothing is signaled (e.g., Disconnect from a hung remote with it2ssh alive). Without this it would
    // stay logged in to the remote host on the session's tty. Never signals a
    // process that can't be positively identified: the pid, start time, and
    // arguments must all match. Forgets the connection. Returns whether it signaled.
    @discardableResult
    @objc(hangUpOrphanedSSHClientForClientUniqueID:)
    func hangUpOrphanedSSHClient(clientUniqueID: String) -> Bool {
        guard let record = clients.removeValue(forKey: clientUniqueID) else {
            DLog("No ssh client recorded for \(clientUniqueID)")
            return false
        }
        let ssh = record.ssh
        guard inspector.startTime(of: ssh.pid) == ssh.startTime,
              inspector.arguments(of: ssh.pid) == record.sshArguments else {
            DLog("ssh client \(ssh) for \(clientUniqueID) is gone")
            return false
        }
        // A live it2ssh is still ssh's parent (children are reparented when it exits),
        // so a failure to read its start time can't make it look dead.
        if inspector.startTime(of: record.it2ssh.pid) == record.it2ssh.startTime ||
            inspector.parentPID(of: ssh.pid) == record.it2ssh.pid {
            RLog("it2ssh \(record.it2ssh) for \(clientUniqueID) is alive; leaving its ssh client alone")
            return false
        }
        // A ControlMaster may carry other sessions' connections.
        guard inspector.hasListeningUnixSocket(ssh.pid) == false else {
            RLog("ssh client \(ssh) for \(clientUniqueID) may be a ControlMaster; leaving it alone")
            return false
        }
        RLog("Hanging up orphaned ssh client \(ssh) for \(clientUniqueID)")
        signaler(ssh.pid, SIGHUP)
        return true
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
