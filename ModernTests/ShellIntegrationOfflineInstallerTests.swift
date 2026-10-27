//
//  ShellIntegrationOfflineInstallerTests.swift
//  ModernTests
//
//  Exercises the “Internet-Free” (send shell commands) shell integration installer's
//  discovery step and Skip button without a real terminal. A fake terminal plays the role of
//  the session: it syncs the main-thread (dry) iTermExpect into a wet copy the way
//  PTYSession does, and answers each command the installer types with the output a shell
//  would print, matching it against the wet copy that is current at that moment.
//

import XCTest
@testable import iTerm2SharedARC

// Part of the command with which the helper sh reads the utilities archive. The fakes' sh
// answers it with it2-receiving-utilities, reads lines until one that is just EOF, and then
// prints whether the archive extracted.
private let receiveUtilitiesCommandMarker = "echo it2-\"\"receiving-utilities"

// Part of the command with which the helper sh receives the shell integration script. The fakes'
// sh answers it with it2-receiving-script (or it2-cannot-receive-script when the file's folder
// doesn't exist), reads lines until one that is just EOF, and writes the decoded script only if
// its checksum is the one in the command, as the real command does.
private let receiveScriptCommandMarker = "echo it2-\"\"receiving-script"

// A typed line as the shell reads it: Control-U (the tty's kill character, and the line editors'
// default binding for it) erases what was typed on the line before it.
private func erasingKilledText(_ line: String) -> String {
    guard let kill = line.lastIndex(of: "\u{15}") else {
        return line
    }
    return String(line[line.index(after: kill)...])
}

// What the helper launch prints, with no newline, right before the helper's first prompt.
private let helpersReadyMarker = "it2-helpers-ready "

// The path, as typed, that the installer's command to receive the script writes to.
private func fakeReceiveScriptPath(_ command: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: "^IT2_F=(.+?); "),
          let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
          let range = Range(match.range(at: 1), in: command) else {
        return nil
    }
    return String(command[range])
}

// What the command to receive the script writes, given the lines it read, or nil if what it read
// isn't the script the command expects, so it writes nothing.
private func fakeReceivedScript(_ command: String, lines: [String]) -> String? {
    guard let regex = try? NSRegularExpression(pattern: "\\$1 \\$2\" = '([0-9]+ [0-9]+)'"),
          let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
          let range = Range(match.range(at: 1), in: command),
          let data = Data(base64Encoded: lines.joined(), options: []),
          iTermShellIntegrationWindowController.posixChecksum(of: data) == command[range] else {
        return nil
    }
    return String(decoding: data, as: UTF8.self)
}

// What sh prints for the installer's `cd folder && echo done || echo failed` line, or nil if the
// line isn't one.
private func fakeConditionalEchoAnswer(_ line: String, fails: Bool) -> String? {
    guard let and = line.range(of: " && echo "),
          let or = line.range(of: " || echo ", range: and.upperBound..<line.endIndex) else {
        return nil
    }
    let answer = fails ? line[or.upperBound...] : line[and.upperBound..<or.lowerBound]
    return answer.replacingOccurrences(of: "\"", with: "")
}

// The length in bytes of the longest line in texts.
private func longestTypedLine(_ texts: [String]) -> Int {
    return texts.joined().components(separatedBy: "\n").map { $0.utf8.count }.max() ?? 0
}

private class FakeShellIntegrationTerminal: NSObject, iTermShellIntegrationWindowControllerDelegate {
    let dryExpect = iTermExpect(dry: true)
    private var wetExpect: iTermExpect?
    private(set) var sentTexts = [String]()
    private var unansweredTexts = [String]()
    private let testCase: XCTestCase
    // Maps a command the installer types to the line the shell prints in response.
    var responses = [String: String]()
    // Like responses, for a command answered with several lines. A line may also stand for
    // part of a line that has arrived so far, since partial lines are matched too.
    var responseLines = [String: [String]]()
    // Things that happen only after the shell has dealt with everything typed so far, such as a
    // newly launched shell printing its first prompt.
    var laterEvents = [() -> Void]()
    // When set, a match completes the installer's expectation (running its completion) only
    // after the callback that types the next command has run, as can happen in the app, where
    // the completion goes through the token executor's side effects. Otherwise it completes
    // right away.
    var defersMatchCompletions = false
    private var deferredMatchCompletions = [() -> Void]()

    init(testCase: XCTestCase) {
        self.testCase = testCase
    }

    func shellIntegrationWindowControllerSendText(_ text: String) {
        sentTexts.append(text)
        unansweredTexts.append(text)
    }

    // How many times the installer asked to stop typing what it sent.
    private(set) var stopSendingTextCount = 0

    func shellIntegrationWindowControllerStopSendingText() {
        stopSendingTextCount += 1
    }

    func shellIntegrationExpect() -> iTermExpect {
        return dryExpect
    }

    // Copy the dry expect to a wet one, as PTYSession does on a sync. Adding an expectation to
    // the wet copy dispatches its willExpect (which types the command) to the main queue, so
    // drain the main queue afterwards.
    private func sync() {
        if dryExpect.dirty {
            dryExpect.resetDirty()
            wetExpect = (dryExpect.copy() as! iTermExpect)
        }
        let drained = XCTestExpectation(description: "Main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        testCase.wait(for: [drained], timeout: 10)
        let completions = deferredMatchCompletions
        deferredMatchCompletions.removeAll()
        for completion in completions {
            completion()
        }
    }

    // The lines the shell prints in response to typed text.
    func respond(to text: String) -> [String] {
        if let lines = responseLines[text] {
            return lines
        }
        if let response = responses[text] {
            return [response]
        }
        return []
    }

    // The shell prints a line. The mutation thread checks it against the current wet copy.
    func output(_ line: String) {
        guard let wetExpect else {
            return
        }
        for expectation in wetExpect.expectations {
            guard let captures = Self.captures(of: expectation.regex, in: line) else {
                continue
            }
            expectation.didMatch(withCaptureGroups: captures) { [weak self] closure in
                guard let self, self.defersMatchCompletions else {
                    closure()
                    return
                }
                self.deferredMatchCompletions.append(closure)
            }
        }
    }

    private static func captures(of pattern: String, in line: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { i in
            let range = match.range(at: i)
            guard range.location != NSNotFound, let r = Range(range, in: line) else {
                return ""
            }
            return String(line[r])
        }
    }

    // Alternate syncs and shell output until the installer stops typing. Output for a command
    // is processed as soon as it is typed, before the next sync, which is the order a fast
    // shell produces in practice.
    func run() {
        for _ in 0..<50 {
            sync()
            if !unansweredTexts.isEmpty {
                while !unansweredTexts.isEmpty {
                    let text = unansweredTexts.removeFirst()
                    for line in respond(to: text) {
                        output(line)
                    }
                }
            } else if !laterEvents.isEmpty {
                laterEvents.removeFirst()()
            } else if dryExpect.dirty {
                // A deferred completion added an expectation, whose text the next sync types.
                continue
            } else {
                return
            }
        }
        XCTFail("Installer kept typing commands")
    }
}

// Plays nushell with the POSIX sh the installer starts from it. Like nushell's reedline, it
// reads typeahead in bulk: text typed after `sh -c '…'` but before that sh prints its first
// prompt is lost to nushell (recorded in textLostToNushell). The sh understands the few
// commands the installer types, echoes each typed line after its prompt, and keeps the files it
// writes in `files`.
private final class FakeNushellTerminal: FakeShellIntegrationTerminal {
    static let nuPath = "/opt/homebrew/bin/nu"
    static let autoloadDir = "/Users/someone/Library/Application Support/nushell/autoload"
    static let scriptPath = autoloadDir + "/iterm2_shell_integration.nu"

    private enum State {
        case nushell
        case helperStarting
        case helper
    }
    private var state = State.nushell
    private var helperDepth = 0
    private var pendingInput = ""
    // Set while sh reads a heredoc: where it goes (nil for a pipe) and what was read so far.
    private var heredoc: (path: String?, lines: [String])?
    private var lastStatus: Int32 = 0
    private var autoloadDirVariable = ""
    // The command receiving the script, while sh reads it.
    private var receiveScriptCommand: String?

    // The value of $SHELL in the session, which need not be nu.
    var shellVariable = FakeNushellTerminal.nuPath
    var canCreateAutoloadDir = true
    var helperStarts = true
    private(set) var createdDirectories = Set<String>()
    private(set) var files = [String: String]()
    private(set) var textLostToNushell = [String]()

    var helperIsRunning: Bool {
        return state != .nushell
    }

    override func respond(to text: String) -> [String] {
        if state == .helperStarting {
            textLostToNushell.append(text)
            return []
        }
        pendingInput += text
        var result = [String]()
        while let newline = pendingInput.firstIndex(of: "\n") {
            let line = erasingKilledText(String(pendingInput[..<newline]))
            pendingInput = String(pendingInput[pendingInput.index(after: newline)...])
            result.append(contentsOf: handle(line))
            if state == .helperStarting {
                // nushell reads whatever else was typed ahead along with this line.
                if !pendingInput.isEmpty {
                    textLostToNushell.append(pendingInput)
                    pendingInput = ""
                }
                break
            }
        }
        return result
    }

    private func handle(_ line: String) -> [String] {
        switch state {
        case .nushell:
            return handleInNushell(line)
        case .helper:
            return handleInHelper(line)
        case .helperStarting:
            return []
        }
    }

    private func handleInNushell(_ line: String) -> [String] {
        let echo = "~> " + line
        if line == ShellIntegrationOfflineInstallerTests.shellCommand.trimmingCharacters(in: .newlines) {
            return [echo, "My shell is nu \(Self.nuPath) or \(shellVariable), end", "~> "]
        }
        if line == ShellIntegrationOfflineInstallerTests.helperLaunchLine {
            state = .helperStarting
            guard helperStarts else {
                return [echo]
            }
            laterEvents.append { [weak self] in
                guard let self else {
                    return
                }
                self.state = .helper
                self.helperDepth = 1
                self.output(">> ")
            }
            return [echo]
        }
        return [echo, "Error: nu::shell::external_command", "~> "]
    }

    private func expand(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\"$IT2_NU_AUTOLOAD_DIR", with: "\"" + autoloadDirVariable)
            .replacingOccurrences(of: "\"", with: "")
    }

    private func makeAutoloadDir() -> [String] {
        guard canCreateAutoloadDir, !autoloadDirVariable.isEmpty else {
            lastStatus = 1
            return ["mkdir: \(autoloadDirVariable): Permission denied"]
        }
        createdDirectories.insert(autoloadDirVariable)
        lastStatus = 0
        return []
    }

    private func handleInHelper(_ line: String) -> [String] {
        if var heredoc {
            let echo = (heredoc.path == nil ? "" : "> ") + line
            if line != "EOF" {
                heredoc.lines.append(line)
                self.heredoc = heredoc
                return [echo, heredoc.path == nil ? "" : "> "]
            }
            self.heredoc = nil
            guard let path = heredoc.path else {
                if let command = receiveScriptCommand {
                    receiveScriptCommand = nil
                    guard let path = fakeReceiveScriptPath(command).map(expand),
                          let contents = fakeReceivedScript(command, lines: heredoc.lines) else {
                        return [line, "it2-script-failed", ">> "]
                    }
                    files[path] = contents
                    return [line, "it2-script-written", ">> "]
                }
                // The utilities archive was received.
                lastStatus = 0
                return [line, "it2-utilities-installed", ">> "]
            }
            let directory = (path as NSString).deletingLastPathComponent
            guard createdDirectories.contains(directory) else {
                lastStatus = 1
                return [echo, "sh: \(path): No such file or directory", ">> "]
            }
            files[path] = heredoc.lines.joined(separator: "\n") + "\n"
            lastStatus = 0
            return [echo, ">> "]
        }

        var result = [">> " + line]
        let prompt: String
        if line.hasPrefix("IT2_NU_AUTOLOAD_DIR=$(") {
            // Asking $SHELL only works when $SHELL is nu; command -v finds nu in PATH.
            let asksSHELL = line.hasPrefix("IT2_NU_AUTOLOAD_DIR=$(\"$SHELL\" --no-config-file")
            let findsNu = line.contains("command -v nu")
            let found = asksSHELL ? shellVariable == Self.nuPath : findsNu
            autoloadDirVariable = found ? Self.autoloadDir : ""
            if line.contains("mkdir -p \"$IT2_NU_AUTOLOAD_DIR\"") {
                result.append(contentsOf: makeAutoloadDir())
            }
            if line.contains("echo iTerm2-nu-autoload-dir-\"\"ready") {
                result.append("iTerm2-nu-autoload-dir-ready")
            }
            prompt = ">> "
        } else if line.hasPrefix("mkdir -p \"$IT2_NU_AUTOLOAD_DIR\"") {
            result.append(contentsOf: makeAutoloadDir())
            prompt = ">> "
        } else if line.hasPrefix("cat <<'EOF' > ") {
            heredoc = (path: expand(String(line.dropFirst("cat <<'EOF' > ".count))), lines: [])
            prompt = "> "
        } else if line.contains(receiveUtilitiesCommandMarker) {
            // sh reads the archive from the tty with its line editor off, so there is no prompt.
            result.append("it2-receiving-utilities")
            heredoc = (path: nil, lines: [])
            prompt = ""
        } else if line.contains(receiveScriptCommandMarker) {
            let path = fakeReceiveScriptPath(line).map(expand) ?? ""
            if createdDirectories.contains((path as NSString).deletingLastPathComponent) {
                result.append("it2-receiving-script")
                heredoc = (path: nil, lines: [])
                receiveScriptCommand = line
                prompt = ""
            } else {
                result.append("sh: \(path).it2-b64: No such file or directory")
                result.append("it2-cannot-receive-script")
                prompt = ">> "
            }
        } else if line.hasPrefix("chmod +x ") {
            let path = expand(String(line.dropFirst("chmod +x ".count)))
            if files[path] == nil {
                result.append("chmod: \(path): No such file or directory")
            }
            prompt = ">> "
        } else if line.hasPrefix("cd "), let answer = fakeConditionalEchoAnswer(line, fails: false) {
            result.append(answer)
            prompt = ">> "
        } else if line.hasPrefix("mkdir "), let range = line.range(of: "; echo ") {
            result.append(line[range.upperBound...].replacingOccurrences(of: "\"", with: ""))
            prompt = ">> "
        } else if line == ShellIntegrationOfflineInstallerTests.helperLaunchLine {
            // A nested sh reads the typeahead a byte at a time, so it starts without losing any.
            helperDepth += 1
            prompt = ">> "
        } else if line == "exit" {
            helperDepth -= 1
            if helperDepth == 0 {
                state = .nushell
                prompt = "~> "
            } else {
                prompt = ">> "
            }
        } else if line.isEmpty {
            prompt = ">> "
        } else {
            result.append("sh: \(line): command not found")
            prompt = ">> "
        }
        result.append(prompt)
        return result
    }
}

