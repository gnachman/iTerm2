//
//  WorkingDirectoryFlowTests.swift
//  iTerm2
//
//  Tests for working directory flow across 16 scenarios of OSC 7 and shell integration.
//
//  ## Testing Scope
//
//  These tests verify the VT100Screen layer behavior:
//  - Interval tree storage of working directories
//  - The shouldExpectWorkingDirectoryUpdates flag
//  - Which delegate methods are called (getWorkingDirectory vs pollLocalDirectoryOnly)
//
//  NOT tested at this level (tested elsewhere):
//  - VT100Terminal escape sequence parsing (see VT100TerminalTests)
//  - iTermSessionDirectoryTracker invalidation logic (see iTermSessionDirectoryTrackerTests)
//  - Actual PTYSession directory polling implementation
//
//  ## Key Behavior Being Protected
//
//  When OSC 7 or shell integration provides a working directory:
//  1. The shouldExpectWorkingDirectoryUpdates flag is set
//  2. Window title changes trigger pollLocalDirectoryOnly (not full polling)
//  3. pollLocalDirectoryOnly updates ONLY lastLocalDirectory, NOT the interval tree
//  4. Therefore, the escape-sequence-provided directory is never overwritten by polling
//

import XCTest
@testable import iTerm2SharedARC

class WorkingDirectoryFlowTests: XCTestCase {
    var harness: TerminalTestHarness!

    override func setUp() {
        super.setUp()
        harness = TerminalTestHarness()
    }

    override func tearDown() {
        harness = nil
        super.tearDown()
    }

    // MARK: - OSC 7 Both Local+Remote (scenarios 1-4)

