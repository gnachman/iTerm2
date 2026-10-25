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

    init(testCase: XCTestCase) {
        self.testCase = testCase
    }

    func shellIntegrationWindowControllerSendText(_ text: String) {
        sentTexts.append(text)
        unansweredTexts.append(text)
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
            expectation.didMatch(withCaptureGroups: captures) { closure in
                closure()
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
            let line = String(pendingInput[..<newline])
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
        if line.hasPrefix("sh -c 'ENV=/dev/null") {
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
        } else if line.hasPrefix("if test $? -eq 0 && test -s ") {
            let written = lastStatus == 0 && !(files[Self.scriptPath] ?? "").isEmpty
            result.append(written ? "iTerm2-nu-script-written" : "iTerm2-nu-script-missing")
            prompt = ">> "
        } else if line.hasPrefix("chmod +x ") {
            let path = expand(String(line.dropFirst("chmod +x ".count)))
            if files[path] == nil {
                result.append("chmod: \(path): No such file or directory")
            }
            prompt = ">> "
        } else if line.hasPrefix("mkdir ") || line.hasPrefix("cd "), let range = line.range(of: "; echo ") {
            result.append(line[range.upperBound...].replacingOccurrences(of: "\"", with: ""))
            prompt = ">> "
        } else if line.hasPrefix("sh -c 'ENV=/dev/null") {
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
            let line = String(pendingInput[..<newline])
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
        if line.hasPrefix("sh -c 'ENV=/dev/null") {
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
        } else if line.hasPrefix("chmod +x ") {
            let path = String(line.dropFirst("chmod +x ".count))
            if files[path] == nil {
                result.append("chmod: \(path): No such file or directory")
            }
        } else if line.hasPrefix("mkdir ") || line.hasPrefix("cd "), let range = line.range(of: "; echo ") {
            result.append(line[range.upperBound...].replacingOccurrences(of: "\"", with: ""))
        } else if line.hasPrefix("sh -c 'ENV=/dev/null") {
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
    static let shellCommand = "sh -c 'echo My shell is $(ps -o ucomm=,comm= -p $PPID 2>/dev/null || ps -o comm= -p $PPID 2>/dev/null) or $SHELL, end'\n"
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

    // F-436: writing the script starts a helper sh and then, from within it, a nested one. The
    // nested launch must wait for output from the outer helper, not be typed at the same time.
    func testWriteScriptTypesOneThingUntilTheShellResponds() {
        discover(shellPath: "/bin/zsh", dotdirOutput: "My dotfiles go in /Users/someone, end")
        let discoveryCount = terminal.sentTexts.count

        controller.shellIntegrationInstallerSendShellCommands(1)
        terminal.run()

        let typed = Array(terminal.sentTexts.dropFirst(discoveryCount))
        XCTAssertEqual(typed, ["sh\nENV=/dev/null INPUTRC=/dev/null sh\n PS1='>> '; PS2='> '\n"])
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
            XCTAssertTrue(texts[0].hasPrefix("sh -c 'ENV=/dev/null"), texts[0])
            XCTAssertTrue(texts[1].hasPrefix("IT2_NU_AUTOLOAD_DIR="), texts[1])
            XCTAssertTrue(texts[1].contains("mkdir -p \"$IT2_NU_AUTOLOAD_DIR\""), texts[1])
            XCTAssertEqual(texts[2], "cat <<'EOF' > \"$IT2_NU_AUTOLOAD_DIR/iterm2_shell_integration.nu\"\n")
            XCTAssertTrue(texts[3].contains("\nEOF\nif test $? -eq 0 && test -s "), texts[3])
            XCTAssertEqual(texts[4], "exit\n")
        }
        let script = terminal.files[FakeNushellTerminal.scriptPath] ?? ""
        let bundled = bundledScript()
        XCTAssertFalse(bundled.isEmpty)
        XCTAssertTrue(script.hasPrefix(bundled), script)
        XCTAssertFalse(script.contains("mkdir"), script)
        XCTAssertFalse(terminal.helperIsRunning)
        XCTAssertEqual(controller.sendShellCommandsStage, 2)
        XCTAssertFalse(controller.sendShellCommandsWriteFailed)
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
        XCTAssertEqual(terminal.sentTexts.last, "exit\n")
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
    private static let curlCommand = "\ncurl -L https://iterm2.com/shell_integration/install_shell_integration.sh | bash\n"
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
    private var heredocLines: [String]?
    private var receivingUtilities = false

    private(set) var heredocBodies = [[String]]()
    // Set to make tar fail to extract the utilities archive, as for one damaged on the way.
    var extractionFails = false
    // Set to make sh unable to create the file the archive goes into, as in a folder that is
    // not writable.
    var receiveFails = false

    var helperIsRunning: Bool {
        return depth > 0
    }

    override func respond(to text: String) -> [String] {
        pendingInput += text
        var rows = [String]()
        while let newline = pendingInput.firstIndex(of: "\n") {
            let line = String(pendingInput[..<newline])
            pendingInput = String(pendingInput[pendingInput.index(after: newline)...])
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

    // What the shell prints when it gets to a line: in sh, the line editor's redraw of its prompt
    // and the line it read, then the command's output and the next prompt.
    private func handle(_ line: String) -> [String] {
        if depth == 0 {
            if line == "sh" {
                depth = 1
                prompt = "$ "
                return [prompt]
            }
            return super.respond(to: line + "\n") + ["> "]
        }
        let redraw = prompt + line
        if var lines = heredocLines {
            if line == "EOF" {
                heredocBodies.append(lines)
                heredocLines = nil
                prompt = ">> "
                if receivingUtilities {
                    receivingUtilities = false
                    let answer = extractionFails ? "it2-utilities-failed" : "it2-utilities-installed"
                    return [redraw, answer, prompt]
                }
            } else {
                lines.append(line)
                heredocLines = lines
            }
            return [redraw, prompt]
        }
        var result = [redraw]
        if line.hasPrefix("ENV=/dev/null") {
            depth += 1
            prompt = "$ "
        } else if line.hasPrefix(" PS1=") {
            prompt = ">> "
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
        } else if line.contains("<<'EOF'") {
            heredocLines = []
            prompt = "> "
        } else if line == "exit" {
            depth -= 1
            if depth == 0 {
                return [redraw, "> "]
            }
            prompt = depth == 1 ? "$ " : ">> "
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
final class ShellIntegrationOfflineTcshFromZshInstallerTests: XCTestCase {
    private var controller: iTermShellIntegrationWindowController!
    private var terminal: FakeTcshFromZshTerminal!

    override func setUp() {
        super.setUp()
        terminal = FakeTcshFromZshTerminal(testCase: self)
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
}

// F-353: the dotfile step for bash. The rows sh prints for the line that starts the
// here-document match both its own expectation and the next one in the same batch of output, so
// the next one completes before the main thread gets around to typing its text.
final class ShellIntegrationOfflineDotfileInstallerTests: XCTestCase {
    private static let launchHelper = "sh\nENV=/dev/null INPUTRC=/dev/null sh\n PS1='>> '; PS2='> '\n"
    private static let bashDotfileAssignment = "IT2_INSTALLER_DOTFILE=$(if test -f ~/.bash_profile; then echo ~/.bash_profile; else echo ~/.profile; fi)\n"
    private static let bashIf = "if ! grep iterm2_shell_integration \"$IT2_INSTALLER_DOTFILE\"  > /dev/null 2>&1; then\n"
    private static let bashCat = "    cat <<-EOF >> \"$IT2_INSTALLER_DOTFILE\"\n\n"
    private static let bashSource = "test -e ~/.iterm2_shell_integration.bash && source ~/.iterm2_shell_integration.bash || true\n"

    private var controller: iTermShellIntegrationWindowController!
    private var terminal: FakeShellIntegrationTerminal!

    override func setUp() {
        super.setUp()
        terminal = FakeShellIntegrationTerminal(testCase: self)
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
                       Self.bashSource + "EOF\nfi\nexit\nexit\n")
    }

    func testZshDotfileCommandTypesTheSourceLine() {
        discover(parentProcess: "zsh -zsh", shellPath: "/bin/zsh", dotdirOutput: "My dotfiles go in /Users/someone, end")
        XCTAssertEqual(controller.shell, .zsh)
        XCTAssertEqual(dotfileCommandText(),
                       Self.launchHelper +
                       "if ! grep iterm2_shell_integration /Users/someone/.zshrc  > /dev/null 2>&1; then\n" +
                       "    cat <<-EOF >> /Users/someone/.zshrc\n\n" +
                       "test -e /Users/someone/.iterm2_shell_integration.zsh && source /Users/someone/.iterm2_shell_integration.zsh || true\n" +
                       "EOF\nfi\nexit\nexit\n")
    }

    func testTcshDotfileCommandTypesTheSourceLine() {
        discover(parentProcess: "tcsh -csh", shellPath: "/bin/zsh")
        XCTAssertEqual(controller.shell, .tcsh)
        XCTAssertEqual(dotfileCommandText(),
                       Self.launchHelper +
                       "if ! grep iterm2_shell_integration ~/.login  > /dev/null 2>&1; then\n" +
                       "    cat <<-EOF >> ~/.login\n\n" +
                       "test -e ~/.iterm2_shell_integration.tcsh && source ~/.iterm2_shell_integration.tcsh || true\n" +
                       "EOF\nfi\nexit\nexit\n")
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
                       "EOF\nfi\nexit\nexit\n")
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
        terminal.responseLines[Self.launchHelper + Self.bashDotfileAssignment] = [
            ">> IT2_INSTALLER_DOTFILE=$(if test -f ~/.bash_profile; then echo ~/.bash_profile; else echo ~/.profile; fi)"
        ]
        terminal.responseLines[Self.bashIf] = [">> if ! grep iterm2_shell_integration \"$IT2_INSTALLER_DOTFILE\"  > /dev/null 2>&1; then"]
        terminal.responseLines[Self.bashCat] = [">     cat <<-EOF >> \"$IT2_INSTALLER_DOTFILE\"", "> "]
        terminal.responseLines[Self.bashSource] = ["> test -e ~/.iterm2_shell_integration.bash && source ~/.iterm2_shell_integration.bash || true"]
        terminal.responseLines["EOF\n"] = ["> EOF"]
        terminal.responseLines["fi\n"] = ["> fi", ">> "]
        terminal.responseLines["exit\nexit\n"] = [">> exit"]
        let discoveryCount = terminal.sentTexts.count

        // In the app the button click's autorelease pool drains before any output arrives, so
        // only the installer and the expect object keep the expectations alive. Do the same
        // here.
        autoreleasepool {
            controller.shellIntegrationInstallerSendShellCommands(2)
        }
        terminal.run()

        XCTAssertEqual(Array(terminal.sentTexts.dropFirst(discoveryCount)),
                       [Self.launchHelper + Self.bashDotfileAssignment,
                        Self.bashIf,
                        Self.bashCat,
                        Self.bashSource,
                        "EOF\n",
                        "fi\n",
                        "exit\nexit\n"])
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

    // sh echoes the typed command, and the echo must not look like any of its answers.
    func testCommandDoesNotContainItsAnswers() {
        let command = iTermShellIntegrationWindowController.receiveUtilitiesCommand
        for answer in ["it2-receiving-utilities", "it2-cannot-receive-utilities",
                       "it2-utilities-installed", "it2-utilities-failed"] {
            XCTAssertFalse(command.contains(answer), answer)
        }
    }
}
