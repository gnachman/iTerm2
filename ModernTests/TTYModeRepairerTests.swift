//
//  TTYModeRepairerTests.swift
//  iTerm2
//
//  F-460: when it2ssh is killed, its ssh client can't restore the tty modes it changed, so
//  the session is left without signals, output processing, or flow control. iTerm2 puts
//  them back through its end of the pty. These tests use real ptys.
//

import XCTest
@testable import iTerm2SharedARC

private final class PTYPair {
    let master: Int32
    let slave: Int32
    let path: String

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var name = [CChar](repeating: 0, count: 128)
        var modes = TTYModeRepairer.defaultModes
        guard openpty(&master, &slave, &name, &modes, nil) == 0 else {
            throw NSError(domain: "PTYPair", code: Int(errno))
        }
        self.master = master
        self.slave = slave
        self.path = String(cString: name)
    }

    deinit {
        close(master)
        close(slave)
    }

    var slaveModes: termios {
        var modes = termios()
        XCTAssertEqual(tcgetattr(slave, &modes), 0)
        return modes
    }

    func setSlaveModes(_ modes: termios) {
        var modes = modes
        XCTAssertEqual(tcsetattr(slave, TCSANOW, &modes), 0)
    }

    // What OpenSSH's enter_raw_mode does.
    func enterSSHRawMode() {
        var modes = slaveModes
        modes.c_iflag |= tcflag_t(IGNPAR)
        modes.c_iflag &= ~tcflag_t(ISTRIP | INLCR | IGNCR | ICRNL | IXON | IXANY | IXOFF)
        modes.c_lflag &= ~tcflag_t(ISIG | ICANON | ECHO | ECHOE | ECHOK | ECHONL | IEXTEN)
        modes.c_oflag &= ~tcflag_t(OPOST)
        setControlCharacter(&modes, VMIN, 1)
        setControlCharacter(&modes, VTIME, 0)
        setSlaveModes(modes)
    }

    // What zsh does before a command: reapply the modes it recorded, with ICANON and ECHO
    // forced on.
    func reapplyRecordedModesLikeZsh() {
        var modes = slaveModes
        modes.c_lflag |= tcflag_t(ICANON | ECHO)
        setSlaveModes(modes)
    }
}

private func setControlCharacter(_ modes: inout termios, _ index: Int32, _ value: cc_t) {
    withUnsafeMutableBytes(of: &modes.c_cc) { $0[Int(index)] = value }
}

private func slavePath(_ master: Int32) -> String {
    var buffer = [CChar](repeating: 0, count: 128)
    XCTAssertEqual(ptsname_r(master, &buffer, buffer.count), 0)
    return String(cString: buffer)
}

private func has(_ flags: tcflag_t, _ flag: Int32) -> Bool {
    return flags & tcflag_t(flag) != 0
}

final class TTYModeRepairerTests: XCTestCase {
    // The modes before ssh started, as a user who turned off flow control has them.
    private var goodModes: termios {
        var modes = TTYModeRepairer.defaultModes
        modes.c_iflag &= ~tcflag_t(IXON)
        return modes
    }

    func testMayRepairOnlyTheLastConnectionWhileNothingElseOwnsTheTTY() {
        func may(_ id: String = "a", last: String? = "a", active: Bool = false,
                 elsewhere: Bool = false, group: pid_t = 10) -> Bool {
            return TTYModeRepairer.mayRepair(afterAbandoning: id,
                                             lastClientUniqueID: last,
                                             connectionActive: active,
                                             ranOnAnotherTTY: elsewhere,
                                             shellProcessGroup: group)
        }
        XCTAssertTrue(may())
        // Disconnect's wait: a new it2ssh started on the tty in the meantime.
        XCTAssertFalse(may(last: "b"))
        XCTAssertFalse(may(active: true))
        XCTAssertFalse(may(last: nil))
        XCTAssertFalse(may(elsewhere: true))
        // No job control.
        XCTAssertFalse(may(group: 0))
        XCTAssertFalse(may("", last: ""))
    }

