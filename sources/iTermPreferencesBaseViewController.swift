//
//  iTermPreferencesBaseViewController.swift
//  iTerm2
//
//  Created by George Nachman on 6/21/25.
//

fileprivate let terminalModeKey = "terminal mode"
fileprivate let browserModeKey = "browser mode"

@objc
extension iTermPreferencesBaseViewController {

    @objc(moveSubviewsForBrowserMode:tabViewItem:)
    func moveSubviews(browserMode: Bool, tabViewItem: NSTabViewItem) -> Bool {
        let contentView = view

        let needsReveal: Bool
        if internalState.count == 0 {
            needsReveal = false
            let terminalEnclosures: [TerminalModeEnclosure] = findEnclosures(in: contentView).sorted { $0.frame.origin.y > $1.frame.origin.y }
            let browserEnclosures: [BrowserModeEnclosure] = findEnclosures(in: contentView).sorted { $0.frame.origin.y > $1.frame.origin.y }
            initialize(terminalEnclosures: terminalEnclosures,
                       browserEnclosures: browserEnclosures,
                       tabViewItem: tabViewItem)
        } else {
            needsReveal = true
        }
        if browserMode {
            DLog("Setting browser mode on. Remove terminal views.")
            self.remove(internalState: internalState[terminalModeKey] as! InternalState)
            if needsReveal {
                DLog("Still setting browser mode on. Reveal browser views.")
                self.reveal(internalState: internalState[browserModeKey] as! InternalState)
            }
        } else {
            DLog("Setting terminal mode on. Remove brwoser views.")
            self.remove(internalState: internalState[browserModeKey] as! InternalState)
            if needsReveal {
                DLog("Still setting terminal mode on. Reveal terminal views.")
                self.reveal(internalState: internalState[terminalModeKey] as! InternalState)
            }
        }
        return hasVisibleControls(in: view)
    }
}

@objc fileprivate class InternalState: NSObject {
    struct Tab {
        var tabView: NSTabView
        var tabViewItem: NSTabViewItem
        var successors: [NSTabViewItem]

        var insertionIndex: Int {
            for i in 0..<tabView.tabViewItems.count {
                if successors.contains(where: { $0 == tabView.tabViewItems[i] }) {
                    return i
                }
            }
            return tabView.tabViewItems.count
        }
    }
    var originalFrames: [NSView: NSRect]
    var enclosures: [ModalEnclosure]
    var removedTabs: [Tab]
    var heightAdjustments: [NSView: CGFloat]
    var flippedView: iTermFlippedView?

    init(originalFrames: [NSView: NSRect],
         enclosures: [ModalEnclosure],
         removedTabs: [Tab],
         heightAdjustments: [NSView: CGFloat],
         viewController: iTermPreferencesBaseViewController) {
        self.originalFrames = originalFrames
        self.enclosures = enclosures
        self.removedTabs = removedTabs
        self.heightAdjustments = heightAdjustments
        self.flippedView = Self.findFlippedView(under: viewController.view)
    }

    private static func findFlippedView(under view: NSView) -> iTermFlippedView? {
        if let flipped = view as? iTermFlippedView {
            return flipped
        }
        if let superview = view.superview {
            return findFlippedView(under: superview)
        }
        return nil
    }
}

extension iTermPreferencesBaseViewController {
    private func initialize(terminalEnclosures: [TerminalModeEnclosure],
                            browserEnclosures: [BrowserModeEnclosure],
                            tabViewItem: NSTabViewItem) {
        internalState[terminalModeKey] = makeInternalState(terminalEnclosures,
                                                           viewController: self)
        internalState[browserModeKey] = makeInternalState(browserEnclosures,
                                                          viewController: self)
    }

    private func makeInternalState<T: ModalEnclosure>(
        _ enclosures: [T],
        viewController: iTermPreferencesBaseViewController) -> InternalState {
            // First pass: Record original frames for all enclosures and their siblings
            let originalFrameTuples = enclosures.flatMap { enclosure in
                enclosure.superview!.subviews.compactMap { sibling in
                    (sibling, sibling.frame)
                }
            }
            var originalFrames = [NSView: NSRect]()
            for (control, frame) in originalFrameTuples {
                originalFrames[control] = frame
            }

            // Second pass: Calculate adjustments for removing enclosures
            let heightAdjustmentTuples = enclosures.flatMap { enclosure -> [(NSView, CGFloat)] in
                let enclosureHeight = enclosure.frame.height
                let enclosureMinY = enclosure.frame.origin.y

                return enclosure.superview!.subviews.compactMap { sibling -> (NSView, CGFloat)? in
                    if sibling is T {
                        return nil
                    }
                    // Check if this view is below the threshold (using original frame)
                    if sibling.frame.minY < enclosureMinY {
                        return (sibling, enclosureHeight)
                    }
                    return nil
                }
            }
            var heightAdjustments = [NSView: CGFloat]()
            for (view, height) in heightAdjustmentTuples {
                print("Adjustment for \(view) is \(height). Initial frame is \(view.frame)")
                heightAdjustments[view, default: 0] += height
            }

            let removedTabs = findTabsToRemove(afterRemovingEnclosures: enclosures)

            return InternalState(originalFrames: originalFrames,
                                 enclosures: enclosures,
                                 removedTabs: removedTabs,
                                 heightAdjustments: heightAdjustments,
                                 viewController: viewController)
        }

