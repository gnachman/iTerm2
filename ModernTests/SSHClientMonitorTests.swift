//
//  SSHClientMonitorTests.swift
//  iTerm2
//
//  F-482: when it2ssh runs on this Mac, iTerm2 learns its process from the secret
//  server's socket peer, watches it, and recovers the session when it dies. When it
//  can't be watched, an unframed prompt mark offers Disconnect once.
//

import XCTest
@testable import iTerm2SharedARC

private final class FakeProcessInspector: SSHClientProcessInspecting {
    struct Info {
        var parent: pid_t
        var startTime: Date?
        var arguments: [String]?
    }
    var processes = [pid_t: Info]()

    func parentPID(of pid: pid_t) -> pid_t {
        return processes[pid]?.parent ?? 0
    }

    func startTime(of pid: pid_t) -> Date? {
        return processes[pid]?.startTime
    }

    func arguments(of pid: pid_t) -> [String]? {
        return processes[pid]?.arguments
    }

    func childPIDs(of pid: pid_t) -> [pid_t] {
        return processes.filter { $0.value.parent == pid }.map { $0.key }.sorted()
    }

    var listeners = Set<pid_t>()
    var unknownSockets = Set<pid_t>()

    func hasListeningUnixSocket(_ pid: pid_t) -> Bool? {
        if unknownSockets.contains(pid) {
            return nil
        }
        return listeners.contains(pid)
    }
}

final class SSHClientProcessLocatorTests: XCTestCase {
    private let it2sshArgs = ["bash", "/Users/me/.iterm2/it2ssh", "example.com"]
    private let t0 = Date(timeIntervalSince1970: 1000)
    private let t1 = Date(timeIntervalSince1970: 1001)
    private let t2 = Date(timeIntervalSince1970: 1002)
    private let t3 = Date(timeIntervalSince1970: 1003)

    // nc (40) <- command substitution subshell (30) <- it2ssh (20) <- zsh (10) <- login (1)
    private func makeInspector() -> FakeProcessInspector {
        let inspector = FakeProcessInspector()
        inspector.processes[40] = .init(parent: 30, startTime: t3, arguments: ["/usr/bin/nc", "-U", "secrets"])
        inspector.processes[30] = .init(parent: 20, startTime: t2, arguments: it2sshArgs)
        inspector.processes[20] = .init(parent: 10, startTime: t1, arguments: it2sshArgs)
        inspector.processes[10] = .init(parent: 1, startTime: t0, arguments: ["-zsh"])
        inspector.processes[1] = .init(parent: 0, startTime: t0, arguments: ["login"])
        return inspector
    }

    // F-786: a restored session's job still runs ssh only if an ssh client or it2ssh is
    // among its descendants.
    func testFindsSSHClientAmongDescendants() {
        let inspector = FakeProcessInspector()
        // login (100) -> zsh (110) -> it2ssh (120) -> ssh (130)
        inspector.processes[110] = .init(parent: 100, startTime: t0, arguments: ["-zsh"])
        inspector.processes[120] = .init(parent: 110, startTime: t1, arguments: it2sshArgs)
        inspector.processes[130] = .init(parent: 120, startTime: t2, arguments: ["/usr/bin/ssh", "-t", "example.com"])
        let locator = SSHClientProcessLocator(inspector: inspector)
        XCTAssertTrue(locator.hasSSHClient(amongDescendantsOf: 100))

        // ssh died while iTerm2 was down: only the shell is left.
        inspector.processes[120] = nil
        inspector.processes[130] = nil
        XCTAssertFalse(locator.hasSSHClient(amongDescendantsOf: 100))

        // Not fooled by something merely named like ssh.
        inspector.processes[140] = .init(parent: 110, startTime: t3, arguments: ["/usr/bin/sshd-keygen-wrapper"])
        XCTAssertFalse(locator.hasSSHClient(amongDescendantsOf: 100))
        XCTAssertFalse(locator.hasSSHClient(amongDescendantsOf: 0))
    }

    func testAncestorsOfPeerStartAtItsParent() {
        let locator = SSHClientProcessLocator(inspector: makeInspector())
        let ancestors = locator.ancestors(ofPeer: 40)
        XCTAssertEqual(ancestors.map { $0.pid }, [30, 20, 10])
        XCTAssertEqual(ancestors.map { $0.startTime }, [t2, t1, t0])
    }

