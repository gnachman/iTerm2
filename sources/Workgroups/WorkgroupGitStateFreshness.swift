//
//  WorkgroupGitStateFreshness.swift
//  iTerm2SharedARC
//

import Foundation

// Tracks whether a workgroup's git poller state is current enough to
// launch a diff. Launching from stale state runs difftool on a tree that
// has since changed, which shows nothing and exits.
//
// It is fed facts about the poller rather than holding one, so it can be
// tested on its own. A "context" is what a poll is for: its directory,
// base, and worker.
struct WorkgroupGitStateFreshness {
    // How long after it arrives state may be trusted to launch a diff. A
    // little more than the poller's cadence, which is how often it polls
    // while the leader is working. Measured from arrival, not from when the
    // computation started, so slow polls aren't stale on arrival.
    static let freshAge: TimeInterval = 3

    // The poller's deliveryCount when it last called back.
    private var lastDeliveryCount: UInt = 0
    // When the latest delivery arrived and what it was for. nil when it
    // timed out: the worker replays older cached state then.
    private var deliveredAt: TimeInterval?
    private var deliveredContext: String?
    // Set by a request for fresh state: only a delivery from a poll
    // numbered this or higher reflects the tree as of the request. Applies
    // only while the context is the one the request was made in, because a
    // context change starts a poll that reads the tree after it.
    private var required: (pollNumber: UInt, context: String)?

    // Notes that the poller called back. Not every callback is a
    // delivery: disabling, changing workers, and retrying after a timeout
    // call back with no poll behind them, and deliveryCount tells them
    // apart. deliveredPollNumber is the number of the poll whose result
    // was delivered last.
    mutating func pollerDidUpdate(deliveryCount: UInt,
                                  deliveredPollNumber: UInt,
                                  timedOut: Bool,
                                  context: String,
                                  now: TimeInterval) {
        if deliveryCount != lastDeliveryCount {
            lastDeliveryCount = deliveryCount
            if timedOut {
                deliveredAt = nil
                deliveredContext = nil
            } else {
                deliveredAt = now
                deliveredContext = context
            }
        }
        if let required, required.context != context || deliveredPollNumber >= required.pollNumber {
            self.required = nil
        }
    }

    // Notes a request for state that reflects the tree as of now.
    // startedPollCount is the number of the latest poll to start. The
    // caller must then poll.
    //
    // Any poll that has already started may have read the tree before
    // whatever prompted the request, even one started by a context change:
    // in a large repository it can still be running long after the change.
    // The next poll to start can't have, however many polls are dropped
    // along the way.
    mutating func freshStateRequested(startedPollCount: UInt, context: String) {
        required = (startedPollCount + 1, context)
    }

    // A delivery is on its way that will replace the current one, which
    // predates a request for fresh state. Neither launch nor show the
    // waiting overlay from it: the next delivery decides.
    func isSuperseded(deliveredPollNumber: UInt, context: String) -> Bool {
        guard let required else {
            return false
        }
        return required.context == context && deliveredPollNumber < required.pollNumber
    }

    // The latest delivery didn't time out, is for the current context, and
    // isn't superseded. The poller runs one poll at a time, so a delivered
    // result is from its latest.
    func isFromLatestPoll(deliveredPollNumber: UInt, hasState: Bool, context: String) -> Bool {
        guard hasState, deliveredAt != nil, deliveredContext == context else {
            return false
        }
        return !isSuperseded(deliveredPollNumber: deliveredPollNumber, context: context)
    }

    // isFromLatestPoll, and it arrived recently.
    func isFresh(deliveredPollNumber: UInt, hasState: Bool, context: String, now: TimeInterval) -> Bool {
        guard isFromLatestPoll(deliveredPollNumber: deliveredPollNumber, hasState: hasState, context: context),
              let deliveredAt else {
            return false
        }
        return now - deliveredAt < Self.freshAge
    }
}
