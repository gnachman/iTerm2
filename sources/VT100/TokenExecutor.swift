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
    private let semaphore = DispatchSemaphore(value: Int(iTermAdvancedSettingsModel.bufferDepth()))
    private let impl: TokenExecutorImpl
    private let queue: DispatchQueue
    private static let isTokenExecutorSpecificKey = DispatchSpecificKey<Bool>()
    private var onExecutorQueue: Bool {
        return DispatchQueue.getSpecific(key: Self.isTokenExecutorSpecificKey) == true
    }
    @objc var isBackgroundSession = false {
        didSet {
#if DEBUG
            iTermGCD.assertMutationQueueSafe()
#endif
            if isBackgroundSession != oldValue {
                impl.isBackgroundSession = isBackgroundSession
            }
        }
    }

    @objc var isExecutingToken: Bool {
        #if DEBUG
        iTermGCD.assertMutationQueueSafe()
        #endif
        return impl.isExecutingToken
    }

    @objc(initWithTerminal:slownessDetector:queue:)
    init(_ terminal: VT100Terminal,
         slownessDetector: SlownessDetector,
         queue: DispatchQueue) {
        self.queue = queue
        queue.setSpecific(key: Self.isTokenExecutorSpecificKey, value: true)
        impl = TokenExecutorImpl(terminal,
                                 slownessDetector: slownessDetector,
                                 semaphore: semaphore,
                                 queue: queue)
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
    // parsing, and in select()) vs idle (blocked on TokenExecutor's semaphore), and how much
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
            iTermGCD.assertMutationQueueSafe()
#endif
            // Re-entrant code path so that the Inject trigger can do its job synchronously
            // (before other triggers run).
            reallyAddTokens(vector,
                            lengthTotal: lengthTotal,
                            lengthExcludingInBandSignaling: lengthExcludingInBandSignaling,
                            highPriority: highPriority,
                            semaphore: nil as DispatchSemaphore?)
            return
        }
        // Normal code path for tokens from PTY. Use the semaphore to give backpressure to reading.
        let semaphore = self.semaphore
        if TokenExecutor.enableTimingStats {
            TokenExecutor.parserTimingStats.recordEnd()
        }
        _ = semaphore.wait(timeout: .distantFuture)
        if TokenExecutor.enableTimingStats {
            TokenExecutor.parserTimingStats.recordStart()
        }
        reallyAddTokens(vector,
                        lengthTotal: lengthTotal,
                        lengthExcludingInBandSignaling: lengthExcludingInBandSignaling,
                        highPriority: highPriority,
                        semaphore: semaphore)
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
        iTermGCD.assertMutationQueueSafe()
#endif
        impl.rollBackCurrentToken()
    }

    // Any queue
    @objc
    func addSideEffect(_ task: @escaping TokenExecutorTask) {
        if gDebugLogging.boolValue { DLog("add side effect") }
        impl.addSideEffect(task)
    }

    // Any queue. Schedules an outbound report-send side effect without
    // invalidating reportsMaySkipSync.
    @objc
    func addReportSideEffect(_ task: @escaping TokenExecutorTask) {
        if gDebugLogging.boolValue { DLog("add report side effect") }
        impl.addReportSideEffect(task)
    }

    // Any queue. Exempt from background batching; see
    // TokenExecutorImpl.addUrgentSideEffect(_:) for when that is warranted.
    @objc
    func addUrgentSideEffect(_ task: @escaping TokenExecutorTask) {
        if gDebugLogging.boolValue { DLog("add urgent side effect") }
        impl.addUrgentSideEffect(task)
    }

    // Any queue
    @objc
    func addDeferredSideEffect(_ task: @escaping TokenExecutorTask) {
        impl.addDeferredSideEffect(task)
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
                                 semaphore: DispatchSemaphore?) {
        let tokenArray = TokenArray(vector,
                                    lengthTotal: lengthTotal,
                                    lengthExcludingInBandSignaling: lengthExcludingInBandSignaling,
                                    semaphore: semaphore)
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
}

private class TokenExecutorImpl {
    static let didUnpauseGloballyNotification = Notification.Name("didUnpauseGloballyNotification")
    private let terminal: VT100Terminal
    private let queue: DispatchQueue
    private let slownessDetector: SlownessDetector
    private let semaphore: DispatchSemaphore
    private var taskQueue = iTermTaskQueue()
    private var sideEffects = iTermTaskQueue()
    private let tokenQueue = TwoTierTokenQueue()
    private var pauseCount = iTermAtomicInt64Create()
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
            iTermGCD.assertMutationQueueSafe()
#endif
            if isBackgroundSession != oldValue {
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
         semaphore: DispatchSemaphore,
         queue: DispatchQueue) {
        self.terminal = terminal
        self.queue = queue
        self.slownessDetector = slownessDetector
        self.semaphore = semaphore
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
    }