    func testFindsLiveIT2SSHAfterSubshellExits() {
        let inspector = makeInspector()
        let locator = SSHClientProcessLocator(inspector: inspector)
        let ancestors = locator.ancestors(ofPeer: 40)
        // By the time the conductor hooks, nc and the subshell are gone.
        inspector.processes[40] = nil
        inspector.processes[30] = nil
        XCTAssertEqual(locator.liveIT2SSHProcess(among: ancestors), 20)
    }

    // Even if the subshell were still around, it2ssh itself is the one to watch.
    func testPrefersOutermostIT2SSH() {
        let locator = SSHClientProcessLocator(inspector: makeInspector())
        XCTAssertEqual(locator.liveIT2SSHProcess(among: locator.ancestors(ofPeer: 40)), 20)
    }

    // If it2ssh already died, the shell must not be mistaken for it.
    func testNoLiveIT2SSH() {
        let inspector = makeInspector()
        let locator = SSHClientProcessLocator(inspector: inspector)
        let ancestors = locator.ancestors(ofPeer: 40)
        inspector.processes[30] = nil
        inspector.processes[20] = nil
        XCTAssertEqual(locator.liveIT2SSHProcess(among: ancestors), 0)
    }

    // A reused pid has a different start time.
    func testReusedPIDIsRejected() {
        let inspector = makeInspector()
        let locator = SSHClientProcessLocator(inspector: inspector)
        let ancestors = locator.ancestors(ofPeer: 40)
        inspector.processes[30] = nil
        inspector.processes[20]?.startTime = Date(timeIntervalSince1970: 5000)
        XCTAssertEqual(locator.liveIT2SSHProcess(among: ancestors), 0)
    }

    func testUnknownPeerHasNoAncestors() {
        let locator = SSHClientProcessLocator(inspector: makeInspector())
        XCTAssertTrue(locator.ancestors(ofPeer: 999).isEmpty)
        XCTAssertTrue(locator.ancestors(ofPeer: 0).isEmpty)
    }

    // The real inspector sees that this test process is a child's parent.
    func testSystemInspectorFindsParent() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["600"]
        try child.run()
        defer {
            child.terminate()
        }
        let locator = SSHClientProcessLocator(inspector: SystemSSHClientProcessInspector())
        let ancestors = locator.ancestors(ofPeer: child.processIdentifier)
        XCTAssertEqual(ancestors.first?.pid, getpid())
        XCTAssertNotNil(ancestors.first?.startTime)
    }
}

final class SSHClientMonitorTests: XCTestCase {
    private func launch(_ path: String, _ args: [String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try process.run()
        return process
    }

    func testExitOfWatchedProcessCallsHandler() throws {
        let monitor = SSHClientMonitor()
        let process = try launch("/bin/sleep", ["600"])
        let exited = expectation(description: "exit handler")
        XCTAssertTrue(monitor.watch(processID: process.processIdentifier, clientUniqueID: "abc") {
            exited.fulfill()
        })
        XCTAssertTrue(monitor.isWatching(clientUniqueID: "abc"))
        process.terminate()
        wait(for: [exited], timeout: 60)
        XCTAssertFalse(monitor.isWatching(clientUniqueID: "abc"))
    }

    func testAlreadyExitedProcessCallsHandler() throws {
        let monitor = SSHClientMonitor()
        let process = try launch("/usr/bin/true", [])
        process.waitUntilExit()
        let exited = expectation(description: "exit handler")
        _ = monitor.watch(processID: process.processIdentifier, clientUniqueID: "abc") {
            exited.fulfill()
        }
        wait(for: [exited], timeout: 60)
    }

    func testStopWatchingSuppressesHandler() throws {
        let monitor = SSHClientMonitor()
        let process = try launch("/bin/sleep", ["600"])
        _ = monitor.watch(processID: process.processIdentifier, clientUniqueID: "abc") {
            XCTFail("handler should not run after stopWatching")
        }
        monitor.stopWatching(clientUniqueID: "abc")
        XCTAssertFalse(monitor.isWatching(clientUniqueID: "abc"))
        process.terminate()
        process.waitUntilExit()
        // Let any stray event handler run before the test ends.
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 60)
    }

