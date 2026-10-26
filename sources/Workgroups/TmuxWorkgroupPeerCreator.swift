//
//  TmuxWorkgroupPeerCreator.swift
//  iTerm2SharedARC
//
//  Runs the workgroup state machines over a tmux connection: TmuxWorkgroupLockDriver acquires the
//  session's workgroup lock (TmuxWorkgroupCommands.LockAcquisition), and TmuxWorkgroupPeerCreator
//  holds it while creating an instance's missing peers (TmuxWorkgroupPeerCreation), then releases
//  it. Each step is one command or one atomic command list, so a client that vanishes between
//  steps leaves only a stale lock and missing peers, both of which the next creator handles.
//

import Foundation

/// Lets one lock driver at a time work on a tmux connection. The lock's value names the client,
/// not the acquisition, so a second driver of the same client would find its own value and take
/// the lock as its own, and whichever finished first would release it while the other was still
/// working. Drivers wait here, in the order they started, until the one ahead of them lets go.
///
/// While the driver ahead waits on another client's lock, the ones behind it wait on that client
/// too, and say so, so that the user is told and can take the lock over or stop waiting.
final class TmuxWorkgroupLocalLockQueue {
    private static let queues = NSMapTable<TmuxGateway, TmuxWorkgroupLocalLockQueue>.weakToStrongObjects()

    static func queue(for gateway: TmuxGateway) -> TmuxWorkgroupLocalLockQueue {
        if let queue = queues.object(forKey: gateway) {
            return queue
        }
        let queue = TmuxWorkgroupLocalLockQueue()
        queues.setObject(queue, forKey: gateway)
        return queue
    }

    private struct Entry {
        var id: ObjectIdentifier
        weak var driver: TmuxWorkgroupLockDriver?
        var start: () -> Void
    }

    private var holder: Entry?
    private var waiting = [Entry]()
    /// The other client the holder waits on, if it does.
    private(set) var holderWaitsOn: TmuxWorkgroupCommands.ClientIdentity?

    /// Runs `start` now if nobody holds the queue, else once everyone ahead has left.
    func enter(_ driver: TmuxWorkgroupLockDriver, start: @escaping () -> Void) {
        let entry = Entry(id: ObjectIdentifier(driver), driver: driver, start: start)
        guard holder != nil else {
            holder = entry
            start()
            return
        }
        waiting.append(entry)
        if let holderWaitsOn {
            driver.queuedBehindWait(on: holderWaitsOn)
        }
    }

    /// Lets the next one go, or stops waiting. Harmless when `id` is neither.
    func leave(_ id: ObjectIdentifier) {
        waiting.removeAll { $0.id == id }
        guard holder?.id == id else {
            return
        }
        holder = nil
        holderStoppedWaiting()
        guard !waiting.isEmpty else {
            return
        }
        let next = waiting.removeFirst()
        holder = next
        next.start()
    }

    /// The holder waits on another client's lock.
    func holderDidWait(_ driver: TmuxWorkgroupLockDriver, on other: TmuxWorkgroupCommands.ClientIdentity) {
        guard holder?.id == ObjectIdentifier(driver) else {
            return
        }
        holderWaitsOn = other
        for entry in waiting {
            entry.driver?.queuedBehindWait(on: other)
        }
    }

    /// The holder took the lock, was cancelled, or left: those behind it no longer wait on another
    /// client, only on this one.
    func holderStoppedWaiting(_ driver: TmuxWorkgroupLockDriver) {
        guard holder?.id == ObjectIdentifier(driver) else {
            return
        }
        holderStoppedWaiting()
    }

    private func holderStoppedWaiting() {
        guard holderWaitsOn != nil else {
            return
        }
        holderWaitsOn = nil
        for entry in waiting {
            entry.driver?.queuedWaitDidEnd()
        }
    }

    /// The user chose, from a driver waiting here, to take the lock from the other client.
    func forceHolder() {
        holder?.driver?.force()
    }

    func isQueued(_ driver: TmuxWorkgroupLockDriver) -> Bool {
        let id = ObjectIdentifier(driver)
        return waiting.contains { $0.id == id }
    }

    var isIdle: Bool {
        holder == nil && waiting.isEmpty
    }
}

final class TmuxWorkgroupLockDriver {
    typealias Lock = TmuxWorkgroupCommands.LockAcquisition

