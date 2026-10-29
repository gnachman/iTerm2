//
//  TokenExecutor.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/22.
//

import Foundation

protocol UnpauserDelegate: AnyObject {
    func unpause()
}

typealias TokenExecutorTask = () -> ()

// Delegate calls are run on the execution queue.
@objc(iTermTokenExecutorDelegate)
protocol TokenExecutorDelegate: AnyObject {
    // Should token execution be delayed? Do this in copy mode, for example.
    func tokenExecutorShouldQueueTokens() -> Bool

    // Should tokens be freed without use? Do this during a mute coprocess, for example.
    @objc(tokenExecutorShouldDiscardToken:withHighPriority:)
    func tokenExecutorShouldDiscard(token: VT100Token,
                                    highPriority: Bool) -> Bool

    // Called only when tokens are actually executed. `length` gives the number of bytes of input
    // that were executed.
    func tokenExecutorDidExecute(lengthTotal: Int,
                                 lengthExcludingInBandSignaling: Int,
                                 throughput: Int)

    // Remove this eventually
    func tokenExecutorCursorCoordString() -> NSString

    // Synchronize state between threads.
    func tokenExecutorSync()

    // Side-effect state found.
    func tokenExecutorHandleSideEffectFlags(_ flags: Int64)

    // About to execute a batch of tokens.
    func tokenExecutorWillExecuteTokens()
}

// Uncomment the stack tracing code to debug stuck paused executors.
@objc(iTermTokenExecutorUnpauser)
class Unpauser: NSObject {
    private weak var delegate: UnpauserDelegate?
    private let mutex = Mutex()
    // @objc var stack: String
    #if DEBUG
    private var hasBeenUnpaused = false
    #endif

    init(_ delegate: UnpauserDelegate) {
        self.delegate = delegate
        // stack = Thread.callStackSymbols.joined(separator: "\n")
        super.init()
        // print("Pause \(self) from\n\(stack)")
    }

    @objc
    func unpause() {
        mutex.sync {
            #if DEBUG
            hasBeenUnpaused = true
            #endif
            // print("Unpause \(self)")
            guard let temp = delegate else {
                return
            }
            // stack = ""
            delegate = nil
            temp.unpause()
        }
    }

    deinit {
        #if DEBUG
        it_assert(hasBeenUnpaused)
        #endif
        let stillPaused = mutex.sync { delegate != nil }
        guard stillPaused else {
            return
        }
        DLog("Unpause in deinit! This should never happen.")
        unpause()
//        if stack != "" {
//            fatalError()
//        }
    }
}

func CVectorReleaseObjectsAndDestroy(_ vector: CVector) {
    var temp = vector
    CVectorReleaseObjects(&temp);
    CVectorDestroy(&temp)
}

@objc(iTermTokenExecutor)
class TokenExecutor: NSObject {
    @objc weak var delegate: TokenExecutorDelegate? {
        didSet {
            impl.delegate = delegate
        }
    }
    // Limits how many token arrays from the pty are buffered, giving backpressure to reading.
    private let budget = TokenBudget(capacity: Int(iTermAdvancedSettingsModel.bufferDepth()))
    private let impl: TokenExecutorImpl
    private let queue: DispatchQueue
    // Identifies an executor queue. Executors that share a queue share its token, so each may run
    // tasks synchronously on it; an executor on another queue may not.
    private final class QueueToken {}
    private static let queueTokenKey = DispatchSpecificKey<QueueToken>()
    private let queueToken: QueueToken
    private var onExecutorQueue: Bool {
        return DispatchQueue.getSpecific(key: Self.queueTokenKey) === queueToken
    }
    @objc var isBackgroundSession = false {
        didSet {
#if DEBUG
            iTermGCD.assertSafe(forMutationQueue: queue)
#endif
            if isBackgroundSession != oldValue {
                impl.isBackgroundSession = isBackgroundSession
            }
        }
    }

    @objc var isExecutingToken: Bool {
        #if DEBUG
        iTermGCD.assertSafe(forMutationQueue: queue)
        #endif
        return impl.isExecutingToken
    }

    // `ownsQueue` says whether `queue` belongs to this session alone, as opposed to the mutation
    // queue every session shares. An executor with a queue of its own pauses only itself for a
    // join, and takes an execution permit to execute tokens, which limits how many sessions do so at
    // once. On the shared queue only one can run anyway.
    @objc(initWithTerminal:slownessDetector:queue:ownsQueue:)
    convenience init(_ terminal: VT100Terminal,
                     slownessDetector: SlownessDetector,
                     queue: DispatchQueue,
                     ownsQueue: Bool) {
        self.init(terminal,
                  slownessDetector: slownessDetector,
                  queue: queue,
                  ownsQueue: ownsQueue,
                  permits: ExecutionPermits.forNewExecutor(ownsQueue: ownsQueue))
    }

    init(_ terminal: VT100Terminal,
         slownessDetector: SlownessDetector,
         queue: DispatchQueue,
         ownsQueue: Bool,
         permits: ExecutionPermits?) {
        self.queue = queue
        // Main queue only, so two executors made for one queue can't both set its token.
        it_assert(Thread.isMainThread, "TokenExecutor must be created on the main queue")
        if let token = queue.getSpecific(key: Self.queueTokenKey) {
            queueToken = token
        } else {
            queueToken = QueueToken()
            queue.setSpecific(key: Self.queueTokenKey, value: queueToken)
        }
        impl = TokenExecutorImpl(terminal,
                                 slownessDetector: slownessDetector,
                                 queue: queue,
                                 ownsQueue: ownsQueue,
                                 permits: permits)
    }

    // Any queue. Whether addTokens(_:lengthTotal:lengthExcludingInBandSignaling:) would return
    // without blocking right now. A reader that is the only one adding tokens to this executor can
    // check this before reading, and use notifyWhenTokenCapacityAvailable(on:_:) instead of blocking.
    @objc
    var hasTokenCapacity: Bool {
        return budget.hasCapacity
    }

    // Any queue. Runs `block` asynchronously on `queue` once a slot is free (as soon as a token
    // array finishes executing), or right away if one already is. Registering
    // another block runs the pending one right away, so a block must check for capacity again.
    @objc(notifyWhenTokenCapacityAvailableOnQueue:block:)
    func notifyWhenTokenCapacityAvailable(on queue: DispatchQueue, _ block: @escaping () -> Void) {
        budget.notifyWhenCapacityAvailable(on: queue, block)
    }

    // Mutation queue, or the main queue in a joined block. Discards tokens read from the pty that
    // haven't executed yet, such as a program's last output when its session restarts. Injected
    // (high priority) tokens are kept.
    @objc
    func discardTokensFromPTY() {
        impl.discardTokensFromPTY()
    }

    // This takes ownership of vector.
    // You can call this on any queue.
    @objc
    func addTokens(_ vector: CVector,
                   lengthTotal: Int,
                   lengthExcludingInBandSignaling: Int) {
        addTokens(vector,
                  lengthTotal: lengthTotal,
                  lengthExcludingInBandSignaling: lengthExcludingInBandSignaling,
                  highPriority: false)
    }

    private static let parserTimingStats: TimingStats = {
        TimingStats(name: "Parser thread")
    }()
    // Flip this to true to measure how much time the TaskNotifier thread spends busy (reading,
    // parsing, and in select()) vs idle (blocked on TokenExecutor's budget), and how much
    // time the mutation thread spends busy (executing tokens) vs idle (waiting for tokens).
    static let enableTimingStats = false