    func testAnnouncesUnwatchedConnectionOnce() {
        let monitor = SSHClientMonitor()
        XCTAssertTrue(monitor.shouldAnnounceUnframedPrompt(clientUniqueID: "abc"))
        XCTAssertFalse(monitor.shouldAnnounceUnframedPrompt(clientUniqueID: "abc"))
        XCTAssertTrue(monitor.shouldAnnounceUnframedPrompt(clientUniqueID: "def"))
    }

    func testDoesNotAnnounceWatchedConnection() throws {
        let monitor = SSHClientMonitor()
        let process = try launch("/bin/sleep", ["600"])
        defer {
            monitor.stopWatching(clientUniqueID: "abc")
            process.terminate()
        }
        XCTAssertTrue(monitor.watch(processID: process.processIdentifier, clientUniqueID: "abc") {})
        XCTAssertFalse(monitor.shouldAnnounceUnframedPrompt(clientUniqueID: "abc"))
    }
}

// F-351: when a watched it2ssh dies, its ssh client is orphaned but still logged in
// to the remote host. Recovery kills it, but only when it is positively the same
// process that was it2ssh's child.
final class SSHClientKillTests: XCTestCase {
    private let it2sshArgs = ["bash", "/Users/me/.iterm2/it2ssh", "example.com"]
    private let sshArgs = ["/usr/bin/ssh", "-t", "--", "example.com", "exec", "sh"]
    private let t1 = Date(timeIntervalSince1970: 1001)
    private let t2 = Date(timeIntervalSince1970: 1002)
    private var signals = [(pid_t, Int32)]()

    // it2ssh (20) <- zsh (10), with ssh (21) as it2ssh's child.
    private func makeInspector() -> FakeProcessInspector {
        let inspector = FakeProcessInspector()
        inspector.processes[10] = .init(parent: 1, startTime: t1, arguments: ["-zsh"])
        inspector.processes[20] = .init(parent: 10, startTime: t1, arguments: it2sshArgs)
        inspector.processes[21] = .init(parent: 20, startTime: t2, arguments: sshArgs)
        return inspector
    }

    private func makeMonitor(_ inspector: FakeProcessInspector) -> SSHClientMonitor {
        return SSHClientMonitor(inspector: inspector) { [weak self] pid, signal in
            self?.signals.append((pid, signal))
        }
    }

    // Simulates killing it2ssh: the ssh client is reparented to launchd.
    private func killIT2SSH(_ inspector: FakeProcessInspector) {
        inspector.processes[20] = nil
        inspector.processes[21]?.parent = 1
    }

    private func watch(_ monitor: SSHClientMonitor) {
        monitor.recordSSHClient(ofIT2SSHProcessID: 20, clientUniqueID: "abc")
    }

