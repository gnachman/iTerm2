//
//  ShellIntegrationLiveHarness.swift
//  iTerm2
//
//  Live-shell regression baseline for the iTerm2 shell-integration scripts.
//  Each test spawns a real shell over a pseudo-tty, sources our shell
//  integration, runs a trivial command, and asserts on the OSC 133
//  semantic-prompt sequences observed in the pty output stream.
//
//  We scrape the raw byte stream rather than running it through a real
//  VT100Screen. The screen + token executor would be the obvious thing to
//  reuse, but a real shell session emits OSC 1337 (RemoteHost / CurrentDir)
//  *before* the first OSC 133;A. The existing screen state machine reaches
//  a short-circuit branch in promptDidStartAt: when that state-data arrives
//  before any prompt mark exists, and subsequent 133;A's don't create
//  marks. That interaction is real iTerm2 behavior, not a bug in this
//  harness; understanding and changing it is out of scope for this PR.
//  Counting OSC 133 occurrences in the raw stream is sufficient for the
//  baseline we want to lock in here, and keeps the harness footprint small.
//
//  Today's baseline (locked in here): exactly one OSC 133;A per primary
//  prompt, no `k=` attribute is present on any A, and a 133;D;<code>
//  arrives between command-start and the next prompt. When PR 3 lands
//  `k=s` continuation-prompt emission, the new-behavior tests will be added
//  in that PR.
//
//  Opt-in: every test self-skips unless tools/run_shell_integration_live.sh
//  has written a config file with PROJECT_ROOT.
//

import XCTest
@testable import iTerm2SharedARC

final class ShellIntegrationLiveHarness: XCTestCase {

    private static let configFileName = "iterm2-shell-integration-live.json"

    private static func configPath() -> String {
        return (NSTemporaryDirectory() as NSString).appendingPathComponent(configFileName)
    }

