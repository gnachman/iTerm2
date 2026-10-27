//
//  SSHPaneProcessInfoTests.swift
//  iTerm2 ModernTests
//
//  Jobs in a tmux pane on a host reached through SSH Integration (Phase 5). framer.py reports the
//  process subtree of every pid registered with it, not only the login shell's, so a pane whose
//  pid is registered gets its own view of the host's process table. Before this, a remote pane
//  answered with the gateway's login shell, whose job is `tmux -CC`, and `claude` running in the
//  pane was never seen.
//

import XCTest
@testable import iTerm2SharedARC

private final class FakeRunner: SSHCommandRunning {
    var registered = [pid_t]()
    var deregistered = [pid_t]()
    func runRemoteCommand(_ commandLine: String, completion: @escaping (Data, Int32) -> ()) {}
    func registerProcess(_ pid: pid_t) { registered.append(pid) }
    func deregisterProcess(_ pid: pid_t) { deregistered.append(pid) }
    func poll(_ completion: @escaping (Data) -> ()) {}
}

@MainActor
final class SSHPaneProcessInfoTests: XCTestCase {
    private let loginShell: pid_t = 100
    private let panePID: pid_t = 300

    /// The host's process table as framer's poll reports it:
    ///   100 -zsh (the connection's login shell) -> 101 tmux -CC (foreground)
    ///   200 tmux: server -> 300 -zsh (the pane) -> 301 claude (foreground) -> 302 node (an MCP helper)
    private let listing = """
    $begin ps
    +100 1 Ss Sun Oct  4 20:00:00 2026 -zsh
    +101 100 S+ Sun Oct  4 20:00:01 2026 tmux -CC attach
    +200 1 Ss Sun Oct  4 20:00:01 2026 tmux: server
    +300 200 Ss Sun Oct  4 20:00:02 2026 -zsh
    +301 300 S+ Sun Oct  4 20:00:03 2026 claude
    +302 301 S+ Sun Oct  4 20:00:04 2026 node /usr/lib/mcp-server.js
    """

    private func makeProvider(_ runner: FakeRunner) -> SSHProcessInfoProvider {
        let provider = SSHProcessInfoProvider(rootPID: loginShell, runner: runner)
        provider.register(trackedPID: loginShell)
        return provider
    }

    func testPaneReportsItsOwnJob() throws {
        let runner = FakeRunner()
        let provider = makeProvider(runner)
        provider.register(trackedPID: panePID)
        provider.handle(listing)
        let pane = provider.sessionProcessInfoProvider(forPID: panePID)
        let job = try XCTUnwrap(pane.cachedProcessInfoIfAvailable())
        XCTAssertEqual(job.processID, 302, "the deepest foreground job, as for any session")
        XCTAssertEqual(job.foregroundJobAncestorNames, ["node", "claude"],
                       "the chain stops at the pane's login shell, so claude is seen")
    }

    // claude starts caffeinate, in the foreground process group with its stdio on /dev/null,
    // which framer marks with "!". The job is named after claude, as it is locally; the raw
    // deepest foreground job is still caffeinate.
    func testJobNameSkipsAForegroundHelperOffTheTerminal() throws {
        let runner = FakeRunner()
        let provider = makeProvider(runner)
        provider.register(trackedPID: panePID)
        provider.handle("""
        $begin ps
        +100 1 Ss Sun Oct  4 20:00:00 2026 -zsh
        +101 100 S+ Sun Oct  4 20:00:01 2026 claude
        +102 101 S+! Sun Oct  4 20:00:02 2026 caffeinate -i -t 300
        +300 1 Ss Sun Oct  4 20:00:02 2026 -zsh
        +301 300 S+ Sun Oct  4 20:00:03 2026 claude
        +302 301 S+! Sun Oct  4 20:00:04 2026 caffeinate -i -t 300
        """)
        XCTAssertEqual(provider.displayForegroundJob(for: loginShell)?.processID, 101)
        XCTAssertEqual(provider.deepestForegroundJob(for: loginShell)?.processID, 102)
        XCTAssertEqual(provider.displayForegroundJob(for: panePID)?.processID, 301, "a remote tmux pane too")
    }