// Plays xonsh with the POSIX sh the installer starts from it. xonsh's line editor
// (prompt_toolkit) reads typeahead in bulk, like nushell's: text typed after `sh -c '…'` but
// before that sh prints its first prompt is kept by xonsh (recorded in textLostToXonsh) instead
// of reaching sh. prompt_toolkit also breaks a long command line with hard newlines when it
// echoes it, so a row of the echo can start with what looks like the helper's prompt.
private final class FakeXonshTerminal: FakeShellIntegrationTerminal {
    static let xonshPrompt = "user@host ~ @ "
    static let scriptPath = "~/.config/xonsh/rc.d/iterm2.xsh"

    private enum State {
        case xonsh
        case helperStarting
        case helper
    }
    private var state = State.xonsh
    private var helperDepth = 0
    private var pendingInput = ""
    private var heredoc: (path: String?, lines: [String])?
    // The command receiving the script, while sh reads it.
    private var receiveScriptCommand: String?

    private(set) var createdDirectories = Set<String>()
    private(set) var files = [String: String]()
    private(set) var textLostToXonsh = [String]()

    var helperIsRunning: Bool {
        return state != .xonsh
    }

    override func respond(to text: String) -> [String] {
        if state == .helperStarting {
            textLostToXonsh.append(text)
            return []
        }
        pendingInput += text
        var result = [String]()
        while let newline = pendingInput.firstIndex(of: "\n") {
            let line = erasingKilledText(String(pendingInput[..<newline]))
            pendingInput = String(pendingInput[pendingInput.index(after: newline)...])
            result.append(contentsOf: handle(line))
            if state == .helperStarting {
                if !pendingInput.isEmpty {
                    textLostToXonsh.append(pendingInput)
                    pendingInput = ""
                }
                break
            }
        }
        return result
    }

    private func handle(_ line: String) -> [String] {
        switch state {
        case .xonsh:
            return handleInXonsh(line)
        case .helper:
            return handleInHelper(line)
        case .helperStarting:
            return []
        }
    }

    private func handleInXonsh(_ line: String) -> [String] {
        if line == ShellIntegrationOfflineInstallerTests.helperLaunchLine {
            state = .helperStarting
            laterEvents.append { [weak self] in
                guard let self else {
                    return
                }
                self.state = .helper
                self.helperDepth = 1
                self.output(">> ")
            }
            // The echo, broken by the line editor right before the prompt in PS1=">> ".
            let echo = Self.xonshPrompt + line
            guard let range = echo.range(of: ">> \"") else {
                return [echo]
            }
            return [String(echo[..<range.lowerBound]), String(echo[range.lowerBound...])]
        }
        // The discovery command is answered from responses.
        let answer = super.respond(to: line + "\n")
        if !answer.isEmpty {
            return [Self.xonshPrompt + line] + answer + [Self.xonshPrompt]
        }
        return [Self.xonshPrompt + line, "xonsh: command not found: \(line)", Self.xonshPrompt]
    }

    private func handleInHelper(_ line: String) -> [String] {
        if var heredoc {
            let echo = (heredoc.path == nil ? "" : "> ") + line
            if line != "EOF" {
                heredoc.lines.append(line)
                self.heredoc = heredoc
                return [echo, heredoc.path == nil ? "" : "> "]
            }
            self.heredoc = nil
            guard let path = heredoc.path else {
                if let command = receiveScriptCommand {
                    receiveScriptCommand = nil
                    guard let path = fakeReceiveScriptPath(command),
                          let contents = fakeReceivedScript(command, lines: heredoc.lines) else {
                        return [line, "it2-script-failed", ">> "]
                    }
                    files[path] = contents
                    return [line, "it2-script-written", ">> "]
                }
                // The utilities archive was received.
                return [line, "it2-utilities-installed", ">> "]
            }
            let directory = (path as NSString).deletingLastPathComponent
            guard createdDirectories.contains(directory) else {
                return [echo, "sh: \(path): No such file or directory", ">> "]
            }
            files[path] = heredoc.lines.joined(separator: "\n") + "\n"
            return [echo, ">> "]
        }

        var result = [">> " + line]
        var prompt = ">> "
        if line.hasPrefix("mkdir -p ") {
            createdDirectories.insert(String(line.dropFirst("mkdir -p ".count)))
        } else if line.hasPrefix("cat <<'EOF' > ") {
            heredoc = (path: String(line.dropFirst("cat <<'EOF' > ".count)), lines: [])
            prompt = "> "
        } else if line.contains(receiveUtilitiesCommandMarker) {
            // sh reads the archive from the tty with its line editor off, so there is no prompt.
            result.append("it2-receiving-utilities")
            heredoc = (path: nil, lines: [])
            prompt = ""
        } else if line.contains(receiveScriptCommandMarker) {
            let path = fakeReceiveScriptPath(line) ?? ""
            if createdDirectories.contains((path as NSString).deletingLastPathComponent) {
                result.append("it2-receiving-script")
                heredoc = (path: nil, lines: [])
                receiveScriptCommand = line
                prompt = ""
            } else {
                result.append("sh: \(path).it2-b64: No such file or directory")
                result.append("it2-cannot-receive-script")
            }
        } else if line.hasPrefix("chmod +x ") {
            let path = String(line.dropFirst("chmod +x ".count))
            if files[path] == nil {
                result.append("chmod: \(path): No such file or directory")
            }
        } else if line.hasPrefix("cd "), let answer = fakeConditionalEchoAnswer(line, fails: false) {
            result.append(answer)
        } else if line.hasPrefix("mkdir "), let range = line.range(of: "; echo ") {
            result.append(line[range.upperBound...].replacingOccurrences(of: "\"", with: ""))
        } else if line.hasPrefix("echo ") {
            result.append(line.dropFirst("echo ".count).replacingOccurrences(of: "\"", with: ""))
        } else if line == ShellIntegrationOfflineInstallerTests.helperLaunchLine {
            // A nested sh reads the typeahead a byte at a time, so it starts without losing any.
            helperDepth += 1
        } else if line == "exit" {
            helperDepth -= 1
            if helperDepth == 0 {
                state = .xonsh
                prompt = Self.xonshPrompt
            }
        } else if !line.isEmpty {
            result.append("sh: \(line): command not found")
        }
        result.append(prompt)
        return result
    }
}

final class ShellIntegrationOfflineInstallerTests: XCTestCase {
    static let shellCommand = "sh -c 'echo My shell is $(ps -o ucomm=,comm= -p $PPID 2>/dev/null || ps -o comm= -p $PPID 2>/dev/null) or $SHELL, ${IT2_INSTALLER_HELPER:+in an installer helper shell, }end'\n"
    // The line that starts the helper sh, without its newline. It prints the ready marker right
    // before the helper's first prompt.
    static let helperLaunchLine = "sh -c 'printf \"it2-\"\"helpers-ready \"; exec env ENV=/dev/null INPUTRC=/dev/null IT2_INSTALLER_HELPER=$((${IT2_INSTALLER_HELPER:-0}+1)) PS1=\">> \" PS2=\"> \" sh'"
    static let launchHelper = helperLaunchLine + "\n"
    // The exit typed to end the helper, after Control-U erases what the user may have typed on
    // its line (F-883). What the installer shows for pasting by hand has no Control-U.
    static let typedExit = "\u{15}exit\n"
    // Asks the shell that printed a helper prompt after Cancel how many helpers deep it is.
    static let helperDepthCommand = "echo \"it2-\"\"helper-depth-${IT2_INSTALLER_HELPER:-0}-\"\n"
    private static let zshDotdirCommand = "echo My dotfiles go in ${ZDOTDIR:-$HOME}, end\n"

    private var controller: iTermShellIntegrationWindowController!
    private var terminal: FakeShellIntegrationTerminal!

    override func setUp() {
        super.setUp()
        terminal = FakeShellIntegrationTerminal(testCase: self)
        controller = iTermShellIntegrationWindowController(windowNibName: "iTermShellIntegrationWindowController")
        controller.delegate = terminal
        XCTAssertNotNil(controller.window)
        // Choose the Internet-Free install, which shows the send-shell-commands page at stage 0.
        controller.shellIntegrationInstallerSendShellCommands(-1)
        XCTAssertEqual(controller.sendShellCommandsStage, 0)
    }

    override func tearDown() {
        controller.shellIntegrationInstallerCancelExpectations()
        controller.window?.orderOut(nil)
        controller = nil
        terminal = nil
        super.tearDown()
    }

    // parentProcess is what ps prints for the shell the commands are typed into, its executable
    // name (ucomm) followed by its argv[0] (comm): by default the same shell as $SHELL, as a
    // login shell.
    private func discover(shellPath: String, parentProcess: String? = nil, dotdirOutput: String?) {
        let name = (shellPath as NSString).lastPathComponent
        let parentProcess = parentProcess ?? name + " -" + name
        terminal.responses[Self.shellCommand] = "My shell is \(parentProcess) or \(shellPath), end"
        if let dotdirOutput {
            terminal.responses[Self.zshDotdirCommand] = dotdirOutput
        }
        controller.shellIntegrationInstallerSendShellCommands(0)
        terminal.run()
    }

