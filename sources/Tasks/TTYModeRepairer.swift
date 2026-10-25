//
//  TTYModeRepairer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/24/26.
//

import Foundation

// A tty's modes at some moment, and which tty they belong to.
@objc(iTermTTYModes)
final class TTYModes: NSObject {
    @objc let path: String
    let modes: termios

    init(path: String, modes: termios) {
        self.path = path
        self.modes = modes
    }

    // The modes of the controlling tty of the process with this pid, or nil if it has none
    // or they can't be read.
    static func ofControllingTTY(ofProcessID pid: pid_t) -> TTYModes? {
        guard pid > 0 else {
            return nil
        }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return nil
        }
        let device = dev_t(bitPattern: info.e_tdev)
        guard device != dev_t(bitPattern: UInt32.max) else {
            return nil
        }
        // devname() isn't thread-safe and this runs on the secret server's queue.
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard devname_r(device, S_IFCHR, &buffer, Int32(buffer.count)) != nil else {
            return nil
        }
        return ofTTY(atPath: "/dev/" + String(cString: buffer))
    }

    // Opening the tty doesn't make it a controlling tty and reading its modes changes
    // nothing.
    @objc(modesOfTTYAtPath:)
    static func ofTTY(atPath path: String) -> TTYModes? {
        let fd = open(path, O_RDONLY | O_NOCTTY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            DLog("Can't open \(path): \(String(cString: strerror(errno)))")
            return nil
        }
        defer {
            close(fd)
        }
        var modes = termios()
        guard tcgetattr(fd, &modes) == 0 else {
            return nil
        }
        return TTYModes(path: path, modes: modes)
    }
}

// Puts back the tty modes that ssh changed when an SSH Integration connection's it2ssh died
// (F-460). ssh makes the tty raw while it runs and restores it when it exits, but a killed
// it2ssh can't, and its orphaned ssh client is no longer in the tty's foreground process
// group (and is killed anyway), so its tcsetattr fails. The tty is left without signals,
// output processing, or flow control: output staircases and Control-C prints ^C.
//
// Modes are set through iTerm2's end of the pty, never by sending anything to the shell.
//
// Some shells record the tty modes when a foreground job exits, even one killed by a
// signal, and reapply them before every command. zsh does: update_job() records them in
// shttyinfo when the foreground job ends (unless `ttyctl -f`), its line editor works from
// shttyinfo at the prompt, and it applies shttyinfo when the line editor returns, before
// running the command line. Such a shell recorded ssh's modes when it2ssh died, so fixing
// the tty at the prompt only lasts until the next command starts, and only a fix in effect
// when an external command exits is recorded.
//
// So the repairer stays armed after an abandonment, and whenever the tty is in that
// recorded state (ssh's, but with ICANON and ECHO set, which a raw program clears and
// which the shell sets outside its line editor) it fixes it again:
// - when a command starts (OSC 133 C), with shell integration;
// - when the shell that ran it2ssh forks, which it does to run an external command after
//   applying its recorded modes. This works without shell integration.
// The shell records the fixed modes when that command exits.
//
// It disarms at a command's end (OSC 133 D) only if that command started with good modes
// that the repairer hadn't set since the previous command ended: the line editor returned
// and the shell applied its recorded modes in between, so those are good now. The end of
// the killed it2ssh's command arrives right after the repair at the prompt and proves
// nothing (F-541). It also disarms when the watched shell exits, when a new connection
// starts on the tty, or when the session's shell is replaced (see PTYSession).
//
// Thread-safe. The mutation queue calls commandWillRun and commandDidFinish.
@objc(iTermTTYModeRepairer)
final class TTYModeRepairer: NSObject {
    // The input modes OpenSSH's enter_raw_mode clears.
    static let sshRawInputFlags = tcflag_t(ISTRIP | INLCR | IGNCR | ICRNL | IXON | IXANY | IXOFF)
    // The local modes it clears that a line editor (zsh's zle, readline) leaves alone, so
    // they may be fixed while the shell is reading a command.
    static let sshRawLocalFlagsOutsideLineEditor = tcflag_t(ISIG | IEXTEN)
    // The local modes it clears that a line editor manages itself.
    static let sshRawLocalFlagsManagedByLineEditor = tcflag_t(ICANON | ECHO | ECHOE | ECHOK | ECHONL)
    static let sshRawOutputFlags = tcflag_t(OPOST)

