//
//  ShellIntegrationInstallerIt2Tests.swift
//  iTerm2 ModernTests
//
//  Install Shell Integration & Utilities installs iTerm2's Python it2 as well: the wrapper at
//  ~/.iterm2/bin/it2 and the interpreter at ~/.iterm2/it2.<hash>.py, the layout it2ssh uploads,
//  so the two never compete. That is $HOME's .iterm2 even when the utilities go under $ZDOTDIR,
//  because the shell-integration scripts, Claude Code hooks and the wrapper all look there. it2
//  gets no alias: an alias would beat PATH, and on this Mac the wrapper has to be able to hand
//  off to the native it2 (see It2WrapperSelectionTests).
//

import XCTest
@testable import iTerm2SharedARC

final class ShellIntegrationInstallerIt2Tests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("si-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var archive: URL {
        get throws {
            try XCTUnwrap(Bundle(for: PTYSession.self).url(forResource: "utilities", withExtension: "tgz",
                                                            subdirectory: "utilities")
                          ?? Bundle(for: PTYSession.self).url(forResource: "utilities", withExtension: "tgz"))
        }
    }

    private func run(_ executable: String, _ arguments: [String], cwd: URL? = nil,
                     environment: [String: String]? = nil, stdin: String? = nil) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.environment = environment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        let input = Pipe()
        process.standardInput = input
        try process.run()
        if let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
        }
        try input.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testArchiveCarriesIt2() throws {
        let (status, listing) = try run("/usr/bin/tar", ["tzf", try archive.path])
        XCTAssertEqual(status, 0, listing)
        let entries = Set(listing.split(separator: "\n").map { String($0).replacingOccurrences(of: "./", with: "") })
        XCTAssertTrue(entries.contains("it2-files/bin/it2"), "\(entries.sorted())")
        XCTAssertTrue(entries.contains("it2-files/it2.\(iTermBundledIt2PyHash).py"), "\(entries.sorted())")
        XCTAssertTrue(entries.contains("it2git"), "the utilities are still there")
    }

    // The manifest names what gets an alias. Neither it2 nor its folder may.
    func testNothingAboutIt2IsAliased() throws {
        let url = try XCTUnwrap(Bundle(for: PTYSession.self).url(forResource: "utilities-manifest", withExtension: "txt"))
        let names = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isWhitespace).map(String.init)
        XCTAssertFalse(names.contains("it2"))
        XCTAssertFalse(names.contains("it2-files"))
        XCTAssertFalse(names.contains("bin"))
        XCTAssertTrue(names.contains("it2git"))
    }

    // What the installer types, run in bash with a ZDOTDIR that is not HOME.
    func testInstallerPutsIt2UnderHome() throws {
        let home = root.appendingPathComponent("home")
        let utilities = root.appendingPathComponent("zdotdir/.iterm2")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: utilities, withIntermediateDirectories: true)
        let encoded = try Data(contentsOf: try archive).base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
        let typed = iTermShellIntegrationWindowController.receiveUtilitiesCommand + encoded + "\nEOF\n"
        let (status, output) = try run("/bin/bash", ["-s"], cwd: utilities,
                                       environment: ["HOME": home.path, "PATH": "/usr/bin:/bin"],
                                       stdin: typed)
        XCTAssertEqual(status, 0, output)
        XCTAssertTrue(output.contains("it2-utilities-installed"), output)

        let wrapper = home.appendingPathComponent(".iterm2/bin/it2")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: wrapper.path), output)
        let interpreter = home.appendingPathComponent(".iterm2/it2.\(iTermBundledIt2PyHash).py")
        XCTAssertTrue(FileManager.default.fileExists(atPath: interpreter.path), output)
        // The wrapper names that interpreter when nothing injected IT2_PY.
        XCTAssertTrue(try String(contentsOf: wrapper, encoding: .utf8).contains("it2.\(iTermBundledIt2PyHash).py"))
        // The utilities stay where they were, and the staging folder is gone.
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: utilities.appendingPathComponent("it2git").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: utilities.appendingPathComponent("it2-files").path))
    }

    // HOME and ZDOTDIR the same, the usual case: the copy is not onto itself.
    func testInstallerWhenUtilitiesAreUnderHome() throws {
        let home = root.appendingPathComponent("home")
        let utilities = home.appendingPathComponent(".iterm2")
        try FileManager.default.createDirectory(at: utilities, withIntermediateDirectories: true)
        let encoded = try Data(contentsOf: try archive).base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
        let typed = iTermShellIntegrationWindowController.receiveUtilitiesCommand + encoded + "\nEOF\n"
        let (status, output) = try run("/bin/bash", ["-s"], cwd: utilities,
                                       environment: ["HOME": home.path, "PATH": "/usr/bin:/bin"],
                                       stdin: typed)
        XCTAssertEqual(status, 0, output)
        XCTAssertTrue(output.contains("it2-utilities-installed"), output)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: utilities.appendingPathComponent("bin/it2").path), output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: utilities.appendingPathComponent("it2-files").path))
    }
}

