//
//  FramerFlowLedger.swift
//  iTerm2SharedARC
//
//  Flow control measures delay when a frame arrives and returns credit once the session's
//  token executor has run it. The parser and executor run on the session's own threads and the
//  conductor on the main thread, so they share this ledger. The threads append, and the
//  conductor takes what they appended on its next tick. One record per frame, with no hop
//  to the main thread each time; only the first record after the conductor has caught up
//  wakes it.
//
//  With nested SSH Integration each framer runs flow control on its own reads, so the ledger
//  keeps each depth's records apart, for that depth's conductor.
//

import Foundation

@objc(iTermFramerFlowLedger)
final class FramerFlowLedger: NSObject {
    enum Event: Equatable {
        /// A controlled frame the framer sent at `sendMilliseconds` reached the parser, with its
        /// flow flags. `flow` is 0 for the leader, a pane's pid, or `it2Flow`. For an inner
        /// framer's frame, `carrierMilliseconds` is when the framer around it sent the frame
        /// that carried its first line, on that framer's clock; 0 at the outermost depth.
        case arrived(time: TimeInterval, flow: Int32, sendMilliseconds: Int64, bytes: Int, flags: Int32,
                     carrierMilliseconds: Int64 = 0)
        /// The executor ran a controlled frame.
        case executed(time: TimeInterval, bytes: Int)
    }

    /// One depth's records and listener.
    private struct Depth {
        var active = false
        var events = [Event]()
        var wakePending = false
        var onActivity: (@Sendable () -> Void)?
        /// Who listens. Conductors at one depth can follow each other, as when an inner ssh
        /// ends and another starts; the one that ended must not unregister its successor.
        weak var owner: AnyObject?
    }

    private let lock = NSLock()
    private var depths = [Int32: Depth]()
    private let clock: () -> TimeInterval

    init(clock: @escaping () -> TimeInterval = Conductor.monotonicNow) {
        self.clock = clock
    }

    @objc override convenience init() {
        self.init(clock: Conductor.monotonicNow)
    }

    /// Whether the outermost conductor is listening.
    @objc var isActive: Bool {
        return isActive(depth: 0)
    }

    /// Whether the conductor at `depth` is listening. Frames are not recorded otherwise, so a
    /// session without flow control pays only for checking this.
    @objc(isActiveForDepth:)
    func isActive(depth: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return depths[depth]?.active ?? false
    }

    /// Called on the main thread. `onActivity` runs on the main thread when a record arrives
    /// for `depth` and none was waiting.
    func activate(depth: Int32 = 0, owner: AnyObject? = nil, onActivity: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        depths[depth] = Depth(active: true, onActivity: onActivity, owner: owner)
    }

    /// With an `owner`, only if it is still the one listening at `depth`.
    func deactivate(depth: Int32 = 0, owner: AnyObject? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let owner, depths[depth]?.owner !== owner {
            return
        }
        depths[depth] = nil
    }

    /// The flow code of it2 data in `.arrived`.
    @objc static let it2Flow: Int32 = -1

    /// Called on the thread that reads the session's output.
    @objc(frameDidArriveWithLength:sendMilliseconds:flags:flow:)
    func frameDidArrive(bytes: Int, sendMilliseconds: Int64, flags: Int32, flow: Int32 = 0) {
        frameDidArrive(bytes: bytes, sendMilliseconds: sendMilliseconds, flags: flags, flow: flow,
                       depth: 0, carrierMilliseconds: 0)
    }

    /// Called on the thread that reads the session's output.
    @objc(frameDidArriveWithLength:sendMilliseconds:flags:flow:depth:carrierMilliseconds:)
    func frameDidArrive(bytes: Int, sendMilliseconds: Int64, flags: Int32, flow: Int32,
                        depth: Int32, carrierMilliseconds: Int64) {
        record(.arrived(time: clock(), flow: flow, sendMilliseconds: sendMilliseconds, bytes: bytes,
                        flags: flags, carrierMilliseconds: carrierMilliseconds),
               depth: depth)
    }

    /// Called on the mutation thread once the frame's contents have executed.
    @objc(frameDidExecuteWithLength:)
    func frameDidExecute(bytes: Int) {
        frameDidExecute(bytes: bytes, depth: 0)
    }

    /// Called on the mutation thread once the frame's contents have executed.
    @objc(frameDidExecuteWithLength:depth:)
    func frameDidExecute(bytes: Int, depth: Int32) {
        record(.executed(time: clock(), bytes: bytes), depth: depth)
    }

    /// Called on the main thread.
    func takeEvents(depth: Int32 = 0) -> [Event] {
        lock.lock()
        defer { lock.unlock() }
        guard var state = depths[depth] else {
            return []
        }
        let result = state.events
        state.events.removeAll()
        state.wakePending = false
        depths[depth] = state
        return result
    }

    private func record(_ event: Event, depth: Int32) {
        lock.lock()
        guard var state = depths[depth], state.active else {
            lock.unlock()
            return
        }
        state.events.append(event)
        let wake = state.wakePending ? nil : state.onActivity
        state.wakePending = true
        depths[depth] = state
        lock.unlock()
        if let wake {
            DispatchQueue.main.async(execute: wake)
        }
    }
}
