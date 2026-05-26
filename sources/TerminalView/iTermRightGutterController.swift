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

// Vertical separator drawn between/around adjacent right-gutter panels. It is
// itself an iTermDragHandleView (the same view the toolbelt uses for its
// left-edge resize), so it handles its own mouse tracking and resize cursor.
// The visible 1pt hairline is drawn flush with the left edge (the panel
// boundary), while the wider, transparent body is the grab area: it overhangs
// into the panel so the resize affordance can't steal mouse events from the
// terminal grid or the neighboring panel. The owning controller is the drag
// handle's delegate and applies the width change.
final class iTermRightGutterDividerView: iTermDragHandleView {
    // Identifier of the panel whose width this divider adjusts (the panel
    // immediately to its right — every divider sits on the left edge of some
    // panel). nil makes the divider purely decorative and non-draggable.
    var resizablePanelIdentifier: String?

    static let lineWidth: CGFloat = 1
    static let grabWidth: CGFloat = 6

    // The visible hairline. A 1pt sublayer pinned to the left edge (the panel
    // boundary), leaving the rest of the view as a transparent grab area. A
    // layer-backed fill avoids the cost of a draw(_:) override; the view's own
    // backing layer would color the full grab width, so the line gets its own
    // sublayer.
    private let lineLayer = CALayer()

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        // The hairline is pinned to the left edge (the panel boundary) with a
        // fixed width and x; only its height tracks the view. Letting the
        // layer autoresize keeps that in sync without any per-layout frame
        // bookkeeping. (Height is the sole flexible part with both margins
        // fixed at 0, so it absorbs the full size delta even growing from the
        // initial zero frame.)
        lineLayer.autoresizingMask = [.layerHeightSizable]
        lineLayer.frame = CGRect(x: 0, y: 0, width: Self.lineWidth, height: bounds.height)
        updateLineColor()
        layer?.addSublayer(lineLayer)
    }

    private func updateLineColor() {
        // Resolve the dynamic system color against this view's appearance so
        // the cached CGColor matches dark/light mode.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            lineLayer.backgroundColor = NSColor.separatorColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLineColor()
    }

    override func resetCursorRects() {
        guard resizablePanelIdentifier != nil else {
            return
        }
        super.resetCursorRects()
    }

    // The resize cursor rect lives in this view's own coordinates, but the
    // divider is repositioned to a new window x on every layout pass, so the
    // window's cached rects must be rebuilt for it to keep showing the resize
    // cursor at its new location.
    func updateGrabCursorRects() {
        window?.invalidateCursorRects(for: self)
    }
}