    func testKillsOrphanedSSHClient() {
        let inspector = makeInspector()
        let monitor = makeMonitor(inspector)
        watch(monitor)
        killIT2SSH(inspector)
        XCTAssertTrue(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        XCTAssertEqual(signals.map { $0.0 }, [21])
        XCTAssertEqual(signals.map { $0.1 }, [SIGKILL])
        // Only once.
        XCTAssertFalse(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        XCTAssertEqual(signals.count, 1)
    }

    // If it2ssh is alive, its ssh client isn't orphaned (e.g., Disconnect from a
    // hung remote) and must be left alone.
    func testDoesNotKillWhileIT2SSHIsAlive() {
        let inspector = makeInspector()
        let monitor = makeMonitor(inspector)
        watch(monitor)
        XCTAssertFalse(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        XCTAssertTrue(signals.isEmpty)
    }

    // A process that reused it2ssh's pid doesn't make it look alive.
    func testIT2SSHPIDReuseCountsAsDead() {
        let inspector = makeInspector()
        let monitor = makeMonitor(inspector)
        watch(monitor)
        killIT2SSH(inspector)
        inspector.processes[20] = .init(parent: 1, startTime: Date(timeIntervalSince1970: 9000), arguments: ["other"])
        XCTAssertTrue(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        XCTAssertEqual(signals.map { $0.0 }, [21])
    }

    // A process that reused the ssh client's pid must never be signaled.
    func testSSHPIDReuseIsNotSignaled() {
        let inspector = makeInspector()
        let monitor = makeMonitor(inspector)
        watch(monitor)
        killIT2SSH(inspector)
        inspector.processes[21] = .init(parent: 1, startTime: Date(timeIntervalSince1970: 9000), arguments: sshArgs)
        XCTAssertFalse(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        XCTAssertTrue(signals.isEmpty)
    }

    // A failure to read a live it2ssh's start time must not make it look dead.
    func testIT2SSHStillParentIsNotSignaled() {
        let inspector = makeInspector()
        let monitor = makeMonitor(inspector)
        watch(monitor)
        inspector.processes[20]?.startTime = nil
        XCTAssertFalse(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        XCTAssertTrue(signals.isEmpty)
    }

    // A ControlMaster may carry other sessions' connections.
    func testControlMasterIsNotSignaled() {
        let inspector = makeInspector()
        let monitor = makeMonitor(inspector)
        watch(monitor)
        killIT2SSH(inspector)
        inspector.listeners.insert(21)
        XCTAssertFalse(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        XCTAssertTrue(signals.isEmpty)
    }

    func testUnknownSocketsAreNotSignaled() {
        let inspector = makeInspector()
        let monitor = makeMonitor(inspector)
        watch(monitor)
        killIT2SSH(inspector)
        inspector.unknownSockets.insert(21)
        XCTAssertFalse(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        XCTAssertTrue(signals.isEmpty)
    }

    // The real inspector tells a unix-socket listener from a process without one.
    func testSystemInspectorFindsListeningUnixSocket() throws {
        let inspector = SystemSSHClientProcessInspector()
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["600"]
        try sleeper.run()
        defer {
            sleeper.terminate()
        }
        XCTAssertEqual(inspector.hasListeningUnixSocket(sleeper.processIdentifier), false)

        // This test process listens once the server is up.
        let path = "/tmp/it2-listen-test-\(getpid())"
        defer {
            unlink(path)
        }
        let server = try XCTUnwrap(SecretServer(socketURL: URL(fileURLWithPath: path)))
        try server.listen()
        XCTAssertEqual(inspector.hasListeningUnixSocket(getpid()), true)
    }

    func testChangedArgumentsAreNotSignaled() {
        let inspector = makeInspector()
        let monitor = makeMonitor(inspector)
        watch(monitor)
        killIT2SSH(inspector)
        inspector.processes[21]?.arguments = ["/usr/bin/vim"]
        XCTAssertFalse(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        XCTAssertTrue(signals.isEmpty)
    }

    func testExitedSSHClientIsNotSignaled() {
        let inspector = makeInspector()
        let monitor = makeMonitor(inspector)
        watch(monitor)
        killIT2SSH(inspector)
        inspector.processes[21] = nil
        XCTAssertFalse(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        XCTAssertTrue(signals.isEmpty)
    }

    // Only a child that is ssh is recorded.
    func testNonSSHChildIsNotRecorded() {
        let inspector = makeInspector()
        inspector.processes[21]?.arguments = ["/bin/cat"]
        let monitor = makeMonitor(inspector)
        watch(monitor)
        killIT2SSH(inspector)
        XCTAssertFalse(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        XCTAssertTrue(signals.isEmpty)
    }

    // With more than one candidate there's no telling which carried the connection.
    func testAmbiguousChildrenAreNotRecorded() {
        let inspector = makeInspector()
        inspector.processes[22] = .init(parent: 20, startTime: t2, arguments: sshArgs)
        let monitor = makeMonitor(inspector)
        watch(monitor)
        killIT2SSH(inspector)
        inspector.processes[22]?.parent = 1
        XCTAssertFalse(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        XCTAssertTrue(signals.isEmpty)
    }

    func testForgottenClientIsNotSignaled() {
        let inspector = makeInspector()
        let monitor = makeMonitor(inspector)
        watch(monitor)
        monitor.forgetSSHClient(clientUniqueID: "abc")
        killIT2SSH(inspector)
        XCTAssertFalse(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        XCTAssertTrue(signals.isEmpty)
    }

    func testUnknownClientIsNotSignaled() {
        let monitor = makeMonitor(makeInspector())
        XCTAssertFalse(monitor.killOrphanedSSHClient(clientUniqueID: "nope"))
        XCTAssertTrue(signals.isEmpty)
    }

    // End to end with real processes: a fake it2ssh (bash) runs a fake ssh (sleep,
    // reached through a link named ssh), and is killed.
    func testRealOrphanedSSHClientIsKilled() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("it2-kill-\(getpid())-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: dir)
        }
        let fakeSSH = dir.appendingPathComponent("ssh")
        try FileManager.default.createSymbolicLink(at: fakeSSH, withDestinationURL: URL(fileURLWithPath: "/bin/sleep"))
        let fakeIT2SSH = dir.appendingPathComponent("it2ssh")
        // The trailing command keeps bash from exec'ing ssh in its place.
        try "\"\(fakeSSH.path)\" 600\n:\n".write(to: fakeIT2SSH, atomically: true, encoding: .utf8)

        let it2ssh = Process()
        it2ssh.executableURL = URL(fileURLWithPath: "/bin/bash")
        it2ssh.arguments = [fakeIT2SSH.path]
        try it2ssh.run()
        let inspector = SystemSSHClientProcessInspector()
        var sshPID: pid_t = 0
        var stopPolling = false
        // Wait for bash to start the child.
        let started = expectation(description: "ssh started")
        func poll() {
            if stopPolling {
                return
            }
            if let child = inspector.childPIDs(of: it2ssh.processIdentifier).first,
               inspector.arguments(of: child)?.first.map({ ($0 as NSString).lastPathComponent }) == "ssh" {
                sshPID = child
                started.fulfill()
                return
            }
            DispatchQueue.main.async { poll() }
        }
        poll()
        wait(for: [started], timeout: 60)
        stopPolling = true
        defer {
            if it2ssh.isRunning {
                it2ssh.terminate()
            }
        }
        guard sshPID > 0 else {
            XCTFail("fake ssh never started")
            return
        }
        let sshStart = inspector.startTime(of: sshPID)
        defer {
            // Clean up only if the test failed to end the very same process.
            if sshStart != nil && inspector.startTime(of: sshPID) == sshStart {
                kill(sshPID, SIGKILL)
            }
        }

        let monitor = SSHClientMonitor()
        let it2sshExited = expectation(description: "it2ssh exited")
        XCTAssertTrue(monitor.watch(processID: it2ssh.processIdentifier, clientUniqueID: "abc") {
            it2sshExited.fulfill()
        })
        kill(it2ssh.processIdentifier, SIGKILL)
        wait(for: [it2sshExited], timeout: 60)
        it2ssh.waitUntilExit()

        let sshExited = expectation(description: "ssh exited")
        let source = DispatchSource.makeProcessSource(identifier: sshPID, eventMask: .exit, queue: .main)
        source.setEventHandler {
            sshExited.fulfill()
            source.cancel()
        }
        source.resume()
        XCTAssertNotNil(inspector.startTime(of: sshPID), "the orphaned ssh is still running")
        XCTAssertTrue(monitor.killOrphanedSSHClient(clientUniqueID: "abc"))
        wait(for: [sshExited], timeout: 60)
    }
}

final class SecretServerPeerTests: XCTestCase {
    // Fetches a secret the way it2ssh does, so the socket peer is nc, a child of
    // this test process.
    private func fetchSecretWithNC(from path: String) throws -> String {
        let nc = Process()
        nc.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        nc.arguments = ["-U", path]
        let pipe = Pipe()
        nc.standardOutput = pipe
        nc.standardInput = FileHandle.nullDevice
        try nc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        nc.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func testClaimReportsPeerAncestors() throws {
        let path = "/tmp/it2-secret-test-\(getpid())"
        defer {
            unlink(path)
        }
        let server = try XCTUnwrap(SecretServer(socketURL: URL(fileURLWithPath: path)))
        try server.listen()
        let secret = try fetchSecretWithNC(from: path)
        XCTAssertFalse(secret.isEmpty)

        let claim = try XCTUnwrap(server.claim(secret))
        // nc's parent is this process.
        XCTAssertEqual(claim.clientAncestors.first?.pid, getpid())

        XCTAssertNil(server.claim(secret), "a secret is good only once")
        XCTAssertNil(server.claim("bogus"))
    }
}
