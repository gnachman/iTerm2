//
//  ClaudeCodeRemoteHooksTests.swift
//  iTerm2 ModernTests
//
//  Installing, checking and removing the Claude Code hook on a host reached through SSH
//  Integration (Phase 4c). The edits are the shared ClaudeCodeHookSettings ones with the remote
//  rule for which entries are ours; the remote file access is faked here, and the Python that
//  implements it for real is run under this Mac's python3 at the end.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
private final class FakeRemoteFiles: ClaudeCodeRemoteFiles {
    var files: [String: Data] = [:]
    var unreadable: Set<String> = []
    var executables: Set<String> = []
    var failWrites = false
    var token: String? = "1:"
    private(set) var writes: [String] = []

    func read(_ path: String) async -> ClaudeCodeRemoteRead {
        if unreadable.contains(path) {
            return .failed("PermissionError")
        }
        guard let data = files[path] else {
            return .missing
        }
        return .contents(data)
    }

    func write(_ path: String, _ data: Data) async -> Bool {
        writes.append(path)
        guard !failWrites else {
            return false
        }
        files[path] = data
        return true
    }

    func isExecutable(_ path: String) async -> Bool {
        return executables.contains(path)
    }

    func machineToken() async -> String? {
        return token
    }
}

@MainActor
final class ClaudeCodeRemoteHooksTests: XCTestCase {
    private typealias Hooks = ClaudeCodeRemoteHooks
    private let home = "/home/u"
    private let settingsPath = "/home/u/.claude/settings.json"
    private var wrapper: String { home + "/.iterm2/bin/it2" }
    private let command = ClaudeCodeHookSettings.remoteHookCommand(descriptor: .claudeCode)

    private func makeFiles(settings: [String: Any]? = nil) throws -> FakeRemoteFiles {
        let files = FakeRemoteFiles()
        files.executables = [wrapper]
        if let settings {
            files.files[settingsPath] = try ClaudeCodeHookSettings.serialized(settings)
        }
        return files
    }