    private let gatewayProvider: () -> TmuxGateway?
    private var lock: Lock
    private(set) var lastAction: Lock.Action?
    /// Called when the acquisition acquires, waits on a connected holder, or is cancelled. A driver
    /// queued behind another of this client's drivers that waits is told it waits too.
    var onSettled: ((Lock.Action) -> Void)?
    /// Called when a queued driver no longer waits on another client because the one ahead of it
    /// stopped waiting. It still waits its turn here, which is quick.
    var onQueuedWaitEnded: (() -> Void)?
    /// This connection's queue, once started. Left on release, on cancel once nothing it sent is
    /// unanswered, and when this goes away.
    private var localQueue: TmuxWorkgroupLocalLockQueue?
    private var unanswered = 0

    init(gatewayProvider: @escaping () -> TmuxGateway?, sessionID: Int, identity: TmuxWorkgroupCommands.ClientIdentity) {
        self.gatewayProvider = gatewayProvider
        lock = Lock(sessionID: sessionID, identity: identity)
    }

    deinit {
        localQueue?.leave(ObjectIdentifier(self))
    }

    func start() {
        guard localQueue == nil, let gateway = gatewayProvider() else {
            perform(lock.start())
            return
        }
        let queue = TmuxWorkgroupLocalLockQueue.queue(for: gateway)
        localQueue = queue
        queue.enter(self) { [weak self] in
            guard let self else {
                return
            }
            if case .cancelled = self.lock.state {
                // Cancelled while waiting its turn.
                self.leaveLocalQueue()
                return
            }
            self.perform(self.lock.start())
        }
    }

    private func leaveLocalQueue() {
        localQueue?.leave(ObjectIdentifier(self))
        localQueue = nil
    }

    /// The lock option changed or a client detached.
    func wake() {
        perform(lock.wake())
    }

    /// The user chose to take the lock from a holder that is connected but seems stuck. A
    /// driver still queued behind this client's own driver passes it on to that one.
    func force() {
        if let localQueue, localQueue.isQueued(self) {
            localQueue.forceHolder()
            return
        }
        perform(lock.force())
    }

    /// The driver ahead of this one waits on `other`'s lock, so this does too.
    fileprivate func queuedBehindWait(on other: TmuxWorkgroupCommands.ClientIdentity) {
        let action = Lock.Action.wait(holder: other)
        lastAction = action
        onSettled?(action)
    }

    fileprivate func queuedWaitDidEnd() {
        onQueuedWaitEnded?()
    }

    func cancel() {
        perform(lock.cancel())
        leaveIfCancelledAndIdle()
    }

    /// Release the lock if this client still holds it.
    func release(completion: @escaping () -> Void) {
        guard let gateway = gatewayProvider() else {
            leaveLocalQueue()
            completion()
            return
        }
        // The unlock goes out before the next driver's attempt, since the gateway keeps order.
        gateway.sendGuarded(TmuxWorkgroupCommands.unlock(sessionID: lock.sessionID, identity: lock.identity)) { _ in
            completion()
        }
        leaveLocalQueue()
    }

    /// A reply after cancel() may still release a lock this took, so the next driver waits until
    /// that is sent.
    private func leaveIfCancelledAndIdle() {
        if case .cancelled = lock.state, unanswered == 0 {
            leaveLocalQueue()
        }
    }

    private func perform(_ action: Lock.Action?) {
        guard let action else {
            return
        }
        lastAction = action
        guard let gateway = gatewayProvider() else {
            return
        }
        switch action {
        case .send(.tryLock(let command)):
            unanswered += 1
            gateway.send(command) { [weak self] reply in
                guard let self else { return }
                self.unanswered -= 1
                self.perform(self.lock.didTryLock(succeeded: reply != nil))
                self.leaveIfCancelledAndIdle()
            }
        case .send(.snapshot(let commands)):
            unanswered += 1
            gateway.sendList(commands) { [weak self] replies in
                guard let self else { return }
                self.unanswered -= 1
                let holder = replies.first ?? nil
                let clients = replies.count > 1 ? replies[1] : nil
                self.perform(self.lock.didSnapshot(holder: holder ?? "", clients: clients ?? ""))
                self.leaveIfCancelledAndIdle()
            }
        case .send(.evict(let command)):
            unanswered += 1
            gateway.sendGuarded(command) { [weak self] outcome in
                guard let self else { return }
                self.unanswered -= 1
                self.perform(self.lock.didEvict(outcome))
                self.leaveIfCancelledAndIdle()
            }
        case .send(.release(let command)):
            RLog("TmuxWorkgroupLockDriver: took the lock after cancelling; releasing it")
            gateway.sendGuarded(command) { _ in }
        case .wait(let holder):
            localQueue?.holderDidWait(self, on: holder)
            onSettled?(action)
        case .acquired, .cancelled:
            localQueue?.holderStoppedWaiting(self)
            onSettled?(action)
        }
    }
}