    private static func loadConfig() -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath())),
              let any = try? JSONSerialization.jsonObject(with: data),
              let json = any as? [String: String]
        else {
            return nil
        }
        return json
    }

    private static func projectRoot() -> String? {
        return loadConfig()?["PROJECT_ROOT"]
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.loadConfig() != nil,
                          "Shell-integration live harness is opt-in. Run tools/run_shell_integration_live.sh.")
    }

    // MARK: - Tests

    func testZsh_baseline_emitsOnePromptAPerCommand() throws {
        try runShellBaseline(.zsh)
    }

    /// The zsh integration wraps RPROMPT in OSC 133;P;k=r … B, so iTerm2 keeps
    /// the right prompt out of the recorded command.
    func testZsh_rightPrompt_isMarkedAndExcludedFromCommand() throws {
        let rightPrompt = "iterm2_right_prompt_token"
        guard let recorded = try runShellBaseline(.zsh,
                                                  beforeSourcing: "RPROMPT='\(rightPrompt)'\n") else {
            return
        }
        XCTAssertTrue(recorded.osc133Args(forKind: "P").contains { $0.split(separator: ";").contains("k=r") },
                      "[zsh] expected the right prompt to be marked with OSC 133;P;k=r")

        // Replay what the shell wrote through the real parser.
        let harness = TerminalTestHarness(width: LiveShell.columns, height: LiveShell.rows)
        harness.feedEscapeSequence(Array(recorded))
        harness.sync()
        let marks = harness.allScreenMarks().filter {
            $0.fullCommand == SupportedShell.zsh.testCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        XCTAssertEqual(marks.count, 1, "[zsh] expected one mark for the test command")
        XCTAssertEqual(marks.first?.excludedSubranges?.count, 1,
                       "[zsh] expected the right prompt's cells to be excluded")
    }

    /// A theme that rebuilds PS1 in a precmd hook makes the ^C path decorate
    /// the prompt again while RPROMPT and RPS2 still hold their wrapped values.
    /// Those must not be saved as the raw ones: commands must still see the
    /// user's own right prompts.
    func testZsh_ctrlCAfterThemeRebuildsPS1_keepsRawRightPrompts() throws {
        let output = try runZsh(beforeSourcing: [Self.bindSendBreak, "RPROMPT='%T'", "RPS2='r2'"],
                                steps: [.command("theme() { PS1=\"%~ $RANDOM %# \" }\n"),
                                        .command("precmd_functions+=(theme)\n"),
                                        .keys("abc"),
                                        .command(Self.sendBreak),
                                        .keys(Self.printValues("$RPROMPT|$RPS2"))])
        XCTAssertEqual(Self.printedValues(in: output), "%T|r2")
    }

    /// After ^C, a precmd hook that runs before ours changes RPROMPT and RPS2.
    /// The new RPS2 is the user's and must not be replaced by the one saved at
    /// the previous prompt.
    func testZsh_ctrlCAfterHookChangesRightPrompts_keepsNewRPS2() throws {
        let output = try runZsh(beforeSourcing: [Self.bindSendBreak,
                                                 "typeset -gi n=0",
                                                 "rp() { n=$((n+1)); RPROMPT=\"rp$n\"; RPS2=\"rps2_$n\" }",
                                                 "precmd_functions=(rp)"],
                                steps: [.command("true\n"),
                                        .keys("abc"),
                                        .command(Self.sendBreak),
                                        .keys(Self.printValues("$RPS2|$n"))])
        guard let printed = Self.printedValues(in: output) else {
            XCTFail("[zsh] values were not printed")
            return
        }
        let parts = printed.split(separator: "|", omittingEmptySubsequences: false)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.first.map(String.init), parts.last.map { "rps2_\($0)" })
    }

    /// An async theme sets RPROMPT from a zle callback after precmd. Running a
    /// command must not put back the value precmd saw.
    func testZsh_rightPromptSetAfterPrecmd_survivesPreexec() throws {
        let output = try runZsh(beforeSourcing: ["RPROMPT='sync_A'"],
                                // async_""B so that waiting for async_B matches the redrawn
                                // prompt, not the echoed definition.
                                steps: [.command("TRAPALRM() { RPROMPT=async_\"\"B; zle && zle reset-prompt; TMOUT=0 }\n"),
                                        .command("TMOUT=1\n"),
                                        .waitFor("async_B"),
                                        .keys(Self.printValues("$RPROMPT"))])
        XCTAssertEqual(Self.printedValues(in: output), "async_B")
    }

    /// A right prompt that already carries a 133;P mark (a theme that marks
    /// its own, like powerlevel10k's unreleased master in iTerm2 3.7+, or one
    /// added by hand) must not get a second, nested mark from the integration.
    func testZsh_alreadyMarkedRightPrompt_isNotMarkedAgain() throws {
        let output = try runZsh(beforeSourcing: ["RPROMPT=$'%{\\e]133;P;k=r\\a%}hand%{\\e]133;B\\a%}'"],
                                steps: [.command("echo hi\n")])
        let recorded = Data(output.utf8)
        let rightPromptMarks = recorded.osc133Args(forKind: "P").filter { $0.split(separator: ";").contains("k=r") }
        XCTAssertFalse(rightPromptMarks.isEmpty, "[zsh] the hand-added mark should be drawn")
        XCTAssertTrue(rightPromptMarks.allSatisfy { !$0.contains("aid=") },
                      "[zsh] the integration added its own mark: \(rightPromptMarks)")
    }

    func testBash_baseline_emitsOnePromptAPerCommand() throws {
        try runShellBaseline(.bash)
    }

    func testFish_baseline_emitsOnePromptAPerCommand() throws {
        try runShellBaseline(.fish)
    }

    func testTcsh_baseline_emitsOnePromptAPerCommand() throws {
        try runShellBaseline(.tcsh)
    }

    func testXonsh_baseline_emitsOnePromptAPerCommand() throws {
        // xonsh's prompt-toolkit sends CSI 6n (cursor-position-report) on
        // startup and waits for a response before running its main loop.
        // This harness doesn't speak back to the pty, so xonsh stalls before
        // it ever sources our integration. To exercise xonsh end-to-end the
        // harness would need to parse the byte stream for CSI 6n and emit a
        // synthetic CSI <row>;<col>R reply. That's strictly more
        // infrastructure than this PR is scoped for; tracking as a
        // follow-up.
        throw XCTSkip("xonsh needs synthetic CPR responses from the harness; see method comment")
    }

    func testNu_baseline_emitsOnePromptAPerCommand() throws {
        try runShellBaseline(.nu)
    }

    // MARK: - Implementation

    /// Aborting the line at the prompt makes zsh run precmd without preexec,
    /// which is what ^C does. A real ^C arrives as SIGINT, and the terminal
    /// flushes pending input when it does; depending on when it lands, zsh can
    /// lose the keys and never redraw. A key bound to send-break takes the same
    /// path as an ordinary character.
    private static let bindSendBreak = "bindkey '^X' send-break"
    private static let sendBreak = "\u{18}"

    private enum ZshStep {
        // Type text without waiting for anything.
        case keys(String)
        // Type text, then wait until zle is reading the next line.
        case command(String)
        // Wait until zsh has written `text`.
        case waitFor(String)
    }

    /// A command that prints `values` between [[ and ]]. The brackets are
    /// split in the typed text so the echoed command can't be mistaken for
    /// the output.
    private static func printValues(_ values: String) -> String {
        return "print -r -- \"[\"\"[\(values)]\"\"]\"\n"
    }

    /// What the command from printValues(_:) printed.
    private static func printedValues(in output: String) -> String? {
        guard let start = output.range(of: "[["),
              let end = output.range(of: "]]", range: start.upperBound..<output.endIndex) else {
            return nil
        }
        return String(output[start.upperBound..<end.lowerBound])
    }

    /// Runs zsh, sends `beforeSourcing`, sources the integration, performs
    /// `steps`, and returns everything zsh wrote once it has printed a
    /// sentinel after the last step. Throws XCTSkip when zsh or the project
    /// root is unavailable.
    private func runZsh(beforeSourcing: [String], steps: [ZshStep]) throws -> String {
        let shell = SupportedShell.zsh
        guard let executable = shell.executablePath() else {
            throw XCTSkip("zsh is not installed on this machine")
        }
        guard let projectRoot = Self.projectRoot() else {
            throw XCTSkip("PROJECT_ROOT not set; run via tools/run_shell_integration_live.sh")
        }
        let integrationPath = (projectRoot as NSString)
            .appendingPathComponent("Resources/shell_integration/\(shell.integrationFilename())")

        var env = ProcessInfo.processInfo.environment
        env["TERM_PROGRAM"] = "iTerm.app"
        env["LC_TERMINAL"] = "iTerm2"
        env["TERM"] = "xterm-256color"
        env.removeValue(forKey: "ITERM_SHELL_INTEGRATION_INSTALLED")

        let captured = NSMutableData()
        let lock = NSLock()
        let liveShell = try LiveShell(shellPath: executable,
                                      arguments: shell.arguments(for: executable),
                                      environment: env,
                                      onBytes: { bytes, length in
                                          lock.lock()
                                          captured.append(bytes, length: length)
                                          lock.unlock()
                                      })
        defer {
            liveShell.terminate()
        }
        func snapshot() -> Data {
            lock.lock(); defer { lock.unlock() }
            return captured as Data
        }
        for line in beforeSourcing {
            liveShell.send(line + "\n")
        }
        // zle writes this each time it starts reading a line. Our precmd sends
        // OSC 133;D early on, then runs subprocesses while it decorates the
        // prompt, so D alone doesn't mean zsh is ready: a ^C sent then would
        // interrupt precmd instead of the line editor. A theme may also
        // rebuild PS1 without our A mark, so A can't be relied on either.
        let zleReading = Data("\u{1B}[?2004h".utf8)
        func zleIsReading(afterFirst marker: Data, from offset: Int) -> Bool {
            let data = snapshot()
            guard let found = data.range(of: marker, in: offset..<data.count) else {
                return false
            }
            return data.range(of: zleReading, in: found.upperBound..<data.count) != nil
        }
        func waitForZle(afterFirst marker: Data, from offset: Int, _ description: String) throws {
            do {
                try liveShell.waitUntil(description, timeout: 8.0) {
                    zleIsReading(afterFirst: marker, from: offset)
                }
            } catch {
                print("[zsh] \(error); captured:\n" + snapshot().escapedForLog)
                throw error
            }
        }

        let sourced = snapshot().count
        liveShell.send(shell.sourceCommand(integrationPath: integrationPath))
        try waitForZle(afterFirst: Data("ShellIntegrationVersion=".utf8), from: sourced, "integration loaded")
        for step in steps {
            switch step {
            case .keys(let text):
                liveShell.send(text)
            case .command(let text):
                let sent = snapshot().count
                liveShell.send(text)
                // The next precmd reports with D, then zle starts reading.
                try waitForZle(afterFirst: Data("\u{1B}]133;D".utf8),
                               from: sent,
                               "zle reading after \(text.debugDescription)")
            case .waitFor(let text):
                try liveShell.waitUntil(text, timeout: 8.0) {
                    snapshot().contains(asciiString: text)
                }
            }
        }
        liveShell.send("print -r -- \"DONE_\"\"SENTINEL\"\n")
        try liveShell.waitUntil("sentinel", timeout: 8.0) {
            snapshot().contains(asciiString: "DONE_SENTINEL")
        }
        return String(decoding: snapshot(), as: UTF8.self)
    }

    private enum SupportedShell: String {
        case zsh, bash, fish, tcsh, xonsh, nu

        func executablePath() -> String? {
            let candidates: [String]
            switch self {
            case .zsh:   candidates = ["/bin/zsh", "/usr/local/bin/zsh", "/opt/homebrew/bin/zsh"]
            case .bash:  candidates = ["/bin/bash", "/usr/local/bin/bash", "/opt/homebrew/bin/bash"]
            case .fish:  candidates = ["/usr/local/bin/fish", "/opt/homebrew/bin/fish", "/usr/bin/fish"]
            case .tcsh:  candidates = ["/bin/tcsh", "/usr/bin/tcsh", "/usr/local/bin/tcsh"]
            case .xonsh: candidates = ["/usr/local/bin/xonsh", "/opt/homebrew/bin/xonsh", "/usr/bin/xonsh"]
            case .nu:    candidates = ["/opt/homebrew/bin/nu", "/usr/local/bin/nu", "/usr/bin/nu"]
            }
            return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        }

        func arguments(for executable: String) -> [String] {
            switch self {
            case .zsh:   return [executable, "-f", "-i"]
            case .bash:  return [executable, "--noprofile", "--norc", "-i"]
            case .fish:  return [executable, "-i", "-N"]
            case .tcsh:  return [executable, "-f", "-i"]
            case .xonsh: return [executable, "--no-rc", "-i"]
            case .nu:    return [executable, "--no-config-file", "--interactive"]
            }
        }

        // Shells that query the terminal on startup and wait for the answer
        // before they read any input: nushell's reedline asks for the cursor
        // position, and fish 4 for the device attributes.
        var waitsForTerminalQueryReplies: Bool {
            switch self {
            case .nu, .fish:
                return true
            case .zsh, .bash, .tcsh, .xonsh:
                return false
            }
        }

        // nushell emits the OSC 133 marks itself (the script only turns that
        // on), and reedline tags the primary prompt with k=i.
        var marksAreTheShellsOwn: Bool {
            switch self {
            case .nu:
                return true
            case .zsh, .bash, .fish, .tcsh, .xonsh:
                return false
            }
        }

        func integrationFilename() -> String {
            switch self {
            case .zsh:   return "iterm2_shell_integration.zsh"
            case .bash:  return "iterm2_shell_integration.bash"
            case .fish:  return "iterm2_shell_integration.fish"
            case .tcsh:  return "iterm2_shell_integration.tcsh"
            case .xonsh: return "iterm2_shell_integration.xonsh"
            case .nu:    return "iterm2_shell_integration.nu"
            }
        }

        func sourceCommand(integrationPath: String) -> String {
            switch self {
            case .zsh, .bash, .fish, .tcsh:
                return "source \(integrationPath)\n"
            case .xonsh:
                return "execx(open('\(integrationPath)').read())\n"
            case .nu:
                // source needs a parse-time constant path; a quoted literal is one.
                return "source '\(integrationPath)'\n"
            }
        }

        var testCommand: String { "echo iterm2_shell_test_token\n" }
    }

    /// Runs `shell` with the integration, sends one command, and checks the
    /// baseline OSC 133 traffic. `beforeSourcing` is sent to the shell before
    /// the integration is sourced. Returns everything the shell wrote, or nil
    /// if the integration file is missing.
    @discardableResult
    private func runShellBaseline(_ shell: SupportedShell, beforeSourcing: String? = nil) throws -> Data? {
        guard let executable = shell.executablePath() else {
            throw XCTSkip("\(shell.rawValue) is not installed on this machine")
        }
        guard let projectRoot = Self.projectRoot() else {
            throw XCTSkip("PROJECT_ROOT not set; run via tools/run_shell_integration_live.sh")
        }
        let integrationPath = (projectRoot as NSString)
            .appendingPathComponent("Resources/shell_integration/\(shell.integrationFilename())")
        guard FileManager.default.fileExists(atPath: integrationPath) else {
            XCTFail("Shell integration file not found at \(integrationPath)")
            return nil
        }

        var env = ProcessInfo.processInfo.environment
        env["TERM_PROGRAM"] = "iTerm.app"
        env["LC_TERMINAL"] = "iTerm2"
        env["TERM"] = "xterm-256color"
        env.removeValue(forKey: "ITERM_SHELL_INTEGRATION_INSTALLED")

        let capturedBytes = NSMutableData()
        let captureLock = NSLock()

        let liveShell = try LiveShell(
            shellPath: executable,
            arguments: shell.arguments(for: executable),
            environment: env,
            answersTerminalQueries: shell.waitsForTerminalQueryReplies,
            onBytes: { bytes, length in
                captureLock.lock()
                capturedBytes.append(bytes, length: length)
                captureLock.unlock()
            })

        let launchDate = Date()

        // Waits like LiveShell.waitUntil, but on a timeout records everything
        // the shell wrote so far, so a failure shows where the shell stalled.
        func waitUntil(_ description: String, timeout: TimeInterval, _ predicate: () -> Bool) throws {
            do {
                try liveShell.waitUntil(description, timeout: timeout, predicate)
            } catch {
                let snapshot: Data = {
                    captureLock.lock(); defer { captureLock.unlock() }
                    return capturedBytes as Data
                }()
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(launchDate))
                let dump = "[\(shell.rawValue)] \(error) after \(elapsed)s; captured \(snapshot.count) bytes:\n"
                    + snapshot.escapedForLog
                print(dump)
                let attachment = XCTAttachment(string: dump)
                attachment.name = "\(shell.rawValue) capture at timeout"
                attachment.lifetime = .keepAlways
                add(attachment)
                throw error
            }
        }

        if let beforeSourcing {
            liveShell.send(beforeSourcing)
        }
        liveShell.send(shell.sourceCommand(integrationPath: integrationPath))

        // Wait for the integration's ShellIntegrationVersion announcement
        // (OSC 1337) which the script prints right after sourcing.
        try waitUntil("integration loaded", timeout: 8.0) {
            captureLock.lock(); defer { captureLock.unlock() }
            return capturedBytes.contains(asciiString: "ShellIntegrationVersion=")
        }
        let afterSourceByteCount = { () -> Int in
            captureLock.lock(); defer { captureLock.unlock() }
            return capturedBytes.length
        }()

        liveShell.send(shell.testCommand)

        // Wait for D;<code> *after* command start and a fresh A (the
        // post-command prompt). We count occurrences in the suffix after
        // the source-complete point.
        try waitUntil("post-command D and A", timeout: 8.0) {
            captureLock.lock(); defer { captureLock.unlock() }
            let snapshot = capturedBytes as Data
            let suffix = snapshot.subdata(in: afterSourceByteCount..<snapshot.count)
            return suffix.contains(osc133Kind: "D") && suffix.contains(osc133Kind: "A")
        }

        liveShell.terminate()

        // ------------------------------------------------------------------
        // Baseline assertions
        // ------------------------------------------------------------------

        let recorded = capturedBytes as Data

        // (a) Integration loaded.
        XCTAssertTrue(recorded.contains(asciiString: "ShellIntegrationVersion="),
                      "[\(shell.rawValue)] integration did not announce its version")

        // (b) At least one prompt-start (133;A) and one command-end (133;D)
        // were emitted. We don't pin an exact count here because each shell
        // has different startup churn (zsh might prefix with an extra D
        // from the initial precmd hook, bash may not, etc.); we just want
        // to lock in that the integration is producing OSC 133 traffic.
        let aOccurrences = recorded.osc133Args(forKind: "A")
        let dOccurrences = recorded.osc133Args(forKind: "D")
        XCTAssertGreaterThanOrEqual(aOccurrences.count, 1,
                                    "[\(shell.rawValue)] expected at least one OSC 133;A")
        XCTAssertGreaterThanOrEqual(dOccurrences.count, 1,
                                    "[\(shell.rawValue)] expected at least one OSC 133;D")

        // (c) None of today's A markers carry a `k=` attribute. PR 3 will
        // introduce `k=s` on PS2 lines for zsh/bash; that will rewrite this
        // assertion shell-by-shell. A shell that emits its own marks may tag
        // the primary prompt as initial (k=i); nothing else is expected.
        for args in aOccurrences {
            let kinds = args.split(separator: ";").filter { $0.hasPrefix("k=") }
            if shell.marksAreTheShellsOwn {
                XCTAssertTrue(kinds.allSatisfy { $0 == "k=i" },
                              "[\(shell.rawValue)] OSC 133;A carries an unexpected `k=` in args '\(args)'")
            } else {
                XCTAssertTrue(kinds.isEmpty,
                              "[\(shell.rawValue)] OSC 133;A unexpectedly carries `k=` in args '\(args)'")
            }
        }

        // (d) D arguments parse as digits (return codes), or are empty.
        // Defensive: locks in that we're not emitting malformed D sequences.
        for args in dOccurrences {
            let value = args.split(separator: ";").first.map(String.init) ?? ""
            if !value.isEmpty {
                XCTAssertNotNil(Int(value),
                                "[\(shell.rawValue)] OSC 133;D arg '\(args)' should start with a numeric return code")
            }
        }
        return recorded
    }
}

