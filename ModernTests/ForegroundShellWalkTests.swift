//
//  ForegroundShellWalkTests.swift
//  ModernTests
//
//  Which process a working directory poll reads. It must be the shell the user is in, which in a
//  nested shell (bash from zsh, sudo -s, poetry shell) is not the session's root process, and
//  while a command runs is the shell that started it rather than the command, a subshell, or a
//  shell running a script, any of which may change its own directory.
//
//  The process tables mirror what an interactive zsh in a pty shows (observed with ps-style
//  sysctls under tmux): a shell doing job control puts each job in a process group led by the
//  job's first process, while subshells and script shells leave what they run in their own group.
//  A program that relays a pty (script, sudo with use_pty, pexpect) starts a child in a new session
//  on that pty, which is the only way to tell it apart from other commands.
//

import XCTest
@testable import iTerm2SharedARC

final class ForegroundShellWalkTests: XCTestCase {
    private struct FakeProcess {
        var name: String
        var ppid: pid_t
        var pgid: pid_t
        var didExec = true
        var arguments: [String]? = nil
        // The session's own pty unless a relay put it on another.
        var tty: dev_t = ForegroundShellWalkTests.sessionTTY
        // The foreground process group of its tty. Only read for a relay's first process.
        var tpgid: pid_t = 0
    }

    private static let sessionTTY: dev_t = 1
    // No controlling terminal.
    private static let noTTY: dev_t = -1

    // How many times the last walk read the whole process table.
    private var tableReads = 0

    private func walkProcess(_ pid: pid_t, _ process: FakeProcess) -> iTermWalkProcess {
        var result = iTermWalkProcess()
        result.pid = pid
        result.ppid = process.ppid
        result.pgid = process.pgid
        result.didExec = ObjCBool(process.didExec)
        result.tty = process.tty
        result.ttyForegroundProcessGroup = process.tpgid
        withUnsafeMutableBytes(of: &result.name) { buffer in
            buffer.copyBytes(from: process.name.utf8.prefix(buffer.count - 1))
        }
        return result
    }

    private func walk(root: pid_t, pgrp: pid_t, _ table: [pid_t: FakeProcess]) -> pid_t {
        tableReads = 0
        return iTermLSOF.foregroundShellPid(withRootPid: root,
                                            foregroundProcessGroup: pgrp,
                                            lookup: { pid, process in
            guard let fake = table[pid] else {
                return false
            }
            process?.pointee = walkProcess(pid, fake)
            return true
        }, processTable: {
            tableReads += 1
            let processes = table.map { walkProcess($0.key, $0.value) }
            return processes.withUnsafeBytes { Data($0) }
        }, arguments: { pid in
            return table[pid]?.arguments
        })
    }

    // login(100) -> -zsh(200), the user's interactive shell, in its own group.
    private func session(_ more: [pid_t: FakeProcess]) -> [pid_t: FakeProcess] {
        var table: [pid_t: FakeProcess] = [
            100: FakeProcess(name: "login", ppid: 1, pgid: 100),
            200: FakeProcess(name: "-zsh", ppid: 100, pgid: 200, arguments: ["-zsh"]),
        ]
        table.merge(more) { $1 }
        return table
    }

    // MARK: - The leader is a shell at its prompt

    func testShellAtPromptIsItself() {
        XCTAssertEqual(walk(root: 100, pgrp: 200, session([:])), 200)
        XCTAssertEqual(tableReads, 0)
    }

    func testLeaderIsRootGivesRoot() {
        XCTAssertEqual(walk(root: 200, pgrp: 200, session([:])), 200)
    }

