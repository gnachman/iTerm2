//
//  PaneFocusFollowsMouse.swift
//  iTerm2
//

import AppKit

// A pane that focus follows mouse can move keyboard focus to. In the app, a SessionView.
@objc
@MainActor
protocol PaneFocusFollowsMousePane: AnyObject {
    // The view to focus when nothing else in the pane should get focus, e.g., its terminal.
    var focusFollowsMouseMainResponder: NSView? { get }
}

extension NSView {
    // A view in a pane that should get keyboard focus when the pointer is over it (a find bar,
    // composer, session note, …) returns the view to make first responder, e.g., its text field.
    // nil means the pointer being over this view doesn't move focus.
    @objc var it_focusFollowsMouseResponder: NSView? {
        return nil
    }

    // A view outside every pane that belongs to one, such as the window's status bar, which
    // belongs to the current session, returns that pane. Views in its subtree count as being in
    // that pane.
    @objc var it_focusFollowsMouseOwningPane: PaneFocusFollowsMousePane? {
        return nil
    }
}

// Everything PaneFocusFollowsMouse needs from the outside world, so its decisions can be tested
// without real windows and mouse events.
@MainActor
protocol PaneFocusFollowsMouseEnvironment: AnyObject {
    var isEnabled: Bool { get }
    // Also move focus between the terminal and views in a pane, such as the find bar. When off,
    // focus moves only between panes.
    var includesSubviews: Bool { get }
    var stealKeyFocusEnabled: Bool { get }
    var appIsActive: Bool { get }
    // True while any mouse button is held, e.g., during a drag.
    var mouseButtonIsDown: Bool { get }
    // True while handling the release of a mouse button.
    var currentEventIsMouseUp: Bool { get }
    // In screen coordinates.
    var pointerLocation: NSPoint { get }
    // The topmost pane at a screen point, or nil if the point is over something else, including
    // another app's window.
    func pane(at screenPoint: NSPoint) -> PaneFocusFollowsMousePane?
    func pane(containing view: NSView) -> PaneFocusFollowsMousePane?
    // The view in pane that should get focus when the pointer is at screenPoint: the pane's main
    // responder or an it_focusFollowsMouseResponder. nil if the pointer is over something that
    // can't take focus, such as a title bar.
    func focusTarget(at screenPoint: NSPoint, in pane: PaneFocusFollowsMousePane) -> NSView?
    // The pane that has keyboard focus, if any.
    var focusedPane: PaneFocusFollowsMousePane? { get }
    // The key window's first responder.
    var firstResponder: NSResponder? { get }
    // False when something like a modal window forbids it.
    func canFocus(_ pane: PaneFocusFollowsMousePane) -> Bool
    // Make the pane's window key, make the pane the active session, and make responder its
    // first responder.
    func focus(_ pane: PaneFocusFollowsMousePane, responder: NSResponder, evenIfInactive: Bool)
    func stealKeyFocus()
    func releaseKeyFocus()
    // The pane gained or lost stolen key focus, which changes how its cursor draws.
    func stolenKeyFocusDidChange(for pane: PaneFocusFollowsMousePane)
    // Run block after the current layout pass settles.
    func scheduleRebaseline(_ block: @escaping () -> Void)
    // Run block whenever a sheet ends, which may have been what kept focus from moving into a pane.
    // Its argument tells whether a pane is in the window the sheet was on.
    func observeSheetDidEnd(_ block: @escaping (_ isInWindowOfSheet: (PaneFocusFollowsMousePane) -> Bool) -> Void)
}

// Focus goes to whatever the pointer moves onto. Without includesSubviews, the only things are
// panes, and a pane gets its last-focused view.
//
// - When the thing under the pointer changes to something that can take focus (a pane's terminal,
//   or a view in it such as the find bar or composer), it gets focus. Moving within one thing
//   does nothing, so a panel that opens under a resting pointer, or by keyboard shortcut, keeps
//   focus until the pointer moves onto something else.
// - Entering a pane over something that can't take focus, such as its title bar, focuses
//   whatever last had focus in that pane. Moving from a pane to something that isn't a pane
//   (such as the tab bar) and back into the same pane is not entering it.
// - Nothing changes while a mouse button is held, so a drag that drifts into another pane can
//   finish where it started.
// - A focus change made by anything else (a click, the keyboard, a menu item, a new split) is not
//   undone until the pointer moves onto something else. The same goes for layout changes and app
//   activation that happen while the pointer is still.
@objc(iTermPaneFocusFollowsMouse)
@MainActor
class PaneFocusFollowsMouse: NSObject {
    @objc static let shared = PaneFocusFollowsMouse(environment: PaneFocusFollowsMouseAppEnvironment())

    private struct LastFocused {
        // Guards against a new pane reusing a deallocated pane's ObjectIdentifier.
        weak var pane: PaneFocusFollowsMousePane?
        weak var view: NSView?
    }

