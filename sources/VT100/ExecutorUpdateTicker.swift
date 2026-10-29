//
//  ExecutorUpdateTicker.swift
//  iTerm2
//
//  Sends sessions' executor updates (bytes executed, estimated throughput) to the main thread, at
//  most 120 times a second in all. Each session used to run its own 120 Hz timer while it had
//  output, so 19 busy sessions meant about 2,300 timer registrations and main-thread dispatches a
//  second. Now one timer runs while any session has an update, and each tick sends every pending
//  update in one dispatch.
//
//  A session's update goes out right away if the session hasn't delivered one within the last
//  period, so the first sign of new output (such as a keystroke's echo) isn't delayed, even while
//  other sessions keep the ticker running. A session that delivered recently waits for the next
//  tick, at most 1/120 s, unless it was expedited: after a keystroke, the next update (the echo)
//  goes out right away regardless.
//

import Foundation

protocol ExecutorUpdateTickSource: AnyObject {
    // Starts calling `handler` once a period, on any queue (the same one each time), until stop().
    // The ticker calls start() and stop() alternately, starting with start().
    func start(_ handler: @escaping () -> Void)
    func stop()
}

// One session's link to the ticker.
@objc(iTermExecutorUpdateTickerClient)
final class ExecutorUpdateTickerClient: NSObject {
    // Sends the session's update: VT100Screen forks what executed and gives it to its delegate.
    // Called with no arguments, through the ticker's `deliver`, so on the main thread.
    fileprivate let fire: () -> Void
    private unowned let ticker: ExecutorUpdateTicker
    // Whether an update is waiting to go out. Set by markNeedsUpdate(), cleared just before fire().
    fileprivate let pending = iTermAtomicInt64Create()
    // When an update last went out, from the ticker's clock, or 0 if none has.
    fileprivate let lastDelivered = iTermAtomicInt64Create()
    // Set by expedite(), consumed by the next update to go out right away.
    fileprivate let expedited = iTermAtomicInt64Create()

    fileprivate init(ticker: ExecutorUpdateTicker, fire: @escaping () -> Void) {
        self.ticker = ticker
        self.fire = fire
    }

    deinit {
        iTermAtomicInt64Free(pending)
        iTermAtomicInt64Free(lastDelivered)
        iTermAtomicInt64Free(expedited)
    }

    // Any queue. Cheap when an update is already waiting.
    @objc func markNeedsUpdate() {
        if iTermAtomicInt64CompareAndSwap(pending, 0, 1) {
            ticker.add(self)
        } else if takeExpedite() {
            // Already waiting for the tick, but expedited since.
            ticker.deliverQueuedNow(self)
        }
    }

    // Main queue, when the user presses a key. The session's next update, normally the echo, goes
    // out right away, so the redraw that shows it isn't throttled.
    @objc func expedite() {
        iTermAtomicInt64Set(expedited, 1)
    }

    // Clears the expedite flag. Returns whether it was set. A compare-and-swap, so of the threads
    // that find it set (marking from the mutation queue, or adding to the ticker), exactly one acts
    // on it.
    fileprivate func takeExpedite() -> Bool {
        return iTermAtomicInt64CompareAndSwap(expedited, 1, 0)
    }

    fileprivate func deliverNow() {
        // Clear first, so an update marked while this runs goes out at the next tick. fire()
        // collects everything marked before now.
        iTermAtomicInt64Set(pending, 0)
        iTermAtomicInt64Set(lastDelivered, Int64(ticker.now()))
        fire()
    }
}

@objc(iTermExecutorUpdateTicker)
final class ExecutorUpdateTicker: NSObject {
    @objc static let shared = ExecutorUpdateTicker(
        tickSource: DispatchTimerTickSource(period: ExecutorUpdateTicker.period),
        period: ExecutorUpdateTicker.period,
        now: { DispatchTime.now().uptimeNanoseconds },
        deliver: { DispatchQueue.main.async(execute: $0) })
    private static let period = 1.0 / 120.0

    private let tickSource: ExecutorUpdateTickSource
    private let periodNanoseconds: UInt64
    // Returns the current time in nanoseconds, from a monotonic clock. Called on any queue.
    fileprivate let now: () -> UInt64
    // Runs its argument, a block that sends updates, on the queue updates go to (the main queue in
    // production). Called on any queue, without the ticker's lock held.
    private let deliver: (@escaping () -> Void) -> Void

    private struct State {
        // Whether the tick source is running.
        var ticking = false
        // Clients whose updates wait for the next tick.
        var pending = [ExecutorUpdateTickerClient]()
    }
    private let state = MutableAtomicObject(State())

    init(tickSource: ExecutorUpdateTickSource,
         period: TimeInterval,
         now: @escaping () -> UInt64,
         deliver: @escaping (@escaping () -> Void) -> Void) {
        self.tickSource = tickSource
        self.periodNanoseconds = UInt64(period * 1e9)
        self.now = now
        self.deliver = deliver
    }

    // Any queue. `fire` sends the session's update; see ExecutorUpdateTickerClient.fire.
    @objc func makeClient(fire: @escaping () -> Void) -> ExecutorUpdateTickerClient {
        return ExecutorUpdateTickerClient(ticker: self, fire: fire)
    }

    // Any queue. The client's update is pending.
    fileprivate func add(_ client: ExecutorUpdateTickerClient) {
        let last = UInt64(iTermAtomicInt64Get(client.lastDelivered))
        let deliveredRecently = last != 0 && now() &- last < periodNanoseconds
        let expedite = client.takeExpedite()
        let deliverNow = state.mutableAccess { state -> Bool in
            if state.ticking && deliveredRecently && !expedite {
                state.pending.append(client)
                return false
            }
            if !state.ticking {
                state.ticking = true
                tickSource.start { [weak self] in
                    self?.tick()
                }
            }
            return true
        }
        if deliverNow {
            deliver {
                client.deliverNow()
            }
        }
    }

    // Any queue. The client's update was waiting for the tick and it has been expedited (the caller
    // took the expedite flag). If it's still waiting (not already on its way), it goes out right
    // away instead.
    fileprivate func deliverQueuedNow(_ client: ExecutorUpdateTickerClient) {
        let found = state.mutableAccess { state -> Bool in
            guard let i = state.pending.firstIndex(where: { $0 === client }) else {
                return false
            }
            state.pending.remove(at: i)
            return true
        }
        if found {
            deliver {
                client.deliverNow()
            }
        }
    }

    private func tick() {
        let batch = state.mutableAccess { state -> [ExecutorUpdateTickerClient] in
            let batch = state.pending
            state.pending.removeAll()
            if batch.isEmpty && state.ticking {
                // Nothing happened for a whole period. Stop until the next update, which goes out
                // right away.
                state.ticking = false
                tickSource.stop()
            }
            return batch
        }
        guard !batch.isEmpty else {
            return
        }
        deliver {
            for client in batch {
                client.deliverNow()
            }
        }
    }
}

// A repeating timer on a private queue.
private final class DispatchTimerTickSource: ExecutorUpdateTickSource {
    private let period: TimeInterval
    private let timer: DispatchSourceTimer

    init(period: TimeInterval) {
        self.period = period
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.iterm2.executor-update-ticker",
                                                                     qos: .userInteractive))
    }

    func start(_ handler: @escaping () -> Void) {
        timer.setEventHandler(handler: handler)
        timer.schedule(deadline: .now() + period, repeating: period, leeway: .milliseconds(1))
        timer.resume()
    }

    func stop() {
        timer.suspend()
    }
}
