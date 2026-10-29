//
//  ClaudeInteractivityTests.swift
//  iTerm2 ModernTests
//
//  The offer to try the Claude Code integration waits until a run of claude looks like an
//  interactive session. A non-interactive run (`claude -p`, `claude plugin list`) is recognized
//  from its command line where that can be read, and otherwise by its tty staying canonical.
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeInvocationTests: XCTestCase {
    private func classify(_ arguments: String...) -> ClaudeInvocation {
        return ClaudeInvocation.classify(arguments: arguments)
    }

    func testBareClaudeIsUndetermined() {
        XCTAssertEqual(classify(), .undetermined)
    }

    func testPromptIsUndetermined() {
        XCTAssertEqual(classify("fix the bug"), .undetermined)
        XCTAssertEqual(classify("--model", "opus", "fix the bug"), .undetermined)
        XCTAssertEqual(classify("-c"), .undetermined)
    }

    func testPrintIsNonInteractive() {
        XCTAssertEqual(classify("-p", "hello"), .nonInteractive)
        XCTAssertEqual(classify("--print", "hello"), .nonInteractive)
        XCTAssertEqual(classify("--model", "opus", "-p", "hello"), .nonInteractive)
        XCTAssertEqual(classify("hello", "--print"), .nonInteractive)
    }

    func testAttachedValueStillNamesTheFlag() {
        XCTAssertEqual(classify("--print=true"), .nonInteractive)
    }

    func testVersionHelpAndBackgroundAreNonInteractive() {
        XCTAssertEqual(classify("--version"), .nonInteractive)
        XCTAssertEqual(classify("-v"), .nonInteractive)
        XCTAssertEqual(classify("-h"), .nonInteractive)
        XCTAssertEqual(classify("--bg", "do a thing"), .nonInteractive)
    }

    func testSubcommandsAreNonInteractive() {
        XCTAssertEqual(classify("plugin", "list"), .nonInteractive)
        XCTAssertEqual(classify("mcp", "add", "x"), .nonInteractive)
        XCTAssertEqual(classify("doctor"), .nonInteractive)
    }

    // A word after an option may be its value, so only the first argument can be a subcommand.
    func testAWordAfterAnOptionIsNotASubcommand() {
        XCTAssertEqual(classify("--add-dir", "config"), .undetermined)
        XCTAssertEqual(classify("--add-dir", "logs"), .undetermined)
        XCTAssertEqual(classify("--agent", "agents"), .undetermined)
        XCTAssertEqual(classify("--resume", "update"), .undetermined)
        XCTAssertEqual(classify("--debug", "update"), .undetermined)
    }

    func testAttachOpensASession() {
        XCTAssertEqual(classify("attach", "abc123"), .undetermined)
    }

    func testOnlyTheFirstPositionalCanBeASubcommand() {
        XCTAssertEqual(classify("please", "update", "the", "docs"), .undetermined)
    }

    func testEverythingAfterDoubleDashIsThePrompt() {
        XCTAssertEqual(classify("--", "-p"), .undetermined)
        XCTAssertEqual(classify("--", "doctor"), .undetermined)
    }
}

// The command line is only classified from raw argv. A data source without it can't be trusted:
// ps output, which SSH Integration's process info comes from, has lost the argument boundaries, so
// an interactive `claude "update the readme"` would read as the `update` subcommand and lose the
// offer for good. And the display argv iTermLSOF returns is shell-escaped, which hides flags:
// `--print=x` arrives as `"--print=x"`.
final class ClaudeInvocationDataSourceTests: XCTestCase {
    private static let claudePID: pid_t = 42

    // Answers commandLineArguments with argv shell-escaped the way iTermLSOF does it.
    private class DisplayOnlyDataSource: NSObject, ProcessDataSource {
        let argv: [String]

        init(argv: [String]) {
            self.argv = argv
        }

        private static func escaped(_ argument: String) -> String {
            if argument.isEmpty {
                return "\"\""
            }
            let special = CharacterSet(charactersIn: NSString.shellEscapableCharacters())
            return argument.rangeOfCharacter(from: special) == nil ? argument : "\"\(argument)\""
        }