    // The flags whose absence identifies ssh's raw mode. A program that wants a raw tty
    // also clears ICANON and ECHO, which a shell like zsh always sets before a command, so
    // only a tty that has these clear but ICANON and ECHO set is fixed when a command
    // starts or the shell forks. ICRNL isn't among them because zsh's line editor turns it back on.
    private static let signatureInputFlags = tcflag_t(IXON)
    private static let signatureLocalFlags = tcflag_t(ISIG | IEXTEN)
    private static let signatureOutputFlags = tcflag_t(OPOST)

    private static let queue = DispatchQueue(label: "com.iterm2.tty-mode-repairer")

    private let mutex = Mutex()
    // Returns the pty's master fd, or -1 once the session's task has closed it.
    private var fileDescriptor: () -> Int32 = { -1 }
    // The pty's slave, which fileDescriptor must still be the master of. Job managers close
    // the fd before forgetting it, so its number may already belong to another pty.
    private var ttyPath = ""
    private var good = termios()
    private var armed = false
    // Reports forks and the exit of the shell that ran it2ssh while armed.
    private var shellWatcher: DispatchSourceProcess?
    // Whether the repairer changed the modes since the last command finished (or since it
    // armed). Until the shell applies its recorded modes again, good modes may be its own.
    private var changedModesSinceCommandFinished = false
    // Whether a fork made the repairer change the modes since the last command started.
    // Forks are reported as they happen, but commands are reported as the shell's output
    // is parsed, which may lag: a fork for the next command may come before the previous
    // command's end is parsed, so only a command's start clears this.
    private var forkChangedModesSinceCommandStarted = false
    // Whether the current command started with good modes the repairer didn't set.
    private var commandStartedWithShellsGoodModes = false

    // Called on the repairer's queue after the shell watcher stops.
    private var _didStopWatchingShellForTesting: (() -> Void)?
    var didStopWatchingShellForTesting: (() -> Void)? {
        get {
            return mutex.sync { _didStopWatchingShellForTesting }
        }
        set {
            mutex.sync { _didStopWatchingShellForTesting = newValue }
        }
    }

    // The modes iTerm2 gives a new session's tty, for when the modes from before ssh
    // started are unknown.
    @objc static var defaultModes: termios {
        var state = iTermTTYState()
        iTermTTYStateInit(&state, iTermTTYCellSizeMake(80, 25), iTermTTYPixelSizeMake(0, 0), 1)
        return state.term
    }

    @objc var isArmed: Bool {
        return mutex.sync { armed }
    }

    deinit {
        shellWatcher?.cancel()
    }

    // Whether the session's tty may be repaired at all after the outermost connection
    // with this it2ssh unique ID was abandoned. Not if:
    // - a connection is active (e.g., one hooked during Disconnect's wait), since its ssh
    //   may be using the modes;
    // - another connection started on the tty since, so its modes are the new one's;
    // - it2ssh ran on another tty (e.g., inside tmux);
    // - it2ssh ran without job control (shellProcessGroup is 0), since whatever runs next
    //   shares the shell's process group and may be using the modes.
    @objc(mayRepairAfterAbandoningClientUniqueID:lastClientUniqueID:connectionActive:ranOnAnotherTTY:shellProcessGroup:)
    static func mayRepair(afterAbandoning clientUniqueID: String,
                          lastClientUniqueID: String?,
                          connectionActive: Bool,
                          ranOnAnotherTTY: Bool,
                          shellProcessGroup: pid_t) -> Bool {
        return !clientUniqueID.isEmpty &&
            clientUniqueID == lastClientUniqueID &&
            !connectionActive &&
            !ranOnAnotherTTY &&
            shellProcessGroup > 0
    }