    private func adjustFlippedViewHeight(removing enclosures: [ModalEnclosure],
                                         flippedView: iTermFlippedView) {
        adjustFlippedViewHeight(enclosures: enclosures, flippedView: flippedView, sign: -1)
    }

    private func adjustFlippedViewHeight(revealing enclosures: [ModalEnclosure],
                                         flippedView: iTermFlippedView) {
        adjustFlippedViewHeight(enclosures: enclosures, flippedView: flippedView, sign: 1)
    }


    private func adjustFlippedViewHeight(enclosures: [ModalEnclosure],
                                         flippedView: iTermFlippedView,
                                         sign: CGFloat) {
        let totalHeightReduction = enclosures.reduce(0) { total, enclosure in
            return total + enclosure.frame.height
        }

        var flippedFrame = flippedView.frame
        flippedFrame.size.height += totalHeightReduction * sign
        flippedView.frame = flippedFrame
        print("For \(self) adjust flipped view height by \(totalHeightReduction * sign)")
    }


    private func remove(internalState: InternalState) {
        // Hide enclosures and show browser enclosures
        for enclosure in internalState.enclosures {
            enclosure.isHidden = true
        }
        DLog("Begin remove")
        // Apply all view adjustments
        for (view, adjustment) in internalState.heightAdjustments {
            var frame = view.frame
            frame.origin.y += adjustment
            view.frame = frame
            DLog("Move \(view) by +\(adjustment). New frame is \(view.frame)")
        }
        DLog("End remove")
        // Handle nested tab views - remove tabs that have no visible controls
        for tab in internalState.removedTabs {
            tab.tabView.removeTabViewItem(tab.tabViewItem)
        }

        // Adjust the flipped view height if we're in a scroll view
        if let flippedView = internalState.flippedView {
            adjustFlippedViewHeight(removing: internalState.enclosures,
                                    flippedView: flippedView)
        }
    }

    private func reveal(internalState: InternalState) {
        // Reveal enclosures and show browser enclosures
        for enclosure in internalState.enclosures {
            enclosure.isHidden = false
        }
        DLog("Begin reveal")
        // Apply all view adjustments
        for (view, adjustment) in internalState.heightAdjustments {
            var frame = view.frame
            frame.origin.y -= adjustment
            view.frame = frame
            DLog("Move \(view) by -\(adjustment). New frame is \(view.frame)")
        }
        DLog("End reveal")
        // Handle nested tab views - remove tabs that have no visible controls
        for tab in internalState.removedTabs {
            tab.tabView.insertTabViewItem(tab.tabViewItem, at: tab.insertionIndex)
        }

        // Adjust the flipped view height if we're in a scroll view
        if let flippedView = internalState.flippedView {
            adjustFlippedViewHeight(revealing: internalState.enclosures,
                                    flippedView: flippedView)
        }
    }

    private func findEnclosures<T: ModalEnclosure>(in view: NSView) -> [T] {
        var enclosures: [T] = []

        // If this is an NSTabView, search all tab views (not just the active one)
        if let tabView = view as? NSTabView {
            for tabViewItem in tabView.tabViewItems {
                if let tabView = tabViewItem.view {
                    let children: [T] = findEnclosures(in: tabView)
                    enclosures.append(contentsOf: children)
                }
            }
        } else if let enclosure = view as? T {
            enclosures.append(enclosure)
        } else {
            for subview in view.subviews {
                let children: [T] = findEnclosures(in: subview)
                enclosures.append(contentsOf: children)
            }
        }

        return enclosures
    }

    private var nestedTabViews: [NSTabView] {
        return nestedTabViews(of: view)
    }

    private func nestedTabViews(of view: NSView) -> [NSTabView] {
        return view.subviews.flatMap { subview -> [NSTabView] in
            let children = nestedTabViews(of: subview)
            var result = [NSTabView]()
            if let me = subview as? NSTabView {
                result.append(me)
            }
            result.append(contentsOf: children)
            return result
        }
    }

    private func findTabsToRemove<T: ModalEnclosure>(afterRemovingEnclosures: [T]) -> [InternalState.Tab] {
        let tabViews = nestedTabViews
        return tabViews.flatMap { tabView -> [InternalState.Tab] in
            return tabView.tabViewItems.enumerated().compactMap { i, tabViewItem -> InternalState.Tab? in
                if let tabViewItemView = tabViewItem.view,
                   tabViewItemView.subviews.allSatisfy({ $0 is T }) {
                    let successors = Array(tabView.tabViewItems[(i + 1)...])
                    return InternalState.Tab(tabView: tabView,
                                             tabViewItem: tabViewItem,
                                             successors: successors)
                } else {
                    return nil
                }
            }
        }
    }

    private func hasVisibleControls(in view: NSView) -> Bool {
        if let enclosure = view as? ModalEnclosure, enclosure.isHidden {
            return false
        }

        // If this view is a control and visible, we found one
        if view is NSControl && !view.isHidden {
            return true
        }

        // If this is an NSTabView, check all tab views
        if let tabView = view as? NSTabView {
            for tabViewItem in tabView.tabViewItems {
                if let tabView = tabViewItem.view, hasVisibleControls(in: tabView) {
                    return true
                }
            }
        }

        // Recursively check subviews
        for subview in view.subviews {
            if !subview.isHidden && hasVisibleControls(in: subview) {
                return true
            }
        }

        return false
    }
}