    func testZshDiscoveryCompletesWithoutZDOTDIR() {
        discover(shellPath: "/bin/zsh", dotdirOutput: "My dotfiles go in /Users/someone, end")

        XCTAssertEqual(terminal.sentTexts, [Self.shellCommand, Self.zshDotdirCommand])
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .zsh)
        XCTAssertEqual(controller.dotdir, "/Users/someone")
    }

    func testZshDiscoveryCompletesWithZDOTDIR() {
        discover(shellPath: "/usr/local/bin/zsh", dotdirOutput: "My dotfiles go in /Users/someone/.config/zsh, end")

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .zsh)
        XCTAssertEqual(controller.dotdir, "/Users/someone/.config/zsh")
        let next = controller.shellIntegrationInstallerNextCommandForSendShellCommands() ?? ""
        XCTAssertTrue(next.contains("/Users/someone/.config/zsh/.iterm2_shell_integration.zsh"), next)
    }

    func testZshDiscoveryWithEmptyDotdirFallsBackToHome() {
        discover(shellPath: "/bin/zsh", dotdirOutput: "My dotfiles go in, end")

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .zsh)
        XCTAssertEqual(controller.dotdir, "$HOME")
        let next = controller.shellIntegrationInstallerNextCommandForSendShellCommands() ?? ""
        XCTAssertTrue(next.contains("$HOME/.iterm2_shell_integration.zsh"), next)
        XCTAssertFalse(next.contains("(null)"), next)
    }

    // F-325: on a slow link “My dotfiles go in” can arrive before the path. That partial line
    // must not be read as an empty ZDOTDIR, which would fall back to $HOME.
    func testZshDiscoveryIgnoresAPartialDotdirLine() {
        terminal.responses[Self.shellCommand] = "My shell is zsh -zsh or /bin/zsh, end"
        terminal.responseLines[Self.zshDotdirCommand] = [
            "My dotfiles go in",
            "My dotfiles go in /Users/qa/qa-zd",
            "My dotfiles go in /Users/qa/qa-zdot, end"
        ]
        controller.shellIntegrationInstallerSendShellCommands(0)
        terminal.run()

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .zsh)
        XCTAssertEqual(controller.dotdir, "/Users/qa/qa-zdot")
    }

    func testBashDiscoveryCompletes() {
        discover(shellPath: "/bin/bash", dotdirOutput: nil)

        XCTAssertEqual(terminal.sentTexts, [Self.shellCommand])
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .bash)
        XCTAssertEqual(controller.dotdir, "~")
    }

    // F-260: tcsh started from a zsh login shell. The commands are typed into tcsh, so the
    // installer must target tcsh and must not type zsh-only syntax.
    func testDiscoveryUsesTheShellReadingTheCommandsOverSHELL() {
        discover(shellPath: "/bin/zsh", parentProcess: "tcsh /bin/tcsh", dotdirOutput: nil)

        XCTAssertEqual(terminal.sentTexts, [Self.shellCommand])
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .tcsh)
        XCTAssertEqual(controller.dotdir, "~")
    }

    // F-451: tcsh overwrites the first character of its argv[0] with “-”, so comm is “-csh” for
    // a tcsh started as `tcsh`. The executable name (ucomm) is still tcsh.
    func testDiscoveryUsesTheExecutableNameOfATcshParent() {
        discover(shellPath: "/bin/zsh", parentProcess: "tcsh -csh", dotdirOutput: nil)

        XCTAssertEqual(terminal.sentTexts, [Self.shellCommand])
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .tcsh)
        XCTAssertEqual(controller.dotdir, "~")
    }

    // F-451: started as `/bin/tcsh`, comm is “-bin/tcsh”.
    func testDiscoveryUsesTheExecutableNameOfATcshParentStartedByPath() {
        discover(shellPath: "/bin/zsh", parentProcess: "tcsh -bin/tcsh", dotdirOutput: nil)

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .tcsh)
    }

    // F-451: macOS /bin/csh is tcsh. Started as `csh`, its comm is “-sh”, but its executable
    // name is csh.
    func testDiscoveryTreatsACshParentAsTcsh() {
        discover(shellPath: "/bin/zsh", parentProcess: "csh -sh", dotdirOutput: nil)

        XCTAssertEqual(terminal.sentTexts, [Self.shellCommand])
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .tcsh)
        XCTAssertEqual(controller.dotdir, "~")
    }

    // A ps without ucomm (busybox, say) falls back to printing comm alone.
    func testDiscoveryUsesCommAloneWhenUcommIsUnavailable() {
        discover(shellPath: "/bin/bash", parentProcess: "-csh", dotdirOutput: nil)

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .tcsh)
    }

    func testDiscoveryUsesALoginShellParent() {
        discover(shellPath: "/bin/zsh", parentProcess: "fish -fish", dotdirOutput: nil)

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .fish)
    }

    func testDiscoveryUsesABashParent() {
        discover(shellPath: "/bin/zsh", parentProcess: "bash -bash", dotdirOutput: nil)

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .bash)
    }

    // xonsh runs under python, so its executable name is “Python”, but it sets its process title
    // (comm) to xonsh followed by its arguments.
    func testDiscoveryUsesCommWhenTheExecutableNameIsAnInterpreter() {
        discover(shellPath: "/bin/zsh", parentProcess: "Python xonsh --no-rc -i", dotdirOutput: nil)

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .xonsh)
    }

    // Without a process title xonsh is just python, and ps may be missing on a remote host: an
    // unknown or empty parent falls back to $SHELL.
    func testDiscoveryFallsBackToSHELLForAnUnknownParent() {
        discover(shellPath: "/Users/someone/venv/bin/xonsh", parentProcess: "python3 /usr/bin/python3", dotdirOutput: nil)

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .xonsh)
    }

    func testDiscoveryFallsBackToSHELLWithoutPs() {
        discover(shellPath: "/bin/bash", parentProcess: "", dotdirOutput: nil)

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .bash)
    }

    // A line that has arrived only in part must not be taken for the answer.
    func testDiscoveryIgnoresAPartialLine() {
        terminal.responseLines[Self.shellCommand] = ["My shell is tcsh /bin/tc", "My shell is tcsh /bin/tcsh or /bin/zsh, end"]
        controller.shellIntegrationInstallerSendShellCommands(0)
        terminal.run()

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .tcsh)
    }

    // Once the mutation thread has picked up an expectation, typing its text is already queued
    // for the main thread. Canceling before that runs must keep the text from being typed.
    func testCancelKeepsAQueuedCommandFromBeingTyped() {
        terminal.responses[Self.shellCommand] = "My shell is zsh -zsh or /bin/zsh, end"
        controller.shellIntegrationInstallerSendShellCommands(0)
        // As PTYSession's sync does: the copy adds the expectation and queues its text.
        let wet = terminal.dryExpect.copy() as! iTermExpect
        controller.shellIntegrationInstallerCancelExpectations()
        let drained = XCTestExpectation(description: "Main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 10)

        XCTAssertEqual(wet.expectations.count, 1)
        XCTAssertEqual(terminal.sentTexts, [])
    }

    func testSkipDoesNotBypassDiscovery() {
        controller.shellIntegrationInstallerSkipStage()

        XCTAssertEqual(controller.sendShellCommandsStage, 0)
        let next = controller.shellIntegrationInstallerNextCommandForSendShellCommands() ?? ""
        XCTAssertEqual(next, Self.shellCommand)
        XCTAssertFalse(next.contains("(null)"), next)
    }

    // F-436, F-544: writing the script starts the helper shells, once. Nothing else is typed
    // until they prompt.
    func testWriteScriptTypesOneThingUntilTheShellResponds() {
        discover(shellPath: "/bin/zsh", dotdirOutput: "My dotfiles go in /Users/someone, end")
        let discoveryCount = terminal.sentTexts.count

        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()

        let typed = Array(terminal.sentTexts.dropFirst(discoveryCount))
        XCTAssertEqual(typed, [Self.launchHelper])
    }

    // Starts writing the script, whose helpers don't prompt, then cancels.
    private func cancelWhileTheHelpersLaunch() -> Int {
        discover(shellPath: "/bin/zsh", dotdirOutput: "My dotfiles go in /Users/someone, end")
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()
        XCTAssertEqual(terminal.sentTexts.last, Self.launchHelper)
        _ = controller.perform(Selector(("cancel:")), with: nil)
        terminal.run()
        return terminal.sentTexts.count
    }

    // F-552: a “>> ” prompt after Cancel can be the user's own. The exit is typed only if the
    // shell that printed it says it is one helper deep.
    func testCancelBeforeTheHelpersPromptDoesNotExitTheUserShellWithALookalikePrompt() {
        let sentBefore = cancelWhileTheHelpersLaunch()
        terminal.responses[Self.helperDepthCommand] = "it2-helper-depth-0-"

        terminal.output(">> ")
        terminal.run()

        XCTAssertEqual(Array(terminal.sentTexts.dropFirst(sentBefore)), [Self.helperDepthCommand])
        XCTAssertFalse(controller.waitingForCanceledHelperLaunch)
    }

    // F-552: a shell that says it is two helpers deep is not what the installer knows it launched
    // (as in a helper left over from before), so nothing is typed.
    func testCancelBeforeTheHelpersPromptDoesNotExitWhenTheHelperIsNested() {
        let sentBefore = cancelWhileTheHelpersLaunch()
        terminal.responses[Self.helperDepthCommand] = "it2-helper-depth-2-"

        terminal.output(">> ")
        terminal.run()

        XCTAssertEqual(Array(terminal.sentTexts.dropFirst(sentBefore)), [Self.helperDepthCommand])
    }

    func testCancelBeforeTheHelpersPromptExitsTheHelperWhenItSaysItIsOneDeep() {
        let sentBefore = cancelWhileTheHelpersLaunch()
        terminal.responses[Self.helperDepthCommand] = "it2-helper-depth-1-"

        terminal.output(">> ")
        terminal.run()

        XCTAssertEqual(Array(terminal.sentTexts.dropFirst(sentBefore)), [Self.helperDepthCommand, Self.typedExit])
    }

    func testSkipAfterDiscoveryUsesDiscoveredDotdir() {
        discover(shellPath: "/bin/zsh", dotdirOutput: "My dotfiles go in /Users/someone, end")
        XCTAssertEqual(controller.sendShellCommandsStage, 1)

        controller.shellIntegrationInstallerSkipStage()

        XCTAssertEqual(controller.sendShellCommandsStage, 2)
        let next = controller.shellIntegrationInstallerNextCommandForSendShellCommands() ?? ""
        XCTAssertFalse(next.contains("(null)"), next)
        XCTAssertTrue(next.contains("/Users/someone/.zshrc"), next)
    }
}

class ShellIntegrationOfflineNushellInstallerTests: XCTestCase {
    // $SHELL in the session.
    class var shellVariable: String { FakeNushellTerminal.nuPath }

    private var controller: iTermShellIntegrationWindowController!
    private var terminal: FakeNushellTerminal!

    override func setUp() {
        super.setUp()
        terminal = FakeNushellTerminal(testCase: self)
        terminal.shellVariable = Self.shellVariable
        controller = iTermShellIntegrationWindowController(windowNibName: "iTermShellIntegrationWindowController")
        controller.delegate = terminal
        XCTAssertNotNil(controller.window)
        controller.shellIntegrationInstallerSendShellCommands(-1)
        controller.shellIntegrationInstallerSendShellCommands(0)
        terminal.run()
        XCTAssertEqual(controller.shell, .nu)
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
    }

    override func tearDown() {
        controller.shellIntegrationInstallerCancelExpectations()
        controller.window?.orderOut(nil)
        controller = nil
        terminal = nil
        super.tearDown()
    }

    // What the installer typed after discovery.
    private func textsAfterDiscovery() -> [String] {
        return Array(terminal.sentTexts.dropFirst())
    }

    private func bundledScript() -> String {
        let bundle = Bundle(for: iTermShellIntegrationWindowController.self)
        guard let url = bundle.url(forResource: "iterm2_shell_integration", withExtension: "nu"),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Missing bundled nushell script")
            return ""
        }
        return script
    }

    func testWriteScriptWaitsForEachStepAndWritesTheScript() {
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()

        XCTAssertEqual(terminal.textLostToNushell, [])
        let texts = textsAfterDiscovery()
        XCTAssertEqual(texts.count, 5, "\(texts)")
        if texts.count == 5 {
            XCTAssertEqual(texts[0], ShellIntegrationOfflineInstallerTests.launchHelper)
            XCTAssertTrue(texts[1].hasPrefix("IT2_NU_AUTOLOAD_DIR="), texts[1])
            XCTAssertTrue(texts[1].contains("mkdir -p \"$IT2_NU_AUTOLOAD_DIR\""), texts[1])
            XCTAssertTrue(texts[2].contains(receiveScriptCommandMarker), texts[2])
            XCTAssertTrue(texts[2].hasPrefix("IT2_F=\"$IT2_NU_AUTOLOAD_DIR/iterm2_shell_integration.nu\"; "), texts[2])
            XCTAssertTrue(texts[3].hasSuffix("\nEOF\n"), texts[3])
            XCTAssertEqual(texts[4], ShellIntegrationOfflineInstallerTests.typedExit)
        }
        let script = terminal.files[FakeNushellTerminal.scriptPath] ?? ""
        let bundled = bundledScript()
        XCTAssertFalse(bundled.isEmpty)
        XCTAssertTrue(script.hasPrefix(bundled), script)
        XCTAssertFalse(script.contains("mkdir"), script)
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(controller.sendShellCommandsStage, 2)
        XCTAssertFalse(controller.sendShellCommandsWriteFailed)
        XCTAssertLessThan(longestTypedLine(textsAfterDiscovery()), 1024)
    }

    func testWriteScriptReportsFailureWhenTheFileIsNotWritten() {
        terminal.canCreateAutoloadDir = false

        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()

        XCTAssertNil(terminal.files[FakeNushellTerminal.scriptPath])
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertTrue(controller.sendShellCommandsWriteFailed)
        // The helper sh still exits, leaving the session in nushell.
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(terminal.sentTexts.last, ShellIntegrationOfflineInstallerTests.typedExit)
    }

    // QA finding F-381: the write-failed message wraps, and the step list had a fixed height, so
    // the steps after it were cut off.
    func testStepListGrowsToFitTheWriteFailedMessage() {
        controller.shellIntegrationInstallerSetInstallUtilities(true)
        let field = controller.sendShellCommandsStepListField
        let originalFieldHeight = field.frame.height
        let originalFieldMinY = field.frame.minY
        let originalContentHeight = controller.window?.contentView?.frame.height ?? 0

        terminal.canCreateAutoloadDir = false
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()
        XCTAssertTrue(controller.sendShellCommandsWriteFailed)

        let bounds = NSRect(x: 0, y: 0, width: field.frame.width, height: .greatestFiniteMagnitude)
        let fittingHeight = ceil(field.cell?.cellSize(forBounds: bounds).height ?? 0)
        XCTAssertGreaterThan(fittingHeight, originalFieldHeight)
        XCTAssertGreaterThanOrEqual(field.frame.height, fittingHeight)
        // The list grows upward; the buttons below it keep their places.
        XCTAssertEqual(field.frame.minY, originalFieldMinY)
        let growth = field.frame.height - originalFieldHeight
        guard let view = field.superview, let contentView = controller.window?.contentView else {
            XCTFail("Step list is not in the window")
            return
        }
        XCTAssertLessThanOrEqual(field.frame.maxY, view.bounds.height)
        XCTAssertEqual(contentView.frame.height, originalContentHeight + growth, accuracy: 0.5)
        let frameInContent = view.convert(view.bounds, to: contentView)
        XCTAssertGreaterThanOrEqual(frameInContent.minY, 0)
        XCTAssertLessThanOrEqual(frameInContent.maxY, contentView.bounds.height)

        // Back to shorter text: the list shrinks again but still fits.
        let grownHeight = field.frame.height
        controller.shellIntegrationInstallerSkipStage()
        XCTAssertFalse(controller.sendShellCommandsWriteFailed)
        let shorterFit = ceil(field.cell?.cellSize(forBounds: bounds).height ?? 0)
        XCTAssertLessThan(field.frame.height, grownHeight)
        XCTAssertGreaterThanOrEqual(field.frame.height, shorterFit)
        XCTAssertEqual(field.frame.minY, originalFieldMinY)
    }

    func testWriteScriptWaitsForTheHelperToStart() {
        // The helper sh never prompts. Nothing more may be typed, since nushell would read it,
        // and the echo of the typed command must not count as progress.
        terminal.helperStarts = false
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()

        XCTAssertEqual(textsAfterDiscovery().count, 1)
        XCTAssertEqual(terminal.textLostToNushell, [])
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertFalse(controller.sendShellCommandsWriteFailed)
    }

    func testInstallUtilitiesWaitsForTheHelperPrompt() {
        controller.shellIntegrationInstallerSetInstallUtilities(true)
        controller.shellIntegrationInstallerSkipStage()
        XCTAssertEqual(controller.sendShellCommandsStage, 2)

        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()

        XCTAssertEqual(terminal.textLostToNushell, [])
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(controller.sendShellCommandsStage, 3)
    }
}

// The online (download and run) installer types `curl … | bash`; the script iterm2.com serves
// decides which shell it supports. Until it supports nushell, the installer must switch to the
// Internet-free installer, which does, instead of reporting nushell as unsupported.
final class ShellIntegrationOnlineInstallerTests: XCTestCase {
    private static let curlCommand = "\ncurl -L https://iterm2.com/shell_integration/v2/install_shell_integration.sh | bash\n"
    private static let oldScriptNuError = "Your shell, nu, is not supported yet. Only tcsh, zsh, bash, and fish are supported. Sorry!"

    private var controller: iTermShellIntegrationWindowController!
    private var terminal: FakeShellIntegrationTerminal!

    override func setUp() {
        super.setUp()
        terminal = FakeShellIntegrationTerminal(testCase: self)
        controller = iTermShellIntegrationWindowController(windowNibName: "iTermShellIntegrationWindowController")
        controller.delegate = terminal
        XCTAssertNotNil(controller.window)
        controller.shellIntegrationInstallerConfirmDownloadAndRun()
        XCTAssertTrue(controller.showingDownloadAndRunPage)
    }

    override func tearDown() {
        controller.shellIntegrationInstallerCancelExpectations()
        controller.window?.orderOut(nil)
        controller = nil
        terminal = nil
        super.tearDown()
    }