    // A framer too old to mark anything: every foreground process counts, as before.
    func testUnmarkedListingKeepsTheDeepestForegroundJob() {
        let provider = makeProvider(FakeRunner())
        provider.handle(listing)
        XCTAssertEqual(provider.displayForegroundJob(for: loginShell)?.processID, 101)
    }

    // The pid a session's job is looked up by must be the one its provider knows it by.
    func testProviderKeyFollowsTheProvider() {
        func key(framerPane: Bool = false, tmuxPane: Bool = false, conductor: Bool = false,
                 framing: Bool = false, remotePane: pid_t = 0) -> pid_t {
            return ProcessInfoProviderKey.pid(framerPane: framerPane, tmuxPaneOfGateway: tmuxPane,
                                              hasConductor: conductor, framing: framing,
                                              framedPID: 500, remotePanePID: remotePane,
                                              effectivePID: 42)
        }
        XCTAssertEqual(key(), 42, "a local session")
        XCTAssertEqual(key(conductor: true, framing: true), 500, "a session on a host reached through SSH Integration")
        XCTAssertEqual(key(conductor: true, framing: false), 42, "a connection not framing yet")
        XCTAssertEqual(key(tmuxPane: true, remotePane: 301), 301, "a remote tmux pane")
        XCTAssertEqual(key(tmuxPane: true), 42, "a local tmux pane")
        XCTAssertEqual(key(tmuxPane: true, conductor: true, framing: true, remotePane: 301), 500,
                       "a remote tmux pane running it2ssh has a connection of its own")
        XCTAssertEqual(key(framerPane: true, conductor: true, framing: true, remotePane: 301), 301,
                       "a framer pane uses its host's provider")
    }

    // The gateway session keeps answering for the connection's login shell.
    func testRootStillReportsTheLoginShellsJob() throws {
        let runner = FakeRunner()
        let provider = makeProvider(runner)
        provider.register(trackedPID: panePID)
        provider.handle(listing)
        let job = try XCTUnwrap(provider.cachedProcessInfoIfAvailable())
        XCTAssertEqual(job.processID, 101)
    }

    // A pane whose pid was never registered has nothing to report, rather than borrowing the
    // login shell's job.
    func testUnregisteredPaneReportsNothing() {
        let provider = makeProvider(FakeRunner())
        provider.handle(listing)
        XCTAssertNil(provider.sessionProcessInfoProvider(forPID: panePID).cachedProcessInfoIfAvailable())
    }

    // A closed pane stops being tracked, both here and by framer.
    func testUnregisteringAPaneDropsIt() {
        let runner = FakeRunner()
        let provider = makeProvider(runner)
        provider.register(trackedPID: panePID)
        provider.handle(listing)
        provider.unregister(trackedPID: panePID)
        provider.handle("$begin ps\n~301 300 S+ Sun Oct  4 20:00:03 2026 claude\n")
        XCTAssertNil(provider.sessionProcessInfoProvider(forPID: panePID).cachedProcessInfoIfAvailable())
        XCTAssertEqual(runner.deregistered, [panePID])
    }

    // framer forgets its registrations when the conductor resets it. Every tracked pid has to be
    // registered again, not just the login shell, or each pane goes blank after a reset.
    func testReregisteringAfterAResetIncludesPanes() {
        let runner = FakeRunner()
        let provider = makeProvider(runner)
        provider.register(trackedPID: panePID)
        runner.registered = []
        provider.reregisterTrackedPIDs()
        XCTAssertEqual(Set(runner.registered), [loginShell, panePID])
    }

    // The same pane asked twice gets the same adapter, so its "already asked for an update" state
    // is not lost between calls.
    func testAdapterIsReusedPerPID() {
        let provider = makeProvider(FakeRunner())
        XCTAssertTrue(provider.sessionProcessInfoProvider(forPID: panePID)
                      === provider.sessionProcessInfoProvider(forPID: panePID))
    }
}
