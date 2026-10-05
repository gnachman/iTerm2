//
//  iTermTitlebarAccessoryNanny.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/13/25.
//

import AppKit

// This catastrofuck of a class exists to work around a long-lived macOS bug that I finally tracked
// down. If you adjust the fullScreenMinHeight of a titlebar accessory view controller between
// willEnterFullScreen and *one spin of the runloop after* didEnterFullScreen on a display with a
// notch then the view controller's view is invisible, but it reserves space for it.
//
// Thefore we have a preposterous system for putting titlebar accessory view controllers on
// probation, during which time we don't adjust fullScreenMinHeight. We only remove them from
// probation and  adjust their delicate snowflake fullScreenMinHeight when macOS won't
// pollute its britches.
@objc
class iTermTitlebarAccessoryNanny: NSObject {
    @objc var defaultHeight = 38.0
    let updateAfterDelay = false
    @objc private(set) var viewControllers = [NSTitlebarAccessoryViewController]()
    private var probation = [ObjectIdentifier: CGFloat]()
    @objc weak var windowController: NSWindowController?

    // The window, but only if it has a title bar. AppKit throws "titlebarAccessoryViewControllers
    // not supported for this window style" when you get or change a window's titlebar accessories
    // without .titled, so there is nothing to manage until it has one. Exiting Lion fullscreen can
    // restore a style mask without it (e.g., tmux integration windows).
    private var titledWindow: NSWindow? {
        guard let window = windowController?.window, window.styleMask.contains(.titled) else {
            return nil
        }
        return window
    }
    private var hasProbationers = false
    @objc var enteringFullScreen = false {
        didSet {
            RLog("enteringFullScreen set to \(enteringFullScreen)")
            if enteringFullScreen {
                safe = false
            }
            if !enteringFullScreen {
                DispatchQueue.main.async {
                    DLog("One spin after update of enteringFullScreen")
                    if !self.enteringFullScreen {
                        self.safe = true
                    }
                }
            }
        }
    }
    private var safe = true {
        didSet {
            if safe && hasProbationers {
                reviewProbation()
            }
        }
    }
    private var needsUpdate = false {
        didSet {
            if needsUpdate == oldValue || !needsUpdate {
                return
            }
            if updateAfterDelay {
                DispatchQueue.main.async {
                    self.update()
                }
            } else {
                self.update()
            }
        }
    }
    private var pendingUpdates = [ObjectIdentifier: (CGFloat, NSRect)]()
    // The most recent minHeight requested for each view controller via
    // updateMinHeight. Tracked here rather than reading
    // vc.fullScreenMinHeight because that value can be stashed on probation or
    // overridden with defaultHeight when a vc is first added. Used by callers
    // who want to react to the *requested* height changing. Issue 12811.
    private var lastRequestedMinHeight = [ObjectIdentifier: CGFloat]()
    private var timer: Timer?

    @objc(add:)
    func add(viewController: NSTitlebarAccessoryViewController) {
        if viewControllers.contains(viewController) {
            return;
        }
        RLog("Add \(viewController)")
        viewControllers.append(viewController)
        needsUpdate = true
    }