        func nameOfProcess(withPid thePid: pid_t,
                           isForeground: UnsafeMutablePointer<ObjCBool>) -> String? {
            isForeground.pointee = true
            return "claude"
        }

        func commandLineArguments(forProcess pid: pid_t,
                                  execName: AutoreleasingUnsafeMutablePointer<NSString>?) -> [String]? {
            return pid == ClaudeInvocationDataSourceTests.claudePID ? argv.map(Self.escaped) : nil
        }

        func startTime(forProcess pid: pid_t) -> Date? {
            return nil
        }

        func ttyRdev(forFileDescriptor fd: Int32, ofProcess pid: pid_t) -> dev_t {
            return 0
        }
    }

    // Also has raw argv, like the local data source.
    private final class RawDataSource: DisplayOnlyDataSource {
        @objc(rawCommandLineArgumentsForProcess:)
        func rawCommandLineArguments(forProcess pid: pid_t) -> [String]? {
            return pid == ClaudeInvocationDataSourceTests.claudePID ? argv : nil
        }
    }

    private func classify(_ dataSource: ProcessDataSource) -> ClaudeInvocation {
        return ClaudeInvocation.classify(processID: Self.claudePID, dataSource: dataSource)
    }

    func testRawArgvIsClassified() {
        XCTAssertEqual(classify(RawDataSource(argv: ["claude", "-p", "hi"])), .nonInteractive)
        XCTAssertEqual(classify(RawDataSource(argv: ["claude", "plugin", "list"])), .nonInteractive)
        XCTAssertEqual(classify(RawDataSource(argv: ["claude", "update the readme"])), .undetermined)
    }

    func testFlagsWithAttachedValuesAreSeenInRawArgv() {
        let printWithValue = RawDataSource(argv: ["claude", "--print=x"])
        XCTAssertEqual(printWithValue.commandLineArguments(forProcess: Self.claudePID, execName: nil),
                       ["claude", "\"--print=x\""],
                       "the display argv quotes it, which is why it isn't used")
        XCTAssertEqual(classify(printWithValue), .nonInteractive)
        XCTAssertEqual(classify(RawDataSource(argv: ["claude", "mcp", "list", "--debug=api"])), .nonInteractive,
                       "an option after a subcommand doesn't hide it")
    }

    func testDisplayArgvAloneIsNotClassified() {
        XCTAssertEqual(classify(DisplayOnlyDataSource(argv: ["claude", "-p", "hi"])), .undetermined)
        // What ps-based argv makes of `claude "update the readme"` and `claude "-p is broken"`.
        XCTAssertEqual(classify(DisplayOnlyDataSource(argv: ["claude", "update", "the", "readme"])), .undetermined)
        XCTAssertEqual(classify(DisplayOnlyDataSource(argv: ["claude", "-p", "is", "broken"])), .undetermined)
    }

    func testUnreadableCommandLineIsUndetermined() {
        XCTAssertEqual(ClaudeInvocation.classify(processID: Self.claudePID + 1,
                                                 dataSource: RawDataSource(argv: ["claude", "-p"])),
                       .undetermined)
    }
}

private final class ClaudeInteractivityFakeRunner: SSHCommandRunning {
    func runRemoteCommand(_ commandLine: String, completion: @escaping (Data, Int32) -> ()) {}
    func registerProcess(_ pid: pid_t) {}
    func deregisterProcess(_ pid: pid_t) {}
    func poll(_ completion: @escaping (Data) -> ()) {}
}

// The same, through the process info SSH Integration builds from framer's ps report.
@MainActor
final class ClaudeInvocationOverSSHTests: XCTestCase {
    private let loginShell: pid_t = 100

    private func claudeInvocation(psCommand: String) throws -> ClaudeInvocation {
        let provider = SSHProcessInfoProvider(rootPID: loginShell, runner: ClaudeInteractivityFakeRunner())
        provider.register(trackedPID: loginShell)
        provider.handle("""
        $begin ps
        +100 1 Ss Sun Oct  4 20:00:00 2026 -zsh
        +101 100 S+ Sun Oct  4 20:00:01 2026 \(psCommand)
        """)
        let claude = try XCTUnwrap(provider.processInfo(for: 101))
        return ClaudeInvocation.classify(processID: claude.processID, dataSource: claude.dataSource)
    }

