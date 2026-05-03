//
//  iTermRightGutterController.swift
//  iTerm2SharedARC
//
//  Per-SessionView controller for right-gutter panels. Owns the ordered,
//  lazily-created set of live panel instances for one session and manages
//  their layout as SessionView subviews positioned in the rightExtra strip.
//

import AppKit
import Foundation

// Vertical 1pt separator drawn between adjacent right-gutter panels. Uses
// NSColor.separatorColor so it adapts to dark/light mode and matches the
// system divider styling used elsewhere in the app.
final class iTermRightGutterDividerView: NSView {
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@objc(iTermRightGutterController)
class iTermRightGutterController: NSObject, iTermRightGutterPanelDelegate {
    private weak var sessionView: SessionView?
    private var panels: [iTermRightGutterPanel] = []
    // Mirrors panels' identifiers in order; used for diffing against the
    // registry's enabled list.
    private var panelIdentifiers: [String] = []

    // Hairline vertical separators drawn between adjacent visible panels.
    // Pooled and re-used across layout passes; unused dividers are hidden
    // rather than removed.
    private var dividers: [iTermRightGutterDividerView] = []
    // Hairline drawn along the left edge of the gutter as a whole (between
    // the cell grid / timestamps slot and the leftmost visible panel).
    // Lazily attached on first use.
    private var leadingDivider: iTermRightGutterDividerView?
    private static let dividerWidth: CGFloat = 1

    @objc(initWithSessionView:)
    init(sessionView: SessionView) {
        self.sessionView = sessionView
        super.init()
        // Advanced settings can change panel widths or enable/disable panels
        // without going through setProfile:. Catch those so the right-extra
        // budget stays in sync.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(advancedSettingsDidChange(_:)),
            name: NSNotification.Name(rawValue: iTermAdvancedSettingsDidChange),
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        for panel in panels {
            panel.panelDelegate = nil
            panel.view.removeFromSuperview()
            panel.detach()
        }
        for divider in dividers {
            divider.removeFromSuperview()
        }
        leadingDivider?.removeFromSuperview()
    }

    // MARK: - Public

    @objc func layoutPanels() {
        guard let sessionView = sessionView,
              let session = sessionView.delegate as? PTYSession else {
            return
        }
        // PTYSession.view can be assigned before the session's profile is
        // populated (e.g., during arrangement restore in tmux -CC). Skip
        // until the profile is in place; SessionView.updateLayout will
        // re-fire once setProfile: lands.
        guard let profile = session.profile else {
            return
        }
        syncPanels(forSession: session, profile: profile)
        positionPanels(in: sessionView)
    }

    @objc func detachAll() {
        for panel in panels {
            panel.panelDelegate = nil
            panel.view.removeFromSuperview()
            panel.detach()
        }
        panels.removeAll()
        panelIdentifiers.removeAll()
        for divider in dividers {
            divider.removeFromSuperview()
        }
        dividers.removeAll()
        leadingDivider?.removeFromSuperview()
        leadingDivider = nil
    }

    // MARK: - Notifications

    @objc private func advancedSettingsDidChange(_ notification: Notification) {
        guard let sessionView = sessionView,
              let session = sessionView.delegate as? PTYSession,
              let view = session.view,
              session.profile != nil else {
            return
        }
        if view.actualRightExtra != session.desiredRightExtra() {
            session.delegate?.realParentWindow()?.rightExtraDidChange()
        } else {
            layoutPanels()
        }
    }

    // MARK: - Sync

    // `profile` is `Profile` in ObjC, which is a preprocessor #define for
    // NSDictionary that Swift can't see — Swift bridges it to a Dictionary.
    private func syncPanels(forSession session: PTYSession, profile: [AnyHashable: Any]) {
        let registry = iTermRightGutterPanelRegistry.sharedInstance()
        let desired = registry.enabledPanelIdentifiers(forProfile: profile, session: session)
        if desired == panelIdentifiers {
            return
        }
        let desiredSet = Set(desired)
        var byID: [String: iTermRightGutterPanel] = [:]
        for panel in panels {
            if desiredSet.contains(panel.panelIdentifier) {
                byID[panel.panelIdentifier] = panel
            } else {
                panel.panelDelegate = nil
                panel.view.removeFromSuperview()
                panel.detach()
            }
        }

        guard let sessionView = sessionView else {
            return
        }

        var survivors: [iTermRightGutterPanel] = []
        for identifier in desired {
            var panel = byID[identifier]
            if panel == nil {
                guard let newPanel = registry.createPanel(withIdentifier: identifier) else {
                    continue
                }
                newPanel.panelDelegate = self
                newPanel.attach(to: session)
                // Hosted as a SessionView subview (above the scrollview and
                // the legacy/metal rendering siblings) so neither renderer
                // can overdraw the panel — including the alternate-screen
                // background extension that fills the right margin. Panels
                // that want background drawing to show through (e.g. via
                // NSVisualEffectView) opt in themselves.
                sessionView.addSubview(belowFind: newPanel.view)
                panel = newPanel
            }
            if let panel = panel {
                survivors.append(panel)
            }
        }
        panels = survivors
        panelIdentifiers = survivors.map { $0.panelIdentifier }
    }

    // MARK: - Layout

