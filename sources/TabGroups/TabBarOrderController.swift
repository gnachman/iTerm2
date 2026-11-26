//
//  TabBarOrderController.swift
//  iTerm2SharedARC
//
//  A window's tab bar order (see TabBarOrder) and what it needs to keep it
//  current and steady:
//
//  - While the pointer holds the bar (it's over the bar and moved recently;
//    see PSMTabBarControl.pointerIsHoldingTabs), tabs keep the places they
//    were last shown in, so nothing moves under it. The window asks with
//    useSnapshot.
//  - Directories change without telling anyone, so while ordering by
//    directory a timer checks for changes.
//  - The bar may not hear the pointer leave, so while changes wait for it a
//    timer checks whether it's gone or stopped moving.
//

import Foundation

/// What a tab is now, as the window sees it.
@objc(iTermTabBarOrderLiveTab)
final class TabBarOrderLiveTab: NSObject {
    let key: Int
    let pinned: Bool
    let statusPriority: Int
    let snoozed: Bool
    let directory: String?
    let group: String?

    @objc init(key: Int, pinned: Bool, statusPriority: Int, snoozed: Bool, directory: String?, group: String?) {
        self.key = key
        self.pinned = pinned
        self.statusPriority = statusPriority
        self.snoozed = snoozed
        self.directory = directory
        self.group = group
    }
}

@objc(iTermTabBarOrderController)
final class TabBarOrderController: NSObject {
    /// How often to check for changes while ordering by directory.
    static let pollInterval: TimeInterval = 0.5

    @objc var mode = TabBarOrderMode.manual {
        didSet {
            guard mode != oldValue else {
                return
            }
            DLog("Tab bar order mode \(oldValue.rawValue) -> \(mode.rawValue)")
            snapshot.removeAll()
            heldBackByPointer = false
            updateTimer()
        }
    }

    /// Called when what the bar shows may need to change. The window then
    /// asks for the order again.
    @objc var needsUpdate: (() -> Void)?
    /// Gives the window's tabs as they are now, in manual order.
    @objc var liveTabs: (() -> [TabBarOrderLiveTab])?
    /// Whether the pointer is over the bar and moved recently.
    @objc var pointerIsHolding: (() -> Bool)?
    /// Whether the bar shows the order now. Polling is skipped otherwise.
    @objc var isActive: (() -> Bool)?

    private var snapshot = [Int: TabBarOrderTab]()
    /// What was last applied, to tell whether a check found a change.
    private var lastApplied: (order: [Int], sections: [String], membership: [String])?
    private var heldBackByPointer = false {
        didSet {
            updatePointerTimer()
        }
    }
    private var timer: Timer?
    /// While changes wait for the pointer, checks whether it's gone, in case
    /// the bar doesn't hear it leave.
    private var pointerTimer: Timer?

    deinit {
        timer?.invalidate()
        pointerTimer?.invalidate()
    }

    /// The order for these tabs. With `useSnapshot`, tabs keep the inputs
    /// they were last applied with (pinned state is always current). With
    /// `store`, as when applying to the bar, the inputs used are remembered;
    /// with both, if what tabs are now would show differently, that change
    /// waits for the pointer to leave.
    @objc(resultForTabs:useSnapshot:store:)
    func result(for tabs: [TabBarOrderLiveTab], useSnapshot: Bool, store: Bool) -> TabBarOrderResult {
        var differsFromSnapshot = false
        var liveTabs = [TabBarOrderTab]()
        let orderTabs = tabs.map { live -> TabBarOrderTab in
            let tab = TabBarOrderTab(pinned: live.pinned,
                                     statusPriority: live.statusPriority,
                                     snoozed: live.snoozed,
                                     directory: live.directory,
                                     group: live.group)
            liveTabs.append(tab)
            if useSnapshot, let held = snapshot[live.key] {
                if held.statusPriority != tab.statusPriority ||
                    held.snoozed != tab.snoozed ||
                    held.directory != tab.directory {
                    differsFromSnapshot = true
                }
                return TabBarOrderTab(pinned: live.pinned,
                                      statusPriority: held.statusPriority,
                                      snoozed: held.snoozed,
                                      directory: held.directory,
                                      group: live.group)
            }
            if store {
                snapshot[live.key] = tab
            }
            return tab
        }
        if store {
            let keys = Set(tabs.map(\.key))
            snapshot = snapshot.filter { keys.contains($0.key) }
        }
        let result = TabBarOrder.apply(mode: mode, tabs: orderTabs)
        if store && differsFromSnapshot && !heldBackByPointer {
            let now = Self.summary(of: TabBarOrder.apply(mode: mode, tabs: liveTabs))
            let shown = Self.summary(of: result)
            if now.order != shown.order || now.sections != shown.sections || now.membership != shown.membership {
                // Shown as it was, so the change waits for the pointer to
                // leave rather than being lost.
                DLog("Applied the tab order under the pointer with a change waiting")
                heldBackByPointer = true
            }
        }
        if store {
            lastApplied = Self.summary(of: result)
            if !useSnapshot {
                heldBackByPointer = false
            }
        }
        return result
    }

