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
    func tokenExecutorShouldDiscardTokens() -> Bool

    // Called only when tokens are actually executed. `length` gives the number of bytes of input
    // that were executed.
    func tokenExecutorDidExecute(length: Int, throughput: Int)

    // Remove this eventually
    func tokenExecutorCursorCoordString() -> NSString

    // Synchronize state between threads.
    func tokenExecutorSync()

    // Side-effect state found.
    func tokenExecutorHandleSideEffectState(_ state: [String: AnyObject])
}

// Uncomment the stack tracing code to debug stuck paused executors.
@objc(iTermTokenExecutorUnpauser)
class Unpauser: NSObject {
    private weak var delegate: UnpauserDelegate?
    private let mutex = Mutex()
    // @objc var stack: String
    init(_ delegate: UnpauserDelegate) {
        self.delegate = delegate
        // stack = Thread.callStackSymbols.joined(separator: "\n")
    }

    @objc
    func unpause() {
        mutex.sync {
            guard let temp = delegate else {
                return
            }
            // stack = ""
            delegate = nil
            temp.unpause()
        }
    }
}

func CVectorReleaseObjectsAndDestroy(_ vector: CVector) {
    var temp = vector
    CVectorReleaseObjects(&temp);
    CVectorDestroy(&temp)
}

private class TokenArray: IteratorProtocol {
    typealias Element = VT100Token
    let length: Int
    private var cvector: CVector
    private var nextIndex = Int32(0)
    private let count: Int32
    private static var destroyQueue: DispatchQueue = {
        return DispatchQueue(label: "com.iterm2.token-destroyer")
    }()
    private var semaphore: DispatchSemaphore?

    var hasNext: Bool {
        return nextIndex < count
    }

    init(_ cvector: CVector, length: Int, semaphore: DispatchSemaphore?) {
        precondition(length > 0)
        self.cvector = cvector
        self.length = length
        self.semaphore = semaphore
        count = CVectorCount(&self.cvector)
    }

    func next() -> VT100Token? {
        guard hasNext else {
            return nil
        }
        defer {
            nextIndex += 1
            if nextIndex == count, let semaphore = semaphore {
                semaphore.signal()
                self.semaphore = nil
            }
        }
        return (CVectorGetObject(&cvector, nextIndex) as! VT100Token)
    }

    func skipToEnd() {
        if nextIndex >= count {
            return
        }
        nextIndex = count
        if let semaphore = semaphore {
            semaphore.signal()
            self.semaphore = nil
        }
    }

    deinit {
        semaphore?.signal()
        let temp = cvector
        Self.destroyQueue.async {
            CVectorReleaseObjectsAndDestroy(temp)
        }
    }
}

private class TwoTierTokenQueue {
    class Queue {
        private var arrays = [TokenArray]()
        var first: TokenArray? {
            return arrays.first
        }

        func removeFirst() {
            guard !arrays.isEmpty else {
                return
            }
            arrays.removeFirst()
        }

        func removeAll() {
            arrays.removeAll()
        }

        func append(_ tokenArray: TokenArray) {
            arrays.append(tokenArray)
        }

        var isEmpty: Bool {
            return arrays.isEmpty
        }
    }
    static let numberOfPriorities = 2
    private lazy var queues: [Queue] = {
        (0..<TwoTierTokenQueue.numberOfPriorities).map { _ in Queue() }
    }()

    private var nextQueueAndTokenArray: (Queue, TokenArray, Int)? {
        for (i, queue) in queues.enumerated() {
            if let tokenArray = queue.first {
                return (queue, tokenArray, i)
            }
        }
        return nil
    }

    var isEmpty: Bool {
        return queues.allSatisfy { $0.isEmpty }
    }

    // Closure returns false to stop, true to keep going
    func enumerateTokenArrays(_ closure: (TokenArray, Int) -> Bool) {
        while let tuple = nextQueueAndTokenArray {
            let (queue, tokenArray, priority) = tuple
            let shouldContinue = closure(tokenArray, priority)
            if !tokenArray.hasNext {
                queue.removeFirst()
            }
            if !shouldContinue {
                return
            }
        }
    }

    var hasHighPriorityToken: Bool {
        return !queues[0].isEmpty
    }

    func removeAll() {
        for i in 0..<queues.count {
            queues[i].removeAll()
        }
    }

    func addTokens(_ tokenArray: TokenArray, highPriority: Bool) {
        queues[highPriority ? 0 : 1].append(tokenArray)
    }
}

