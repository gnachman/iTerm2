//
//  WorkgroupGitPollPolicy.swift
//  iTerm2SharedARC
//

import Foundation

// Decides whether a workgroup's git poller should run on a given tick.
// A poll with diff stats walks the whole working tree, so polling every
// tick for every workgroup is expensive in a large repository. This polls
// while the leader is working and someone can see the result. Otherwise
// it polls when something suggests the tree changed, plus a slow
// fallback that catches changes made outside the workgroup's terminals.
struct WorkgroupGitPollPolicy {
    struct Inputs {
        // When the last poll started, or nil if there has never been one.
        var lastPoll: Date?
        var now: Date
        // The directory, base ref, or worker differs from the last poll's.
        var contextChanged: Bool
        // Something asked for a poll now, such as a Diff member that is
        // about to launch and needs current state.
        var pollRequested: Bool
        // Whether any member of the workgroup is on screen.
        var anyMemberVisible: Bool
        // A member came on screen since the previous tick.
        var memberBecameVisible: Bool
        // A visible Diff member is waiting for the tree to change before
        // it launches.
        var visibleMemberAwaitsChanges: Bool
        // The leader's status. .unknown when it reports none.
        var leaderState: SessionState
        // When the leader's status last changed to idle or waiting, or nil
        // if it hasn't been seen to make that change.
        var leaderQuietSince: Date?
        // The latest newline any member sent.
        var lastNewline: Date?
        // The last poll timed out.
        var lastPollTimedOut: Bool
    }

    // Git can take a moment to reflect a change, so keep polling for a
    // little while after a newline or the end of a turn.
    static let gracePeriod: TimeInterval = 3

    // Poll at least this often while the workgroup is on screen, to catch
    // changes made outside its terminals, such as edits saved in another
    // app or a commit made in another tab.
    static let fallbackInterval: TimeInterval = 30

    // Poll this often while a visible Diff member waits for changes, so it
    // launches soon after one appears. Polls while the leader works and
    // after newlines come sooner.
    static let awaitingChangesInterval: TimeInterval = 5

    static func shouldPoll(_ inputs: Inputs) -> Bool {
        guard let lastPoll = inputs.lastPoll else {
            return true
        }
        if inputs.contextChanged || inputs.pollRequested {
            return true
        }
        guard inputs.anyMemberVisible else {
            return false
        }
        if inputs.memberBecameVisible {
            return true
        }
        // Polling every tick after a timeout would most likely time out
        // again at full cost. Rely on the slower triggers instead.
        if inputs.visibleMemberAwaitsChanges &&
            !inputs.lastPollTimedOut &&
            inputs.now.timeIntervalSince(lastPoll) >= awaitingChangesInterval {
            return true
        }
        if inputs.now.timeIntervalSince(lastPoll) > fallbackInterval {
            return true
        }
        if let lastNewline = inputs.lastNewline,
           lastNewline > lastPoll.addingTimeInterval(-gracePeriod) {
            return true
        }
        switch inputs.leaderState {
        case .working:
            return !inputs.lastPollTimedOut
        case .idle, .waiting:
            // The leader isn't changing the tree while it's idle or waiting
            // for the user. Take one last look after it stops, to pick up
            // its final edits.
            guard let quietSince = inputs.leaderQuietSince else {
                return false
            }
            return lastPoll < quietSince.addingTimeInterval(gracePeriod)
        case .unknown:
            // With no status to go by, rely on newlines and the fallback.
            return false
        }
    }
}
