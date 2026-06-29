//
//  CompanionStreamPacer.swift
//  iTerm2
//
//  The change-driven emission decision for a live stream, isolated from any
//  rendering or timing so it can be tested deterministically. A timer ticks the
//  pacer at the frame-rate cap; the pacer emits a frame only when the screen has
//  changed since the last frame and the cap allows it, coalescing a burst of
//  changes into one frame. A requested keyframe bypasses the cap (a (re)subscribe
//  or resume must show something immediately).
//

import Foundation

struct CompanionStreamPacer: Equatable {
    /// Minimum seconds between emitted frames (1 / fps cap).
    let minInterval: TimeInterval

    private var lastEmit: TimeInterval?
    private var dirty = false
    private var keyframeRequested = false

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    /// The screen changed since the last frame.
    mutating func noteDirty() {
        dirty = true
    }

    /// The next emitted frame must be a keyframe, and it should be emitted
    /// promptly (bypassing the frame-rate cap).
    mutating func requestKeyframe() {
        keyframeRequested = true
        dirty = true
    }

    struct Emit: Equatable {
        var keyframe: Bool
    }

    /// Decide whether to emit a frame at `now`. Returns the emit decision and
    /// resets the change/keyframe state, or nil to skip this tick.
    mutating func evaluate(now: TimeInterval) -> Emit? {
        guard dirty else { return nil }
        if !keyframeRequested, let last = lastEmit, now - last < minInterval {
            return nil  // frame-rate cap; a non-urgent change waits
        }
        let emit = Emit(keyframe: keyframeRequested)
        lastEmit = now
        dirty = false
        keyframeRequested = false
        return emit
    }
}
