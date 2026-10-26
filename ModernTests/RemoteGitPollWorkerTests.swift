//
//  RemoteGitPollWorkerTests.swift
//  iTerm2 ModernTests
//
//  Git state for a host reached through SSH Integration comes from it2_git_state.py run there
//  (RemoteGitStateParityTests checks its meaning against libgit2). These cover the Mac side:
//  reading its output, which arrives through a pty, and the per-connection worker that runs it.
//

import XCTest
@testable import iTerm2SharedARC

final class RemoteGitStateDecodingTests: XCTestCase {
    private func output(_ json: [String: Any], noise: String = "") -> String {
        let data = try! JSONSerialization.data(withJSONObject: json)
        // A pty turns \n into \r\n, and anything the shell prints comes first.
        return noise + "\r\nit2-git-state:" + data.base64EncodedString() + "\r\n"
    }

    private func decode(_ output: String) -> (iTermGitState?, Bool) {
        var timedOut = ObjCBool(false)
        let state = iTermRemoteGitState.state(fromScriptOutput: output, timedOut: &timedOut)
        return (state, timedOut.boolValue)
    }

    func testFullState() throws {
        let (state, timedOut) = decode(output([
            "branch": "main", "ahead": "2", "behind": "", "dirty": true, "adds": 3, "deletes": 1,
            "repoState": "rebase",
            "files": [["a b.txt", "modified", "none"], ["c", "none", "conflicted"], ["d", "renamed", "untracked"]],
            "stats": ["filesAdded": 4, "filesModified": 5, "filesDeleted": 6, "linesInserted": 7, "linesDeleted": 8]
        ], noise: "motd\r\n"))
        XCTAssertFalse(timedOut)
        let s = try XCTUnwrap(state)
        XCTAssertEqual(s.branch, "main")
        XCTAssertEqual(s.ahead, "2")
        XCTAssertEqual(s.behind, "")
        XCTAssertTrue(s.dirty)
        XCTAssertEqual(s.adds, 3)
        XCTAssertEqual(s.deletes, 1)
        XCTAssertEqual(s.repoState, .rebase)
        XCTAssertEqual(s.filesAdded, 4)
        XCTAssertEqual(s.filesModified, 5)
        XCTAssertEqual(s.filesDeleted, 6)
        XCTAssertEqual(s.linesInserted, 7)
        XCTAssertEqual(s.linesDeleted, 8)
        let files = try XCTUnwrap(s.fileStatuses)
        XCTAssertEqual(files.map(\.path), ["a b.txt", "c", "d"])
        XCTAssertEqual(files.map(\.indexStatus), [.modified, .none, .renamed])
        XCTAssertEqual(files.map(\.workdirStatus), [.none, .conflicted, .untracked])
        XCTAssertGreaterThan(s.creationTime, 0)
    }

    // Without stats or a base, libgit2 leaves the list nil, not empty.
    func testNoFilesMeansNil() throws {
        let (state, _) = decode(output(["branch": "main", "ahead": "", "behind": "", "dirty": false,
                                        "adds": 0, "deletes": 0, "repoState": "none"]))
        XCTAssertNil(try XCTUnwrap(state).fileStatuses)
    }

    func testNotARepository() {
        let (state, timedOut) = decode(output(["repo": false]))
        XCTAssertNil(state)
        XCTAssertFalse(timedOut)
        XCTAssertTrue(iTermRemoteGitState.scriptOutputIsWellFormed(output(["repo": false])))
    }

    func testTimeout() {
        let (state, timedOut) = decode(output(["timeout": true]))
        XCTAssertNil(state)
        XCTAssertTrue(timedOut)
    }

    func testGarbage() {
        for text in ["", "python3: not found\r\n", "it2-git-state:!!!\r\n", "it2-git-state:" + Data("[1]".utf8).base64EncodedString()] {
            let (state, timedOut) = decode(text)
            XCTAssertNil(state, text)
            XCTAssertFalse(timedOut, text)
            XCTAssertFalse(iTermRemoteGitState.scriptOutputIsWellFormed(text), text)
        }
    }

    func testErrorIsNotWellFormed() {
        XCTAssertFalse(iTermRemoteGitState.scriptOutputIsWellFormed(output(["error": "KeyError: x"])))
    }

    // The command line survives sh, whatever the python path and arguments contain.
    func testCommandLineRunsUnderSh() throws {
        let dir = NSTemporaryDirectory() + "it's a \"dir\" $HOME"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        let command = iTermRemoteGitState.commandLine(python: "/usr/bin/python3",
                                                      path: dir,
                                                      gitBase: "it's",
                                                      includeDiffStats: true,
                                                      timeout: 20)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(iTermRemoteGitState.scriptOutputIsWellFormed(text), text)
    }
}

@MainActor
final class RemoteGitPollWorkerTests: XCTestCase {
    private final class FakeRunner: RemoteGitCommandRunning {
        var python: String? = "/usr/bin/python3"
        var pythonLookups = 0
        var commands = [String]()
        var pending = [(String?) -> Void]()

        func remoteGitPythonPath(_ completion: @escaping (String?) -> Void) {
            pythonLookups += 1
            completion(python)
        }

        func runRemoteGitCommand(_ commandLine: String, completion: @escaping (String?) -> Void) {
            commands.append(commandLine)
            pending.append(completion)
        }

        func answer(_ json: [String: Any]) {
            let data = try! JSONSerialization.data(withJSONObject: json)
            let completions = pending
            pending = []
            for completion in completions {
                completion("it2-git-state:" + data.base64EncodedString() + "\r\n")
            }
        }
    }

    private let state: [String: Any] = ["branch": "main", "ahead": "", "behind": "", "dirty": false,
                                        "adds": 0, "deletes": 0, "repoState": "none"]

