//
//  ExecutionPermits.swift
//  iTerm2
//
//  Limits how many sessions execute tokens at once when each session has a mutation queue of its
//  own. A session's token executor takes a permit before executing tokens. When none is free it
//  waits in line, holding no thread, and is woken when a permit is handed to it.
//
//  Sessions that want permits share them fairly, by weight (stride scheduling). Each session has a
//  virtual run time that goes up by the time it ran divided by its weight, and the next permit goes
//  to the waiter with the lowest. Visible sessions have a larger weight, so they get more turns,
//  but a background session still gets its share. Virtual time only changes in three places:
//
//    1. A new session starts at the floor.
//    2. A holder is charged ran / weight at each checkpoint and when it releases its permit.
//    3. A session that had stopped wanting a permit is raised to the floor when it wants one
//       again, so it can't bank credit by being idle (and keeps any debt it ran up).
//
//  The floor is the lowest virtual time among sessions that hold or want a permit. It never goes
//  down, and it stays put when no session wants a permit.
//

import Foundation

@objc(iTermExecutionPermits)
final class ExecutionPermits: NSObject {
    final class Client {
        fileprivate enum State {
            case idle
            case waiting
            case holding
            case removed
        }
        // These are guarded by the ExecutionPermits' mutex.
        fileprivate var state = State.idle
        fileprivate var virtualTime: Double
        // Atomic rather than guarded by the mutex, so main can set it inside a join without taking
        // the permits' lock.
        fileprivate let visible = iTermAtomicInt64Create()
        // Sampled when the client gets a permit, so a visibility change takes effect from the next
        // one.
        fileprivate var weight = 1.0
        // Orders waiters with equal virtual times, first come first served.
        fileprivate var waitingSequence = 0
        // Keeps permits away from sessions that couldn't use them. Returns whether the session's
        // token execution is paused for any reason (a join, or a paused side effect). A paused session
        // would only sit on a permit until the pause ended, so handOff() passes over it to the next
        // waiter, and checkpoint() doesn't make a holder yield to it. It keeps its place in line, and
        // is considered again at the next handoff or when it asks for a permit after the pause ends.
        // Called on any thread with the mutex held, so it must be cheap and must not call back into
        // ExecutionPermits.
        fileprivate let isPaused: () -> Bool
        // Called with the mutex held when a permit is handed to the client. It must not block or
        // call back into ExecutionPermits; it should only schedule execution. Returns false if the
        // session is gone, in which case the permit goes to someone else.
        fileprivate let wake: () -> Bool

        fileprivate init(virtualTime: Double, isPaused: @escaping () -> Bool, wake: @escaping () -> Bool) {
            self.virtualTime = virtualTime
            self.isPaused = isPaused
            self.wake = wake
        }

        deinit {
            iTermAtomicInt64Free(visible)
        }
    }

    private let mutex = Mutex()
    private var _capacity: Int
    private let visibleWeight: Double
    // Clients holding a permit. Its count is the number of permits in use.
    private var holders = [Client]()
    private var inUse: Int {
        return holders.count
    }
    private var waiters = [Client]()
    private var floor = 0.0
    private var nextWaitingSequence = 0

    // The shared instance used by sessions with mutation queues of their own.
    static let shared: ExecutionPermits = {
        return ExecutionPermits(capacity: configuredCapacity,
                                visibleWeight: iTermAdvancedSettingsModel.visibleSessionExecutionWeight())
    }()

    private static var cores: Int {
        return ProcessInfo.processInfo.activeProcessorCount
    }

    private static var configuredCapacity: Int {
        return resolvedCapacity(configured: iTermPreferences.integer(forKey: kPreferenceKeyMaximumConcurrentTokenExecutions),
                                cores: cores)
    }

    // The capacity “Automatic” stands for on this computer.
    @objc static var automaticCapacity: Int {
        return resolvedCapacity(configured: 0, cores: cores)
    }

    // Never fewer permits than this, so one long-running token can't stop every other session.
    @objc static let minimumCapacity = 2

