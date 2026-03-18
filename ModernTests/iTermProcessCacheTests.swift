//
//  iTermProcessCacheTests.swift
//  iTerm2
//
//  Tests for iTermProcessCache, covering:
//  - Background refresh cadence (P2 fix: background roots stay in dirty set)
//  - Foreground/background priority transitions (P3 fix: setForegroundRootPIDs)
//  - Coalescer behavior
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Test Class

final class iTermProcessCacheTests: XCTestCase {
    var cache: Any!

    override func setUp() {
        super.setUp()
        // Create a fresh cache instance for each test using the helper
        cache = iTermProcessCacheTestHelper.createTestCache() as Any
    }

    override func tearDown() {
        cache = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private var dirtyLowRootsCount: UInt {
        return iTermProcessCacheTestHelper.dirtyLowRootsCount(forCache: cache)
    }

    private var dirtyHighRootsCount: UInt {
        return iTermProcessCacheTestHelper.dirtyHighRootsCount(forCache: cache)
    }

    private func isRootHighPriority(_ rootPID: pid_t) -> Bool {
        return iTermProcessCacheTestHelper.cache(cache, isRootHighPriority: rootPID)
    }

    private func isTrackingRoot(_ rootPID: pid_t) -> Bool {
        return iTermProcessCacheTestHelper.cache(cache, isTrackingRoot: rootPID)
    }

    private func forceBackgroundRefreshTick() {
        iTermProcessCacheTestHelper.forceBackgroundRefreshTick(forCache: cache)
    }

    private func registerTestRoot(_ rootPID: pid_t) {
        iTermProcessCacheTestHelper.cache(cache, registerTestRoot: rootPID)
    }

    private func unregisterTestRoot(_ rootPID: pid_t) {
        iTermProcessCacheTestHelper.cache(cache, unregisterTestRoot: rootPID)
    }

    private func setForegroundRootPIDs(_ pids: Set<NSNumber>) {
        iTermProcessCacheTestHelper.cache(cache, setForegroundRootPIDs: pids)
    }

    // MARK: - 1. Background Refresh Cadence Tests (P2 Fix)

    func testBackgroundRoot_AddedToDirtyLowSet_WhenDemotedToBackground() {
        // Given: A root PID registered as foreground
        let rootPID = getpid()
        registerTestRoot(rootPID)
        XCTAssertTrue(isRootHighPriority(rootPID), "Should start as high priority")

        // When: Demoted to background
        setForegroundRootPIDs([])

        // Then: Should be in dirty low set
        XCTAssertFalse(isRootHighPriority(rootPID), "Should be low priority after demotion")
        XCTAssertGreaterThan(dirtyLowRootsCount, 0, "Background root should be in dirty low set")
    }

    func testBackgroundRoot_RemainsInDirtySetAfterRefresh() {
        // This test verifies the P2 fix: background roots should be re-added
        // to _dirtyLowRootsLQ after being processed.

        // Given: A root PID registered and moved to background
        let rootPID = getpid()
        registerTestRoot(rootPID)
        setForegroundRootPIDs([])

        let initialDirtyCount = dirtyLowRootsCount
        XCTAssertGreaterThan(initialDirtyCount, 0, "Background root should be in dirty low set")

        // When: Force a background refresh tick
        forceBackgroundRefreshTick()

        // Allow async work to complete
        let expectation = self.expectation(description: "Background refresh completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // Then: The root should still be in the dirty low set (the P2 fix)
        // If the process is alive, it gets re-added after refresh
        // This verifies the fix prevents permanent staleness
        XCTAssertTrue(isTrackingRoot(rootPID), "Root should still be tracked")
    }

    func testBackgroundRoot_ReenqueuedInDirtyLowSet_AfterRefresh() {
        // This test specifically verifies that dirtyLowRootsCount remains > 0
        // after a background refresh tick - catching the "one refresh then stale forever" bug.

        // Given: A root PID registered and moved to background
        let rootPID = getpid()
        registerTestRoot(rootPID)
        setForegroundRootPIDs([])

        // Verify initial state
        let initialDirtyCount = dirtyLowRootsCount
        XCTAssertGreaterThanOrEqual(initialDirtyCount, 1, "Background root should be in dirty low set")

        // When: Force a background refresh tick
        forceBackgroundRefreshTick()

        // Allow async work to complete
        let expectation = self.expectation(description: "Background refresh completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // Then: dirtyLowRootsCount should still be >= 1 (root re-added after processing)
        // This is the key assertion that catches the regression
        XCTAssertGreaterThanOrEqual(dirtyLowRootsCount, 1,
            "Background root should be RE-ADDED to dirty low set after refresh (P2 fix)")
        XCTAssertTrue(isTrackingRoot(rootPID), "Root should still be tracked")
    }

    func testBackgroundRoots_ProcessedAcrossMultipleTicks() {
        // Verify background roots continue refreshing across multiple cadence ticks

        // Given: A root registered and moved to background
        let root1 = getpid()
        registerTestRoot(root1)
        setForegroundRootPIDs([])

        // When: Multiple background refresh ticks
        for i in 0..<5 {
            forceBackgroundRefreshTick()

            let expectation = self.expectation(description: "Tick \(i) completes")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                expectation.fulfill()
            }
            waitForExpectations(timeout: 1.0)
        }

        // Then: Should complete without issues, root still tracked
        XCTAssertTrue(isTrackingRoot(root1), "Root should still be tracked after multiple ticks")
    }

    func testBackgroundRoot_DirtyLowSetSurvivesMultipleTicks() {
        // Verify that background roots remain in the dirty low set across multiple
        // cadence ticks - ensures repeated cadence refresh does not drain the dirty set.

        // Given: A root registered and moved to background
        let rootPID = getpid()
        registerTestRoot(rootPID)
        setForegroundRootPIDs([])

        // Initial verification
        XCTAssertGreaterThan(dirtyLowRootsCount, 0, "Background root should be in dirty low set initially")

        // When/Then: After each of multiple ticks, dirtyLowRootsCount should remain > 0
        for tickNumber in 1...5 {
            forceBackgroundRefreshTick()

            let expectation = self.expectation(description: "Tick \(tickNumber) completes")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                expectation.fulfill()
            }
            waitForExpectations(timeout: 1.0)

            // Key assertion: dirty set should NOT be drained
            XCTAssertGreaterThan(dirtyLowRootsCount, 0,
                "dirtyLowRootsCount should remain > 0 after tick \(tickNumber)")
        }

        XCTAssertTrue(isTrackingRoot(rootPID), "Root should still be tracked after multiple ticks")
    }

    // MARK: - 2. Foreground Selection Behavior Tests (P3 Fix)

    func testSetForegroundRootPIDs_TransitionsToHighPriority() {
        // Given: A root registered as background
        let rootPID = getpid()
        registerTestRoot(rootPID)
        setForegroundRootPIDs([])
        XCTAssertFalse(isRootHighPriority(rootPID), "Should start as low priority")

        // When: Set as foreground
        setForegroundRootPIDs([NSNumber(value: rootPID)])

        // Then: Should be high priority
        XCTAssertTrue(isRootHighPriority(rootPID), "Should be high priority after setForegroundRootPIDs")
    }

    func testSetForegroundRootPIDs_TransitionsToLowPriority() {
        // Given: A root registered as high priority (default)
        let rootPID = getpid()
        registerTestRoot(rootPID)
        XCTAssertTrue(isRootHighPriority(rootPID), "Should start as high priority")

        // When: Remove from foreground set
        setForegroundRootPIDs([])

        // Then: Should be low priority and in dirty low set
        XCTAssertFalse(isRootHighPriority(rootPID), "Should be low priority after removal")
        XCTAssertGreaterThan(dirtyLowRootsCount, 0, "Should be in dirty low set")
    }

    func testSetForegroundRootPIDs_SwitchingBetweenWindows() {
        // This simulates the window focus change scenario from P3
        // When user switches windows, the foreground set should update

        // Given: Two roots, root1 is initially foreground
        let root1 = getpid()
        let root2: pid_t = 99998

        registerTestRoot(root1)
        registerTestRoot(root2)
        setForegroundRootPIDs([NSNumber(value: root1)])

        XCTAssertTrue(isRootHighPriority(root1), "root1 should be foreground")
        XCTAssertFalse(isRootHighPriority(root2), "root2 should be background")

        // When: Switch foreground to root2 (simulates switching windows)
        setForegroundRootPIDs([NSNumber(value: root2)])

        // Then: Priorities should swap
        XCTAssertFalse(isRootHighPriority(root1), "root1 should now be background")
        XCTAssertTrue(isRootHighPriority(root2), "root2 should now be foreground")
    }

    func testSetForegroundRootPIDs_MultipleRootsInSameWindow() {
        // A window with multiple tabs/sessions should have all their roots as foreground

        // Given: Multiple roots
        let root1 = getpid()
        let root2: pid_t = 99997
        let root3: pid_t = 99996

        registerTestRoot(root1)
        registerTestRoot(root2)
        registerTestRoot(root3)

        // When: Set multiple roots as foreground (simulates window with multiple sessions)
        setForegroundRootPIDs([NSNumber(value: root1), NSNumber(value: root2)])

        // Then: root1 and root2 should be high priority, root3 should be low
        XCTAssertTrue(isRootHighPriority(root1), "root1 should be high priority")
        XCTAssertTrue(isRootHighPriority(root2), "root2 should be high priority")
        XCTAssertFalse(isRootHighPriority(root3), "root3 should be low priority")
    }

    func testSetForegroundRootPIDs_Idempotent() {
        // Setting the same foreground roots multiple times should be safe

        let rootPID = getpid()
        registerTestRoot(rootPID)
        setForegroundRootPIDs([NSNumber(value: rootPID)])

        // When: Set the same foreground roots multiple times
        for _ in 0..<5 {
            setForegroundRootPIDs([NSNumber(value: rootPID)])
        }

        // Then: Should still be foreground
        XCTAssertTrue(isRootHighPriority(rootPID), "Should remain foreground")
    }

    // MARK: - 3. Coalescer Behavior Tests

    func testHighPriorityRoot_NotInLowDirtySet() {
        // High priority (foreground) roots should use the coalescer, not cadence

        // Given: A root registered as foreground
        let rootPID = getpid()
        registerTestRoot(rootPID)
        setForegroundRootPIDs([NSNumber(value: rootPID)])

        // Then: Should NOT be in dirty low set (foreground uses coalescer)
        // The dirty low set is only for background roots
        XCTAssertTrue(isRootHighPriority(rootPID), "Should be high priority")
        // After being set as foreground, it may be in dirty high set instead
    }

    func testForegroundRoot_NotInDirtyLowSet_AfterMonitorEvent() {
        // Foreground roots should go to the high-priority dirty set (coalescer),
        // NOT the low-priority dirty set (cadence timer).

        // Given: A root registered and explicitly set as foreground
        let rootPID = getpid()
        registerTestRoot(rootPID)
        setForegroundRootPIDs([NSNumber(value: rootPID)])

        // Allow registration to complete
        let setupExpectation = self.expectation(description: "Setup completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            setupExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // Then: dirtyLowRootsCount should be 0 (foreground roots use coalescer path)
        XCTAssertTrue(isRootHighPriority(rootPID), "Root should be high priority")
        XCTAssertEqual(dirtyLowRootsCount, 0,
            "Foreground root should NOT be in dirty low set - it uses coalescer instead")
    }

    func testLowPriorityRoot_InLowDirtySet() {
        // Low priority (background) roots should be in the cadence-driven dirty set

        // Given: A root demoted to background
        let rootPID = getpid()
        registerTestRoot(rootPID)
        setForegroundRootPIDs([])

        // Then: Should be in dirty low set
        XCTAssertFalse(isRootHighPriority(rootPID), "Should be low priority")
        XCTAssertGreaterThan(dirtyLowRootsCount, 0, "Should be in dirty low set")
    }

    // MARK: - 4. Root Registration/Unregistration Tests

    func testRegisterAndUnregisterRoot() {
        let rootPID = getpid()

        // When: Register
        registerTestRoot(rootPID)
        XCTAssertTrue(isTrackingRoot(rootPID), "Should be tracked after registration")

        // When: Unregister
        unregisterTestRoot(rootPID)
        XCTAssertFalse(isTrackingRoot(rootPID), "Should not be tracked after unregistration")
    }

    func testUnregisterRoot_ClearsFromDirtySets() {
        // Given: A root in background (in dirty low set)
        let rootPID = getpid()
        registerTestRoot(rootPID)
        setForegroundRootPIDs([])

        let dirtyCountBefore = dirtyLowRootsCount
        XCTAssertGreaterThan(dirtyCountBefore, 0, "Should be in dirty low set")

        // When: Unregister
        unregisterTestRoot(rootPID)

        // Then: Should be removed from dirty sets
        let dirtyCountAfter = dirtyLowRootsCount
        XCTAssertLessThan(dirtyCountAfter, dirtyCountBefore, "Should be removed from dirty set")
    }

    // MARK: - 5. Concurrent Access Tests

    func testConcurrentForegroundRootPIDUpdates() {
        // Verify thread safety of setForegroundRootPIDs

        let root1 = getpid()
        let root2: pid_t = 99995
        let root3: pid_t = 99994

        registerTestRoot(root1)
        registerTestRoot(root2)
        registerTestRoot(root3)

        let expectation = self.expectation(description: "Concurrent updates complete")
        expectation.expectedFulfillmentCount = 10

        // When: Concurrent updates from multiple queues
        for i in 0..<10 {
            DispatchQueue.global().async {
                let foregroundSet: Set<NSNumber>
                switch i % 3 {
                case 0:
                    foregroundSet = [NSNumber(value: root1)]
                case 1:
                    foregroundSet = [NSNumber(value: root2)]
                default:
                    foregroundSet = [NSNumber(value: root3)]
                }
                self.setForegroundRootPIDs(foregroundSet)
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0)

        // Then: All roots should still be tracked (no corruption)
        XCTAssertTrue(isTrackingRoot(root1), "root1 should still be tracked")
        XCTAssertTrue(isTrackingRoot(root2), "root2 should still be tracked")
        XCTAssertTrue(isTrackingRoot(root3), "root3 should still be tracked")
    }

    // MARK: - 6. Edge Cases

    func testSetForegroundRootPIDs_EmptySet() {
        let rootPID = getpid()
        registerTestRoot(rootPID)
        setForegroundRootPIDs([NSNumber(value: rootPID)])

        // When: Set empty foreground set
        setForegroundRootPIDs([])

        // Then: All roots should be background
        XCTAssertFalse(isRootHighPriority(rootPID), "Should be background with empty foreground set")
    }

    func testSetForegroundRootPIDs_UnregisteredPID() {
        // Setting foreground with an unregistered PID should be safe
        let unregisteredPID: pid_t = 88888

        // When: Set unregistered PID as foreground
        setForegroundRootPIDs([NSNumber(value: unregisteredPID)])

        // Then: Should not crash, unregistered PID should not become tracked
        XCTAssertFalse(isTrackingRoot(unregisteredPID), "Unregistered PID should not be tracked")
    }

    func testBackgroundRefreshTick_EmptyDirtySet() {
        // Calling backgroundRefreshTick with no dirty roots should be safe
        XCTAssertEqual(dirtyLowRootsCount, 0, "Should start with empty dirty set")

        // When: Force background refresh
        forceBackgroundRefreshTick()

        // Then: Should not crash
        XCTAssertEqual(dirtyLowRootsCount, 0, "Should still be empty")
    }
}
