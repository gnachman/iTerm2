//
//  CompanionPriorityOutbox.swift
//  iTerm2
//
//  The bridge's single outbound queue, draining CONTROL frames ahead of MEDIA so
//  a keystroke, selection, or reply never waits behind a backlog of video frames.
//
//  Media is never dropped or reordered here: HEVC P-frames are differential, so a
//  gap corrupts decode until the next keyframe. Coalescing happens upstream (the
//  pacer collapses a burst of changes into one frame; the in-flight limiter stops
//  encoding when the receiver falls behind), which keeps the media queue shallow.
//  This queue only reorders control ahead of media. Because a streamConfig is a
//  control frame and its keyframe is a media frame, the config still precedes the
//  keyframe it describes.
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
    private var finished = false
    private var waiter: CheckedContinuation<Void, Never>?

    /// Enqueue a control frame (high priority). Thread-safe.
    func enqueueControl(_ value: Control) { append { self.control.append(value) } }

    /// Enqueue a media frame (drained only when no control is pending). Thread-safe.
    func enqueueMedia(_ data: Data) { append { self.media.append(data) } }

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

    /// Await the next item, control before media. Returns .finished after the
    /// queues are empty and finish() was called.
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
        if finished { return .finished }
        return nil
    }

    private func park() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            // Re-check under the lock so an enqueue between dequeue() returning nil
            // and here is not a lost wakeup.
            if !control.isEmpty || !media.isEmpty || finished {
                lock.unlock()
                continuation.resume()
                return
            }
            waiter = continuation
            lock.unlock()
        }
    }
}
