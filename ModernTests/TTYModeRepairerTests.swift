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

    // Everything that can be read from the master without waiting.
    func readAvailableFromMaster() -> [UInt8] {
        return Self.readAvailable(master)
    }

    // Everything that can be read from the slave without waiting. The slave must not be
    // canonical, or a partial line would not be readable.
    func readAvailableFromSlave() -> [UInt8] {
        return Self.readAvailable(slave)
    }

    private static func readAvailable(_ fd: Int32) -> [UInt8] {
        var result = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, 200) == 1 else {
                return result
            }
            let n = read(fd, &buffer, buffer.count)
            guard n > 0 else {
                return result
            }
            result.append(contentsOf: buffer[0..<n])
        }
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
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master }, ttyPath: pty.path, goodModes: snapshot, repairNow: true, shellProcessID: 0)

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
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master }, ttyPath: pty.path, goodModes: nil, repairNow: true, shellProcessID: 0)
        let modes = pty.slaveModes
        XCTAssertTrue(has(modes.c_lflag, ISIG))
        XCTAssertTrue(has(modes.c_oflag, OPOST))
        XCTAssertTrue(has(modes.c_iflag, IXON))
        XCTAssertTrue(has(modes.c_iflag, ICRNL))
    }

    // F-554: the conductor's commands (e.g., an autopoll request) that the dead ssh client
    // didn't read are discarded instead of being read by the shell. Input written later is
    // delivered.
    func testDiscardPendingInputDropsWhatTheDeadClientDidNotRead() throws {
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        let stale = Array("YXV0b3BvbGw=\n".utf8)
        XCTAssertEqual(write(pty.master, stale, stale.count), stale.count)

        XCTAssertTrue(TTYModeRepairer.discardPendingInput(masterFileDescriptor: pty.master, ttyPath: pty.path))
        XCTAssertEqual(pty.readAvailableFromSlave(), [])

        let later = Array("ls\n".utf8)
        XCTAssertEqual(write(pty.master, later, later.count), later.count)
        XCTAssertEqual(pty.readAvailableFromSlave(), later)
    }

    // Pending input and unwritten output are discarded only when the connection was
    // abandoned just now, nothing else owns the tty, and the tty was still in ssh's raw
    // mode. Not from Disconnect's forced unhook seconds later, when the shell may have owned
    // the tty for a while (the input may be the user's typeahead), and not when another
    // program is in the foreground (a large paste's unwritten tail may be its).
    func testMayDiscardInputOnlyRightAfterAbandoningWhileSSHRawModeRemains() {
        XCTAssertTrue(TTYModeRepairer.mayDiscardInputForDeadClient(abandonedJustNow: true, repairNow: true, foundSSHRawMode: true))
        XCTAssertFalse(TTYModeRepairer.mayDiscardInputForDeadClient(abandonedJustNow: false, repairNow: true, foundSSHRawMode: true))
        XCTAssertFalse(TTYModeRepairer.mayDiscardInputForDeadClient(abandonedJustNow: true, repairNow: false, foundSSHRawMode: true))
        XCTAssertFalse(TTYModeRepairer.mayDiscardInputForDeadClient(abandonedJustNow: true, repairNow: true, foundSSHRawMode: false))
    }

    // What decides foundSSHRawMode: the repairer arms only for a tty still in ssh's raw mode.
    func testRepairerArmsOnlyForSSHRawMode() throws {
        let pty = try PTYPair()
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master }, ttyPath: pty.path, goodModes: nil, repairNow: true, shellProcessID: 0)
        XCTAssertFalse(repairer.isArmed, "a sane tty")
        pty.enterSSHRawMode()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master }, ttyPath: pty.path, goodModes: nil, repairNow: true, shellProcessID: 0)
        XCTAssertTrue(repairer.isArmed, "ssh's raw mode")
    }

    // A pty that isn't the session's keeps its input.
    func testDiscardPendingInputLeavesAnotherPTYAlone() throws {
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        let input = Array("keep".utf8)
        XCTAssertEqual(write(pty.master, input, input.count), input.count)
        XCTAssertFalse(TTYModeRepairer.discardPendingInput(masterFileDescriptor: pty.master, ttyPath: "/dev/ttys999"))
        XCTAssertEqual(pty.readAvailableFromSlave(), input)
    }

    // F-553: setting the modes through the pty's master discards the output still waiting
    // to be read (on macOS a set-attributes ioctl on the master flushes the output queue)
    // and doesn't wake a writer waiting for that queue to drain. zsh restores its tty
    // modes with TCSADRAIN when the killed it2ssh's job ends, so it slept, and nothing it
    // printed was drawn, until something else wrote to the tty.
    func testRepairKeepsOutputWaitingToBeRead() throws {
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        let pending = Array("output from the remote".utf8)
        XCTAssertEqual(write(pty.slave, pending, pending.count), pending.count)

        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master }, ttyPath: pty.path, goodModes: nil, repairNow: true, shellProcessID: 0)
        XCTAssertTrue(has(pty.slaveModes.c_oflag, OPOST), "the repair must still happen")

        XCTAssertEqual(pty.readAvailableFromMaster(), pending)
    }

    // The same for the repair when a command starts.
    func testCommandStartRepairKeepsOutputWaitingToBeRead() throws {
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master },
                                         ttyPath: pty.path,
                                         goodModes: TTYModes(path: pty.path, modes: goodModes),
                                         repairNow: false, shellProcessID: 0)
        pty.reapplyRecordedModesLikeZsh()
        let pending = Array("prompt".utf8)
        XCTAssertEqual(write(pty.slave, pending, pending.count), pending.count)
        repairer.commandWillRun()
        XCTAssertTrue(has(pty.slaveModes.c_oflag, OPOST), "the repair must still happen")
        XCTAssertEqual(pty.readAvailableFromMaster(), pending)
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
                                         repairNow: true, shellProcessID: 0)
        XCTAssertEqual(pty.slaveModes.c_lflag, modes.c_lflag)
        XCTAssertEqual(pty.slaveModes.c_iflag, modes.c_iflag)
        XCTAssertFalse(repairer.isArmed)
    }

    // A shell that recorded ssh's modes reapplies them before the next command. The
    // repairer fixes them when the command starts, so the shell records good modes when
    // it exits. It stops once a command starts with the good modes the shell recorded.
    func testCommandStartRepairsModesTheShellReapplied() throws {
        let pty = try PTYPair()
        let snapshot = TTYModes(path: pty.path, modes: goodModes)
        pty.enterSSHRawMode()
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master }, ttyPath: pty.path, goodModes: snapshot, repairNow: true, shellProcessID: 0)

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
        XCTAssertTrue(repairer.isArmed)
        repairer.commandWillRun()
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
                                         repairNow: true, shellProcessID: 0)
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
                                         repairNow: true, shellProcessID: 0)
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
                                         repairNow: true, shellProcessID: 0)
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
                                         repairNow: false, shellProcessID: 0)
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
                                         repairNow: true, shellProcessID: 0)
        pty.enterSSHRawMode()
        let before = pty.slaveModes
        repairer.commandWillRun()
        let after = pty.slaveModes
        XCTAssertEqual(after.c_lflag, before.c_lflag)
        XCTAssertEqual(after.c_iflag, before.c_iflag)
        XCTAssertEqual(after.c_oflag, before.c_oflag)
        XCTAssertTrue(repairer.isArmed)
    }
    // F-541: zsh reports the end of the killed it2ssh command (OSC 133 D) right after the
    // repair at the prompt, but it has recorded ssh's modes and reapplies them before the
    // next command. That report must not disarm the repairer.
    func testCommandFinishingRightAfterRepairDoesNotDisarm() throws {
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master },
                                         ttyPath: pty.path,
                                         goodModes: TTYModes(path: pty.path, modes: goodModes),
                                         repairNow: true,
                                         shellProcessID: 0)
        // The killed it2ssh's command finishes.
        repairer.commandDidFinish()
        XCTAssertTrue(repairer.isArmed)

        // zsh reapplies the modes it recorded when it2ssh died, and the next command starts.
        pty.enterSSHRawMode()
        pty.reapplyRecordedModesLikeZsh()
        repairer.commandWillRun()
        XCTAssertTrue(has(pty.slaveModes.c_lflag, ISIG))
        XCTAssertTrue(has(pty.slaveModes.c_oflag, OPOST))
        // Until a command starts with good modes, the shell may still have ssh's recorded.
        repairer.commandDidFinish()
        XCTAssertTrue(repairer.isArmed)

        // The shell recorded the repaired modes, so the next command starts with them.
        repairer.commandWillRun()
        XCTAssertTrue(repairer.isArmed)
        repairer.commandDidFinish()
        XCTAssertFalse(repairer.isArmed)
    }

    // A builtin doesn't make zsh record the modes, so they come back before the next
    // command and are repaired again.
    func testShellReapplyingRawModesAfterRepairedCommandIsRepairedAgain() throws {
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master },
                                         ttyPath: pty.path,
                                         goodModes: TTYModes(path: pty.path, modes: goodModes),
                                         repairNow: true,
                                         shellProcessID: 0)
        repairer.commandDidFinish()
        for _ in 0..<3 {
            pty.enterSSHRawMode()
            pty.reapplyRecordedModesLikeZsh()
            repairer.commandWillRun()
            XCTAssertTrue(has(pty.slaveModes.c_lflag, ISIG))
            repairer.commandDidFinish()
            XCTAssertTrue(repairer.isArmed)
        }
    }

    // Good modes when a command starts prove nothing if they are the repairer's own,
    // set since the last command finished: the shell hasn't reapplied its recorded modes
    // over them.
    func testCommandStartingWithRepairersOwnModesDoesNotDisarm() throws {
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        // Between commands, zsh has its recorded modes applied.
        pty.reapplyRecordedModesLikeZsh()
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master },
                                         ttyPath: pty.path,
                                         goodModes: TTYModes(path: pty.path, modes: goodModes),
                                         repairNow: true,
                                         shellProcessID: 0)
        XCTAssertTrue(has(pty.slaveModes.c_lflag, ISIG))
        XCTAssertTrue(has(pty.slaveModes.c_lflag, ICANON))
        repairer.commandWillRun()
        repairer.commandDidFinish()
        XCTAssertTrue(repairer.isArmed)
    }

    // Without shell integration nothing reports commands, but the shell forks to run
    // one after reapplying its recorded modes.
    func testShellForkRepairsReappliedModes() throws {
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master },
                                         ttyPath: pty.path,
                                         goodModes: TTYModes(path: pty.path, modes: goodModes),
                                         repairNow: false,
                                         shellProcessID: 0)
        // A raw program is left alone.
        let raw = pty.slaveModes
        repairer.shellDidFork()
        XCTAssertEqual(pty.slaveModes.c_lflag, raw.c_lflag)
        XCTAssertEqual(pty.slaveModes.c_oflag, raw.c_oflag)

        pty.reapplyRecordedModesLikeZsh()
        repairer.shellDidFork()
        let modes = pty.slaveModes
        XCTAssertTrue(has(modes.c_lflag, ISIG))
        XCTAssertTrue(has(modes.c_lflag, IEXTEN))
        XCTAssertTrue(has(modes.c_oflag, OPOST))
        XCTAssertTrue(has(modes.c_iflag, ICRNL))
        // A fork says nothing about what the shell recorded.
        repairer.shellDidFork()
        XCTAssertTrue(repairer.isArmed)

        repairer.disarm()
        pty.enterSSHRawMode()
        pty.reapplyRecordedModesLikeZsh()
        let before = pty.slaveModes
        repairer.shellDidFork()
        XCTAssertEqual(pty.slaveModes.c_lflag, before.c_lflag)
    }

    // Forks are reported when they happen but commands only once the shell's output is
    // parsed. When parsing lags, the fork for the next command (e.g., a background job,
    // after which the shell records nothing) may come before the previous command's end.
    // Its repair still doesn't count as the shell's good modes when the next command
    // starts.
    func testForkRepairBeforeLaggingCommandEndIsNotTheShellsModes() throws {
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master },
                                         ttyPath: pty.path,
                                         goodModes: TTYModes(path: pty.path, modes: goodModes),
                                         repairNow: false,
                                         shellProcessID: 0)
        pty.reapplyRecordedModesLikeZsh()
        repairer.shellDidFork()
        XCTAssertTrue(has(pty.slaveModes.c_lflag, ISIG))
        // The previous command's end, parsed late.
        repairer.commandDidFinish()
        repairer.commandWillRun()
        repairer.commandDidFinish()
        XCTAssertTrue(repairer.isArmed)
    }

    // The repairer stops watching a shell once it exits.
    func testDisarmsWhenWatchedShellExits() throws {
        let pty = try PTYPair()
        pty.enterSSHRawMode()
        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/cat"), nil]
        defer {
            argv.forEach { free($0) }
        }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer {
            posix_spawn_file_actions_destroy(&actions)
        }
        posix_spawn_file_actions_adddup2(&actions, pty.slave, 0)
        XCTAssertEqual(posix_spawn(&pid, "/bin/cat", &actions, nil, argv, nil), 0)
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { pty.master },
                                         ttyPath: pty.path,
                                         goodModes: TTYModes(path: pty.path, modes: goodModes),
                                         repairNow: false,
                                         shellProcessID: pid)
        XCTAssertTrue(repairer.isArmed)
        let disarmed = expectation(description: "disarmed")
        repairer.didStopWatchingShellForTesting = {
            disarmed.fulfill()
        }
        kill(pid, SIGKILL)
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        wait(for: [disarmed], timeout: 30)
        XCTAssertFalse(repairer.isArmed)
    }

    // End to end with a real zsh: a foreground job that made the tty raw is killed, as
    // it2ssh is. zsh records the raw modes and reapplies them before every command, so
    // fixing the tty at the prompt doesn't last; fixing it again when the next external
    // command starts does. zsh reports the killed command's end right after the repair
    // at the prompt (F-541).
    func testZshRecordsModesRepairedWhenCommandStarts() throws {
        let zsh = try ZshWithKilledRawJob()
        defer {
            zsh.shell.terminate()
        }
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { zsh.shell.fileDescriptor },
                                         ttyPath: slavePath(zsh.shell.fileDescriptor),
                                         goodModes: zsh.good,
                                         repairNow: true,
                                         shellProcessID: 0)
        XCTAssertTrue(has(zsh.modes().c_lflag, ISIG))
        XCTAssertTrue(has(zsh.modes().c_oflag, OPOST))
        // OSC 133 D for the killed command.
        repairer.commandDidFinish()
        XCTAssertTrue(repairer.isArmed)

        // zsh reapplies the modes it recorded when the job died.
        XCTAssertTrue(try zsh.lflags().contains("-isig"))
        XCTAssertTrue(repairer.isArmed)

        // cat runs until it reads end of file, so the repair surely happens while it runs.
        zsh.shell.send("/bin/cat > /dev/null\n")
        try zsh.waitFor("COMMAND-STARTS-MARK")
        repairer.commandWillRun()
        zsh.shell.send("\u{04}")
        try zsh.waitFor("COMMAND-DONE-MARK")
        repairer.commandDidFinish()
        XCTAssertTrue(repairer.isArmed)
        try zsh.waitFor("LINE-READY-MARK")

        // The next command starts with the modes zsh recorded, which are good now.
        zsh.shell.send("/bin/cat > /dev/null\n")
        try zsh.waitFor("COMMAND-STARTS-MARK")
        repairer.commandWillRun()
        zsh.shell.send("\u{04}")
        try zsh.waitFor("COMMAND-DONE-MARK")
        repairer.commandDidFinish()
        XCTAssertFalse(repairer.isArmed)
        try zsh.waitFor("LINE-READY-MARK")

        let fixed = try zsh.lflags()
        XCTAssertTrue(fixed.contains(" isig"), fixed)
        XCTAssertTrue(fixed.contains(" iexten"), fixed)
        XCTAssertTrue(fixed.contains(" icanon"), fixed)
        // At the prompt the line editor works from the modes zsh recorded.
        XCTAssertTrue(has(zsh.modes().c_oflag, OPOST))
    }

    // Without shell integration nothing reports when a command starts. The repairer
    // watches the shell instead and fixes the modes it reapplied when it forks to run a
    // command, so zsh records good modes when the command exits.
    func testZshWithoutShellIntegrationRecordsModesRepairedWhenItForks() throws {
        let zsh = try ZshWithKilledRawJob()
        defer {
            zsh.shell.terminate()
        }
        let repairer = TTYModeRepairer()
        repairer.repairAfterAbandonedSSH(fileDescriptor: { zsh.shell.fileDescriptor },
                                         ttyPath: slavePath(zsh.shell.fileDescriptor),
                                         goodModes: zsh.good,
                                         repairNow: true,
                                         shellProcessID: zsh.shell.processID)
        XCTAssertTrue(has(zsh.modes().c_lflag, ISIG))

        // cat runs until it reads end of file. While it runs the modes are what zsh
        // reapplied, repaired when zsh forked.
        zsh.shell.send("/bin/cat > /dev/null\n")
        try zsh.waitFor("COMMAND-STARTS-MARK")
        try zsh.shell.waitUntil("repaired modes", timeout: 30) {
            let modes = zsh.modes()
            return has(modes.c_lflag, ISIG) && has(modes.c_lflag, ICANON) && has(modes.c_oflag, OPOST)
        }
        zsh.shell.send("\u{04}")
        try zsh.waitFor("COMMAND-DONE-MARK")
        try zsh.waitFor("LINE-READY-MARK")

        let fixed = try zsh.lflags()
        XCTAssertTrue(fixed.contains(" isig"), fixed)
        XCTAssertTrue(fixed.contains(" iexten"), fixed)
        XCTAssertTrue(fixed.contains(" icanon"), fixed)
        XCTAssertTrue(repairer.isArmed)
        repairer.disarm()
    }
}

