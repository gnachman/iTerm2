//
//  SSHHookArgumentsTests.swift
//  ModernTests
//
//  F-608: it2ssh sends its ssh arguments as base64 of bash's `printf %q` output. macOS's
//  bash 3.2 quotes non-ASCII words as $'...' with raw lead bytes mixed among octal escapes,
//  which is not valid UTF-8. iTerm2 required UTF-8, ignored the hook, and the remote
//  bootstrap waited forever.
//

import XCTest
@testable import iTerm2SharedARC

final class SSHHookArgumentsTests: XCTestCase {
    private final class FakeHostnameFinder: SSHHostnameFinder {
        func sshHostname(forHost host: String) -> String { host }
    }

    private func parsed(_ normalized: String) -> ParsedSSHArguments {
        return ParsedSSHArguments(normalized, booleanArgs: "46AaCfGgKkMNnqsTtVvXxYy", hostnameFinder: FakeHostnameFinder())
    }

    // The payload logged in the QA report, from `it2ssh 192.168.64.3 printf '%s|' 'Ünï 😀'`
    // run by /bin/bash 3.2 in a UTF-8 locale.
    private let bash32UTF8Payload = "MTkyLjE2OC42NC4zIHByaW50ZiAlc1x8ICQnw1wyMzRuw68g8FwyMzdcMjMwXDIwMCcg"

    func testBash32PayloadIsNotUTF8() {
        let data = Data(base64Encoded: bash32UTF8Payload)!
        XCTAssertNil(String(data: data, encoding: .utf8))
    }

    func testBash32PayloadDecodesToOriginalWords() {
        let data = Data(base64Encoded: bash32UTF8Payload)!
        let normalized = SSHHookArguments.normalizedArguments(data)
        XCTAssertNotNil(normalized)
        XCTAssertEqual((normalized! as NSString).componentsInShellCommand(),
                       ["192.168.64.3", "printf", "%s|", "Ünï 😀"])
    }

    // The command the conductor sends to the remote must carry the original UTF-8 bytes.
    // ssh joins the command words with spaces and the remote shell reparses them, so
    // the remote command is the words joined with spaces, exactly as plain ssh sends it.
    func testRemoteCommandBytesEqualOriginalUTF8() {
        let data = Data(base64Encoded: bash32UTF8Payload)!
        let args = parsed(SSHHookArguments.normalizedArguments(data)!)
        XCTAssertEqual(args.host, "192.168.64.3")
        let command = args.commandArgs.joined(separator: " ")
        XCTAssertEqual(Array(command.utf8), Array("printf %s| Ünï 😀".utf8))

        let wire = Conductor.encodeForWire(.run(command), linePrefix: "")
        let decoded = Data(base64Encoded: wire.trimmingCharacters(in: .whitespacesAndNewlines))!
        XCTAssertEqual(Array(decoded), Array("run printf %s| Ünï 😀".utf8))
    }

    // In the C locale bash 3.2 escapes every non-ASCII byte as octal.
    func testAllOctalANSICQuoting() {
        let quoted = "host echo $'\\303\\234n\\303\\257 \\360\\237\\230\\200' "
        let normalized = SSHHookArguments.normalizedArguments(Data(quoted.utf8))
        XCTAssertEqual((normalized! as NSString).componentsInShellCommand(),
                       ["host", "echo", "Ünï 😀"])
    }

    func testEmojiOnlyWord() {
        // printf %q '😀' in bash 3.2: a raw lead byte followed by octal continuation bytes.
        let bytes: [UInt8] = Array("host echo $'".utf8) + [0xf0] + Array("\\237\\230\\200'".utf8)
        let normalized = SSHHookArguments.normalizedArguments(Data(bytes))
        let args = parsed(normalized!)
        XCTAssertEqual(Array(args.commandArgs.joined(separator: " ").utf8), Array("echo 😀".utf8))
    }