    // The largest number of permits the setting allows on this computer.
    @objc static var maximumCapacity: Int {
        return max(minimumCapacity, cores)
    }

    // Main queue. Applies a change to the setting right away.
    @objc static func capacityPreferenceDidChange() {
        shared.capacity = configuredCapacity
    }

    // The number of permits for a configured value. 0 means automatic, which depends on how many
    // cores there are.
    static func resolvedCapacity(configured: Int, cores: Int) -> Int {
        if configured == 0 {
            return max(minimumCapacity, min(4, cores / 4))
        }
        return clampedCapacity(configured, cores: cores)
    }

    // A number of permits brought into the range the setting allows. 0 is not automatic here.
    static func clampedCapacity(_ value: Int, cores: Int) -> Int {
        return max(minimumCapacity, min(value, cores))
    }

    // The setting's control shows and stores values through this.
    @objc static func clampedCapacity(_ value: Int) -> Int {
        return clampedCapacity(value, cores: cores)
    }

    init(capacity: Int, visibleWeight: Double) {
        _capacity = max(1, capacity)
        self.visibleWeight = max(1, visibleWeight)
        super.init()
    }

    // Any thread. Raising it hands permits to waiters right away. Lowering it lets holders run
    // until their next checkpoint, and no permit is handed out until fewer than the new capacity
    // are in use.
    var capacity: Int {
        get {
            return mutex.sync { _capacity }
        }
        set {
            mutex.sync {
                _capacity = max(1, newValue)
                handOff()
            }
        }
    }

    // Any thread.
    func makeClient(isPaused: @escaping () -> Bool, wake: @escaping () -> Bool) -> Client {
        return mutex.sync {
            raiseFloor()
            return Client(virtualTime: floor, isPaused: isPaused, wake: wake)
        }
    }

    // Any thread. Takes effect from the next time the client gets a permit. Doesn't take the lock.
    func setVisible(_ client: Client, _ visible: Bool) {
        iTermAtomicInt64Set(client.visible, visible ? 1 : 0)
    }

    // The session's queue. Returns true if the client holds a permit, either already (it was
    // handed one) or because one was free and no waiter that can run is ahead of it. Otherwise the
    // client waits in line and is woken once a permit is handed to it.
    func acquire(_ client: Client) -> Bool {
        return mutex.sync {
            switch client.state {
            case .holding:
                return true
            case .removed:
                it_fatalError("Acquiring a permit for a removed client")
            case .idle:
                raiseFloor()
                client.virtualTime = max(client.virtualTime, floor)
                enqueue(client)
            case .waiting:
                break
            }
            // A permit can be free with waiters in line if they were paused when it was given up.
            // Hand it out in the usual order, counting this client, so it doesn't take a permit
            // from a waiter ahead of it.
            return handOff(caller: client)
        }
    }

    // The session's queue, while holding a permit. Charges the time run since the last checkpoint
    // or acquire, and returns whether the holder should give up its permit: there are more holders
    // than permits, or a waiter that isn't paused has run no more than it.
    func checkpoint(_ client: Client, ran: TimeInterval) -> Bool {
        return mutex.sync {
            guard client.state == .holding else {
                return false
            }
            charge(client, ran: ran)
            if inUse > _capacity {
                return true
            }
            return waiters.contains { !$0.isPaused() && $0.virtualTime <= client.virtualTime }
        }
    }

    // The session's queue, while holding a permit. Charges the time run since the last checkpoint
    // or acquire and gives up the permit. With more work, the client waits in line again (and is
    // woken right away if it is still first).
    func release(_ client: Client, ran: TimeInterval, hasMoreWork: Bool) {
        mutex.sync {
            guard client.state == .holding else {
                return
            }
            charge(client, ran: ran)
            unhold(client)
            if hasMoreWork {
                enqueue(client)
            } else {
                client.state = .idle
            }
            handOff()
        }
    }

