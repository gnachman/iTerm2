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
        let sessionSize = windowSizeHelper.sessionSize(
            profile: session.profile,
            existingViewSize: currentSession()?.view?.scrollview?.documentVisibleRect.size,
            desiredPointSize: size?.pointee,
            hasScrollbar: scrollbarShouldBeVisible(),
            scrollerStyle: scrollerStyle(),
            rightExtra: currentSession()?.desiredRightExtra() ?? 0.0,
            screenSize: screenSize)
        windowSizeHelper.updateDesiredSize(sessionSize.desiredSize)
        if session.setScreenSize(sessionSize.pointSize,
                                 parent: self) {
            DLog("setupSession - call safelySetSessionSize")
            safelySetSessionSize(session,
                                 rows: sessionSize.gridSize.height,
                                 columns: sessionSize.gridSize.width)

            DLog("setupSession - call setPreferencesFromAddressBookEntry")
            session.setPreferencesFromAddressBookEntry(session.profile)
            session.loadInitialColorTableAndResetCursorGuide()
            session.screen.resetTimestamps()
        }
    }
}

// MARK: - Tab Color Picker (ColorsMenuItemViewDelegate)

/// Private helper that holds mutable state for the tab color picker.
/// Attached to PseudoTerminal via an associated object so Swift extensions
/// can have stored properties without touching the ObjC ivar layout.
private class TabColorPickerState: NSObject {
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
private let kUseSystemColorPickerKey = "kCPKUseSystemColorPicker"

private var tabColorPickerStateKey: UInt8 = 0

extension PseudoTerminal: ColorsMenuItemViewDelegate {

    private var pickerState: TabColorPickerState {
        if let state = objc_getAssociatedObject(self, &tabColorPickerStateKey) as? TabColorPickerState {
            return state
        }
        let state = TabColorPickerState()
        objc_setAssociatedObject(self, &tabColorPickerStateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }

    // MARK: - ColorsMenuItemViewDelegate

    public func colorsMenuItemViewDidRequestColorPicker(_ view: ColorsMenuItemView!) {
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

    /// Builds the accessory view for NSColorPanel with a \u{201C}Default Picker\u{201D} button and recent color swatches.
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
            let label = NSTextField(labelWithString: "Recent Tab Colors")
            label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.sizeToFit()
            let labelY = totalHeight + vPadding + swatchSize + 4
            label.frame = NSMakeRect(hPadding, labelY, label.frame.width, labelHeight)
            container.addSubview(label)

            totalHeight = labelY + labelHeight + vPadding
        }

        // \u{201C}Default Picker\u{201D} button above the recent colors
        let cpkBundle = Bundle(for: CPKPopover.self)
        let image = cpkBundle.image(forResource: "ActiveEscapeHatch")
        let buttonY = totalHeight + kSectionSpacing
        let button = NSButton(frame: NSMakeRect(0, buttonY, 0, 0))
        button.isBordered = false
        button.image = image
        button.title = "Default Picker"
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
        guard let tab = targetTab() else { return }
        for session in tab.sessions() {
            guard let ptySession = session as? PTYSession else { continue }
            ptySession.tabColor = color
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

    /// Finds the frame of the target tab\u{2019}s cell in the tab bar for popover anchoring.
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
}