    private func settings(_ files: FakeRemoteFiles) throws -> [String: Any] {
        let data = try XCTUnwrap(files.files[settingsPath])
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func ourCommands(_ settings: [String: Any], event: String) -> [String] {
        let groups = ((settings["hooks"] as? [String: Any])?[event] as? [[String: Any]]) ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
            .filter { ClaudeCodeHookSettings.isRemoteHookCommand($0, home: home) }
    }

    // MARK: - Which entries are ours

    func testRemoteCommandShape() {
        XCTAssertEqual(command, "\"$HOME/.iterm2/bin/it2\" handle-agent-hook")
    }

    func testOwnership() {
        let ours = [
            "\"$HOME/.iterm2/bin/it2\" handle-agent-hook",
            "\"/home/u/.iterm2/bin/it2\" handle-agent-hook",
            "\"$HOME/.iterm2/bin/it2\" handle-agent-hook --agent codex",
        ]
        for command in ours {
            XCTAssertTrue(ClaudeCodeHookSettings.isRemoteHookCommand(command, home: "/home/u/"), command)
        }
        let notOurs = [
            // A Mac install's entry, synced over in a dotfiles repo: that install manages it.
            "\"/Users/u/.config/iterm2/it2\" handle-agent-hook",
            "/Users/u/.config/iterm2/cc-status",
            // Another user's wrapper, and look-alikes.
            "\"/home/other/.iterm2/bin/it2\" handle-agent-hook",
            "\"$HOME/.iterm2/bin/it2\" handle-agent-hookx",
            "\"$HOME/.iterm2/bin/it2\" session list",
            "$HOME/.iterm2/bin/it2 handle-agent-hook",
            "echo hi",
        ]
        for command in notOurs {
            XCTAssertFalse(ClaudeCodeHookSettings.isRemoteHookCommand(command, home: "/home/u"), command)
        }
    }

    // MARK: - Install

    func testInstallIntoAMissingFileCoversEveryEvent() async throws {
        let files = try makeFiles()
        let result = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(result, .installed)
        let written = try settings(files)
        for event in ClaudeCodeOnboarding.hookEventNames {
            XCTAssertEqual(ourCommands(written, event: event), [command], event)
        }
    }

    // The user's other settings and other hooks survive, and a second install changes nothing.
    func testInstallKeepsEverythingElseAndIsIdempotent() async throws {
        let foreign: [String: Any] = ["hooks": [["type": "command", "command": "~/bin/notify"]]]
        let files = try makeFiles(settings: ["model": "opus", "hooks": ["Stop": [foreign]]])
        _ = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        let once = try XCTUnwrap(files.files[settingsPath])
        let written = try settings(files)
        XCTAssertEqual(written["model"] as? String, "opus")
        let stopCommands = (((written["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]) ?? [])
            .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["command"] as? String }
        XCTAssertEqual(Set(stopCommands), ["~/bin/notify", command])

        _ = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(files.files[settingsPath], once)
    }

    // An entry naming the wrapper by absolute path is ours and is rewritten, not duplicated.
    func testInstallAdoptsAnAbsolutePathEntry() async throws {
        let old: [String: Any] = ["hooks": [["type": "command", "command": "\"/home/u/.iterm2/bin/it2\" handle-agent-hook"]]]
        let files = try makeFiles(settings: ["hooks": ["Stop": [old]]])
        _ = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(ourCommands(try settings(files), event: "Stop"), [command])
    }

    // This Mac reached over ssh (localhost): its settings belong to the local install, and a remote
    // install would replace the local hook command. Refused, nothing written.
    func testInstallOntoThisMacIsRefused() async throws {
        let files = try makeFiles()
        files.token = try XCTUnwrap(iTermMachineIdentity.localVersion1TokenForTesting())
        let result = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(result, .thisMac)
        XCTAssertEqual(files.writes, [])
    }

    // Uninstall's this-Mac check before its confirmation uses a short deadline, so a wedged
    // connection can't leave the menu item doing nothing for half a minute (QA finding F-814).
    // An answer that never comes is nil at the deadline, which the check treats as unknown and
    // keeps the host in the dialog.
    func testAnAnswerThatNeverComesIsNilAtTheDeadline() async {
        let start = Date()
        let value = await ConductorClaudeCodeRemoteFiles.awaitAnswer(deadline: 0.1) { _ in }
        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        let answered = await ConductorClaudeCodeRemoteFiles.awaitAnswer(deadline: 30) { finish in
            finish("1:abc")
        }
        XCTAssertEqual(answered, "1:abc")
        XCTAssertLessThan(ConductorClaudeCodeRemoteFiles.confirmationCheckDeadline, 5)
    }

    // A host that can't be told apart from this Mac (no token, a "0:" token from a Mac whose
    // identity couldn't be computed, or a version this Mac doesn't implement) might be this Mac,
    // so neither install nor uninstall edits its settings (QA finding F-815).
    func testInstallAndUninstallRefuseAHostOfUnknownIdentity() async throws {
        for token in [nil, "0:", "99:abc", "garbage"] as [String?] {
            let files = try makeFiles()
            files.token = token
            let installed = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
            XCTAssertEqual(installed, .identityUnknown, String(describing: token))
            files.files[settingsPath] = try ClaudeCodeHookSettings.serialized(
                ["hooks": ["Stop": [["hooks": [["type": "command", "command": command]]]]]])
            let uninstalled = await Hooks.uninstall(files: files, settingsPath: settingsPath, home: home)
            // No token at all means the host didn't answer, which uninstall reports as such
            // rather than as an identity it couldn't judge (QA finding F-868).
            XCTAssertEqual(uninstalled, token == nil ? .hostNotResponding : .hostIdentityUnknown,
                           String(describing: token))
            XCTAssertEqual(files.writes, [], String(describing: token))
        }
    }


    // A Linux host says so ("1:" with no value), which is a positive "not this Mac".
    func testANonMacHostIsEdited() async throws {
        let files = try makeFiles()
        files.token = "1:"
        let result = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(result, .installed)
    }

    // No wrapper means a hook would fail on every event: the shell there could not be set up by
    // ssh integration (tcsh, for one). Say so rather than install something that cannot run.
    func testInstallWithoutTheWrapperIsRefused() async throws {
        let files = try makeFiles()
        files.executables = []
        let result = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(result, .it2Missing)
        XCTAssertEqual(files.writes, [])
    }

    // A file iTerm2 cannot parse is the user's, not an empty one to overwrite.
    func testMalformedSettingsAreNotOverwritten() async throws {
        let files = try makeFiles()
        files.files[settingsPath] = Data("{ not json".utf8)
        let result = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(result, .malformed)
        XCTAssertEqual(files.writes, [])
    }

    func testUnreadableSettingsAreNotOverwritten() async throws {
        let files = try makeFiles(settings: [:])
        files.unreadable = [settingsPath]
        let result = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(result, .unreadable)
        XCTAssertEqual(files.writes, [])
    }

    func testWriteFailureIsReported() async throws {
        let files = try makeFiles()
        files.failWrites = true
        let result = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(result, .writeFailed)
    }

    // MARK: - Status, read from the host itself
    //
    // Nothing about remote hosts is kept on this Mac, so whether the hook is installed is always
    // what the host's settings say.

    func testHealthyAfterInstall() async throws {
        let files = try makeFiles()
        _ = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        let status = await Hooks.status(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(status, .healthy)
    }

    // Claude Code rewrote the file and dropped one event: broken, so a reinstall is offered.
    func testMissingEventIsBroken() async throws {
        let files = try makeFiles()
        _ = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        var written = try settings(files)
        var hooks = try XCTUnwrap(written["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "Stop")
        written["hooks"] = hooks
        files.files[settingsPath] = try ClaudeCodeHookSettings.serialized(written)
        let status = await Hooks.status(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(status, .broken)
    }

    // The entries are there but the wrapper they run is gone.
    func testMissingWrapperIsBroken() async throws {
        let files = try makeFiles()
        _ = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        files.executables = []
        let status = await Hooks.status(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(status, .broken)
    }

    func testNoFileIsNotInstalled() async throws {
        let status = await Hooks.status(files: try makeFiles(), settingsPath: settingsPath, home: home)
        XCTAssertEqual(status, .notInstalled)
    }

    // Other tools' hooks, none of ours.
    func testOnlyOtherHooksIsNotInstalled() async throws {
        let files = try makeFiles(settings: ["hooks": ["Stop": [["hooks": [["type": "command", "command": "other"]]]]]])
        let status = await Hooks.status(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(status, .notInstalled)
    }

    // A connection back to this Mac would otherwise report this Mac's own settings as the remote
    // install, and the installer would pre-mark the remote step from them (QA finding F-816).
    func testStatusOfThisMacIsNotInstalledAndOfAnUnknownHostIsUnknown() async throws {
        let files = try makeFiles()
        _ = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        files.token = try XCTUnwrap(iTermMachineIdentity.localVersion1TokenForTesting())
        let thisMac = await Hooks.status(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(thisMac, .notInstalled)
        files.token = nil
        let unknown = await Hooks.status(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(unknown, .unknown)
    }

    // Could not read it, or not JSON: nothing can be said either way.
    func testUnreadableIsUnknown() async throws {
        let files = try makeFiles()
        files.unreadable = [settingsPath]
        let unreadable = await Hooks.status(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(unreadable, .unknown)
        let malformed = try makeFiles()
        malformed.files[settingsPath] = Data("{".utf8)
        let status = await Hooks.status(files: malformed, settingsPath: settingsPath, home: home)
        XCTAssertEqual(status, .unknown)
    }

    // MARK: - Uninstall

    func testUninstallRemovesOnlyOurs() async throws {
        let foreign: [String: Any] = ["hooks": [["type": "command", "command": "~/bin/notify"]]]
        let files = try makeFiles(settings: ["model": "opus", "hooks": ["Stop": [foreign]]])
        _ = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        let result = await Hooks.uninstall(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(result, .success)
        let written = try settings(files)
        XCTAssertEqual(written["model"] as? String, "opus")
        let hooks = try XCTUnwrap(written["hooks"] as? [String: Any])
        XCTAssertEqual(Array(hooks.keys), ["Stop"], "events that held only ours are gone")
        for event in ClaudeCodeOnboarding.hookEventNames {
            XCTAssertEqual(ourCommands(written, event: event), [], event)
        }
    }

    // Nothing to remove is success, and does not write.
    func testUninstallWithNothingToRemove() async throws {
        let files = try makeFiles()
        let missing = await Hooks.uninstall(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(missing, .success)
        files.files[settingsPath] = try ClaudeCodeHookSettings.serialized(["model": "opus"])
        let nothingOurs = await Hooks.uninstall(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(nothingOurs, .success)
        XCTAssertEqual(files.writes, [])
    }

    func testUninstallFailures() async throws {
        let files = try makeFiles()
        files.files[settingsPath] = Data("nope".utf8)
        let malformed = await Hooks.uninstall(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(malformed, .malformed)
        files.unreadable = [settingsPath]
        let unreadable = await Hooks.uninstall(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(unreadable, .unreadable)
    }

    // The parse shared with this Mac's install: blank is empty, a non-object root is nil, and
    // anything else that is not JSON throws.
    func testSettingsObjectParse() throws {
        XCTAssertEqual(try ClaudeCodeHookSettings.settingsObject(from: Data())?.count, 0)
        XCTAssertEqual(try ClaudeCodeHookSettings.settingsObject(from: Data(" \r\n".utf8))?.count, 0)
        XCTAssertEqual(try ClaudeCodeHookSettings.settingsObject(from: Data("{\"a\": 1}".utf8))?["a"] as? Int, 1)
        XCTAssertNil(try ClaudeCodeHookSettings.settingsObject(from: Data("[]".utf8)))
        XCTAssertThrowsError(try ClaudeCodeHookSettings.settingsObject(from: Data("{".utf8)))
        XCTAssertNil(ClaudeCodeHookSettings.settingsObjectIfValid(from: Data("{".utf8)))
    }

    // An empty or whitespace-only settings file is an empty object, as on this Mac (F-365): there
    // is nothing to remove, so uninstall succeeds without writing (QA finding F-606).
    func testUninstallTreatsABlankFileAsEmpty() async throws {
        for contents in ["", "  \n\t"] {
            let files = try makeFiles()
            files.files[settingsPath] = Data(contents.utf8)
            let result = await Hooks.uninstall(files: files, settingsPath: settingsPath, home: home)
            XCTAssertEqual(result, .success, contents.debugDescription)
            XCTAssertEqual(files.writes, [], contents.debugDescription)
        }
    }

    func testStatusOfABlankFileIsNotInstalled() async throws {
        let files = try makeFiles()
        files.files[settingsPath] = Data()
        let status = await Hooks.status(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(status, .notInstalled)
    }

    func testInstallIntoABlankFile() async throws {
        let files = try makeFiles()
        files.files[settingsPath] = Data("\n".utf8)
        let result = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(result, .installed)
        XCTAssertEqual(ourCommands(try settings(files), event: "Stop"), [command])
    }

    // Install refuses this Mac reached over ssh, so uninstall must not edit its settings through
    // the connection either: the local uninstall owns them (QA finding F-606).
    func testUninstallOnThisMacLeavesItsSettingsAlone() async throws {
        let files = try makeFiles()
        _ = await Hooks.install(files: files, settingsPath: settingsPath, home: home)
        let before = try XCTUnwrap(files.files[settingsPath])
        files.token = try XCTUnwrap(iTermMachineIdentity.localVersion1TokenForTesting())
        let result = await Hooks.uninstall(files: files, settingsPath: settingsPath, home: home)
        XCTAssertEqual(result, .success)
        XCTAssertEqual(files.writes, [settingsPath], "only the install wrote")
        XCTAssertEqual(files.files[settingsPath], before)
    }

    // MARK: - The Python that does it for real

    /// Runs `statements` the way framer's runpy does: as the body of a function whose return
    /// value is the answer.
    private nonisolated func runPython(_ statements: String) throws -> String {
        let indented = statements.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    " + $0 }.joined(separator: "\n")
        let script = "def __f__():\n\(indented)\nimport sys\nsys.stdout.write(str(__f__()))\n"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private nonisolated func scratchDirectory() throws -> String {
        let path = NSTemporaryDirectory() + "remote-hooks-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    nonisolated func testPythonWriteReadRoundTripCreatesDirectoriesPrivately() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/nested/claude/settings.json"
        let payload = Data("{\"a\": 1}\n".utf8)
        XCTAssertEqual(try runPython(ClaudeCodeRemotePython.write(path: path, data: payload)), "ok")
        XCTAssertEqual(FileManager.default.contents(atPath: path), payload)
        let mode = (try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(mode, 0o600, "a new settings file can hold secrets")
        let read = try runPython(ClaudeCodeRemotePython.read(path: path))
        XCTAssertEqual(ClaudeCodeRemoteRead(pythonOutput: read), .contents(payload))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir + "/nested/claude")
        XCTAssertEqual(leftovers, ["settings.json"], "no temporary left behind")
    }

    // An existing file keeps its mode, and a symlinked settings file (a dotfiles manager) keeps
    // being a symlink: the file it points at is what changes.
    nonisolated func testPythonWriteKeepsModeAndSymlinks() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let target = dir + "/dotfiles-settings.json"
        FileManager.default.createFile(atPath: target, contents: Data("{}".utf8),
                                       attributes: [.posixPermissions: 0o640])
        let link = dir + "/settings.json"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        XCTAssertEqual(try runPython(ClaudeCodeRemotePython.write(path: link, data: Data("{\"b\":2}".utf8))), "ok")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link), target)
        XCTAssertEqual(FileManager.default.contents(atPath: target), Data("{\"b\":2}".utf8))
        let mode = (try FileManager.default.attributesOfItem(atPath: target)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(mode, 0o640)
    }

    nonisolated func testPythonReadDistinguishesMissingFromUnreadable() throws {
        let dir = try scratchDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir + "/locked")
            try? FileManager.default.removeItem(atPath: dir)
        }
        XCTAssertEqual(ClaudeCodeRemoteRead(pythonOutput: try runPython(ClaudeCodeRemotePython.read(path: dir + "/nope/settings.json"))),
                       .missing)
        FileManager.default.createFile(atPath: dir + "/locked", contents: Data("x".utf8),
                                       attributes: [.posixPermissions: 0o000])
        if case .failed = ClaudeCodeRemoteRead(pythonOutput: try runPython(ClaudeCodeRemotePython.read(path: dir + "/locked"))) {
        } else {
            XCTFail("an unreadable file must not read as missing")
        }
    }

    nonisolated func testPythonExecutableCheck() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        FileManager.default.createFile(atPath: dir + "/x", contents: Data(), attributes: [.posixPermissions: 0o755])
        FileManager.default.createFile(atPath: dir + "/n", contents: Data(), attributes: [.posixPermissions: 0o644])
        XCTAssertEqual(try runPython(ClaudeCodeRemotePython.isExecutable(path: dir + "/x")), "yes")
        XCTAssertEqual(try runPython(ClaudeCodeRemotePython.isExecutable(path: dir + "/n")), "no")
        XCTAssertEqual(try runPython(ClaudeCodeRemotePython.isExecutable(path: dir)), "no", "a directory is not a program")
        XCTAssertEqual(try runPython(ClaudeCodeRemotePython.isExecutable(path: dir + "/gone")), "no")
    }

    // Run here, on this Mac, the token must say "this machine": that is the whole refusal.
    nonisolated func testPythonMachineTokenMatchesThisMac() throws {
        // The app side HMACs the FakeBootSessionUUID override when it is set; the Python reads the
        // real value. Same skip as iTermMachineIdentityTests.
        try XCTSkipUnless((iTermAdvancedSettingsModel.fakeBootSessionUUID() ?? "").isEmpty,
                          "FakeBootSessionUUID override is set")
        let token = try runPython(iTermMachineIdentity.pythonStatementsReturningToken())
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: token), .localhost, token)
    }
}
