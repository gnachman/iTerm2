//
//  ClaudeCodeRemoteConfigDirResolverTests.swift
//  iTerm2 ModernTests
//
//  Finding CLAUDE_CONFIG_DIR on a host reached through SSH Integration (Phase 4b). The remote
//  login shell runs /usr/bin/env between two random markers, interactive and login as iTerm2 runs
//  it, so the rc files that usually set the variable are read. Everything outside the markers is
//  rc-file noise. A lookup that cannot finish is a failure, never a guess.
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeCodeRemoteConfigDirResolverTests: XCTestCase {
    private typealias Resolver = ClaudeCodeRemoteConfigDirResolver

    private let sentinel = "0123abcd"

    private func output(before: String = "", env: [String], after: String = "",
                        lineEnding: String = "\n") -> String {
        var lines = [String]()
        if !before.isEmpty {
            lines.append(before)
        }
        lines.append(Resolver.startMarker(sentinel))
        lines += env
        lines.append(Resolver.endMarker(sentinel))
        if !after.isEmpty {
            lines.append(after)
        }
        return lines.joined(separator: lineEnding) + lineEnding
    }

    // MARK: - The command

    func testCommandRunsTheLoginShellInteractiveAndLogin() {
        let command = Resolver.commandLine(shell: "/usr/bin/zsh", sentinel: sentinel)
        XCTAssertEqual(command,
                       "'/usr/bin/zsh' -i -l -c 'echo \(Resolver.startMarker(sentinel)); /usr/bin/env; echo \(Resolver.endMarker(sentinel))'")
    }

    // Separate flags, because not every shell accepts them bundled.
    func testFishGetsSeparateFlags() {
        XCTAssertTrue(Resolver.commandLine(shell: "/usr/bin/fish", sentinel: sentinel)
            .hasPrefix("'/usr/bin/fish' -i -l -c "))
    }

    // tcsh takes -l only on its own and xonsh spells it --login: interactive only, as locally.
    func testShellsWithoutAUsableLoginFlagRunInteractiveOnly() {
        XCTAssertTrue(Resolver.commandLine(shell: "/bin/tcsh", sentinel: sentinel).hasPrefix("'/bin/tcsh' -i -c "))
        XCTAssertTrue(Resolver.commandLine(shell: "/usr/local/bin/xonsh", sentinel: sentinel)
            .hasPrefix("'/usr/local/bin/xonsh' -i -c "))
    }

    // The command goes through /bin/sh -c on the host, so the path must survive it.
    func testShellPathIsQuotedForSh() {
        XCTAssertTrue(Resolver.commandLine(shell: "/opt/my shells/it's/zsh", sentinel: sentinel)
            .hasPrefix("'/opt/my shells/it'\\''s/zsh' -i -l -c "))
    }

    // MARK: - Reading the answer

    func testValueBetweenTheMarkersIsUsed() {
        let text = output(env: ["HOME=/home/u", "CLAUDE_CONFIG_DIR=/srv/claude-work", "PATH=/bin"])
        XCTAssertEqual(Resolver.directory(fromOutput: text, sentinel: sentinel, home: "/home/u"),
                       "/srv/claude-work")
    }

    // Unset is a real answer: Claude Code's own default, under the REMOTE home.
    func testUnsetMeansDotClaudeUnderTheRemoteHome() {
        let text = output(env: ["HOME=/home/u", "PATH=/bin"])
        XCTAssertEqual(Resolver.directory(fromOutput: text, sentinel: sentinel, home: "/home/u"),
                       "/home/u/.claude")
    }

    func testEmptyValueMeansTheDefault() {
        let text = output(env: ["CLAUDE_CONFIG_DIR="])
        XCTAssertEqual(Resolver.directory(fromOutput: text, sentinel: sentinel, home: "/home/u"),
                       "/home/u/.claude")
    }

    // rc files print banners, motd, shell-integration codes, and might even mention the variable.
    // None of it counts.
    func testNoiseOutsideTheMarkersIsIgnored() {
        let text = output(before: "Welcome!\nCLAUDE_CONFIG_DIR=/wrong/before\n\u{1b}]1337;ShellIntegrationVersion=1\u{7}",
                          env: ["CLAUDE_CONFIG_DIR=/right"],
                          after: "CLAUDE_CONFIG_DIR=/wrong/after\nlogout")
        XCTAssertEqual(Resolver.directory(fromOutput: text, sentinel: sentinel, home: "/home/u"), "/right")
    }

    // A pty turns \n into \r\n.
    func testCarriageReturnsAreTolerated() {
        let text = output(env: ["CLAUDE_CONFIG_DIR=/srv/claude"], lineEnding: "\r\n")
        XCTAssertEqual(Resolver.directory(fromOutput: text, sentinel: sentinel, home: "/home/u"), "/srv/claude")
    }

    func testTildeExpandsToTheRemoteHome() {
        XCTAssertEqual(Resolver.directory(fromOutput: output(env: ["CLAUDE_CONFIG_DIR=~/work-claude"]),
                                          sentinel: sentinel, home: "/home/u"),
                       "/home/u/work-claude")
        XCTAssertEqual(Resolver.directory(fromOutput: output(env: ["CLAUDE_CONFIG_DIR=~"]),
                                          sentinel: sentinel, home: "/home/u"),
                       "/home/u")
    }

    // No start marker: the shell never ran the command. No end marker: it was cut off partway, so
    // a missing variable might just not have been printed yet. Both are failures, not "unset".
    func testMissingMarkersAreFailures() {
        XCTAssertNil(Resolver.directory(fromOutput: "zsh: command not found\n", sentinel: sentinel, home: "/home/u"))
        let truncated = Resolver.startMarker(sentinel) + "\nHOME=/home/u\n"
        XCTAssertNil(Resolver.directory(fromOutput: truncated, sentinel: sentinel, home: "/home/u"))
    }

    // A marker from some other run (a different sentinel) proves nothing.
    func testOtherSentinelsDoNotCount() {
        let text = output(env: ["CLAUDE_CONFIG_DIR=/x"])
        XCTAssertNil(Resolver.directory(fromOutput: text, sentinel: "ffff0000", home: "/home/u"))
    }

    // MARK: - Running it

    private final class CommandLog {
        var commands = [String]()
        var killed = [Int32]()
    }

    private final class Clock {
        var pending = [() -> Void]()
        func fire() {
            let blocks = pending
            pending = []
            blocks.forEach { $0() }
        }
    }

    private func dependencies(clock: Clock,
                              log: CommandLog? = nil,
                              started: ((@escaping (Int32) -> Void) -> Void)? = nil,
                              run: @escaping (String, @escaping (Data, Int32) -> Void) -> Void) -> Resolver.Dependencies {
        return Resolver.Dependencies(
            run: { command, startedCallback, completion in
                log?.commands.append(command)
                started?(startedCallback)
                run(command, completion)
            },
            kill: { pid in log?.killed.append(pid) },
            after: { _, block in clock.pending.append(block) },
            makeSentinel: { self.sentinel })
    }

    func testResolveDeliversTheDirectory() {
        let clock = Clock()
        var result: String??
        let deps = dependencies(clock: clock) { _, completion in
            completion(Data(self.output(env: ["CLAUDE_CONFIG_DIR=/srv/c"]).utf8), 0)
        }
        Resolver.resolve(shell: "/bin/zsh", home: "/home/u", dependencies: deps) { result = .some($0) }
        XCTAssertEqual(result, .some("/srv/c"))
    }

    // Sentinels present but a nonzero status (a failing .zlogout, say): the answer still stands.
    func testNonzeroStatusWithBothMarkersStillCounts() {
        let clock = Clock()
        var result: String??
        let deps = dependencies(clock: clock) { _, completion in
            completion(Data(self.output(env: []).utf8), 1)
        }
        Resolver.resolve(shell: "/bin/zsh", home: "/home/u", dependencies: deps) { result = .some($0) }
        XCTAssertEqual(result, .some("/home/u/.claude"))
    }

    // An rc file that waits for input would hold the install forever. The deadline fails it, and
    // an answer arriving afterwards is ignored rather than delivered twice.
    func testDeadlineFailsAndALateAnswerIsIgnored() {
        let clock = Clock()
        var results = [String?]()
        var finish: ((Data, Int32) -> Void)?
        let deps = dependencies(clock: clock) { _, completion in finish = completion }
        Resolver.resolve(shell: "/bin/zsh", home: "/home/u", dependencies: deps) { results.append($0) }
        XCTAssertTrue(results.isEmpty)
        clock.fire()
        XCTAssertEqual(results, [nil])
        finish?(Data(output(env: ["CLAUDE_CONFIG_DIR=/late"]).utf8), 0)
        XCTAssertEqual(results, [nil], "delivered exactly once")
    }

    // A shell that never answers (an rc file waiting for input) is ended at the deadline rather
    // than left on the host for the life of the connection.
    func testTheShellIsEndedAtTheDeadline() {
        let clock = Clock()
        let log = CommandLog()
        var results = [String?]()
        let deps = dependencies(clock: clock, log: log, started: { $0(77) }) { _, _ in }
        Resolver.resolve(shell: "/bin/zsh", home: "/home/u", dependencies: deps) { results.append($0) }
        XCTAssertEqual(log.killed, [])
        clock.fire()
        XCTAssertEqual(results, [nil])
        XCTAssertEqual(log.killed, [77])
    }

    // Its pid may arrive only after the deadline passed.
    func testAShellThatStartsAfterTheDeadlineIsEnded() {
        let clock = Clock()
        let log = CommandLog()
        var start: ((Int32) -> Void)?
        let deps = dependencies(clock: clock, log: log, started: { start = $0 }) { _, _ in }
        Resolver.resolve(shell: "/bin/zsh", home: "/home/u", dependencies: deps) { _ in }
        clock.fire()
        XCTAssertEqual(log.killed, [])
        start?(78)
        XCTAssertEqual(log.killed, [78])
    }

    // One that answered, or exited without answering, is left alone.
    func testAShellThatExitedIsNotEnded() {
        let clock = Clock()
        let log = CommandLog()
        let deps = dependencies(clock: clock, log: log, started: { $0(79) }) { _, completion in
            completion(Data("noise".utf8), 1)
        }
        Resolver.resolve(shell: "/bin/zsh", home: "/home/u", dependencies: deps) { _ in }
        clock.fire()
        XCTAssertEqual(log.killed, [])
    }

    // Without the remote login shell or home there is nothing safe to run or to default to.
    // Nothing from the profile is ever substituted: a custom command must not be run again.
    func testMissingShellOrHomeFailsWithoutRunningAnything() {
        let clock = Clock()
        let log = CommandLog()
        var results = [String?]()
        let deps = dependencies(clock: clock, log: log) { _, _ in }
        Resolver.resolve(shell: nil, home: "/home/u", dependencies: deps) { results.append($0) }
        Resolver.resolve(shell: "/bin/zsh", home: nil, dependencies: deps) { results.append($0) }
        Resolver.resolve(shell: "", home: "/home/u", dependencies: deps) { results.append($0) }
        XCTAssertEqual(results, [nil, nil, nil])
        XCTAssertEqual(log.commands, [])
    }
}
