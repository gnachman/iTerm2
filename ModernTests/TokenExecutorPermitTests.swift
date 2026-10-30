//
//  TokenExecutorPermitTests.swift
//  iTerm2
//
//  Sessions with mutation queues of their own take an execution permit before executing tokens,
//  which limits how many do so at once. Joins never wait for a permit.
//

import XCTest
@testable import iTerm2SharedARC

final class TokenExecutorPermitTests: XCTestCase {
    // Discards every token instead of executing it (unless told otherwise), and lets a test act on
    // each one.
    private final class FakeDelegate: TokenExecutorDelegate {
        private let mutex = Mutex()
        private var _tokensSeen = 0
        private var _highPriorityTokensSeen = 0
        private var _didExecuteCount = 0
        private var _queueTokens = false
        var onToken: ((Int) -> Void)?
        // Set before adding tokens. Executed tokens can switch to high-priority ones; discarded
        // tokens don't.
        var discardTokens = true

        // Like copy mode: tokens wait instead of executing.
        var queueTokens: Bool {
            get { mutex.sync { _queueTokens } }
            set { mutex.sync { _queueTokens = newValue } }
        }

        var tokensSeen: Int {
            return mutex.sync { _tokensSeen }
        }

        var highPriorityTokensSeen: Int {
            return mutex.sync { _highPriorityTokensSeen }
        }

        var didExecuteCount: Int {
            return mutex.sync { _didExecuteCount }
        }

        // Called each time the executor asks whether to queue tokens.
        var onShouldQueueTokens: (() -> Void)?

        func tokenExecutorShouldQueueTokens() -> Bool {
            onShouldQueueTokens?()
            return queueTokens
        }
        func tokenExecutorShouldDiscard(token: VT100Token, highPriority: Bool) -> Bool {
            let count = mutex.sync {
                _tokensSeen += 1
                if highPriority {
                    _highPriorityTokensSeen += 1
                }
                return _tokensSeen
            }
            onToken?(count)
            return discardTokens
        }
        func tokenExecutorDidExecute(lengthTotal: Int, lengthExcludingInBandSignaling: Int, throughput: Int) {
            mutex.sync { _didExecuteCount += 1 }
        }
        func tokenExecutorCursorCoordString() -> NSString { "" }
        func tokenExecutorSync() {}
        func tokenExecutorHandleSideEffectFlags(_ flags: Int64) {}
        func tokenExecutorWillExecuteTokens() {}
    }

    private struct Session {
        let executor: TokenExecutor
        let delegate: FakeDelegate
        let queue: DispatchQueue
    }

    private var sessions = [Session]()

    override func tearDown() {
        sessions.removeAll()
        super.tearDown()
    }

    private func makeSession(permits: ExecutionPermits) -> Session {
        let session = makeUnretainedSession(permits: permits)
        sessions.append(session)
        return session
    }

    // Like makeSession, but the test doesn't keep it alive.
    private func makeUnretainedSession(permits: ExecutionPermits) -> Session {
        let queue = iTermGCD.newMutationQueue()
        let executor = TokenExecutor(VT100Terminal(),
                                     slownessDetector: SlownessDetector(),
                                     queue: queue,
                                     ownsQueue: true,
                                     permits: permits)
        let delegate = FakeDelegate()
        executor.delegate = delegate
        return Session(executor: executor, delegate: delegate, queue: queue)
    }

    private func addTokens(_ count: Int, to session: Session, highPriority: Bool = false) {
        var vector = CVector()
        CVectorCreate(&vector, Int32(count))
        for _ in 0..<count {
            let token = VT100Token()
            token.type = VT100CSI_SET_MODIFIERS
            CVectorAppendVT100Token(&vector, token)
        }
        session.executor.addTokens(vector,
                                   lengthTotal: count,
                                   lengthExcludingInBandSignaling: count,
                                   highPriority: highPriority)
    }

    private func waitUntil(_ description: String, _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        expectation.expectationDescription = description
        wait(for: [expectation], timeout: 30)
    }