@objc(iTermTokenExecutor)
class TokenExecutor: NSObject {
    @objc weak var delegate: TokenExecutorDelegate? {
        didSet {
            impl.delegate = delegate
        }
    }
    private let semaphore = DispatchSemaphore(value: 4)
    private let impl: TokenExecutorImpl
    private let queue: DispatchQueue
    private static let isTokenExecutorSpecificKey = DispatchSpecificKey<Bool>()
    private var onExecutorQueue: Bool {
        return DispatchQueue.getSpecific(key: Self.isTokenExecutorSpecificKey) == true
    }

    @objc(initWithTerminal:slownessDetector:queue:)
    init(_ terminal: VT100Terminal,
         slownessDetector: iTermSlownessDetector,
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
    func addTokens(_ vector: CVector, length: Int) {
        addTokens(vector, length: length, highPriority: false)
    }

    // This takes ownership of vector.
    // You can call this on any queue when not high priority.
    // If high priority, then you must be on the main queue or have joined the main & mutation queue.
    @objc
    func addTokens(_ vector: CVector, length: Int, highPriority: Bool) {
        if length == 0 {
            return
        }
        if highPriority {
            iTermGCD.assertMutationQueueSafe()
            // Re-entrant code path so that the Inject trigger can do its job synchronously
            // (before other triggers run).
            reallyAddTokens(vector, length: length, highPriority: highPriority, semaphore: nil)
            return
        }
        // Normal code path for tokens from PTY. Use the semaphore to give backpressure to reading.
        let semaphore = self.semaphore
        _ = semaphore.wait(timeout: .distantFuture)
        queue.async { [weak self] in
            self?.reallyAddTokens(vector, length: length, highPriority: highPriority, semaphore: semaphore)
        }
    }

    // Any queue
    @objc
    func addSideEffect(_ task: @escaping TokenExecutorTask) {
        impl.addSideEffect(task)
    }

    // Any queue
    @objc
    func setSideEffectState(key: String, value: AnyObject) {
        impl.setSideEffectState(key: key, value: value)
    }

    // This can run on the main queue, or else on the mutation queue when joined.
    @objc(executeSideEffectsImmediatelySyncingFirst:)
    func executeSideEffectsImmediately(syncFirst: Bool) {
        impl.executeSideEffects(syncFirst: syncFirst)
    }

    // This takes ownership of vector.
    // You can only call this on `queue`.
    private func reallyAddTokens(_ vector: CVector,
                                 length: Int,
                                 highPriority: Bool,
                                 semaphore: DispatchSemaphore?) {
        let tokenArray = TokenArray(vector, length: length, semaphore: semaphore)
        self.impl.addTokens(tokenArray, highPriority: highPriority)
    }

    // Call this on the token evaluation queue.
    @objc
    func pause() -> Unpauser {
        return impl.pause()
    }

    // You can call this on any queue.
    @objc
    func schedule() {
        impl.schedule()
    }

    // Note that the task may be run either synchronously or asynchronously.
    // High priority tasks run as soon as possible. If a token is currently
    // executing, it runs after that token's execution completes. Token
    // execution is guaranteed to not block and should not take "very long".
    // You can call this on any queue.
    @objc
    func scheduleHighPriorityTask(_ task: @escaping TokenExecutorTask) {
        self.impl.scheduleHighPriorityTask(task, syncAllowed: onExecutorQueue)
    }
}

// This is a low-budget dequeue.
// Dequeue from the first array with a nonnil member. Rather than deleting the item, which gives
// quadratic performance, just nil it out. When a TaskArray becomes empty it can be removed from the
// list of task arrays. Since the list of task arrays will never have more than 2 elements, it's fast.
// Appends always go to the last task array. If the last task array has already been dequeued from
// then a new TaskArray is crated and appends to go it.
//
// taskArray = [ [] ]
// append(t1)
// taskARray = [ [t1] ]
// append(t2)
// taskArray = [ [t1, t2] ]
// dequeue() -> t1
// taskArray = [ [nil, t2] ]
// append(t3)
// taskArray = [ [nil, t2], [ t3 ] ]
// dequeue() -> t2
// taskArray = [ [], [ t3 ] ]
// append(t4)
// taskArray = [ [], [ t3, t4 ] ]
// dequeue() -> t3
// taskArray = [ [t4] ]

private class TaskQueue {
    class TaskArray {
        private var tasks: [TokenExecutorTask?] = []
        // Index to first valid element
        var head = 0
        var dequeue: TokenExecutorTask? {
            if head >= tasks.count {
                return nil
            }
            defer {
                head += 1
            }
            let value = tasks[head]
            tasks[head] = nil
            return value
        }

