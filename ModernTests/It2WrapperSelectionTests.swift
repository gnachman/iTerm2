//
//  It2WrapperSelectionTests.swift
//  iTerm2 ModernTests
//
//  ~/.iterm2/bin/it2 is iTerm2's Python it2 wrapper. iTerm2 uploads it to hosts reached through
//  SSH Integration, and Install Shell Integration & Utilities installs it anywhere, this Mac
//  included, where the shell-integration scripts put ~/.iterm2/bin first on PATH. So it must not
//  shadow the native it2 that iTerm2 puts on PATH for local sessions, and it must never hand off
//  to the open-source `it2` (pip or Homebrew) that iTerm2's it2 supplanted, which does not speak
//  iTerm2's protocol.
//

import XCTest
@testable import iTerm2SharedARC

final class It2WrapperSelectionTests: XCTestCase {
    private var root: URL!
    private var nativeDir: URL!
    private var openSourceDir: URL!
    private var pythonDir: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("it2-wrapper-\(UUID().uuidString)")
        nativeDir = root.appendingPathComponent("My iTerm2.app/Contents/Resources/utilities")
        openSourceDir = root.appendingPathComponent("homebrew/bin")
        pythonDir = root.appendingPathComponent("python")
        try script(at: nativeDir.appendingPathComponent("it2"), printing: "native")
        try script(at: openSourceDir.appendingPathComponent("it2"), printing: "open-source")
        // Stands in for python3: reports that the Python it2 ran, and with what.
        try script(at: pythonDir.appendingPathComponent("python3"), printing: "python")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func script(at url: URL, printing label: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\nprintf '%s' \(label)\nfor a in \"$@\"; do printf '|%s' \"$a\"; done\n"
            .write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// What the wrapper ran: "native", "open-source" or "python", then each argument after a |.
    private func run(path: [URL], it2Sock: String? = nil, arguments: [String] = ["session", "a b"]) throws -> String {
        let wrapper = try XCTUnwrap(Bundle(for: PTYSession.self).path(forResource: "it2-remote", ofType: nil))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [wrapper] + arguments
        var environment = ["PATH": (path.map(\.path) + ["/usr/bin", "/bin"]).joined(separator: ":"),
                           "HOME": root.path,
                           "IT2_PY": "/the/it2.py"]
        environment["IT2_SOCK"] = it2Sock
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // On this Mac, where iTerm2 puts its utilities on PATH: the native it2.
    func testLocalSessionRunsTheNativeIt2() throws {
        XCTAssertEqual(try run(path: [pythonDir, nativeDir]), "native|session|a b")
    }

    // The open-source it2 earlier on PATH is skipped in favor of iTerm2's.
    func testOpenSourceIt2IsSkippedForTheNativeOne() throws {
        XCTAssertEqual(try run(path: [pythonDir, openSourceDir, nativeDir]), "native|session|a b")
    }

    // Over SSH Integration, including it2ssh to this Mac: the Python it2, even with the native one
    // on PATH, because only it speaks through the connection.
    func testSSHIntegrationRunsThePythonIt2() throws {
        XCTAssertEqual(try run(path: [pythonDir, nativeDir], it2Sock: "/tmp/sock"),
                       "python|/the/it2.py|session|a b")
    }

    // A remote host with the open-source it2 installed: never that one.
    func testOpenSourceIt2IsNeverRun() throws {
        XCTAssertEqual(try run(path: [pythonDir, openSourceDir]), "python|/the/it2.py|session|a b")
        XCTAssertEqual(try run(path: [pythonDir, openSourceDir], it2Sock: "/tmp/sock"),
                       "python|/the/it2.py|session|a b")
    }

    // A remote tmux pane has no IT2_SOCK; the Python it2 finds its connection through tmux.
    func testNoNativeIt2RunsThePythonIt2() throws {
        XCTAssertEqual(try run(path: [pythonDir]), "python|/the/it2.py|session|a b")
    }

    // A PATH entry that merely mentions utilities, or a glob character, changes nothing.
    func testOnlyAnAppBundleUtilitiesDirectoryCounts() throws {
        let impostor = root.appendingPathComponent("Contents/Resources/utilities")
        try script(at: impostor.appendingPathComponent("it2"), printing: "impostor")
        let globby = URL(fileURLWithPath: root.path + "/*")
        XCTAssertEqual(try run(path: [pythonDir, globby, impostor]), "python|/the/it2.py|session|a b")
    }
}