    // This takes ownership of vector.
    // You can call this on any queue when not high priority.
    // If high priority, then you must be on the main queue or have joined the main & mutation queue.
    // This blocks when the queue of tokens gets too large.
    @objc
    func addTokens(_ vector: CVector,
                   lengthTotal: Int,
                   lengthExcludingInBandSignaling: Int,
                   highPriority: Bool) {
        if gDebugLogging.boolValue { DLog("Add tokens with length \(lengthTotal) (excluding OOB: \(lengthExcludingInBandSignaling)), highpri=\(highPriority)") }
        if lengthTotal == 0 {
            return
        }
        if highPriority {
#if DEBUG
            iTermGCD.assertSafe(forMutationQueue: queue)
#endif
            // Re-entrant code path so that the Inject trigger can do its job synchronously
            // (before other triggers run).
            reallyAddTokens(vector,
                            lengthTotal: lengthTotal,
                            lengthExcludingInBandSignaling: lengthExcludingInBandSignaling,
                            highPriority: highPriority,
                            budget: nil)
            return
        }
        // Normal code path for tokens from PTY. Use the budget to give backpressure to reading.
        if TokenExecutor.enableTimingStats {
            TokenExecutor.parserTimingStats.recordEnd()
        }
        budget.acquire()
        if TokenExecutor.enableTimingStats {
            TokenExecutor.parserTimingStats.recordStart()
        }
        reallyAddTokens(vector,
                        lengthTotal: lengthTotal,
                        lengthExcludingInBandSignaling: lengthExcludingInBandSignaling,
                        highPriority: highPriority,
                        budget: budget)
        queue.async { [weak self] in
            self?.impl.didAddTokens()
        }
    }


    // Call this while a token is being executed to cause it to be re-executed next time execution
    // is scheduled.
    @objc
    func rollBackCurrentToken() {
        if gDebugLogging.boolValue { DLog("Roll back current token") }
#if DEBUG
        iTermGCD.assertSafe(forMutationQueue: queue)
#endif
        impl.rollBackCurrentToken()
    }

    // Any queue
    @objc
    func addSideEffect(_ task: @escaping TokenExecutorTask) {
        if gDebugLogging.boolValue { DLog("add side effect") }
        impl.addSideEffect(task)
    }

    // Any queue. Exempt from background batching; see
    // TokenExecutorImpl.addUrgentSideEffect(_:) for when that is warranted.
    @objc
    func addUrgentSideEffect(_ task: @escaping TokenExecutorTask) {
        if gDebugLogging.boolValue { DLog("add urgent side effect") }
        impl.addUrgentSideEffect(task)
    }

    // Any queue. Schedules an outbound report-send side effect without
    // invalidating reportsMaySkipSync.
    @objc
    func addReportSideEffect(_ task: @escaping TokenExecutorTask) {
        if gDebugLogging.boolValue { DLog("add report side effect") }
        impl.addReportSideEffect(task)
    }

    // Any queue
    @objc
    func addDeferredSideEffect(_ task: @escaping TokenExecutorTask) {
        impl.addDeferredSideEffect(task)
    }

    // Any queue. Goes up by one each time a side effect is added. Comparing it
    // just before and just after adding a side effect tells whether that side
    // effect was the only one added in between; comparing it later tells
    // whether it is still the last one in the queue.
    @objc
    var sideEffectSerial: Int64 {
        return impl.sideEffectSerial
    }

    // Any queue. True if a report may be sent without first pausing+syncing.
    @objc
    var reportsMaySkipSync: Bool {
        return impl.reportsMaySkipSync
    }

    // Any queue. Call from a scheduling path the executor doesn't otherwise see
    // (e.g. addUnmanagedPausedSideEffect) so the next report re-syncs.
    @objc
    func noteStateSideEffectScheduled() {
        impl.noteStateSideEffectScheduled()
    }

    // Arm skip-sync (single atomic op; safe from any queue). Called from the
    // report gate's joined side effect.
    @objc
    func armReportsMaySkipSync() {
        impl.armReportsMaySkipSync()
    }

    // Any queue
    @objc
    func setSideEffectFlag(value: Int64) {
        if gDebugLogging.boolValue { DLog("Set side-effect flag \(value)") }
        impl.setSideEffectFlag(value: value)
    }

    // This can run on the main queue, or else on the mutation queue when joined.
    @objc(executeSideEffectsImmediatelySyncingFirst:)
    func executeSideEffectsImmediately(syncFirst: Bool) {
        if gDebugLogging.boolValue { DLog("[side effects] Execute side effects immediately syncFirst=\(syncFirst)") }
        impl.executeSideEffects(syncFirst: syncFirst)
        if gDebugLogging.boolValue { DLog("[side effects] Side effect execution complete") }
    }

    // This takes ownership of vector.
    // You can call this on any queue
    private func reallyAddTokens(_ vector: CVector,
                                 lengthTotal: Int,
                                 lengthExcludingInBandSignaling: Int,
                                 highPriority: Bool,
                                 budget: TokenBudget?) {
        let tokenArray = TokenArray(vector,
                                    lengthTotal: lengthTotal,
                                    lengthExcludingInBandSignaling: lengthExcludingInBandSignaling,
                                    budget: budget)
        self.impl.addTokens(tokenArray, highPriority: highPriority)
    }

    // Call this on the token evaluation queue.
    @objc
    func pause() -> Unpauser {
        if gDebugLogging.boolValue { DLog("pause") }
        return impl.pause()
    }

    class GlobalUnpauserDelegate: UnpauserDelegate {
        func unpause() {
            iTermAtomicInt64Add(globalPauseCount, -1)
            NotificationCenter.default.post(name: TokenExecutorImpl.didUnpauseGloballyNotification, object: nil)
        }
    }

    static let globalPauseCount = iTermAtomicInt64Create()
    private static var globalUnpauserDelegate = GlobalUnpauserDelegate()
    static func globalPause() -> Unpauser {
        let newValue = iTermAtomicInt64Add(globalPauseCount, 1)
        if newValue == 1 && gDebugLogging.boolValue {
            DLog("Pause")
        }
        return Unpauser(globalUnpauserDelegate)
    }

    // You can call this on any queue.
    @objc
    func schedule() {
        if gDebugLogging.boolValue { DLog("schedule") }
        impl.schedule()
    }

    @objc func assertSynchronousSideEffectsAreSafe() {
        impl.assertSynchronousSideEffectsAreSafe()
    }

    // Note that the task may be run either synchronously or asynchronously.
    // High priority tasks run as soon as possible. If a token is currently
    // executing, it runs after that token's execution completes. Token
    // execution is guaranteed to not block and should not take "very long".
    // You can call this on any queue.
    @objc
    func scheduleHighPriorityTask(_ task: @escaping TokenExecutorTask) {
        if gDebugLogging.boolValue { DLog("schedule high-pri task") }
        self.impl.scheduleHighPriorityTask(task, syncAllowed: onExecutorQueue)
    }

    // Main queue only
    @objc
    func whilePaused(_ block: () -> ()) {
        self.impl.whilePaused(block, onExecutorQueue: onExecutorQueue)
    }

    // Any queue
    var joinWaitsForIdleQueue: Bool {
        return impl.joinWaitsForIdleQueue
    }

    // Mutation queue, or the main queue in a joined block. Whether tokens or high-priority tasks
    // are waiting to execute.
    var hasPendingWork: Bool {
#if DEBUG
        iTermGCD.assertSafe(forMutationQueue: queue)
#endif
        return impl.hasPendingWork
    }

    // Any queue
    var isPausedForTesting: Bool {
        return impl.isPausedForTesting
    }

    // Main queue, outside a joined block. For tests: executes pending work on this executor's
    // queue now, unless execution is paused. Doesn't depend on how many hops an unpause takes to
    // schedule execution.
    func executeForTesting() {
        dispatchPrecondition(condition: .onQueue(.main))
        queue.sync {
            impl.executeForTesting()
        }
    }
}