    private func positionPanels(in sessionView: SessionView) {
        let scrollview = sessionView.scrollview
        // Express the panel area in SessionView coordinates so panels can be
        // hosted as SessionView subviews. The cell grid's right edge sits at
        // (scrollview content right) - rightExtra; panels occupy the inner
        // portion of the rightExtra strip, with any timestamp slot to their
        // right (timestamps right-align against the content's right edge).
        let contentFrameInScroll = scrollview.contentView.frame
        let contentFrameInSession = sessionView.convert(contentFrameInScroll, from: scrollview)
        // Panels live on the OUTER side of the rightExtra strip (against the
        // scrollbar). The timestamp slot, if any, sits between the cell grid
        // and the inner edge of the panel area.
        let panelReservation = sessionView.actualPanelReservation
        var x = contentFrameInSession.maxX - panelReservation
        let y = contentFrameInSession.minY
        let height = contentFrameInSession.height

        var visiblePanelIndices: [Int] = []
        for (i, panel) in panels.enumerated() {
            // Always advance `x` by `panel.width` even when hidden, so a panel
            // that goes invisible without zeroing its widthProvider (e.g.
            // during a slide-in/out animation) leaves its slot intact rather
            // than being slid into by neighbors. To free the slot for real,
            // the panel's widthProvider must return 0 — which removes the
            // panel from the width budget too.
            let width = panel.width
            if panel.visible {
                panel.view.isHidden = false
                panel.view.frame = NSRect(x: x, y: y, width: width, height: height)
                visiblePanelIndices.append(i)
            } else {
                panel.view.isHidden = true
            }
            x += width
        }

        positionDividers(visiblePanelIndices: visiblePanelIndices,
                         y: y,
                         height: height,
                         in: sessionView)
        positionLeadingDivider(visiblePanelIndices: visiblePanelIndices,
                               gutterMinX: contentFrameInSession.maxX - panelReservation,
                               y: y,
                               height: height,
                               in: sessionView)
    }

    // Hairline drawn along the left edge of the gutter strip as a whole,
    // visible whenever the gutter contains any visible panel. Sits flush
    // with the leftmost panel's left edge — one pixel wide, overlapping
    // the panel's leading edge for the same reason as inter-panel
    // dividers (no width-budget plumbing required).
    private func positionLeadingDivider(visiblePanelIndices: [Int],
                                        gutterMinX: CGFloat,
                                        y: CGFloat,
                                        height: CGFloat,
                                        in sessionView: SessionView) {
        guard let firstIndex = visiblePanelIndices.first else {
            leadingDivider?.isHidden = true
            return
        }
        if leadingDivider == nil {
            let divider = iTermRightGutterDividerView()
            sessionView.addSubview(belowFind: divider)
            leadingDivider = divider
        }
        guard let divider = leadingDivider else {
            return
        }
        // Anchor to the first visible panel rather than gutterMinX so the
        // divider tracks the panel exactly even if upstream rounding nudges
        // its frame; gutterMinX is only used as the effective fallback when
        // the panel hasn't been positioned yet.
        let x = panels[firstIndex].view.frame.minX.isFinite
            ? panels[firstIndex].view.frame.minX
            : gutterMinX
        divider.frame = NSRect(x: x, y: y, width: Self.dividerWidth, height: height)
        divider.isHidden = false
        // Re-add to push to the end of the subview list so it draws above
        // its panel neighbor.
        sessionView.addSubview(belowFind: divider)
    }

    // Hairline divider between consecutive visible panels. Drawn as an
    // overlay above the panels — it overlaps the leftmost dividerWidth pt
    // of the right panel rather than reserving budget space, which would
    // require plumbing through PTYSession.desiredRightExtraForProfile.
    private func positionDividers(visiblePanelIndices: [Int],
                                  y: CGFloat,
                                  height: CGFloat,
                                  in sessionView: SessionView) {
        let neededDividerCount = max(visiblePanelIndices.count - 1, 0)
        while dividers.count < neededDividerCount {
            let divider = iTermRightGutterDividerView()
            sessionView.addSubview(belowFind: divider)
            dividers.append(divider)
        }
        for (slot, divider) in dividers.enumerated() {
            if slot < neededDividerCount {
                let rightPanel = panels[visiblePanelIndices[slot + 1]]
                let frame = NSRect(x: rightPanel.view.frame.minX,
                                   y: y,
                                   width: Self.dividerWidth,
                                   height: height)
                divider.frame = frame
                divider.isHidden = false
                // Re-add so the divider is at the end of the subview list
                // (and therefore drawn above the just-positioned panels).
                sessionView.addSubview(belowFind: divider)
            } else {
                divider.isHidden = true
            }
        }
    }

    // MARK: - iTermRightGutterPanelDelegate

    func rightGutterPanelDidChangeWidthOrVisibility(_ panel: iTermRightGutterPanel) {
        guard let sessionView = sessionView,
              let session = sessionView.delegate as? PTYSession,
              let view = session.view,
              session.profile != nil else {
            return
        }
        // The registry's totalWidthForProfile reads the same prefs the panels
        // use, so the next time desiredRightExtra is evaluated it will reflect
        // the new width. Notify the parent window to rerun the layout cascade.
        if view.actualRightExtra != session.desiredRightExtra() {
            session.delegate?.realParentWindow()?.rightExtraDidChange()
        } else {
            // Width unchanged at the budget level (e.g., visibility toggle
            // that doesn't affect the configured width). Just relayout in
            // place.
            positionPanels(in: sessionView)
        }
    }
}
