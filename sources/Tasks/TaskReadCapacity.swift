//
//  TaskReadCapacity.swift
//  iTerm2
//

import Foundation

// Decides whether a session's task may read more, and when to try again. A session stops reading
// while its token executor is full. A tmux gateway also stops while its panes have too much output
// waiting, counting lines the main queue hasn't handled yet. That holds back everything tmux sends,
// including command replies, so it relies on main and every pane that is still open draining
// their queues.
@objc(iTermTaskReadCapacity)
final class TaskReadCapacity: NSObject {
    private let tokenHasCapacity: () -> Bool
    private let notifyWhenTokenCapacityAvailable: (DispatchQueue, @escaping () -> Void) -> Void
    private let gatewayBudget: () -> ByteBudget?

    // `gatewayBudget` returns the panes' output budget while the session is a tmux gateway, and
    // nil otherwise. All three are called on the task's monitor queue.
    @objc
    init(tokenHasCapacity: @escaping () -> Bool,
         notifyWhenTokenCapacityAvailable: @escaping (DispatchQueue, @escaping () -> Void) -> Void,
         gatewayBudget: @escaping () -> ByteBudget?) {
        self.tokenHasCapacity = tokenHasCapacity
        self.notifyWhenTokenCapacityAvailable = notifyWhenTokenCapacityAvailable
        self.gatewayBudget = gatewayBudget
        super.init()
    }

    @objc var hasCapacity: Bool {
        guard tokenHasCapacity() else {
            return false
        }
        return gatewayBudget()?.hasCapacity ?? true
    }

    // Runs `block` on `queue` once, when it may be worth checking hasCapacity again. Call after
    // hasCapacity returned false. The block should check again, since only one of the two limits
    // is waited for at a time.
    @objc(notifyWhenCapacityAvailableOnQueue:block:)
    func notifyWhenCapacityAvailable(on queue: DispatchQueue, block: @escaping () -> Void) {
        guard let budget = gatewayBudget(), tokenHasCapacity() else {
            notifyWhenTokenCapacityAvailable(queue, block)
            return
        }
        if budget.hasCapacity {
            // The token executor was what was full, and it has drained since the caller checked.
            // Waiting on the budget would wait for its low watermark, which reading doesn't need.
            queue.async(execute: block)
            return
        }
        budget.notifyWhenCapacityAvailable(on: queue, block)
        if gatewayBudget() == nil {
            // Gateway mode ended after the check above, and its wake may have come before the block
            // was registered.
            budget.wake()
        }
    }
}