private class TokenExecutorImpl {
    static let didUnpauseGloballyNotification = Notification.Name("didUnpauseGloballyNotification")
    private let terminal: VT100Terminal
    private let queue: DispatchQueue
    // False when every session shares the one mutation queue. Then joining any session must pause
    // them all, and background sessions yield to active ones, because they all run on that queue.
    private let hasOwnQueue: Bool
    private let slownessDetector: SlownessDetector
    private var taskQueue = iTermTaskQueue()
    private var sideEffects = iTermTaskQueue()
    // Counts side effects ever added. See TokenExecutor.sideEffectSerial.
    private let sideEffectSerialCounter = iTermAtomicInt64Create()
    private let sideEffectAppendMutex = Mutex()
    private let tokenQueue = TwoTierTokenQueue()
    private let pauseCount = PauseCount()
    // Limits how many sessions execute tokens at once. Nil on the shared queue.
    private var permitHolder: ExecutionPermitHolder?
    // Executor's queue. True while executeForTesting() runs execute(), which then executes tokens
    // without a permit. Tests call it synchronously and expect tokens to execute.
    private var bypassingPermits = false
    // Executor's queue. The permit holder that token execution goes through.
    private var executionPermitHolder: ExecutionPermitHolder? {
        return bypassingPermits ? nil : permitHolder
    }
    // Mutation queue. The current execute() call's stats, if TokenExecutionStats is enabled.
    private var statsSample: TokenExecutionStats.Sample?
    // Nonzero means a report may be sent without first pausing+syncing, because a
    // sync has happened and no state side effect has been scheduled since. It is
    // armed by armReportsMaySkipSync() (from the report gate's joined sync) and
    // reset to zero by any state side effect being scheduled. Report-send side
    // effects use addReportSideEffect() so they do NOT reset it; otherwise a burst
    // of queries (e.g. herdr querying all 256 palette colors on focus) would pay
    // one joined sync per query. See terminalShouldSendReport:.
    private var reportsMaySkipSyncFlag = iTermAtomicInt64Create()
    private var executingCount = 0
    private let executingSideEffects = MutableAtomicObject(false)
    private var sideEffectScheduler: PeriodicScheduler! = nil
    private let throughputEstimator = iTermThroughputEstimator(historyOfDuration: 5.0 / 30.0,
                                                               secondsPerBucket: 1.0 / 30.0)
    private var commit = true
    private static let mutationTimingStats: TimingStats = {
        TimingStats(name: "Mutation thread")
    }()
    // Access on mutation queue only
    private(set) var isExecutingToken = false
    weak var delegate: TokenExecutorDelegate?

    // This is used to give visible sessions priority for token processing over those that cannot
    // be seen. This prevents a very busy non-selected tab from starving a visible one.
    private static var activeSessionsWithTokens = MutableAtomicObject<Set<ObjectIdentifier>>(Set())
    private static let foregroundSideEffectPeriod = 1.0 / 30.0
    private static let backgroundSideEffectPeriod = 1.0
    // Urgent side effects are not batched, so they run at the foreground rate no matter
    // how the session is scheduled. See addUrgentSideEffect(_:).
    private static let urgentSideEffectMaximumDelay = foregroundSideEffectPeriod
    @objc var isBackgroundSession = false {
        didSet {
#if DEBUG
            iTermGCD.assertSafe(forMutationQueue: queue)
#endif
            if isBackgroundSession != oldValue {
                permitHolder?.setVisible(!isBackgroundSession)
                sideEffectScheduler.period = isBackgroundSession ? Self.backgroundSideEffectPeriod : Self.foregroundSideEffectPeriod
                if isBackgroundSession {
                    Self.activeSessionsWithTokens.mutableAccess { set in
                        set.remove(ObjectIdentifier(self))
                    }
                } else {
                    // Changing the period does not disturb timers already armed at the
                    // old one, so without this a session that becomes visible waits out
                    // whatever remains of a background-sized window before its first
                    // paint.
                    sideEffectScheduler.expedite(within: Self.foregroundSideEffectPeriod)
                }
            }
        }
    }

