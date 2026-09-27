//
//  PseudoTerminal.swift
//  iTerm2
//
//  Created by George Nachman on 7/28/25.
//

import ColorPicker

@objc
extension PseudoTerminal {
    // Set the session's profile dictionary and initialize its screen and name. Sets the
    // window title to the session's name. If size is not nil then the session is initialized to fit
    // a view of that size; otherwise the size is derived from the existing window if there is already
    // an open tab, or its bookmark's preference if it's the first session in the window.
    @objc(setupSessionImpl:screenSize:withSize:)
    func setup(session: PTYSession,
               screenSize: NSSize,
               size: UnsafePointer<NSSize>?) {
        let existingViewSize = currentSession()?.view?.scrollview.documentVisibleRect.size
        let sessionSize = windowSizeHelper.sessionSize(
            profile: session.justProfile,
            existingViewSize: existingViewSize,
            desiredPointSize: size?.pointee,
            hasScrollbar: scrollbarShouldBeVisible(),
            scrollerStyle: scrollerStyle(),
            rightExtra: currentSession()?.desiredRightExtra() ?? 0.0,
            screenSize: screenSize)
        // Only seed the window’s desired size from a session’s profile when this is the
        // first session of a brand-new window (no existing tab to measure). Adding a tab
        // to an existing window must not re-seed desiredColumns/desiredRows from the new
        // tab’s profile: a later canonicalizeWindowFrame (e.g. triggered by a screen or
        // display-configuration change) reads those values and would resize the window to
        // the tab’s profile width instead of preserving the window’s own width. Issue 12917.
        if existingViewSize == nil {
            windowSizeHelper.updateDesiredSize(sessionSize.desiredSize)
        }
        if session.setScreenSize(sessionSize.pointSize,
                                 parent: self) {
            DLog("setupSession - call safelySetSessionSize")
            safelySetSessionSize(session,
                                 rows: sessionSize.gridSize.height,
                                 columns: sessionSize.gridSize.width)

            DLog("setupSession - call setPreferencesFromAddressBookEntry")
            session.setPreferencesFromAddressBookEntry(session.justProfile)
            session.loadInitialColorTableAndResetCursorGuide()
            session.screen.resetTimestamps()
        }
    }
}

// MARK: - Tab Color Picker (ColorsMenuItemViewDelegate)

/// Holds mutable state for the tab color picker.
/// Stored as a property on PseudoTerminal (declared in PseudoTerminal.h).
@objc class TabColorPickerState: NSObject {
    var popover: CPKPopover?
    var debounceTimer: Timer?
    var pendingRecentColor: NSColor?

    func invalidate() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        pendingRecentColor = nil
        if NSColorPanel.sharedColorPanelExists {
            let panel = NSColorPanel.shared
            if panel.accessoryView?.identifier == kTabColorAccessoryViewID {
                panel.accessoryView = nil
                panel.setTarget(nil)
                panel.setAction(nil)
            }
        }
    }
}

/// Identifier used to recognize our accessory view in NSColorPanel.
private let kTabColorAccessoryViewID = NSUserInterfaceItemIdentifier("iTermTabColorAccessory")

/// Mirrors the kCPKUseSystemColorPicker constant from CPKControlsView.h (not public).
/// Must use UserDefaults.standard rather than iTermUserDefaults: ColorPicker
/// reads and writes this key against standardUserDefaults and has no awareness
/// of -suite, so a custom suite would desynchronize the two sides.
private let kUseSystemColorPickerKey = "kCPKUseSystemColorPicker"

extension PseudoTerminal: ColorsMenuItemViewDelegate {

    private var pickerState: TabColorPickerState {
        if let state = tabColorPickerState {
            return state
        }
        let state = TabColorPickerState()
        tabColorPickerState = state
        return state
    }

    // MARK: - ColorsMenuItemViewDelegate

    // What a color picker opened from a menu's swatch row should recolor: the
    // menu item's representedObject is a group id (group context menu) or an
    // NSTabViewItem (tab context menu). Pure so it can be unit tested.
    enum TabColorPickerTarget: Equatable {
        case group(String)
        case tab(NSTabViewItem)
    }