    // Call only when the it2ssh that ran ssh on this tty is known to have exited.
    // `goodModes` is the tty's modes from before ssh started, or nil if unknown. ttyPath is
    // the pty's slave. Arms the repairer if the tty is in ssh's raw mode and, if
    // `repairNow`, fixes what can be fixed without disturbing a line editor. Pass false
    // when something other than the shell may be using the tty right now.
    // `shellProcessID` is the shell that ran it2ssh, still running, or 0 if unknown. While
    // armed, the repairer watches it for forks.
    @objc(repairAfterAbandonedSSHWithFileDescriptor:ttyPath:goodModes:repairNow:shellProcessID:)
    func repairAfterAbandonedSSH(fileDescriptor: @escaping () -> Int32,
                                 ttyPath: String,
                                 goodModes: TTYModes?,
                                 repairNow: Bool,
                                 shellProcessID: pid_t) {
        mutex.sync {
            disarmLocked()
            let fd = fileDescriptor()
            let good = goodModes?.modes ?? Self.defaultModes
            guard Self.isMaster(fd, of: ttyPath),
                  let original = Self.modes(fd),
                  Self.isSSHRaw(original, good: good) else {
                DLog("tty is not in ssh's raw mode")
                return
            }
            self.fileDescriptor = fileDescriptor
            self.ttyPath = ttyPath
            self.good = good
            armed = true
            changedModesSinceCommandFinished = false
            forkChangedModesSinceCommandStarted = false
            commandStartedWithShellsGoodModes = false
            if shellProcessID > 0 {
                watchShellLocked(shellProcessID)
            }
            guard repairNow else {
                RLog("Waiting for a command to start before restoring tty modes")
                return
            }
            var current = original
            Self.copy(Self.sshRawInputFlags, from: good.c_iflag, to: &current.c_iflag)
            Self.copy(Self.sshRawLocalFlagsOutsideLineEditor, from: good.c_lflag, to: &current.c_lflag)
            Self.copy(Self.sshRawOutputFlags, from: good.c_oflag, to: &current.c_oflag)
            RLog("Restoring tty modes ssh changed (from \(goodModes == nil ? "defaults" : "snapshot"))")
            if Self.set(fd, current, ifStill: original) {
                changedModesSinceCommandFinished = true
            }
        }
    }

    // A command is about to run (OSC 133 C).
    @objc func commandWillRun() {
        mutex.sync {
            guard armed else {
                return
            }
            switch repairReappliedModesLocked(reason: "a command started") {
            case .repaired:
                changedModesSinceCommandFinished = true
                commandStartedWithShellsGoodModes = false
            case .unknown:
                commandStartedWithShellsGoodModes = false
            case .good:
                commandStartedWithShellsGoodModes = (!changedModesSinceCommandFinished &&
                                                     !forkChangedModesSinceCommandStarted)
            }
            forkChangedModesSinceCommandStarted = false
        }
    }

    // A command finished (OSC 133 D). The shell has recorded the tty's modes by now.
    @objc func commandDidFinish() {
        mutex.sync {
            guard armed else {
                return
            }
            let startedWithShellsGoodModes = commandStartedWithShellsGoodModes
            commandStartedWithShellsGoodModes = false
            changedModesSinceCommandFinished = false
            let fd = fileDescriptor()
            guard Self.isMaster(fd, of: ttyPath), let current = Self.modes(fd) else {
                RLog("The session's pty is gone; stop repairing it")
                disarmLocked()
                return
            }
            if startedWithShellsGoodModes && !Self.isSSHRaw(current, good: good) {
                RLog("The shell's tty modes are no longer ssh's; stop repairing them")
                disarmLocked()
            }
        }
    }

    // The watched shell forked. zsh forks to run an external command after it applies
    // the modes it recorded, so they are fixed while the command runs and it records the
    // fixed modes when the command exits. A fork tells nothing about the recorded modes,
    // so it never disarms.
    //
    // The child is about to run a program that may make the tty raw itself, so the fork
    // is when the window between reading and setting the modes (see set(_:_:ifStill:))
    // matters most. The program clears ICANON and ECHO, so the modes are left alone if it
    // does so before they are read or before they are read again just before setting.
    func shellDidFork() {
        mutex.sync {
            shellDidForkLocked()
        }
    }

    private func shellDidForkLocked() {
        guard armed else {
            return
        }
        if repairReappliedModesLocked(reason: "the shell forked") == .repaired {
            changedModesSinceCommandFinished = true
            forkChangedModesSinceCommandStarted = true
        }
    }

    @objc func disarm() {
        mutex.sync {
            disarmLocked()
        }
    }

    // MARK: - Private

    private enum Outcome {
        // The tty had the shell's reapplied raw modes and they were fixed.
        case repaired
        // The tty is not in ssh's raw mode and has ICANON and ECHO, as the shell sets them
        // outside its line editor.
        case good
        // Anything else, such as a raw program, the line editor, or a pty that is gone.
        case unknown
    }