    init(_ terminal: VT100Terminal,
         slownessDetector: SlownessDetector,
         queue: DispatchQueue,
         ownsQueue: Bool,
         permits: ExecutionPermits?) {
        self.terminal = terminal
        self.queue = queue
        hasOwnQueue = ownsQueue
        self.slownessDetector = slownessDetector
        sideEffectScheduler = PeriodicScheduler(DispatchQueue.main, period: Self.foregroundSideEffectPeriod, action: { [weak self] in
            guard let self = self else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                DLog("[side effects] Begin executing scheduled side effects")
                self?.executeSideEffects(syncFirst: true)
                DLog("[side effects] End executing scheduled side effects")
            }
        })
        if let permits {
            permitHolder = ExecutionPermitHolder(permits: permits,
                                                 queue: queue,
                                                 isPaused: { [pauseCount] in
                pauseCount.isPaused
            }, execute: { [weak self] in
                self?.execute()
            })
            permitHolder?.setVisible(!isBackgroundSession)
        }
        NotificationCenter.default.addObserver(forName: Self.didUnpauseGloballyNotification,
                                               observer: self,
                                               object: nil) { [weak self] _ in
            guard let self else {
                return
            }
            self.queue.async {
                if !self.isPaused {
                    self.schedule()
                }
            }
        }
    }

    deinit {
        Self.activeSessionsWithTokens.mutableAccess { set in
            set.remove(ObjectIdentifier(self))
        }
        iTermAtomicInt64Free(sideEffectSerialCounter)
    }

    func pause() -> Unpauser {
#if DEBUG
        assertQueue()
#endif
        if pauseCount.addOther() && gDebugLogging.boolValue {
            DLog("Pause")
        }
        return Unpauser(self)
    }

    // Mutation queue, or the main queue in a joined block.
    var hasPendingWork: Bool {
        return !tokenQueue.isEmpty || taskQueue.count > 0
    }

    // Mutation queue
    func executeForTesting() {
        bypassingPermits = true
        defer {
            bypassingPermits = false
        }
        execute()
    }

    private var isPaused: Bool {
#if DEBUG
        assertQueue()
#endif
        return pauseCount.isPaused || iTermAtomicInt64Get(TokenExecutor.globalPauseCount) > 0
    }

    func invalidate() {
#if DEBUG
        assertQueue()
#endif
        tokenQueue.removeAll()
    }

    func discardTokensFromPTY() {
#if DEBUG
        assertQueue()
#endif
        tokenQueue.removeAllNormalPriority()
        if !isBackgroundSession && tokenQueue.isEmpty {
            Self.activeSessionsWithTokens.mutableAccess { set in
                set.remove(ObjectIdentifier(self))
            }
        }
    }

    // You can call this on any queue
    func addTokens(_ tokenArray: TokenArray, highPriority: Bool) {
        throughputEstimator.addByteCount(tokenArray.lengthTotal)
        tokenQueue.addTokens(tokenArray, highPriority: highPriority)
        if !isBackgroundSession {
            Self.activeSessionsWithTokens.mutableAccess { set in
                set.insert(ObjectIdentifier(self))
            }
        }
    }

    func didAddTokens() {
        execute()
    }

    // You can call this on any queue.
    func schedule() {
        queue.async { [weak self] in
            self?.execute()
        }
    }

    // Any queue
    func scheduleHighPriorityTask(_ task: @escaping TokenExecutorTask, syncAllowed: Bool) {
        taskQueue.append(task)
        if syncAllowed {
#if DEBUG
            assertQueue()
#endif
            if executingCount == 0 {
                execute()
                return
            }
        }
        schedule()
    }

    // Main queue
    // Runs block synchronously while token executor is stopped.
    func whilePaused(_ block: () -> (), onExecutorQueue: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        let waitForIdle = joinWaitsForIdleQueue
        if gDebugLogging.boolValue { DLog("Join: waitForIdle=\(waitForIdle)") }
        var endPause = waitForIdle ? nil : pauseForJoin()

        let sema = DispatchSemaphore(value: 0)
        let sema2 = DispatchSemaphore(value: 0)
        queue.async {
            sema2.signal()
            sema.wait()
            DLog("Mutation queue unpaused")
        }
        let joinStart = TokenExecutionStats.enabled ? monotonicNanoseconds() : nil
        if endPause != nil {
            sema2.wait()
        } else {
            // On the shared queue with maximize throughput on, pausing stops every session, so first
            // give the queue a chance to reach the join by itself. After a timeout, pause it and block
            // for what should be a short amount of time (until the current batch of tokens is done
            // being executed).
            let timeout = 0.03
            if sema2.wait(timeout: .now() + timeout) == .timedOut {
                endPause = pauseForJoin()
                sema2.wait()
            }
        }
        if let joinStart {
            TokenExecutionStats.recordJoinWait(secondsSince(joinStart))
        }
        DLog("Mutation queue paused")
        block()
        if endPause != nil {
            if gDebugLogging.boolValue { DLog("Decr pending pauses") }
        }
        endPause?()
        sema.signal()
    }

    // Any queue. With Maximize Throughput on, a join on the shared queue first gives the queue a short
    // time to go idle by itself, because pausing it stops every session. A session with a queue of its
    // own pauses right away and waits only for its current batch: pausing costs only that session,
    // and a busy queue never goes idle, so waiting would block the main thread for the whole grace
    // period on every join (issue 13141).
    var joinWaitsForIdleQueue: Bool {
        return !hasOwnQueue && iTermPreferences.maximizeThroughput()
    }

    // Main queue. Stops token execution so the queue gets to the join soon, and returns a closure
    // that ends the pause. A session with a queue of its own pauses only itself; on the shared
    // queue, every session must stop.
    private func pauseForJoin() -> () -> Void {
        guard hasOwnQueue else {
            let unpauser = TokenExecutor.globalPause()
            return {
                unpauser.unpause()
            }
        }
        if pauseCount.addJoin() && gDebugLogging.boolValue {
            DLog("Pause for join")
        }
        return { [self] in
            unpauseJoin()
        }
    }

    // Any queue. Ends a pause begun by pauseForJoin(). Once no joins remain, schedules execution,
    // unless another kind of pause remains. Then the session can't make progress, so it only gives
    // up any permit it kept for the join; its unpause schedules execution later.
    private func unpauseJoin() {
        guard pauseCount.removeJoin() else {
            return
        }
        if pauseCount.isPaused {
            guard permitHolder != nil else {
                return
            }
            queue.async { [weak self] in
                guard let self, pauseCount.isPaused, !pauseCount.isPausedOnlyForJoins else {
                    // The other pause ended meanwhile, and that scheduled execution.
                    return
                }
                permitHolder?.relinquish()
            }
            return
        }
        if iTermAtomicInt64Get(TokenExecutor.globalPauseCount) == 0 {
            if gDebugLogging.boolValue { DLog("Unpause join") }
            schedule()
        }
    }

    // Any queue
    var sideEffectSerial: Int64 {
        return iTermAtomicInt64Get(sideEffectSerialCounter)
    }

    // Any queue. Every side effect is added through here. The lock makes the
    // serial go up in the same order the side effects join the queue.
    private func appendSideEffect(_ task: @escaping TokenExecutorTask) {
        sideEffectAppendMutex.sync {
            sideEffects.append(task)
            iTermAtomicInt64Add(sideEffectSerialCounter, 1)
        }
    }

    // Any queue
    func addSideEffect(_ task: @escaping TokenExecutorTask) {
        noteStateSideEffectScheduled()
        appendSideEffect(task)
        if gDebugLogging.boolValue { DLog("addSideEffect()") }
        sideEffectScheduler.markNeedsUpdate()
    }

    // Like addSideEffect but exempt from the batching a background session applies to its
    // side effects. Use it only where a batching period would stall a protocol or hold a
    // pause, not merely delay output.
    //
    // The SSH conductor is the motivating case: it is a strictly serial request/response
    // channel whose queue only advances when `end ssh command` runs, and that side effect
    // is also a paused one, so it halts token execution until it runs. At the background
    // period of 1s every conductor round trip -- including every keystroke sent to a tmux
    // gateway over ssh -- cost a full second in each direction.
    //
    // Note this is a narrower test than "belongs to a latency-sensitive subsystem". Urgency
    // is a no-op for a visible session, whose period is already the short one. And every
    // tier appends to the same `sideEffects` FIFO, which executeSideEffects drains whole,
    // so an urgent flush carries everything queued ahead of it; a non-urgent side effect is
    // actually delayed only when it is the tail with no urgent sibling behind it.
    // Issue 13013.
    func addUrgentSideEffect(_ task: @escaping TokenExecutorTask) {
        noteStateSideEffectScheduled()
        appendSideEffect(task)
        if gDebugLogging.boolValue { DLog("addUrgentSideEffect()") }
        sideEffectScheduler.markNeedsUpdate(within: Self.urgentSideEffectMaximumDelay)
    }

    // Like addSideEffect but does NOT invalidate reportsMaySkipSync. Use this only
    // for purely outbound report-send side effects, which never mutate state a
    // later report reads.
    func addReportSideEffect(_ task: @escaping TokenExecutorTask) {
        appendSideEffect(task)
        if gDebugLogging.boolValue { DLog("addReportSideEffect()") }
        sideEffectScheduler.markNeedsUpdate()
    }

    func addDeferredSideEffect(_ task: @escaping TokenExecutorTask) {
        noteStateSideEffectScheduled()
        appendSideEffect(task)
        sideEffectScheduler.markNeedsUpdateDeferredByHalfPeriod()
    }

    // Any queue
    func setSideEffectFlag(value: Int64) {
        noteStateSideEffectScheduled()
        if (sideEffects.setFlag(value) & value) == 0 {
            sideEffectScheduler.markNeedsUpdateDeferredByHalfPeriod()
        }
    }

    // Any queue. A report may skip its pause+sync only if this is nonzero.
    var reportsMaySkipSync: Bool {
        return iTermAtomicInt64Get(reportsMaySkipSyncFlag) != 0
    }

    // Any queue. Called from every state side-effect scheduling path so that the
    // next report re-syncs.
    func noteStateSideEffectScheduled() {
        iTermAtomicInt64GetAndReset(reportsMaySkipSyncFlag)
    }

    // Arm the flag with a single atomic op so it can't tear against a concurrent
    // noteStateSideEffectScheduled (GetAndReset) from any queue: arming ORs in the
    // low bit; disarming resets to zero. If a disarm lands between... there is no
    // "between" - each is one atomic operation. (armed == nonzero.)
    func armReportsMaySkipSync() {
        iTermAtomicInt64BitwiseOr(reportsMaySkipSyncFlag, 1)
    }

    func assertSynchronousSideEffectsAreSafe() {
        precondition(sideEffects.count == 0 && !executingSideEffects.value)
    }

    // This can run on the main queue, or else on the mutation queue when joined.
    func executeSideEffects(syncFirst: Bool) {
        if gDebugLogging.boolValue { DLog("[side effects] begin") }
        iTermGCD.assertMainQueueSafe()

        if executingSideEffects.getAndSet(true) {
            // Do not allow re-entrant side-effects.
            if gDebugLogging.boolValue { DLog("[side effects] reentrancy detected! aborting") }
            return
        }
        if gDebugLogging.boolValue { DLog("[side effects] dequeuing side effects") }
        var shouldSync = syncFirst
        while let task = sideEffects.dequeue() {
            if shouldSync {
                if gDebugLogging.boolValue { DLog("[side effects] sync before first side effect") }
                delegate?.tokenExecutorSync()
                shouldSync = false
            }
            if gDebugLogging.boolValue { DLog("[side effects] execute side effect") }
            task()
        }
        if gDebugLogging.boolValue { DLog("[side effects] finished executing side effects") }
        executingSideEffects.set(false)

        // Do this last because it might join.
        let flags = sideEffects.resetFlags()
        if flags != 0 {
            if gDebugLogging.boolValue { DLog("f[side effects] lags=\(flags)") }
            if shouldSync {
                if gDebugLogging.boolValue { DLog("[side effects] sync before handling flags") }
                delegate?.tokenExecutorSync()
            }
            delegate?.tokenExecutorHandleSideEffectFlags(flags)
        }
    }

#if DEBUG
    private func assertQueue() {
        iTermGCD.assertSafe(forMutationQueue: queue)
    }
