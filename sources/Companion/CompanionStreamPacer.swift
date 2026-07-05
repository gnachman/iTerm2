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
    /// Minimum seconds between emitted frames (1 / fps cap). Not a `let`: the
    /// effective cap is lowered once the rendered resolution is known, so a large
    /// window is emitted less often and total bandwidth stays bounded.
    private(set) var minInterval: TimeInterval

    private var lastEmit: TimeInterval?
    private var dirty = false
    private var keyframeRequested = false

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    /// Retune the frame-rate cap (e.g. after the rendered resolution is known).
    /// The pending change/keyframe state is preserved.
    mutating func setMinInterval(_ interval: TimeInterval) {
        minInterval = interval
    }

    /// Whether an urgent keyframe is pending. The streamer lets a keyframe bypass
    /// the in-flight limiter, so it must be able to tell before calling evaluate()
    /// (which would otherwise consume the dirty flag if the limiter then skipped).
    var isKeyframeRequested: Bool { keyframeRequested }

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
