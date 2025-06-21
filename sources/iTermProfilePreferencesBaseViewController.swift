//
//  iTermProfilePreferencesBaseViewController.swift
//  iTerm2
//
//  Created by George Nachman on 6/21/25.
//

@objc
extension iTermProfilePreferencesBaseViewController {
    private static var originalFramesKey = "iTermOriginalFrames"
    private static var optionalEnclosuresKey = "iTermOptionalEnclosures"
    private static var removedTabsKey = "iTermRemovedTabs"

    @objc(moveSubviewsForBrowserMode:)
    func moveSubviews(browserMode: Bool) -> Bool {
        let contentView = view

        if browserMode {
            // Find all OptionalEnclosure views and record original frames
            let enclosures = findOptionalEnclosures(in: contentView)
            enterBrowserMode(enclosures: enclosures)

            // Check if there are any visible controls remaining
            return hasVisibleControls(in: contentView)
        } else {
            // Restore all original frames and show enclosures
            exitBrowserMode()
            return true // Always has controls in terminal mode
        }
    }
}

    // MARK: - Private Methods
extension iTermProfilePreferencesBaseViewController {
    private func findOptionalEnclosures(in view: NSView) -> [OptionalEnclosure] {
        var enclosures: [OptionalEnclosure] = []

        // If this is an NSTabView, search all tab views (not just the active one)
        if let tabView = view as? NSTabView {
            for tabViewItem in tabView.tabViewItems {
                if let tabView = tabViewItem.view {
                    enclosures.append(contentsOf: findOptionalEnclosures(in: tabView))
                }
            }
        } else if let enclosure = view as? OptionalEnclosure {
            enclosures.append(enclosure)
        } else {
            for subview in view.subviews {
                enclosures.append(contentsOf: findOptionalEnclosures(in: subview))
            }
        }

        return enclosures
    }
    
    private func enterBrowserMode(enclosures: [OptionalEnclosure]) {
        var originalFrames: [NSView: NSRect] = [:]
        var viewAdjustments: [NSView: CGFloat] = [:]
        
        // Sort enclosures by y position (top to bottom) to process them in correct order
        let sortedEnclosures = enclosures.sorted { $0.frame.origin.y > $1.frame.origin.y }
        
        // First pass: Record original frames for all enclosures and their siblings
        for enclosure in sortedEnclosures {
            guard !enclosure.isHidden else { continue }
            
            // Record original frame of the enclosure
            originalFrames[enclosure] = enclosure.frame
            
            // Record original frames for all sibling views
            if let superview = enclosure.superview {
                for subview in superview.subviews {
                    if originalFrames[subview] == nil {
                        originalFrames[subview] = subview.frame
                    }
                }
            }
        }
        
        // Second pass: Calculate adjustments for each enclosure
        for enclosure in sortedEnclosures {
            guard !enclosure.isHidden else { continue }
            
            let enclosureHeight = enclosure.frame.height
            let enclosureMinY = enclosure.frame.origin.y
            
            // Find all sibling views that are below this enclosure
            if let superview = enclosure.superview {
                for subview in superview.subviews {
                    // Skip OptionalEnclosure views
                    if subview is OptionalEnclosure {
                        continue
                    }
                    
                    // Check if this view is below the threshold (using original frame)
                    let originalY = originalFrames[subview]!.origin.y
                    if originalY < enclosureMinY {
                        // Accumulate the adjustment
                        viewAdjustments[subview] = (viewAdjustments[subview] ?? 0) + enclosureHeight
                    }
                }
            }
        }
        
        // Third pass: Hide enclosures and apply all adjustments at once
        for enclosure in sortedEnclosures {
            guard !enclosure.isHidden else { continue }
            enclosure.isHidden = true
        }
        
        // Apply all view adjustments
        for (view, adjustment) in viewAdjustments {
            var frame = originalFrames[view]!
            frame.origin.y += adjustment
            view.frame = frame
        }
        
        // Handle nested tab views - remove tabs that have no visible controls
        let removedTabs = handleNestedTabViews(in: view)
        
        // Adjust the flipped view height if we're in a scroll view
        adjustFlippedViewHeight(for: enclosures)
        
        // Store original frames, enclosures, and removed tabs for restoration
        if internalState[Self.originalFramesKey] == nil {
            internalState[Self.originalFramesKey] = originalFrames
            internalState[Self.optionalEnclosuresKey] = enclosures
            internalState[Self.removedTabsKey] = removedTabs
        }
    }
    
    private func exitBrowserMode() {
        guard let originalFrames = internalState[Self.originalFramesKey] as? [NSView: NSRect],
              let enclosures = internalState[Self.optionalEnclosuresKey] as? [OptionalEnclosure] else {
            return
        }
        
        // Restore nested tab views first
        if let removedTabs = internalState[Self.removedTabsKey] as? [[String: Any]] {
            restoreNestedTabViews(removedTabs: removedTabs)
        }
        
        // Restore the flipped view height if we're in a scroll view
        restoreFlippedViewHeight()

        // Restore all original frames
        for (view, originalFrame) in originalFrames {
            view.frame = originalFrame
        }
        
        // Show all enclosures
        for enclosure in enclosures {
            enclosure.isHidden = false
        }
        
        // Clean up stored data
        internalState.removeObject(forKey: Self.originalFramesKey)
        internalState.removeObject(forKey: Self.optionalEnclosuresKey)
        internalState.removeObject(forKey: Self.removedTabsKey)
    }
    