    func testReadsModesOfTTYAtPath() throws {
        let pty = try PTYPair()
        pty.setSlaveModes(goodModes)
        let snapshot = try XCTUnwrap(TTYModes.ofTTY(atPath: pty.path))
        XCTAssertEqual(snapshot.path, pty.path)
        XCTAssertEqual(snapshot.modes.c_iflag, goodModes.c_iflag)
        XCTAssertEqual(snapshot.modes.c_lflag, goodModes.c_lflag)
        XCTAssertEqual(snapshot.modes.c_oflag, goodModes.c_oflag)
    }

    // At the shell's prompt, the modes a line editor leaves alone are restored from the
    // snapshot. ICANON and ECHO belong to the line editor, so they stay as they are.
    func testRepairRestoresModesOutsideLineEditor() throws {
        let pty = try PTYPair()
        pty.setSlaveModes(goodModes)
        let snapshot = try XCTUnwrap(TTYModes.ofTTY(atPath: pty.path))
        pty.enterSSHRawMode()

        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master }, ttyPath: pty.path, goodModes: snapshot, repairNow: true)

        let modes = pty.slaveModes
        XCTAssertTrue(has(modes.c_lflag, ISIG))
        XCTAssertTrue(has(modes.c_lflag, IEXTEN))
        XCTAssertTrue(has(modes.c_oflag, OPOST))
        XCTAssertTrue(has(modes.c_iflag, ICRNL))
        XCTAssertTrue(has(modes.c_iflag, IXANY))
        XCTAssertFalse(has(modes.c_iflag, IXON), "the snapshot had flow control off")
        XCTAssertFalse(has(modes.c_lflag, ICANON))
        XCTAssertFalse(has(modes.c_lflag, ECHO))
        XCTAssertTrue(repairer.isArmed)
    }

    func testRepairUsesDefaultModesWithoutSnapshot() throws {
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master }, ttyPath: pty.path, goodModes: nil, repairNow: true)
        let modes = pty.slaveModes
        XCTAssertTrue(has(modes.c_lflag, ISIG))
        XCTAssertTrue(has(modes.c_oflag, OPOST))
        XCTAssertTrue(has(modes.c_iflag, IXON))
        XCTAssertTrue(has(modes.c_iflag, ICRNL))
    }

    func testRepairLeavesNonRawTTYAlone() throws {
        let pty = try PTYPair()
        var modes = goodModes
        modes.c_lflag &= ~tcflag_t(ICANON | ECHO)
        pty.setSlaveModes(modes)
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master },
                                         ttyPath: pty.path,
                                         goodModes: TTYModes(path: pty.path, modes: goodModes),
                                         repairNow: true)
        XCTAssertEqual(pty.slaveModes.c_lflag, modes.c_lflag)
        XCTAssertEqual(pty.slaveModes.c_iflag, modes.c_iflag)
        XCTAssertFalse(repairer.isArmed)
    }

    // A shell that recorded ssh's modes reapplies them before the next command. The
    // repairer fixes them when the command starts, so the shell records good modes when
    // it exits, and then stops.
    func testCommandStartRepairsModesTheShellReapplied() throws {
        let pty = try PTYPair()
        let snapshot = TTYModes(path: pty.path, modes: goodModes)
        pty.enterSSHRawMode()
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master }, ttyPath: pty.path, goodModes: snapshot, repairNow: true)

        pty.enterSSHRawMode()
        pty.reapplyRecordedModesLikeZsh()
        repairer.commandWillRun()
        let modes = pty.slaveModes
        // The kernel may add PENDIN when canonical mode comes back on.
        let localFlags = TTYModeRepairer.sshRawLocalFlagsOutsideLineEditor | TTYModeRepairer.sshRawLocalFlagsManagedByLineEditor
        XCTAssertEqual(modes.c_lflag & localFlags, goodModes.c_lflag & localFlags)
        XCTAssertEqual(modes.c_oflag & tcflag_t(OPOST), goodModes.c_oflag & tcflag_t(OPOST))
        XCTAssertEqual(modes.c_iflag & TTYModeRepairer.sshRawInputFlags,
                       goodModes.c_iflag & TTYModeRepairer.sshRawInputFlags)

        repairer.commandDidFinish()
        XCTAssertFalse(repairer.isArmed)

        // Disarmed: later raw modes are someone else's.
        pty.enterSSHRawMode()
        pty.reapplyRecordedModesLikeZsh()
        let before = pty.slaveModes
        repairer.commandWillRun()
        XCTAssertEqual(pty.slaveModes.c_lflag, before.c_lflag)
    }

    // A builtin doesn't make the shell record the modes, so the repairer stays armed.
    func testStaysArmedWhileShellStillReappliesRawModes() throws {
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master },
                                         ttyPath: pty.path,
                                         goodModes: TTYModes(path: pty.path, modes: goodModes),
                                         repairNow: true)
        pty.enterSSHRawMode()
        pty.reapplyRecordedModesLikeZsh()
        repairer.commandDidFinish()
        XCTAssertTrue(repairer.isArmed)
    }

    // Once the session's pty is closed its fd number may be reused by another session's
    // pty, which is left alone.
    func testReusedDescriptorForAnotherPTYIsNotTouched() throws {
        let repairer = TTYModeRepairer()
        let first = try PTYPair()
        let second = try PTYPair()
        first.enterSSHRawMode()
        var fd = first.master
        repairer.repairAfterAbandonedSSH(fileDescriptor: { fd },
                                         ttyPath: first.path,
                                         goodModes: TTYModes(path: first.path, modes: goodModes),
                                         repairNow: true)
        XCTAssertTrue(repairer.isArmed)
        // The number now refers to another pty.
        fd = second.master
        second.enterSSHRawMode()
        second.reapplyRecordedModesLikeZsh()
        let before = second.slaveModes
        repairer.commandWillRun()
        XCTAssertEqual(second.slaveModes.c_lflag, before.c_lflag)
        XCTAssertEqual(second.slaveModes.c_oflag, before.c_oflag)
        repairer.commandDidFinish()
        XCTAssertFalse(repairer.isArmed)
    }

    // A pty that isn't the session's is never touched, even the first time.
    func testWrongPTYIsNotRepaired() throws {
        let repairer = TTYModeRepairer()
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        let before = pty.slaveModes
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master },
                                         ttyPath: "/dev/ttys999",
                                         goodModes: nil,
                                         repairNow: true)
        XCTAssertFalse(repairer.isArmed)
        XCTAssertEqual(pty.slaveModes.c_lflag, before.c_lflag)
    }

    // When something other than the shell may be using the tty the repairer only arms, and
    // acts once the shell starts a command with its reapplied raw modes.
    func testArmingWithoutRepairingLeavesModesUntilCommandStarts() throws {
        let repairer = TTYModeRepairer()
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        let before = pty.slaveModes
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master },
                                         ttyPath: pty.path,
                                         goodModes: TTYModes(path: pty.path, modes: goodModes),
                                         repairNow: false)
        XCTAssertTrue(repairer.isArmed)
        XCTAssertEqual(pty.slaveModes.c_lflag, before.c_lflag)
        XCTAssertEqual(pty.slaveModes.c_oflag, before.c_oflag)
        pty.reapplyRecordedModesLikeZsh()
        repairer.commandWillRun()
        XCTAssertTrue(has(pty.slaveModes.c_lflag, ISIG))
        XCTAssertTrue(has(pty.slaveModes.c_oflag, OPOST))
    }

    // A program that makes the tty raw itself (e.g., a new ssh, or an editor) clears
    // ICANON and ECHO, so it is never disturbed.
    func testCommandStartLeavesRawProgramAlone() throws {
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master },
                                         ttyPath: pty.path,
                                         goodModes: TTYModes(path: pty.path, modes: goodModes),
                                         repairNow: true)
        pty.enterSSHRawMode()
        let before = pty.slaveModes
        repairer.commandWillRun()
        let after = pty.slaveModes
        XCTAssertEqual(after.c_lflag, before.c_lflag)
        XCTAssertEqual(after.c_iflag, before.c_iflag)
        XCTAssertEqual(after.c_oflag, before.c_oflag)
        XCTAssertTrue(repairer.isArmed)
    }

    // End to end with a real zsh: a foreground job that made the tty raw is killed, as
    // it2ssh is. zsh records the raw modes and reapplies them before every command, so
    // fixing the tty at the prompt doesn't last; fixing it again when the next external
    // command starts does.
    func testZshRecordsRepairedModes() throws {
        let zsh = "/bin/zsh"
        guard FileManager.default.fileExists(atPath: zsh) else {
            throw XCTSkip("no zsh")
        }
        let lock = NSLock()
        var output = ""
        let shell = try LiveShell(shellPath: zsh,
                                  arguments: ["zsh", "-f", "-i"],
                                  environment: ["PS1": "PROMPT> ",
                                                "TERM": "dumb",
                                                "PATH": "/usr/bin:/bin",
                                                "HOME": NSTemporaryDirectory()],
                                  onBytes: { bytes, count in
            let chunk = String(decoding: UnsafeRawBufferPointer(start: bytes, count: count), as: UTF8.self)
            lock.lock()
            output += chunk
            lock.unlock()
        })
        defer {
            shell.terminate()
        }
        // Waits for the marker and returns the output before it, discarding the output
        // through it.
        @discardableResult
        func waitFor(_ marker: String) throws -> String {
            var before = ""
            try shell.waitUntil(marker, timeout: 30) {
                lock.lock()
                defer { lock.unlock() }
                guard let range = output.range(of: marker) else {
                    return false
                }
                before = String(output[..<range.lowerBound])
                output.removeSubrange(output.startIndex..<range.upperBound)
                return true
            }
            return before
        }
        func lflags() throws -> String {
            shell.send("/bin/stty -a\n")
            let text = try waitFor("LINE-READY-MARK")
            guard let range = text.range(of: "lflags:") else {
                return ""
            }
            return String(text[range.lowerBound...].prefix { $0 != "\n" && $0 != "\r" })
        }
        func modes() -> termios {
            var modes = termios()
            XCTAssertEqual(tcgetattr(shell.fileDescriptor, &modes), 0)
            return modes
        }

        // The markers print what happens when. The line editor only takes input after
        // zle-line-init runs. They are built from a variable so that the echo of this
        // command line doesn't contain them.
        shell.send("m=MARK; zle-line-init() { print -n LINE-READY-$m }; zle -N zle-line-init; " +
                   "preexec() { print -n COMMAND-STARTS-$m }; precmd() { print -n COMMAND-DONE-$m }\n")
        try waitFor("LINE-READY-MARK")

        let good = TTYModes(path: "", modes: TTYModeRepairer.defaultModes)
        shell.send("/bin/bash -c 'stty -istrip -inlcr -igncr -icrnl -ixon -ixany -ixoff " +
                   "-icanon -isig -echo -echoe -echok -echonl -iexten -opost min 1 time 0; kill -TERM $$'\n")
        try waitFor("COMMAND-DONE-MARK")
        try waitFor("LINE-READY-MARK")
        XCTAssertFalse(has(modes().c_lflag, ISIG))

        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { shell.fileDescriptor },
                                         ttyPath: slavePath(shell.fileDescriptor),
                                         goodModes: good,
                                         repairNow: true)
        XCTAssertTrue(has(modes().c_lflag, ISIG))
        XCTAssertTrue(has(modes().c_oflag, OPOST))

        // zsh reapplies the modes it recorded when the job died.
        XCTAssertTrue(try lflags().contains("-isig"))
        XCTAssertTrue(repairer.isArmed)

        // cat runs until it reads end of file, so the repair surely happens while it runs.
        shell.send("/bin/cat > /dev/null\n")
        try waitFor("COMMAND-STARTS-MARK")
        repairer.commandWillRun()
        shell.send("\u{04}")
        try waitFor("COMMAND-DONE-MARK")
        repairer.commandDidFinish()
        XCTAssertFalse(repairer.isArmed)
        try waitFor("LINE-READY-MARK")

        let fixed = try lflags()
        XCTAssertTrue(fixed.contains(" isig"), fixed)
        XCTAssertTrue(fixed.contains(" iexten"), fixed)
        XCTAssertTrue(fixed.contains(" icanon"), fixed)
    }
}