    private func downloadAndRun(output: String) {
        terminal.responses[Self.curlCommand] = output
        controller.shellIntegrationInstallerReallyDownloadAndRun()
        terminal.run()
        XCTAssertEqual(terminal.sentTexts, [Self.curlCommand])
    }

    func testNushellRejectedByWebsiteScriptSwitchesToInternetFreeInstall() {
        downloadAndRun(output: Self.oldScriptNuError)

        XCTAssertFalse(controller.showingDownloadAndRunPage)
        XCTAssertTrue(controller.showingSendShellCommandsPage)
        XCTAssertEqual(controller.sendShellCommandsStage, 0)
    }

    func testOtherUnsupportedShellStaysOnDownloadPage() {
        downloadAndRun(output: "Your shell, elvish, is not supported yet. Only bash, fish, nu, tcsh, xonsh and zsh are supported. Sorry!")

        XCTAssertTrue(controller.showingDownloadAndRunPage)
        XCTAssertFalse(controller.showingSendShellCommandsPage)
    }

    func testSuccessfulInstallAdvances() {
        downloadAndRun(output: "Done.")

        XCTAssertFalse(controller.showingDownloadAndRunPage)
        XCTAssertFalse(controller.showingSendShellCommandsPage)
    }
}

// nu started from a zsh login shell: $SHELL is zsh, but the commands go to nu, so every step
// must work without asking $SHELL for nu's autoload directory.
final class ShellIntegrationOfflineNushellFromZshInstallerTests: ShellIntegrationOfflineNushellInstallerTests {
    override class var shellVariable: String { "/bin/zsh" }
}

// F-436: xonsh reads typeahead in bulk, so the installer must wait for the helper sh's prompt
// before typing into it, or xonsh keeps the commands and the steps go wrong.
final class ShellIntegrationOfflineXonshInstallerTests: XCTestCase {
    private var controller: iTermShellIntegrationWindowController!
    private var terminal: FakeXonshTerminal!

    override func setUp() {
        super.setUp()
        terminal = FakeXonshTerminal(testCase: self)
        terminal.responses[ShellIntegrationOfflineInstallerTests.shellCommand] = "My shell is Python xonsh --no-rc -i or /bin/zsh, end"
        controller = iTermShellIntegrationWindowController(windowNibName: "iTermShellIntegrationWindowController")
        controller.delegate = terminal
        XCTAssertNotNil(controller.window)
        controller.shellIntegrationInstallerSetInstallUtilities(true)
        controller.shellIntegrationInstallerSendShellCommands(-1)
        controller.shellIntegrationInstallerSendShellCommands(0)
        terminal.run()
        XCTAssertEqual(controller.shell, .xonsh)
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
    }

    override func tearDown() {
        controller.shellIntegrationInstallerCancelExpectations()
        controller.window?.orderOut(nil)
        controller = nil
        terminal = nil
        super.tearDown()
    }

    func testWriteScriptWaitsForTheHelperAndReturnsToXonsh() {
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()

        XCTAssertEqual(terminal.textLostToXonsh, [])
        XCTAssertNotNil(terminal.files[FakeXonshTerminal.scriptPath])
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(controller.sendShellCommandsStage, 2)
    }

    func testInstallUtilitiesWaitsForTheHelperAndReturnsToXonsh() {
        controller.shellIntegrationInstallerSkipStage()
        XCTAssertEqual(controller.sendShellCommandsStage, 2)

        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()

        XCTAssertEqual(terminal.textLostToXonsh, [])
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(controller.sendShellCommandsStage, 3)
    }

    func testWholeInstallReturnsToXonsh() {
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()

        XCTAssertLessThan(longestTypedLine(terminal.sentTexts), 1024)
        XCTAssertEqual(terminal.textLostToXonsh, [])
        XCTAssertNotNil(terminal.files[FakeXonshTerminal.scriptPath])
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(controller.sendShellCommandsStage, 3)
    }
}

// Plays tcsh started by hand from a zsh login shell, with the helper sh the installer starts
// from it. The tty echoes typed text as soon as it is typed, but a command's output comes only
// once it has run. Output a command has not printed yet when the next line is typed lands
// inside that line's echo, as in `…fi <<'Eok`.
private final class FakeTcshFromZshTerminal: FakeShellIntegrationTerminal {
    private var depth = 0
    private var pendingInput = ""
    private var delayedOutput = [String]()
    private var flushScheduled = false
    private var prompt = "> "
    // The row the cursor is on, which a typed line's echo is appended to: the last prompt, plus
    // whatever was printed before it on the same row.
    private var promptRow = "> "
    private var heredocLines: [String]?
    private var receivingUtilities = false
    // The command receiving the script, while sh reads it.
    private var receiveScriptCommand: String?
    // sh is reading an if statement up to its fi.
    private var inIfStatement = false
    // Set to make the helper sh like dash (Debian's and Ubuntu's sh), which has no line editor:
    // the tty echoes what is typed as it arrives, and sh's prompts follow the echo (see
    // respondWithoutLineEditor(to:)).
    var shEchoesTypeahead = true

    private(set) var heredocBodies = [[String]]()
    // The files sh wrote, by the path as typed.
    private(set) var files = [String: String]()
    // Where the here-document being read goes, if it goes to a file.
    private var heredocPath: String?
    // Set to make tar fail to extract the utilities archive, as for one damaged on the way.
    var extractionFails = false
    // Set to make sh unable to create the file the archive goes into, as in a folder that is
    // not writable.
    var receiveFails = false
    // Set to make cd into the utilities folder fail, as when ~/.iterm2 is a file.
    var cdFails = false
    // Set to keep sh reading the archive, as while it is still being typed: the line that ends
    // the archive doesn't arrive, though one typed later does.
    var archiveNeverEnds = false
    // Text typed from the first text containing this on waits, unread, as for a shell that is
    // slow to start or a long paste still being typed, until releaseHeldInput().
    var holdInputContaining: String?
    private var heldInput = ""
    // The helper launch was read and its first prompt has not been printed yet.
    private var awaitingHelperPrompt = false
    // The user types text (with no newline) right after the installer types a text containing
    // trigger, before the shell has answered it.
    var userTypesAfter: (trigger: String, text: String)?
    // How many times exit reached the user's shell, which would end it.
    private(set) var exitsTypedIntoUserShell = 0

    var helperIsRunning: Bool {
        return depth > 0
    }

    var helperDepth: Int {
        return depth
    }

    func releaseHeldInput() {
        holdInputContaining = nil
        let text = heldInput
        heldInput = ""
        for line in respond(to: text) {
            output(line)
        }
    }

    override func respond(to text: String) -> [String] {
        // F-882: see the check where the launch line is read.
        XCTAssertTrue(!awaitingHelperPrompt || text.allSatisfy { $0 == "\n" },
                      "Typed ahead of the helper: \(text)")
        if !heldInput.isEmpty || holdInputContaining.map({ text.contains($0) }) == true {
            heldInput += text
            return []
        }
        var userText: String?
        if let typing = userTypesAfter, text.contains(typing.trigger) {
            userText = typing.text
            userTypesAfter = nil
        }
        defer {
            // Typed before anything else arrives, so sh reads it before the next text.
            if let userText {
                pendingInput += userText
            }
        }
        var text = text
        if archiveNeverEnds && receivingUtilities && text.count > "\nEOF\n".count && text.hasSuffix("\nEOF\n") {
            text.removeLast("EOF\n".count)
        }
        if !shEchoesTypeahead && depth > 0 {
            return respondWithoutLineEditor(to: text)
        }
        pendingInput += text
        var rows = [String]()
        while let newline = pendingInput.firstIndex(of: "\n") {
            let line = erasingKilledText(String(pendingInput[..<newline]))
            pendingInput = String(pendingInput[pendingInput.index(after: newline)...])
            if depth == 0 && line == ShellIntegrationOfflineInstallerTests.helperLaunchLine {
                // F-882: what is typed before the helper prompts can be read by the wrong shell
                // (on Linux, a shell the launch starts reads all of it at once), so it must be
                // harmless anywhere: at most the empty lines that ask for a fresh prompt.
                XCTAssertEqual(pendingInput.filter { $0 != "\n" }, "", "Typed ahead of the helper")
                awaitingHelperPrompt = true
            }
            if delayedOutput.isEmpty {
                rows.append(line)
            } else {
                // The earlier command's output arrives in the middle of this line's echo.
                let cut = line.index(line.startIndex, offsetBy: line.count / 2)
                rows.append(String(line[..<cut]) + delayedOutput.removeFirst())
                rows.append(contentsOf: delayedOutput)
                delayedOutput.removeAll()
                rows.append(String(line[cut...]))
            }
            let inSh = depth > 0
            var printed = handle(line)
            if inSh {
                // sh's line editor redraws the line as soon as it reads it. What the command
                // prints comes later.
                rows.append(printed.removeFirst())
            }
            delayedOutput.append(contentsOf: printed)
            if !flushScheduled {
                flushScheduled = true
                laterEvents.append { [weak self] in
                    guard let self else {
                        return
                    }
                    self.flushScheduled = false
                    self.awaitingHelperPrompt = false
                    let lines = self.delayedOutput
                    self.delayedOutput.removeAll()
                    for line in lines {
                        self.output(line)
                    }
                }
            }
        }
        return rows
    }

    // A helper sh like dash, which has no line editor, leaves the tty in canonical mode with
    // echo on. The tty echoes all of the text as soon as it arrives, on the row the cursor is
    // on. sh reads the lines only after that, and prints each one's output and the next prompt
    // without redrawing the line.
    private func respondWithoutLineEditor(to text: String) -> [String] {
        var rows = [String]()
        var row = promptRow
        for (i, piece) in text.components(separatedBy: "\n").enumerated() {
            if i > 0 {
                rows.append(row)
                row = ""
            }
            row += piece
        }
        if !row.isEmpty {
            rows.append(row)
        }
        pendingInput += text
        while let newline = pendingInput.firstIndex(of: "\n") {
            // In canonical mode Linux's tty keeps at most 4095 bytes of a line, plus its newline,
            // and drops the rest.
            let line = erasingKilledText(String(decoding: pendingInput[..<newline].utf8.prefix(4095), as: UTF8.self))
            pendingInput = String(pendingInput[pendingInput.index(after: newline)...])
            let inSh = depth > 0
            var printed = handle(line)
            if inSh && !printed.isEmpty {
                printed.removeFirst()
            }
            for (i, text) in printed.enumerated() {
                if i > 0 {
                    row = ""
                }
                row += text
                rows.append(row)
            }
        }
        promptRow = row
        return rows
    }

    // What the shell prints when it gets to a line: in sh, the line editor's redraw of its prompt
    // and the line it read, then the command's output and the next prompt.
    private func handle(_ line: String) -> [String] {
        if depth > 0 {
            // The helper reads a line only after it prompted.
            awaitingHelperPrompt = false
        }
        let printed = handleLine(line)
        if let last = printed.last {
            promptRow = last
        }
        return printed
    }

    private func handleLine(_ line: String) -> [String] {
        if depth == 0 {
            if line == ShellIntegrationOfflineInstallerTests.helperLaunchLine {
                depth = 1
                prompt = ">> "
                return [helpersReadyMarker + prompt]
            }
            if line == "exit" {
                exitsTypedIntoUserShell += 1
            }
            return super.respond(to: line + "\n") + ["> "]
        }
        let redraw = promptRow + line
        if var lines = heredocLines {
            if line == "EOF" {
                heredocBodies.append(lines)
                heredocLines = nil
                if let heredocPath {
                    files[heredocPath] = lines.joined(separator: "\n") + "\n"
                    self.heredocPath = nil
                }
                prompt = inIfStatement ? "> " : ">> "
                if receivingUtilities {
                    receivingUtilities = false
                    let answer = extractionFails ? "it2-utilities-failed" : "it2-utilities-installed"
                    return [redraw, answer, prompt]
                }
                if let command = receiveScriptCommand {
                    receiveScriptCommand = nil
                    guard let path = fakeReceiveScriptPath(command),
                          let contents = fakeReceivedScript(command, lines: lines) else {
                        return [redraw, "it2-script-failed", prompt]
                    }
                    files[path] = contents
                    return [redraw, "it2-script-written", prompt]
                }
            } else {
                lines.append(line)
                heredocLines = lines
            }
            return [redraw, prompt]
        }
        var result = [redraw]
        if line == ShellIntegrationOfflineInstallerTests.helperLaunchLine {
            depth += 1
            prompt = ">> "
            return result + [helpersReadyMarker + prompt]
        } else if line + "\n" == ShellIntegrationOfflineInstallerTests.shellCommand {
            // macOS's sh is bash, and the helper has IT2_INSTALLER_HELPER in its environment.
            result.append("My shell is bash sh or /bin/zsh, in an installer helper shell, end")
        } else if line.contains(receiveScriptCommandMarker) && receiveFails {
            result.append("sh: \(fakeReceiveScriptPath(line) ?? "").it2-b64: Permission denied")
            result.append("it2-cannot-receive-script")
        } else if line.contains(receiveScriptCommandMarker) {
            // sh reads the script from the tty with its line editor off, so there is no prompt.
            result.append("it2-receiving-script")
            heredocLines = []
            receiveScriptCommand = line
            prompt = ""
        } else if line.contains(receiveUtilitiesCommandMarker) && receiveFails {
            // The redirection failed, so the read loop never runs and sh reads commands again.
            result.append("sh: .it2-utilities.b64: Permission denied")
            result.append("it2-cannot-receive-utilities")
        } else if line.contains(receiveUtilitiesCommandMarker) {
            // sh reads the archive from the tty with its line editor off, so there is no prompt.
            result.append("it2-receiving-utilities")
            heredocLines = []
            receivingUtilities = true
            prompt = ""
        } else if line.contains("<<'EOF'") || line.contains("<<-EOF") {
            heredocLines = []
            if line.hasPrefix("cat <<'EOF' > ") {
                heredocPath = String(line.dropFirst("cat <<'EOF' > ".count))
            }
            prompt = "> "
        } else if line.hasPrefix("if ") && line.hasSuffix("then") {
            inIfStatement = true
            prompt = "> "
        } else if line == "fi" || line.hasPrefix("fi;") {
            inIfStatement = false
            prompt = ">> "
            if let range = line.range(of: "; echo ") {
                result.append(line[range.upperBound...].replacingOccurrences(of: "\"", with: ""))
            }
        } else if line == "exit" {
            depth -= 1
            if depth == 0 {
                return [redraw, "> "]
            }
            prompt = ">> "
        } else if line.hasPrefix("echo ") {
            result.append(line.dropFirst("echo ".count)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "$PS1", with: prompt)
                .replacingOccurrences(of: "${IT2_INSTALLER_HELPER:-0}", with: String(depth)))
        } else if line.hasPrefix("cd "), let answer = fakeConditionalEchoAnswer(line, fails: cdFails) {
            if cdFails {
                result.append("sh: cd: \(line.dropFirst("cd ".count).prefix(while: { $0 != " " })): Not a directory")
            }
            result.append(answer)
        } else if let range = line.range(of: "; echo ") {
            if line.hasPrefix("mkdir ") {
                result.append("mkdir: \(line.dropFirst("mkdir ".count).prefix(while: { $0 != ";" })): File exists")
            }
            result.append(line[range.upperBound...].replacingOccurrences(of: "\"", with: ""))
        }
        return result + [prompt]
    }
}

