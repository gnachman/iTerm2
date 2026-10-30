//
//  PTYSession+ClaudeInteractivity.swift
//  iTerm2SharedARC
//
//  Gathers what ClaudeInteractivityPolicy needs to know about the claude running in a session:
//  its command line, and the terminal mode of the tty it runs on along with whether claude or the
//  shell has that tty's foreground. Where those live depends on what owns the tty: this Mac,
//  framer on a host reached through SSH Integration, or a tmux server.
//

import Foundation

// Reads the tty claude runs on.
protocol ClaudeTTYModeReading: AnyObject {
    // Calls completion on the main queue.
    func read(_ completion: @escaping (ClaudeTTYReading) -> Void)
}

extension PTYSession {
    // The run of claude in this session's foreground job, as its command line describes it.
    // undetermined when the command line can't be read exactly, which is the case for any claude
    // that isn't on this Mac.
    func claudeInvocation() -> ClaudeInvocation {
        guard let claude = claudeProcessInfo() else {
            DLog("\(self): no claude process found to classify")
            return .undetermined
        }
        return ClaudeInvocation.classify(processID: claude.processID, dataSource: claude.dataSource)
    }

    // A reader for the tty claude runs on in this session. Make one per run of claude: the tmux
    // reader remembers the pane's tty.
    func makeClaudeTTYModeReader() -> ClaudeTTYModeReading {
        if shell.framerPaneJobManager != nil {
            // A workgroup peer running inside its leader's framer. Its terminal modes aren't
            // reported anywhere this can read.
            return ClaudeUnknownTTYModeReader()
        }
        if isTmuxClient {
            guard let gateway = tmuxController?.gateway,
                  gateway.versionAtLeastDecimalNumber(with: ClaudeTmuxPaneTTYModeReader.minimumTmuxVersion) else {
                DLog("\(self): tmux server is too old or unknown; can't read the pane's tty mode")
                return ClaudeUnknownTTYModeReader()
            }
            return ClaudeTmuxPaneTTYModeReader(gateway: gateway, pane: tmuxPane)
        }
        if let conductor {
            // The local tty belongs to ssh, which keeps it raw whatever runs on the remote host.
            return ClaudeConductorTTYModeReader(conductor: conductor, session: self)
        }
        return ClaudeLocalTTYModeReader(session: self)
    }

    // The claude the user ran, which the foreground job is or descends from.
    fileprivate func claudeProcessInfo() -> iTermProcessInfo? {
        guard let jobPid = (genericScope.value(forVariableName: iTermVariableKeySessionJobPid) as? NSNumber)?.int32Value,
              jobPid > 0 else {
            return nil
        }
        return ClaudeProcessLocator.outermostClaude(startingAt: processInfoProvider?.processInfo(for: jobPid))
    }
}

private final class ClaudeUnknownTTYModeReader: ClaudeTTYModeReading {
    func read(_ completion: @escaping (ClaudeTTYReading) -> Void) {
        completion(.unknown)
    }
}

// A session on this Mac: claude runs on the session's own pty.
private final class ClaudeLocalTTYModeReader: ClaudeTTYModeReading {
    private weak var session: PTYSession?

    init(session: PTYSession) {
        self.session = session
    }

    func read(_ completion: @escaping (ClaudeTTYReading) -> Void) {
        guard let session else {
            completion(.unknown)
            return
        }
        var attributes = termios()
        var status = Int32(-1)
        var error = Int32(0)
        // The descriptor stays open until the block returns.
        let wasOpen = session.shell.withFileDescriptor { fd in
            status = tcgetattr(fd, &attributes)
            error = errno
        }
        guard wasOpen, status == 0 else {
            DLog("tcgetattr failed: \(wasOpen ? String(cString: strerror(error)) : "closed")")
            completion(.unknown)
            return
        }
        let mode = ClaudeTTYMode(icanon: (attributes.c_lflag & tcflag_t(ICANON)) != 0)
        completion(ClaudeTTYReading(mode: mode, claudeHasForeground: claudeHasForeground(session)))
    }

    // Asks about claude itself, right after reading the mode. The local data source reads the
    // process table directly, so unlike the job ancestry this is never stale. A wrapper script that
    // launches claude doesn't matter: claude inherits the wrapper's process group.
    private func claudeHasForeground(_ session: PTYSession) -> Bool? {
        guard let claude = session.claudeProcessInfo() else {
            return nil
        }
        var isForeground = ObjCBool(false)
        guard claude.dataSource.nameOfProcess(withPid: claude.processID,
                                              isForeground: &isForeground) != nil else {
            // claude has exited and the job ancestry hasn't caught up. The mode is a prompt's.
            DLog("claude pid \(claude.processID) is gone")
            return false
        }
        return isForeground.boolValue
    }
}

// A host reached through SSH Integration: framer owns claude's pty there and reports changes to
// its ICANON flag and to its foreground process group, which the conductor keeps. Both come from
// the same framer sample, so however stale the report is, a prompt's raw mode arrives with the
// prompt's shell's group, which isn't claude's.
private final class ClaudeConductorTTYModeReader: ClaudeTTYModeReading {
    private weak var conductor: Conductor?
    private weak var session: PTYSession?

    init(conductor: Conductor, session: PTYSession) {
        self.conductor = conductor
        self.session = session
    }

