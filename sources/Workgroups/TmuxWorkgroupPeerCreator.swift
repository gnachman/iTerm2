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

final class TmuxWorkgroupLockDriver {
    typealias Lock = TmuxWorkgroupCommands.LockAcquisition

    private let gatewayProvider: () -> TmuxGateway?
    private var lock: Lock
    private(set) var lastAction: Lock.Action?
    /// Called when the acquisition acquires, waits on a connected holder, or is cancelled.
    var onSettled: ((Lock.Action) -> Void)?

    init(gatewayProvider: @escaping () -> TmuxGateway?, sessionID: Int, identity: TmuxWorkgroupCommands.ClientIdentity) {
        self.gatewayProvider = gatewayProvider
        lock = Lock(sessionID: sessionID, identity: identity)
    }

    func start() {
        perform(lock.start())
    }

    /// The lock option changed or a client detached.
    func wake() {
        perform(lock.wake())
    }

    /// The user chose to take the lock from a holder that is connected but seems stuck.
    func force() {
        perform(lock.force())
    }

    func cancel() {
        perform(lock.cancel())
    }

    /// Release the lock if this client still holds it.
    func release(completion: @escaping () -> Void) {
        guard let gateway = gatewayProvider() else {
            completion()
            return
        }
        gateway.sendGuarded(TmuxWorkgroupCommands.unlock(sessionID: lock.sessionID, identity: lock.identity)) { _ in
            completion()
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
            gateway.send(command) { [weak self] reply in
                guard let self else { return }
                self.perform(self.lock.didTryLock(succeeded: reply != nil))
            }
        case .send(.snapshot(let commands)):
            gateway.sendList(commands) { [weak self] replies in
                guard let self else { return }
                let holder = replies.first ?? nil
                let clients = replies.count > 1 ? replies[1] : nil
                self.perform(self.lock.didSnapshot(holder: holder ?? "", clients: clients ?? ""))
            }
        case .send(.evict(let command)):
            gateway.sendGuarded(command) { [weak self] outcome in
                guard let self else { return }
                self.perform(self.lock.didEvict(outcome))
            }
        case .send(.release(let command)):
            RLog("TmuxWorkgroupLockDriver: took the lock after cancelling; releasing it")
            gateway.sendGuarded(command) { _ in }
        case .wait, .acquired, .cancelled:
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
                self.perform(self.repair.start())
            case .wait(let holder):
                self.onWaiting?(holder)
            case .cancelled:
                self.finish(.cancelled)
            case .send:
                break
            }
        }
        lockDriver.start()
    }

    /// The lock changed or a client detached.
    func wake() {
        lockDriver.wake()
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