    /// The bar stopped showing the order.
    @objc func forgetApplied() {
        lastApplied = nil
        // Nothing was frozen while it wasn't shown, so start from what tabs
        // are when it shows again.
        snapshot.removeAll()
        heldBackByPointer = false
    }

    /// Something a tab's place depends on changed, such as its status.
    @objc func inputsDidChange() {
        guard mode != .manual else {
            return
        }
        if pointerIsHolding?() ?? false {
            DLog("Tab order inputs changed with the pointer holding the bar; wait for it to leave or rest")
            heldBackByPointer = true
            return
        }
        // The pointer may have gone without an exit; don't wait for one.
        heldBackByPointer = false
        needsUpdate?()
    }

    /// The status priority list changed. Held priorities are indices into
    /// the old list and would show under the wrong headings, so drop them
    /// and show tabs as they are now. The list is edited in Settings, so
    /// this doesn't wait for the pointer.
    @objc func statusPrioritiesDidChange() {
        guard mode == .status else {
            return
        }
        DLog("Status priorities changed; drop the snapshot and update")
        snapshot.removeAll()
        heldBackByPointer = false
        needsUpdate?()
    }

    /// The pointer left the bar or stopped moving over it, or may have
    /// without saying so.
    @objc func applyChangesHeldBackByPointer() {
        guard heldBackByPointer, !(pointerIsHolding?() ?? false) else {
            return
        }
        DLog("Apply tab order changes that waited for the pointer")
        heldBackByPointer = false
        needsUpdate?()
    }

    /// Whether changes are waiting for the pointer to leave, so readers
    /// should go by the snapshot.
    @objc var isHoldingBack: Bool {
        return heldBackByPointer
    }

    private func updatePointerTimer() {
        if heldBackByPointer {
            guard pointerTimer == nil else {
                return
            }
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                self?.applyChangesHeldBackByPointer()
            }
            timer.tolerance = Self.pollInterval / 2
            RunLoop.main.add(timer, forMode: .common)
            pointerTimer = timer
        } else {
            pointerTimer?.invalidate()
            pointerTimer = nil
        }
    }

    private func updateTimer() {
        if mode == .workingDirectory {
            guard timer == nil else {
                return
            }
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                self?.poll()
            }
            timer.tolerance = Self.pollInterval / 2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Checks whether the order would change, and asks for an update if so.
    @objc func poll() {
        guard mode != .manual, isActive?() ?? true, let tabs = liveTabs?() else {
            return
        }
        let candidate = Self.summary(of: self.result(for: tabs, useSnapshot: false, store: false))
        if let lastApplied,
           lastApplied.order == candidate.order,
           lastApplied.sections == candidate.sections,
           lastApplied.membership == candidate.membership {
            return
        }
        inputsDidChange()
    }

    /// What tells whether the bar would show something different.
    private static func summary(of result: TabBarOrderResult) -> (order: [Int], sections: [String], membership: [String]) {
        return (result.order,
                result.sections.map(\.identifier),
                result.sectionIdentifiers.map { $0 as? String ?? "" })
    }
}
