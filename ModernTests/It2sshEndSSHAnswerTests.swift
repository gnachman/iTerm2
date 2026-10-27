//
//  It2sshEndSSHAnswerTests.swift
//  iTerm2 ModernTests
//
//  After ssh exits, it2ssh prints EndSSH and waits for iTerm2's answer with the tty at
//  -echo -isig. For a connection iTerm2 didn't start (ssh never connected), the answer is a
//  bare ^C, so it2ssh must stop on a ^C that ends no line. These run the real script in a pty
//  (via script(1)) with a fake ssh.
//

import XCTest

final class It2sshEndSSHAnswerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("it2ssh-answer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("home"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var it2sshURL: URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("submodules/iTerm2-shell-integration/utilities/it2ssh")
    }

    private func makeFakeSSH(status: Int32) throws -> URL {
        let url = root.appendingPathComponent("ssh")
        try """
            #!/bin/sh
            echo 'ssh: Could not resolve hostname bogus: nodename nor servname provided' >&2
            exit \(status)
            """.write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Runs it2ssh in a pty and writes `answer` once EndSSH has been printed. Returns its exit
    /// status, or nil if it was still waiting at the (generous) deadline.
    private func run(ssh: URL, answer: String) throws -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", "/bin/bash", it2sshURL.path, "bogus"]
        process.environment = ["HOME": root.appendingPathComponent("home").path,
                               "SSH": ssh.path,
                               "TERM": "xterm-256color",
                               "PATH": "/usr/bin:/bin"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        let printedEndSSH = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var transcript = Data()
        var signaled = false
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            lock.lock()
            transcript.append(data)
            let ready = !signaled && String(decoding: transcript, as: UTF8.self).contains("1337;EndSSH=")
            if ready {
                signaled = true
            }
            lock.unlock()
            if ready {
                printedEndSSH.signal()
            }
        }
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
        }
        // The tty is in -isig mode once EndSSH is printed, so the ^C arrives as a byte.
        XCTAssertEqual(printedEndSSH.wait(timeout: .now() + 30), .success, "it2ssh never printed EndSSH")
        try input.fileHandleForWriting.write(contentsOf: Data(answer.utf8))
        if exited.wait(timeout: .now() + 30) == .timedOut {
            process.terminate()
            exited.wait()
            return nil
        }
        return process.terminationStatus
    }

    // iTerm2's answer to an EndSSH no connection started.
    func testBareControlCEndsTheWaitAndReturnsSSHStatus() throws {
        XCTAssertEqual(try run(ssh: try makeFakeSSH(status: 255), answer: "\u{03}"), 255)
    }

    // iTerm2's answer to a connection it knows.
    func testControlCAndNewlineEndTheWait() throws {
        XCTAssertEqual(try run(ssh: try makeFakeSSH(status: 3), answer: "\u{03}\n"), 3)
    }

    // Lines of conductor.sh still being typed when ssh died don't end the wait; the answer does.
    func testNonEmptyLinesDoNotEndTheWait() throws {
        XCTAssertEqual(try run(ssh: try makeFakeSSH(status: 255), answer: "QUJD\nREVG\n\u{03}\n"), 255)
    }
}
