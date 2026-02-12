//
//  PTYSessionWiringTests.swift
//  ModernTests
//
//  Tests that verify PTYSession correctly wires taskDidChangePaused and
//  shortcutNavigationDidComplete to call performBlock(joinedThreads:) and set
//  the appropriate state on VT100ScreenMutableState.
//
//  In v3, these methods use performBlock(joinedThreads:) (synchronous, NS_NOESCAPE)
//  rather than mutateAsynchronously. The block sets the relevant property on
//  mutableState but does not call scheduleTokenExecution.
//

import XCTest
@testable import iTerm2SharedARC

/// Tests for PTYSession's wiring of pause/unpause and shortcut navigation to the scheduler.
final class PTYSessionWiringTests: XCTestCase {

    private var session: PTYSession!
    private var spyScreen: SpyVT100Screen!
    private var spyMutableState: SpyVT100ScreenMutableState!
    private var performer: MockSideEffectPerformer!

    override func setUp() {
        super.setUp()
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(true)
        performer = MockSideEffectPerformer()
        spyScreen = SpyVT100Screen()
        spyMutableState = SpyVT100ScreenMutableState(sideEffectPerformer: performer)

        // Inject the spy mutableState into the spy screen so performBlock(joinedThreads:)
        // executes blocks against it.
        spyScreen.spyMutableState = spyMutableState

        // Create a PTYSession with synthetic=YES to avoid full initialization
        session = PTYSession(synthetic: true)

        // Swap the screen with our spy
        session.screen = spyScreen
    }

    override func tearDown() {
        // Cleanup
        spyMutableState.terminalEnabled = false
        waitForMutationQueue()

        session = nil
        spyScreen = nil
        spyMutableState = nil
        performer = nil
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(false)
        super.tearDown()
    }

    // MARK: - taskDidChangePaused Tests

    func testTaskDidChangePausedCallsPerformBlockWithJoinedThreads() {
        // REQUIREMENT: taskDidChangePaused should call performBlock(joinedThreads:) on screen
        spyScreen.reset()

        // Call the method under test
        session.taskDidChangePaused(PTYTask(), paused: false)

        // Verify performBlockWithJoinedThreads was called
        XCTAssertEqual(spyScreen.performBlockWithJoinedThreadsCallCount, 1,
                       "taskDidChangePaused should call performBlock(joinedThreads:) exactly once")
    }

    func testTaskDidChangePausedWithPausedTrueSetsTaskPaused() {
        // REQUIREMENT: When paused=true, block sets mutableState.taskPaused = true
        spyScreen.reset()
        spyMutableState.taskPaused = false

        // Call the method under test -- block executes synchronously
        session.taskDidChangePaused(PTYTask(), paused: true)

        // Verify taskPaused was set to true
        XCTAssertTrue(spyMutableState.taskPaused,
                      "Block should set taskPaused = true when paused parameter is true")
    }

    func testTaskDidChangePausedWithPausedFalseSetsTaskPaused() {
        // REQUIREMENT: When paused=false, block sets mutableState.taskPaused = false
        // NOTE: In v3, scheduleTokenExecution is NOT called by taskDidChangePaused.
        spyScreen.reset()
        spyMutableState.taskPaused = true  // Start in paused state

        // Call the method under test -- block executes synchronously
        session.taskDidChangePaused(PTYTask(), paused: false)

        // Verify taskPaused was set to false
        XCTAssertFalse(spyMutableState.taskPaused,
                       "Block should set taskPaused = false when paused parameter is false")
    }

    // MARK: - shortcutNavigationDidComplete Tests

    func testShortcutNavigationDidCompleteCallsPerformBlockWithJoinedThreads() {
        // REQUIREMENT: shortcutNavigationDidComplete should call performBlock(joinedThreads:) on screen
        spyScreen.reset()

        // Call the method under test using performSelector since the protocol
        // conformance (iTermShortcutNavigationModeHandlerDelegate) is in PTYSession+Private.h
        // which can't be imported in the bridging header due to circular dependencies.
        session.perform(NSSelectorFromString("shortcutNavigationDidComplete"))

        // Verify performBlockWithJoinedThreads was called
        XCTAssertEqual(spyScreen.performBlockWithJoinedThreadsCallCount, 1,
                       "shortcutNavigationDidComplete should call performBlock(joinedThreads:) exactly once")
    }

    func testShortcutNavigationDidCompleteSetsShortcutNavigationMode() {
        // REQUIREMENT: shortcutNavigationDidComplete block sets shortcutNavigationMode = false
        // NOTE: In v3, scheduleTokenExecution is NOT called by shortcutNavigationDidComplete.
        spyScreen.reset()
        spyMutableState.shortcutNavigationMode = true  // Start in shortcut nav mode

        // Call the method under test using performSelector
        session.perform(NSSelectorFromString("shortcutNavigationDidComplete"))

        // Verify shortcutNavigationMode was set to false
        XCTAssertFalse(spyMutableState.shortcutNavigationMode,
                       "Block should set shortcutNavigationMode = false")
    }