    func testQuotedPromptIsNotMistakenForASubcommand() throws {
        // `claude "update the readme"`: ps has already dropped the quotes.
        XCTAssertEqual(try claudeInvocation(psCommand: "claude update the readme"), .undetermined)
    }

    func testPrintIsLeftToTheTTYCheck() throws {
        // Can't tell `claude -p hi` from `claude "-p hi"`, so the tty mode decides.
        XCTAssertEqual(try claudeInvocation(psCommand: "claude -p hi"), .undetermined)
    }
}

// The session is judged by the claude the user ran, not one its hooks or tools started.
@MainActor
final class ClaudeProcessLocatorTests: XCTestCase {
    private let loginShell: pid_t = 100

    private func provider(_ processes: String) -> SSHProcessInfoProvider {
        let provider = SSHProcessInfoProvider(rootPID: loginShell, runner: ClaudeInteractivityFakeRunner())
        provider.register(trackedPID: loginShell)
        provider.handle("$begin ps\n" + processes)
        return provider
    }

    func testOutermostClaudeIsTheOneTheUserRan() throws {
        // A statusLine script that runs `claude --version`, in claude's foreground process group.
        let provider = provider("""
        +100 1 Ss Sun Oct  4 20:00:00 2026 -zsh
        +101 100 S+ Sun Oct  4 20:00:01 2026 claude
        +102 101 S+ Sun Oct  4 20:00:02 2026 sh -c statusline.sh
        +103 102 S+ Sun Oct  4 20:00:02 2026 claude --version
        """)
        let found = ClaudeProcessLocator.outermostClaude(startingAt: provider.processInfo(for: 103))
        XCTAssertEqual(found?.processID, 101)
    }

    func testForegroundJobCanBeClaudeItself() throws {
        let provider = provider("""
        +100 1 Ss Sun Oct  4 20:00:00 2026 -zsh
        +101 100 S+ Sun Oct  4 20:00:01 2026 claude
        """)
        XCTAssertEqual(ClaudeProcessLocator.outermostClaude(startingAt: provider.processInfo(for: 101))?.processID, 101)
    }

    func testWalkStopsAtTheLoginShell() throws {
        // A claude above the login shell isn't this session's job.
        let provider = provider("""
        +50 1 S Sun Oct  4 19:00:00 2026 claude
        +100 50 Ss Sun Oct  4 20:00:00 2026 -zsh
        +101 100 S+ Sun Oct  4 20:00:01 2026 vim
        """)
        XCTAssertNil(ClaudeProcessLocator.outermostClaude(startingAt: provider.processInfo(for: 101)))
    }
}

// Over SSH Integration, framer's foreground process group is compared with claude's, from the ps
// rows framer reports. Comparing with the login shell's group instead took a nested shell's prompt
// (bash started from the login zsh) for claude.
@MainActor
final class ClaudeForegroundOverSSHTests: XCTestCase {
    private let loginShell: pid_t = 100

    private func claudeHasForeground(rows: String, report: String) throws -> Bool? {
        let provider = SSHProcessInfoProvider(rootPID: loginShell, runner: ClaudeInteractivityFakeRunner())
        provider.register(trackedPID: loginShell)
        provider.handle("$begin ps\n" + rows)
        let claude = try XCTUnwrap(ClaudeProcessLocator.outermostClaude(startingAt: provider.processInfo(for: 103)))
        var tty = Conductor.TTYState()
        tty.apply(ttyNotification: report)
        return ClaudeTTYReading.claudeHasForeground(
            foregroundGroup: tty.foregroundProcessGroup,
            claudeGroup: claude.dataSource.processGroupID?(forProcess: claude.processID))
    }

    // login zsh -> bash -> claude -> (its child, the foreground job)
    private let nested = """
        +100 1 100 Ss Sun Oct  4 20:00:00 2026 -zsh
        +101 100 101 S Sun Oct  4 20:00:01 2026 bash
        +102 101 102 S+ Sun Oct  4 20:00:02 2026 claude
        +103 102 102 S+ Sun Oct  4 20:00:03 2026 node /usr/lib/mcp-server.js
        """