#endif

    private struct ByteExecutionStats {
        var total = 0
        var excludingInBandSignaling = 0
    }

    private func execute() {
        DLog("execute()")
#if DEBUG
        assertQueue()
#endif
        if TokenExecutor.enableTimingStats {
            Self.mutationTimingStats.recordStart()
        }
        executingCount += 1
        // execute() can be reentered (a high-priority task may run it synchronously), so only the
        // call that starts a sample records it.
        let ownsStatsSample = statsSample == nil && TokenExecutionStats.enabled
        if ownsStatsSample {
            statsSample = TokenExecutionStats.Sample(start: monotonicNanoseconds())
            executionPermitHolder?.stats = ExecutionPermitHolder.Stats()
        }
        defer {
            executingCount -= 1
            executionPermitHolder?.settle(isPaused: isPaused,
                                          isPausedOnlyForJoins: isPausedOnlyForJoins,
                                          hasTokensToExecute: {
                !tokenQueue.isEmpty && !(delegate?.tokenExecutorShouldQueueTokens() ?? true)
            })
            executeHighPriorityTasks()
            if TokenExecutor.enableTimingStats {
                Self.mutationTimingStats.recordEnd()
            }
            if ownsStatsSample, var sample = statsSample {
                statsSample = nil
                if let permitStats = executionPermitHolder?.stats {
                    executionPermitHolder?.stats = nil
                    sample.permits = permitStats.permits
                    sample.waited = permitStats.waited
                    sample.yielded = permitStats.yielded
                    sample.handoffGap = permitStats.handoffGap
                }
                TokenExecutionStats.record(sample)
            }
        }
        executeHighPriorityTasks()
        guard let delegate = delegate else {
            // This is necessary to avoid deadlock. If the terminal is disabled then the token queue
            // holds budget slots that need to be released.
            if gDebugLogging.boolValue {
                DLog("empty queue")
            }
            tokenQueue.removeAll()
            executionPermitHolder?.relinquish()
            return
        }
        let hadTokens = !tokenQueue.isEmpty
        var accumulatedLength = ByteExecutionStats()
        let willQueueTokens = delegate.tokenExecutorShouldQueueTokens()
        let permitDecision = executionPermitHolder?.decide(hasTokens: hadTokens,
                                                  willQueueTokens: willQueueTokens,
                                                  isPaused: isPaused,
                                                  isPausedOnlyForJoins: isPausedOnlyForJoins) ?? (willQueueTokens ? .dontExecute : .execute)
        if permitDecision == .execute {
            it_assert(executionPermitHolder?.isHolding ?? true, "Executing tokens without a permit")
            let tokensStart = statsSample == nil ? 0 : monotonicNanoseconds()
            let excludedBefore = (statsSample?.highPriorityTasks ?? 0) + (executionPermitHolder?.stats?.permits ?? 0)
            defer {
                if statsSample != nil {
                    let excluded = (statsSample?.highPriorityTasks ?? 0) + (executionPermitHolder?.stats?.permits ?? 0) - excludedBefore
                    statsSample?.tokens += max(0, secondsSince(tokensStart) - excluded)
                }
            }
            slownessDetector.measure(event: PTYSessionSlownessEventExecute) {
                var first = true
                if gDebugLogging.boolValue {
                    DLog("Will enumerate token arrays")
                }
                tokenQueue.enumerateTokenArrayGroups { (tokenArrayGroup, priority) in
                    if first {
                        delegate.tokenExecutorWillExecuteTokens()
                        first = false
                    }
                    if gDebugLogging.boolValue {
                        DLog("Begin executing a batch of tokens of sizes \(tokenArrayGroup.arrays.map(\.numberRemaining))")
                    }
                    defer {
                        if gDebugLogging.boolValue {
                            DLog("Done executing a batch of tokens. Vector has \(tokenArrayGroup.arrays.map(\.numberRemaining)) remaining.")
                        }
                    }
                    return executeTokenGroups(tokenArrayGroup,
                                              priority: priority,
                                              accumulatedLength: &accumulatedLength,
                                              delegate: delegate)
                }
                if !isBackgroundSession && tokenQueue.isEmpty {
                    DLog("Active session completely drained")
                    Self.activeSessionsWithTokens.mutableAccess { set in
                        set.remove(ObjectIdentifier(self))
                    }
                }
                if gDebugLogging.boolValue { DLog("Finished enumerating token arrays. \(tokenQueue.isEmpty ? "There are no more tokens in the queue" : "The queue is not empty")") }
            }
        }
        statsSample?.bytes += accumulatedLength.total
        // A session waiting for a permit executed nothing, and will be scheduled again when it gets one.
        if accumulatedLength.total > 0 || (hadTokens && permitDecision != .waitForPermit) {
            delegate.tokenExecutorDidExecute(lengthTotal: accumulatedLength.total,
                                             lengthExcludingInBandSignaling: accumulatedLength.excludingInBandSignaling,
                                             throughput: throughputEstimator.estimatedThroughput)
        }
    }

    private func executeTokenGroups(_ group: TokenArrayGroup,
                                    priority: Int,
                                    accumulatedLength: inout ByteExecutionStats,
                                    delegate: TokenExecutorDelegate) -> Bool {
        if gDebugLogging.boolValue { DLog("Begin for \(delegate)") }
        defer {
            if gDebugLogging.boolValue {
                DLog("execute tokens cleanup for \(delegate)")
            }
            executeHighPriorityTasks()
        }
        var quitVectorEarly = false
        var vectorHasNext = true
        while !isPaused && !quitVectorEarly && vectorHasNext {
            if gDebugLogging.boolValue {
                DLog("continuing to next token")
            }
            if let token = group.peek {
                // Drain per token: executing a token can spray autoreleased
                // temporaries (e.g. OSC 133 handling calls -lastCommandMark,
                // which walks the interval tree via reverseLimitEnumerator and
                // allocates an NSMutableArray per step). Under a repaint firehose
                // one execute() call can process tens of thousands of tokens
                // before its GCD block's pool drains, so those temporaries pile
                // up into multi-GB of live NSMutableArray/CFString. Scoping a
                // pool to each token bounds that to one token's worth. See #12992.
                autoreleasepool {
                    executeHighPriorityTasks()
                    commit = true
                    var consume = true
                    if execute(token: token,
                               priority: priority,
                               delegate: delegate) {
                        if gDebugLogging.boolValue {
                            DLog("quit early")
                        }
                        quitVectorEarly = true
                        consume = true
                    } else {
                        consume = commit
                    }
                    if consume {
                        vectorHasNext = group.consume()
                    } else {
                        vectorHasNext = false
                    }
                    if gDebugLogging.boolValue {
                        DLog("commit=\(commit) consume=\(consume) remaining=\(group.arrays.map(\.numberRemaining))")
                    }
                }
            }
            // High-priority tokens (as from an Inject trigger) run before giving up the permit.
            // A token that leaves some sets quitVectorEarly to switch to them. Not after the
            // group's last token either, for the same reason as below.
            if vectorHasNext && !tokenQueue.hasHighPriorityToken && (executionPermitHolder?.sliceIsOverAndShouldYield() ?? false) {
                // Give the permit to a waiting session. Settling puts this one back in line
                // with its remaining tokens.
                DLog("Yield permit")
                return false
            }
            if vectorHasNext && !hasOwnQueue && isBackgroundSession && !Self.activeSessionsWithTokens.value.isEmpty {
                // Avoid blocking the active session, which shares this queue. A session with a
                // queue of its own doesn't block anyone. Reschedule to resume processing once
                // active sessions drain.
                // Not after the group's last token: it is done, and returning here would skip
                // counting its bytes (see the accumulation below), which flow control for a
                // hidden workgroup peer depends on.
                DLog("Stop processing early because active session has tokens")
                queue.async { [weak self] in
                    self?.execute()
                }
                return false
            }
        }
        if quitVectorEarly {
            if gDebugLogging.boolValue { DLog("quitVectorEarly") }
            return true
        }
        if isPaused {
            if gDebugLogging.boolValue { DLog("paused") }
            return false
        }
        if gDebugLogging.boolValue { DLog("normal termination") }
        accumulatedLength.total += group.lengthTotal
        accumulatedLength.excludingInBandSignaling += group.lengthExcludingInBandSignaling
        return true
    }

    // MARK: - Execution permits

    // Any queue. Whether every current pause is a join. Joins are short, so a session paused only
    // for joins keeps its permit.
    private var isPausedOnlyForJoins: Bool {
        return pauseCount.isPausedOnlyForJoins
    }

    // Any queue
    var isPausedForTesting: Bool {
        return pauseCount.isPaused
    }

    func rollBackCurrentToken() {
        if gDebugLogging.boolValue { DLog("roll back current token") }
#if DEBUG
        assertQueue()
#endif
        commit = false
    }

    // Returns true to stop processing tokens in this vector and move on to the next one, if any.
    // Returns false to continue processing tokens in the vector, if any (and if not go to the next
    // vector).
    private func execute(token: VT100Token,
                         priority: Int,
                         delegate: TokenExecutorDelegate) -> Bool {
        if gDebugLogging.boolValue { DLog("Execute token \(token) cursor=\(delegate.tokenExecutorCursorCoordString())") }

        if delegate.tokenExecutorShouldDiscard(token: token, highPriority: priority == 0) {
            DLog("Discarding token")
            return false
        }

        isExecutingToken = true
        terminal.execute(token)
        isExecutingToken = false

        // Return true if we need to switch to a high priority queue.
        return (priority > 0) && tokenQueue.hasHighPriorityToken
    }

    private func executeHighPriorityTasks(until stopCondition: () -> Bool) {
        if gDebugLogging.boolValue { DLog("begin") }
#if DEBUG
        assertQueue()
#endif
        executingCount += 1
        defer {
            executingCount -= 1
        }
        while !stopCondition(), let task = taskQueue.dequeue() {
            if gDebugLogging.boolValue { DLog("execute task") }
            task()
        }
        if gDebugLogging.boolValue { DLog ("done")}
    }

    private func executeHighPriorityTasks() {
        if gDebugLogging.boolValue { DLog("begin") }
        let start = statsSample != nil && taskQueue.count > 0 ? monotonicNanoseconds() : nil
        defer {
            if let start {
                statsSample?.highPriorityTasks += secondsSince(start)
            }
        }
        while let task = taskQueue.dequeue() {
            if gDebugLogging.boolValue { DLog("execute task") }
            task()
        }
        if gDebugLogging.boolValue { DLog("done") }
    }
}

