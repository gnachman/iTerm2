//
//  FocusOrder.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/26/26.
//

import Foundation

// Records the order in which terminal sessions gain keyboard focus and stamps
// each newly-focused session with a monotonically increasing ordinal
// (PTYSession.lastActivityOrdinal). Open Quickly reads those ordinals to rank
// its "switch to session" rows by recency, so its MRU order is exactly focus
// order.
//
// Call setNeedsUpdate() from anything that can change which session is focused:
// the front window, the selected tab, or a tab's active pane. The stamp is
// coalesced to the next spin of the main loop (via IdempotentOperationJoiner)
// and reads the *settled* focused session, so transient intermediate states
// during a jump (e.g. a cross-window reveal that briefly leaves the destination
// window's previously-active sibling as its current session) are never stamped.
@objc(iTermFocusOrder)
class FocusOrder: NSObject {
    @objc(sharedInstance) static let instance = FocusOrder()

    // Source of the ordinals. Fully private: callers only ask us to stamp the
    // focused session; nobody else allocates ordinals.
    private let counter = MonotonicCounter()
    private lazy var joiner = IdempotentOperationJoiner.asyncJoiner(.main)
    // The session stamped by the last update(). Skips re-stamping when the
    // focused session hasn't actually changed.
    private weak var lastStampedSession: PTYSession?

    // Schedule a coalesced stamp of the focused session's ordinal.
    @objc
    func setNeedsUpdate() {
        DLog("setNeedsUpdate")
        joiner.setNeedsUpdate { [weak self] in
            self?.update()
        }
    }

    private func update() {
        // Read the settled focused session now (rather than when a trigger
        // fired) so any mid-operation state has resolved. The focused session
        // is the front window's current session.
        guard let focused = iTermController.sharedInstance()?.currentTerminal?.currentSession() else {
            DLog("update: no focused session; not stamping")
            return
        }
        if focused === lastStampedSession {
            DLog("update: focused session unchanged (guid=\(focused.guid) name=\(focused.name)); not stamping")
            return
        }
        lastStampedSession = focused
        let ordinal = counter.next
        focused.lastActivityOrdinal = ordinal
        DLog("update: stamped guid=\(focused.guid) name=\(focused.name) ordinal=\(ordinal)")
    }

    // MARK: - Persistence

    // The high-water mark is saved in the app-wide restorable state and each
    // restored session's arrangement ratchets it (see PTYSession), so ordinals
    // stay comparable across launches.

    @objc var highWaterMark: Int {
        return counter.value
    }

    @objc(ratchetToValue:)
    func ratchet(to value: Int) {
        counter.setMinimum(value)
    }
}