    private func hasVisibleControls(in view: NSView) -> Bool {
        // If this view is an OptionalEnclosure and it's hidden, skip it
        if let enclosure = view as? OptionalEnclosure, enclosure.isHidden {
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
    
    private func adjustFlippedViewHeight(for enclosures: [OptionalEnclosure]) {
        guard let flippedView = findFlippedView() else { return }
        
        // Calculate total height reduction from hidden enclosures
        let totalHeightReduction = enclosures.reduce(0) { total, enclosure in
            return enclosure.isHidden ? total + enclosure.frame.height : total
        }
        
        // Store original flipped view frame if not already stored
        let flippedViewFrameKey = "iTermOriginalFlippedViewFrame"
        if internalState[flippedViewFrameKey] == nil {
            internalState[flippedViewFrameKey] = NSValue(rect: flippedView.frame)
        }
        
        // Adjust the flipped view height
        var flippedFrame = flippedView.frame
        flippedFrame.size.height -= totalHeightReduction
        flippedView.frame = flippedFrame
    }
    
    private func restoreFlippedViewHeight() {
        guard let flippedView = findFlippedView() else { return }
        
        let flippedViewFrameKey = "iTermOriginalFlippedViewFrame"
        guard let originalFrameValue = internalState[flippedViewFrameKey] as? NSValue else { return }
        
        // Restore original flipped view frame
        flippedView.frame = originalFrameValue.rectValue
        
        // Clean up stored frame
        internalState.removeObject(forKey: flippedViewFrameKey)
    }
    
    private func findFlippedView() -> iTermFlippedView? {
        // Navigate up the view hierarchy to find the flipped view
        // Structure: view -> iTermFlippedView -> NSScrollView -> iTermSizeRememberingView
        var currentView: NSView? = view
        
        // Go up to find iTermFlippedView
        while let parentView = currentView?.superview {
            if let flippedView = parentView as? iTermFlippedView {
                return flippedView
            }
            currentView = parentView
        }
        
        return nil
    }
    
    private func handleNestedTabViews(in rootView: NSView) -> [[String: Any]] {
        var removedTabs: [[String: Any]] = []
        findAndProcessNestedTabViews(in: rootView, removedTabs: &removedTabs)
        return removedTabs
    }
    
    private func findAndProcessNestedTabViews(in view: NSView, removedTabs: inout [[String: Any]]) {
        // If this view is a tab view, check if any tabs should be removed
        if let tabView = view as? NSTabView {
            var tabsToRemove: [NSTabViewItem] = []
            
            for tabViewItem in tabView.tabViewItems {
                if var tabContentView = tabViewItem.view {
                    if tabContentView.subviews.count == 1 {
                        tabContentView = tabContentView.subviews[0]
                    }

                    // Check if this tab has any visible controls
                    if !hasVisibleControls(in: tabContentView) {
                        tabsToRemove.append(tabViewItem)
                    }
                }
            }
            
            // Remove tabs that have no visible controls and store them for restoration
            for (index, tabViewItem) in tabsToRemove.enumerated() {
                let originalIndex = tabView.tabViewItems.firstIndex(of: tabViewItem) ?? 0
                
                // Store tab information for restoration
                let tabInfo: [String: Any] = [
                    "tabView": tabView,
                    "tabViewItem": tabViewItem,
                    "originalIndex": originalIndex
                ]
                removedTabs.append(tabInfo)
                
                // Remove the tab
                tabView.removeTabViewItem(tabViewItem)
            }
        }
        
        // Recursively check subviews
        for subview in view.subviews {
            findAndProcessNestedTabViews(in: subview, removedTabs: &removedTabs)
        }
        
        // Also check tab views for their tab contents
        if let tabView = view as? NSTabView {
            for tabViewItem in tabView.tabViewItems {
                if let tabContentView = tabViewItem.view {
                    findAndProcessNestedTabViews(in: tabContentView, removedTabs: &removedTabs)
                }
            }
        }
    }
    
    private func restoreNestedTabViews(removedTabs: [[String: Any]]) {
        // Restore tabs in reverse order to maintain proper indices
        for tabInfo in removedTabs.reversed() {
            guard let tabView = tabInfo["tabView"] as? NSTabView,
                  let tabViewItem = tabInfo["tabViewItem"] as? NSTabViewItem,
                  let originalIndex = tabInfo["originalIndex"] as? Int else {
                continue
            }
            
            // Insert the tab back at its original index
            let insertIndex = min(originalIndex, tabView.tabViewItems.count)
            tabView.insertTabViewItem(tabViewItem, at: insertIndex)
        }
    }
}