    // Spins (for use inside a token, where waiting on the main queue would deadlock) until
    // `condition` holds. Gives up after 30 seconds, so a regression fails the test instead of
    // hanging it.
    private static func spin(_ description: String, until condition: () -> Bool) {
        let deadline = DispatchTime.now().uptimeNanoseconds + 30 * NSEC_PER_SEC
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds > deadline {
                XCTFail("Gave up waiting: \(description)")
                return
            }
        }
    }

    private func spin(for seconds: TimeInterval) {
        let start = DispatchTime.now().uptimeNanoseconds
        while TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1e9 < seconds {}
    }

    // Runs on the executor's queue, in a token, until a join pauses the executor.
    private static func spinUntilPaused(_ executor: TokenExecutor) {
        spin("the join pauses the executor") { executor.isPausedForTesting }
    }

    // A session closed while it waits for a permit leaves the line.
    func testSessionFreedWhileWaitingLeavesTheLine() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        let release = DispatchSemaphore(value: 0)
        a.delegate.onToken = { count in
            if count == 1 {
                _ = release.wait(timeout: .now() + 30)
            }
        }
        addTokens(10, to: a)
        waitUntil("a holds the permit") { permits.inUseForTesting == 1 }

        weak var weakExecutor: TokenExecutor?
        do {
            let b = makeUnretainedSession(permits: permits)
            weakExecutor = b.executor
            addTokens(10, to: b)
            waitUntil("b waits") { permits.waitingCountForTesting == 1 }
        }
        waitUntil("b is freed") { weakExecutor == nil }
        XCTAssertEqual(permits.waitingCountForTesting, 0)

        release.signal()
        waitUntil("a ran") { a.delegate.tokensSeen == 10 }
        waitUntil("nobody runs or waits") { permits.runningCountForTesting == 0 && permits.waitingCountForTesting == 0 }
    }

    // A session closed while it holds an idle permit gives it up, so another session can run.
    func testSessionFreedWhileHoldingAnIdlePermitGivesItUp() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        weak var weakExecutor: TokenExecutor?
        do {
            let a = makeUnretainedSession(permits: permits)
            weakExecutor = a.executor
            addTokens(10, to: a)
            waitUntil("a ran") { a.delegate.tokensSeen == 10 }
            waitUntil("a's permit is idle") { permits.idleHolderCountForTesting == 1 }
        }
        waitUntil("a is freed") { weakExecutor == nil }
        XCTAssertEqual(permits.inUseForTesting, 0)

        let b = makeSession(permits: permits)
        addTokens(10, to: b)
        waitUntil("b ran") { b.delegate.tokensSeen == 10 }
    }

    // While the main thread has one session joined, other sessions keep executing their output.
    // Before sessions had queues of their own, a join paused every session (issue 13141).
    func testJoiningOneSessionLeavesAnotherExecuting() {
        let permits = ExecutionPermits(capacity: 2, visibleWeight: 4)
        let a = makeSession(permits: permits)
        let b = makeSession(permits: permits)
        var aTokensWhileJoined = -1
        a.executor.whilePaused {
            self.addTokens(10, to: a)
            self.addTokens(10, to: b)
            Self.spin("b executes while a is joined") { b.delegate.tokensSeen == 10 }
            aTokensWhileJoined = a.delegate.tokensSeen
        }
        XCTAssertEqual(b.delegate.tokensSeen, 10)
        XCTAssertEqual(aTokensWhileJoined, 0)
        waitUntil("a runs after the join") { a.delegate.tokensSeen == 10 }
    }

    // With one permit, a second session waits in line, holding no thread, until the first is done.
    func testSessionWaitsForAPermitAndRunsWhenOneFrees() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        let b = makeSession(permits: permits)
        let release = DispatchSemaphore(value: 0)
        a.delegate.onToken = { count in
            if count == 1 {
                release.wait()
            }
        }
        addTokens(10, to: a)
        waitUntil("a holds the permit") { permits.inUseForTesting == 1 }
        addTokens(10, to: b)
        waitUntil("b waits") { permits.waitingCountForTesting == 1 }
        XCTAssertEqual(b.delegate.tokensSeen, 0)

        release.signal()
        waitUntil("b ran") { b.delegate.tokensSeen == 10 }
        XCTAssertEqual(a.delegate.tokensSeen, 10)
        waitUntil("nobody runs") { permits.runningCountForTesting == 0 }
    }

    // Joining a session that is waiting for a permit doesn't wait for one: its queue is idle.
    func testJoiningASessionWaitingForAPermitDoesNotWait() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        let b = makeSession(permits: permits)
        let release = DispatchSemaphore(value: 0)
        a.delegate.onToken = { count in
            if count == 1 {
                release.wait()
            }
        }
        addTokens(10, to: a)
        waitUntil("a holds the permit") { permits.inUseForTesting == 1 }
        addTokens(10, to: b)
        waitUntil("b waits") { permits.waitingCountForTesting == 1 }

        var joined = false
        b.executor.whilePaused {
            joined = true
        }
        XCTAssertTrue(joined)
        XCTAssertEqual(b.delegate.tokensSeen, 0)

        release.signal()
        waitUntil("b ran") { b.delegate.tokensSeen == 10 }
    }

    // A session paused for a join keeps its permit, so the join doesn't hand it to a waiter, and
    // the session carries on after the join.
    func testSessionPausedForAJoinKeepsItsPermit() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        let b = makeSession(permits: permits)
        let started = DispatchSemaphore(value: 0)
        a.delegate.onToken = { [executor = a.executor] count in
            if count == 1 {
                started.signal()
                // Stay in the first token until the join has paused a, so the join lands mid-run.
                Self.spinUntilPaused(executor)
            }
        }
        addTokens(10, to: a)
        XCTAssertEqual(started.wait(timeout: .now() + 30), .success, "The first token never ran")
        addTokens(10, to: b)

        var inUseDuringJoin = -1
        var aTokensDuringJoin = -1
        a.executor.whilePaused {
            inUseDuringJoin = permits.inUseForTesting
            aTokensDuringJoin = a.delegate.tokensSeen
        }
        XCTAssertEqual(inUseDuringJoin, 1)
        XCTAssertEqual(aTokensDuringJoin, 1)
        XCTAssertEqual(b.delegate.tokensSeen, 0)

        waitUntil("both ran") { a.delegate.tokensSeen == 10 && b.delegate.tokensSeen == 10 }
    }

    // A session that has run past its time slice gives its permit to a waiting session at the next
    // token, and finishes its own tokens afterwards.
    func testSessionYieldsAtTheEndOfItsSliceToAWaiter() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        let b = makeSession(permits: permits)
        a.delegate.onToken = { count in
            if count == 1 {
                Self.spin("b waits") { permits.waitingCountForTesting == 1 }
                self.spin(for: 2 * iTermAdvancedSettingsModel.tokenExecutionTimeSlice())
            }
        }
        var aTokensWhenBStarted = -1
        b.delegate.onToken = { count in
            if count == 1 {
                aTokensWhenBStarted = a.delegate.tokensSeen
            }
        }
        addTokens(100, to: a)
        waitUntil("a holds the permit") { permits.inUseForTesting == 1 }
        addTokens(10, to: b)

        waitUntil("both ran") { a.delegate.tokensSeen == 100 && b.delegate.tokensSeen == 10 }
        XCTAssertEqual(aTokensWhenBStarted, 1)
    }

    // Starts a holding a permit, stuck in its first token, with b waiting in line. Signal the
    // returned semaphore to let a finish.
    private func makeHolderAndWaiter(permits: ExecutionPermits) -> (Session, Session, DispatchSemaphore) {
        let a = makeSession(permits: permits)
        let b = makeSession(permits: permits)
        let release = DispatchSemaphore(value: 0)
        a.delegate.onToken = { count in
            if count == 1 {
                release.wait()
            }
        }
        addTokens(10, to: a)
        waitUntil("a holds the permit") { permits.inUseForTesting == 1 }
        addTokens(10, to: b)
        waitUntil("b waits") { permits.waitingCountForTesting == 1 }
        return (a, b, release)
    }

    // A waiting session that enters copy mode can't use a permit handed to it, so it passes it on
    // instead of sitting on it.
    func testWaiterInCopyModePassesThePermitOn() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let (_, b, release) = makeHolderAndWaiter(permits: permits)
        let c = makeSession(permits: permits)
        addTokens(10, to: c)
        waitUntil("c waits") { permits.waitingCountForTesting == 2 }
        b.delegate.queueTokens = true

        release.signal()
        waitUntil("c ran") { c.delegate.tokensSeen == 10 }
        XCTAssertEqual(b.delegate.tokensSeen, 0)
        waitUntil("no permit is stranded") { permits.runningCountForTesting == 0 && permits.waitingCountForTesting == 0 }

        // Leaving copy mode reschedules execution, which takes a permit again.
        b.delegate.queueTokens = false
        b.executor.schedule()
        waitUntil("b ran") { b.delegate.tokensSeen == 10 }
    }

    // A waiting session whose tokens are discarded (as when it restarts) doesn't keep the permit
    // it is handed.
    func testWaiterWithDiscardedTokensDoesNotKeepThePermit() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let (_, b, release) = makeHolderAndWaiter(permits: permits)
        b.executor.whilePaused {
            b.executor.discardTokensFromPTY()
        }
        release.signal()
        waitUntil("no permit is stranded") { permits.runningCountForTesting == 0 && permits.waitingCountForTesting == 0 }
        XCTAssertEqual(b.delegate.tokensSeen, 0)
    }

    // A waiting session whose delegate goes away (it is closing) gives up the permit it is handed.
    func testWaiterWithoutADelegateDoesNotKeepThePermit() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let (_, b, release) = makeHolderAndWaiter(permits: permits)
        b.executor.delegate = nil
        release.signal()
        waitUntil("no permit is stranded") { permits.runningCountForTesting == 0 && permits.waitingCountForTesting == 0 }
    }

    // A pause other than a join (a paused side effect, say) can last a long time, so the session
    // gives up its permit, and another session runs meanwhile.
    func testPauseOtherThanAJoinGivesUpThePermit() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        let b = makeSession(permits: permits)
        var unpauser: Unpauser?
        a.delegate.onToken = { [executor = a.executor] count in
            if count == 1 {
                // Wait for b to get in line, then pause as a paused side effect would.
                while permits.waitingCountForTesting != 1 {}
                unpauser = executor.pause()
            }
        }
        addTokens(10, to: a)
        waitUntil("a holds the permit") { permits.inUseForTesting == 1 }
        addTokens(10, to: b)

        waitUntil("b ran while a was paused") { b.delegate.tokensSeen == 10 }
        XCTAssertEqual(a.delegate.tokensSeen, 1)
        unpauser?.unpause()
        waitUntil("a finished") { a.delegate.tokensSeen == 10 }
    }

    // A pause other than a join that begins while a join holds the session (and its permit) makes
    // the session give up the permit once the join ends.
    func testPauseThatBeginsDuringAJoinGivesUpThePermitAfterIt() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        let b = makeSession(permits: permits)
        let started = DispatchSemaphore(value: 0)
        a.delegate.onToken = { [executor = a.executor] count in
            if count == 1 {
                started.signal()
                Self.spinUntilPaused(executor)
            }
        }
        addTokens(10, to: a)
        XCTAssertEqual(started.wait(timeout: .now() + 30), .success, "The first token never ran")
        addTokens(10, to: b)
        waitUntil("b waits") { permits.waitingCountForTesting == 1 }

        var unpauser: Unpauser?
        a.executor.whilePaused {
            unpauser = a.executor.pause()
        }
        waitUntil("b ran while a was paused") { b.delegate.tokensSeen == 10 }
        XCTAssertEqual(a.delegate.tokensSeen, 1)
        unpauser?.unpause()
        waitUntil("a finished") { a.delegate.tokensSeen == 10 }
    }

    // A session keeps its permit through a join, and its time slice keeps running afterward: it
    // still yields to a waiter once the slice is over. A visible session is joined about once a
    // frame, so if a join stopped the clock for good, a flooding visible session would never yield.
    func testSessionStillYieldsAfterAJoin() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        let b = makeSession(permits: permits)
        let started = DispatchSemaphore(value: 0)
        a.delegate.onToken = { [executor = a.executor] count in
            switch count {
            case 1:
                started.signal()
                // Stay in the first token until the join has paused a, so the join lands mid-run.
                Self.spinUntilPaused(executor)
            case 2:
                // b got in line during the join. Run past the time slice.
                Self.spin("b waits") { permits.waitingCountForTesting == 1 }
                self.spin(for: 2 * iTermAdvancedSettingsModel.tokenExecutionTimeSlice())
            default:
                break
            }
        }
        var aTokensWhenBStarted = -1
        b.delegate.onToken = { count in
            if count == 1 {
                aTokensWhenBStarted = a.delegate.tokensSeen
            }
        }
        addTokens(100, to: a)
        XCTAssertEqual(started.wait(timeout: .now() + 30), .success, "The first token never ran")
        // Nobody is owed the permit until the join, so a doesn't yield at its first token.
        a.executor.whilePaused {
            self.addTokens(10, to: b)
        }

        waitUntil("both ran") { a.delegate.tokensSeen == 100 && b.delegate.tokensSeen == 10 }
        XCTAssertEqual(aTokensWhenBStarted, 2)
    }

    // Tokens injected with high priority (as by an Inject trigger) run next, even when the session
    // is past its time slice with a session waiting.
    func testInjectedTokensRunBeforeYielding() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        let b = makeSession(permits: permits)
        a.delegate.discardTokens = false
        a.delegate.onToken = { count in
            if count == 1 {
                Self.spin("b waits") { permits.waitingCountForTesting == 1 }
                self.spin(for: 2 * iTermAdvancedSettingsModel.tokenExecutionTimeSlice())
                self.addTokens(5, to: a, highPriority: true)
            }
        }
        var injectedWhenBStarted = -1
        b.delegate.onToken = { count in
            if count == 1 {
                injectedWhenBStarted = a.delegate.highPriorityTokensSeen
            }
        }
        addTokens(100, to: a)
        waitUntil("a holds the permit") { permits.inUseForTesting == 1 }
        addTokens(10, to: b)

        waitUntil("both ran") { a.delegate.tokensSeen == 105 && b.delegate.tokensSeen == 10 }
        XCTAssertEqual(injectedWhenBStarted, 5)
    }

    // Joining a session that is paused for another reason doesn't make it try to execute when the
    // join ends; it can't make progress until the other pause ends.
    func testJoinOfASessionPausedForAnotherReasonDoesNotExecuteAfterward() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        var unpauser: Unpauser?
        a.queue.sync {
            unpauser = a.executor.pause()
        }
        addTokens(10, to: a)
        a.queue.sync {}
        let didExecuteBefore = a.delegate.didExecuteCount

        a.executor.whilePaused {}
        a.queue.sync {}
        XCTAssertEqual(a.delegate.didExecuteCount, didExecuteBefore)
        XCTAssertEqual(a.delegate.tokensSeen, 0)

        unpauser?.unpause()
        waitUntil("a ran") { a.delegate.tokensSeen == 10 }
    }

    // Execution that runs on the main thread in the session's queue's context (a queue.sync from
    // main) still needs a permit.
    func testExecutionOnTheMainThreadStillNeedsAPermit() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let (_, b, release) = makeHolderAndWaiter(permits: permits)
        b.queue.sync {
            // Runs execute() synchronously, on the main thread.
            b.executor.scheduleHighPriorityTask {}
        }
        XCTAssertEqual(b.delegate.tokensSeen, 0)
        XCTAssertEqual(permits.inUseForTesting, 1)

        release.signal()
        waitUntil("b ran") { b.delegate.tokensSeen == 10 }
    }

    // A session with nothing left to do leaves its permit idle, where anyone can take it, even if
    // a join pauses it as it finishes.
    func testSessionWithNoWorkLeavesItsPermitIdleDuringAJoin() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        let started = DispatchSemaphore(value: 0)
        a.delegate.onToken = { [executor = a.executor] count in
            if count == 1 {
                started.signal()
                Self.spinUntilPaused(executor)
            }
        }
        addTokens(1, to: a)
        XCTAssertEqual(started.wait(timeout: .now() + 30), .success, "The first token never ran")

        var runningDuringJoin = -1
        a.executor.whilePaused {
            runningDuringJoin = permits.runningCountForTesting
        }
        XCTAssertEqual(runningDuringJoin, 0)
    }

    // Tokens that arrive while execute() is deciding what to do with an empty queue wait for a
    // permit like any others, rather than running without one.
    func testTokensArrivingAfterTheQueueWasFoundEmptyStillNeedAPermit() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let (_, b, release) = makeHolderAndWaiter(permits: permits)
        let a = makeSession(permits: permits)
        var added = false
        a.delegate.onShouldQueueTokens = {
            // execute() has already found the queue empty. Tokens arrive from the reader now.
            if !added {
                added = true
                self.addTokens(10, to: a)
            }
        }
        a.executor.schedule()
        a.queue.sync {}
        a.queue.sync {}
        XCTAssertEqual(a.delegate.tokensSeen, 0)
        XCTAssertEqual(permits.inUseForTesting, 1)

        release.signal()
        waitUntil("everyone ran") { a.delegate.tokensSeen == 10 && b.delegate.tokensSeen == 10 }
    }

    // A session that runs out of tokens keeps its permit, idle, and runs its next tokens with it.
    func testSessionThatRunsOutOfTokensKeepsItsPermitIdle() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        addTokens(10, to: a)
        waitUntil("a ran") { a.delegate.tokensSeen == 10 }
        waitUntil("a's permit is idle") { permits.idleHolderCountForTesting == 1 }
        XCTAssertEqual(permits.inUseForTesting, 1)

        addTokens(10, to: a)
        waitUntil("a ran again") { a.delegate.tokensSeen == 20 }
        XCTAssertEqual(permits.waitingCountForTesting, 0)
        waitUntil("a's permit is idle again") { permits.idleHolderCountForTesting == 1 }
    }

    // An idle session's permit goes to a session that needs it, and comes back when the idle
    // session has work again.
    func testIdlePermitGoesWhereItIsNeeded() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        let b = makeSession(permits: permits)
        addTokens(10, to: a)
        waitUntil("a's permit is idle") { a.delegate.tokensSeen == 10 && permits.idleHolderCountForTesting == 1 }

        addTokens(10, to: b)
        waitUntil("b ran") { b.delegate.tokensSeen == 10 }
        addTokens(10, to: a)
        waitUntil("a ran again") { a.delegate.tokensSeen == 20 }
        waitUntil("nobody runs or waits") { permits.runningCountForTesting == 0 && permits.waitingCountForTesting == 0 }
    }

    // A session whose slice ends with a waiter owed the permit gives it up even if a join pauses it
    // just then, rather than keeping it through the join and running another slice.
    func testSessionYieldsAtTheEndOfItsSliceEvenIfAJoinPausesIt() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        let a = makeSession(permits: permits)
        let b = makeSession(permits: permits)
        let joinNow = DispatchSemaphore(value: 0)
        a.delegate.onToken = { [executor = a.executor] count in
            if count == 1 {
                Self.spin("b waits") { permits.waitingCountForTesting == 1 }
                // Pause for a join as the slice ends, before execute() settles.
                joinNow.signal()
                Self.spinUntilPaused(executor)
                self.spin(for: 2 * iTermAdvancedSettingsModel.tokenExecutionTimeSlice())
            }
        }
        var aTokensWhenBStarted = -1
        b.delegate.onToken = { count in
            if count == 1 {
                aTokensWhenBStarted = a.delegate.tokensSeen
            }
        }
        addTokens(100, to: a)
        waitUntil("a holds the permit") { permits.inUseForTesting == 1 }
        addTokens(10, to: b)
        XCTAssertEqual(joinNow.wait(timeout: .now() + 30), .success, "a never asked for the join")
        a.executor.whilePaused {}

        waitUntil("both ran") { a.delegate.tokensSeen == 100 && b.delegate.tokensSeen == 10 }
        XCTAssertEqual(aTokensWhenBStarted, 1)
    }

    // Reading the clock costs a noticeable share of execution when done for every token, so a
    // holder checks whether its slice is over only every few tokens, starting with the first.
    func testSliceClockIsReadOnlyEveryFewTokens() {
        let permits = ExecutionPermits(capacity: 1, visibleWeight: 4)
        var reads = 0
        let holder = ExecutionPermitHolder(permits: permits,
                                           queue: DispatchQueue(label: "test"),
                                           isPaused: { false },
                                           execute: {},
                                           now: {
            reads += 1
            return UInt64(reads)
        })
        XCTAssertEqual(holder.decide(hasTokens: true, willQueueTokens: false, isPaused: false, isPausedOnlyForJoins: false),
                       .execute)
        let before = reads
        for _ in 0..<80 {
            XCTAssertFalse(holder.sliceIsOverAndShouldYield())
        }
        XCTAssertEqual(reads - before, 10)
    }
}