// F-481: with tcsh started from zsh, output from a command can arrive in the middle of the echo
// of the next one. The utilities step must wait for each command's own answer, or it waits for
// an answer that already went by and never sends the here-document body.
class ShellIntegrationOfflineTcshFromZshInstallerTests: XCTestCase {
    // See FakeShellIntegrationTerminal.defersMatchCompletions.
    class var defersMatchCompletions: Bool { false }
    // See FakeTcshFromZshTerminal.shEchoesTypeahead.
    class var shEchoesTypeahead: Bool { true }

    private var controller: iTermShellIntegrationWindowController!
    private var terminal: FakeTcshFromZshTerminal!

    override func setUp() {
        super.setUp()
        terminal = FakeTcshFromZshTerminal(testCase: self)
        terminal.defersMatchCompletions = Self.defersMatchCompletions
        terminal.shEchoesTypeahead = Self.shEchoesTypeahead
        terminal.responses[ShellIntegrationOfflineInstallerTests.shellCommand] = "My shell is tcsh -csh or /bin/zsh, end"
        controller = iTermShellIntegrationWindowController(windowNibName: "iTermShellIntegrationWindowController")
        controller.delegate = terminal
        XCTAssertNotNil(controller.window)
        controller.shellIntegrationInstallerSetInstallUtilities(true)
        controller.shellIntegrationInstallerSendShellCommands(-1)
        controller.shellIntegrationInstallerSendShellCommands(0)
        terminal.run()
        XCTAssertEqual(controller.shell, .tcsh)
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
    }

    override func tearDown() {
        controller.shellIntegrationInstallerCancelExpectations()
        controller.window?.orderOut(nil)
        controller = nil
        terminal = nil
        super.tearDown()
    }

    func testInstallUtilitiesSendsTheArchiveAndExitsTheHelper() {
        controller.shellIntegrationInstallerSkipStage()
        XCTAssertEqual(controller.sendShellCommandsStage, 2)

        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()

        XCTAssertEqual(terminal.heredocBodies.count, 1)
        XCTAssertGreaterThan(terminal.heredocBodies.first?.count ?? 0, 1)
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(controller.sendShellCommandsStage, 3)
    }

    private func encodedUtilitiesArchive() -> [String] {
        let bundle = Bundle(for: iTermShellIntegrationWindowController.self)
        guard let url = bundle.url(forResource: "utilities", withExtension: "tgz"),
              let data = try? Data(contentsOf: url) else {
            XCTFail("Missing bundled utilities archive")
            return []
        }
        return data.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
            .components(separatedBy: "\n")
    }

    // F-352: the archive is typed only once sh says it is reading it with its line editor off,
    // and all of it arrives.
    func testInstallUtilitiesSendsTheArchiveToAReaderWithoutALineEditor() {
        controller.shellIntegrationInstallerSkipStage()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()

        let receive = terminal.sentTexts.firstIndex { $0.contains(receiveUtilitiesCommandMarker) }
        XCTAssertNotNil(receive)
        XCTAssertFalse(terminal.sentTexts.contains { $0.contains("<<'EOF'| tar") })
        XCTAssertEqual(terminal.heredocBodies, [encodedUtilitiesArchive()])
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(controller.sendShellCommandsStage, 3)
        XCTAssertFalse(controller.sendShellCommandsWriteFailed)
    }

    // F-352: when the archive does not extract, the step says so instead of reporting success.
    func testInstallUtilitiesReportsFailureWhenTheArchiveDoesNotExtract() {
        terminal.extractionFails = true
        controller.shellIntegrationInstallerSkipStage()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()

        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(controller.sendShellCommandsStage, 2)
        XCTAssertTrue(controller.sendShellCommandsWriteFailed)
        let steps = controller.sendShellCommandsStepListField.stringValue
        XCTAssertTrue(steps.contains("utility scripts were not installed"), steps)
        XCTAssertFalse(steps.contains("Done!"), steps)
    }

    // F-462: when sh can't create the file the archive goes into, the archive is not typed (it
    // would run as commands) and the step says the utilities were not installed.
    func testInstallUtilitiesDoesNotTypeTheArchiveWhenShCannotReceiveIt() {
        terminal.receiveFails = true
        controller.shellIntegrationInstallerSkipStage()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()

        let firstLine = encodedUtilitiesArchive().first ?? ""
        XCTAssertFalse(firstLine.isEmpty)
        XCTAssertNotNil(terminal.sentTexts.firstIndex { $0.contains(receiveUtilitiesCommandMarker) })
        XCTAssertFalse(terminal.sentTexts.contains { $0.contains(firstLine) })
        XCTAssertFalse(terminal.sentTexts.contains { $0.contains("\nEOF\n") })
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(controller.sendShellCommandsStage, 2)
        XCTAssertTrue(controller.sendShellCommandsWriteFailed)
        let steps = controller.sendShellCommandsStepListField.stringValue
        XCTAssertTrue(steps.contains("utility scripts were not installed"), steps)
    }

    // T-130: when sh can't enter the utilities folder (as when ~/.iterm2 is a file), nothing is
    // received or unpacked in the folder it is in, the helpers exit, and the step says the
    // utilities were not installed.
    func testInstallUtilitiesStopsWhenCdFails() {
        terminal.cdFails = true
        controller.shellIntegrationInstallerSkipStage()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()

        let firstLine = encodedUtilitiesArchive().first ?? ""
        XCTAssertFalse(firstLine.isEmpty)
        XCTAssertNotNil(terminal.sentTexts.firstIndex { $0.hasPrefix("cd ") })
        XCTAssertNil(terminal.sentTexts.firstIndex { $0.contains(receiveUtilitiesCommandMarker) })
        XCTAssertFalse(terminal.sentTexts.contains { $0.contains(firstLine) })
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
        XCTAssertEqual(controller.sendShellCommandsStage, 2)
        XCTAssertTrue(controller.sendShellCommandsWriteFailed)
        let steps = controller.sendShellCommandsStepListField.stringValue
        XCTAssertTrue(steps.contains("utility scripts were not installed"), steps)
    }

    // F-463: the archive takes a minute or more to type. Cancel must stop typing it, not just
    // stop waiting for sh's answer.
    func testCancelStopsTypingTheArchive() {
        terminal.archiveNeverEnds = true
        controller.shellIntegrationInstallerSkipStage()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()
        XCTAssertTrue(terminal.sentTexts.contains { $0.hasSuffix("\nEOF\n") })
        XCTAssertEqual(terminal.heredocBodies, [])
        let stopsBefore = terminal.stopSendingTextCount
        let sentBefore = terminal.sentTexts.count

        _ = controller.perform(Selector(("cancel:")), with: nil)
        terminal.run()

        XCTAssertEqual(terminal.stopSendingTextCount, stopsBefore + 1)
        // The line that ends the read loop is still typed, so sh doesn't keep taking what is
        // typed next into its file.
        let typed = Array(terminal.sentTexts.dropFirst(sentBefore))
        XCTAssertTrue(typed.first?.hasPrefix("\nEOF\n") == true, "\(typed)")
    }

    private var launchesTyped: Int {
        return terminal.sentTexts.filter { $0.contains("ENV=/dev/null INPUTRC=/dev/null ") }.count
    }

    // F-544: Cancel while the archive is typed ends sh's read loop and, once sh says it is done,
    // leaves the helper shell for the user's shell.
    func testCancelWhileTypingTheArchiveReturnsToTheUserShell() {
        terminal.archiveNeverEnds = true
        controller.shellIntegrationInstallerSkipStage()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()
        XCTAssertEqual(terminal.helperDepth, 1)

        _ = controller.perform(Selector(("cancel:")), with: nil)
        terminal.run()

        XCTAssertEqual(terminal.helperDepth, 0)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
    }

    // F-544: Cancel while sh receives the script ends its read loop, then leaves the helpers.
    // The helpers are started once, not again from within themselves. F-880: what sh got is not
    // the whole script, so it writes nothing.
    func testCancelWhileWritingTheScriptReturnsToTheUserShell() {
        terminal.holdInputContaining = receiveScriptCommandMarker
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()
        XCTAssertEqual(terminal.heredocBodies.count, 0)

        _ = controller.perform(Selector(("cancel:")), with: nil)
        terminal.run()
        terminal.releaseHeldInput()
        terminal.run()

        XCTAssertEqual(launchesTyped, 1)
        XCTAssertEqual(terminal.heredocBodies.count, 1)
        XCTAssertEqual(terminal.files, [:])
        XCTAssertEqual(terminal.helperDepth, 0)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
    }

    // F-544: until the helpers prompt, it isn't known that they run, so Cancel types nothing
    // (exit could reach the user's shell). F-552: once they prompt, as a shell slow to start a
    // command lets them do well after Cancel, they are known to run and are exited.
    func testCancelBeforeTheHelpersPromptExitsThemOnceTheyPrompt() {
        terminal.holdInputContaining = "ENV=/dev/null"
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()
        let sentBefore = terminal.sentTexts.count

        _ = controller.perform(Selector(("cancel:")), with: nil)
        terminal.run()
        XCTAssertEqual(terminal.sentTexts.count, sentBefore)
        XCTAssertTrue(controller.waitingForCanceledHelperLaunch)
        terminal.releaseHeldInput()
        terminal.run()

        XCTAssertEqual(Array(terminal.sentTexts.dropFirst(sentBefore)),
                       [ShellIntegrationOfflineInstallerTests.helperDepthCommand, ShellIntegrationOfflineInstallerTests.typedExit])
        XCTAssertEqual(terminal.helperDepth, 0)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
        XCTAssertFalse(controller.waitingForCanceledHelperLaunch)
    }

