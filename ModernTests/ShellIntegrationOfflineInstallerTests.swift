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
            return [echo, "My shell is \(Self.nuPath) or \(shellVariable), end", "~> "]
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
            let echo = "> " + line
            if line != "EOF" {
                heredoc.lines.append(line)
                self.heredoc = heredoc
                return [echo, "> "]
            }
            self.heredoc = nil
            guard let path = heredoc.path else {
                lastStatus = 0
                return [echo, ">> "]
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
        } else if line.contains("<<'EOF'") {
            heredoc = (path: nil, lines: [])
            prompt = "> "
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
        } else if line.hasPrefix("mkdir ") || line.hasPrefix("cd ") {
            result.append("ok")
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

final class ShellIntegrationOfflineInstallerTests: XCTestCase {
    static let shellCommand = "sh -c 'echo My shell is $(ps -o comm= -p $PPID 2>/dev/null) or $SHELL, end'\n"
    private static let zshDotdirCommand = "echo My dotfiles go in ${ZDOTDIR:-$HOME}\n"

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

    // parentProcess is what ps prints for the shell the commands are typed into: by default the
    // same shell as $SHELL, as a login shell (macOS ps prints its argv[0]).
    private func discover(shellPath: String, parentProcess: String? = nil, dotdirOutput: String?) {
        let parentProcess = parentProcess ?? "-" + (shellPath as NSString).lastPathComponent
        terminal.responses[Self.shellCommand] = "My shell is \(parentProcess) or \(shellPath), end"
        if let dotdirOutput {
            terminal.responses[Self.zshDotdirCommand] = dotdirOutput
        }
        controller.shellIntegrationInstallerSendShellCommands(0)
        terminal.run()
    }

    func testZshDiscoveryCompletesWithoutZDOTDIR() {
        discover(shellPath: "/bin/zsh", dotdirOutput: "My dotfiles go in /Users/someone")

        XCTAssertEqual(terminal.sentTexts, [Self.shellCommand, Self.zshDotdirCommand])
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .zsh)
        XCTAssertEqual(controller.dotdir, "/Users/someone")
    }

    func testZshDiscoveryCompletesWithZDOTDIR() {
        discover(shellPath: "/usr/local/bin/zsh", dotdirOutput: "My dotfiles go in /Users/someone/.config/zsh")

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .zsh)
        XCTAssertEqual(controller.dotdir, "/Users/someone/.config/zsh")
        let next = controller.shellIntegrationInstallerNextCommandForSendShellCommands() ?? ""
        XCTAssertTrue(next.contains("/Users/someone/.config/zsh/.iterm2_shell_integration.zsh"), next)
    }

    func testZshDiscoveryWithEmptyDotdirFallsBackToHome() {
        discover(shellPath: "/bin/zsh", dotdirOutput: "My dotfiles go in")

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .zsh)
        XCTAssertEqual(controller.dotdir, "$HOME")
        let next = controller.shellIntegrationInstallerNextCommandForSendShellCommands() ?? ""
        XCTAssertTrue(next.contains("$HOME/.iterm2_shell_integration.zsh"), next)
        XCTAssertFalse(next.contains("(null)"), next)
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
        discover(shellPath: "/bin/zsh", parentProcess: "/bin/tcsh", dotdirOutput: nil)

        XCTAssertEqual(terminal.sentTexts, [Self.shellCommand])
        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .tcsh)
        XCTAssertEqual(controller.dotdir, "~")
    }

    func testDiscoveryUsesALoginShellParent() {
        discover(shellPath: "/bin/zsh", parentProcess: "-fish", dotdirOutput: nil)

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .fish)
    }

    // xonsh runs under python, and ps may be missing on a remote host: an unknown or empty
    // parent falls back to $SHELL.
    func testDiscoveryFallsBackToSHELLForAnUnknownParent() {
        discover(shellPath: "/Users/someone/venv/bin/xonsh", parentProcess: "/usr/bin/python3", dotdirOutput: nil)

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
        terminal.responseLines[Self.shellCommand] = ["My shell is /bin/tc", "My shell is /bin/tcsh or /bin/zsh, end"]
        controller.shellIntegrationInstallerSendShellCommands(0)
        terminal.run()

        XCTAssertEqual(controller.sendShellCommandsStage, 1)
        XCTAssertEqual(controller.shell, .tcsh)
    }

    func testSkipDoesNotBypassDiscovery() {
        controller.shellIntegrationInstallerSkipStage()

        XCTAssertEqual(controller.sendShellCommandsStage, 0)
        let next = controller.shellIntegrationInstallerNextCommandForSendShellCommands() ?? ""
        XCTAssertEqual(next, Self.shellCommand)
        XCTAssertFalse(next.contains("(null)"), next)
    }

    func testSkipAfterDiscoveryUsesDiscoveredDotdir() {
        discover(shellPath: "/bin/zsh", dotdirOutput: "My dotfiles go in /Users/someone")
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

// nu started from a zsh login shell: $SHELL is zsh, but the commands go to nu, so every step
// must work without asking $SHELL for nu's autoload directory.
final class ShellIntegrationOfflineNushellFromZshInstallerTests: ShellIntegrationOfflineNushellInstallerTests {
    override class var shellVariable: String { "/bin/zsh" }
}