extension TokenExecutorImpl: CustomDebugStringConvertible {
    var debugDescription: String {
        return "<TokenExecutorImpl: \(Unmanaged.passUnretained(self).toOpaque()): queue=\(queue.debugDescription) taskQueue=\(taskQueue.count) sideEffects=\(sideEffects.count) pauseCount=\(pauseCount) globalPauseCount=\(iTermAtomicInt64Get(TokenExecutor.globalPauseCount)) throughput=\(throughputEstimator.estimatedThroughput) delegate=\(String(describing: delegate))>"
    }
}

// Counts a token executor's pauses: joins, and every other kind (such as a paused side effect).
// Both counts share one atomic word (joins in the high 32 bits, others in the low 32 bits), so a
// single read can tell whether the session is paused only for joins. Such a session keeps its
// execution permit, because joins are short and frequent (about once a frame for a visible session).
private final class PauseCount: CustomStringConvertible {
    private let value = iTermAtomicUInt64Create()
    private static let join: UInt64 = 1 << 32
    private static let othersMask: UInt64 = 0xFFFF_FFFF

    deinit {
        iTermAtomicUInt64Free(value)
    }

    // Any queue
    var isPaused: Bool {
        return iTermAtomicUInt64Get(value) != 0
    }

    // Any queue
    var isPausedOnlyForJoins: Bool {
        let pauses = iTermAtomicUInt64Get(value)
        return pauses != 0 && (pauses & Self.othersMask) == 0
    }

    // Any queue. Returns whether this is the first pause of any kind.
    func addOther() -> Bool {
        let newValue = iTermAtomicUInt64Add(value, 1)
        it_assert(newValue & Self.othersMask != 0, "Too many pauses")
        return newValue == 1
    }

    // Any queue. Returns whether this is the first pause of any kind.
    func addJoin() -> Bool {
        let newValue = iTermAtomicUInt64Add(value, Self.join)
        it_assert(newValue >= Self.join, "Too many joins")
        return newValue == Self.join
    }

    // Any queue. Returns whether no pauses remain.
    func removeOther() -> Bool {
        let oldValue = iTermAtomicUInt64Subtract(value, 1)
        it_assert(oldValue & Self.othersMask != 0, "Unpaused more than were paused")
        return oldValue == 1
    }

    // Any queue. Returns whether no joins remain (other pauses may).
    func removeJoin() -> Bool {
        let oldValue = iTermAtomicUInt64Subtract(value, Self.join)
        it_assert(oldValue >= Self.join, "Unpaused more joins than were paused")
        return oldValue - Self.join < Self.join
    }

    var description: String {
        let pauses = iTermAtomicUInt64Get(value)
        return "joins=\(pauses >> 32) others=\(pauses & Self.othersMask)"
    }
}

extension TokenExecutorImpl: UnpauserDelegate {
    // You can call this on any queue.
    func unpause() {
        if pauseCount.removeOther() && iTermAtomicInt64Get(TokenExecutor.globalPauseCount) == 0 {
            if gDebugLogging.boolValue { DLog("Unpause") }
            schedule()
        }
    }
}

extension TokenExecutor: IdempotentOperationScheduler {
    func scheduleIdempotentOperation(_ closure: @escaping () -> Void) {
        // Use a deferred side effect because this might happen during a prompt redraw and we want
        // to give it a chance to finish so we can avoid syncing with a half-finished prompt.
        addDeferredSideEffect(closure)
    }
}

// Run a closure but not too often.
@objc(iTermPeriodicScheduler)
class PeriodicScheduler: NSObject {
    private var updatePending: Bool {
        return mutex.sync { _updatePending }
    }
    private var _updatePending = false
    private var needsUpdate: Bool {
        get {
            return mutex.sync { _needsUpdate }
        }
        set {
            mutex.sync { _needsUpdate = newValue }
        }
    }
    private var _needsUpdate = false
    private let queue: DispatchQueue
    private let mutex = Mutex()
    // The mutation queue changes this when a session becomes visible or hidden while any
    // queue may be reading it, so it is guarded like the rest of the scheduler's state.
    // Code that already holds the mutex must use _period; the lock is not reentrant.
    private var _period: TimeInterval
    var period: TimeInterval {
        get { return mutex.sync { _period } }
        set { mutex.sync { _period = newValue } }
    }
    private let action: () -> ()
    // Deadline and generation of the deferred flush armed by markNeedsUpdate(deferred:),
    // if any. A request whose deadline is no sooner than the armed one coalesces into it;
    // a sooner one supersedes it by way of the generation counter, the same way
    // resetAfterDelay(_:) supersedes an armed reset. Guarded by mutex.
    private var pendingDeferredDeadline: DispatchTime?
    private var deferredGeneration = 0
    // Deadline of the reset currently armed by resetAfterDelay(_:), if any, plus the
    // generation it belongs to. markNeedsUpdate(within:) uses these to pull an armed
    // reset in when `period` is longer than a caller can tolerate. Guarded by mutex.
    private var pendingResetDeadline: DispatchTime?
    private var resetGeneration = 0

    @objc(initWithQueue:period:block:)
    init(_ queue: DispatchQueue, period: TimeInterval, action: @escaping () -> ()) {
        self.queue = queue
        self._period = period
        self.action = action
    }