// A real interactive zsh whose foreground job made the tty raw as ssh does and was then
// killed, as a killed it2ssh's ssh is, so zsh recorded the raw modes.
private final class ZshWithKilledRawJob {
    let shell: LiveShell
    let good = TTYModes(path: "", modes: TTYModeRepairer.defaultModes)
    // The shell's output not yet consumed by waitFor.
    private let output = OutputBuffer()

    init() throws {
        let zsh = "/bin/zsh"
        guard FileManager.default.fileExists(atPath: zsh) else {
            throw XCTSkip("no zsh")
        }
        let output = self.output
        shell = try LiveShell(shellPath: zsh,
                              arguments: ["zsh", "-f", "-i"],
                              environment: ["PS1": "PROMPT> ",
                                            "TERM": "dumb",
                                            "PATH": "/usr/bin:/bin",
                                            "HOME": NSTemporaryDirectory()],
                              onBytes: { bytes, count in
            output.append(String(decoding: UnsafeRawBufferPointer(start: bytes, count: count), as: UTF8.self))
        })

        // The markers print what happens when. The line editor only takes input after
        // zle-line-init runs. They are built from a variable so that the echo of this
        // command line doesn't contain them.
        shell.send("m=MARK; zle-line-init() { print -n LINE-READY-$m }; zle -N zle-line-init; " +
                   "preexec() { print -n COMMAND-STARTS-$m }; precmd() { print -n COMMAND-DONE-$m }\n")
        try waitFor("LINE-READY-MARK")

        shell.send("/bin/bash -c 'stty -istrip -inlcr -igncr -icrnl -ixon -ixany -ixoff " +
                   "-icanon -isig -echo -echoe -echok -echonl -iexten -opost min 1 time 0; kill -TERM $$'\n")
        try waitFor("COMMAND-DONE-MARK")
        try waitFor("LINE-READY-MARK")
        XCTAssertFalse(has(modes().c_lflag, ISIG))
    }

    // Waits for the marker and returns the output before it, discarding the output
    // through it.
    @discardableResult
    func waitFor(_ marker: String) throws -> String {
        var before = ""
        try shell.waitUntil(marker, timeout: 30) {
            guard let text = output.consume(through: marker) else {
                return false
            }
            before = text
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
}

private final class OutputBuffer {
    private let lock = NSLock()
    private var text = ""

    func append(_ chunk: String) {
        lock.lock()
        text += chunk
        lock.unlock()
    }

    // Returns the text before the marker and discards it through the marker, or returns
    // nil if the marker hasn't arrived.
    func consume(through marker: String) -> String? {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard let range = text.range(of: marker) else {
            return nil
        }
        let before = String(text[..<range.lowerBound])
        text.removeSubrange(text.startIndex..<range.upperBound)
        return before
    }
}