    private func waitUntilNotWaitingForCanceledHelperLaunch(_ controller: iTermShellIntegrationWindowController) {
        let predicate = NSPredicate { object, _ in
            !(object as! iTermShellIntegrationWindowController).waitingForCanceledHelperLaunch
        }
        wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: controller)], timeout: 10)
    }

    // F-552: if the helpers don't prompt in time, the installer stops waiting and still types
    // nothing, even if a prompt shows up later.
    func testCancelBeforeTheHelpersPromptTypesNothingIfTheyDoNotPromptInTime() {
        controller.canceledHelperLaunchTimeout = 0
        terminal.holdInputContaining = "ENV=/dev/null"
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()
        let sentBefore = terminal.sentTexts.count

        _ = controller.perform(Selector(("cancel:")), with: nil)
        waitUntilNotWaitingForCanceledHelperLaunch(controller)
        terminal.releaseHeldInput()
        terminal.run()

        XCTAssertEqual(terminal.sentTexts.count, sentBefore)
        XCTAssertEqual(terminal.helperDepth, 1)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
    }

    // A new installer window, as opened after Cancel closed this one, for the same session.
    private func makeNextInstaller() -> iTermShellIntegrationWindowController {
        let next = iTermShellIntegrationWindowController(windowNibName: "iTermShellIntegrationWindowController")
        XCTAssertNotNil(next.window)
        next.delegate = terminal
        next.takeOverHelperShells(fromInstaller: controller)
        next.shellIntegrationInstallerSendShellCommands(-1)
        return next
    }

    // F-552: discovery in an installer opened after Cancel while the helpers launched waits for
    // them to prompt and exit, then asks the user's shell.
    func testDiscoveryAfterCancelBeforeTheHelpersPromptAsksTheUserShell() {
        terminal.holdInputContaining = "ENV=/dev/null"
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()
        _ = controller.perform(Selector(("cancel:")), with: nil)
        terminal.run()
        let sentBefore = terminal.sentTexts.count

        let next = makeNextInstaller()
        next.shellIntegrationInstallerSendShellCommands(0)
        terminal.run()
        XCTAssertEqual(terminal.sentTexts.count, sentBefore)
        terminal.releaseHeldInput()
        terminal.run()

        XCTAssertEqual(Array(terminal.sentTexts.dropFirst(sentBefore)),
                       [ShellIntegrationOfflineInstallerTests.helperDepthCommand,
                        ShellIntegrationOfflineInstallerTests.typedExit,
                        ShellIntegrationOfflineInstallerTests.shellCommand])
        XCTAssertEqual(terminal.helperDepth, 0)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
        XCTAssertEqual(next.shell, .tcsh)
        XCTAssertEqual(next.sendShellCommandsStage, 1)
        next.shellIntegrationInstallerCancelExpectations()
        next.window?.orderOut(nil)
    }

    // F-552: discovery inside helper shells the installer can't exit (they prompted too late)
    // says so instead of taking macOS's sh, which is bash, for the user's shell.
    func testDiscoveryInsideLeftoverHelpersDoesNotReportBash() {
        controller.canceledHelperLaunchTimeout = 0
        terminal.holdInputContaining = "ENV=/dev/null"
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()
        _ = controller.perform(Selector(("cancel:")), with: nil)
        waitUntilNotWaitingForCanceledHelperLaunch(controller)
        terminal.releaseHeldInput()
        terminal.run()
        XCTAssertEqual(terminal.helperDepth, 1)
        let sentBefore = terminal.sentTexts.count

        let next = makeNextInstaller()
        next.shellIntegrationInstallerSendShellCommands(0)
        terminal.run()

        XCTAssertEqual(Array(terminal.sentTexts.dropFirst(sentBefore)),
                       [ShellIntegrationOfflineInstallerTests.shellCommand])
        XCTAssertEqual(next.shell, .unknown)
        XCTAssertEqual(next.sendShellCommandsStage, 0)
        let steps = next.sendShellCommandsStepListField.stringValue
        XCTAssertTrue(steps.contains("helper shell"), steps)
        XCTAssertFalse(steps.contains("bash"), steps)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
        next.shellIntegrationInstallerCancelExpectations()
        next.window?.orderOut(nil)
    }

    // F-552: an installer opened after Cancel doesn't wait forever for the previous one to exit
    // helpers whose answer never comes. It discovers after a while, finding out itself where it
    // is.
    func testDiscoveryDoesNotWaitForeverForThePreviousInstaller() {
        terminal.archiveNeverEnds = true
        controller.shellIntegrationInstallerSkipStage()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()
        // The helpers never answer the command that asks whether they read commands again.
        terminal.holdInputContaining = "helpers-$PS1-idle"
        _ = controller.perform(Selector(("cancel:")), with: nil)
        terminal.run()

        let next = makeNextInstaller()
        next.canceledHelperLaunchTimeout = 0
        next.shellIntegrationInstallerSendShellCommands(0)
        // Running the terminal drains the main queue, where the timeout fires.
        terminal.run()

        XCTAssertEqual(terminal.sentTexts.last, ShellIntegrationOfflineInstallerTests.shellCommand)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
        next.shellIntegrationInstallerCancelExpectations()
        next.window?.orderOut(nil)
    }

    // F-552: leaving the page while the helpers launch and starting over waits for them to
    // prompt and exit before asking the user's shell.
    func testDiscoveryAfterLeavingThePageBeforeTheHelpersPromptAsksTheUserShell() {
        terminal.holdInputContaining = "ENV=/dev/null"
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()
        let sentBefore = terminal.sentTexts.count

        controller.shellIntegrationInstallerBack()
        controller.shellIntegrationInstallerSendShellCommands(-1)
        controller.shellIntegrationInstallerSendShellCommands(0)
        terminal.run()
        XCTAssertEqual(terminal.sentTexts.count, sentBefore)
        terminal.releaseHeldInput()
        terminal.run()

        XCTAssertEqual(Array(terminal.sentTexts.dropFirst(sentBefore)),
                       [ShellIntegrationOfflineInstallerTests.helperDepthCommand,
                        ShellIntegrationOfflineInstallerTests.typedExit,
                        ShellIntegrationOfflineInstallerTests.shellCommand])
        XCTAssertEqual(terminal.helperDepth, 0)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
        XCTAssertEqual(controller.shell, .tcsh)
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
    }

    // F-543: Send Again while the archive is typed reuses the helpers rather than starting two
    // more inside them, so the step's exits end at the user's shell.
    func testSendAgainWhileTypingTheArchiveReturnsToTheUserShell() {
        terminal.archiveNeverEnds = true
        controller.shellIntegrationInstallerSkipStage()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()

        terminal.archiveNeverEnds = false
        controller.shellIntegrationInstallerCancelExpectations()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()

        XCTAssertEqual(launchesTyped, 1)
        XCTAssertEqual(terminal.heredocBodies.last, encodedUtilitiesArchive())
        XCTAssertEqual(terminal.helperDepth, 0)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
        XCTAssertEqual(controller.sendShellCommandsStage, 3)
    }

    // F-880: Cancel while the command that receives the script may still be typing doesn't stop
    // typing, which could cut the command and leave sh waiting for the rest of it. The lines that
    // end its read loop follow it.
    func testCancelBeforeTheScriptIsTypedDoesNotStopTyping() {
        terminal.holdInputContaining = receiveScriptCommandMarker
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()
        let sentBefore = terminal.sentTexts.count

        _ = controller.perform(Selector(("cancel:")), with: nil)
        terminal.run()
        terminal.releaseHeldInput()
        terminal.run()

        XCTAssertEqual(terminal.stopSendingTextCount, 0)
        XCTAssertTrue(terminal.sentTexts.dropFirst(sentBefore).first?.hasPrefix("\nEOF\n") == true)
        XCTAssertEqual(terminal.helperDepth, 0)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
    }

    // F-880: once the script is being typed, Cancel stops typing it.
    func testCancelWhileTypingTheScriptStopsTypingIt() {
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.holdInputContaining = "\nEOF\n"
        terminal.run()
        XCTAssertNotNil(terminal.sentTexts.firstIndex { $0.contains(receiveScriptCommandMarker) })
        XCTAssertTrue(terminal.sentTexts.last?.hasSuffix("\nEOF\n") == true)

        _ = controller.perform(Selector(("cancel:")), with: nil)
        terminal.run()

        XCTAssertEqual(terminal.stopSendingTextCount, 1)
    }

    // F-883: text the user types into the terminal after Cancel, before the helper answers the
    // command that shows it reads commands again, doesn't keep the exit from running.
    func testCancelWhileWritingTheScriptReturnsToTheUserShellWhenTheUserTypes() {
        terminal.holdInputContaining = receiveScriptCommandMarker
        terminal.userTypesAfter = (trigger: "helpers-$PS1-idle", text: "echo")
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()

        _ = controller.perform(Selector(("cancel:")), with: nil)
        terminal.run()
        terminal.releaseHeldInput()
        terminal.run()

        XCTAssertNil(terminal.userTypesAfter)
        XCTAssertEqual(terminal.helperDepth, 0)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
    }

    // F-543: Send Again while sh receives the script ends its read loop and writes the script
    // again from the same helpers.
    func testSendAgainWhileWritingTheScriptReturnsToTheUserShell() {
        terminal.holdInputContaining = receiveScriptCommandMarker
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()

        controller.shellIntegrationInstallerCancelExpectations()
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()
        terminal.releaseHeldInput()
        terminal.run()

        XCTAssertEqual(launchesTyped, 1)
        XCTAssertEqual(terminal.heredocBodies.count, 2)
        XCTAssertEqual(terminal.files["~/.iterm2_shell_integration.tcsh"]?.hasPrefix(bundledScript("tcsh")), true)
        XCTAssertEqual(terminal.helperDepth, 0)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
        XCTAssertEqual(controller.sendShellCommandsStage, 2)
    }

    // F-544: once the helpers prompted, Cancel while the next command waits for its answer
    // leaves them, even if the completion of the launch's expectation had not run when that
    // command was typed.
    func testCancelAfterTheHelpersPromptReturnsToTheUserShell() {
        terminal.holdInputContaining = "mkdir "
        controller.shellIntegrationInstallerSkipStage()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()
        XCTAssertEqual(terminal.helperDepth, 1)

        _ = controller.perform(Selector(("cancel:")), with: nil)
        terminal.run()
        terminal.releaseHeldInput()
        terminal.run()

        XCTAssertEqual(terminal.helperDepth, 0)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
    }

    // A second Send Again once the retry is typing into the helpers again doesn't treat them as
    // still reading the archive: it neither stops typing nor ends a read loop that has ended.
    func testSecondSendAgainAfterTheArchiveEndedDoesNotStopTyping() {
        terminal.archiveNeverEnds = true
        controller.shellIntegrationInstallerSkipStage()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()
        terminal.archiveNeverEnds = false
        terminal.holdInputContaining = "mkdir "
        controller.shellIntegrationInstallerCancelExpectations()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()
        let stops = terminal.stopSendingTextCount

        controller.shellIntegrationInstallerCancelExpectations()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.releaseHeldInput()
        terminal.run()

        XCTAssertEqual(terminal.stopSendingTextCount, stops)
        XCTAssertEqual(launchesTyped, 1)
        XCTAssertEqual(terminal.helperDepth, 0)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
        XCTAssertEqual(controller.sendShellCommandsStage, 3)
    }

    // Leaving the page while sh reads the archive and starting over asks the user's shell what
    // it is, once the helpers have exited, rather than asking a helper.
    func testDiscoveryAfterLeavingThePageWhileTypingTheArchiveAsksTheUserShell() {
        terminal.archiveNeverEnds = true
        controller.shellIntegrationInstallerSkipStage()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()
        let sentBefore = terminal.sentTexts.count

        controller.shellIntegrationInstallerBack()
        controller.shellIntegrationInstallerSendShellCommands(-1)
        controller.shellIntegrationInstallerSendShellCommands(0)
        terminal.run()

        let typed = Array(terminal.sentTexts.dropFirst(sentBefore))
        XCTAssertEqual(typed.count, 3, "\(typed)")
        XCTAssertEqual(typed.dropFirst().first, ShellIntegrationOfflineInstallerTests.typedExit)
        XCTAssertEqual(typed.last, ShellIntegrationOfflineInstallerTests.shellCommand)
        XCTAssertEqual(terminal.helperDepth, 0)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
    }

    // F-543: Send Again before the helpers prompt waits for them instead of starting more.
    func testSendAgainBeforeTheHelpersPromptReturnsToTheUserShell() {
        terminal.holdInputContaining = "ENV=/dev/null"
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()

        controller.shellIntegrationInstallerCancelExpectations()
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()
        terminal.releaseHeldInput()
        terminal.run()

        XCTAssertEqual(launchesTyped, 1)
        XCTAssertEqual(terminal.heredocBodies.count, 1)
        XCTAssertEqual(terminal.helperDepth, 0)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
        XCTAssertEqual(controller.sendShellCommandsStage, 2)
    }

    // F-463: Send Again while the archive is being typed stops it, and the retry's commands
    // reach sh rather than its read loop.
    func testSendAgainWhileTypingTheArchiveInstalls() {
        terminal.archiveNeverEnds = true
        controller.shellIntegrationInstallerSkipStage()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()
        XCTAssertEqual(terminal.heredocBodies, [])

        // As the step's Send Again button does while busy.
        terminal.archiveNeverEnds = false
        controller.shellIntegrationInstallerCancelExpectations()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()

        XCTAssertEqual(terminal.heredocBodies.count, 2)
        XCTAssertEqual(terminal.heredocBodies.last, encodedUtilitiesArchive())
        XCTAssertEqual(controller.sendShellCommandsStage, 3)
        XCTAssertFalse(controller.sendShellCommandsWriteFailed)
    }

    // F-463: Cancel stops typing only while sh reads a file: before anything was typed, or once
    // the archive is in, there is nothing to stop.
    func testCancelStopsTypingOnlyWhileShReadsAFile() {
        controller.shellIntegrationInstallerSendShellCommands(1)
        controller.shellIntegrationInstallerCancelExpectations()
        XCTAssertEqual(terminal.stopSendingTextCount, 0)

        controller.shellIntegrationInstallerSkipStage()
        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()
        XCTAssertEqual(controller.sendShellCommandsStage, 3)
        controller.shellIntegrationInstallerCancelExpectations()
        XCTAssertEqual(terminal.stopSendingTextCount, 0)
    }

    private func bundledScript(_ shell: String) -> String {
        let bundle = Bundle(for: iTermShellIntegrationWindowController.self)
        guard let url = bundle.url(forResource: "iterm2_shell_integration", withExtension: shell),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Missing bundled \(shell) script")
            return ""
        }
        return script
    }

    // F-880: the script has lines longer than a tty in canonical mode, as dash reads it, keeps.
    // It must be written whole, and no typed line may be longer than macOS's limit of 1024 bytes,
    // the smaller one.
    func testWriteScriptWritesTheWholeScript() {
        let bundled = bundledScript("tcsh")
        XCTAssertGreaterThan(bundled.components(separatedBy: "\n").map { $0.utf8.count }.max() ?? 0, 4096)

        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()

        let script = terminal.files["~/.iterm2_shell_integration.tcsh"] ?? ""
        XCTAssertTrue(script.hasPrefix(bundled), "\(script.utf8.count) bytes written, \(bundled.utf8.count) expected")
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(controller.sendShellCommandsStage, 2)
        XCTAssertFalse(controller.sendShellCommandsWriteFailed)
        XCTAssertLessThan(longestTypedLine(terminal.sentTexts), 1024)
    }

    // F-880: when sh can't create the file the script goes into, the script is not typed (it
    // would run as commands), the helpers exit, and the step says the script was not written.
    func testWriteScriptDoesNotTypeTheScriptWhenShCannotReceiveIt() {
        terminal.receiveFails = true
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()

        XCTAssertNotNil(terminal.sentTexts.firstIndex { $0.contains(receiveScriptCommandMarker) })
        XCTAssertFalse(terminal.sentTexts.contains { $0.contains("\nEOF\n") })
        XCTAssertEqual(terminal.files, [:])
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertTrue(controller.sendShellCommandsWriteFailed)
    }

    // F-880: every line of the whole install, the dotfile step too, is far shorter than a tty in
    // canonical mode keeps.
    func testWholeInstallTypesOnlyShortLines() {
        for stage in 1...3 {
            controller.shellIntegrationInstallerSendShellCommands(Int32(stage))
            terminal.run()
            XCTAssertEqual(controller.sendShellCommandsStage, Int32(stage + 1))
        }
        XCTAssertLessThan(longestTypedLine(terminal.sentTexts), 1024)
    }

    func testWholeInstallSendsBothHereDocumentsAndExitsTheHelper() {
        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(controller.sendShellCommandsStage, 2)

        controller.shellIntegrationInstallerSendShellCommands(2)
        terminal.run()

        XCTAssertEqual(terminal.heredocBodies.count, 2)
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(controller.sendShellCommandsStage, 3)
    }

    // F-870: every step, the dotfile too, gets through its helpers' launch and returns to the
    // user's shell.
    func testWholeInstallWithTheDotfileReturnsToTheUserShell() {
        for stage in 1...3 {
            controller.shellIntegrationInstallerSendShellCommands(Int32(stage))
            terminal.run()
            XCTAssertFalse(terminal.helperIsRunning, "stage \(stage)")
            XCTAssertEqual(controller.sendShellCommandsStage, Int32(stage + 1))
        }

        XCTAssertEqual(terminal.heredocBodies.count, 3)
        XCTAssertTrue(terminal.heredocBodies.last?.contains { $0.contains("source ~/.iterm2_shell_integration.tcsh") } == true,
                      "\(terminal.heredocBodies.last ?? [])")
        XCTAssertEqual(terminal.exitsTypedIntoUserShell, 0)
    }
}

