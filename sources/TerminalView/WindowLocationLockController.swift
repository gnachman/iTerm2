//
//  WindowLocationLockController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/24/26.
//

import AppKit

@objc(iTermWindowLocationLockControllerDelegate)
@MainActor
protocol WindowLocationLockControllerDelegate: AnyObject {
    var windowForLocationLock: (any NSWindow & PTYWindow)? { get }

    var locationLockWindowType: iTermWindowType { get }

    /// KEY_SCREEN from the window’s first profile. -2 means the window opens on
    /// whichever screen has the cursor.
    var locationLockProfileScreenPreference: Int32 { get }

    /// True while the window controller is doing something that owns the frame:
    /// a full screen transition, or a hotkey window that is hidden or animating.
    var locationLockWindowStateOwnsFrame: Bool { get }

    /// Moves the window to a screen and gives it the shape it should have there.
    @objc(locationLockMoveToScreen:)
    func locationLockMoveToScreen(_ screen: NSScreen)
}

/// Owns a window’s Lock Location state and decides when to act on it.
///
/// The lock itself (`WindowLocationLock`) remembers where the window belongs and
/// never touches a window. This decides whether the lock applies to this kind of
/// window at all, whether now is a moment worth acting on, and which of the two
/// enforcement strategies to use. The window controller keeps one of these and
/// forwards the handful of AppKit notifications that matter.
@objc(iTermWindowLocationLockController)
@MainActor
class WindowLocationLockController: NSObject {
    /// How much of the window’s geometry the lock is responsible for, which
    /// depends on how much of it the user picked in the first place.
    private enum Mode {
        /// macOS owns the frame, so there is nothing for Lock Location to do.
        case unsupported

        /// The user chose the frame, so the lock defends all of it.
        case frame

        /// -canonicalizeWindowFrame computes the frame from whatever screen the
        /// window is on, so the lock defends only the choice of screen and lets
        /// the canonicalizer give the window its shape there.
        case screen
    }

    private weak var delegate: WindowLocationLockControllerDelegate?
    private var lock: WindowLocationLock?

    /// Set while this is moving the window. The frames it produces are the least
    /// trustworthy there are, because -setFrame: gets constrained to the screen
    /// and moving to a screen canonicalizes, so nothing is learned from them. It
    /// also keeps enforcement from reentering itself by way of the notifications
    /// it provokes.
    private var enforcing = false

    @objc(initWithDelegate:)
    init(delegate: WindowLocationLockControllerDelegate) {
        self.delegate = delegate
        super.init()
    }

    // MARK: - Menu

    @objc var isLocked: Bool {
        return lock != nil
    }

    /// Whether a *new* lock can be taken. Releasing one that already exists must
    /// always be possible, so callers validating the menu item allow the action
    /// whenever `isLocked` is true regardless of this.
    @objc var canLock: Bool {
        guard let delegate else {
            return false
        }
        if delegate.locationLockProfileScreenPreference == -2 {
            // A window that opens on the screen with the cursor has no fixed
            // location, so pinning it to one is nonsense.
            return false
        }
        return mode != .unsupported
    }

    @objc
    func toggle() {
        if lock != nil {
            DLog("Unlocking location")
            lock = nil
            return
        }
        guard canLock, let window = delegate?.windowForLocationLock else {
            return
        }
        lock = WindowLocationLock(window: window)
    }

    /// The profile’s screen preference changed. A window that now follows the
    /// cursor cannot hold a lock: it would spend its life fighting whatever moves
    /// it to the cursor’s screen.
    @objc
    func profileScreenPreferenceDidChange() {
        guard lock != nil, delegate?.locationLockProfileScreenPreference == -2 else {
            return
        }
        DLog("Profile screen preference became follow-cursor. Dropping the location lock.")
        lock = nil
    }

    // MARK: - Notifications

    /// Called the instant the displays change, well before anything acts on it.
    @objc
    func displaysDidChange() {
        lock?.latchDormant()
    }

    /// `userIsDragging` is the window controller’s verdict on whether this move is
    /// the user dragging the window, which is the one way to release a lock by
    /// hand besides the menu item.
    @objc(windowDidMoveUserIsDragging:)
    func windowDidMove(userIsDragging: Bool) {
        guard lock != nil else {
            return
        }
        if userIsDragging {
            DLog("User dragged a location-locked window. Unlocking it.")
            lock = nil
            return
        }
        enforce()
    }

    @objc
    func windowDidResize() {
        guard !shouldYield, let window = delegate?.windowForLocationLock else {
            return
        }
        // Absorption honors the same veto as enforcement. A lock that refuses to
        // move a window while it is full screen but happily learns the full screen
        // rect would restore the window at the size of its whole display
        // afterwards, and would persist that frame into any arrangement written
        // meanwhile.
        lock?.absorbResize(of: window)
    }

    // MARK: - Enforcement