    func read(_ completion: @escaping (ClaudeTTYReading) -> Void) {
        let claudeGroup = session?.claudeProcessInfo().flatMap { claude in
            claude.dataSource.processGroupID?(forProcess: claude.processID)
        }
        let reading = MainActor.assumeIsolated { () -> ClaudeTTYReading in
            guard let conductor, conductor.framing else {
                // Still connecting, or not framing at all.
                return .unknown
            }
            return ClaudeTTYReading(
                mode: ClaudeTTYMode(icanon: conductor.ttyState.icanon),
                claudeHasForeground: ClaudeTTYReading.claudeHasForeground(
                    foregroundGroup: conductor.ttyState.foregroundProcessGroup,
                    claudeGroup: claudeGroup))
        }
        completion(reading)
    }
}

// A tmux pane: the tmux server owns the pane's pty and doesn't report its terminal modes, so ask
// the server's host with run-shell. That works whether the server is local or remote.
final class ClaudeTmuxPaneTTYModeReader: ClaudeTTYModeReading {
    // Before 2.4, run-shell without -t shows its output in the client's active pane instead of
    // returning it as the command's reply.
    static let minimumTmuxVersion = "2.4"

    private weak var gateway: TmuxGateway?
    private let pane: Int32
    private var paneTTY: String?

    init(gateway: TmuxGateway, pane: Int32) {
        self.gateway = gateway
        self.pane = pane
    }

    func read(_ completion: @escaping (ClaudeTTYReading) -> Void) {
        if let paneTTY {
            read(paneTTY, completion)
            return
        }
        guard let gateway else {
            completion(.unknown)
            return
        }
        gateway.send("display-message -p -t '%\(pane)' '#{pane_tty}'") { [weak self] reply in
            guard let self else {
                return
            }
            guard let path = reply?.trimmingCharacters(in: .whitespacesAndNewlines),
                  Self.isSafeTTYPath(path) else {
                DLog("Unusable pane_tty for %\(pane): \(reply ?? "(nil)")")
                completion(.unknown)
                return
            }
            paneTTY = path
            read(path, completion)
        }
    }

    // The path goes into a shell command, so accept only what a tty path looks like.
    static func isSafeTTYPath(_ path: String) -> Bool {
        return path.range(of: "^/dev/[A-Za-z0-9._/-]+$", options: .regularExpression) != nil
    }

    // The run-shell command for one reading: the tty's modes, then each process on the tty with
    // the tty's foreground process group (tpgid), its own process group, and its command line.
    // stty works on its stdin, which spells the same on macOS and Linux, and `ps -o` with these
    // fields and `-t` with a /dev path work on macOS and with procps on Linux. args rather than
    // comm: comm is the executable's file name, which for claude depends on how it was installed,
    // while args starts with the argv[0] the job ancestry matches on.
    static func readingCommand(tty: String) -> String {
        return "stty -a < \(tty); ps -o tpgid= -o pgid= -o args= -t \(tty)"
    }

    // A ps row: tpgid, pgid, then a command line. stty -a never prints a line shaped like this.
    private static let psRowPattern = "^\\s*-?[0-9]+\\s+[0-9]+\\s+\\S"

    // Parses the output of readingCommand. Each part is parsed from its own lines: a ps row's
    // command line can contain anything, including the "-icanon" the mode is read from.
    static func reading(fromOutput output: String) -> ClaudeTTYReading {
        let lines = output.split(separator: "\n")
        let isPSRow = { (line: Substring) in line.range(of: psRowPattern, options: .regularExpression) != nil }
        let sttyOutput = lines.filter { !isPSRow($0) }.joined(separator: "\n")
        return ClaudeTTYReading(mode: ClaudeTTYMode(sttyOutput: sttyOutput),
                                claudeHasForeground: claudeHasForeground(psRows: lines.filter(isPSRow)))
    }

    // Whether a process whose argv[0] is claude is in the tty's foreground process group. That
    // asks about claude, not a shell, so a prompt drawn by a shell nested anywhere never counts,
    // and a claude that shares a wrapper script's process group still does. nil without a usable
    // ps row, e.g. from a ps that doesn't take these options.
    private static func claudeHasForeground(psRows: [Substring]) -> Bool? {
        let processes = psRows.compactMap { line -> (tpgid: Int, pgid: Int, argv0: String)? in
            let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard fields.count >= 3, let tpgid = Int(fields[0]), let pgid = Int(fields[1]) else {
                return nil
            }
            return (tpgid, pgid, fields[2])
        }
        // A tpgid of 0 (macOS) or -1 (procps) means no controlling terminal: no answer. Each row
        // carries the tty's tpgid, so compare within the row rather than trusting any one line.
        let onTerminal = processes.filter { $0.tpgid > 0 }
        guard !onTerminal.isEmpty else {
            return nil
        }
        return onTerminal.contains { process in
            process.pgid == process.tpgid && (process.argv0 as NSString).lastPathComponent.lowercased() == "claude"
        }
    }

    private func read(_ tty: String, _ completion: @escaping (ClaudeTTYReading) -> Void) {
        guard let gateway else {
            completion(.unknown)
            return
        }
        // run-shell gets no -t: with it, tmux shows the output in that pane instead of replying.
        gateway.send("run-shell '\(Self.readingCommand(tty: tty))'") { reply in
            guard let reply else {
                DLog("Reading \(tty) failed")
                completion(.unknown)
                return
            }
            completion(Self.reading(fromOutput: reply))
        }
    }
}