@objc(iTermRightGutterController)
class iTermRightGutterController: NSObject, iTermRightGutterPanelDelegate, iTermDragHandleViewDelegate {
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
            let divider = iTermRightGutterDividerView(frame: .zero)
            divider.delegate = self
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
        // The leftmost visible panel's left edge: dragging this divider
        // resizes that panel.
        divider.resizablePanelIdentifier = panels[firstIndex].panelIdentifier
        divider.frame = NSRect(x: x, y: y,
                               width: iTermRightGutterDividerView.grabWidth, height: height)
        divider.isHidden = false
        // Re-add to push to the end of the subview list so it draws above
        // its panel neighbor.
        sessionView.addSubview(belowFind: divider)
        divider.updateGrabCursorRects()
    }

    // Hairline divider between consecutive visible panels. Drawn as an
    // overlay above the panels — its grab strip overlaps the leftmost pts of
    // the right panel rather than reserving budget space, which would require
    // plumbing through PTYSession.desiredRightExtraForProfile.
    private func positionDividers(visiblePanelIndices: [Int],
                                  y: CGFloat,
                                  height: CGFloat,
                                  in sessionView: SessionView) {
        let neededDividerCount = max(visiblePanelIndices.count - 1, 0)
        while dividers.count < neededDividerCount {
            let divider = iTermRightGutterDividerView(frame: .zero)
            divider.delegate = self
            sessionView.addSubview(belowFind: divider)
            dividers.append(divider)
        }
        for (slot, divider) in dividers.enumerated() {
            if slot < neededDividerCount {
                let rightPanel = panels[visiblePanelIndices[slot + 1]]
                // The divider is the right panel's left edge; dragging it
                // resizes that panel.
                divider.resizablePanelIdentifier = rightPanel.panelIdentifier
                let frame = NSRect(x: rightPanel.view.frame.minX,
                                   y: y,
                                   width: iTermRightGutterDividerView.grabWidth,
                                   height: height)
                divider.frame = frame
                divider.isHidden = false
                // Re-add so the divider is at the end of the subview list
                // (and therefore drawn above the just-positioned panels).
                sessionView.addSubview(belowFind: divider)
                divider.updateGrabCursorRects()
            } else {
                divider.isHidden = true
            }
        }
    }

    // MARK: - iTermRightGutterPanelDelegate

    func rightGutterPanelDidChangeWidthOrVisibility(_ panel: iTermRightGutterPanel) {
        relayoutAfterWidthChange()
    }

    // The registry's totalWidthForProfile reads the same store the panels'
    // widthProviders use, so the next time desiredRightExtra is evaluated it
    // reflects the new width. Notify the parent window to rerun the layout
    // cascade, or relayout in place when the budget is unchanged (e.g., a
    // visibility toggle that doesn't affect the configured width).
    private func relayoutAfterWidthChange() {
        guard let sessionView = sessionView,
              let session = sessionView.delegate as? PTYSession,
              let view = session.view,
              session.profile != nil else {
            return
        }
        if view.actualRightExtra != session.desiredRightExtra() {
            session.delegate?.realParentWindow()?.rightExtraDidChange()
        } else {
            positionPanels(in: sessionView)
        }
    }

    // MARK: - iTermDragHandleViewDelegate

    func dragHandleView(_ dragHandle: iTermDragHandleView, didMoveBy delta: CGFloat) -> CGFloat {
        guard let divider = dragHandle as? iTermRightGutterDividerView,
              let identifier = divider.resizablePanelIdentifier,
              let sessionView = sessionView,
              let panel = panels.first(where: { $0.panelIdentifier == identifier }) else {
            return 0
        }
        let before = panel.width
        // Dragging the handle right (delta > 0) shrinks the panel; left widens
        // it (the gutter is right-anchored, so a panel's left edge moves left
        // as it grows).
        let proposed = before - delta
        let after = min(maxResizableWidth(forIdentifier: identifier, in: sessionView),
                        max(iTermGutterPanelWidths.minWidth, proposed))
        if after != before {
            iTermGutterPanelWidths.setWidth(after, forIdentifier: identifier)
            relayoutAfterWidthChange()
        }
        // The handle moved right by however much the panel narrowed; reporting
        // this lets iTermDragHandleView make the handle "stick" at the clamp.
        return before - after
    }

    func dragHandleViewDidFinishMoving(_ dragHandle: iTermDragHandleView) {
        // Live dragging relayouts the visible session; make sure the final
        // size is committed across the window, mirroring the toolbelt's
        // toolbeltDidFinishGrowing.
        relayoutAfterWidthChange()
    }

    // Largest width this panel may take without crushing the terminal grid
    // below a usable minimum, holding the other panels and the timestamp slot
    // fixed. The other panels' widths come from the store (they don't change
    // during this drag) and the timestamp slot is stable, so this is robust to
    // the asynchronous right-extra relayout lagging a frame behind.
    private func maxResizableWidth(forIdentifier identifier: String,
                                   in sessionView: SessionView) -> CGFloat {
        let minTerminalWidth: CGFloat = 120
        guard let session = sessionView.delegate as? PTYSession,
              let view = session.view else {
            return iTermGutterPanelWidths.maxWidth
        }
        let timestampSlot = max(0, view.actualRightExtra - view.actualPanelReservation)
        let otherPanels = panels
            .filter { $0.visible && $0.panelIdentifier != identifier }
            .reduce(0) { $0 + $1.width }
        let available = sessionView.bounds.width - timestampSlot - otherPanels - minTerminalWidth
        return max(iTermGutterPanelWidths.minWidth,
                   min(iTermGutterPanelWidths.maxWidth, available))
    }
}