    private var mode: Mode {
        guard let windowType = delegate?.locationLockWindowType else {
            return .unsupported
        }
        switch windowType {
        case .WINDOW_TYPE_NORMAL,
             .WINDOW_TYPE_NO_TITLE_BAR,
             .WINDOW_TYPE_COMPACT,
             .WINDOW_TYPE_ACCESSORY:
            return .frame

        case .WINDOW_TYPE_CENTERED,
             .WINDOW_TYPE_COMPACT_CENTERED,
             .WINDOW_TYPE_CENTERED_NO_TITLE_BAR,
             .WINDOW_TYPE_MAXIMIZED,
             .WINDOW_TYPE_COMPACT_MAXIMIZED,
             .WINDOW_TYPE_TOP_PERCENTAGE,
             .WINDOW_TYPE_BOTTOM_PERCENTAGE,
             .WINDOW_TYPE_LEFT_PERCENTAGE,
             .WINDOW_TYPE_RIGHT_PERCENTAGE,
             .WINDOW_TYPE_BOTTOM_CELLS,
             .WINDOW_TYPE_TOP_CELLS,
             .WINDOW_TYPE_LEFT_CELLS,
             .WINDOW_TYPE_RIGHT_CELLS:
            return .screen

        case .WINDOW_TYPE_TRADITIONAL_FULL_SCREEN,
             .WINDOW_TYPE_LION_FULL_SCREEN:
            return .unsupported

        @unknown default:
            return .unsupported
        }
    }

    /// True when something with a better claim to the window’s frame is driving
    /// it and the lock must keep its hands off.
    private var shouldYield: Bool {
        guard lock != nil, let delegate else {
            return true
        }
        if enforcing {
            return true
        }
        if delegate.locationLockWindowStateOwnsFrame {
            return true
        }
        if mode == .unsupported {
            // The window went full screen, or its style changed out from under
            // the lock.
            return true
        }
        if delegate.windowForLocationLock?.it_isMovingScreen ?? false {
            return true
        }
        return false
    }

    /// Puts a location-locked window back where it belongs.
    @objc
    func enforce() {
        guard !shouldYield, let window = delegate?.windowForLocationLock else {
            return
        }
        guard window.screen != nil else {
            // Miniaturized or ordered out. There is no meaningful "where it is
            // now" to move it from: moving to a screen would divide by an empty
            // source screen and hand -setFrame: a NaN rect. The window controller
            // enforces again on deminiaturize, and dormancy survives until then.
            DLog("Location lock deferring: the window is on no screen")
            return
        }
        let home: Bool
        switch mode {
        case .unsupported:
            return
        case .screen:
            home = enforceOnDisplay(window)
        case .frame:
            home = enforceOnFrame(window)
        }
        // Start trusting frame changes again only once the window verifiably
        // landed. Both modes report, so a window that spends time in a style that
        // only pins its display isn't left dormant forever if its style later
        // changes back.
        lock?.clearDormancyIfWindowIsHome(home)
    }

    /// The canonicalizer computes this window's frame from whatever screen it is
    /// on, so all the lock has to defend is the choice of screen. Moving to the
    /// screen canonicalizes the window once it gets there, which gives it the
    /// shape it should have on that display even if the display has changed size
    /// since it was locked.
    private func enforceOnDisplay(_ window: any NSWindow & PTYWindow) -> Bool {
        guard let lock, let display = lock.anchorDisplay else {
            DLog("Location lock is lying in wait")
            return false
        }
        if !lock.windowIsOnAnchorDisplay(window) {
            DLog("Location lock moving window to display \(display.it_description())")
            enforcing = true
            delegate?.locationLockMoveToScreen(display)
            enforcing = false
        }
        return lock.windowIsOnAnchorDisplay(window)
    }

    /// The user chose this window's frame, so the lock defends all of it.
    ///
    /// A window that is already on its anchor display only needs its origin put
    /// back, which leaves alone a size the user chose there. A window that is
    /// somewhere else may have been squeezed to fit whatever display it landed
    /// on, so bringing it home restores its whole frame.
    private func enforceOnFrame(_ window: any NSWindow & PTYWindow) -> Bool {
        guard let lock, lock.isEnforceable else {
            DLog("Location lock is lying in wait")
            return false
        }
        // Where the window is now says nothing about what has been done to it.
        // macOS squeezes a window onto whatever display is left and then hands it
        // back when the display returns, so a window that is already home may
        // still be the wrong size. Dormancy is what remembers that, so restore the
        // whole frame whenever the arrangement has been disturbed since the lock
        // was taken.
        let restoreSize = lock.isDormant || !lock.windowIsOnAnchorDisplay(window)
        let desired = lock.desiredFrame
        let current = window.frame
        let needsChange = restoreSize ? !NSEqualRects(desired, current)
                                      : !NSEqualPoints(desired.origin, current.origin)
        if needsChange {
            DLog("Location lock moving window from \(NSStringFromRect(current)) to \(NSStringFromRect(desired)) (restoreSize=\(restoreSize) dormant=\(lock.isDormant))")
            enforcing = true
            if restoreSize {
                window.setFrame(desired, display: true)
            } else {
                window.setFrameOrigin(desired.origin)
            }
            enforcing = false
        }
        // Whether the window is actually home. -setFrame:display: goes through
        // -constrainFrameRect:toScreen:, so it may not have gone where we asked,
        // and reporting home on a frame that is already wrong would teach the lock
        // the wrong thing. Saying no just means retrying on the next notification.
        return NSEqualRects(window.frame, desired)
    }

    // MARK: - Arrangements

    @objc(loadArrangement:)
    func load(arrangement: [AnyHashable: Any]) {
        lock = WindowLocationLock.lock(from: arrangement)
    }

    @objc(populateInArrangement:)
    func populate(in arrangement: iTermEncoderAdapter) {
        lock?.populate(in: arrangement)
    }
}