    static func colorPickerTarget(for item: NSMenuItem?) -> TabColorPickerTarget? {
        if let groupID = item?.representedObject as? String {
            return .group(groupID)
        }
        if let tabViewItem = item?.representedObject as? NSTabViewItem {
            return .tab(tabViewItem)
        }
        return nil
    }

    public func colorsMenuItemViewDidRequestColorPicker(_ view: ColorsMenuItemView!) {
        // Capture the picker's target from the menu item the swatch view lives
        // in, at the moment the picker opens. The pickers (popover and shared
        // NSColorPanel) outlive the menu, so binding the target when a menu was
        // merely built would leave a stale target behind: a panel opened for a
        // single tab would silently start recoloring whichever group's context
        // menu was opened (and dismissed untouched) last.
        switch PseudoTerminal.colorPickerTarget(for: view.enclosingMenuItem) {
        case .group(let groupID):
            tabGroupIDForColorPicker = groupID
            tabViewItemForColorPicker = tabs(inGroup: groupID).first?.tabViewItem
        case .tab(let tabViewItem):
            tabGroupIDForColorPicker = nil
            tabViewItemForColorPicker = tabViewItem
        case nil:
            break
        }
        if UserDefaults.standard.bool(forKey: kUseSystemColorPickerKey) {
            showSystemTabColorPicker()
        } else {
            showCustomTabColorPicker()
        }
    }

    // MARK: - Cleanup

    /// Called from ObjC dealloc to clean up color picker state.
    @objc func cleanUpTabColorPicker() {
        pickerState.invalidate()
    }

    // MARK: - Custom Picker (CPKPopover)

    private func showCustomTabColorPicker() {
        let tab = targetTab()
        let currentColor = tab?.activeSession?.tabColor ?? NSColor.gray
        guard let tabBar = tabBarControl() else { return }
        let anchorRect = rectOfTab(in: tabBar)

        let state = pickerState
        state.popover = CPKPopover.presentRelative(
            to: anchorRect,
            of: tabBar,
            preferredEdge: .maxY,
            initialColor: currentColor,
            colorSpace: NSColorSpace.it_default(),
            options: [],
            selectionDidChange: { [weak self] (color: NSColor?) in
                guard let self, let color else { return }
                self.applyTabColor(color)
                self.debounceRecentColorSave(color)
            },
            useSystemColorPicker: { [weak self] in
                guard let self else { return }
                self.pickerState.popover?.close()
                self.pickerState.popover = nil
                UserDefaults.standard.set(true, forKey: kUseSystemColorPickerKey)
                self.showSystemTabColorPicker()
            }
        )
    }

    // MARK: - System Picker (NSColorPanel)

    private func showSystemTabColorPicker() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false

        let tab = targetTab()
        if let currentColor = tab?.activeSession?.tabColor {
            panel.color = currentColor
        }

        panel.accessoryView = buildSystemPickerAccessoryView(panelWidth: panel.contentView?.bounds.width ?? 300)
        panel.setTarget(self)
        panel.setAction(#selector(tabColorPanelDidSelectColor(_:)))
        panel.orderFront(nil)
    }