    @objc func markNeedsUpdate() {
        if !needsUpdate {
            DLog("  did not need an update before! This should do something")
        } else {
            DLog(" Already needed an update, though")
        }
        needsUpdate = true
        schedule(reset: false)
    }

    // Like markNeedsUpdate() but deliberately withholds the flush for `delay` so that more
    // tokens land in the same batch and intermediate state is never drawn. See
    // TokenExecutorImpl.addDeferredSideEffect(_:); the motivating case is a terminal that
    // hides the cursor and shows it again a few tokens later, where flushing in between
    // costs a visible flicker. Issue 10206.
    //
    // At most one deferred flush is armed at a time. A request that is no sooner than the
    // armed one coalesces into it rather than arming a timer of its own, which matters
    // because the hot callers (the side-effect flags) hit this on every linefeed.
    @objc func markNeedsUpdate(deferred delay: TimeInterval) {
        armDeferredFlush(delay: delay)
    }

    // What every production caller wants: a deferred flush half a period out. The period
    // is read under the same lock that arms the timer because the mutation queue changes
    // it when a session becomes visible or hidden; reading it separately would let a
    // session compute its window from one period and arm it against another. That closes
    // only the compute/arm race. A window already armed at the background period is a
    // separate problem, handled by expedite(within:) on the transition to foreground.
    @objc func markNeedsUpdateDeferredByHalfPeriod() {
        armDeferredFlush(delay: nil)
    }

    // A nil delay means half the current period. Sampling `now` before taking the lock
    // keeps the deadline anchored to when the request was made rather than to when it
    // won the lock, so requests cannot be ordered differently than they arrived.
    private func armDeferredFlush(delay explicitDelay: TimeInterval?) {
        let now = DispatchTime.now()
        mutex.sync {
            let delay = explicitDelay ?? (_period / 2.0)
            _needsUpdate = true
            if let pendingDeferredDeadline, pendingDeferredDeadline <= now + delay {
                DLog("A deferred flush is already armed and is at least this soon")
                return
            }
            DLog("Arm deferred flush \(delay) from now")
            deferAfterDelay(delay, from: now)
        }
    }

    // Caller must hold the mutex. Arms a deferred flush `delay` from `now`, superseding
    // any deferred flush armed earlier so that exactly one is live at a time. The mirror
    // of resetAfterDelay(_:), which does the same for the throttling reset.
    private func deferAfterDelay(_ delay: TimeInterval, from now: DispatchTime) {
        deferredGeneration += 1
        let generation = deferredGeneration
        let deadline = now + delay
        pendingDeferredDeadline = deadline
        queue.asyncAfter(deadline: deadline) { [weak self] in
            guard let self else {
                return
            }
            let superseded = self.mutex.sync { () -> Bool in
                guard self.deferredGeneration == generation else {
                    return true
                }
                self.pendingDeferredDeadline = nil
                return false
            }
            if superseded {
                // A later call armed a sooner flush, which is responsible for this update.
                DLog("Ignore superseded deferred flush")
                return
            }
            DLog("Deferred flush of \(delay) elapsed")
            self.schedule(reset: false)
        }
    }

    // Like markNeedsUpdate() but guarantees the action runs within `maximumDelay` even
    // when `period` is longer. Without this a caller that can't tolerate the period is
    // stuck: in a steady state _updatePending is almost always true, so markNeedsUpdate()
    // just returns and the action waits out the full period. Arming an earlier reset
    // supersedes the pending one (see resetAfterDelay(_:)) so the rate limit stays exact
    // rather than allowing two flushes in one period.
    @objc func markNeedsUpdate(within maximumDelay: TimeInterval) {
        DLog("markNeedsUpdate(within: \(maximumDelay))")
        // One locked pass: dropping the lock to call schedule() would let another thread
        // arm a full-period reset in the gap, which is exactly the delay we are avoiding.
        mutex.sync {
            _needsUpdate = true
            guard _updatePending else {
                // Nothing is throttling us, so run the action now.
                scheduleLocked(reset: false)
                return
            }
            pullInArmedResetLocked(within: maximumDelay)
        }
    }

    // Shortens an armed reset to `maximumDelay` without itself requesting an update.
    // markNeedsUpdate(within:) would set _needsUpdate, which forces a flush even when
    // nothing is waiting; this only accelerates work that is already scheduled. Used when
    // a session becomes visible and its period shrinks, so that nothing armed at the old,
    // longer period holds the first paint for the rest of that period.
    //
    // Both armed timers have to be pulled in, and they are independent. The reset only
    // exists while an update is throttled, whereas a deferred flush can be the only thing
    // scheduled on an otherwise quiescent session: a hidden tab that draws a prompt arms
    // a flush half a background period out and nothing else, so a user switching to it
    // 50ms later would wait out the remaining 450ms.
    @objc func expedite(within maximumDelay: TimeInterval) {
        DLog("expedite(within: \(maximumDelay))")
        let now = DispatchTime.now()
        mutex.sync {
            if _updatePending {
                pullInArmedResetLocked(within: maximumDelay)
            }
            pullInArmedDeferredFlushLocked(within: maximumDelay, from: now)
        }
    }

    // Caller must hold the mutex. Arms a deferred flush `maximumDelay` from now if one is
    // armed and is further out than that. Does nothing when none is armed: unlike the
    // reset, a deferred flush is a request that was actually made, so there is nothing to
    // accelerate if nobody made one.
    private func pullInArmedDeferredFlushLocked(within maximumDelay: TimeInterval,
                                                from now: DispatchTime) {
        guard let pendingDeferredDeadline else {
            return
        }
        guard pendingDeferredDeadline > now + maximumDelay else {
            DLog("Armed deferred flush is already soon enough")
            return
        }
        DLog("Pull in armed deferred flush to \(maximumDelay) from now")
        deferAfterDelay(maximumDelay, from: now)
    }

    // Caller must hold the mutex. Arms a reset `maximumDelay` from now unless the one
    // already armed is at least that soon.
    private func pullInArmedResetLocked(within maximumDelay: TimeInterval) {
        let deadline = DispatchTime.now() + maximumDelay
        if let pendingResetDeadline, pendingResetDeadline <= deadline {
            DLog("Armed reset is already soon enough")
            return
        }
        DLog("Pull in armed reset to \(maximumDelay) from now")
        resetAfterDelay(maximumDelay)
    }

    @objc func schedule() {
        schedule(reset: false)
    }

    private func schedule(reset: Bool, generation: Int? = nil) {
        mutex.sync {
            scheduleLocked(reset: reset, generation: generation)
        }
    }

    // Caller must hold the mutex.
    private func scheduleLocked(reset: Bool, generation: Int? = nil) {
        DLog("schedule(reset: \(reset)) called")
        if let generation, generation != resetGeneration {
            // A later call to resetAfterDelay(_:) superseded us.
            DLog("Ignore superseded reset")
            return
        }
        if reset {
            DLog("set updatePending = false")
            _updatePending = false
            pendingResetDeadline = nil
        }
        guard _needsUpdate else {
            // Nothing changed.
            DLog("No update needed")
            return
        }
        let wasPending = _updatePending
        _updatePending = true

        if wasPending {
            // Too soon to update.
            DLog("Too soon to update")
            return
        }

        resetAfterDelay(_period)
        _needsUpdate = false
        DLog("Periodic scheduler performing action")
        action()
    }

    // Caller must hold the mutex. Arms a reset `delay` from now, superseding any reset
    // armed earlier so that exactly one is live at a time.
    private func resetAfterDelay(_ delay: TimeInterval) {
        resetGeneration += 1
        let generation = resetGeneration
        let deadline = DispatchTime.now() + delay
        pendingResetDeadline = deadline
        queue.asyncAfter(deadline: deadline) { [weak self] in
            guard let self = self else {
                return
            }
            DLog("Resetting after delay of \(delay)")
            self.schedule(reset: true, generation: generation)
        }
    }
}


func monotonicNanoseconds() -> UInt64 {
    return DispatchTime.now().uptimeNanoseconds
}

