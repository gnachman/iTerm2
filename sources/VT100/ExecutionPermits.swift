//
//  ExecutionPermits.swift
//  iTerm2
//
//  Limits how many sessions execute tokens at once when each session has a mutation queue of its
//  own. A session's token executor takes a permit before executing tokens. When none is free it
//  waits in line, holding no thread, and is woken when a permit is handed to it.
//
//  A session that runs out of tokens parks its permit: it keeps it, idle, so its next tokens run
//  without taking the lock. Parking and resuming are lock-free. A session that needs a permit when
//  none is free takes one from an idle holder, under the lock. A holder parks by marking itself
//  idle and then checking for waiters, and a waiter gets in line before looking for idle holders,
//  so at least one of them sees the other: a waiter is never left in line beside an idle permit.
//
//  Sessions that want permits share them fairly, by weight (stride scheduling). Each session has a
//  virtual run time that goes up by the time it ran divided by its weight, and the next permit goes
//  to the waiter with the lowest. Visible sessions have a larger weight, so they get more turns,
//  but a background session still gets its share. Virtual time only changes in three places:
//
//    1. A new session starts at the floor.
//    2. A holder is charged ran / weight at each checkpoint, when it releases its permit, and when
//       its idle permit is taken. Before being charged, it is raised to the floor, which matters
//       for a holder that was idle while others ran.
//    3. A session that had stopped wanting a permit is raised to the floor when it wants one
//       again, so it can't bank credit by being idle (and keeps any debt it ran up).
//
//  The floor is the lowest virtual time among sessions that are running or want a permit (idle
//  holders don't count). It never goes down, and it stays put when no session wants a permit.
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
        // Called when a permit is handed to the client, after the mutex is released, so other
        // sessions don't wait while it schedules execution. It may be called after the client was
        // removed. It should only schedule execution. Returns false if the session is gone, in
        // which case the permit goes to someone else.
        fileprivate let wake: () -> Bool
        // Whether a holder's permit is parked: running (or not holding), idle, or taken by another
        // session while idle. Only the holder moves it from running to idle, and from taken back
        // to running; only another session, with the mutex held, moves it from idle to taken.
        fileprivate let parking = iTermAtomicInt64Create()
        // While parked, the time run that hasn't been charged yet, in nanoseconds. Whoever takes
        // the permit charges it.
        fileprivate let unchargedNanoseconds = iTermAtomicInt64Create()

        // Guarded by the mutex. When the client last got in line.
        fileprivate var waitingSince = UInt64(0)
        // When a running holder was last heard from (it got its permit, reached a checkpoint, or
        // resumed). For the health check.
        fileprivate let lastHeardFrom = iTermAtomicInt64Create()

        // With the mutex held.
        fileprivate func description(now: UInt64) -> String {
            let id = String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16)
            var parts = ["client \(id)", "vtime=\(virtualTime)", "weight=\(weight)"]
            switch state {
            case .holding:
                parts.append(isParked ? "holding parked" : "holding running")
                let heardFrom = UInt64(iTermAtomicInt64Get(lastHeardFrom))
                parts.append("heardFrom=\(Double(now &- heardFrom) / 1e9)s ago")
            case .waiting:
                parts.append("waiting for \(Double(now &- waitingSince) / 1e9)s")
                parts.append(isPaused() ? "paused" : "runnable")
            case .idle:
                parts.append("idle")
            case .removed:
                parts.append("removed")
            }
            return parts.joined(separator: " ")
        }

        fileprivate var isParked: Bool {
            return iTermAtomicInt64Get(parking) == Parking.idle.rawValue
        }

        fileprivate init(virtualTime: Double, isPaused: @escaping () -> Bool, wake: @escaping () -> Bool) {
            self.virtualTime = virtualTime
            self.isPaused = isPaused
            self.wake = wake
        }

        deinit {
            iTermAtomicInt64Free(visible)
            iTermAtomicInt64Free(parking)
            iTermAtomicInt64Free(unchargedNanoseconds)
            iTermAtomicInt64Free(lastHeardFrom)
        }
    }

    fileprivate enum Parking: Int64 {
        case running = 0
        case idle = 1
        case taken = 2
    }

    private let mutex = Mutex()
    private var _capacity: Int
    private let visibleWeight: Double
    // Clients holding a permit. Its count is the number of permits in use.
    private var holders = [Client]()
    private var inUse: Int {
        return holders.count
    }
    private var waiters = [Client]() {
        didSet {
            // Parking reads this without the lock. It's stored before handOff() looks for idle
            // holders to take a permit from; see the comment at the top of the file.
            iTermAtomicInt64Set(waiterCount, Int64(waiters.count))
        }
    }
    private let waiterCount = iTermAtomicInt64Create()
    private var floor = 0.0
    private var nextWaitingSequence = 0
    private let now: () -> UInt64
    // Runs checkHealth() once a second while anyone waits or holds a running permit. Nil if the
    // check isn't periodic (tests call it directly). Guarded by the mutex.
    private let healthTimer: DispatchSourceTimer?
    private var healthTimerRunning = false
    private static let strandedWaiterThreshold = UInt64(NSEC_PER_SEC)
    // Waits of over a second, since the last summary in the debug log. Guarded by the mutex.
    private static let longWaitThreshold = UInt64(NSEC_PER_SEC)
    private static let longWaitReportInterval = 10 * UInt64(NSEC_PER_SEC)
    private var longWaitCount = 0
    private var longestWait = UInt64(0)
    private var lastLongWaitReport = UInt64(0)
    private static let silentHolderThreshold = 5 * UInt64(NSEC_PER_SEC)
    // A check this long after the previous one means the process was stopped (as in a debugger),
    // not that wakeups were lost.
    private static let lateCheckThreshold = 2 * UInt64(NSEC_PER_SEC)
    // When checkHealth() last ran, or 0 if the health timer stopped since. Guarded by the mutex.
    private var lastHealthCheck = UInt64(0)

    // The shared instance used by sessions with mutation queues of their own.
    static let shared: ExecutionPermits = {
        let permits = ExecutionPermits(capacity: configuredCapacity,
                                       visibleWeight: iTermAdvancedSettingsModel.visibleSessionExecutionWeight(),
                                       checksHealthPeriodically: true)
        iTermRegisterDebugLogStateProvider("Execution permits") { [weak permits] in
            return permits?.stateDescription ?? "(none)"
        }
        return permits
    }()

    // Whether sessions take permits at all. Read once: an advanced setting turns the limit off, in
    // case it causes trouble, and needs a restart.
    @objc static let limitEnabled = iTermAdvancedSettingsModel.limitSessionsProcessingOutput()

    // The permits a new token executor takes, if any. Only sessions with queues of their own take
    // them: sessions on the shared queue already run one at a time.
    static func forNewExecutor(ownsQueue: Bool, limitEnabled: Bool = ExecutionPermits.limitEnabled) -> ExecutionPermits? {
        return ownsQueue && limitEnabled ? shared : nil
    }

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

    // Called by the health check, without the mutex held, with a description of a state that is
    // never expected (it means a bug). By default debug builds crash; release builds rely on the
    // repair and the debug log.
    private let onUnexpectedState: (String) -> Void

    static func crashInDebugBuilds(_ message: String) {
#if DEBUG
        it_fatalError(message)
#endif
    }

    init(capacity: Int,
         visibleWeight: Double,
         now: @escaping () -> UInt64 = monotonicNanoseconds,
         checksHealthPeriodically: Bool = false,
         onUnexpectedState: @escaping (String) -> Void = ExecutionPermits.crashInDebugBuilds) {
        _capacity = max(1, capacity)
        self.visibleWeight = max(1, visibleWeight)
        self.now = now
        self.onUnexpectedState = onUnexpectedState
        healthTimer = checksHealthPeriodically ? DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.iterm2.execution-permits-health", qos: .utility)) : nil
        super.init()
        if let healthTimer {
            healthTimer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(500))
            healthTimer.setEventHandler { [weak self] in
                self?.checkHealth()
            }
        }
    }

    deinit {
        if let healthTimer {
            // A dispatch source must not be released while inactive or suspended.
            if !healthTimerRunning {
                healthTimer.resume()
            }
            healthTimer.cancel()
        }
        iTermAtomicInt64Free(waiterCount)
    }

    // Any thread. Raising it hands permits to waiters right away. Lowering it lets holders run
    // until their next checkpoint, and no permit is handed out until fewer than the new capacity
    // are in use.
    var capacity: Int {
        get {
            return mutex.sync { _capacity }
        }
        set {
            wake(mutex.sync {
                _capacity = max(1, newValue)
                while inUse > _capacity && takeIdlePermit() {}
                return handOff().woken
            })
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
        let (acquired, woken) = mutex.sync { () -> (Bool, [Client]) in
            switch client.state {
            case .holding:
                return (true, [])
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
            let result = handOff(caller: client)
            return (result.callerHolds, result.woken)
        }
        wake(woken)
        return acquired
    }

    // The session's queue, while holding a permit. Charges the time run since the last checkpoint
    // or acquire, and returns whether the holder should give up its permit: there are more holders
    // than permits, or a waiter that isn't paused has run no more than it.
    func checkpoint(_ client: Client, ran: TimeInterval) -> Bool {
        return mutex.sync {
            guard client.state == .holding else {
                return false
            }
            it_assert(!client.isParked, "Checkpoint with a parked permit")
            iTermAtomicInt64Set(client.lastHeardFrom, Int64(now()))
            startHealthTimerIfNeeded()
            charge(client, ran: ran)
            // Over the cap (it was lowered), idle permits go first, so only a running holder that is
            // really over the cap stops.
            while inUse > _capacity && takeIdlePermit() {}
            if inUse > _capacity {
                return true
            }
            return waiters.contains { !$0.isPaused() && $0.virtualTime <= client.virtualTime }
        }
    }

    // The session's queue, while holding a permit. Charges the time run since the last checkpoint
    // or acquire and gives up the permit. With more work, the client waits in line again, and
    // returns true if it was first in line and so keeps the permit. It isn't woken then: the
    // caller carries on.
    @discardableResult
    func release(_ client: Client, ran: TimeInterval, hasMoreWork: Bool) -> Bool {
        let (keeps, woken) = mutex.sync { () -> (Bool, [Client]) in
            guard client.state == .holding else {
                return (false, [])
            }
            it_assert(!client.isParked, "Releasing a parked permit")
            charge(client, ran: ran)
            unhold(client)
            guard hasMoreWork else {
                client.state = .idle
                return (false, handOff().woken)
            }
            enqueue(client)
            let result = handOff(caller: client)
            return (result.callerHolds, result.woken)
        }
        wake(woken)
        return keeps
    }

    // The session's queue. For a session that won't execute tokens for now (it has none, it is
    // paused for long, or it is in copy mode). Charges the time run if it held a permit, gives up
    // the permit or its place in line, and leaves it idle, so it rejoins at the floor later. This
    // also gives up a permit that was handed to it but not yet taken up.
    func relinquish(_ client: Client, ran: TimeInterval) {
        wake(mutex.sync { () -> [Client] in
            switch client.state {
            case .holding:
                it_assert(!client.isParked, "Relinquishing a parked permit")
                charge(client, ran: ran)
                unhold(client)
                client.state = .idle
                return handOff().woken
            case .waiting:
                raiseFloor()
                waiters.removeAll { $0 === client }
                client.state = .idle
                return []
            case .idle, .removed:
                return []
            }
        })
    }

    // Any thread. For a session that is going away. Gives up its permit or its place in line.
    func remove(_ client: Client) {
        wake(mutex.sync { () -> [Client] in
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
            return handOff().woken
        })
    }

    // MARK: - Private

    // Without the mutex. Wakes clients that were handed permits. One that is gone gives its permit
    // up, so it goes to someone else.
    private func wake(_ clients: [Client]) {
        var pending = clients
        while !pending.isEmpty {
            let client = pending.removeFirst()
            if client.wake() {
                continue
            }
            pending += mutex.sync { () -> [Client] in
                guard client.state == .holding else {
                    // Removed meanwhile, which gave up the permit.
                    return []
                }
                unhold(client)
                client.state = .removed
                return handOff().woken
            }
        }
    }

    // MARK: - Private, with the mutex held

    private func hold(_ client: Client) {
        mutex.assertOwned()
        it_assert(inUse < _capacity, "Holding more permits than there are")
        it_assert(client.state == .idle || client.state == .waiting, "Holding a permit in state \(client.state)")
        it_assert(!holders.contains { $0 === client }, "Client already holds a permit")
        it_assert(!waiters.contains { $0 === client }, "A client must leave the line before holding a permit")
        it_assert(!client.isParked, "Holding a permit while parked")
        if client.state == .waiting {
            let waited = now() &- client.waitingSince
            if waited > Self.longWaitThreshold {
                longWaitCount += 1
                longestWait = max(longestWait, waited)
            }
        }
        client.state = .holding
        client.weight = iTermAtomicInt64Get(client.visible) != 0 ? visibleWeight : 1
        iTermAtomicInt64Set(client.lastHeardFrom, Int64(now()))
        holders.append(client)
        startHealthTimerIfNeeded()
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
        client.waitingSince = now()
        client.waitingSequence = nextWaitingSequence
        nextWaitingSequence += 1
        waiters.append(client)
        startHealthTimerIfNeeded()
    }

    private func charge(_ client: Client, ran: TimeInterval) {
        mutex.assertOwned()
        it_assert(client.state == .holding, "Charging a client in state \(client.state)")
        client.virtualTime = max(client.virtualTime, floor) + max(0, ran) / client.weight
        raiseFloor()
    }

    private func raiseFloor() {
        mutex.assertOwned()
        let lowest = min(holders.lazy.filter { !$0.isParked }.map(\.virtualTime).min() ?? .infinity,
                         waiters.lazy.map(\.virtualTime).min() ?? .infinity)
        if lowest.isFinite {
            floor = max(floor, lowest)
        }
    }

    // Hands free permits to the waiters with the lowest virtual times, skipping paused ones.
    // Returns the clients that got one, which the caller must wake after releasing the mutex.
    // `caller`, a waiter asking for a permit itself, counts as able to run. It isn't among those
    // to wake if it gets a permit; instead, callerHolds is true.
    private func handOff(caller: Client? = nil) -> (callerHolds: Bool, woken: [Client]) {
        mutex.assertOwned()
        var callerHolds = false
        var woken = [Client]()
        while true {
            var best: Client?
            for waiter in waiters where waiter === caller || !waiter.isPaused() {
                if let current = best,
                   (current.virtualTime, current.waitingSequence) <= (waiter.virtualTime, waiter.waitingSequence) {
                    continue
                }
                best = waiter
            }
            guard let best else {
                break
            }
            // Over the cap (it was lowered), it may take more than one idle permit to make room.
            while inUse >= _capacity && takeIdlePermit() {}
            guard inUse < _capacity else {
                break
            }
            waiters.removeAll { $0 === best }
            hold(best)
            if best === caller {
                callerHolds = true
            } else {
                woken.append(best)
            }
        }
        return (callerHolds, woken)
    }

    // The session's queue, while holding a running permit, when it has nothing to execute.
    // Doesn't take the lock unless someone is in line. Returns true if the permit was parked: it
    // stays idle until resume(), which must be called before running again, but another session
    // may take it at any time, even before this returns. Returns false if the permit was given up
    // here (to a waiter that can run, or taken by one), in which case `ran` has been charged.
    func park(_ client: Client, uncharged ran: TimeInterval) -> Bool {
        iTermAtomicInt64Set(client.unchargedNanoseconds, Int64(max(0, ran) * 1e9))
        iTermAtomicInt64Set(client.parking, Parking.idle.rawValue)
        if iTermAtomicInt64Get(waiterCount) == 0 {
            return true
        }
        // Someone is in line. Unless they took the permit already, decide under the lock.
        guard iTermAtomicInt64CompareAndSwap(client.parking, Parking.idle.rawValue, Parking.running.rawValue) else {
            iTermAtomicInt64Set(client.parking, Parking.running.rawValue)
            return false
        }
        let (parked, woken) = mutex.sync { () -> (Bool, [Client]) in
            it_assert(client.state == .holding, "Parking a permit in state \(client.state)")
            guard waiters.contains(where: { !$0.isPaused() }) else {
                // Only paused waiters, which can't use it. Park after all: one takes the idle
                // permit when it asks again after its pause.
                iTermAtomicInt64Set(client.parking, Parking.idle.rawValue)
                return (true, [])
            }
            charge(client, ran: ran)
            unhold(client)
            client.state = .idle
            return (false, handOff().woken)
        }
        wake(woken)
        return parked
    }

    // The session's queue, for a client that parked its permit. Doesn't take the lock. Returns
    // true if the permit is still the client's, now running. Returns false if another session took
    // it (charging the time run); the client must acquire a permit again.
    func resume(_ client: Client) -> Bool {
        if iTermAtomicInt64CompareAndSwap(client.parking, Parking.idle.rawValue, Parking.running.rawValue) {
            iTermAtomicInt64Set(client.lastHeardFrom, Int64(now()))
            return true
        }
        it_assert(iTermAtomicInt64Get(client.parking) == Parking.taken.rawValue, "Resuming a permit that isn't parked")
        iTermAtomicInt64Set(client.parking, Parking.running.rawValue)
        return false
    }

    // Takes the permit of an idle holder, if there is one, charging it for the time it ran. It
    // must ask for a permit again.
    private func takeIdlePermit() -> Bool {
        mutex.assertOwned()
        for holder in holders where iTermAtomicInt64CompareAndSwap(holder.parking, Parking.idle.rawValue, Parking.taken.rawValue) {
            charge(holder, ran: TimeInterval(iTermAtomicInt64Get(holder.unchargedNanoseconds)) / 1e9)
            unhold(holder)
            holder.state = .idle
            return true
        }
        return false
    }

    // MARK: - Health check

    // Any thread. A safety net for lost wakeups, which would otherwise leave a session frozen with
    // no sign of why. Hands free and idle permits to waiters that can run and have been in line for
    // over a second, and wakes running holders that haven't been heard from for five seconds (one
    // that is really running reaches a checkpoint every slice). Waking a session that didn't need it
    // only costs an extra execute(). Either repair is logged, since it suggests a bug. A silent
    // holder is also reported to onUnexpectedState (debug builds crash), except in two cases that
    // aren't bugs: a holder paused for a join is skipped (it reaches no checkpoint until the join
    // ends, which schedules it), and a check that ran late means the process was stopped, so every
    // holder looks silent. A waiter can look stranded without a bug too: if its queue is busy when
    // its pause ends, its next execute() takes a while to ask for the free permit.
    func checkHealth() {
        // Logged after the mutex is released: the debug log's state provider takes the mutex while
        // holding the debug log's lock.
        var messages = [String]()
        var unexpected = [String]()
        let woken = mutex.sync { () -> [Client] in
            let now = self.now()
            let ranLate = lastHealthCheck != 0 && now &- lastHealthCheck > Self.lateCheckThreshold
            lastHealthCheck = now
            var woken = [Client]()
            if longWaitCount > 0 && now &- lastLongWaitReport > Self.longWaitReportInterval {
                messages.append("Execution permits: \(longWaitCount) waits of over a second recently, the longest \(Double(longestWait) / 1e9)s. \(stateDescriptionLocked)")
                longWaitCount = 0
                longestWait = 0
                lastLongWaitReport = now
            }
            let stranded = waiters.filter { !$0.isPaused() && now &- $0.waitingSince > Self.strandedWaiterThreshold }
            if !stranded.isEmpty {
                let handed = handOff().woken
                if !handed.isEmpty {
                    messages.append("Execution permits: handed \(handed.count) permits to waiters, \(stranded.count) of which had waited over a second. A wakeup may have been lost. \(stateDescriptionLocked)")
                }
                woken += handed
            }
            for holder in holders where !holder.isParked && !holder.isPaused() {
                let last = UInt64(iTermAtomicInt64Get(holder.lastHeardFrom))
                if now &- last > Self.silentHolderThreshold {
                    if ranLate {
                        messages.append("Execution permits: woke a holder not heard from for \(Double(now &- last) / 1e9)s, after a health check that ran late (the process was probably stopped). \(stateDescriptionLocked)")
                    } else {
                        let message = "Execution permits: woke a holder not heard from for \(Double(now &- last) / 1e9)s. A wakeup may have been lost. \(stateDescriptionLocked)"
                        messages.append(message)
                        unexpected.append(message)
                    }
                    woken.append(holder)
                }
                if ranLate || now &- last > Self.silentHolderThreshold {
                    // Start over, so the next check judges only time after this one.
                    iTermAtomicInt64Set(holder.lastHeardFrom, Int64(now))
                }
            }
            if let healthTimer, healthTimerRunning, waiters.isEmpty, longWaitCount == 0,
               !holders.contains(where: { !$0.isParked }) {
                // Nothing that could be stuck. Parked holders have nothing to run.
                healthTimer.suspend()
                healthTimerRunning = false
                // The next check after the timer restarts isn't late.
                lastHealthCheck = 0
            }
            return woken
        }
        for message in messages {
            RLog("\(message)")
        }
        // After logging, so the debug log has the message even if this crashes.
        for message in unexpected {
            onUnexpectedState(message)
        }
        wake(woken)
    }

    private func startHealthTimerIfNeeded() {
        mutex.assertOwned()
        guard let healthTimer, !healthTimerRunning else {
            return
        }
        healthTimerRunning = true
        healthTimer.resume()
    }

    // Any thread. For debug logs. Takes the mutex, so it must not be called while logging under
    // the mutex (nothing logs under it).
    var stateDescription: String {
        return mutex.sync {
            let now = self.now()
            let clients = (holders + waiters).map { "  " + $0.description(now: now) }
            return ([stateDescriptionLocked] + clients).joined(separator: "\n")
        }
    }

    // With the mutex held.
    private var stateDescriptionLocked: String {
        return "capacity=\(_capacity) holders=\(holders.count) waiters=\(waiters.count) floor=\(floor)"
    }

    // MARK: - Testing

    var longWaitsForTesting: (Int, TimeInterval) {
        return mutex.sync { (longWaitCount, TimeInterval(longestWait) / 1e9) }
    }

    var idleHolderCountForTesting: Int {
        return mutex.sync { holders.filter(\.isParked).count }
    }

    var runningCountForTesting: Int {
        return mutex.sync { holders.filter { !$0.isParked }.count }
    }

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