    /// Builds the accessory view for NSColorPanel with a “Default Picker” button and recent color swatches.
    private func buildSystemPickerAccessoryView(panelWidth: CGFloat) -> NSView {
        let kBottomMargin: CGFloat = 8
        let kSectionSpacing: CGFloat = 12

        let container = NSView(frame: .zero)
        container.identifier = kTabColorAccessoryViewID

        var totalHeight: CGFloat = kBottomMargin

        // Recent tab colors row (placed at the bottom of the accessory view)
        let recentColors = iTermRecentTabColors.shared.recentColors
        if !recentColors.isEmpty {
            let swatchSize: CGFloat = 14
            let spacing: CGFloat = 2
            let hPadding: CGFloat = 12
            let vPadding: CGFloat = 6
            let labelHeight: CGFloat = 14

            // Swatches
            for (i, color) in recentColors.enumerated() {
                let x = hPadding + CGFloat(i) * (swatchSize + spacing)
                let swatch = NSButton(frame: NSMakeRect(x, totalHeight + vPadding, swatchSize, swatchSize))
                swatch.isBordered = false
                swatch.title = ""
                swatch.wantsLayer = true
                swatch.layer?.backgroundColor = color.cgColor
                swatch.layer?.cornerRadius = 3
                swatch.layer?.borderWidth = 1
                swatch.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
                swatch.tag = i
                swatch.target = self
                swatch.action = #selector(recentColorSwatchClicked(_:))
                container.addSubview(swatch)
            }

            // Label above swatches
            let label = NSTextField(labelWithString: String(localized: "PseudoTerminal.RecentTabColors", defaultValue: "Recent Tab Colors", comment: "Label above the recently used tab colors"))
            label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.sizeToFit()
            let labelY = totalHeight + vPadding + swatchSize + 4
            label.frame = NSMakeRect(hPadding, labelY, label.frame.width, labelHeight)
            container.addSubview(label)

            totalHeight = labelY + labelHeight + vPadding
        }

        // “Default Picker” button above the recent colors
        let cpkBundle = Bundle(for: CPKPopover.self)
        let image = cpkBundle.image(forResource: "ActiveEscapeHatch")
        let buttonY = totalHeight + kSectionSpacing
        let button = NSButton(frame: NSMakeRect(0, buttonY, 0, 0))
        button.isBordered = false
        button.image = image
        button.title = String(localized: "PseudoTerminal.DefaultPicker", defaultValue: "Default Picker", comment: "Button to switch to the custom color picker")
        button.imagePosition = .imageAbove
        button.target = self
        button.action = #selector(switchToCustomPicker(_:))
        button.sizeToFit()
        container.addSubview(button)

        totalHeight = NSMaxY(button.frame) + kBottomMargin

        container.frame = NSMakeRect(0, 0, max(panelWidth, 300), totalHeight)
        container.autoresizingMask = .width
        return container
    }

    @objc private func switchToCustomPicker(_ sender: Any?) {
        UserDefaults.standard.set(false, forKey: kUseSystemColorPickerKey)
        NSColorPanel.shared.close()
        NSColorPanel.shared.accessoryView = nil
        showCustomTabColorPicker()
    }

    @objc private func recentColorSwatchClicked(_ sender: NSButton) {
        let recentColors = iTermRecentTabColors.shared.recentColors
        guard sender.tag < recentColors.count else { return }

        let color = recentColors[sender.tag]
        applyTabColor(color)
        iTermRecentTabColors.shared.addColor(color)
        NSColorPanel.shared.orderOut(nil)
    }

    @objc private func tabColorPanelDidSelectColor(_ panel: NSColorPanel) {
        let color = panel.color
        applyTabColor(color)
        debounceRecentColorSave(color)
    }

    // MARK: - Shared Helpers

    private func targetTab() -> PTYTab? {
        return (tabViewItemForColorPicker?.identifier as? PTYTab) ?? currentTab()
    }

    private func applyTabColor(_ color: NSColor) {
        // When the picker was opened for a group (its members share one color),
        // apply to the whole group instead of a single tab.
        if let groupID = tabGroupIDForColorPicker, !groupID.isEmpty {
            setTabGroupColor(color, forGroupID: groupID)
            return
        }
        guard let tab = targetTab() else { return }
        for session in tab.sessions() {
            session.tabColor = color
        }
        updateTabColors()
    }