    func pause() -> Unpauser {
#if DEBUG
        assertQueue()
#endif
        let newValue = iTermAtomicInt64Add(pauseCount, 1)
        if newValue == 1 && gDebugLogging.boolValue {
            DLog("Pause")
        }
        return Unpauser(self)
    }

    private var isPaused: Bool {
#if DEBUG
        assertQueue()
#endif
        return iTermAtomicInt64Get(pauseCount) > 0 || iTermAtomicInt64Get(TokenExecutor.globalPauseCount) > 0
    }

    func invalidate() {
#if DEBUG
        assertQueue()
#endif
        tokenQueue.removeAll()
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
        if gDebugLogging.boolValue { DLog("Incr pending pauses if \(iTermPreferences.maximizeThroughput())") }
        var unpauser = iTermPreferences.maximizeThroughput() ? nil : TokenExecutor.globalPause()

        let sema = DispatchSemaphore(value: 0)
        let sema2 = DispatchSemaphore(value: 0)
        queue.async {
            sema2.signal()
            iTermGCD.joined = true
            sema.wait()
            iTermGCD.joined = false
            DLog("Mutation queue unpaused")
        }
        if unpauser != nil {
            sema2.wait()
        } else {
            // When maximize throughput is on, we want to avoid pausing token execution but we can't
            // let it go on indefinitely. After a timeout, pause it and block for what should be a short
            // amount of time (until the current batch of tokens is done being executed).
            let timeout = 0.03
            if sema2.wait(timeout: .now() + timeout) == .timedOut {
                unpauser = TokenExecutor.globalPause()
                sema2.wait()
            }
        }
        DLog("Mutation queue paused")
        block()
        if unpauser != nil {
            if gDebugLogging.boolValue { DLog("Decr pending pauses") }
        }
        unpauser?.unpause()
        sema.signal()
    }

    // Any queue
    func addSideEffect(_ task: @escaping TokenExecutorTask) {
        noteStateSideEffectScheduled()
        sideEffects.append(task)
        if gDebugLogging.boolValue { DLog("addSideEffect()") }
        sideEffectScheduler.markNeedsUpdate()
    }

    // Like addSideEffect but does NOT invalidate reportsMaySkipSync. Use this only
    // for purely outbound report-send side effects, which never mutate state a
    // later report reads.
    func addReportSideEffect(_ task: @escaping TokenExecutorTask) {
        sideEffects.append(task)
        if gDebugLogging.boolValue { DLog("addReportSideEffect()") }
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
        sideEffects.append(task)
        if gDebugLogging.boolValue { DLog("addUrgentSideEffect()") }
        sideEffectScheduler.markNeedsUpdate(within: Self.urgentSideEffectMaximumDelay)
    }

    func addDeferredSideEffect(_ task: @escaping TokenExecutorTask) {
        noteStateSideEffectScheduled()
        sideEffects.append(task)
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
        iTermGCD.assertMutationQueueSafe()
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
        defer {
            executingCount -= 1
            executeHighPriorityTasks()
            if TokenExecutor.enableTimingStats {
                Self.mutationTimingStats.recordEnd()
            }
        }
        executeHighPriorityTasks()
        guard let delegate = delegate else {
            // This is necessary to avoid deadlock. If the terminal is disabled then the token queue
            // will hold semaphores that need to be signaled.
            if gDebugLogging.boolValue {
                DLog("empty queue")
            }
            tokenQueue.removeAll()
            return
        }
        let hadTokens = !tokenQueue.isEmpty
        var accumulatedLength = ByteExecutionStats()
        if !delegate.tokenExecutorShouldQueueTokens() {
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
        if accumulatedLength.total > 0 || hadTokens {
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
            if isBackgroundSession && !Self.activeSessionsWithTokens.value.isEmpty {
                // Avoid blocking the active session. If there were multiple mutation threads this
                // would be unnecessary. Reschedule to resume processing once active sessions drain.
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
        while let task = taskQueue.dequeue() {
            if gDebugLogging.boolValue { DLog("execute task") }
            task()
        }
        if gDebugLogging.boolValue { DLog("done") }
    }
}

extension TokenExecutorImpl: CustomDebugStringConvertible {
    var debugDescription: String {
        return "<TokenExecutorImpl: \(Unmanaged.passUnretained(self).toOpaque()): queue=\(queue.debugDescription) taskQueue=\(taskQueue.count) sideEffects=\(sideEffects.count) pauseCount=\(iTermAtomicInt64Get(pauseCount)) globalPauseCount=\(iTermAtomicInt64Get(TokenExecutor.globalPauseCount)) throughput=\(throughputEstimator.estimatedThroughput) delegate=\(String(describing: delegate))>"
    }
}

extension TokenExecutorImpl: UnpauserDelegate {
    // You can call this on any queue.
    func unpause() {
        let newCount = iTermAtomicInt64Add(pauseCount, -1)
        precondition(newCount >= 0)
        if newCount == 0 && iTermAtomicInt64Get(TokenExecutor.globalPauseCount) == 0 {
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

