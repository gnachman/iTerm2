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

private final class FakeShellIntegrationTerminal: NSObject, iTermShellIntegrationWindowControllerDelegate {
    let dryExpect = iTermExpect(dry: true)
    private var wetExpect: iTermExpect?
    private(set) var sentTexts = [String]()
    private var unansweredTexts = [String]()
    private let testCase: XCTestCase
    // Maps a command the installer types to the line the shell prints in response.
    var responses = [String: String]()

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

    // The shell prints a line. The mutation thread checks it against the current wet copy.
    private func output(_ line: String) {
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
        for _ in 0..<20 {
            sync()
            if unansweredTexts.isEmpty {
                return
            }
            while !unansweredTexts.isEmpty {
                let text = unansweredTexts.removeFirst()
                if let response = responses[text] {
                    output(response)
                }
            }
        }
        XCTFail("Installer kept typing commands")
    }
}

final class ShellIntegrationOfflineInstallerTests: XCTestCase {
    private static let shellCommand = "echo My shell is $SHELL\n"
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

    private func discover(shellPath: String, dotdirOutput: String?) {
        terminal.responses[Self.shellCommand] = "My shell is \(shellPath)"
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