    // Fixes the modes if they are what a shell that recorded ssh's modes reapplies: ssh's,
    // but with ICANON and ECHO set. A program that wants a raw tty clears those.
    @discardableResult
    private func repairReappliedModesLocked(reason: String) -> Outcome {
        let fd = fileDescriptor()
        guard Self.isMaster(fd, of: ttyPath), let original = Self.modes(fd) else {
            return .unknown
        }
        guard original.c_lflag & tcflag_t(ICANON | ECHO) == tcflag_t(ICANON | ECHO) else {
            return .unknown
        }
        guard Self.isSSHRaw(original, good: good) else {
            return .good
        }
        var current = original
        Self.copy(Self.sshRawInputFlags, from: good.c_iflag, to: &current.c_iflag)
        Self.copy(Self.sshRawLocalFlagsOutsideLineEditor | Self.sshRawLocalFlagsManagedByLineEditor,
                  from: good.c_lflag,
                  to: &current.c_lflag)
        Self.copy(Self.sshRawOutputFlags, from: good.c_oflag, to: &current.c_oflag)
        Self.copyControlCharacter(VMIN, from: good, to: &current)
        Self.copyControlCharacter(VTIME, from: good, to: &current)
        RLog("Restoring tty modes the shell reapplied from ssh's raw mode because \(reason)")
        guard Self.set(fd, current, ifStill: original) else {
            return .unknown
        }
        return .repaired
    }

    private func disarmLocked() {
        armed = false
        changedModesSinceCommandFinished = false
        forkChangedModesSinceCommandStarted = false
        commandStartedWithShellsGoodModes = false
        if let shellWatcher {
            shellWatcher.cancel()
            self.shellWatcher = nil
        }
    }

    private func watchShellLocked(_ pid: pid_t) {
        let source = DispatchSource.makeProcessSource(identifier: pid,
                                                      eventMask: [.fork, .exit],
                                                      queue: Self.queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else {
                return
            }
            self.shellWatcher(source, didReport: source.data)
        }
        source.setCancelHandler { [weak self] in
            self?.didStopWatchingShellForTesting?()
        }
        shellWatcher = source
        source.resume()
        DLog("Watching shell \(pid) for forks")
    }

    private func shellWatcher(_ source: DispatchSourceProcess,
                              didReport events: DispatchSource.ProcessEvent) {
        mutex.sync {
            guard armed, shellWatcher === source else {
                return
            }
            if events.contains(.exit) {
                RLog("The shell that ran it2ssh exited; stop repairing tty modes")
                disarmLocked()
                return
            }
            if events.contains(.fork) {
                shellDidForkLocked()
            }
        }
    }

    private static func bytes(_ modes: termios) -> [UInt8] {
        var modes = modes
        return withUnsafeBytes(of: &modes) { Array($0) }
    }

    // Whether fd is the master of the pty whose slave is at path.
    static func isMaster(_ fd: Int32, of path: String) -> Bool {
        guard fd > 0, !path.isEmpty else {
            return false
        }
        var buffer = [CChar](repeating: 0, count: 128)
        guard ptsname_r(fd, &buffer, buffer.count) == 0 else {
            return false
        }
        return String(cString: buffer) == path
    }

    private static func modes(_ fd: Int32) -> termios? {
        guard fd > 0 else {
            return nil
        }
        var modes = termios()
        guard tcgetattr(fd, &modes) == 0 else {
            return nil
        }
        return modes
    }

    // Skips the change if the modes changed since they were read (e.g., a command that
    // just started made the tty raw itself). That narrows, but can't close, the window
    // between reading and writing. Returns whether the modes were set.
    private static func set(_ fd: Int32, _ modes: termios, ifStill original: termios) -> Bool {
        guard let now = Self.modes(fd), bytes(now) == bytes(original) else {
            RLog("tty modes changed while repairing them; leaving them alone")
            return false
        }
        var modes = modes
        if tcsetattr(fd, TCSANOW, &modes) != 0 {
            RLog("tcsetattr failed: \(String(cString: strerror(errno)))")
            return false
        }
        return true
    }

    // Whether every signature flag that is set in the good modes is clear now.
    private static func isSSHRaw(_ current: termios, good: termios) -> Bool {
        let input = good.c_iflag & signatureInputFlags
        let local = good.c_lflag & signatureLocalFlags
        let output = good.c_oflag & signatureOutputFlags
        if input == 0 && local == 0 && output == 0 {
            return false
        }
        return current.c_iflag & input == 0 && current.c_lflag & local == 0 && current.c_oflag & output == 0
    }

    private static func copyControlCharacter(_ index: Int32, from source: termios, to destination: inout termios) {
        var source = source
        let value = withUnsafeBytes(of: &source.c_cc) { $0[Int(index)] }
        withUnsafeMutableBytes(of: &destination.c_cc) { $0[Int(index)] = value }
    }

    private static func copy(_ mask: tcflag_t, from source: tcflag_t, to destination: inout tcflag_t) {
        destination = (destination & ~mask) | (source & mask)
    }
}
