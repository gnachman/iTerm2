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

@objc(iTermRightGutterController)
class iTermRightGutterController: NSObject, iTermRightGutterPanelDelegate {
    private weak var sessionView: SessionView?
    private var panels: [iTermRightGutterPanel] = []
    // Mirrors panels' identifiers in order; used for diffing against the
    // registry's enabled list.
    private var panelIdentifiers: [String] = []

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
    }

    // MARK: - Notifications

    @objc private func advancedSettingsDidChange(_ notification: Notification) {
        guard let sessionView = sessionView,
              let session = sessionView.delegate as? PTYSession,
              session.profile != nil else {
            return
        }
        if session.view.actualRightExtra != session.desiredRightExtra() {
            session.delegate?.realParentWindow().rightExtraDidChange()
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
            if desiredSet.contains(panel.identifier) {
                byID[panel.identifier] = panel
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
        panelIdentifiers = survivors.map { $0.identifier }
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

        for panel in panels {
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
            } else {
                panel.view.isHidden = true
            }
            x += width
        }
    }

    // MARK: - iTermRightGutterPanelDelegate

    func rightGutterPanelDidChangeWidthOrVisibility(_ panel: iTermRightGutterPanel) {
        guard let sessionView = sessionView,
              let session = sessionView.delegate as? PTYSession,
              session.profile != nil else {
            return
        }
        // The registry's totalWidthForProfile reads the same prefs the panels
        // use, so the next time desiredRightExtra is evaluated it will reflect
        // the new width. Notify the parent window to rerun the layout cascade.
        if session.view.actualRightExtra != session.desiredRightExtra() {
            session.delegate?.realParentWindow().rightExtraDidChange()
        } else {
            // Width unchanged at the budget level (e.g., visibility toggle
            // that doesn't affect the configured width). Just relayout in
            // place.
            positionPanels(in: sessionView)
        }
    }
}
