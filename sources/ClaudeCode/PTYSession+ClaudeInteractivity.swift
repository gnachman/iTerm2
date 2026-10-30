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
    // reader remembers what it learned about the pane.
    func makeClaudeTTYModeReader() -> ClaudeTTYModeReading {
        if shell.framerPaneJobManager != nil {
            // A workgroup peer running inside its leader's framer. Its terminal modes aren't
            // reported anywhere this can read.
            return ClaudeUnknownTTYModeReader()
        }
        if isTmuxClient {
            guard let gateway = tmuxController?.gateway,
                  gateway.versionAtLeastDecimalNumber(with: ClaudeTmuxPaneTTYModeReader.minimumTmuxVersion) else {
                DLog("\(self): tmux server is too old or unknown; can't read the pane's tty")
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
// the server's host with if-shell, which works whether the server is local or remote.
// Not run-shell: in control mode tmux ends run-shell's reply right away and prints the output
// afterward, outside any reply, which the gateway takes for a broken connection and detaches.
// if-shell's branch replies in a block of its own, and a display-message there says which way the
// shell test went.
final class ClaudeTmuxPaneTTYModeReader: ClaudeTTYModeReading {
    // Before 3.2, tmux flags the reply to if-shell's branch as server-originated, so the gateway
    // doesn't take it as the reply it's waiting for and hands it the next command's reply instead.
    // (Before 2.1 the branch's output never arrives at all and the client exits.)
    static let minimumTmuxVersion = "3.2"

    static let yes = "YES"
    static let no = "NO"

    private weak var gateway: TmuxGateway?
    private let pane: Int32
    private var paneTTY: String?
    // Whether the server's host can run the reading's commands; nil until checked.
    private var hostCanRead: Bool?

    init(gateway: TmuxGateway, pane: Int32) {
        self.gateway = gateway
        self.pane = pane
    }

    func read(_ completion: @escaping (ClaudeTTYReading) -> Void) {
        guard let gateway else {
            completion(.unknown)
            return
        }
        guard let paneTTY else {
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
                read(completion)
            }
            return
        }
        guard let hostCanRead else {
            gateway.sendGuardedForBranchReply(Self.capabilityCommand(tty: paneTTY), reply: { [weak self] reply in
                guard let self else {
                    return
                }
                hostCanRead = Self.isYes(reply)
                DLog("tmux host can read %\(pane)'s tty: \(hostCanRead ?? false)")
                read(completion)
            })
            return
        }
        guard hostCanRead else {
            completion(.unknown)
            return
        }
        gateway.sendGuardedForBranchReply(Self.readingCommand(tty: paneTTY), reply: { reply in
            completion(Self.reading(fromBranchReply: reply))
        })
    }

    // The path goes into a shell command, so accept only what a tty path looks like.
    static func isSafeTTYPath(_ path: String) -> Bool {
        return path.range(of: "^/dev/[A-Za-z0-9._/-]+$", options: .regularExpression) != nil
    }

    // Whether stty and `ps -o ... -t` work on the server's host. Where they don't, a reading would
    // always say NO, so fall back to the dwell time instead.
    static func capabilityCommand(tty: String) -> String {
        return ifShell("stty -a < \(tty) > /dev/null 2>&1 && " +
                       "ps -o tpgid= -o pgid= -o args= -t \(tty) > /dev/null 2>&1")
    }

    // YES when the tty is in raw mode and a process whose argv[0] is claude is in the tty's
    // foreground process group. That asks about claude, not a shell, so a prompt drawn by a shell
    // nested anywhere never counts, and a claude that shares a wrapper script's process group still
    // does. A tpgid of 0 (macOS) or -1 (procps) means no controlling terminal, which isn't YES.
    // stty works on its stdin, which spells the same on macOS and Linux, and `ps -o` with these
    // fields and `-t` with a /dev path work on macOS and with procps on Linux. args rather than
    // comm: comm is the executable's file name, which for claude depends on how it was installed.
    static func readingCommand(tty: String) -> String {
        // In double quotes for the shell, because tmux takes the whole test in single quotes.
        let claudeInForeground = "\\$1 > 0 && \\$1 == \\$2 { n = split(\\$3, p, \\\"/\\\"); if (p[n] == \\\"claude\\\") f = 1 } END { exit !f }"
        return ifShell("stty -a < \(tty) | grep -q -- -icanon && " +
                       "ps -o tpgid= -o pgid= -o args= -t \(tty) | awk \"\(claudeInForeground)\"")
    }

    // YES: raw with claude in the foreground. NO covers canonical, claude without the foreground,
    // and anything that failed, so it can't lead to an offer; it reads as canonical, which keeps
    // checking until the policy gives up.
    static func reading(fromBranchReply reply: String?) -> ClaudeTTYReading {
        guard let reply else {
            return .unknown
        }
        if isYes(reply) {
            return ClaudeTTYReading(mode: .raw, claudeHasForeground: true)
        }
        return ClaudeTTYReading(mode: .canonical, claudeHasForeground: nil)
    }

    private static func isYes(_ reply: String?) -> Bool {
        return reply?.trimmingCharacters(in: .whitespacesAndNewlines) == yes
    }

    // Neither branch may contain a single quote, and the test must not contain one or a #, which
    // tmux would take as the start of a format.
    private static func ifShell(_ test: String) -> String {
        return "if-shell '\(test)' 'display-message -p \(yes)' 'display-message -p \(no)'"
    }
}