    func testASCIIQuotingForms() {
        let quoted = "host printf a\\ b x\\'y $'tab\\tx' \"dq \\\"z\\\"\" 'sq' '' "
        let normalized = SSHHookArguments.normalizedArguments(Data(quoted.utf8))
        XCTAssertEqual((normalized! as NSString).componentsInShellCommand(),
                       ["host", "printf", "a b", "x'y", "tab\tx", "dq \"z\"", "sq", ""])
    }

    func testOptionsAndPlainHostAreUnchanged() {
        let quoted = "-p 2222 -l george example.com "
        let normalized = SSHHookArguments.normalizedArguments(Data(quoted.utf8))!
        let args = parsed(normalized)
        XCTAssertEqual(args.host, "example.com")
        XCTAssertEqual(args.port, 2222)
        XCTAssertEqual(args.username, "george")
        XCTAssertEqual(args.commandArgs, [])
    }

    func testCharactersTheSplitterTreatsSpeciallyRoundTrip() {
        let words = ["host", "~", "a\\nb", "tab\tnew\nline", "$HOME", "\"q\"", "'", "\\", "n", "\u{00a0}nbsp"]
        let normalized = SSHHookArguments.quote(words: words)
        XCTAssertEqual((normalized as NSString).componentsInShellCommand(), words)
    }

    func testDisplayStringShowsControlCharacters() {
        let normalized = SSHHookArguments.quote(words: ["host", "echo", "\u{1b}[31m", "a\nb", "Ü"])
        XCTAssertEqual(SSHHookArguments.displayString(normalized), "host echo \\\\x1B\\[31m a'\\x0A'b Ü")
    }

    func testInvalidUTF8WordIsRejected() {
        // A Latin-1 byte that isn't valid UTF-8.
        let quoted = "host echo $'caf\\351' "
        XCTAssertNil(SSHHookArguments.normalizedArguments(Data(quoted.utf8)))
    }

    func testUnterminatedQuoteIsRejected() {
        XCTAssertNil(SSHHookArguments.normalizedArguments(Data("host echo 'abc ".utf8)))
        XCTAssertNil(SSHHookArguments.normalizedArguments(Data("host echo $'abc ".utf8)))
        XCTAssertNil(SSHHookArguments.normalizedArguments(Data("host echo \"abc ".utf8)))
    }

    // Quote real arguments with the bash that runs it2ssh and check they come back intact.
    func testRoundTripThroughSystemBash() throws {
        let words = ["example.com", "printf", "%s|", "Ünï 😀", "😀", "a b", "x'y", "tab\tx",
                     "new\nline", "~", "$HOME", "\"", "\\", "", "日本語", "ü"]
        for locale in ["en_US.UTF-8", "C"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", "printf '%q ' \"$@\"", "bash"] + words
            process.environment = ["LC_ALL": locale, "PATH": "/usr/bin:/bin"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let normalized = SSHHookArguments.normalizedArguments(output)
            XCTAssertNotNil(normalized, "locale \(locale)")
            XCTAssertEqual((normalized! as NSString).componentsInShellCommand(), words, "locale \(locale)")
        }
    }
}

private final class WriteRecordingConductorDelegate: NSObject, ConductorDelegate {
    private(set) var written = ""
    private(set) var quitCount = 0

    func conductorWrite(string: String) {
        written += string
    }
    func conductorAbort(reason: String) {}
    func conductorQuit() {
        quitCount += 1
    }
    func conductorStateDidChange() {}
    func conductorStopQueueingInput() {}
    func conductorSendInitialText() {}
    func conductorRequestIT2Authorization(guid: String,
                                          displayName: String,
                                          callerTmuxPane: String?,
                                          completion: @escaping (Bool, Bool, Bool) -> Void) {
        completion(false, false, false)
    }
    func conductorDismissIT2AuthorizationPrompt(guid: String) {}
    let guid = "write-recording-delegate"
}