    // MARK: - Helpers

    private func waitForMutationQueue() {
        let expectation = self.expectation(description: "Mutation queue drained")
        iTermGCD.mutationQueue().async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }
}

// MARK: - Backpressure Wiring Tests

/// Tests for PTYSession's wiring of backpressureReleaseHandler to PTYTask.updateReadSourceState.
/// This is critical for resuming reads after backpressure drops.
final class PTYSessionBackpressureWiringTests: XCTestCase {

    private var session: PTYSession!
    private var realScreen: VT100Screen!
    private var spyTask: SpyPTYTask!

    override func setUp() {
        super.setUp()
        // Enable fairness scheduler flag BEFORE creating components
        // (taskDidRegister is gated by useFairnessScheduler)
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(true)

        // Create a PTYSession with synthetic=YES to avoid full initialization
        session = PTYSession(synthetic: true)

        // Use a real VT100Screen (not spy) because we need the real tokenExecutor
        realScreen = VT100Screen()

        // Swap the screen
        session.screen = realScreen

        // Create spy task
        spyTask = SpyPTYTask()
    }

    override func tearDown() {
        // Cleanup - disable terminal to unregister from FairnessScheduler
        realScreen.mutableState.terminalEnabled = false
        waitForMutationQueue()

        session = nil
        realScreen = nil
        spyTask = nil
        iTermAdvancedSettingsModel.setUseFairnessSchedulerForTesting(false)
        super.tearDown()
    }

    // MARK: - taskDidRegister Backpressure Wiring Tests

    func testTaskDidRegisterWiresBackpressureReleaseHandler() {
        // REQUIREMENT: taskDidRegister should set backpressureReleaseHandler on tokenExecutor
        let executor = realScreen.mutableState.tokenExecutor

        // Before calling taskDidRegister, handler should be nil
        XCTAssertNil(executor.backpressureReleaseHandler,
                     "Handler should be nil before taskDidRegister")

        // Call the method under test
        session.taskDidRegister(spyTask)

        // After calling taskDidRegister, handler should be set
        XCTAssertNotNil(executor.backpressureReleaseHandler,
                        "backpressureReleaseHandler should be set after taskDidRegister")
    }

    func testTaskDidRegisterSetsTokenExecutorOnTask() {
        // REQUIREMENT: taskDidRegister sets task.tokenExecutor = executor
        let executor = realScreen.mutableState.tokenExecutor

        XCTAssertNil(spyTask.tokenExecutor as AnyObject?,
                     "Task's tokenExecutor should be nil before taskDidRegister")

        // Call the method under test
        session.taskDidRegister(spyTask)

        // Verify task has tokenExecutor set
        XCTAssertTrue(spyTask.tokenExecutor === executor,
                      "Task's tokenExecutor should be set to screen's tokenExecutor")
    }

    func testBackpressureReleaseHandlerCallsUpdateReadSourceState() {
        // REQUIREMENT: When backpressureReleaseHandler is invoked,
        // it should call updateReadSourceState on the task.
        // This is the critical wiring that resumes reads after backpressure drops.

        let executor = realScreen.mutableState.tokenExecutor

        // Wire up via taskDidRegister
        session.taskDidRegister(spyTask)

        // Verify handler is set
        guard let handler = executor.backpressureReleaseHandler else {
            XCTFail("backpressureReleaseHandler should be set")
            return
        }

        // Reset spy counts
        spyTask.resetSpyCounts()
        XCTAssertEqual(spyTask.updateReadSourceStateCallCount, 0,
                       "updateReadSourceState should not have been called yet")

        // Invoke the handler (simulating backpressure release)
        handler()

        // Verify updateReadSourceState was called
        XCTAssertEqual(spyTask.updateReadSourceStateCallCount, 1,
                       "backpressureReleaseHandler should call updateReadSourceState exactly once")
    }

    func testBackpressureReleaseHandlerUsesWeakTask() {
        // REQUIREMENT: The handler uses a weak reference to task to avoid retain cycles.
        // If the task is deallocated, the handler should not crash.

        let executor = realScreen.mutableState.tokenExecutor

        // Create a task that will be deallocated
        var temporaryTask: SpyPTYTask? = SpyPTYTask()
        session.taskDidRegister(temporaryTask!)

        // Verify handler is set
        guard let handler = executor.backpressureReleaseHandler else {
            XCTFail("backpressureReleaseHandler should be set")
            return
        }

        // Deallocate the task
        temporaryTask = nil

        // Invoking the handler after task deallocation should not crash
        // (weak reference becomes nil, updateReadSourceState is not called)
        handler()

        // If we reach here without crashing, the test passes
    }

    // MARK: - Helpers

    private func waitForMutationQueue() {
        let expectation = self.expectation(description: "Mutation queue drained")
        iTermGCD.mutationQueue().async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }
}