    // The session's queue. For a session that won't execute tokens for now (it has none, it is
    // paused for long, or it is in copy mode). Charges the time run if it held a permit, gives up
    // the permit or its place in line, and leaves it idle, so it rejoins at the floor later. This
    // also gives up a permit that was handed to it but not yet taken up.
    func relinquish(_ client: Client, ran: TimeInterval) {
        mutex.sync {
            switch client.state {
            case .holding:
                charge(client, ran: ran)
                unhold(client)
                client.state = .idle
                handOff()
            case .waiting:
                raiseFloor()
                waiters.removeAll { $0 === client }
                client.state = .idle
            case .idle, .removed:
                break
            }
        }
    }

    // Any thread. For a session that is going away. Gives up its permit or its place in line.
    func remove(_ client: Client) {
        mutex.sync {
            switch client.state {
            case .holding:
                raiseFloor()
                unhold(client)
            case .waiting:
                raiseFloor()
                waiters.removeAll { $0 === client }
            case .idle, .removed:
                break
            }
            client.state = .removed
            handOff()
        }
    }

    // MARK: - Private, with the mutex held

    private func hold(_ client: Client) {
        mutex.assertOwned()
        it_assert(inUse < _capacity, "Holding more permits than there are")
        it_assert(client.state == .idle || client.state == .waiting, "Holding a permit in state \(client.state)")
        it_assert(!holders.contains { $0 === client }, "Client already holds a permit")
        it_assert(!waiters.contains { $0 === client }, "A client must leave the line before holding a permit")
        client.state = .holding
        client.weight = iTermAtomicInt64Get(client.visible) != 0 ? visibleWeight : 1
        holders.append(client)
    }

    private func unhold(_ client: Client) {
        mutex.assertOwned()
        it_assert(client.state == .holding, "Releasing a permit in state \(client.state)")
        let countBefore = holders.count
        holders.removeAll { $0 === client }
        it_assert(holders.count == countBefore - 1, "Released a permit that wasn't held")
    }

    private func enqueue(_ client: Client) {
        mutex.assertOwned()
        it_assert(client.state == .idle || client.state == .holding, "Waiting in line in state \(client.state)")
        it_assert(!waiters.contains { $0 === client }, "Client is already in line")
        client.state = .waiting
        client.waitingSequence = nextWaitingSequence
        nextWaitingSequence += 1
        waiters.append(client)
    }

    private func charge(_ client: Client, ran: TimeInterval) {
        mutex.assertOwned()
        it_assert(client.state == .holding, "Charging a client in state \(client.state)")
        client.virtualTime += max(0, ran) / client.weight
        raiseFloor()
    }

    private func raiseFloor() {
        mutex.assertOwned()
        let lowest = min(holders.lazy.map(\.virtualTime).min() ?? .infinity,
                         waiters.lazy.map(\.virtualTime).min() ?? .infinity)
        if lowest.isFinite {
            floor = max(floor, lowest)
        }
    }

    // Hands free permits to the waiters with the lowest virtual times, skipping paused ones.
    // `caller`, a waiter asking for a permit itself, counts as able to run. It isn't woken if it
    // gets a permit; instead, this returns true.
    @discardableResult
    private func handOff(caller: Client? = nil) -> Bool {
        mutex.assertOwned()
        while inUse < _capacity {
            var best: Client?
            for waiter in waiters where waiter === caller || !waiter.isPaused() {
                if let current = best,
                   (current.virtualTime, current.waitingSequence) <= (waiter.virtualTime, waiter.waitingSequence) {
                    continue
                }
                best = waiter
            }
            guard let best else {
                return false
            }
            waiters.removeAll { $0 === best }
            hold(best)
            if best === caller {
                return true
            }
            if !best.wake() {
                unhold(best)
                best.state = .removed
            }
        }
        return false
    }

    // MARK: - Testing

    var inUseForTesting: Int {
        return mutex.sync { inUse }
    }

    var waitingCountForTesting: Int {
        return mutex.sync { waiters.count }
    }

    func virtualTimeForTesting(_ client: Client) -> Double {
        return mutex.sync { client.virtualTime }
    }
}