// F-870: the same with a helper sh like dash, the sh of Debian and Ubuntu, which has no line
// editor.
final class ShellIntegrationOfflineDashInstallerTests: ShellIntegrationOfflineTcshFromZshInstallerTests {
    override class var shEchoesTypeahead: Bool { false }
}

// F-353: the dotfile step for bash. The rows sh prints for the line that starts the
// here-document match both its own expectation and the next one in the same batch of output, so
// the next one completes before the main thread gets around to typing its text.
class ShellIntegrationOfflineDotfileInstallerTests: XCTestCase {
    // See FakeShellIntegrationTerminal.defersMatchCompletions.
    class var defersMatchCompletions: Bool { false }

    private static let launchHelper = ShellIntegrationOfflineInstallerTests.launchHelper
    private static let bashDotfileAssignment = "IT2_INSTALLER_DOTFILE=$(if test -f ~/.bash_profile; then echo ~/.bash_profile; else echo ~/.profile; fi)\n"
    private static let bashIf = "if ! grep iterm2_shell_integration \"$IT2_INSTALLER_DOTFILE\"  > /dev/null 2>&1; then\n"
    private static let bashCat = "    cat <<-EOF >> \"$IT2_INSTALLER_DOTFILE\"\n\n"
    private static let bashSource = "test -e ~/.iterm2_shell_integration.bash && source ~/.iterm2_shell_integration.bash || true\n"
    private static let fiLine = "fi; echo it2-\"\"dotfile-done\n"

    private var controller: iTermShellIntegrationWindowController!
    private var terminal: FakeShellIntegrationTerminal!

    override func setUp() {
        super.setUp()
        terminal = FakeShellIntegrationTerminal(testCase: self)
        terminal.defersMatchCompletions = Self.defersMatchCompletions
        controller = iTermShellIntegrationWindowController(windowNibName: "iTermShellIntegrationWindowController")
        controller.delegate = terminal
        XCTAssertNotNil(controller.window)
        controller.shellIntegrationInstallerSendShellCommands(-1)
    }

    override func tearDown() {
        controller.shellIntegrationInstallerCancelExpectations()
        controller.window?.orderOut(nil)
        controller = nil
        terminal = nil
        super.tearDown()
    }

    private func discover(parentProcess: String, shellPath: String, dotdirOutput: String? = nil) {
        terminal.responses[ShellIntegrationOfflineInstallerTests.shellCommand] = "My shell is \(parentProcess) or \(shellPath), end"
        if let dotdirOutput {
            terminal.responses["echo My dotfiles go in ${ZDOTDIR:-$HOME}, end\n"] = dotdirOutput
        }
        controller.shellIntegrationInstallerSendShellCommands(0)
        terminal.run()
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        // Skip writing the script to get to the dotfile step.
        controller.shellIntegrationInstallerSkipStage()
        XCTAssertEqual(controller.sendShellCommandsStage, 2)
    }

    private func dotfileCommandText() -> String {
        return controller.shellIntegrationInstallerNextCommandForSendShellCommands() ?? ""
    }

    func testBashDotfileCommandTypesTheSourceLine() {
        discover(parentProcess: "bash bash", shellPath: "/bin/zsh")
        XCTAssertEqual(controller.shell, .bash)
        XCTAssertEqual(dotfileCommandText(),
                       Self.launchHelper + Self.bashDotfileAssignment + Self.bashIf + Self.bashCat +
                       Self.bashSource + "EOF\nfi; echo it2-\"\"dotfile-done\nexit\n")
    }

    func testZshDotfileCommandTypesTheSourceLine() {
        discover(parentProcess: "zsh -zsh", shellPath: "/bin/zsh", dotdirOutput: "My dotfiles go in /Users/someone, end")
        XCTAssertEqual(controller.shell, .zsh)
        XCTAssertEqual(dotfileCommandText(),
                       Self.launchHelper +
                       "if ! grep iterm2_shell_integration /Users/someone/.zshrc  > /dev/null 2>&1; then\n" +
                       "    cat <<-EOF >> /Users/someone/.zshrc\n\n" +
                       "test -e /Users/someone/.iterm2_shell_integration.zsh && source /Users/someone/.iterm2_shell_integration.zsh || true\n" +
                       "EOF\nfi; echo it2-\"\"dotfile-done\nexit\n")
    }

    func testTcshDotfileCommandTypesTheSourceLine() {
        discover(parentProcess: "tcsh -csh", shellPath: "/bin/zsh")
        XCTAssertEqual(controller.shell, .tcsh)
        XCTAssertEqual(dotfileCommandText(),
                       Self.launchHelper +
                       "if ! grep iterm2_shell_integration ~/.login  > /dev/null 2>&1; then\n" +
                       "    cat <<-EOF >> ~/.login\n\n" +
                       "test -e ~/.iterm2_shell_integration.tcsh && source ~/.iterm2_shell_integration.tcsh || true\n" +
                       "EOF\nfi; echo it2-\"\"dotfile-done\nexit\n")
    }

    func testFishDotfileCommandTypesTheSourceLine() {
        discover(parentProcess: "fish fish", shellPath: "/opt/homebrew/bin/fish")
        XCTAssertEqual(controller.shell, .fish)
        XCTAssertEqual(dotfileCommandText(),
                       Self.launchHelper +
                       "mkdir -p ~/.config/fish\n" +
                       "if ! grep iterm2_shell_integration ~/.config/fish/config.fish  > /dev/null 2>&1; then\n" +
                       "    cat <<-EOF >> ~/.config/fish/config.fish\n\n" +
                       "test -e $HOME/.iterm2_shell_integration.fish ; and source $HOME/.iterm2_shell_integration.fish ; or true\n" +
                       "EOF\nfi; echo it2-\"\"dotfile-done\nexit\n")
    }

    // xonsh and nushell load the script from where it was written, so there is no dotfile step.
    func testXonshHasNoDotfileCommand() {
        discover(parentProcess: "python3 xonsh", shellPath: "/opt/homebrew/bin/xonsh")
        XCTAssertEqual(controller.shell, .xonsh)
        XCTAssertEqual(dotfileCommandText(), "")
    }

    // sh echoes the line that starts the here-document and then the empty line after it. The
    // first row answers that line's expectation and the second answers the next one, whose text
    // is the source line, before the main thread has typed it. The source line must be typed
    // anyway, and before EOF.
    func testBashDotfileStepTypesTheSourceLineWhenItsExpectationIsAnsweredEarly() {
        discover(parentProcess: "bash bash", shellPath: "/bin/zsh")
        terminal.responseLines[Self.launchHelper] = [">> "]
        terminal.responseLines[Self.bashDotfileAssignment + Self.bashIf] = [
            ">> IT2_INSTALLER_DOTFILE=$(if test -f ~/.bash_profile; then echo ~/.bash_profile; else echo ~/.profile; fi)",
            ">> if ! grep iterm2_shell_integration \"$IT2_INSTALLER_DOTFILE\"  > /dev/null 2>&1; then"
        ]
        terminal.responseLines[Self.bashCat] = [">     cat <<-EOF >> \"$IT2_INSTALLER_DOTFILE\"", "> "]
        terminal.responseLines[Self.bashSource] = ["> test -e ~/.iterm2_shell_integration.bash && source ~/.iterm2_shell_integration.bash || true"]
        terminal.responseLines["EOF\n"] = ["> EOF"]
        terminal.responseLines[Self.fiLine] = ["> fi; echo it2-\"\"dotfile-done", "it2-dotfile-done", ">> "]
        terminal.responseLines[ShellIntegrationOfflineInstallerTests.typedExit] = [">> exit"]
        let discoveryCount = terminal.sentTexts.count

        // In the app the button click's autorelease pool drains before any output arrives, so
        // only the installer and the expect object keep the expectations alive. Do the same
        // here.
        autoreleasepool {
            controller.shellIntegrationInstallerSendShellCommands(2)
        }
        terminal.run()

        XCTAssertEqual(Array(terminal.sentTexts.dropFirst(discoveryCount)),
                       [Self.launchHelper,
                        Self.bashDotfileAssignment + Self.bashIf,
                        Self.bashCat,
                        Self.bashSource,
                        "EOF\n",
                        Self.fiLine,
                        ShellIntegrationOfflineInstallerTests.typedExit])
        XCTAssertEqual(controller.sendShellCommandsStage, 3)
    }
}

// F-462: runs the command with which the helper sh receives and unpacks the utilities in real
// POSIX shells, in the utilities folder, as the installer types it.
final class ShellIntegrationReceiveUtilitiesCommandTests: XCTestCase {
    private static let shells = ["/bin/sh", "/bin/dash"]
    private var home: URL!
    private var folder: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        folder = home.appendingPathComponent(".iterm2")
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }
        try? FileManager.default.removeItem(at: home)
        try super.tearDownWithError()
    }

    private func makeFolder(writable: Bool = true) throws {
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }
        try? FileManager.default.removeItem(at: home)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !writable {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        }
    }

    private func encodedArchiveLines() throws -> [String] {
        let bundle = Bundle(for: iTermShellIntegrationWindowController.self)
        let url = try XCTUnwrap(bundle.url(forResource: "utilities", withExtension: "tgz"))
        let data = try Data(contentsOf: url)
        return data.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
            .components(separatedBy: "\n")
    }

    // Runs the command in an interactive sh, like the helper, with `input` as what is typed
    // after it, and returns what sh printed.
    private func run(_ shell: String, input: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-i", "-c", iTermShellIntegrationWindowController.receiveUtilitiesCommand]
        process.currentDirectoryURL = folder
        process.environment = ["ENV": "/dev/null", "HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let stdin = Pipe()
        let output = Pipe()
        process.standardInput = stdin
        process.standardOutput = output
        process.standardError = output
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func leftoverTemporaryFiles() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix(".it2-utilities") }
    }

    func testInstallsTheArchive() throws {
        for shell in Self.shells {
            try makeFolder()
            let input = try encodedArchiveLines().joined(separator: "\n") + "\nEOF\n"
            let output = try run(shell, input: input)

            XCTAssertTrue(output.contains("it2-receiving-utilities"), "\(shell): \(output)")
            XCTAssertTrue(output.contains("it2-utilities-installed"), "\(shell): \(output)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("it2check").path), shell)
            XCTAssertEqual(leftoverTemporaryFiles(), [], shell)
        }
    }

    // The read loop's file can't be created, so sh must not say it is receiving: iTerm2 would
    // then type the archive into its prompt.
    func testDoesNotReceiveWhenTheFolderIsNotWritable() throws {
        for shell in Self.shells {
            try makeFolder(writable: false)
            let output = try run(shell, input: "EOF\n")

            XCTAssertTrue(output.contains("it2-cannot-receive-utilities"), "\(shell): \(output)")
            XCTAssertFalse(output.contains("it2-receiving-utilities"), "\(shell): \(output)")
            XCTAssertFalse(output.contains("it2-utilities-installed"), "\(shell): \(output)")
        }
    }

    // tar given no input at all succeeds, so that must not count as installed.
    func testEmptyArchiveFails() throws {
        for shell in Self.shells {
            try makeFolder()
            let output = try run(shell, input: "EOF\n")

            XCTAssertTrue(output.contains("it2-utilities-failed"), "\(shell): \(output)")
            XCTAssertFalse(output.contains("it2-utilities-installed"), "\(shell): \(output)")
            XCTAssertEqual(leftoverTemporaryFiles(), [], shell)
        }
    }

    func testTruncatedArchiveFails() throws {
        for shell in Self.shells {
            try makeFolder()
            let lines = try encodedArchiveLines()
            let input = lines.prefix(lines.count / 2).joined(separator: "\n") + "\nEOF\n"
            let output = try run(shell, input: input)

            XCTAssertTrue(output.contains("it2-utilities-failed"), "\(shell): \(output)")
            XCTAssertFalse(output.contains("it2-utilities-installed"), "\(shell): \(output)")
            XCTAssertEqual(leftoverTemporaryFiles(), [], shell)
        }
    }

    // F-463: Cancel can stop typing the archive partway. tar would unpack the files before the
    // cut and part of the one at it, overwriting good copies, so nothing may be unpacked.
    func testMostOfTheArchiveUnpacksNothing() throws {
        for shell in Self.shells {
            try makeFolder()
            let lines = try encodedArchiveLines()
            let input = lines.prefix(lines.count * 9 / 10).joined(separator: "\n") + "\nEOF\n"
            let output = try run(shell, input: input)

            XCTAssertTrue(output.contains("it2-utilities-failed"), "\(shell): \(output)")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [], shell)
        }
    }

    // T-130: runs the command that enters the utilities folder in `directory`.
    private func runChangeToFolder(_ shell: String, in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        let command = iTermShellIntegrationWindowController.commandToEnterUtilitiesFolder(folder.path)
        process.arguments = ["-i", "-c", command]
        process.currentDirectoryURL = directory
        process.environment = ["ENV": "/dev/null", "HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let output = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    func testChangeToFolderSaysDoneWhenItEntersTheFolder() throws {
        for shell in Self.shells {
            try makeFolder()
            let output = try runChangeToFolder(shell, in: home)

            XCTAssertTrue(output.contains("it2-cd-done"), "\(shell): \(output)")
            XCTAssertFalse(output.contains("it2-cd-failed"), "\(shell): \(output)")
        }
    }

    // T-130: ~/.iterm2 is a file, so cd fails. It must not say it is done, or the archive would
    // be unpacked in the folder sh is in.
    func testChangeToFolderSaysFailedWhenTheFolderIsAFile() throws {
        for shell in Self.shells {
            try? FileManager.default.removeItem(at: home)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            XCTAssertTrue(FileManager.default.createFile(atPath: folder.path, contents: Data("x".utf8)))
            let output = try runChangeToFolder(shell, in: home)

            XCTAssertTrue(output.contains("it2-cd-failed"), "\(shell): \(output)")
            XCTAssertFalse(output.contains("it2-cd-done"), "\(shell): \(output)")
            try FileManager.default.removeItem(at: folder)
        }
    }

    func testChangeToFolderCommandDoesNotContainItsAnswers() {
        let command = iTermShellIntegrationWindowController.commandToEnterUtilitiesFolder("/x/.iterm2")
        XCTAssertFalse(command.contains("it2-cd-done"))
        XCTAssertFalse(command.contains("it2-cd-failed"))
    }

    // sh echoes the typed command, and the echo must not look like any of its answers.
    func testCommandDoesNotContainItsAnswers() {
        let command = iTermShellIntegrationWindowController.receiveUtilitiesCommand
        for answer in ["it2-receiving-utilities", "it2-cannot-receive-utilities",
                       "it2-utilities-installed", "it2-utilities-failed"] {
            XCTAssertFalse(command.contains(answer), answer)
        }
    }
}