final class TmuxWorkgroupPeerCreator {
    enum Step: Equatable {
        case lock
        case snapshot
        case create(position: Int)
        case unlock
    }

    enum Outcome: Equatable {
        case finished(created: [Int: Int], failed: [Int])
        case abandoned
        case cancelled
    }

    /// Called before each step; returning false stops as if this client vanished there. Tests use
    /// it to simulate a crash at each point.
    var willPerform: ((Step) -> Bool)?
    /// Called when a connected client holds the lock. Call wake() when the lock changes or a client
    /// detaches, or force() or cancel() at the user's request.
    var onWaiting: ((TmuxWorkgroupCommands.ClientIdentity) -> Void)?
    /// Called when it stops waiting: it took the lock, or was cancelled.
    var onWaitingEnded: (() -> Void)?
    private(set) var isWaiting = false

    private let gatewayProvider: () -> TmuxGateway?
    private let lockDriver: TmuxWorkgroupLockDriver
    private var creation: TmuxWorkgroupPeerCreation
    private var completion: ((Outcome) -> Void)?

    init(gatewayProvider: @escaping () -> TmuxGateway?,
         sessionID: Int,
         instanceID: String,
         identity: TmuxWorkgroupCommands.ClientIdentity,
         scriptsByPosition: [Int: String]) {
        self.gatewayProvider = gatewayProvider
        lockDriver = TmuxWorkgroupLockDriver(gatewayProvider: gatewayProvider, sessionID: sessionID, identity: identity)
        creation = TmuxWorkgroupPeerCreation(sessionID: sessionID, instanceID: instanceID,
                                             scriptsByPosition: scriptsByPosition)
    }

    func run(completion: @escaping (Outcome) -> Void) {
        self.completion = completion
        guard proceed(to: .lock) else {
            return
        }
        lockDriver.onSettled = { [weak self] action in
            guard let self else { return }
            switch action {
            case .acquired:
                self.stopWaiting()
                self.perform(self.creation.start())
            case .wait(let holder):
                self.isWaiting = true
                self.onWaiting?(holder)
            case .cancelled:
                self.stopWaiting()
                self.finish(.cancelled)
            case .send:
                break
            }
        }
        lockDriver.onQueuedWaitEnded = { [weak self] in
            self?.stopWaiting()
        }
        lockDriver.start()
    }

    func wake() {
        lockDriver.wake()
    }

    func force() {
        lockDriver.force()
    }

    func cancel() {
        lockDriver.cancel()
    }

    private func stopWaiting() {
        guard isWaiting else {
            return
        }
        isWaiting = false
        onWaitingEnded?()
    }

    private func proceed(to step: Step) -> Bool {
        return willPerform?(step) ?? true
    }

    private func perform(_ action: TmuxWorkgroupPeerCreation.Action?) {
        guard let action, let gateway = gatewayProvider() else {
            return
        }
        switch action {
        case .snapshot(let commands):
            guard proceed(to: .snapshot) else {
                return
            }
            gateway.sendList(commands) { [weak self] replies in
                guard let self else { return }
                self.perform(self.creation.didSnapshot(replies))
            }
        case let .create(position, commands):
            guard proceed(to: .create(position: position)) else {
                return
            }
            gateway.sendList(commands) { [weak self] replies in
                guard let self else { return }
                self.perform(self.creation.didCreate(reply: replies.first ?? nil))
            }
        case let .finished(created, failed):
            unlockThenFinish(.finished(created: created, failed: failed))
        case .abandoned:
            unlockThenFinish(.abandoned)
        }
    }

    private func unlockThenFinish(_ outcome: Outcome) {
        guard proceed(to: .unlock) else {
            return
        }
        lockDriver.release { [weak self] in
            self?.finish(outcome)
        }
    }