    @objc private func reviewProbation() {
        if !safe {
            RLog("Entering full screen. Retry twiddle later. This code path sucks and should be avoided.")
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                self?.reviewProbation()
            }
            return
        }
        guard let window = titledWindow else {
            return
        }
        guard window.styleMask.contains(.fullScreen) else {
            return
        }
        if window.titlebarAccessoryViewControllers.isEmpty {
            return
        }
        DLog("twiddle")
        for vc in window.titlebarAccessoryViewControllers {
            if let height = probation[ObjectIdentifier(vc)] {
                DLog("  Remove \(vc) from probation and set its min height")
                setMinHeight(vc, to: height)
                probation.removeValue(forKey: ObjectIdentifier(vc))
            }
        }
        DLog("end twiddle")
    }

    private func setMinHeight(_ vc: NSTitlebarAccessoryViewController, to height: CGFloat) {
        if let obj = vc as? iTermTitleBarAccessoryViewController {
            if !obj.needsFullScreenMinHeight {
                return
            }
        }
        vc.fullScreenMinHeight = height
    }

    @objc(remove:)
    func remove(viewController: NSTitlebarAccessoryViewController) {
        guard viewControllers.contains(viewController) else {
            return
        }
        RLog("Remove \(viewController)")
        viewControllers.removeAll {
            $0 === viewController
        }
        pendingUpdates.removeValue(forKey: ObjectIdentifier(viewController))
        lastRequestedMinHeight.removeValue(forKey: ObjectIdentifier(viewController))
        needsUpdate = true
    }

    @objc(removeAll)
    func removeAll() {
        guard !viewControllers.isEmpty else {
            return
        }
        RLog("Remove all view controllers")
        viewControllers = []
        pendingUpdates = [:]
        lastRequestedMinHeight = [:]
        needsUpdate = true
    }

    /// Records a minHeight/frame request for `viewController`. Returns true if
    /// the requested minHeight differs from the previous request for this view
    /// controller (or if there was no previous request). Useful for triggering
    /// a relayout when the accessory's effective height changes.
    @discardableResult
    @objc(updateViewController:settingMinHeight:frame:)
    func updateMinHeight(viewController: NSTitlebarAccessoryViewController, minHeight: CGFloat, frame: NSRect) -> Bool {
        DLog("For \(viewController) set minHeight=\(minHeight), frame=\(frame)")
        let id = ObjectIdentifier(viewController)
        let previous = lastRequestedMinHeight[id]
        lastRequestedMinHeight[id] = minHeight
        pendingUpdates[id] = (minHeight, frame)
        needsUpdate = true
        return previous != minHeight
    }

    @objc
    func updateIfNeeded() {
        guard needsUpdate else {
            return
        }
        update()
    }

    private func update() {
        guard let window = titledWindow else {
            // Nothing to do without a title bar. Clear needsUpdate anyway: requests only trigger
            // an update when it goes from false to true, so leaving it set would swallow every later
            // request. viewControllers and pendingUpdates keep the desired state, so the next
            // request after the window has a title bar applies all of it.
            DLog("Not updating titlebar accessories of a window without a title bar")
            needsUpdate = false
            return
        }
        needsUpdate = false
        DLog("Performing update")
        for (objectIdentifier, tuple) in pendingUpdates {
            if let vc = viewControllers.first(where: { ObjectIdentifier($0) == objectIdentifier }) {
                DLog("  Actually update \(vc): minHeight=\(tuple.0), frame=\(tuple.1)")
                vc.view.frame = tuple.1
                if probation[ObjectIdentifier(vc)] == tuple.0 {
                    continue
                }
                if !window.titlebarAccessoryViewControllers.contains(vc) || !safe {
                    DLog("  This vc is/will be on probation so I'm not changing its fullScreenMinHeight")
                    probation[ObjectIdentifier(vc)] = tuple.0
                    hasProbationers = true
                    continue
                }
                // It is safe to change full screen min h and vc is already in the window's array
                setMinHeight(vc, to: tuple.0)
            }
        }
        for vc in viewControllers {
            if window.titlebarAccessoryViewControllers.contains(vc) {
                continue
            }
            DLog("  Actually add \(vc)")
            if probation[ObjectIdentifier(vc)] == nil {
                DLog("  Put \(vc) on probation and force its fullScreenMinHeight to be \(defaultHeight) although it prefers \(vc.fullScreenMinHeight)")
                probation[ObjectIdentifier(vc)] = vc.fullScreenMinHeight
                hasProbationers = true
            }
            setMinHeight(vc, to: defaultHeight)
            window.addTitlebarAccessoryViewController(vc)
        }
        let indexesToRemove = (0..<window.titlebarAccessoryViewControllers.count).filter { i in
            let vc = window.titlebarAccessoryViewControllers[i]
            return !viewControllers.contains(vc)
        }
        for i in indexesToRemove.reversed() {
            DLog("  Actually remove \(window.titlebarAccessoryViewControllers[i])")
            window.removeTitlebarAccessoryViewController(at: i)
        }
        if hasProbationers && safe {
            reviewProbation()
        }
        DLog("Update complete")
    }

    // Work around macOS bug where the content view frame isn't updated to
    // account for titlebar accessories after exiting Lion fullscreen.
    // Removing and re-adding forces AppKit to recalculate. Issue 12810.
    @objc func forceReaddAll() {
        guard let window = titledWindow else {
            return
        }
        RLog("Force re-adding all view controllers to fix content view layout")
        var toReadd = [NSTitlebarAccessoryViewController]()
        for vc in viewControllers {
            if window.titlebarAccessoryViewControllers.contains(vc) {
                toReadd.append(vc)
            }
        }
        for vc in toReadd.reversed() {
            if let index = window.titlebarAccessoryViewControllers.firstIndex(of: vc) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
        }
        for vc in toReadd {
            window.addTitlebarAccessoryViewController(vc)
        }
    }

    @objc(has:)
    func has(viewController: NSTitlebarAccessoryViewController) -> Bool {
        guard titledWindow != nil else {
            return false
        }
        return viewControllers.contains(viewController)
    }
}

@objc
protocol iTermTitleBarAccessoryViewController: AnyObject {
    var needsFullScreenMinHeight: Bool { get }
}