        var count: Int {
            return tasks.count
        }

        var canAppend: Bool {
            return head == 0
        }

        func append(_ task: @escaping TokenExecutorTask) {
            tasks.append(task)
        }
    }
    // This will never be empty
    private var arrays = [ TaskArray() ]
    private let mutex = Mutex()
    private var state = [String: AnyObject]()

    var count: Int {
        return mutex.sync {
            let counts = arrays.map { $0.count }
            return counts.reduce(0) { $0 + $1 }
        }
    }

    func append(_ task: @escaping TokenExecutorTask) {
        mutex.sync {
            if arrays.last!.canAppend {
                arrays.last!.append(task)
                return
            }
            let newTaskArray = TaskArray()
            newTaskArray.append(task)
            arrays.append(newTaskArray)
        }
    }

    func dequeue() -> TokenExecutorTask? {
        mutex.sync {
            while arrays.count > 1 {
                if let task = arrays[0].dequeue {
                    return task
                }
                arrays.removeFirst()
            }
            return arrays[0].dequeue
        }
    }

    func setState(key: String, value: AnyObject) {
        mutex.sync {
            state[key] = value
        }
    }

    func getAndResetState() -> [String: AnyObject] {
        return mutex.sync {
            let temp = state
            state = [:]
            return temp
        }
    }
}

extension TaskQueue: CustomDebugStringConvertible {
    var debugDescription: String {
        return "<TaskQueue: \(Unmanaged.passUnretained(self).toOpaque()) count=\(count)>"
    }
}

private class TokenExecutorImpl {
    private let terminal: VT100Terminal
    private let queue: DispatchQueue
    private let slownessDetector: iTermSlownessDetector
    private let semaphore: DispatchSemaphore
    private var taskQueue = TaskQueue()
    private var sideEffects = TaskQueue()
    private let tokenQueue = TwoTierTokenQueue()
    private var pauseCount = MutableAtomicObject(0)
    private var executingCount = 0
    private let executingSideEffects = MutableAtomicObject(false)
    private var sideEffectScheduler: PeriodicScheduler! = nil
    private let throughputEstimator = iTermThroughputEstimator(historyOfDuration: 5.0 / 30.0,
                                                               secondsPerBucket: 1.0 / 30.0)
    weak var delegate: TokenExecutorDelegate?

    init(_ terminal: VT100Terminal,
         slownessDetector: iTermSlownessDetector,
         semaphore: DispatchSemaphore,
         queue: DispatchQueue) {
        self.terminal = terminal
        self.queue = queue
        self.slownessDetector = slownessDetector
        self.semaphore = semaphore
        sideEffectScheduler = PeriodicScheduler(DispatchQueue.main, period: 1 / 30.0, action: { [weak self] in
            guard let self = self else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.executeSideEffects(syncFirst: true)
            }
        })
    }

    func pause() -> Unpauser {
        assertQueue()
        pauseCount.mutate { value in
            return value + 1
        }
        return Unpauser(self)
    }

    private var isPaused: Bool {
        assertQueue()
        return pauseCount.value > 0
    }

    func invalidate() {
        assertQueue()
        tokenQueue.removeAll()
    }