    func testClaudesGroupInTheForeground() throws {
        XCTAssertEqual(try claudeHasForeground(rows: nested, report: "-echo -icanon fgpgid=102"), true)
    }

    func testANestedShellsPromptIsNotClaude() throws {
        // claude exited, bash's prompt is up, and the ps rows haven't caught up yet.
        XCTAssertEqual(try claudeHasForeground(rows: nested, report: "-echo -icanon fgpgid=101"), false)
    }

    func testTheLoginShellsPromptIsNotClaude() throws {
        XCTAssertEqual(try claudeHasForeground(rows: nested, report: "-echo -icanon fgpgid=100"), false)
    }

    func testAnOlderFramerCantTell() throws {
        // No pgid column, and no fgpgid in the report.
        let old = """
            +100 1 Ss Sun Oct  4 20:00:00 2026 -zsh
            +102 100 S+ Sun Oct  4 20:00:02 2026 claude
            +103 102 S+ Sun Oct  4 20:00:03 2026 node /usr/lib/mcp-server.js
            """
        XCTAssertNil(try claudeHasForeground(rows: old, report: "-echo -icanon fgpgid=102"))
        XCTAssertNil(try claudeHasForeground(rows: nested, report: "-echo -icanon"))
    }
}

final class ClaudeTTYModeTests: XCTestCase {
    func testMacOSSttyOutput() {
        let canonical = """
            speed 9600 baud; 24 rows; 80 columns;
            lflags: icanon isig iexten echo echoe -echok echoke -echonl echoctl
            \t-echoprt -altwerase -noflsh -tostop -flusho pendin -nokerninfo
            """
        XCTAssertEqual(ClaudeTTYMode(sttyOutput: canonical), .canonical)
        let raw = canonical.replacingOccurrences(of: " icanon ", with: " -icanon ")
        XCTAssertEqual(ClaudeTTYMode(sttyOutput: raw), .raw)
    }

    func testLinuxSttyOutput() {
        let raw = """
            speed 38400 baud; rows 24; columns 80; line = 0;
            -isig -icanon -iexten -echo echoe echok -echonl -noflsh -xcase
            """
        XCTAssertEqual(ClaudeTTYMode(sttyOutput: raw), .raw)
    }

    func testUnrecognizedOutputIsUnknown() {
        XCTAssertEqual(ClaudeTTYMode(sttyOutput: "stty: stdin isn't a terminal"), .unknown)
        XCTAssertEqual(ClaudeTTYMode(sttyOutput: ""), .unknown)
    }

    func testIcanonFlag() {
        XCTAssertEqual(ClaudeTTYMode(icanon: true), .canonical)
        XCTAssertEqual(ClaudeTTYMode(icanon: false), .raw)
    }

    func testReadingCommand() {
        XCTAssertEqual(ClaudeTmuxPaneTTYModeReader.readingCommand(tty: "/dev/pts/7"),
                       "stty -a < /dev/pts/7; ps -o tpgid= -o pgid= -o args= -t /dev/pts/7")
    }

    private let rawStty = """
        speed 38400 baud; rows 24; columns 80; line = 0;
        -isig -icanon -iexten -echo echoe echok -echonl -noflsh -xcase
        """

    private func tmuxReading(_ ps: String) -> ClaudeTTYReading {
        return ClaudeTmuxPaneTTYModeReader.reading(fromOutput: rawStty + "\n" + ps)
    }

    func testTmuxReadingWhileClaudeHasTheForeground() {
        XCTAssertEqual(tmuxReading("""
             5012  4242 -zsh
             5012  5012 claude
             5012  5012 node /usr/lib/mcp-server.js
            """),
            ClaudeTTYReading(mode: .raw, claudeHasForeground: true))
    }

    func testTmuxReadingAtTheLoginShellsPrompt() {
        XCTAssertEqual(tmuxReading("""
             4242  4242 -zsh
            """),
            ClaudeTTYReading(mode: .raw, claudeHasForeground: false))
    }

