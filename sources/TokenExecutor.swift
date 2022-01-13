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

    // `length` is the number of bytes of input that created the just-processed tokens.
    // Tokens may not actually be executed after this is called (e.g., if shouldDiscardTokens() returns true).
    func tokenExecutorWillEnqueueTokens(length: Int)

    // Called only when tokens are actually executed. `length` gives the number of bytes of input
    // that were executed.
    func tokenExecutorDidExecute(length: Int)

    // This is called even when paused. Every call to addTokens results in a call to didHandleInput().
    func tokenExecutorDidHandleInput()

    // Remove this eventually
    func tokenExecutorCursorCoordString() -> NSString

    // Synchronize state between threads.
    func tokenExecutorSync()
}

@objc(iTermTokenExecutorUnpauser)
class Unpauser: NSObject {
    private weak var delegate: UnpauserDelegate?
    private let mutex = Mutex()

    init(_ delegate: UnpauserDelegate) {
        self.delegate = delegate
    }

    @objc
    func unpause() {
        mutex.sync {
            guard let temp = delegate else {
                return
            }
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

    var hasNext: Bool {
        return nextIndex < count
    }

    init(_ cvector: CVector, length: Int) {
        self.cvector = cvector
        self.length = length
        count = CVectorCount(&self.cvector)
    }

    func next() -> VT100Token? {
        guard hasNext else {
            return nil
        }
        defer {
            nextIndex += 1
        }
        return (CVectorGetObject(&cvector, nextIndex) as! VT100Token)
    }

    func skipToEnd() {
        nextIndex = count
    }

    deinit {
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
    // You can call this on any queue.
    @objc
    func addTokens(_ vector: CVector, length: Int, highPriority: Bool) {
        if highPriority && onExecutorQueue {
            // Re-entrant code path so that the Inject trigger can do its job synchronously
            // (before other triggers run).
            reallyAddTokens(vector, length: length, highPriority: highPriority)
            return
        }
        #warning("TODO: Test inserting a high-pri token from another dispatch queue. It's not yet possible to do off the main queue.")
        // Normal code path for tokens from PTY. Use the semaphore to give backpressure to reading.
        let semaphore = self.semaphore
        _ = semaphore.wait(timeout: .distantFuture)
        queue.async { [weak self] in
            self?.reallyAddTokens(vector, length: length, highPriority: highPriority)
            semaphore.signal()
        }
    }

    // Any queue
    @objc
    func addSideEffect(_ task: @escaping TokenExecutorTask) {
        impl.addSideEffect(task)
    }

    // This can run on the main queue, or else on the mutation queue when joined.
    @objc
    func executeSideEffectsImmediately() {
        impl.executeSideEffects()
    }

    // This takes ownership of vector.
    // You can only call this on `queue`.
    private func reallyAddTokens(_ vector: CVector, length: Int, highPriority: Bool) {
        let tokenArray = TokenArray(vector, length: length)
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
    @objc
    func scheduleHighPriorityTask(_ task: @escaping TokenExecutorTask) {
        self.impl.scheduleHighPriorityTask(task, syncAllowed: onExecutorQueue)
    }
}

private class TaskQueue {
    private var tasks = [TokenExecutorTask]()
    private let mutex = Mutex()

    func append(_ task: @escaping TokenExecutorTask) {
        mutex.sync {
            tasks.append(task)
        }
    }

    func dequeue() -> TokenExecutorTask? {
        mutex.sync {
            guard let value = tasks.first else {
                return nil
            }
            tasks.removeFirst()
            return value
        }
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
    private var pauseCount = 0
    private var executingCount = 0

    weak var delegate: TokenExecutorDelegate?

    init(_ terminal: VT100Terminal,
         slownessDetector: iTermSlownessDetector,
         semaphore: DispatchSemaphore,
         queue: DispatchQueue) {
        self.terminal = terminal
        self.queue = queue
        self.slownessDetector = slownessDetector
        self.semaphore = semaphore
    }

    func pause() -> Unpauser {
        assertQueue()
        pauseCount += 1
        return Unpauser(self)
    }

    private var isPaused: Bool {
        assertQueue()
        return pauseCount > 0
    }

    func invalidate() {
        assertQueue()
        tokenQueue.removeAll()
    }

    func addTokens(_ tokenArray: TokenArray, highPriority: Bool) {
        assertQueue()
        delegate?.tokenExecutorWillEnqueueTokens(length: tokenArray.length)
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
        DispatchQueue.main.async { [weak self] in
            self?.executeSideEffects()
        }
    }

    // Main queue or mutation queue while joined.
    func executeSideEffects() {
        var haveSynced = false
        while let task = sideEffects.dequeue() {
            if !haveSynced {
                delegate?.tokenExecutorSync()
                haveSynced = true
            }
            task()
        }
    }

    private func assertQueue() {
        dispatchPrecondition(condition: .onQueue(queue))
    }

    private func execute() {
        assertQueue()
        executingCount += 1
        defer {
            executingCount -= 1
            executeHighPriorityTasks()
        }
        guard let delegate = delegate else {
            return
        }
        defer {
            delegate.tokenExecutorDidHandleInput()
        }
        executeHighPriorityTasks()
        if delegate.tokenExecutorShouldQueueTokens() {
            #warning("TODO: Apply backpressure when queueing to avoid building up a huge queue (e.g., in copy mode while running yes)")
            return
        }
        var accumulatedLength = 0
        slownessDetector.measureEvent(PTYSessionSlownessEventExecute) {
            tokenQueue.enumerateTokenArrays { (vector, priority) in
                return executeTokens(vector,
                                     priority: priority,
                                     accumulatedLength: &accumulatedLength,
                                     delegate: delegate)
            }
        }
        if accumulatedLength > 0 {
            delegate.tokenExecutorDidExecute(length: accumulatedLength)
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

extension TokenExecutorImpl: UnpauserDelegate {
    func unpause() {
        precondition(pauseCount > 0)
        pauseCount -= 1
        if pauseCount == 0 {
            schedule()
        }
    }
}