// The v2 curl | bash installer (shell_integration/install_shell_integration_and_utilities.sh,
// published at iterm2.com/shell_integration/v2/ with the rest of that folder by the website's
// copy-shell-integration.sh) fetches the same two files from beside itself. Run for real here,
// with a fake curl that serves this checkout's copies. The v1 installer the app and the docs
// link to today is the frozen legacy tree and is not changed.
final class CurlInstallerIt2Tests: XCTestCase {
    private var root: URL!
    private let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("curl-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("home"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Runs the installer with a curl that serves `wrapper` and `interpreter` for it2.
    private func install(wrapper: URL, interpreter: URL) throws -> String {
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let curl = bin.appendingPathComponent("curl")
        try """
            #!/bin/sh
            for url in "$@"; do :; done
            case "$url" in
              https://iterm2.com/shell_integration/v2/it2-wrapper) cat '\(wrapper.path)' ;;
              https://iterm2.com/shell_integration/v2/it2.py) cat '\(interpreter.path)' ;;
              *) printf '#!/bin/sh\\n' ;;
            esac
            """.write(to: curl, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: curl.path)
        let script = checkout.appendingPathComponent(
            "submodules/iTerm2-shell-integration/shell_integration/install_shell_integration_and_utilities.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.environment = ["HOME": root.appendingPathComponent("home").path,
                               "SHELL": "/bin/bash",
                               "PATH": bin.path + ":/usr/bin:/bin"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(decoding: data, as: UTF8.self)
    }

    private var home: URL { root.appendingPathComponent("home") }

    // The submodule is where both files come from (its shell_integration/Makefile builds the
    // wrapper); the app bundles copies made by tools/copy_shell_integration.sh. They must not drift.
    func testBundledCopiesMatchTheSubmodule() throws {
        let bundle = Bundle(for: PTYSession.self)
        let wrapper = try XCTUnwrap(bundle.url(forResource: "it2-remote", withExtension: nil))
        XCTAssertEqual(try Data(contentsOf: wrapper), try Data(contentsOf: sources.appendingPathComponent("it2-wrapper")),
                       "run tools/copy_shell_integration.sh")
        XCTAssertEqual(try Data(contentsOf: checkout.appendingPathComponent("OtherResources/it2.py")),
                       try Data(contentsOf: sources.appendingPathComponent("it2.py")),
                       "run tools/copy_shell_integration.sh")
    }

    private var sources: URL {
        checkout.appendingPathComponent("submodules/iTerm2-shell-integration/shell_integration")
    }

    func testInstallsIt2UnderHomeWithoutAnAlias() throws {
        let output = try install(wrapper: sources.appendingPathComponent("it2-wrapper"),
                                 interpreter: sources.appendingPathComponent("it2.py"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: home.appendingPathComponent(".iterm2/bin/it2").path), output)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: home.appendingPathComponent(".iterm2/it2.\(iTermBundledIt2PyHash).py").path), output)
        // For bash the utilities are reached through ~/.iterm2 on PATH, so nothing named it2 may be
        // there, and nothing aliases it.
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".iterm2/it2").path))
        let integration = try String(contentsOf: home.appendingPathComponent(".iterm2_shell_integration.bash"), encoding: .utf8)
        XCTAssertFalse(integration.contains("alias it2="), integration)
        XCTAssertTrue(integration.contains("/.iterm2:$PATH"), integration)
    }

    // A wrapper and interpreter from different builds would leave a wrapper naming a file that is
    // not there. Install neither.
    func testMismatchedPairIsNotInstalled() throws {
        let other = root.appendingPathComponent("other.py")
        try "print('a different build')\n".write(to: other, atomically: false, encoding: .utf8)
        let output = try install(wrapper: sources.appendingPathComponent("it2-wrapper"), interpreter: other)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".iterm2/bin/it2").path), output)
        XCTAssertTrue(output.contains("Skipping it2"), output)
    }
}