    func testTmuxReadingAtANestedShellsPrompt() {
        // claude exited and bash, started from the login zsh, has its prompt up. bash isn't the
        // pane's first process, but it isn't claude either.
        XCTAssertEqual(tmuxReading("""
             5100  4242 -zsh
             5100  5100 bash
             5100  5300 claude
            """).claudeHasForeground,
            false)
    }

    func testTmuxReadingWhenAWrapperRunsClaude() {
        // A script that runs claude without exec: claude shares the script's process group.
        XCTAssertEqual(tmuxReading("""
             5100  4242 -zsh
             5100  5100 /bin/bash /home/me/bin/my-claude.sh
             5100  5100 claude
            """).claudeHasForeground,
            true)
    }

    func testTmuxReadingWhenThePaneStartedClaude() {
        XCTAssertEqual(tmuxReading("""
             4242  4242 claude --model opus
            """).claudeHasForeground,
            true)
    }

    func testTmuxModeComesOnlyFromStty() {
        let canonicalStty = rawStty.replacingOccurrences(of: "-icanon", with: "icanon")
        let output = canonicalStty + "\n" + """
             5100  4242 -zsh
             5100  5100 sh -c stty -icanon; read key
             5100  5100 claude -p summarize -icanon
            """
        XCTAssertEqual(ClaudeTmuxPaneTTYModeReader.reading(fromOutput: output).mode, .canonical,
                       "a process's command line can't change the mode")
    }

    func testTmuxReadingComparesWithinEachRow() {
        // A stray line shaped like a row, ahead of the real ones, must not decide the tpgid.
        XCTAssertEqual(tmuxReading("""
             1793308210  330 1
             5100  4242 -zsh
             5100  5100 claude
            """).claudeHasForeground,
            true)
    }

    func testTmuxReadingWithoutAUsablePsLine() {
        XCTAssertEqual(tmuxReading(""), ClaudeTTYReading(mode: .raw, claudeHasForeground: nil))
        XCTAssertEqual(tmuxReading("ps: unknown option -- t\n"),
                       ClaudeTTYReading(mode: .raw, claudeHasForeground: nil))
    }

    func testTmuxReadingWithNoControllingTerminalCantTell() {
        // procps reports a tpgid of -1 for a process without one, and macOS reports 0.
        XCTAssertNil(tmuxReading("   -1  4242 claude\n").claudeHasForeground)
        XCTAssertNil(tmuxReading("    0  4242 claude\n").claudeHasForeground)
    }

    func testTTYPathValidation() {
        XCTAssertTrue(ClaudeTmuxPaneTTYModeReader.isSafeTTYPath("/dev/pts/7"))
        XCTAssertTrue(ClaudeTmuxPaneTTYModeReader.isSafeTTYPath("/dev/ttys012"))
        XCTAssertFalse(ClaudeTmuxPaneTTYModeReader.isSafeTTYPath("/dev/pts/7; rm -rf ~"))
        XCTAssertFalse(ClaudeTmuxPaneTTYModeReader.isSafeTTYPath("/dev/pts/7'"))
        XCTAssertFalse(ClaudeTmuxPaneTTYModeReader.isSafeTTYPath("/tmp/x"))
        XCTAssertFalse(ClaudeTmuxPaneTTYModeReader.isSafeTTYPath(""))
    }
}

final class ClaudeInteractivityPolicyTests: XCTestCase {
    private typealias Policy = ClaudeInteractivityPolicy

    private func decide(_ invocation: ClaudeInvocation,
                        _ mode: ClaudeTTYMode,
                        _ elapsed: TimeInterval,
                        claudeHasForeground: Bool? = nil) -> Policy.Decision {
        return Policy.decide(invocation: invocation,
                             reading: ClaudeTTYReading(mode: mode, claudeHasForeground: claudeHasForeground),
                             elapsed: elapsed)
    }