// When the hook can't be understood, the session makes the remote conductor quit.
// conductor.sh first reads the line prefix and then reads base64 lines (each starting with
// the prefix) until an empty line.
@MainActor
final class ConductorQuitWithoutStartingTests: XCTestCase {
    func testWritesLinePrefixThenQuit() {
        let delegate = WriteRecordingConductorDelegate()
        let conductor = Conductor("", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                                  shouldInjectShellIntegration: false, parent: nil)
        conductor.delegate = delegate
        conductor.quitWithoutStarting()

        let prefix = conductor.linePrefix
        XCTAssertFalse(prefix.isEmpty)
        let lines = delegate.written.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, prefix)
        let body = lines.dropFirst().prefix { !$0.isEmpty }
        XCTAssertEqual(body.count, lines.count - 3, "the command must end with an empty line: \(lines)")
        let base64 = body.map { line -> String in
            XCTAssertTrue(line.hasPrefix(prefix))
            return String(line.dropFirst(prefix.count))
        }.joined()
        XCTAssertEqual(String(data: Data(base64Encoded: base64) ?? Data(), encoding: .utf8), "quit")
        // The session tears the conductor down itself.
        XCTAssertEqual(delegate.quitCount, 0)
    }
}

// A jump evaluates the normalized arguments with bash (Conductor.jumpScript), so bash
// must split them into the same words.
final class SSHHookArgumentsBashCompatibilityTests: XCTestCase {
    func testBashSplitsNormalizedArgumentsIntoTheSameWords() throws {
        let words = ["example.com", "printf", "%s|", "Ünï 😀", "a b", "x'y", "tab\tx",
                     "new\nline", "~", "$HOME", "\"", "\\", "", "n", "-p", "22"]
        let normalized = SSHHookArguments.quote(words: words)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "for w in \(normalized); do printf '%s\\0' \"$w\"; done"]
        process.environment = ["LC_ALL": "en_US.UTF-8", "PATH": "/usr/bin:/bin"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var split = output.split(separator: 0, omittingEmptySubsequences: false).map {
            String(data: Data($0), encoding: .utf8)!
        }
        XCTAssertEqual(split.popLast(), "")
        XCTAssertEqual(split, words)
    }
}

// The hook handler must hand decodable arguments to the session and report undecodable
// ones so the session can make the remote conductor quit instead of leaving it waiting.
final class SSHConductorHookDecodingTests: XCTestCase {
    private func hook(sshargs: String) -> TerminalTestHarness {
        let harness = TerminalTestHarness()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalDidHookSSHConductor(withParams: "none 12345 Ym9vbA== - \(sshargs) dcs1",
                                                      parentDepth: -1)
        })
        harness.screen.performBlock(joinedThreads: { _, _, _ in })
        return harness
    }

    func testNonUTF8QuotedArgumentsHook() {
        let harness = hook(sshargs: "MTkyLjE2OC42NC4zIHByaW50ZiAlc1x8ICQnw1wyMzRuw68g8FwyMzdcMjMwXDIwMCcg")
        XCTAssertEqual(harness.delegate.failedSSHHookUniqueIDs, [])
        XCTAssertEqual(harness.delegate.hookedSSHArgs.count, 1)
        XCTAssertEqual((harness.delegate.hookedSSHArgs.first! as NSString).componentsInShellCommand(),
                       ["192.168.64.3", "printf", "%s|", "Ünï 😀"])
    }

    func testUndecodableArgumentsReportFailure() {
        let latin1 = Data("host echo $'caf\\351' ".utf8).base64EncodedString()
        let harness = hook(sshargs: latin1)
        XCTAssertEqual(harness.delegate.hookedSSHArgs, [])
        XCTAssertEqual(harness.delegate.failedSSHHookUniqueIDs, ["12345"])
    }

    func testInvalidBase64ReportsFailure() {
        let harness = hook(sshargs: "%%%")
        XCTAssertEqual(harness.delegate.hookedSSHArgs, [])
        XCTAssertEqual(harness.delegate.failedSSHHookUniqueIDs, ["12345"])
    }
}
