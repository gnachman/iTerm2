//
//  CompanionPriorityOutbox.swift
//  iTerm2
//
//  The bridge's single outbound queue, with three priority lanes drained in order:
//
//    1. control  -- reliable, prompt, low-volume: replies, events, input acks,
//                   streamConfig. Never dropped or reordered.
//    2. media    -- video access units. Never dropped or reordered (HEVC P-frames
//                   are differential, so a gap corrupts decode until the next
//                   keyframe); upstream pacing keeps this lane shallow.
//    3. coalescing -- latest-wins state (e.g. selectionRange): only the newest
//                   value per key matters, so a new one REPLACES the pending one.
//
//  Coalescing is the fix for a priority inversion: a high-frequency state feed
//  (selectionRange on every drag move) used to ride the control lane and, because
//  control drains ahead of media unboundedly, starved the very media frame that
//  showed the selection -- so the selection appeared frozen for seconds while the
//  flood drained. As a latest-wins lane it is bounded to one entry per key (cannot
//  build a backlog) and sits BELOW media, so the video (the source of truth) is
//  never starved by handle-position feedback. Because streamConfig is control and
//  its keyframe is media, the config still precedes the keyframe it describes.
//
//  One producer side may enqueue from any thread (the encoder callback runs off
//  the main actor); a single consumer awaits next(). Generic over the control
//  payload so it can be tested without the envelope type.
//

import Foundation

final class CompanionPriorityOutbox<Control>: @unchecked Sendable {
    enum Item {
        case control(Control)
        case media(Data)
        case finished
    }

    private let lock = NSLock()
    private var control: [Control] = []
    private var media: [Data] = []
    private var coalescing: [String: Control] = [:]
    private var coalescingOrder: [String] = []
    private var finished = false
    private var waiter: CheckedContinuation<Void, Never>?

    /// Enqueue a control frame (highest priority). Thread-safe.
    func enqueueControl(_ value: Control) { append { self.control.append(value) } }

    /// Enqueue a media frame (drained after control, before coalescing). Thread-safe.
    func enqueueMedia(_ data: Data) { append { self.media.append(data) } }

    /// Enqueue a latest-wins state frame: a new value REPLACES any pending one with
    /// the same key, so a flood collapses to the newest and cannot starve media.
    func enqueueCoalescingControl(_ value: Control, key: String) {
        append {
            if self.coalescing[key] == nil { self.coalescingOrder.append(key) }
            self.coalescing[key] = value
        }
    }

    /// Signal end of stream; once the queues drain, next() returns .finished.
    func finish() { append { self.finished = true } }

    private func append(_ mutate: () -> Void) {
        lock.lock()
        mutate()
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume()
    }

    /// Await the next item in priority order. Returns .finished after every lane is
    /// empty and finish() was called.
    func next() async -> Item {
        while true {
            if let item = dequeue() {
                return item
            }
            await park()
        }
    }

    private func dequeue() -> Item? {
        lock.lock()
        defer { lock.unlock() }
        if !control.isEmpty { return .control(control.removeFirst()) }
        if !media.isEmpty { return .media(media.removeFirst()) }
        if !coalescingOrder.isEmpty {
            let key = coalescingOrder.removeFirst()
            if let value = coalescing.removeValue(forKey: key) { return .control(value) }
        }
        if finished { return .finished }
        return nil
    }

    private var hasWork: Bool {
        !control.isEmpty || !media.isEmpty || !coalescingOrder.isEmpty || finished
    }

    private func park() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            // Re-check under the lock so an enqueue between dequeue() returning nil
            // and here is not a lost wakeup.
            if hasWork {
                lock.unlock()
                continuation.resume()
                return
            }
            waiter = continuation
            lock.unlock()
        }
    }
}