    private let environment: PaneFocusFollowsMouseEnvironment
    // The pane the pointer was last known to be in. Moving into a different pane focuses it.
    private weak var lastPane: PaneFocusFollowsMousePane?
    // The focus target the pointer was last known to be over. Moving onto a different one
    // focuses it.
    private weak var lastTarget: NSView?
    // Set when focus or layout changed while the pointer was still. Until the pointer leaves this
    // location, pointer events only update lastPane and lastTarget.
    private var frozenLocation: NSPoint?
    private var lastFocused = [ObjectIdentifier: LastFocused]()
    private weak var stolenPane: PaneFocusFollowsMousePane?
    private var haveStolenKeyFocus = false
    private var isFocusing = false
    // A pane the pointer entered without focus following it, e.g., because a sheet was open on its
    // window. Nothing else marks the pointer entering it, so when the sheet ends it is focused if
    // the pointer is still in it.
    private weak var blockedPane: PaneFocusFollowsMousePane?

    init(environment: PaneFocusFollowsMouseEnvironment) {
        self.environment = environment
        super.init()
        environment.observeSheetDidEnd { [weak self] isInWindowOfSheet in
            self?.sheetDidEnd(isInWindowOfSheet: isInWindowOfSheet)
        }
    }

    // Call whenever the pointer may have moved onto something else.
    @objc func pointerMoved() {
        guard environment.isEnabled else {
            releaseStolenKeyFocus()
            return
        }
        if environment.mouseButtonIsDown {
            DLog("Ignore pointer movement while a mouse button is down")
            return
        }
        let stealing = !environment.appIsActive
        if stealing && !environment.stealKeyFocusEnabled {
            DLog("Ignore pointer movement while inactive")
            return
        }
        let point = environment.pointerLocation
        let pane = environment.pane(at: point)
        let target = focusTarget(at: point, in: pane)
        if let frozenLocation {
            if frozenLocation == point {
                DLog("Pointer hasn't moved since focus or layout changed. Last pane is now \(pane.d)")
                lastPane = pane
                lastTarget = target
                return
            }
            self.frozenLocation = nil
        }
        guard let pane else {
            releaseStolenKeyFocus()
            blockedPane = nil
            lastTarget = nil
            if let lastPane, lastPane !== environment.focusedPane {
                // Coming back to an unfocused pane should focus it.
                DLog("Pointer left unfocused pane \(lastPane) for something that isn't a pane")
                self.lastPane = nil
            }
            return
        }
        var newlyStolen = false
        if stealing {
            if !haveStolenKeyFocus {
                DLog("Steal key focus")
                environment.stealKeyFocus()
                haveStolenKeyFocus = true
            }
            newlyStolen = stolenPane !== pane
            setStolenPane(pane)
        } else if haveStolenKeyFocus && stolenPane !== pane {
            releaseStolenKeyFocus()
        }
        if pane !== lastPane || newlyStolen {
            DLog("Pointer moved from \(lastPane.d) to \(pane), over \(target.d)")
            lastPane = pane
            lastTarget = target
            focus(pane, responder: target ?? validLastFocused(in: pane) ?? pane.focusFollowsMouseMainResponder)
            if stealing || environment.focusedPane === pane || !environment.canFocus(pane) {
                // Only a sheet ending can let focus move without the pointer moving again, and a
                // sheet doesn't make canFocus false.
                blockedPane = nil
            } else {
                DLog("Focus did not follow the pointer into \(pane)")
                blockedPane = pane
            }
            return
        }
        guard target !== lastTarget else {
            return
        }
        lastTarget = target
        if let target {
            DLog("Pointer moved onto \(target) in \(pane)")
            focus(pane, responder: target)
        }
    }

    // Call when the window's first responder changes.
    @objc(firstResponderDidChangeTo:)
    func firstResponderDidChange(to responder: NSResponder?) {
        guard !isFocusing, environment.isEnabled else {
            return
        }
        DLog("First responder changed to \(responder.d) by something other than focus follows mouse")
        if environment.currentEventIsMouseUp,
           let view = Self.focusableView(responder),
           let focusedPane = environment.pane(containing: view) {
            // A click or drag ends wherever the button is released, which may be over another
            // pane. The pointer hasn't entered that pane as far as focus is concerned, so the next
            // movement focuses it.
            DLog("Changed on mouse up. Last pane is now \(focusedPane)")
            lastPane = focusedPane
            lastTarget = view
            frozenLocation = nil
            remember(view, in: focusedPane)
            return
        }
        let point = environment.pointerLocation
        let pane = environment.pane(at: point)
        lastPane = pane
        lastTarget = focusTarget(at: point, in: pane)
        frozenLocation = point
        if let view = Self.focusableView(responder), let focusedPane = environment.pane(containing: view) {
            remember(view, in: focusedPane)
        }
    }