// MARK: - OSC 133 byte-scanning helpers

private extension Data {
    /// The bytes as printable ASCII: ESC as \e, backslash, other control and
    /// non-ASCII bytes as \xNN, and newlines kept so the dump reads like the
    /// screen.
    var escapedForLog: String {
        var result = ""
        for byte in self {
            switch byte {
            case 0x1B:
                result += "\\e"
            case 0x0A:
                result += "\\n\n"
            case 0x20..<0x7F where byte != 0x5C:
                result.append(Character(UnicodeScalar(byte)))
            default:
                result += String(format: "\\x%02X", byte)
            }
        }
        return result
    }

    func contains(asciiString s: String) -> Bool {
        guard let needle = s.data(using: .ascii) else { return false }
        return range(of: needle) != nil
    }

    /// True if this data contains an `ESC ] 133 ; <kind>` opening sequence.
    /// Doesn't validate the terminator — just detects the kind prefix.
    func contains(osc133Kind kind: String) -> Bool {
        return !osc133Args(forKind: kind).isEmpty
    }

    /// Find every `ESC ] 133 ; <kind>[...args...] <terminator>` and return
    /// each match's argument string (between the kind character and the
    /// terminator). `<terminator>` is BEL (0x07) or ESC \.
    func osc133Args(forKind kind: String) -> [String] {
        var results: [String] = []
        let bytes = [UInt8](self)
        let prefix: [UInt8] = [0x1B, 0x5D, 0x31, 0x33, 0x33, 0x3B] + Array(kind.utf8)
        var i = 0
        while i + prefix.count <= bytes.count {
            var matched = true
            for j in 0..<prefix.count {
                if bytes[i + j] != prefix[j] { matched = false; break }
            }
            if !matched {
                i += 1
                continue
            }
            // Found the prefix. Scan until BEL or ESC.
            var end = i + prefix.count
            while end < bytes.count {
                let b = bytes[end]
                if b == 0x07 || b == 0x1B { break }
                end += 1
            }
            let argBytes = Array(bytes[(i + prefix.count)..<end])
            if let s = String(bytes: argBytes, encoding: .ascii) {
                results.append(s)
            }
            i = end
        }
        return results
    }
}

private extension NSMutableData {
    func contains(asciiString s: String) -> Bool {
        return (self as Data).contains(asciiString: s)
    }
}