    private func debounceRecentColorSave(_ color: NSColor) {
        let state = pickerState
        state.debounceTimer?.invalidate()
        state.pendingRecentColor = color
        state.debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            guard let self else { return }
            let st = self.pickerState
            if let pending = st.pendingRecentColor {
                iTermRecentTabColors.shared.addColor(pending)
                st.pendingRecentColor = nil
                // Refresh the accessory view if the system picker is open.
                if NSColorPanel.sharedColorPanelExists,
                   NSColorPanel.shared.accessoryView?.identifier == kTabColorAccessoryViewID {
                    NSColorPanel.shared.accessoryView = self.buildSystemPickerAccessoryView(
                        panelWidth: NSColorPanel.shared.contentView?.bounds.width ?? 300)
                }
            }
            st.debounceTimer = nil
        }
    }

    /// Finds the frame of the target tab’s cell in the tab bar for popover anchoring.
    private func rectOfTab(in tabBar: PSMTabBarControl) -> NSRect {
        let targetItem = tabViewItemForColorPicker ?? currentTab()?.tabViewItem
        guard targetItem != nil else { return tabBar.bounds }

        // Scan across the tab bar to find the cell whose representedObject matches.
        let midY = tabBar.bounds.midY
        var probeX: CGFloat = 1
        while probeX < tabBar.bounds.width {
            var frame = NSRect.zero
            if let cell = tabBar.cell(for: NSMakePoint(probeX, midY),
                                      cellFrame: &frame) as? PSMTabBarCell {
                if cell.representedObject as AnyObject === targetItem {
                    return frame
                }
                // Skip past this cell to the next one.
                probeX = NSMaxX(frame) + 1
            } else {
                probeX += 20
            }
        }
        return tabBar.bounds
    }

    // MARK: - Pinned Tabs

    @objc func togglePinTab(_ sender: Any?) {
        var tab: PTYTab?
        if let menuItem = sender as? NSMenuItem,
           let tabViewItem = menuItem.representedObject as? NSTabViewItem {
            tab = tabViewItem.identifier as? PTYTab
        }
        if tab == nil {
            tab = currentTab()
        }
        guard let tab else {
            return
        }
        if tab.tmuxController() != nil {
            return
        }
        let newPinned = !tab.isPinned
        if let gid = tab.tabGroupID, !gid.isEmpty {
            let members = tabs(inGroup: gid) ?? []
            // Pin/unpin the whole group as a block so it stays entirely pinned or
            // entirely unpinned. Pinning only one member would strand it across
            // the pinned/unpinned boundary and split the group (non-contiguous).
            // Pinning is unavailable for tmux tabs, so if any member is a tmux tab
            // we cannot pin the block: refuse the whole toggle, mirroring the
            // per-tab guard above and the context menu (disabled for tmux tabs).
            if members.contains(where: { $0.tmuxController() != nil }) {
                return
            }
            for member in members where member.isPinned != newPinned {
                member.isPinned = newPinned
            }
            // Each isPinned change reorders that tab to the pinned/unpinned boundary
            // and runs the contiguity pass as a side effect -- but only when the tab
            // actually moves. The last member toggled can already sit at the
            // boundary (no move -> no reorder -> no contiguity pass), which strands
            // the group split across the boundary until some later reorder. Enforce
            // contiguity once here, after the whole group's pin state is settled, so
            // the members always end up contiguous.
            tabsDidReorder()
        } else {
            tab.isPinned = newPinned
        }
    }

    // Delegate method call forwarded from main class.
    @objc(_tab:didChangePinnedState:) func tab(_ tab: PTYTab, didChangePinnedState pinned: Bool) {
        guard let tabViewItem = tab.tabViewItem else { return }
        tabBarControl()?.setIsPinned(pinned, for: tabViewItem)

        // Reorder the tab to maintain pinned-left / unpinned-right invariant.
        guard let allTabs = tabs() else { return }
        guard let currentIndex = allTabs.firstIndex(where: { $0 === tab }) else { return }

        // Find the boundary: last pinned tab (excluding the tab being toggled).
        var lastPinnedIndex = -1
        for (i, t) in allTabs.enumerated() where t.isPinned && t !== tab {
            lastPinnedIndex = i
        }
        let targetIndex = lastPinnedIndex + 1
        if currentIndex != targetIndex {
            moveTab(at: currentIndex, to: targetIndex)
        }
    }
}
