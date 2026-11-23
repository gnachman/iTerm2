//
//  TabBarOrderController.swift
//  iTerm2SharedARC
//
//  A window's tab bar order (see TabBarOrder) and what it needs to keep it
//  steady:
//
//  - A tab moves between a directory section and the shell prompt section
//    only after its state has held for a while, so a shell that is briefly in
//    the foreground while starting a command doesn't make it flicker.
//  - While the pointer is over the bar, tabs keep the places they were last
//    shown in, so nothing moves under it. The window asks with useSnapshot.
//  - Directories change without telling anyone, so while ordering by
//    directory a timer checks for changes.
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
    let atPrompt: Bool
    let group: String?

    @objc init(key: Int, pinned: Bool, statusPriority: Int, snoozed: Bool, directory: String?, atPrompt: Bool, group: String?) {
        self.key = key
        self.pinned = pinned
        self.statusPriority = statusPriority
        self.snoozed = snoozed
        self.directory = directory
        self.atPrompt = atPrompt
        self.group = group
    }
}

@objc(iTermTabBarOrderController)
final class TabBarOrderController: NSObject {
    /// How long a change between at a prompt and running a command must hold
    /// before the tab changes sections.
    static let promptHoldInterval: TimeInterval = 1
    /// How often to check for changes while ordering by directory.
    static let pollInterval: TimeInterval = 0.5

    @objc var mode = TabBarOrderMode.manual {
        didSet {
            guard mode != oldValue else {
                return
            }
            DLog("Tab bar order mode \(oldValue.rawValue) -> \(mode.rawValue)")
            snapshot.removeAll()
            // Only the directory order tracks prompts, so others recorded
            // tabs as never at one.
            promptStates.removeAll()
            heldBackByPointer = false
            updateTimer()
        }
    }

    /// Called when what the bar shows may need to change. The window then
    /// asks for the order again.
    @objc var needsUpdate: (() -> Void)?
    /// Gives the window's tabs as they are now, in manual order.
    @objc var liveTabs: (() -> [TabBarOrderLiveTab])?
    /// Whether the pointer is over the bar.
    @objc var pointerIsInside: (() -> Bool)?
    /// Whether the bar shows the order now. Polling is skipped otherwise.
    @objc var isActive: (() -> Bool)?

    /// For tests.
    var now: () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }

    private struct PromptState {
        var stable: Bool
        var pending: Bool
        var pendingSince: TimeInterval
    }
    private var promptStates = [Int: PromptState]()
    private var snapshot = [Int: TabBarOrderTab]()
    /// What was last applied, to tell whether a check found a change.
    private var lastApplied: (order: [Int], sections: [String], membership: [String])?
    private var heldBackByPointer = false
    private var timer: Timer?

    deinit {
        timer?.invalidate()
    }

    /// The order for these tabs. With `useSnapshot`, tabs keep the inputs
    /// they were last applied with (pinned state is always current). With
    /// `store`, as when applying to the bar, the inputs used are remembered.
    @objc(resultForTabs:useSnapshot:store:)
    func result(for tabs: [TabBarOrderLiveTab], useSnapshot: Bool, store: Bool) -> TabBarOrderResult {
        let time = now()
        let orderTabs = tabs.map { live -> TabBarOrderTab in
            if useSnapshot, let held = snapshot[live.key] {
                return TabBarOrderTab(pinned: live.pinned,
                                      statusPriority: held.statusPriority,
                                      snoozed: held.snoozed,
                                      directory: held.directory,
                                      atPrompt: held.atPrompt,
                                      group: live.group)
            }
            let atPrompt = stablePromptState(for: live, at: time, store: store)
            let tab = TabBarOrderTab(pinned: live.pinned,
                                     statusPriority: live.statusPriority,
                                     snoozed: live.snoozed,
                                     directory: live.directory,
                                     atPrompt: atPrompt,
                                     group: live.group)
            if store {
                snapshot[live.key] = tab
            }
            return tab
        }
        if store {
            let keys = Set(tabs.map(\.key))
            snapshot = snapshot.filter { keys.contains($0.key) }
            promptStates = promptStates.filter { keys.contains($0.key) }
        }
        let result = TabBarOrder.apply(mode: mode, tabs: orderTabs)
        if store {
            lastApplied = Self.summary(of: result)
            if !useSnapshot {
                heldBackByPointer = false
            }
        }
        return result
    }

    private func stablePromptState(for live: TabBarOrderLiveTab, at time: TimeInterval, store: Bool) -> Bool {
        guard var state = promptStates[live.key] else {
            if store {
                promptStates[live.key] = PromptState(stable: live.atPrompt, pending: live.atPrompt, pendingSince: time)
            }
            return live.atPrompt
        }
        if live.atPrompt == state.stable {
            state.pending = state.stable
        } else if live.atPrompt != state.pending {
            state.pending = live.atPrompt
            state.pendingSince = time
        } else if time - state.pendingSince >= Self.promptHoldInterval {
            state.stable = live.atPrompt
        }
        if store {
            promptStates[live.key] = state
        }
        return state.stable
    }

    /// The bar stopped showing the order.
    @objc func forgetApplied() {
        lastApplied = nil
        // Nothing was frozen or tracked while it wasn't shown, so start
        // from what tabs are when it shows again.
        snapshot.removeAll()
        promptStates.removeAll()
        heldBackByPointer = false
    }

    /// Something a tab's place depends on changed, such as its status.
    @objc func inputsDidChange() {
        guard mode != .manual else {
            return
        }
        if pointerIsInside?() ?? false {
            DLog("Tab order inputs changed with the pointer over the bar; wait for it to leave")
            heldBackByPointer = true
            return
        }
        // The pointer may have gone without an exit; don't wait for one.
        heldBackByPointer = false
        needsUpdate?()
    }

    /// The pointer left the bar, or may have without saying so.
    @objc func applyChangesHeldBackByPointer() {
        guard heldBackByPointer, !(pointerIsInside?() ?? false) else {
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
        // Advance prompt states without applying: store the states but not
        // the snapshot, so held tabs stay put.
        let time = now()
        for live in tabs {
            _ = stablePromptState(for: live, at: time, store: true)
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