    func addTokens(_ tokenArray: TokenArray, highPriority: Bool) {
        assertQueue()
        throughputEstimator.addByteCount(tokenArray.length)
        tokenQueue.addTokens(tokenArray, highPriority: highPriority)
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
            assertQueue()
            if executingCount == 0 {
                execute()
                return
            }
        }
        schedule()
    }

    // Any queue
    func addSideEffect(_ task: @escaping TokenExecutorTask) {
        sideEffects.append(task)
        sideEffectScheduler.markNeedsUpdate()
    }

    // Any queue
    func setSideEffectState(key: String, value: AnyObject) {
        sideEffects.setState(key: key, value: value)
        sideEffectScheduler.markNeedsUpdate()
    }

    // This can run on the main queue, or else on the mutation queue when joined.
    func executeSideEffects(syncFirst: Bool) {
        iTermGCD.assertMainQueueSafe()
        if executingSideEffects.getAndSet(true) {
            // Do not allow re-entrant side-effects.
            return
        }
        defer {
            executingSideEffects.set(false)
        }
        var shouldSync = syncFirst
        while let task = sideEffects.dequeue() {
            if shouldSync {
                delegate?.tokenExecutorSync()
                shouldSync = false
            }
            let state = sideEffects.getAndResetState()
            if !state.isEmpty {
                delegate?.tokenExecutorHandleSideEffectState(state)
            }
            task()
        }

        // In case there were no tasks but there was state:
        let state = sideEffects.getAndResetState()
        if !state.isEmpty {
            if shouldSync {
                delegate?.tokenExecutorSync()
                shouldSync = false
            }
            delegate?.tokenExecutorHandleSideEffectState(state)
        }
    }

    private func assertQueue() {
        iTermGCD.assertMutationQueueSafe()
    }

    private func execute() {
        assertQueue()
        executingCount += 1
        defer {
            executingCount -= 1
            executeHighPriorityTasks()
        }
        executeHighPriorityTasks()
        guard let delegate = delegate else {
            return
        }
        let hadTokens = !tokenQueue.isEmpty
        var accumulatedLength = 0
        if !delegate.tokenExecutorShouldQueueTokens() {
            slownessDetector.measureEvent(PTYSessionSlownessEventExecute) {
                tokenQueue.enumerateTokenArrays { (vector, priority) in
                    return executeTokens(vector,
                                         priority: priority,
                                         accumulatedLength: &accumulatedLength,
                                         delegate: delegate)
                }
            }
        }
        if accumulatedLength > 0 || hadTokens {
            delegate.tokenExecutorDidExecute(length: accumulatedLength,
                                             throughput: throughputEstimator.estimatedThroughput)
        }
    }

    private func executeTokens(_ vector: TokenArray,
                               priority: Int,
                               accumulatedLength: inout Int,
                               delegate: TokenExecutorDelegate) -> Bool {
        defer {
            executeHighPriorityTasks()
        }
        while !isPaused, let token = vector.next() {
            executeHighPriorityTasks()
            if execute(token: token,
                       from: vector,
                       priority: priority,
                       accumulatedLength: &accumulatedLength,
                       delegate: delegate) {
                return true
            }
        }
        if isPaused {
            return false
        }
        accumulatedLength += vector.length
        return true
    }

    // Returns true to stop processing tokens in this vector and move on to the next one, if any.
    // Returns false to continue processing tokens in the vector, if any (and if not go to the next
    // vector).
    private func execute(token: VT100Token,
                         from vector: TokenArray,
                         priority: Int,
                         accumulatedLength: inout Int,
                         delegate: TokenExecutorDelegate) -> Bool {
        if delegate.tokenExecutorShouldDiscardTokens() {
            vector.skipToEnd()
            return true
        }
        DLog("Execute token \(token) cursor=\(delegate.tokenExecutorCursorCoordString())")

        terminal.execute(token)

        // Return true if we need to switch to a high priority queue.
        return (priority > 0) && tokenQueue.hasHighPriorityToken
    }

    private func executeHighPriorityTasks() {
        while let task = taskQueue.dequeue() {
            task()
        }
    }
}

extension TokenExecutorImpl: CustomDebugStringConvertible {
    var debugDescription: String {
        return "<TokenExecutorImpl: \(Unmanaged.passUnretained(self).toOpaque()): queue=\(queue.debugDescription) taskQueue=\(taskQueue.count) sideEffects=\(sideEffects.count) pauseCount=\(pauseCount.value) throughput=\(throughputEstimator.estimatedThroughput) delegate=\(String(describing: delegate))>"
    }
}

extension TokenExecutorImpl: UnpauserDelegate {
    // You can call this on any queue.
    func unpause() {
        let newCount = pauseCount.mutate { value in
            precondition(value > 0)
            return value - 1
        }
        if newCount == 0 {
            schedule()
        }
    }
}

extension TokenExecutor: IdempotentOperationScheduler {
    func scheduleIdempotentOperation(_ closure: @escaping () -> Void) {
        addSideEffect(closure)
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
    private let period: TimeInterval
    private let action: () -> ()

    @objc(initWithQueue:period:block:)
    init(_ queue: DispatchQueue, period: TimeInterval, action: @escaping () -> ()) {
        self.queue = queue
        self.period = period
        self.action = action
    }

    @objc func markNeedsUpdate() {
        needsUpdate = true
        schedule(reset: false)
    }

    @objc func schedule() {
        schedule(reset: false)
    }

    private func schedule(reset: Bool) {
        mutex.sync {
            if reset {
                _updatePending = false
            }
            guard _needsUpdate else {
                // Nothing changed.
                return
            }
            let wasPending = _updatePending
            _updatePending = true

            if wasPending {
                // Too soon to update.
                return
            }

            queue.asyncAfter(deadline: .now() + period) { [weak self] in
                guard let self = self else {
                    return
                }
                self.schedule(reset: true)
            }
            _needsUpdate = false
            action()
        }
    }
}