    func testEveryReadingIsDecidedByTheGiveUpTime() {
        // The controller polls until a decision, so no reading may keep it polling forever.
        for mode in [ClaudeTTYMode.raw, .canonical, .unknown] {
            for owner in [true, false, nil] as [Bool?] {
                XCTAssertNotEqual(decide(.undetermined, mode, Policy.giveUpTime, claudeHasForeground: owner),
                                  .checkAgain(after: Policy.checkInterval),
                                  "mode \(mode), claudeHasForeground \(String(describing: owner))")
            }
        }
    }

    // Every common shell puts the tty in raw mode at its prompt. A raw reading taken while claude
    // doesn't have the foreground (claude -p already exited, or a stale report from before it
    // started) must not count as a session.
    func testRawWithoutClaudeInTheForegroundIsAPrompt() {
        XCTAssertEqual(decide(.undetermined, .raw, Policy.settleTime + 5, claudeHasForeground: false),
                       .checkAgain(after: Policy.checkInterval))
    }

    func testClaudeLackingTheForegroundForTheWholeRunGivesUp() {
        // e.g. a claude without the terminal as its controlling one. Polling must not go on for as
        // long as claude runs.
        XCTAssertEqual(decide(.undetermined, .raw, Policy.giveUpTime - 0.1, claudeHasForeground: false),
                       .checkAgain(after: Policy.checkInterval))
        XCTAssertEqual(decide(.undetermined, .raw, Policy.giveUpTime, claudeHasForeground: false), .decline)
        XCTAssertEqual(decide(.undetermined, .canonical, Policy.giveUpTime * 100, claudeHasForeground: false),
                       .decline)
    }

    func testRawWhileClaudeHasTheForegroundIsOffered() {
        XCTAssertEqual(decide(.undetermined, .raw, Policy.settleTime, claudeHasForeground: true), .offer)
        XCTAssertEqual(decide(.undetermined, .raw, Policy.settleTime - 0.1, claudeHasForeground: true),
                       .checkAgain(after: Policy.checkInterval))
    }

    func testRawWithoutForegroundInformationKeepsTheSettleRule() {
        XCTAssertEqual(decide(.undetermined, .raw, Policy.settleTime, claudeHasForeground: nil), .offer)
    }

    func testANonInteractiveCommandLineStillDeclinesAtThePrompt() {
        XCTAssertEqual(decide(.nonInteractive, .raw, 5, claudeHasForeground: false), .decline)
    }

    func testNonInteractiveCommandLineDeclinesRightAway() {
        XCTAssertEqual(decide(.nonInteractive, .raw, 0), .decline)
        XCTAssertEqual(decide(.nonInteractive, .unknown, 100), .decline)
    }

    func testRawModeOffersOnlyAfterSettling() {
        XCTAssertEqual(decide(.undetermined, .raw, Policy.settleTime - 0.1),
                       .checkAgain(after: Policy.checkInterval))
        XCTAssertEqual(decide(.undetermined, .raw, Policy.settleTime), .offer)
    }

    func testCanonicalKeepsCheckingThenGivesUp() {
        XCTAssertEqual(decide(.undetermined, .canonical, Policy.fallbackDwellTime + 1),
                       .checkAgain(after: Policy.checkInterval))
        XCTAssertEqual(decide(.undetermined, .canonical, Policy.giveUpTime), .decline)
    }

    func testCanonicalThatTurnsRawIsOffered() {
        // A session that is slow to start reaches raw mode after a few canonical readings.
        XCTAssertEqual(decide(.undetermined, .canonical, 2), .checkAgain(after: Policy.checkInterval))
        XCTAssertEqual(decide(.undetermined, .raw, 2.5), .offer)
    }

    func testUnreadableTTYFallsBackToTheDwellTime() {
        XCTAssertEqual(decide(.undetermined, .unknown, Policy.fallbackDwellTime - 0.1),
                       .checkAgain(after: Policy.checkInterval))
        XCTAssertEqual(decide(.undetermined, .unknown, Policy.fallbackDwellTime), .offer)
    }

    func testSettleTimeIsLongerThanFramersPollInterval() {
        // framer reports tty mode changes from a one-second poll.
        XCTAssertGreaterThan(Policy.settleTime, 1)
        XCTAssertLessThan(Policy.settleTime, Policy.giveUpTime)
    }
}
