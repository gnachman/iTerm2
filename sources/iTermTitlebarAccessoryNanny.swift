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
    private var hasProbationers = false
    @objc var enteringFullScreen = false {
        didSet {
            DLog("enteringFullScreen set to \(enteringFullScreen)")
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
    private var timer: Timer?

    @objc(add:)
    func add(viewController: NSTitlebarAccessoryViewController) {
        if viewControllers.contains(viewController) {
            return;
        }
        DLog("Add \(viewController)")
        viewControllers.append(viewController)
        needsUpdate = true
    }

    @objc private func reviewProbation() {
        if !safe {
            DLog("Entering full screen. Retry twiddle later. This code path sucks and should be avoided.")
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                self.reviewProbation()
            }
            return
        }
        guard let window = windowController?.window else {
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
        DLog("Remove \(viewController)")
        viewControllers.removeAll {
            $0 === viewController
        }
        pendingUpdates.removeValue(forKey: ObjectIdentifier(viewController))
        needsUpdate = true
    }

    @objc(removeAll)
    func removeAll() {
        guard !viewControllers.isEmpty else {
            return
        }
        DLog("Remove all view controllers")
        viewControllers = []
        pendingUpdates = [:]
        needsUpdate = true
    }

    @objc(updateViewController:settingMinHeight:frame:)
    func updateMinHeight(viewController: NSTitlebarAccessoryViewController, minHeight: CGFloat, frame: NSRect) {
        DLog("For \(viewController) set minHeight=\(minHeight), frame=\(frame)")
        pendingUpdates[ObjectIdentifier(viewController)] = (minHeight, frame)
        needsUpdate = true
    }

    @objc
    func updateIfNeeded() {
        guard needsUpdate else {
            return
        }
        update()
    }

    private func update() {
        guard let window = windowController?.window else {
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

    @objc(has:)
    func has(viewController: NSTitlebarAccessoryViewController) -> Bool {
        guard windowController?.window?.styleMask.contains(.titled) == true else {
            return false
        }
        return viewControllers.contains(viewController)
    }
}

@objc
protocol iTermTitleBarAccessoryViewController: AnyObject {
    var needsFullScreenMinHeight: Bool { get }
}
