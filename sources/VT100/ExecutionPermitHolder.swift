//
//  ExecutionPermitHolder.swift
//  iTerm2
//
//  One token executor's side of ExecutionPermits: whether it holds a permit or is waiting in line
//  for one, how long it has run in its current time slice, and giving the permit up whenever the
//  executor won't execute tokens. The executor asks it before executing tokens, between tokens,
//  and when execute() ends.
//
//  Everything here runs in the executor's queue's context (possibly on the main thread, in a
//  queue.sync). Joins never call into it: a join only pauses the executor, and must never take the
//  permits' lock. The executor's queue sorts things out when it runs execute() after the unpause.
//

import Foundation

final class ExecutionPermitHolder {
    enum Decision {
        // Execute tokens now.
        case execute
        // Don't execute tokens (none, paused, or in copy mode). Tokens that arrived since the
        // check wait for the next execute().
        case dontExecute
        // Wait in line. The executor's execute closure runs when a permit is handed over.
        case waitForPermit
    }

    // What this holder did during one execute() call, for TokenExecutionStats.
    struct Stats {
        var permits: TimeInterval = 0
        var waited = false
        var yielded = false
        var handoffGap: TimeInterval?
    }

    private let permits: ExecutionPermits
    private let client: ExecutionPermits.Client
    // Any queue. When a permit was last handed over, for TokenExecutionStats.
    private let wokenAt = iTermAtomicInt64Create()
    // Executor's queue. Whether this executor holds a permit, and whether it is in line for one
    // (or was handed one it hasn't taken up yet). With neither, there is nothing to give up.
    private var holding = false
    private var inLine = false
    // Executor's queue. When the current run began (nil while paused for a join), and how long it
    // had run in this slice before the join.
    private var runStart: UInt64?
    private var ranBeforeJoin: TimeInterval = 0
    private static let timeSlice = max(0.0005, iTermAdvancedSettingsModel.tokenExecutionTimeSlice())

    // Executor's queue. Set by the executor to collect stats for an execute() call; nil otherwise.
    var stats: Stats?

    // Executor's queue. Whether the executor holds a permit.
    var isHolding: Bool {
        return holding
    }

    // `isPaused` may be called on any thread; see ExecutionPermits.Client. `execute` runs on `queue`
    // when a permit is handed to this holder.
    init(permits: ExecutionPermits,
         queue: DispatchQueue,
         isPaused: @escaping () -> Bool,
         execute: @escaping () -> Void) {
        self.permits = permits
        let wokenAt = self.wokenAt
        client = permits.makeClient(isPaused: isPaused, wake: {
            // This runs with the permits' lock held, so it must not reference the holder or the
            // executor: if it made the last strong reference to either, its deinit would run here
            // and take the lock again. deinit gives up the permit, so a wake that reaches a dead
            // executor isn't lost.
            if TokenExecutionStats.enabled {
                iTermAtomicInt64Set(wokenAt, Int64(monotonicNanoseconds()))
            }
            queue.async(execute: execute)
            return true
        })
    }

    deinit {
        permits.remove(client)
        iTermAtomicInt64Free(wokenAt)
    }

    // Executor's queue, or main while joined to it. Doesn't take the permits' lock.
    func setVisible(_ visible: Bool) {
        permits.setVisible(client, visible)
    }

    // Executor's queue. Decides whether tokens may be executed now. Without a permit, the executor
    // waits in line. If it won't execute tokens, it gives up its permit or its place in line,
    // including a permit handed to it while it was waiting.
    func decide(hasTokens: Bool,
                willQueueTokens: Bool,
                isPaused: Bool,
                isPausedOnlyForJoins: Bool) -> Decision {
        // Not executing must mean .dontExecute: the executor reads its token queue again when it
        // executes, and tokens may have arrived since the caller found it empty or paused. They
        // must not run without a permit.
        if isPaused {
            // Paused only for joins, keep the permit or the place in line, because the join will
            // be over soon. Any other pause can last a long time.
            if isPausedOnlyForJoins {
                // A permit handed over now is taken up after the join. Drop its handoff time, so
                // the handoff gap measures scheduling delay rather than the join.
                iTermAtomicInt64GetAndReset(wokenAt)
            } else {
                relinquish()
            }
            return .dontExecute
        }
        if willQueueTokens || !hasTokens {
            relinquish()
            return .dontExecute
        }
        if holding {
            // Kept through a join, which stopped the clock. Restart it, or the slice would never
            // end and the time run would never be charged.
            if runStart == nil {
                runStart = monotonicNanoseconds()
            }
            return .execute
        }
        let acquired = timing { permits.acquire(client) }
        guard acquired else {
            if gDebugLogging.boolValue { DLog("Waiting for an execution permit") }
            stats?.waited = true
            inLine = true
            return .waitForPermit
        }
        if stats != nil {
            let woken = iTermAtomicInt64GetAndReset(wokenAt)
            if woken != 0 {
                stats?.handoffGap = secondsSince(UInt64(woken))
            }
        }
        holding = true
        inLine = false
        if runStart == nil {
            runStart = monotonicNanoseconds()
        }
        return .execute
    }

    // Executor's queue, between tokens. Whether the executor has used up its time slice and
    // should give its permit to a waiting session.
    func sliceIsOverAndShouldYield() -> Bool {
        guard holding, let runStart else {
            return false
        }
        let ran = ranBeforeJoin + secondsSince(runStart)
        if ran < Self.timeSlice {
            return false
        }
        // Charge for the slice and start a new one, whether or not anyone is owed the permit.
        ranBeforeJoin = 0
        self.runStart = monotonicNanoseconds()
        let shouldYield = timing { permits.checkpoint(client, ran: ran) }
        if shouldYield {
            stats?.yielded = true
        }
        return shouldYield
    }

    // Executor's queue, at the end of execute(). `hasTokensToExecute` says whether tokens remain
    // that could execute once any pause ends. With some, paused only for joins, the executor keeps
    // its permit and stops its clock. Otherwise it gives up the permit, and waits in line again if
    // it isn't paused and has more to do. `hasTokensToExecute` is called only while holding.
    func settle(isPaused: Bool, isPausedOnlyForJoins: Bool, hasTokensToExecute: () -> Bool) {
        guard holding else {
            return
        }
        let ran = ranBeforeJoin + secondsSince(runStart)
        let hasTokens = hasTokensToExecute()
        if hasTokens && isPaused && isPausedOnlyForJoins {
            ranBeforeJoin = ran
            runStart = nil
            return
        }
        let more = hasTokens && !isPaused
        holding = false
        inLine = more
        ranBeforeJoin = 0
        runStart = nil
        timing {
            permits.release(client, ran: ran, hasMoreWork: more)
        }
    }

    // Executor's queue. Gives up the permit, or the place in line, if it has either.
    func relinquish() {
        guard holding || inLine else {
            return
        }
        let ran = holding ? ranBeforeJoin + secondsSince(runStart) : 0
        holding = false
        inLine = false
        ranBeforeJoin = 0
        runStart = nil
        iTermAtomicInt64GetAndReset(wokenAt)
        timing {
            permits.relinquish(client, ran: ran)
        }
    }

    // Runs a call into ExecutionPermits, timing it for TokenExecutionStats.
    private func timing<T>(_ closure: () -> T) -> T {
        guard stats != nil else {
            return closure()
        }
        let start = monotonicNanoseconds()
        defer {
            stats?.permits += secondsSince(start)
        }
        return closure()
    }
}