    func testNestedInteractiveShellAtPrompt() {
        let table = session([
            300: FakeProcess(name: "bash", ppid: 200, pgid: 300, arguments: ["bash", "--norc", "-i"]),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 300)
        // The leader alone settles it.
        XCTAssertEqual(tableReads, 0)
    }

    // A shell on a tty is interactive without -i.
    func testNestedShellWithOptionsAtPrompt() {
        let table = session([
            300: FakeProcess(name: "zsh", ppid: 200, pgid: 300, arguments: ["zsh", "-f", "-o", "vi"]),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 300)
    }

    // A root shell from sudo -s without use_pty: its arguments can't be read, and neither can its
    // directory, which is handled by the caller. The walk still picks it.
    func testShellWithUnreadableArgumentsAtPrompt() {
        let table = session([
            300: FakeProcess(name: "sudo", ppid: 200, pgid: 300),
            400: FakeProcess(name: "zsh", ppid: 300, pgid: 400, arguments: nil),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 400, table), 400)
    }

    // MARK: - The foreground job is a command

    func testCommandGivesTheShellThatStartedIt() {
        let table = session([
            300: FakeProcess(name: "make", ppid: 200, pgid: 300),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
        XCTAssertEqual(tableReads, 1)
    }

    // If the table can't be read, a command's shell can't be found.
    func testUnreadableTableGivesNothing() {
        let table = session([
            300: FakeProcess(name: "make", ppid: 200, pgid: 300),
        ])
        let pid = iTermLSOF.foregroundShellPid(withRootPid: 100,
                                               foregroundProcessGroup: 300,
                                               lookup: { pid, process in
            guard let fake = table[pid] else {
                return false
            }
            process?.pointee = walkProcess(pid, fake)
            return true
        }, processTable: {
            return nil
        }, arguments: { pid in
            return table[pid]?.arguments
        })
        XCTAssertEqual(pid, -1)
    }

    // ssh doesn't change directory; the shell that ran it is where the user is.
    func testSSHUnderNestedShellGivesTheNestedShell() {
        let table = session([
            300: FakeProcess(name: "bash", ppid: 200, pgid: 300, arguments: ["bash"]),
            400: FakeProcess(name: "ssh", ppid: 300, pgid: 400),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 400, table), 300)
    }

    // zsh runs the last command of a subshell with exec, so after `( cd /tmp; sleep 30 )` the
    // leader is sleep, in /tmp, and its parent is the interactive shell.
    func testZshSubshellExecingItsCommand() {
        let table = session([
            300: FakeProcess(name: "sleep", ppid: 200, pgid: 300),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // `( cd /tmp; sleep 30; true )`: the subshell leads the group, and the command it runs is in it.
    func testSubshellRunningACommand() {
        let table = session([
            300: FakeProcess(name: "zsh", ppid: 200, pgid: 300, didExec: false, arguments: ["-zsh"]),
            301: FakeProcess(name: "sleep", ppid: 300, pgid: 300),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // `( cd /tmp; while :; do :; done )`: only the subshell, which looks like its parent but never
    // exec'ed.
    func testSubshellRunningOnlyBuiltins() {
        let table = session([
            300: FakeProcess(name: "zsh", ppid: 200, pgid: 300, didExec: false, arguments: ["-zsh"]),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // A subshell in a nested bash: skipped, giving the nested bash, not the outer zsh.
    func testSubshellInNestedShell() {
        let table = session([
            300: FakeProcess(name: "bash", ppid: 200, pgid: 300, arguments: ["bash", "--norc", "-i"]),
            400: FakeProcess(name: "bash", ppid: 300, pgid: 400, didExec: false, arguments: ["bash", "--norc", "-i"]),
            401: FakeProcess(name: "sleep", ppid: 400, pgid: 400),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 400, table), 300)
    }

    // `sleep 30 | while read x; do :; done`, as bash runs it: sleep leads the group and the loop
    // runs in a subshell, both children of the shell.
    func testPipelineWithSubshellElement() {
        let table = session([
            300: FakeProcess(name: "sleep", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 200, pgid: 300, didExec: false, arguments: ["-zsh"]),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // ./build.sh running sleep. The script's shell leads the group.
    func testScriptRunningACommand() {
        let table = session([
            300: FakeProcess(name: "bash", ppid: 200, pgid: 300, arguments: ["bash", "./build.sh"]),
            301: FakeProcess(name: "sleep", ppid: 300, pgid: 300),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    func testScriptRunningOnlyBuiltins() {
        let table = session([
            300: FakeProcess(name: "bash", ppid: 200, pgid: 300, arguments: ["bash", "./busy.sh"]),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    func testCommandStringShell() {
        let table = session([
            300: FakeProcess(name: "bash", ppid: 200, pgid: 300, arguments: ["sh", "-c", "cd /tmp; true"]),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // A script that runs a script: both are in the foreground group, so both are skipped.
    func testNestedScripts() {
        let table = session([
            300: FakeProcess(name: "bash", ppid: 200, pgid: 300, arguments: ["bash", "outer.sh"]),
            301: FakeProcess(name: "sh", ppid: 300, pgid: 300, arguments: ["sh", "inner.sh"]),
            302: FakeProcess(name: "make", ppid: 301, pgid: 300),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // A shell that isn't recognized by name (xonsh runs as Python) is still found while it runs a
    // command, because it started the job.
    func testUnrecognizedShellRunningACommand() {
        let table = session([
            300: FakeProcess(name: "Python", ppid: 200, pgid: 300),
            400: FakeProcess(name: "make", ppid: 300, pgid: 400),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 400, table), 300)
    }

    // Known limitation: at its prompt, an unrecognized shell looks like a command, so its parent
    // shell is read.
    func testUnrecognizedShellAtPromptGivesItsParentShell() {
        let table = session([
            300: FakeProcess(name: "Python", ppid: 200, pgid: 300),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // E.g., the session runs a script rather than an interactive shell, so nothing does job control.
    func testJobOfRootGivesRoot() {
        let table: [pid_t: FakeProcess] = [
            100: FakeProcess(name: "bash", ppid: 1, pgid: 100, arguments: ["bash", "job.sh"]),
            200: FakeProcess(name: "python3", ppid: 100, pgid: 100),
        ]
        XCTAssertEqual(walk(root: 100, pgrp: 100, table), 100)
    }

    // MARK: - The leader exited

    // `ps aux | less` once ps finishes: the group's leader is gone and less remains.
    func testExitedPipelineLeaderUsesRemainingMember() {
        let table = session([
            301: FakeProcess(name: "less", ppid: 200, pgid: 300),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // The remaining member may be below a subshell in the job, which is skipped.
    func testExitedLeaderWithMemberBelowSubshell() {
        let table = session([
            301: FakeProcess(name: "zsh", ppid: 200, pgid: 300, didExec: false, arguments: ["-zsh"]),
            302: FakeProcess(name: "less", ppid: 301, pgid: 300),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // The same in a nested shell gives the nested shell.
    func testExitedLeaderInNestedShell() {
        let table = session([
            300: FakeProcess(name: "bash", ppid: 200, pgid: 300, arguments: ["bash"]),
            401: FakeProcess(name: "less", ppid: 300, pgid: 400),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 400, table), 300)
    }

    // A pid reused by a process in another group isn't the leader, but the job's other members
    // still lead to its shell.
    func testLeaderPidReusedUsesRemainingMember() {
        let table = session([
            300: FakeProcess(name: "make", ppid: 1, pgid: 777),
            301: FakeProcess(name: "less", ppid: 200, pgid: 300),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // MARK: - Giving up

    // The group has no members, e.g., they exited since the terminal was asked for it.
    func testNoMemberGivesNothing() {
        XCTAssertEqual(walk(root: 100, pgrp: 999, session([:])), -1)
    }

    func testLeaderPidReusedWithNoOtherMembersGivesNothing() {
        let table = session([
            300: FakeProcess(name: "make", ppid: 200, pgid: 777),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), -1)
    }

    func testMissingAncestorGivesNothing() {
        let table = session([
            400: FakeProcess(name: "make", ppid: 300, pgid: 400),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 400, table), -1)
    }

    // A leader that launchd adopted no longer leads to the shell that started it. Reading the
    // root would describe some other shell.
    func testLeaderNotBelowRootGivesNothing() {
        let table = session([
            500: FakeProcess(name: "python3", ppid: 1, pgid: 500),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 500, table), -1)
    }

    // The same for an ancestor in the job, e.g., a subshell whose parent exited.
    func testJobOutsideRootsTreeGivesNothing() {
        let table = session([
            500: FakeProcess(name: "zsh", ppid: 1, pgid: 500, didExec: false, arguments: ["-zsh"]),
            501: FakeProcess(name: "sleep", ppid: 500, pgid: 500),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 500, table), -1)
    }

    // With the leader gone, the only remaining member was adopted by launchd.
    func testExitedLeaderWithOnlyAnAdoptedMemberGivesNothing() {
        let table = session([
            301: FakeProcess(name: "less", ppid: 1, pgid: 300),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), -1)
    }

    // A member launchd adopted is passed over for one that still leads to the shell, whatever
    // their pids.
    func testExitedLeaderPrefersMemberWithItsParent() {
        let table = session([
            301: FakeProcess(name: "cat", ppid: 1, pgid: 300),
            302: FakeProcess(name: "less", ppid: 200, pgid: 300),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // MARK: - Relays

    private let relayTTY: dev_t = 2
    private let innerRelayTTY: dev_t = 3

    // sudo 1.9.14 and later use a pty by default: sudo's monitor starts a session on it and runs
    // the root shell there. The shell's arguments and directory can't be read, so the poll gives
    // nothing rather than the directory of the shell that ran sudo.
    func testSudoWithPtyGivesTheRootShell() {
        let table = session([
            300: FakeProcess(name: "sudo", ppid: 200, pgid: 300),
            301: FakeProcess(name: "sudo", ppid: 300, pgid: 301, tty: relayTTY, tpgid: 400),
            400: FakeProcess(name: "zsh", ppid: 301, pgid: 400, arguments: nil, tty: relayTTY),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 400)
    }

    // script runs the shell as the first process on its pty.
    func testRelayedShellAtPrompt() {
        let table = session([
            300: FakeProcess(name: "script", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 300, pgid: 301, arguments: ["zsh", "-f"], tty: relayTTY, tpgid: 301),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 301)
    }

    // poetry shell (pexpect), then `cd sub && claude` in it.
    func testRelayedShellRunningACommand() {
        let table = session([
            300: FakeProcess(name: "Python", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 300, pgid: 301, arguments: ["zsh"], tty: relayTTY, tpgid: 400),
            400: FakeProcess(name: "claude", ppid: 301, pgid: 400, tty: relayTTY),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 301)
    }

    // poetry shell run from poetry shell.
    func testNestedRelays() {
        let table = session([
            300: FakeProcess(name: "Python", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 300, pgid: 301, arguments: ["zsh"], tty: relayTTY, tpgid: 400),
            400: FakeProcess(name: "Python", ppid: 301, pgid: 400, tty: relayTTY),
            401: FakeProcess(name: "zsh", ppid: 400, pgid: 401, arguments: ["zsh"], tty: innerRelayTTY, tpgid: 401),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 401)
        // Every terminal is searched in the same snapshot.
        XCTAssertEqual(tableReads, 1)
    }

    func testNestedRelaysWithInnerShellRunningACommand() {
        let table = session([
            300: FakeProcess(name: "Python", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 300, pgid: 301, arguments: ["zsh"], tty: relayTTY, tpgid: 400),
            400: FakeProcess(name: "Python", ppid: 301, pgid: 400, tty: relayTTY),
            401: FakeProcess(name: "zsh", ppid: 400, pgid: 401, arguments: ["zsh"], tty: innerRelayTTY, tpgid: 500),
            500: FakeProcess(name: "vim", ppid: 401, pgid: 500, tty: innerRelayTTY),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 401)
    }

    // An expect script driving ssh: nobody types into a shell on its pty, so the shell that ran
    // the script is where the user is, and a `cd foo && ./deploy.exp` is noticed.
    func testRelayWithoutAShellGivesTheOuterShell() {
        let table = session([
            300: FakeProcess(name: "expect", ppid: 200, pgid: 300),
            301: FakeProcess(name: "ssh", ppid: 300, pgid: 301, tty: relayTTY, tpgid: 301),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // A tool that runs commands on a pty (node-pty) while the user's shell waits for it.
    func testRelayedCommandStringGivesTheOuterShell() {
        let table = session([
            300: FakeProcess(name: "node", ppid: 200, pgid: 300),
            301: FakeProcess(name: "bash", ppid: 300, pgid: 301, arguments: ["bash", "-c", "cd x && npm test"], tty: relayTTY, tpgid: 301),
            302: FakeProcess(name: "npm", ppid: 301, pgid: 301, tty: relayTTY),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // `sudo make install` with use_pty: make's parent is sudo's monitor, which isn't a shell.
    func testSudoCommandWithPtyGivesTheOuterShell() {
        let table = session([
            300: FakeProcess(name: "sudo", ppid: 200, pgid: 300),
            301: FakeProcess(name: "sudo", ppid: 300, pgid: 301, tty: relayTTY, tpgid: 302),
            302: FakeProcess(name: "make", ppid: 301, pgid: 302, tty: relayTTY),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // An editor with two terminal buffers: which one the user is in can't be known.
    func testSeveralRelaysGiveTheOuterShell() {
        let table = session([
            300: FakeProcess(name: "emacs", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 300, pgid: 301, arguments: ["zsh"], tty: relayTTY, tpgid: 301),
            302: FakeProcess(name: "zsh", ppid: 300, pgid: 302, arguments: ["zsh"], tty: innerRelayTTY, tpgid: 302),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // Known limitation: an editor with one terminal buffer looks like a relay, so the buffer's
    // shell is read.
    func testSingleTerminalBufferIsFollowed() {
        let table = session([
            300: FakeProcess(name: "nvim", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 300, pgid: 301, arguments: ["zsh"], tty: relayTTY, tpgid: 301),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 301)
    }

    // Claude Code's children have no terminal, so they aren't relays, even a shell.
    func testChildrenWithoutATerminalAreNotRelays() {
        let table = session([
            300: FakeProcess(name: "claude", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 300, pgid: 301, arguments: ["zsh"], tty: ForegroundShellWalkTests.noTTY),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // What a process without a terminal starts is still searched.
    func testRelayBelowAProcessWithoutATerminal() {
        let table = session([
            300: FakeProcess(name: "claude", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 300, pgid: 301, arguments: ["zsh", "-c", "script -q /dev/null"], tty: ForegroundShellWalkTests.noTTY),
            302: FakeProcess(name: "script", ppid: 301, pgid: 301, tty: ForegroundShellWalkTests.noTTY),
            303: FakeProcess(name: "zsh", ppid: 302, pgid: 303, arguments: ["zsh"], tty: relayTTY, tpgid: 303),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 303)
    }

    // While the relay starts, its pty may have no foreground group yet.
    func testRelayWithoutForegroundGroupGivesTheOuterShell() {
        let table = session([
            300: FakeProcess(name: "script", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 300, pgid: 301, arguments: ["zsh"], tty: relayTTY, tpgid: 0),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // An inner terminal whose foreground group has no members, e.g., while the relay exits, gives
    // nothing: the outer shell isn't the one the user is typing into.
    func testRelayWithEmptyForegroundGroupGivesNothing() {
        let table = session([
            300: FakeProcess(name: "script", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 300, pgid: 301, arguments: ["zsh"], tty: relayTTY, tpgid: 999),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), -1)
    }

    // A terminal already searched isn't searched again, so the walk ends.
    func testRelayBackToAnEarlierTerminalIsIgnored() {
        let table = session([
            300: FakeProcess(name: "script", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 300, pgid: 301, arguments: ["zsh"], tty: relayTTY, tpgid: 400),
            400: FakeProcess(name: "odd", ppid: 301, pgid: 400, tty: relayTTY),
            401: FakeProcess(name: "odd", ppid: 400, pgid: 401, tty: ForegroundShellWalkTests.sessionTTY, tpgid: 300),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 301)
    }

    // A relay run directly by the session, e.g., a profile whose command is `script`.
    func testRelayRunByTheRoot() {
        let table: [pid_t: FakeProcess] = [
            100: FakeProcess(name: "script", ppid: 1, pgid: 100),
            101: FakeProcess(name: "zsh", ppid: 100, pgid: 101, arguments: ["zsh"], tty: relayTTY, tpgid: 101),
        ]
        XCTAssertEqual(walk(root: 100, pgrp: 100, table), 101)
    }

    // poetry shell at its prompt: pexpect execs the user's shell as the first process on its pty.
    func testPexpectShellAtPrompt() {
        let table = session([
            300: FakeProcess(name: "Python", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 300, pgid: 301, arguments: ["-zsh"], tty: relayTTY, tpgid: 301),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 301)
    }

    // Known limitation: a script driving an interactive shell through pexpect looks just like
    // poetry shell, so its shell is read while it runs.
    func testScriptDrivingAnInteractiveShellIsFollowed() {
        let table = session([
            300: FakeProcess(name: "Python", ppid: 200, pgid: 300, arguments: ["python3", "automate.py"]),
            301: FakeProcess(name: "bash", ppid: 300, pgid: 301, arguments: ["bash"], tty: relayTTY, tpgid: 301),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 301)
    }

    // `cd ~/proj && claude` with no relay: claude's children have no terminal, so the shell that
    // started claude is read, wherever its cd took it.
    func testCommandWithChildrenWithoutATerminal() {
        let table = session([
            300: FakeProcess(name: "claude", ppid: 200, pgid: 300),
            301: FakeProcess(name: "zsh", ppid: 300, pgid: 301, arguments: ["zsh", "-c", "git diff"], tty: ForegroundShellWalkTests.noTTY),
            302: FakeProcess(name: "git", ppid: 301, pgid: 301, tty: ForegroundShellWalkTests.noTTY),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // Relays nested deeper than the limit aren't followed. The deepest terminal searched gives
    // its shell.
    func testRelayDepthIsBounded() {
        var table = session([:])
        var parentShell: pid_t = 200
        for level in 0..<12 {
            let relay = pid_t(1000 + level * 10)
            let shell = relay + 1
            let tty = dev_t(10 + level)
            table[relay] = FakeProcess(name: "script", ppid: parentShell, pgid: relay,
                                       tty: level == 0 ? ForegroundShellWalkTests.sessionTTY : dev_t(9 + level))
            table[shell] = FakeProcess(name: "zsh", ppid: relay, pgid: shell, arguments: ["zsh"], tty: tty, tpgid: relay + 10)
            parentShell = shell
        }
        // The innermost shell is at its prompt.
        table[1111]!.tpgid = 1111
        // Eight relays are followed from the session's terminal: the shell on the eighth terminal
        // (level 7) started the next relay, which isn't followed.
        XCTAssertEqual(walk(root: 100, pgrp: 1000, table), 1071)
    }

    // A job with a large tree is searched whole: only processes on other terminals walk up.
    func testRelayBelowALargeJob() {
        var table = session([
            300: FakeProcess(name: "make", ppid: 200, pgid: 300),
        ])
        for i in 0..<5000 {
            table[pid_t(10000 + i)] = FakeProcess(name: "cc", ppid: 300, pgid: 300)
        }
        table[20000] = FakeProcess(name: "script", ppid: 14999, pgid: 300)
        table[20001] = FakeProcess(name: "zsh", ppid: 20000, pgid: 20001, arguments: ["zsh"], tty: relayTTY, tpgid: 20001)
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 20001)
    }

    // Processes on other terminals elsewhere on the system (other sessions) aren't relays.
    func testOtherSessionsAreNotRelays() {
        let table = session([
            300: FakeProcess(name: "make", ppid: 200, pgid: 300),
            500: FakeProcess(name: "login", ppid: 1, pgid: 500, tty: relayTTY, tpgid: 600),
            600: FakeProcess(name: "-zsh", ppid: 500, pgid: 600, arguments: ["-zsh"], tty: relayTTY, tpgid: 600),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // A relay of a background job isn't the foreground job's.
    func testRelayOfABackgroundJobIsIgnored() {
        let table = session([
            300: FakeProcess(name: "make", ppid: 200, pgid: 300),
            400: FakeProcess(name: "script", ppid: 200, pgid: 400),
            401: FakeProcess(name: "zsh", ppid: 400, pgid: 401, arguments: ["zsh"], tty: relayTTY, tpgid: 401),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // A parent cycle, which pid reuse during the snapshot could make, ends the walk up.
    func testParentCycleBelowJobEnds() {
        let table = session([
            300: FakeProcess(name: "make", ppid: 200, pgid: 300),
            400: FakeProcess(name: "odd", ppid: 401, pgid: 400, tty: ForegroundShellWalkTests.noTTY),
            401: FakeProcess(name: "odd", ppid: 400, pgid: 400, tty: ForegroundShellWalkTests.noTTY),
            402: FakeProcess(name: "zsh", ppid: 400, pgid: 402, arguments: ["zsh"], tty: relayTTY, tpgid: 402),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // MARK: - Known limitations of the shell tests

    // `bash < script` reads commands from a redirect but has the arguments of an interactive
    // shell, so it counts as one at its prompt.
    func testShellReadingARedirectCountsAsInteractive() {
        let table = session([
            300: FakeProcess(name: "bash", ppid: 200, pgid: 300, arguments: ["bash"]),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 300)
    }

    // `zsh -i -c cmd` is interactive but runs a command, so it doesn't count as a shell at its
    // prompt.
    func testInteractiveShellRunningACommandIsNotAtItsPrompt() {
        let table = session([
            300: FakeProcess(name: "zsh", ppid: 200, pgid: 300, arguments: ["zsh", "-i", "-c", "make"]),
        ])
        XCTAssertEqual(walk(root: 100, pgrp: 300, table), 200)
    }

    // MARK: - Shell arguments

    private func runsScript(_ argv: [String]) -> Bool {
        return iTermLSOF.shellArgumentsRunScriptOrCommand(argv)
    }

    func testArgumentsOfInteractiveShells() {
        XCTAssertFalse(runsScript(["-zsh"]))
        XCTAssertFalse(runsScript(["zsh", "-f"]))
        XCTAssertFalse(runsScript(["bash", "--norc", "-i"]))
        XCTAssertFalse(runsScript(["bash", "-l"]))
        XCTAssertFalse(runsScript(["bash", "--rcfile", "my.rc"]))
        XCTAssertFalse(runsScript(["zsh", "-o", "vi"]))
        XCTAssertFalse(runsScript(["zsh", "+o", "nomatch"]))
        XCTAssertFalse(runsScript(["bash", "-O", "extglob"]))
        XCTAssertFalse(runsScript(["zsh", "--emulate", "sh"]))
        XCTAssertFalse(runsScript(["fish", "-C", "set x 1"]))
        XCTAssertFalse(runsScript(["fish", "--init-command", "set x 1"]))
        XCTAssertFalse(runsScript(["bash", "-s", "arg"]))
        XCTAssertFalse(runsScript(["bash", "--"]))
        XCTAssertFalse(runsScript([]))
    }

    func testArgumentsOfScriptsAndCommands() {
        XCTAssertTrue(runsScript(["bash", "./build.sh"]))
        XCTAssertTrue(runsScript(["bash", "-e", "build.sh"]))
        XCTAssertTrue(runsScript(["sh", "-c", "true"]))
        XCTAssertTrue(runsScript(["bash", "-lc", "true"]))
        XCTAssertTrue(runsScript(["bash", "-ic", "true"]))
        XCTAssertTrue(runsScript(["zsh", "-o", "vi", "script.zsh"]))
        XCTAssertTrue(runsScript(["zsh", "--", "script.zsh"]))
        XCTAssertTrue(runsScript(["fish", "--command=ls"]))
        XCTAssertTrue(runsScript(["fish", "--command", "ls"]))
        XCTAssertTrue(runsScript(["fish", "script.fish"]))
    }

    // MARK: - Reading arguments

    // The arguments are read with a buffer sized to the process's argument area rather than
    // KERN_ARGMAX. This process's own arguments and environment must still come back whole.
    func testArgumentsAndEnvironmentOfThisProcess() throws {
        var execName: NSString?
        let argv = try XCTUnwrap(iTermLSOF.rawCommandLineArguments(forProcess: getpid(),
                                                                    execName: &execName))
        var expected = ProcessInfo.processInfo.arguments.filter { !$0.isEmpty }
        expected[0] = (expected[0] as NSString).lastPathComponent
        XCTAssertEqual(argv, expected)
        XCTAssertEqual(execName.map { String($0) }, Bundle.main.executablePath)

        let environment = try XCTUnwrap(iTermLSOF.environment(forProcess: getpid()))
        XCTAssertFalse(environment.isEmpty)
        XCTAssertTrue(environment.allSatisfy { $0.contains("=") })
    }
}