// F-880: runs the command with which the helper sh receives and writes the shell integration
// script in real POSIX shells, as the installer types it.
final class ShellIntegrationReceiveScriptCommandTests: XCTestCase {
    private static let shells = ["/bin/sh", "/bin/dash"].filter { FileManager.default.isExecutableFile(atPath: $0) }
    private var folder: URL!
    private var path: String { folder.appendingPathComponent(".iterm2_shell_integration.bash").path }

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        try super.tearDownWithError()
    }

    // The bundled bash script, whose longest line is longer than any tty keeps in canonical mode.
    private func script() throws -> Data {
        let bundle = Bundle(for: iTermShellIntegrationWindowController.self)
        let url = try XCTUnwrap(bundle.url(forResource: "iterm2_shell_integration", withExtension: "bash"))
        return try Data(contentsOf: url)
    }

    // Runs the command in an interactive sh, like the helper, with `input` as what is typed after
    // it, and returns what sh printed.
    private func run(_ shell: String, command: String, input: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-i", "-c", command]
        process.currentDirectoryURL = folder
        process.environment = ["ENV": "/dev/null", "HOME": folder.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let stdin = Pipe()
        let output = Pipe()
        process.standardInput = stdin
        process.standardOutput = output
        process.standardError = output
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func leftoverTemporaryFiles() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.contains(".it2-") }
    }

    func testChecksumIsTheOneCksumPrints() throws {
        for data in [Data(), Data("a".utf8), try script()] {
            let file = folder.appendingPathComponent("data")
            try data.write(to: file)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/cksum")
            process.arguments = [file.path]
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            let words = printed.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            XCTAssertEqual(iTermShellIntegrationWindowController.posixChecksum(of: data),
                           words.prefix(2).joined(separator: " "))
        }
    }

    func testWritesTheWholeScript() throws {
        let script = try script()
        let command = iTermShellIntegrationWindowController.commandToReceiveScript(script, at: path)
        for shell in Self.shells {
            try? FileManager.default.removeItem(atPath: path)
            let output = try run(shell, command: command, input: iTermShellIntegrationWindowController.textToSend(script))

            XCTAssertTrue(output.contains("it2-receiving-script"), "\(shell): \(output)")
            XCTAssertTrue(output.contains("it2-script-written"), "\(shell): \(output)")
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), script, shell)
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path), shell)
            XCTAssertEqual(leftoverTemporaryFiles(), [], shell)
        }
    }

    // The path is typed as the installer has it, which for most shells starts with ~.
    func testWritesToAPathUnderTheHomeDirectory() throws {
        let script = try script()
        let command = iTermShellIntegrationWindowController.commandToReceiveScript(script, at: "~/.iterm2_shell_integration.bash")
        for shell in Self.shells {
            try? FileManager.default.removeItem(atPath: path)
            let output = try run(shell, command: command, input: iTermShellIntegrationWindowController.textToSend(script))

            XCTAssertTrue(output.contains("it2-script-written"), "\(shell): \(output)")
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), script, shell)
            XCTAssertEqual(leftoverTemporaryFiles(), [], shell)
        }
    }

    // A script cut short, as when a tty drops the end of a long line or Cancel stops typing it,
    // must not replace the one there.
    func testPartialScriptIsNotWritten() throws {
        let script = try script()
        let command = iTermShellIntegrationWindowController.commandToReceiveScript(script, at: path)
        var lines = iTermShellIntegrationWindowController.textToSend(script).components(separatedBy: "\n")
        lines.remove(at: lines.count / 2)
        for shell in Self.shells {
            try Data("old".utf8).write(to: URL(fileURLWithPath: path))
            for input in ["EOF\n", lines.joined(separator: "\n")] {
                let output = try run(shell, command: command, input: input)

                XCTAssertTrue(output.contains("it2-script-failed"), "\(shell): \(output)")
                XCTAssertFalse(output.contains("it2-script-written"), "\(shell): \(output)")
                XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "old", shell)
                XCTAssertEqual(leftoverTemporaryFiles(), [], shell)
            }
        }
    }

    // The file to read the script into can't be created, so sh must not say it is receiving:
    // iTerm2 would then type the script into its prompt.
    func testDoesNotReceiveWhenTheFolderIsMissing() throws {
        let script = try script()
        let missing = folder.appendingPathComponent("missing/script").path
        let command = iTermShellIntegrationWindowController.commandToReceiveScript(script, at: missing)
        for shell in Self.shells {
            let output = try run(shell, command: command, input: "EOF\n")

            XCTAssertTrue(output.contains("it2-cannot-receive-script"), "\(shell): \(output)")
            XCTAssertFalse(output.contains("it2-receiving-script"), "\(shell): \(output)")
            XCTAssertFalse(output.contains("it2-script-written"), "\(shell): \(output)")
        }
    }

    // sh echoes the typed command, and the echo must not look like any of its answers. It must
    // also be short enough for a tty in canonical mode to keep, even with a long path.
    func testCommandIsShortAndDoesNotContainItsAnswers() throws {
        let longPath = "/home/" + String(repeating: "x", count: 64) + "/.iterm2_shell_integration.bash"
        let command = iTermShellIntegrationWindowController.commandToReceiveScript(try script(), at: longPath)
        for answer in ["it2-receiving-script", "it2-cannot-receive-script",
                       "it2-script-written", "it2-script-failed"] {
            XCTAssertFalse(command.contains(answer), answer)
        }
        XCTAssertLessThan(command.utf8.count, 1024)
        XCTAssertLessThan(longestTypedLine([iTermShellIntegrationWindowController.textToSend(try script())]), 80)
    }
}

// The same tests with expectations completed in the order the app can complete them: the next
// command is typed before the completion of the expectation that matched runs.
final class ShellIntegrationOfflineTcshFromZshDeferredCompletionInstallerTests: ShellIntegrationOfflineTcshFromZshInstallerTests {
    override class var defersMatchCompletions: Bool { true }
}

final class ShellIntegrationOfflineDashDeferredCompletionInstallerTests: ShellIntegrationOfflineTcshFromZshInstallerTests {
    override class var defersMatchCompletions: Bool { true }
    override class var shEchoesTypeahead: Bool { false }
}

final class ShellIntegrationOfflineDotfileDeferredCompletionInstallerTests: ShellIntegrationOfflineDotfileInstallerTests {
    override class var defersMatchCompletions: Bool { true }
}

// F-870, F-882: starts the helper shell in real dash, the sh of Debian and Ubuntu, in a pty,
// typing the launch the way it reaches a user's shell whose line editor has the tty in raw mode,
// and checks that what the installer waits for shows up.
final class ShellIntegrationHelperLaunchInDashTests: XCTestCase {
    private static let dash = "/bin/dash"
    private var binDirectory: URL!
    private var master: Int32 = -1
    private var process: Process?
    private var output = ""
    // Puts the tty in canonical mode once the helper prompted. See launchHelpers(exportedPS1:).
    private var restoreCanonicalMode: (() -> Void)?

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard FileManager.default.isExecutableFile(atPath: Self.dash) else {
            throw XCTSkip("No \(Self.dash)")
        }
        // The launch runs sh from PATH. Make it dash.
        binDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: binDirectory.appendingPathComponent("sh").path,
                                                   withDestinationPath: Self.dash)
    }

    override func tearDownWithError() throws {
        restoreCanonicalMode?()
        // Closing the master hangs up the tty, which ends shells that are still running.
        if master >= 0 {
            close(master)
            master = -1
        }
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        if let binDirectory {
            try? FileManager.default.removeItem(at: binDirectory)
        }
        try super.tearDownWithError()
    }

    private func type(_ text: String) {
        let bytes = Array(text.utf8)
        XCTAssertEqual(write(master, bytes, bytes.count), bytes.count)
    }

    private func rows() -> [String] {
        return output.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
    }

    // Reads what the shells print until a row, partial ones too, from the firstRow'th on matches
    // regex. The timeout only bounds how long a failure takes.
    private func readUntilARowMatches(_ regex: String,
                                      from firstRow: Int = 0,
                                      timeout: TimeInterval = 30) throws -> String? {
        let re = try NSRegularExpression(pattern: regex)
        let deadline = Date(timeIntervalSinceNow: timeout)
        while true {
            if let row = rows().dropFirst(firstRow).first(where: { re.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }) {
                return row
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                return nil
            }
            var pfd = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, Int32(min(remaining, 1) * 1000)) > 0 else {
                continue
            }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let n = read(master, &buffer, buffer.count)
            if n <= 0 {
                return nil
            }
            output += String(decoding: buffer[0..<n], as: UTF8.self)
        }
    }

    // Types the launch ahead in raw mode, as while the user's line editor reads its first line,
    // then turns echo on, as the line editor does before it runs a command, and starts a shell
    // that reads the first line and runs it.
    //
    // F-882: when the line editor puts the tty back in canonical mode, Linux hands everything
    // still queued to the next read() as one line, so the first shell the launch starts reads
    // all of what was typed after the line that started it. Canonical mode stays off until the
    // helper prompts so macOS's tty, which splits the queued text into lines, does the same.
    private func launchHelpers(exportedPS1: String?) throws {
        var slave: Int32 = -1
        XCTAssertEqual(openpty(&master, &slave, nil, nil, nil), 0)
        var attributes = termios()
        XCTAssertEqual(tcgetattr(slave, &attributes), 0)
        let canonical = attributes
        attributes.c_lflag &= ~tcflag_t(ECHO | ICANON)
        XCTAssertEqual(tcsetattr(slave, TCSANOW, &attributes), 0)
        type(ShellIntegrationOfflineInstallerTests.launchHelper)
        attributes.c_lflag |= tcflag_t(ECHO)
        XCTAssertEqual(tcsetattr(slave, TCSANOW, &attributes), 0)
        let master = self.master
        restoreCanonicalMode = { [weak self] in
            var attributes = canonical
            XCTAssertEqual(tcsetattr(master, TCSANOW, &attributes), 0)
            self?.restoreCanonicalMode = nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.dash)
        process.arguments = ["-c", "read -r line; eval \"$line\""]
        var environment = ["PATH": binDirectory.path + ":/usr/bin:/bin:/usr/sbin:/sbin",
                           "HOME": NSHomeDirectory(),
                           "TERM": "xterm"]
        if let exportedPS1 {
            environment["PS1"] = exportedPS1
        }
        process.environment = environment
        let handle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput = handle
        process.standardOutput = handle
        process.standardError = handle
        defer {
            // The shells have their own copies. Without this one, closing the master ends them.
            close(slave)
        }
        try process.run()
        self.process = process
    }

    private func checkHelpers(exportedPS1: String?) throws {
        try launchHelpers(exportedPS1: exportedPS1)

        XCTAssertNotNil(try readUntilARowMatches(iTermShellIntegrationWindowController.helperPromptRegex), output)
        restoreCanonicalMode?()

        // What the installer types once the helpers prompted is echoed, and gets its answers.
        // Only rows after the one the text is typed on count, since that one already has a
        // prompt.
        var next = rows().count
        type(ShellIntegrationOfflineInstallerTests.helperDepthCommand)
        XCTAssertNotNil(try readUntilARowMatches("it2-helper-depth-1-", from: next), output)
        next = rows().count
        type("echo \"it2-\"\"helpers-$PS1-idle\"\n")
        XCTAssertNotNil(try readUntilARowMatches("it2-helpers->> -idle", from: next), output)
        next = rows().count
        type("true\n")
        XCTAssertNotNil(try readUntilARowMatches("^>> (?![\"'])", from: next), output)

        // The script, as the script step sends it. F-880: one of its lines is longer than the
        // tty keeps in canonical mode, which is how dash reads it.
        let path = binDirectory.appendingPathComponent("script").path
        let script = Data(((1...20).map { "line \($0) of the script" } +
                           [String(repeating: "long line ", count: 1000)]).joined(separator: "\n").utf8 + [0x0a])
        next = rows().count
        type(iTermShellIntegrationWindowController.commandToReceiveScript(script, at: path))
        XCTAssertNotNil(try readUntilARowMatches("it2-receiving-script", from: next), output)
        next = rows().count
        // Typed from another thread while this one reads what the tty echoes, since the tty's
        // buffers are smaller than the text.
        let bytes = Array(iTermShellIntegrationWindowController.textToSend(script).utf8)
        let master = self.master
        // It asserts nothing itself, since the test can be over (and the master closed) if it
        // failed: the expectation is fulfilled only once all of the text was written.
        let typed = expectation(description: "The script was typed")
        DispatchQueue.global().async {
            var offset = 0
            while offset < bytes.count {
                let n = bytes[offset...].withUnsafeBufferPointer { write(master, $0.baseAddress, $0.count) }
                if n <= 0 {
                    return
                }
                offset += n
            }
            typed.fulfill()
        }
        XCTAssertNotNil(try readUntilARowMatches("it2-script-(written|failed)", from: next), output)
        wait(for: [typed], timeout: 30)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), script)
        XCTAssertNotNil(rows().first { $0.contains("it2-script-written") }, output)

        type("exit\n")
        let exited = expectation(description: "The shells exited")
        let process = self.process
        DispatchQueue.global().async {
            process?.waitUntilExit()
            exited.fulfill()
        }
        wait(for: [exited], timeout: 30)
    }

    func testHelperStartsInDash() throws {
        try checkHelpers(exportedPS1: nil)
    }

    // With bash's PS1 exported, which dash would show literally, the helper still gets its own.
    func testHelperStartsInDashWithAnExportedPS1() throws {
        try checkHelpers(exportedPS1: "\\[\\e]0;\\u@\\h: \\w\\a\\]\\u@\\h:\\w\\$ ")
    }
}
