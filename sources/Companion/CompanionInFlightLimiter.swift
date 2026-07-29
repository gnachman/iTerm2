//
//  CompanionInFlightLimiter.swift
//  iTerm2
//
//  Bounds how far ahead of the receiver the streamer may get, using the phone's
//  streamAck feedback. Without this a slow link buffers frames (in the relay /
//  socket / decode queue) and the live view drifts seconds behind. By comparing
//  the PTS of the last frame we sent against the last PTS the phone acked, we
//  stop emitting once the receiver falls too far behind and resume when an ack
//  catches up -- coalescing to the latest screen instead of piling on stale
//  frames. Pure and clock-free so it is deterministically testable.
//

import Foundation

struct CompanionInFlightLimiter {
    /// Stop emitting once the last sent frame is more than this far (in capture
    /// milliseconds) ahead of the last acked frame.
    let maxLeadMilliseconds: UInt64
    /// Stop emitting once the phone reports a decode queue deeper than this.
    let maxQueueDepth: Int

    private var haveAck = false
    private var lastSentPTS: UInt64 = 0
    private var lastAckedPTS: UInt64 = 0
    private var lastQueueDepth = 0

    init(maxLeadMilliseconds: UInt64 = 500, maxQueueDepth: Int = 4) {
        self.maxLeadMilliseconds = maxLeadMilliseconds
        self.maxQueueDepth = maxQueueDepth
    }

    /// Record that a frame with this PTS was sent.
    mutating func noteSent(ptsMilliseconds: UInt64) {
        lastSentPTS = max(lastSentPTS, ptsMilliseconds)
    }

    /// How far (capture ms) the last sent frame is ahead of the last acked one.
    var leadMilliseconds: UInt64 { lastSentPTS > lastAckedPTS ? lastSentPTS - lastAckedPTS : 0 }

    /// The phone's most recently reported decode queue depth.
    var queueDepth: Int { lastQueueDepth }

    /// Apply a streamAck from the phone.
    mutating func noteAck(ptsMilliseconds: UInt64, queueDepth: Int) {
        haveAck = true
        lastAckedPTS = max(lastAckedPTS, ptsMilliseconds)
        lastQueueDepth = queueDepth
    }

    /// Whether a new (non-keyframe) frame may be emitted now. Before any ack the
    /// stream is allowed to establish; after that it is paced by lead and depth.
    func mayEmit() -> Bool {
        guard haveAck else { return true }
        if lastQueueDepth > maxQueueDepth { return false }
        let lead = lastSentPTS > lastAckedPTS ? lastSentPTS - lastAckedPTS : 0
        return lead <= maxLeadMilliseconds
    }
}
