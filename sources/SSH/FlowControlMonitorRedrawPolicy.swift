//
//  FlowControlMonitorRedrawPolicy.swift
//  iTerm2SharedARC
//
//  Decides when the flow control monitor's window redraws. Drawing its charts ten times a
//  second cost an idle iTerm2 a fifth of a core, though nothing on them changed but the time
//  axis. It redraws at once when what it shows changed, at most once a second otherwise, so
//  the charts still scroll, and never while the window cannot be seen.
//

import Foundation

struct FlowControlMonitorRedrawPolicy {
    /// What the window shows that changes when something happens, without the time.
    struct Activity: Equatable {
        struct ConnectionActivity: Equatable {
            var guid: String
            var reasonOff: String?
            var flowVersion: Int
            var window: Double?
            var granted: Int?
            var arrived: Int?
            var consumed: Int?
            var statistics: FramerFlowController.Statistics?
            var eventCount: Int?
            var lastRoundTrip: TimeInterval?
        }

        var sessionName: String?
        var connections: [ConnectionActivity]
        var received: Double?

        init(sessionName: String?,
             connections: [FlowControlMonitor.Connection],
             received: [FlowControlHistory.Point]) {
            self.sessionName = sessionName
            self.connections = connections.map { connection in
                let snapshot = connection.history.samples.last?.snapshot
                return ConnectionActivity(guid: connection.guid,
                                          reasonOff: connection.reasonOff,
                                          flowVersion: connection.flowVersion,
                                          window: snapshot?.window,
                                          granted: snapshot?.granted,
                                          arrived: snapshot?.arrived,
                                          consumed: snapshot?.consumed,
                                          statistics: snapshot?.statistics,
                                          eventCount: snapshot?.events.count,
                                          lastRoundTrip: connection.roundTrips.last?.time)
            }
            self.received = received.last?.value
        }
    }

    /// How often to redraw while nothing changes.
    var idleInterval: TimeInterval = 1
    private var lastActivity: Activity?
    private var lastRedraw = -TimeInterval.infinity

    /// Whether to redraw now. Call on each sample; a redraw it allows is assumed to happen.
    mutating func shouldRedraw(_ activity: Activity, visible: Bool, now: TimeInterval) -> Bool {
        guard visible else {
            return false
        }
        guard activity != lastActivity || now - lastRedraw >= idleInterval else {
            return false
        }
        lastActivity = activity
        lastRedraw = now
        return true
    }

    /// The window became visible again, or something else makes the next sample redraw.
    mutating func invalidate() {
        lastActivity = nil
    }
}
