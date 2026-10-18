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

import Foundation

@objc(iTermFramerFlowLedger)
final class FramerFlowLedger: NSObject {
    enum Event: Equatable {
        /// A controlled frame the framer sent at `sendMilliseconds` reached the parser, with its
        /// flow flags. `flow` is 0 for the leader, a pane's pid, or `it2Flow`.
        case arrived(time: TimeInterval, flow: Int32, sendMilliseconds: Int64, bytes: Int, flags: Int32)
        /// The executor ran a controlled frame.
        case executed(time: TimeInterval, bytes: Int)
    }

    private let lock = NSLock()
    private var events = [Event]()
    private var active = false
    private var wakePending = false
    private var onActivity: (@Sendable () -> Void)?
    private let clock: () -> TimeInterval

    init(clock: @escaping () -> TimeInterval = Conductor.monotonicNow) {
        self.clock = clock
    }

    @objc override convenience init() {
        self.init(clock: Conductor.monotonicNow)
    }

    /// Whether a conductor is listening. Frames are not recorded otherwise, so a session
    /// without flow control pays only for checking this.
    @objc var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    /// Called on the main thread. `onActivity` runs on the main thread when a record arrives
    /// and none was waiting.
    func activate(onActivity: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        active = true
        events.removeAll()
        wakePending = false
        self.onActivity = onActivity
    }

    func deactivate() {
        lock.lock()
        defer { lock.unlock() }
        active = false
        events.removeAll()
        onActivity = nil
    }

    /// Called on the thread that reads the session's output.
    /// The flow code of it2 data in `.arrived`.
    @objc static let it2Flow: Int32 = -1

    @objc(frameDidArriveWithLength:sendMilliseconds:flags:flow:)
    func frameDidArrive(bytes: Int, sendMilliseconds: Int64, flags: Int32, flow: Int32 = 0) {
        record(.arrived(time: clock(), flow: flow, sendMilliseconds: sendMilliseconds, bytes: bytes,
                        flags: flags))
    }

    /// Called on the mutation thread once the frame's contents have executed.
    @objc(frameDidExecuteWithLength:)
    func frameDidExecute(bytes: Int) {
        record(.executed(time: clock(), bytes: bytes))
    }

    /// Called on the main thread.
    func takeEvents() -> [Event] {
        lock.lock()
        defer { lock.unlock() }
        let result = events
        events.removeAll()
        wakePending = false
        return result
    }

    private func record(_ event: Event) {
        lock.lock()
        guard active else {
            lock.unlock()
            return
        }
        events.append(event)
        let wake = wakePending ? nil : onActivity
        wakePending = true
        lock.unlock()
        if let wake {
            DispatchQueue.main.async(execute: wake)
        }
    }
}