    func testIdenticalRequestsInFlightShareOneRun() {
        let runner = FakeRunner()
        let worker = iTermRemoteGitPollWorker(runner: runner)
        var answers = [String?]()
        for _ in 0..<2 {
            worker.requestPath("/r", gitBase: nil, includeDiffStats: true) { state, _ in
                answers.append(state?.branch)
            }
        }
        XCTAssertEqual(runner.commands.count, 1)
        runner.answer(state)
        XCTAssertEqual(answers, ["main", "main"])
    }

    func testDifferentBaseIsADifferentRequest() {
        let runner = FakeRunner()
        let worker = iTermRemoteGitPollWorker(runner: runner)
        worker.requestPath("/r", gitBase: nil, includeDiffStats: true) { _, _ in }
        worker.requestPath("/r", gitBase: "main", includeDiffStats: true) { _, _ in }
        // HEAD means no base, as for the local worker.
        worker.requestPath("/r", gitBase: "HEAD", includeDiffStats: true) { _, _ in }
        XCTAssertEqual(runner.commands.count, 2)
    }

    func testFreshAnswerIsReused() {
        let runner = FakeRunner()
        let worker = iTermRemoteGitPollWorker(runner: runner)
        worker.requestPath("/r", gitBase: nil, includeDiffStats: false) { _, _ in }
        runner.answer(state)
        var branch: String?
        worker.requestPath("/r", gitBase: nil, includeDiffStats: false) { state, _ in
            branch = state?.branch
        }
        XCTAssertEqual(branch, "main")
        XCTAssertEqual(runner.commands.count, 1)
    }

    func testInvalidateForgetsTheAnswer() {
        let runner = FakeRunner()
        let worker = iTermRemoteGitPollWorker(runner: runner)
        worker.requestPath("/r", gitBase: nil, includeDiffStats: false) { _, _ in }
        runner.answer(state)
        worker.invalidateCache(forPath: "/r")
        worker.requestPath("/r", gitBase: nil, includeDiffStats: false) { _, _ in }
        XCTAssertEqual(runner.commands.count, 2)
    }

    func testPythonIsLookedUpOnce() {
        let runner = FakeRunner()
        let worker = iTermRemoteGitPollWorker(runner: runner)
        worker.requestPath("/a", gitBase: nil, includeDiffStats: false) { _, _ in }
        worker.requestPath("/b", gitBase: nil, includeDiffStats: false) { _, _ in }
        XCTAssertEqual(runner.pythonLookups, 1)
        XCTAssertTrue(runner.commands.allSatisfy { $0.hasPrefix("'/usr/bin/python3' -c ") }, "\(runner.commands)")
    }

    func testNoPythonMeansNoState() {
        let runner = FakeRunner()
        runner.python = nil
        let worker = iTermRemoteGitPollWorker(runner: runner)
        var called = false
        worker.requestPath("/r", gitBase: nil, includeDiffStats: false) { state, timedOut in
            XCTAssertNil(state)
            XCTAssertFalse(timedOut)
            called = true
        }
        XCTAssertTrue(called)
        XCTAssertTrue(runner.commands.isEmpty)
    }

    // A job whose answer never arrives (the connection dropped) must not leave the poller waiting.
    func testNoAnswerTimesOut() {
        let runner = FakeRunner()
        let worker = iTermRemoteGitPollWorker(runner: runner)
        worker.extraDeadline = 0.01
        worker.gitTimeoutOverride = 0
        let done = expectation(description: "timed out")
        worker.requestPath("/r", gitBase: nil, includeDiffStats: false) { state, timedOut in
            XCTAssertNil(state)
            XCTAssertTrue(timedOut)
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        // The late answer goes nowhere.
        runner.answer(state)
    }
}

// The status bar's git component and the workgroup toolbar draw through iTermGitStringMaker. Off
// this Mac it used to read only the it2git variables, so a poller reading the host through its
// connection was ignored.
@MainActor
final class GitStringMakerRemoteTests: XCTestCase, iTermObject {
    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    private final class AlwaysPoll: NSObject, iTermGitPollerDelegate {
        func gitPollerShouldPoll(_ poller: iTermGitPoller, after lastPoll: Date?) -> Bool { true }
    }

    private final class FixedWorker: NSObject, iTermGitPollWorkerProtocol {
        func requestPath(_ path: String,
                         gitBase: String?,
                         includeDiffStats: Bool,
                         completion: @escaping (iTermGitState?, Bool) -> Void) {
            let state = iTermGitState()
            state.branch = "remote-branch"
            completion(state, false)
        }

        func invalidateCache(forPath path: String) {}
    }

    func testRemoteWorkerStateIsShownOffThisMac() {
        let scope = iTermVariableScope()
        scope.add(iTermVariables(context: [], owner: self), toScopeNamed: nil)
        scope.setValue("far.example.com", forVariableNamed: iTermVariableKeySessionHostname)
        scope.setValue(false, forVariableNamed: iTermVariableKeySessionIsLocalhost)
        scope.setValue("/repo", forVariableNamed: iTermVariableKeySessionPath)
        let poller = iTermGitPoller(cadence: 100) {}
        let delegate = AlwaysPoll()
        poller.delegate = delegate
        poller.enabled = true
        let maker = iTermGitStringMaker(scope: scope, gitPoller: poller)
        XCTAssertFalse(maker.onLocalhost)
        // Without a remote worker, and with no it2git variables, there is nothing to show.
        XCTAssertNil(maker.currentState)

        let worker = FixedWorker()
        poller.worker = worker
        poller.currentDirectory = "/repo"
        poller.bump()
        XCTAssertEqual(maker.currentState?.branch, "remote-branch")
        withExtendedLifetime(delegate) {}
    }
}

