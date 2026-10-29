//
//  ExecutionPermitHolder.swift
//  iTerm2
//
//  One token executor's side of ExecutionPermits: whether it holds a permit or is waiting in line
//  for one, how long it has run in its current time slice, parking the permit when the executor
//  runs out of tokens, and giving it up when the executor is paused for long. The executor asks
//  it before executing tokens, between tokens, and when execute() ends.
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
    private let queue: DispatchQueue
    private let execute: () -> Void
    // Any queue. When a permit was last handed over, for TokenExecutionStats.
    private let wokenAt = iTermAtomicInt64Create()
    // Executor's queue. Whether this executor holds a permit, and whether it is in line for one
    // (or was handed one it hasn't taken up yet). With neither, there is nothing to give up.
    private var holding = false
    private var inLine = false
    // Executor's queue. Whether the permit held is parked (idle), where another session may take
    // it. It must be resumed before running.
    private var parked = false
    // Executor's queue. Set when the slice ended with a waiter owed the permit, so settle() gives
    // it up.
    private var yieldRequested = false
    // Executor's queue. When the current run began (nil while stopped, as for a join or while
    // parked), and how long it had run in this slice before that.
    private var runStart: UInt64?
    // Returns monotonic nanoseconds. Injectable for tests.
    private let now: () -> UInt64
    // Executor's queue. Reading the clock for every token cost about 2% of token execution, so the
    // slice is checked only every tokensPerClockCheck tokens. A slice can then run a few tokens
    // long, which takes microseconds. 0 means check at the next token, as after the clock restarts.
    private var tokensUntilClockCheck = 0
    private static let tokensPerClockCheck = 8
    private var ranBeforeJoin: TimeInterval = 0
    private static let timeSlice = max(0.0005, iTermAdvancedSettingsModel.tokenExecutionTimeSlice())

    // Executor's queue. Set by the executor to collect stats for an execute() call; nil otherwise.
    var stats: Stats?

    // Executor's queue. Whether the executor holds a permit it may run with.
    var isHolding: Bool {
        return holding && !parked
    }

    // `isPaused` may be called on any thread; see ExecutionPermits.Client. `execute` runs on `queue`
    // when a permit is handed to this holder.
    init(permits: ExecutionPermits,
         queue: DispatchQueue,
         isPaused: @escaping () -> Bool,
         execute: @escaping () -> Void,
         now: @escaping () -> UInt64 = monotonicNanoseconds) {
        self.now = now
        self.permits = permits
        self.queue = queue
        self.execute = execute
        let wokenAt = self.wokenAt
        client = permits.makeClient(isPaused: isPaused, wake: {
            // This must not strongly reference the holder or the executor, which own the client.
            // deinit gives up the permit, so a wake that reaches a dead executor isn't lost.
            if TokenExecutionStats.enabled {
                iTermAtomicInt64Set(wokenAt, Int64(now()))
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
    // waits in line. If it won't execute tokens for now, it parks its permit, or gives up its place
    // in line (including a permit handed to it while it was waiting).
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
            if holding {
                park()
            } else {
                relinquish()
            }
            return .dontExecute
        }
        resumeParkedPermit()
        if holding {
            // The clock stops for a join and while parked. Restart it, or the slice would never
            // end and the time run would never be charged.
            if runStart == nil {
                runStart = now()
                tokensUntilClockCheck = 0
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
                stats?.handoffGap = elapsed(since: UInt64(woken))
            }
        }
        holding = true
        inLine = false
        if runStart == nil {
            runStart = now()
            tokensUntilClockCheck = 0
        }
        return .execute
    }

    // Executor's queue, between tokens. Whether the executor has used up its time slice and
    // should give its permit to a waiting session.
    func sliceIsOverAndShouldYield() -> Bool {
        guard holding, !parked, let runStart else {
            return false
        }
        if tokensUntilClockCheck > 0 {
            tokensUntilClockCheck -= 1
            return false
        }
        tokensUntilClockCheck = Self.tokensPerClockCheck - 1
        let ran = ranBeforeJoin + elapsed(since: runStart)
        if ran < Self.timeSlice {
            return false
        }
        // Charge for the slice and start a new one, whether or not anyone is owed the permit.
        ranBeforeJoin = 0
        self.runStart = now()
        let shouldYield = timing { permits.checkpoint(client, ran: ran) }
        if shouldYield {
            stats?.yielded = true
            yieldRequested = true
        }
        return shouldYield
    }

    // Executor's queue, at the end of execute(). `hasTokensToExecute` says whether tokens remain
    // that could execute once any pause ends. `hasTokensToExecute` is called only while holding a
    // running permit.
    //   - After yielding at the end of a slice, it gives up the permit (even when paused for a join),
    //     and waits in line again if it has more to do (unless it is first in line, when it keeps
    //     the permit and carries on).
    //   - Paused for anything but joins, which can last a long time, it gives up the permit.
    //   - With tokens left, paused only for joins, it keeps the permit and stops its clock.
    //   - With tokens left otherwise (they arrived while it ran), it keeps the permit and carries on.
    //   - With nothing to do, it parks the permit.
    func settle(isPaused: Bool, isPausedOnlyForJoins: Bool, hasTokensToExecute: () -> Bool) {
        let yielded = yieldRequested
        yieldRequested = false
        guard holding, !parked else {
            return
        }
        let hasTokens = hasTokensToExecute()
        if isPaused && !isPausedOnlyForJoins {
            relinquish()
            return
        }
        if yielded {
            // Owed to a waiter. Give it up even when paused for a join, or the waiter would wait
            // for this session's next slice.
            let ran = ranBeforeJoin + elapsed(since: runStart)
            ranBeforeJoin = 0
            runStart = nil
            let keeps = timing {
                permits.release(client, ran: ran, hasMoreWork: hasTokens)
            }
            holding = keeps
            inLine = hasTokens && !keeps
            if keeps {
                // First in line after all, so it kept the permit, charged for the time run.
                queue.async(execute: execute)
            }
            return
        }
        guard hasTokens else {
            park()
            return
        }
        // Keep the permit, stopping the clock until execution resumes.
        ranBeforeJoin += elapsed(since: runStart)
        runStart = nil
        if !isPaused {
            queue.async(execute: execute)
        }
    }

    // Executor's queue. Resumes a parked permit, if there is one. If another session took it while
    // it was idle (charging the time run), the executor no longer holds a permit.
    private func resumeParkedPermit() {
        guard holding && parked else {
            return
        }
        parked = false
        if !timing({ permits.resume(client) }) {
            holding = false
            ranBeforeJoin = 0
            runStart = nil
        }
    }

    // Executor's queue, holding a running permit. Parks it, or gives it up if someone who can run
    // is in line.
    private func park() {
        guard !parked else {
            return
        }
        let ran = ranBeforeJoin + elapsed(since: runStart)
        runStart = nil
        if timing({ permits.park(client, uncharged: ran) }) {
            parked = true
            ranBeforeJoin = ran
        } else {
            // Given up, and charged.
            holding = false
            ranBeforeJoin = 0
        }
    }

    // Executor's queue. Gives up the permit, or the place in line, if it has either.
    func relinquish() {
        resumeParkedPermit()
        guard holding || inLine else {
            return
        }
        let ran = holding ? ranBeforeJoin + elapsed(since: runStart) : 0
        holding = false
        inLine = false
        ranBeforeJoin = 0
        runStart = nil
        iTermAtomicInt64GetAndReset(wokenAt)
        timing {
            permits.relinquish(client, ran: ran)
        }
    }

    private func elapsed(since start: UInt64?) -> TimeInterval {
        guard let start else {
            return 0
        }
        return TimeInterval(now() &- start) / TimeInterval(NSEC_PER_SEC)
    }

    // Runs a call into ExecutionPermits, timing it for TokenExecutionStats.
    private func timing<T>(_ closure: () -> T) -> T {
        guard stats != nil else {
            return closure()
        }
        let start = now()
        defer {
            stats?.permits += elapsed(since: start)
        }
        return closure()
    }
}