func secondsSince(_ start: UInt64?) -> TimeInterval {
    guard let start else {
        return 0
    }
    return TimeInterval(monotonicNanoseconds() &- start) / TimeInterval(NSEC_PER_SEC)
}

// Measures how execute() divides its time between executing tokens and overhead (permits and
// everything else), to tune the execution permits' time slice. Off unless the hidden default
// NoSyncTokenExecutionStatsFile names a file. Once a second, a summary is appended to that file
// and the full stats go to the debug log. Each summary starts with a line giving the Unix times of
// the interval it covers ("start=... end=..."). The file grows by about 1 MB an hour while enabled.
enum TokenExecutionStats {
    enum Slot: Int, CaseIterable {
        case tokens
        case highPriorityTasks
        case permits
        case otherOverhead

        var name: String {
            switch self {
            case .tokens: return "Tokens"
            case .highPriorityTasks: return "High-pri tasks"
            case .permits: return "Permits"
            case .otherOverhead: return "Other overhead"
            }
        }
    }

    // Accumulates one execute() call's times, on its mutation queue.
    struct Sample {
        var start = UInt64(0)
        var highPriorityTasks: TimeInterval = 0
        var permits: TimeInterval = 0
        var tokens: TimeInterval = 0
        var waited = false
        var yielded = false
        var handoffGap: TimeInterval?
        // Bytes of input whose tokens finished executing. A batch is counted when its last token
        // executes.
        var bytes = 0
    }

    private static let path = ((iTermUserDefaults.userDefaults().string(forKey: "NoSyncTokenExecutionStatsFile") ?? "") as NSString).expandingTildeInPath
    static let enabled = !path.isEmpty
    // Writes the file off the mutex, so a slow disk never holds up execution or a join.
    private static let writeQueue = DispatchQueue(label: "com.iterm2.token-execution-stats", qos: .utility)
    // Guarded by mutex. When the interval the next block covers began: wall-clock time for the
    // block's header, which the 13141 harness matches against its own clock, and monotonic time for
    // rates.
    private static var lastLogWallTime: TimeInterval = 0
    private static var lastLogMonotonic = UInt64(0)
    // Writes a block every second, whether or not anything executed, so join waits recorded while
    // output is idle are written in the block covering them. Started by the first thing recorded.
    private static let timer: DispatchSourceTimer = {
        let timer = DispatchSource.makeTimerSource(queue: writeQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler {
            // Write the file after releasing the mutex, which main takes to record a join wait.
            append(mutex.sync { takeBlock() })
        }
        mutex.sync {
            lastLogWallTime = Date().timeIntervalSince1970
            lastLogMonotonic = monotonicNanoseconds()
        }
        timer.resume()
        return timer
    }()

    private static let mutex = Mutex()
    // Guarded by mutex, which makes each one single-writer as iTermPreciseTimerStats requires.
    private static let stats: UnsafeMutablePointer<iTermPreciseTimerStats> = {
        let stats = UnsafeMutablePointer<iTermPreciseTimerStats>.allocate(capacity: Slot.allCases.count)
        for slot in Slot.allCases {
            iTermPreciseTimerStatsInit(stats + slot.rawValue, slot.name)
        }
        return stats
    }()
    private static let joinWait = iTermHistogram()
    private static let echoKeyToExecuted = iTermHistogram()
    private static let echoExecutedToMain = iTermHistogram()
    private static let echoHandlingOnMain = iTermHistogram()
    private static let handoffGap = iTermHistogram()
    private static var waits = 0
    private static var bytes = 0
    private static var yields = 0


    static func record(_ sample: Sample) {
        _ = timer
        let total = secondsSince(sample.start)
        let other = max(0, total - sample.tokens - sample.highPriorityTasks - sample.permits)
        mutex.sync {
            iTermPreciseTimerStatsRecord(stats + Slot.tokens.rawValue, sample.tokens, 1)
            iTermPreciseTimerStatsRecord(stats + Slot.highPriorityTasks.rawValue, sample.highPriorityTasks, 1)
            iTermPreciseTimerStatsRecord(stats + Slot.permits.rawValue, sample.permits, 1)
            iTermPreciseTimerStatsRecord(stats + Slot.otherOverhead.rawValue, other, 1)
            bytes += sample.bytes
            if sample.waited {
                waits += 1
            }
            if sample.yielded {
                yields += 1
            }
            if let gap = sample.handoffGap {
                handoffGap.addValue(gap * 1000)
            }
        }
    }

    // writeQueue. Failures are ignored: this is a diagnostic.
    private static func append(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            return
        }
        guard let handle = FileHandle(forWritingAtPath: path) else {
            FileManager.default.createFile(atPath: path, contents: data)
            return
        }
        defer {
            try? handle.close()
        }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            DLog("Failed to write token execution stats to \(path): \(error)")
        }
    }

    // Main queue. How long a keystroke's echo took; see ExecutorUpdateTicker.EchoTiming.
    static func recordEcho(_ timing: ExecutorUpdateTicker.EchoTiming) {
        _ = timer
        mutex.sync {
            echoKeyToExecuted.addValue(timing.keyToExecuted * 1000)
            echoExecutedToMain.addValue(timing.executedToMain * 1000)
            echoHandlingOnMain.addValue(timing.handlingOnMain * 1000)
        }
    }

    // Main queue. How long a join waited for the session's queue to reach it.
    static func recordJoinWait(_ seconds: TimeInterval) {
        _ = timer
        mutex.sync {
            joinWait.addValue(seconds * 1000)
        }
    }

    // writeQueue, with mutex held. Returns a block describing what was recorded since the last
    // one, and starts over.
    private static func takeBlock() -> String {
        mutex.assertOwned()
        func total(_ slot: Slot) -> TimeInterval {
            let s = stats + slot.rawValue
            return iTermPreciseTimerStatsGetMean(s) * TimeInterval(iTermPreciseTimerStatsGetCount(s))
        }
        let tokens = total(.tokens)
        let overhead = total(.permits) + total(.otherOverhead)
        let busy = tokens + total(.highPriorityTasks) + overhead
        let fraction = busy > 0 ? overhead / busy : 0
        func percentiles(_ histogram: iTermHistogram) -> String {
            guard histogram.count > 0 else {
                return "none"
            }
            return String(format: "p50=%.2fms p95=%.2fms max=%.2fms n=%lld",
                          histogram.value(atNTile: 0.5),
                          histogram.value(atNTile: 0.95),
                          histogram.max,
                          histogram.count)
        }
        let wallTime = Date().timeIntervalSince1970
        let elapsed = secondsSince(lastLogMonotonic)
        let additional = String(format: "Overhead fraction: %.4f (permits %.2fms, other %.2fms, tokens %.2fms, high-pri %.2fms)\n",
                                fraction,
                                total(.permits) * 1000,
                                total(.otherOverhead) * 1000,
                                tokens * 1000,
                                total(.highPriorityTasks) * 1000) +
            "Waits for a permit: \(waits), slice yields: \(yields)\n" +
            String(format: "Bytes executed: %.2f MB/s\n", Double(bytes) / max(0.001, elapsed) / 1e6) +
            "Permit handoff gap: \(percentiles(handoffGap))\n" +
            "Join wait: \(percentiles(joinWait))\n" +
            "Echo key to executed: \(percentiles(echoKeyToExecuted))\n" +
            "Echo executed to main: \(percentiles(echoExecutedToMain))\n" +
            "Echo handling on main: \(percentiles(echoHandlingOnMain))"
        iTermPreciseTimerLog("Token execution", stats, Slot.allCases.count, false, nil, additional)
        let text = "start=\(lastLogWallTime) end=\(wallTime)\n\(additional)\n"
        lastLogWallTime = wallTime
        lastLogMonotonic = monotonicNanoseconds()
        joinWait.clear()
        echoKeyToExecuted.clear()
        echoExecutedToMain.clear()
        echoHandlingOnMain.clear()
        handoffGap.clear()
        waits = 0
        bytes = 0
        yields = 0
        return text
    }
}
