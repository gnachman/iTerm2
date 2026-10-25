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
