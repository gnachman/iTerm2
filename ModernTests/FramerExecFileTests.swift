//
//  FramerExecFileTests.swift
//  iTerm2 ModernTests
//
//  The framer's eval command writes the code it is given to a file and runs it. That carries the
//  jump script for every multi-hop connection (the bundled it2ssh and the next hop's ssh
//  arguments). It went to /tmp, which on a shared host may be full or unwritable; it now goes in
//  ~/.iterm2, private to the user, like everything else iTerm2 writes there.
//

import XCTest
@testable import iTerm2SharedARC

final class FramerExecFileTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("framer-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    /// Imports this checkout's framer.py and prints the path exec_file writes for `code`.
    private func execFilePath(_ code: String) throws -> String {
        let framer = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("OtherResources")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import sys; sys.path.insert(0, sys.argv[1]); import framer; print(framer.write_exec_file(sys.argv[2]))",
                             framer.path, code]
        process.environment = ["HOME": home.path, "TMPDIR": "/nonexistent-tmpdir", "PATH": "/usr/bin:/bin"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(process.terminationStatus, 0, text)
        return text
    }

    // In ~/.iterm2, whatever TMPDIR says, hidden, and readable only by the user.
    func testWrittenUnderHomePrivately() throws {
        let path = try execFilePath("echo hi")
        let directory = home.appendingPathComponent(".iterm2").path
        XCTAssertEqual((path as NSString).deletingLastPathComponent, directory)
        XCTAssertTrue((path as NSString).lastPathComponent.hasPrefix("."), path)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "echo hi")
        let fileMode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
        XCTAssertEqual(fileMode & 0o077, 0, "no access for anyone else")
        XCTAssertNotEqual(fileMode & 0o100, 0, "executable by the user")
        let directoryMode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: directory)[.posixPermissions] as? Int)
        XCTAssertEqual(directoryMode & 0o077, 0)
    }

    // ~/.iterm2 may already exist with other files in it; that is fine.
    func testExistingDirectoryIsReused() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".iterm2"),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let first = try execFilePath("a")
        let second = try execFilePath("b")
        XCTAssertNotEqual(first, second)
    }
}

// The same for conductor.sh's eval, used to jump from a host with no framer. It made a directory
// under TMPDIR or /tmp and never removed it, and left SELF unset, so the jump script's own
// `rm $SELF` did nothing. Now one private file in ~/.iterm2, named by SELF, gone afterwards.
final class ConductorShEvalTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("conductor-eval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("home"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("tmp"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func eval(_ code: String) throws -> String {
        let conductor = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("submodules/iTerm2-shell-integration/ssh-helpers/conductor.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", #". "$1" 2>/dev/null; conductor_cmd_eval "$(printf %s "$2" | base64)""#,
                             "sh", conductor.path, code]
        process.environment = ["HOME": root.appendingPathComponent("home").path,
                               "TMPDIR": root.appendingPathComponent("tmp").path + "/",
                               "PATH": "/usr/bin:/bin"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private var dotIterm2: String { root.appendingPathComponent("home/.iterm2").path }

    func testRunsFromAPrivateFileInHomeThenRemovesIt() throws {
        let output = try eval(#"printf '%s|%s' "$SELF" "$(ls -l "$SELF" | cut -c1-10)""#)
        let parts = output.split(separator: "|").map(String.init)
        guard parts.count == 2 else {
            XCTFail("unexpected output: \(output)")
            return
        }
        XCTAssertEqual((parts[0] as NSString).deletingLastPathComponent, dotIterm2)
        XCTAssertTrue((parts[0] as NSString).lastPathComponent.hasPrefix("."), output)
        XCTAssertEqual(parts[1], "-rw-------", "private to the user")
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: dotIterm2)) ?? [], [], "removed afterwards")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("tmp").path), [],
                       "nothing in TMPDIR")
    }

    // A jump script removes itself first, as Conductor.jumpScript does; that must work, and the
    // cleanup afterwards must not complain.
    func testCodeThatRemovesItselfFirst() throws {
        let output = try eval("rm $SELF\nunset SELF\necho ran")
        XCTAssertEqual(output, "ran\n")
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: dotIterm2)) ?? [], [])
    }
}

// The boundary conductor.sh frames each command's output with. Its generator kept a counter in a
// subshell (so it never advanced), seeded awk from the clock in whole seconds (so every boundary
// within a second was identical), and with no awk on PATH produced the bare "0.".
final class ConductorShBoundaryTests: XCTestCase {
    /// Boundaries from `count` calls in one shell, as fast as it can make them.
    private func boundaries(_ count: Int, path: String = "/usr/bin:/bin") throws -> [String] {
        let conductor = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("submodules/iTerm2-shell-integration/ssh-helpers/conductor.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", #". "$1" 2>/dev/null; PATH="$3"; i=0; while [ $i -lt "$2" ]; do new_boundary; printf '%s\n' "$conductor_boundary"; i=$((i + 1)); done"#,
                             "sh", conductor.path, String(count), path]
        process.environment = ["HOME": NSTemporaryDirectory(), "PATH": "/usr/bin:/bin"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    func testBackToBackBoundariesDiffer() throws {
        let values = try boundaries(20)
        XCTAssertEqual(values.count, 20)
        XCTAssertEqual(Set(values).count, 20, "\(values)")
        // Random, not just counted: at least 16 hex digits after the counter.
        for value in values {
            let random = value.split(separator: ".").last.map(String.init) ?? ""
            XCTAssertGreaterThanOrEqual(random.count, 16, value)
        }
    }

    // With nothing on PATH (no od, no awk), still unique and never the bare counter.
    func testNoToolsStillGivesDistinctBoundaries() throws {
        let values = try boundaries(5, path: "/nonexistent")
        XCTAssertEqual(values.count, 5)
        XCTAssertEqual(Set(values).count, 5, "\(values)")
        for value in values {
            XCTAssertFalse(value.hasSuffix("."), value)
        }
    }
}

// The framer lists processes for job names and the Jobs tool. It used `ps -eo …`: "every process"
// on Linux and macOS, but on FreeBSD and OpenBSD "also print each process's environment", which
// sent every variable (IT2_NONCE among them) to iTerm2 in front of each command and named sessions
// after the first one ("VENDOR=unknown"). Seen on FreeBSD 14.3. This Mac reads both options the
// same way, so the difference cannot be observed here; pin the portable one, POSIX's -A.
final class FramerProcessListingTests: XCTestCase {
    func testListsProcessesWithPOSIXDashA() throws {
        let framer = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("OtherResources/framer.py")
        let source = try String(contentsOf: framer, encoding: .utf8)
        XCTAssertTrue(source.contains(#""ps -Ao pid,ppid,stat,lstart,command""#))
        XCTAssertNil(source.range(of: #"ps -e[a-z]*o"#, options: .regularExpression))
    }
}