    /// Scenario 1: OSC 7 L+R, no shell integration
    /// Expected: Respect last OSC 7
    func testOSC7BothNoShellIntegration_RespectsLastOSC7() {
        // Simulate: local fish sends OSC 7, user SSHs, remote fish sends OSC 7
        harness.sendOSC7(path: "/local/home")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/home")

        // Remote OSC 7 (simulating after SSH)
        harness.sendOSC7(path: "/remote/home")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/home")

        // Window title change should NOT trigger full poll (flag is set)
        harness.resetCalls()
        harness.sendWindowTitle("vim")
        harness.sync()
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 0)
        XCTAssertEqual(harness.delegate.pollLocalDirectoryOnlyCalls.count, 1)
    }

    /// Scenario 2: OSC 7 L+R, shell integration local only
    /// Expected: Most recent wins
    func testOSC7BothShellIntegrationLocal_MostRecentWins() {
        // Local shell integration sets directory
        harness.sendRemoteHost(user: "user", host: "localhost")
        harness.sendCurrentDirectory(path: "/local/dir")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/dir")

        // OSC 7 from remote overwrites
        harness.sendOSC7(path: "/remote/dir")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/dir")

        // Local shell integration wins again
        harness.sendCurrentDirectory(path: "/local/dir2")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/dir2")
    }

    /// Scenario 3: OSC 7 L+R, shell integration both
    /// Expected: Most recent wins
    func testOSC7BothShellIntegrationBoth_MostRecentWins() {
        // Local OSC 7
        harness.sendOSC7(path: "/local/fish")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/fish")

        // Remote shell integration
        harness.sendRemoteHost(user: "user", host: "remote.host")
        harness.sendCurrentDirectory(path: "/remote/shell")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/shell")

        // Remote OSC 7
        harness.sendOSC7(path: "/remote/fish")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/fish")
    }

    /// Scenario 4: OSC 7 L+R, shell integration remote only
    /// Expected: Most recent wins
    func testOSC7BothShellIntegrationRemote_MostRecentWins() {
        // Local OSC 7
        harness.sendOSC7(path: "/local/path")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/path")

        // SSH + remote shell integration
        harness.sendRemoteHost(user: "user", host: "server")
        harness.sendCurrentDirectory(path: "/remote/path")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/path")

        // Remote OSC 7 wins
        harness.sendOSC7(path: "/remote/fish")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/fish")
    }

    // MARK: - No OSC 7 (scenarios 5-8)

    /// Scenario 5: No OSC 7, no shell integration
    /// Expected: Local directory poller is only option (edge case)
    func testNoOSC7NoShellIntegration_UsesLocalPoller() {
        // Window title should trigger full poll since nothing else provides directory
        harness.sendWindowTitle("vim")
        harness.sync()
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 1)
        XCTAssertFalse(harness.expectsWorkingDirectoryUpdates)
    }

    /// Scenario 6: No OSC 7, shell integration local only
    /// Expected: Last CurrentDir respected
    /// Note: Window title is ignored when remote host is set (returns early at line 895-897
    /// in VT100ScreenMutableState+TerminalDelegate.m). This is distinct from the
    /// shouldExpectWorkingDirectoryUpdates check (line 904-908).
    func testNoOSC7ShellIntegrationLocal_RespectsCurrentDir() {
        harness.sendRemoteHost(user: "user", host: "localhost")
        harness.sendCurrentDirectory(path: "/local/dir")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/dir")

        // Window title returns early when remote host is set - no polling at all
        harness.resetCalls()
        harness.sendWindowTitle("vim")
        harness.sync()
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 0)
        XCTAssertEqual(harness.delegate.pollLocalDirectoryOnlyCalls.count, 0)
    }

    /// Scenario 7: No OSC 7, shell integration both
    /// Expected: Most recent wins
    func testNoOSC7ShellIntegrationBoth_MostRecentWins() {
        // Local shell integration
        harness.sendRemoteHost(user: "user", host: "localhost")
        harness.sendCurrentDirectory(path: "/local/home")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/home")

        // SSH + remote shell integration
        harness.sendRemoteHost(user: "user", host: "server")
        harness.sendCurrentDirectory(path: "/remote/home")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/home")

        // Return to local
        harness.sendRemoteHost(user: "user", host: "localhost")
        harness.sendCurrentDirectory(path: "/local/home2")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/home2")
    }

    /// Scenario 8: No OSC 7, shell integration remote only
    /// Expected: Stuck on last remote dir after SSH ends (edge case)
    func testNoOSC7ShellIntegrationRemote_StuckAfterSSH() {
        // Initially no directory info - poller works
        XCTAssertFalse(harness.expectsWorkingDirectoryUpdates)

        // SSH with shell integration
        harness.sendRemoteHost(user: "user", host: "server")
        harness.sendCurrentDirectory(path: "/remote/home")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/home")
        XCTAssertTrue(harness.expectsWorkingDirectoryUpdates)

        // After SSH ends, we're stuck (no way to know SSH ended without local shell integration)
        // Window title change won't help update the path
        harness.resetCalls()
        harness.sendWindowTitle("local shell")
        harness.sync()
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 0)
    }

    // MARK: - OSC 7 Local Only (scenarios 9-12)

    /// Scenario 9: OSC 7 local only, no shell integration
    /// Expected: Wrong path for remote (edge case)
    func testOSC7LocalNoShellIntegration_WrongPathForRemote() {
        harness.sendOSC7(path: "/local/home")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/home")

        // After SSH, local OSC 7 keeps sending local path (wrong but unavoidable)
        harness.sendOSC7(path: "/local/home") // Still sending local path
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/home")
    }

    /// Scenario 10: OSC 7 local only, shell integration local only
    /// Expected: Wrong path for remote (edge case)
    func testOSC7LocalShellIntegrationLocal_WrongPathForRemote() {
        harness.sendRemoteHost(user: "user", host: "localhost")
        harness.sendOSC7(path: "/local/fish")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/fish")

        // Most recent between OSC 7 and CurrentDir
        harness.sendCurrentDirectory(path: "/local/shell")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/shell")
    }

    /// Scenario 11: OSC 7 local only, shell integration both
    /// Expected: Most recent wins
    func testOSC7LocalShellIntegrationBoth_MostRecentWins() {
        // Local OSC 7
        harness.sendOSC7(path: "/local/fish")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/fish")

        // Remote shell integration should win
        harness.sendRemoteHost(user: "user", host: "server")
        harness.sendCurrentDirectory(path: "/remote/home")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/home")
    }

    /// Scenario 12: OSC 7 local only, shell integration remote only
    /// Expected: Most recent wins
    func testOSC7LocalShellIntegrationRemote_MostRecentWins() {
        // Local OSC 7
        harness.sendOSC7(path: "/local/fish")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/fish")

        // Remote shell integration wins after SSH
        harness.sendRemoteHost(user: "user", host: "server")
        harness.sendCurrentDirectory(path: "/remote/home")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/home")
    }

    // MARK: - OSC 7 Remote Only (scenarios 13-16)

    /// Scenario 13: OSC 7 remote only, no shell integration
    /// Expected: Local poller until SSH, then stuck (edge case)
    func testOSC7RemoteNoShellIntegration_LocalPollerThenStuck() {
        // Initially uses local poller
        harness.sendWindowTitle("local")
        harness.sync()
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 1)
        XCTAssertFalse(harness.expectsWorkingDirectoryUpdates)

        // After SSH, remote fish sends OSC 7
        harness.sendOSC7(path: "/remote/fish")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/fish")
        XCTAssertTrue(harness.expectsWorkingDirectoryUpdates)

        // Now stuck - can't detect SSH ended
        harness.resetCalls()
        harness.sendWindowTitle("back local")
        harness.sync()
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 0)
    }

    /// Scenario 14: OSC 7 remote only, shell integration local only
    /// Expected: Most recent wins
    func testOSC7RemoteShellIntegrationLocal_MostRecentWins() {
        // Local shell integration
        harness.sendRemoteHost(user: "user", host: "localhost")
        harness.sendCurrentDirectory(path: "/local/home")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/home")

        // Remote OSC 7 wins
        harness.sendOSC7(path: "/remote/fish")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/fish")

        // Local shell integration wins again when returning
        harness.sendRemoteHost(user: "user", host: "localhost")
        harness.sendCurrentDirectory(path: "/local/home2")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/home2")
    }

    /// Scenario 15: OSC 7 remote only, shell integration both
    /// Expected: Most recent wins
    func testOSC7RemoteShellIntegrationBoth_MostRecentWins() {
        // Local shell integration
        harness.sendRemoteHost(user: "user", host: "localhost")
        harness.sendCurrentDirectory(path: "/local/home")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/home")

        // Remote shell integration
        harness.sendRemoteHost(user: "user", host: "server")
        harness.sendCurrentDirectory(path: "/remote/shell")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/shell")

        // Remote OSC 7 wins
        harness.sendOSC7(path: "/remote/fish")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/fish")
    }

    /// Scenario 16: OSC 7 remote only, shell integration remote only
    /// Expected: Most recent wins
    func testOSC7RemoteShellIntegrationRemote_MostRecentWins() {
        // Start with local poller
        harness.sendWindowTitle("local")
        harness.sync()
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 1)

        // Remote shell integration after SSH
        harness.sendRemoteHost(user: "user", host: "server")
        harness.sendCurrentDirectory(path: "/remote/shell")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/shell")

        // Remote OSC 7
        harness.sendOSC7(path: "/remote/fish")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/fish")

        // Remote shell integration again
        harness.sendCurrentDirectory(path: "/remote/shell2")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/shell2")
    }

    // MARK: - Core Flag Behavior Tests

    func testOSC7SetsExpectationFlag() {
        XCTAssertFalse(harness.expectsWorkingDirectoryUpdates)
        harness.sendOSC7(path: "/path")
        harness.sync()
        XCTAssertTrue(harness.expectsWorkingDirectoryUpdates)
    }

    func testCurrentDirectorySetsExpectationFlag() {
        XCTAssertFalse(harness.expectsWorkingDirectoryUpdates)
        harness.sendCurrentDirectory(path: "/path")
        harness.sync()
        XCTAssertTrue(harness.expectsWorkingDirectoryUpdates)
    }

    func testWindowTitleWithFlagTriggersPollLocalOnly() {
        harness.sendOSC7(path: "/path")
        harness.sync()
        harness.resetCalls()

        harness.sendWindowTitle("title")
        harness.sync()

        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 0)
        XCTAssertEqual(harness.delegate.pollLocalDirectoryOnlyCalls.count, 1)
    }

    func testWindowTitleWithoutFlagTriggersFullPoll() {
        harness.sendWindowTitle("title")
        harness.sync()

        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 1)
        XCTAssertEqual(harness.delegate.pollLocalDirectoryOnlyCalls.count, 0)
    }

    // MARK: - Interval Tree Storage Verification Tests

    /// Verify OSC 7 directory is stored and retrievable from interval tree
    func testOSC7DirectoryStoredCorrectly() {
        harness.sendOSC7(path: "/test/path")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/test/path")
    }

    /// Verify shell integration directory is stored and retrievable
    func testCurrentDirectoryStoredCorrectly() {
        harness.sendCurrentDirectory(path: "/shell/path")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/shell/path")
    }

    /// Verify sequential directories update correctly in interval tree
    func testSequentialDirectoriesStoreCorrectly() {
        harness.sendOSC7(path: "/first")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/first")

        harness.sendOSC7(path: "/second")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/second")
    }

    // MARK: - Polling Response Tests

    /// Regression test: When no OSC 7/shell integration has been received,
    /// window title polling should store the polled directory
    func testPollingStoresDirectoryWhenNoEscapeSequencesReceived() {
        harness.delegate.polledWorkingDirectory = "/polled/path"

        // Window title triggers getWorkingDirectory polling
        harness.sendWindowTitle("vim")
        harness.sync()

        // Verify polling was triggered
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 1)

        // The polled path should be stored in interval tree
        // (via the recursive setWorkingDirectory call with the returned path)
        XCTAssertEqual(harness.currentPath, "/polled/path")
    }

    /// Test that polling returning nil doesn't create directory entry
    func testPollingReturnsNilNoDirectoryStored() {
        harness.delegate.polledWorkingDirectory = nil

        harness.sendWindowTitle("vim")
        harness.sync()

        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 1)
        XCTAssertNil(harness.currentPath)
    }

    // MARK: - Core Bugfix Verification Tests

    /// Verify that polling does NOT overwrite an OSC 7 directory.
    /// This is the core behavior the bugfix protects.
    ///
    /// REGRESSION GUARD: If this test fails, the bugfix from issue 12616 has regressed.
    /// The fix ensures that once OSC 7 sets a directory, window title polling calls
    /// pollLocalDirectoryOnly (which does NOT update the interval tree) instead of
    /// getWorkingDirectory (which WOULD update the interval tree).
    func testPollingDoesNotOverwriteOSC7Directory() {
        // Set OSC 7 directory first
        harness.sendOSC7(path: "/remote/path")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/path")
        XCTAssertTrue(harness.expectsWorkingDirectoryUpdates)

        // Verify directory was logged
        XCTAssertEqual(harness.delegate.logWorkingDirectoryCalls.count, 1)
        XCTAssertEqual(harness.delegate.logWorkingDirectoryCalls.first?.path, "/remote/path")

        // Configure poller to return a different path
        harness.delegate.polledWorkingDirectory = "/local/path"
        harness.resetCalls()

        // Trigger window title change (which would poll if flag wasn't set)
        harness.sendWindowTitle("vim")
        harness.sync()

        // CRITICAL: The OSC 7 path must still be current, NOT the polled path
        // Without the bugfix, this would be "/local/path"
        XCTAssertEqual(harness.currentPath, "/remote/path")

        // Mechanism verification:
        // - pollLocalDirectoryOnly was called (updates lastLocalDirectory only)
        // - getWorkingDirectory was NOT called (would update interval tree)
        // - No new directory was logged (interval tree unchanged)
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 0)
        XCTAssertEqual(harness.delegate.pollLocalDirectoryOnlyCalls.count, 1)
        XCTAssertEqual(harness.delegate.logWorkingDirectoryCalls.count, 0)
    }

    /// Verify that polling does NOT overwrite a shell integration directory.
    /// Same protection as OSC 7, via the shouldExpectWorkingDirectoryUpdates flag.
    func testPollingDoesNotOverwriteShellIntegrationDirectory() {
        // Set shell integration directory
        harness.sendCurrentDirectory(path: "/shell/integration/path")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/shell/integration/path")
        XCTAssertTrue(harness.expectsWorkingDirectoryUpdates)

        // Verify directory was logged
        XCTAssertEqual(harness.delegate.logWorkingDirectoryCalls.count, 1)
        XCTAssertEqual(harness.delegate.logWorkingDirectoryCalls.first?.path, "/shell/integration/path")

        // Configure poller to return a different path
        harness.delegate.polledWorkingDirectory = "/local/polled/path"
        harness.resetCalls()

        // Trigger window title change
        harness.sendWindowTitle("title")
        harness.sync()

        // CRITICAL: The shell integration path must still be current
        XCTAssertEqual(harness.currentPath, "/shell/integration/path")

        // Mechanism verification
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 0)
        XCTAssertEqual(harness.delegate.pollLocalDirectoryOnlyCalls.count, 1)
        XCTAssertEqual(harness.delegate.logWorkingDirectoryCalls.count, 0)
    }

    /// Contrast test: When NO OSC 7/shell integration has been received, polling
    /// DOES update the interval tree. This shows what WOULD happen without the fix.
    func testPollingUpdatesIntervalTreeWhenNoEscapeSequences() {
        // Configure poller
        harness.delegate.polledWorkingDirectory = "/polled/path"

        // Trigger window title - this should call getWorkingDirectory, not pollLocalDirectoryOnly
        harness.sendWindowTitle("vim")
        harness.sync()

        // Without the flag, polling DOES update the interval tree
        XCTAssertEqual(harness.currentPath, "/polled/path")
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 1)
        XCTAssertEqual(harness.delegate.pollLocalDirectoryOnlyCalls.count, 0)

        // And it DOES log the directory
        XCTAssertEqual(harness.delegate.logWorkingDirectoryCalls.count, 1)
        XCTAssertEqual(harness.delegate.logWorkingDirectoryCalls.first?.path, "/polled/path")
    }

    /// Verify the flag stays set through multiple operations
    func testFlagPersistsThroughMultipleOperations() {
        XCTAssertFalse(harness.expectsWorkingDirectoryUpdates)

        // Set first OSC 7
        harness.sendOSC7(path: "/first")
        harness.sync()
        XCTAssertTrue(harness.expectsWorkingDirectoryUpdates)

        // Set second OSC 7
        harness.sendOSC7(path: "/second")
        harness.sync()
        XCTAssertTrue(harness.expectsWorkingDirectoryUpdates)

        // Window title changes
        harness.sendWindowTitle("title1")
        harness.sync()
        XCTAssertTrue(harness.expectsWorkingDirectoryUpdates)

        harness.sendWindowTitle("title2")
        harness.sync()
        XCTAssertTrue(harness.expectsWorkingDirectoryUpdates)

        // Shell integration
        harness.sendCurrentDirectory(path: "/shell")
        harness.sync()
        XCTAssertTrue(harness.expectsWorkingDirectoryUpdates)
    }

    // MARK: - OSC 7 Hostname Handling Tests

    /// Verify OSC 7 without hostname (fish shell style) sets flag but not remote host.
    /// Fish shell sends file:///path (no hostname), which sets the path and flag
    /// but does not establish a remote host.
    func testOSC7WithoutHostname_SetsPathAndFlag() {
        // Fish shell sends file:///path (no hostname)
        harness.sendOSC7(path: "/home/user")  // Uses file:///home/user internally
        harness.sync()

        XCTAssertEqual(harness.currentPath, "/home/user")
        XCTAssertTrue(harness.expectsWorkingDirectoryUpdates)
        // Note: No remote host is set by OSC 7 without hostname
    }

    /// Verify OSC 7 with hostname sets path when remote host is already established.
    /// When the hostname matches the current remote host, setPathFromURL runs synchronously.
    func testOSC7WithHostname_SetsPathWhenHostAlreadySet() {
        // First establish the remote host via shell integration
        harness.sendRemoteHost(user: "user", host: "remoteserver.local")
        harness.sync()

        // Now OSC 7 with same hostname takes the synchronous path
        // (since remote host hasn't changed)
        harness.sendOSC7(path: "/home/user", host: "remoteserver.local")
        harness.sync()

        XCTAssertEqual(harness.currentPath, "/home/user")
        XCTAssertTrue(harness.expectsWorkingDirectoryUpdates)
    }

    // NOTE: OSC 7 with a NEW hostname (no prior host) cannot be tested here because:
    // 1. setHost:user:ssh:completion: adds an unmanaged paused side effect
    // 2. The side effect dispatches to main thread, then back to mutation queue
    // 3. completion() (which sets the flag and path) runs after the dispatch chain
    // 4. Our sync() can't process this async chain without a running main runloop
    //
    // This flow IS tested via shell integration: sendRemoteHost() + sendCurrentDirectory()
    // exercises the same code paths with proper test synchronization.

    /// Simulate fish shell behavior: local fish sends OSC 7, remote fish sends OSC 7.
    /// Both use file:///path format (no hostname).
    /// This verifies that remote OSC 7 path is not overwritten by local poller.
    func testFishShellScenario_RemoteOSC7DoesNotGetOverwrittenByPoller() {
        // Local fish sends OSC 7 (no hostname)
        harness.sendOSC7(path: "/local/home")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/local/home")

        // User SSHs, remote fish sends OSC 7 (also no hostname from fish's perspective)
        harness.sendOSC7(path: "/remote/home")
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/remote/home")

        // Local poller would return /local/cwd, but flag prevents overwrite
        harness.delegate.polledWorkingDirectory = "/local/cwd"
        harness.resetCalls()
        harness.sendWindowTitle("vim")
        harness.sync()

        // Key: Remote path is preserved, not overwritten by local poller
        XCTAssertEqual(harness.currentPath, "/remote/home")
        XCTAssertEqual(harness.delegate.getWorkingDirectoryCalls.count, 0)
        XCTAssertEqual(harness.delegate.pollLocalDirectoryOnlyCalls.count, 1)
    }
}