    // Call when the layout may have changed what is under a pointer that hasn't moved, e.g., a
    // new split pane.
    @objc func freeze() {
        guard environment.isEnabled else {
            return
        }
        let point = environment.pointerLocation
        DLog("Freeze at \(point)")
        frozenLocation = point
        environment.scheduleRebaseline { [weak self] in
            guard let self, self.frozenLocation == point else {
                return
            }
            let pane = self.environment.pane(at: point)
            self.lastPane = pane
            self.lastTarget = self.focusTarget(at: point, in: pane)
            DLog("After layout, last pane is \(self.lastPane.d)")
        }
    }

    // A sheet that kept focus from following the pointer into blockedPane may have ended. The
    // pointer won't enter the pane again while it is still inside, so focus it now.
    private func sheetDidEnd(isInWindowOfSheet: (PaneFocusFollowsMousePane) -> Bool) {
        guard let blocked = blockedPane, isInWindowOfSheet(blocked) else {
            return
        }
        blockedPane = nil
        guard environment.isEnabled, environment.appIsActive, !environment.mouseButtonIsDown else {
            return
        }
        let point = environment.pointerLocation
        guard let pane = environment.pane(at: point), pane === blocked, environment.focusedPane !== pane else {
            return
        }
        DLog("Focus \(pane), which the pointer entered while focus could not move")
        let target = focusTarget(at: point, in: pane)
        frozenLocation = nil
        lastPane = pane
        lastTarget = target
        focus(pane, responder: target ?? validLastFocused(in: pane) ?? pane.focusFollowsMouseMainResponder)
    }

    @objc func appDidBecomeActive() {
        freeze()
    }

    // Focus the pane under the pointer even if the pointer was already in it.
    @objc func focusPaneUnderPointer() {
        guard environment.isEnabled else {
            return
        }
        let point = environment.pointerLocation
        guard let pane = environment.pane(at: point) else {
            return
        }
        let target = focusTarget(at: point, in: pane)
        frozenLocation = nil
        lastPane = pane
        lastTarget = target
        // A Space change can be announced before the app becomes active.
        focus(pane,
              responder: target ?? validLastFocused(in: pane) ?? pane.focusFollowsMouseMainResponder,
              evenIfInactive: true)
    }

    // True while pane needs pointer movement events to notice the pointer moving onto something
    // else within it.
    @objc(wantsPointerMovementFor:)
    func wantsPointerMovement(for pane: PaneFocusFollowsMousePane) -> Bool {
        return environment.isEnabled && environment.includesSubviews
    }

    @objc(hasStolenKeyFocusFor:)
    func hasStolenKeyFocus(for pane: PaneFocusFollowsMousePane) -> Bool {
        return haveStolenKeyFocus && stolenPane === pane
    }

    // MARK: - Private

    private func focusTarget(at point: NSPoint, in pane: PaneFocusFollowsMousePane?) -> NSView? {
        guard let pane, environment.includesSubviews else {
            return nil
        }
        return Self.focusableView(environment.focusTarget(at: point, in: pane))
    }

    private func focus(_ pane: PaneFocusFollowsMousePane, responder: NSView?, evenIfInactive: Bool = false) {
        guard let responder else {
            return
        }
        if Self.focusableView(environment.firstResponder) === responder {
            // Making it first responder again could, for example, select all of a text field.
            DLog("\(responder) already has focus")
            return
        }
        guard environment.canFocus(pane) else {
            DLog("Not allowed to focus \(pane)")
            return
        }
        DLog("Focus \(responder) in \(pane)")
        isFocusing = true
        defer {
            isFocusing = false
        }
        remember(responder, in: pane)
        environment.focus(pane, responder: responder, evenIfInactive: evenIfInactive || haveStolenKeyFocus)
    }

    private func remember(_ view: NSView, in pane: PaneFocusFollowsMousePane) {
        lastFocused[ObjectIdentifier(pane)] = LastFocused(pane: pane, view: view)
    }

    private func validLastFocused(in pane: PaneFocusFollowsMousePane) -> NSView? {
        guard let entry = lastFocused[ObjectIdentifier(pane)],
              entry.pane === pane,
              let view = entry.view,
              environment.pane(containing: view) === pane else {
            return nil
        }
        return view
    }

    private func releaseStolenKeyFocus() {
        guard haveStolenKeyFocus else {
            return
        }
        DLog("Release key focus")
        haveStolenKeyFocus = false
        setStolenPane(nil)
        environment.releaseKeyFocus()
    }

    private func setStolenPane(_ pane: PaneFocusFollowsMousePane?) {
        guard pane !== stolenPane else {
            return
        }
        let before = stolenPane
        stolenPane = pane
        if let before {
            environment.stolenKeyFocusDidChange(for: before)
        }
        if let pane {
            environment.stolenKeyFocusDidChange(for: pane)
        }
    }

    // A field editor stands in for the control it edits, which outlives it.
    private static func focusableView(_ responder: NSResponder?) -> NSView? {
        guard let view = responder as? NSView else {
            return nil
        }
        if let textView = view as? NSTextView, textView.isFieldEditor {
            var ancestor = textView.superview
            while let candidate = ancestor {
                if candidate is NSControl {
                    return candidate
                }
                ancestor = candidate.superview
            }
        }
        return view
    }
}