    private func finish(_ outcome: Outcome) {
        let completion = self.completion
        self.completion = nil
        completion?(outcome)
    }
}

/// Holds the session's workgroup lock while repairing an instance (TmuxWorkgroupRepair), or doing
/// other locked work such as TmuxWorkgroupHiddenPaneRelease, then releases it. Like
/// TmuxWorkgroupPeerCreator, each step is one command or one atomic list, so a client that vanishes
/// between steps leaves only a stale lock and whatever is still to repair.
final class TmuxWorkgroupRepairer {
    enum Outcome: Equatable {
        case finished(repairs: Int)
        case abandoned
        case cancelled
    }

    /// Called when a connected client holds the lock. See TmuxWorkgroupPeerCreator.onWaiting.
    var onWaiting: ((TmuxWorkgroupCommands.ClientIdentity) -> Void)?
    /// See TmuxWorkgroupPeerCreator.onWaitingEnded.
    var onWaitingEnded: (() -> Void)?
    private(set) var isWaiting = false

    private let gatewayProvider: () -> TmuxGateway?
    private let lockDriver: TmuxWorkgroupLockDriver
    private var repair: any TmuxWorkgroupLockedRepair
    private var completion: ((Outcome) -> Void)?

    convenience init(gatewayProvider: @escaping () -> TmuxGateway?,
                     sessionID: Int,
                     instanceID: String,
                     identity: TmuxWorkgroupCommands.ClientIdentity) {
        self.init(gatewayProvider: gatewayProvider,
                  sessionID: sessionID,
                  identity: identity,
                  repair: TmuxWorkgroupRepair(sessionID: sessionID, instanceID: instanceID))
    }

    init(gatewayProvider: @escaping () -> TmuxGateway?,
         sessionID: Int,
         identity: TmuxWorkgroupCommands.ClientIdentity,
         repair: any TmuxWorkgroupLockedRepair) {
        self.gatewayProvider = gatewayProvider
        lockDriver = TmuxWorkgroupLockDriver(gatewayProvider: gatewayProvider, sessionID: sessionID, identity: identity)
        self.repair = repair
    }

    func run(completion: @escaping (Outcome) -> Void) {
        self.completion = completion
        lockDriver.onSettled = { [weak self] action in
            guard let self else { return }
            switch action {
            case .acquired:
                self.stopWaiting()
                self.perform(self.repair.start())
            case .wait(let holder):
                self.isWaiting = true
                self.onWaiting?(holder)
            case .cancelled:
                self.stopWaiting()
                self.finish(.cancelled)
            case .send:
                break
            }
        }
        lockDriver.onQueuedWaitEnded = { [weak self] in
            self?.stopWaiting()
        }
        lockDriver.start()
    }

    /// The lock changed or a client detached.
    func wake() {
        lockDriver.wake()
    }

    /// See TmuxWorkgroupPeerCreator.force().
    func force() {
        lockDriver.force()
    }

    func cancel() {
        lockDriver.cancel()
    }

    private func stopWaiting() {
        guard isWaiting else {
            return
        }
        isWaiting = false
        onWaitingEnded?()
    }

    private func perform(_ action: TmuxWorkgroupRepair.Action?) {
        guard let action, let gateway = gatewayProvider() else {
            return
        }
        switch action {
        case .snapshot(let commands):
            gateway.sendList(commands) { [weak self] replies in
                guard let self else { return }
                self.perform(self.repair.didSnapshot(replies))
            }
        case .repair(let commands):
            RLog("TmuxWorkgroupRepairer: \(commands.first ?? "")")
            gateway.sendList(commands) { [weak self] replies in
                guard let self else { return }
                if replies.contains(where: { $0 == nil }) {
                    RLog("TmuxWorkgroupRepairer: a repair failed partway; the next snapshot shows what is left")
                }
                self.perform(self.repair.didRepair())
            }
        case .finished(let repairs):
            unlockThenFinish(.finished(repairs: repairs))
        case .abandoned:
            unlockThenFinish(.abandoned)
        }
    }

    private func unlockThenFinish(_ outcome: Outcome) {
        lockDriver.release { [weak self] in
            self?.finish(outcome)
        }
    }

    private func finish(_ outcome: Outcome) {
        let completion = self.completion
        self.completion = nil
        completion?(outcome)
    }
}
