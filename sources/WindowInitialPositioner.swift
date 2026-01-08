//
//  WindowInitialPositioner.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/6/26.
//

import Foundation

private let kWindowNameFormat = "iTerm Window %d"

@objc(iTermWindowInitialPositionerDelegate)
@MainActor
protocol WindowInitialPositionerDelegate: AnyObject {
    var windowForPositioner: (any NSWindow & PTYWindow)? { get }
    var windowType: iTermWindowType { get }
    func canonicalize()
    @objc(canonicalFrameForScreen:)
    func canonicalFrame(screen: NSScreen) -> NSRect
}

@objc(iTermWindowInitialPositioner)
@MainActor
class WindowInitialPositioner: NSObject {
    // MARK: - State

    /// Unique window identifier for autosave frame storage (allocated lazily on first access)
    private var _uniqueNumber: Int32?
    @objc var uniqueNumber: Int32 {
        if let num = _uniqueNumber {
            return num
        }
        let num = TemporaryNumberAllocator.sharedInstance().allocateNumber()
        _uniqueNumber = num
        return num
    }

    /// Initial position preference from profile/screen
    @objc var preferredOrigin: NSPoint = .zero

    /// Which screen the window is anchored to, or nil if not anchored.
    /// When non-nil, the window should stay on this screen.
    private var anchoredScreenNumber: Int32?

    /// Whether window is locked to a specific screen (computed from anchoredScreenNumber)
    @objc var isAnchoredToScreen: Bool {
        return anchoredScreenNumber != nil
    }

    /// Screen preference from profile: -2 = follow cursor, -1 = no preference, >= 0 = screen number
    @objc var screenNumberFromFirstProfile: Int32 = -1

    /// Whether auto-frame restoration is disabled (from KEY_DISABLE_AUTO_FRAME in profile)
    @objc let disableAutoFrame: Bool

    /// Saved window positions from user defaults
    @objc var savedWindowPositions: [String: String] {
        let obj = UserDefaults.standard.object(forKey: kPreferenceKeySavedWindowPositions)
        return (obj as? [String: String]) ?? [:]
    }

    // MARK: - Dependencies

    private weak var delegate: WindowInitialPositionerDelegate?

    // MARK: - Initialization

    @objc(initWithScreenNumberFromFirstProfile:disableAutoFrame:delegate:)
    init(screenNumberFromFirstProfile: Int32,
         disableAutoFrame: Bool,
         delegate: WindowInitialPositionerDelegate) {
        self.screenNumberFromFirstProfile = screenNumberFromFirstProfile
        self.disableAutoFrame = disableAutoFrame
        self.delegate = delegate
        super.init()
    }

    deinit {
        if let num = _uniqueNumber {
            TemporaryNumberAllocator.sharedInstance().deallocateNumber(num)
        }
    }

    // MARK: - Screen Anchor Management

    /// Sets the anchored screen number. Use -1 to clear the anchor.
    @objc
    func setAnchoredScreenNumber(_ screenNumber: Int32) {
        DLog("setAnchoredScreenNumber(\(screenNumber))")
        anchoredScreenNumber = screenNumber >= 0 ? screenNumber : nil
    }

    // MARK: - Public API

    /// Main entry point: positions window when it's about to be shown for the first time.
    /// Called from iTermWindowImpl's makeKeyAndOrderFront:.
    @objc
    func windowWillShowInitial() {
        DLog("windowWillShowInitial: preferredOrigin=\(NSStringFromPoint(preferredOrigin)) anchoredScreenNumber=\(String(describing: anchoredScreenNumber)) screenNumberFromFirstProfile=\(screenNumberFromFirstProfile) disableAutoFrame=\(disableAutoFrame)")

        guard let window = delegate?.windowForPositioner else {
            DLog("windowWillShowInitial: no window")
            return
        }
        DLog("windowWillShowInitial: window.frame=\(NSStringFromRect(window.frame)) window.screenNumber=\(window.screenNumber)")

        // If it's a full or top-of-screen window with a screen number preference, always honor that.
        if let anchoredScreen = anchoredScreenNumber {
            DLog("windowWillShowInitial: have screen preference, anchoredScreenNumber=\(anchoredScreen)")
            var frame = window.frame
            frame.origin = preferredOrigin
            window.setFrame(frame, display: false)
        }

        let numberOfTerminalWindows = iTermController.sharedInstance()?.terminals().count ?? 0
        let placement = iTermPreferences.unsignedInteger(forKey: kPreferenceKeyWindowPlacement)
        DLog("windowWillShowInitial: numberOfTerminalWindows=\(numberOfTerminalWindows) placement=\(placement)")

        switch iTermWindowPlacement(rawValue: placement) {
        case .system:
            DLog("Using system placement")
            return

        case .sizeAndPosition:
            DLog("Restoring size and position")
            let screenNumber = window.screenNumber
            loadAutoSaveFrame()
            if anchoredScreenNumber != nil && window.screenNumber != screenNumber {
                DLog("Move window to preferred origin because it moved to another screen.")
                window.setFrameOrigin(preferredOrigin)
            }

        case .position:
            DLog("Restoring position")
            loadSavedWindowPosition()

        case .smart:
            if numberOfTerminalWindows != 1 {
                DLog("Invoking smartLayout")
                window.smartLayout()
                return
            }
            DLog("Smart Layout: restoring position")
            loadSavedWindowPosition()

        case .none:
            break

        @unknown default:
            break
        }
    }

    /// Saves the current window position to user defaults for later restoration.
    @objc
    func saveWindowPosition() {
        guard let window = delegate?.windowForPositioner else {
            DLog("saveWindowPosition: no window")
            return
        }

        var positions = savedWindowPositions
        var point = window.frame.origin
        point.y += window.frame.size.height
        DLog("saveWindowPosition: uniqueNumber=\(uniqueNumber) point=\(NSStringFromPoint(point))")
        positions[String(uniqueNumber)] = NSStringFromPoint(point)
        UserDefaults.standard.set(positions, forKey: kPreferenceKeySavedWindowPositions)
    }

    /// Saves the window frame using the autosave system.
    @objc
    func saveFrame() {
        guard let window = delegate?.windowForPositioner else {
            DLog("saveFrame: no window")
            return
        }
        let name = String(format: kWindowNameFormat, uniqueNumber)
        DLog("saveFrame: name=\(name) frame=\(NSStringFromRect(window.frame))")
        window.saveFrame(usingName: name)
    }

    /// Clears the screen anchor, allowing the window to move freely between screens.
    @objc
    func clearScreenAnchor() {
        DLog("clearScreenAnchor")
        anchoredScreenNumber = nil
    }

    /// Returns the anchored screen number, or -1 if not anchored.
    @objc
    func getAnchoredScreenNumber() -> Int32 {
        return anchoredScreenNumber ?? -1
    }

    // MARK: - Private Methods

    private func loadSavedWindowPosition() {
        DLog("loadSavedWindowPosition")
        guard let window = delegate?.windowForPositioner else {
            DLog("loadSavedWindowPosition: no window")
            return
        }

        let screenNumber = window.screenNumber
        DLog("loadSavedWindowPosition: screenNumber=\(screenNumber) anchoredScreenNumber=\(String(describing: anchoredScreenNumber))")
        loadAutoSavePosition()
        if anchoredScreenNumber != nil && window.screenNumber != screenNumber {
            DLog("Move window to preferred origin because it moved to another screen.")
            window.setFrameOrigin(preferredOrigin)
        }
    }

    private func loadAutoSaveFrame() {
        DLog("loadAutoSaveFrame")

        guard !disableAutoFrame else {
            DLog("Auto-frame disabled.")
            return
        }

        DLog("Load auto-save frame")
        guard let window = delegate?.windowForPositioner else { return }

        var frame = window.frame
        let name = String(format: kWindowNameFormat, uniqueNumber)
        let hadAutoSaveFrame = window.setFrameUsingName(name)

        if hadAutoSaveFrame {
            DLog("Autosave frame restored (possibly asynchronously! good luck)")
        } else {
            frame.origin = preferredOrigin
            window.setFrame(frame, display: false)
            DLog("Update frame to \(NSStringFromRect(frame))")
        }
    }

    private func loadAutoSavePosition() {
        DLog("loadAutoSavePosition")
        guard let delegate else {
            DLog("loadAutoSavePosition: No delegate")
            return
        }
        guard !disableAutoFrame else {
            DLog("loadAutoSavePosition: Auto-frame disabled.")
            return
        }

        let windowType = delegate.windowType
        DLog("loadAutoSavePosition: windowType=\(windowType.rawValue)")

        let canonicalizeAfterPositioning = switch windowType {
        case .WINDOW_TYPE_NORMAL,
             .WINDOW_TYPE_NO_TITLE_BAR,
             .WINDOW_TYPE_COMPACT,
             .WINDOW_TYPE_ACCESSORY:
            false
        case .WINDOW_TYPE_TRADITIONAL_FULL_SCREEN,
             .WINDOW_TYPE_LION_FULL_SCREEN,
             .WINDOW_TYPE_TOP_PERCENTAGE,
             .WINDOW_TYPE_BOTTOM_PERCENTAGE,
             .WINDOW_TYPE_LEFT_PERCENTAGE,
             .WINDOW_TYPE_RIGHT_PERCENTAGE,
             .WINDOW_TYPE_BOTTOM_CELLS,
             .WINDOW_TYPE_CENTERED,
             .WINDOW_TYPE_TOP_CELLS,
             .WINDOW_TYPE_LEFT_CELLS,
             .WINDOW_TYPE_RIGHT_CELLS,
             .WINDOW_TYPE_MAXIMIZED,
             .WINDOW_TYPE_COMPACT_MAXIMIZED:
            true
        @unknown default:
            false
        }
        DLog("loadAutoSavePosition: canonicalizeAfterPositioning=\(canonicalizeAfterPositioning)")
        defer {
            if canonicalizeAfterPositioning {
                DLog("loadAutoSavePosition: calling canonicalize")
                delegate.canonicalize()
            }
        }

        guard let window = delegate.windowForPositioner else {
            DLog("loadAutoSavePosition: no window")
            return
        }

        var frame = window.frame
        let positions = savedWindowPositions
        DLog("loadAutoSavePosition: uniqueNumber=\(uniqueNumber) positions=\(positions)")
        if let position = positions[String(uniqueNumber)] {
            let point = NSPointFromString(position)
            DLog("loadAutoSavePosition: found saved position \(NSStringFromPoint(point))")
            if canonicalizeAfterPositioning, let screen = NSScreen(containingCoordinate: point) {
                // Since the frame is canonicalizable all we need to do is put it on the right
                // screen at the right size. Preserving the exact point is unneeded since it can
                // be derived from the window type, initial size, and screen and might differ from
                // the saved value (for example if screens have changed or the initial size is
                // different than the window's size when its position was saved).
                let canonicalFrame = delegate.canonicalFrame(screen: screen)
                DLog("loadAutoSavePosition: using canonical frame \(NSStringFromRect(canonicalFrame)) on screen \(screen.localizedName)")
                window.setFrame(canonicalFrame, display: false)
            } else {
                // This might not do anything if the frame's size is too big. Or it might decide
                // to put it somewhere else if it would be clipped (or not! who knows! probably
                // only ex-apple employees). This is a YOLO best effort.
                DLog("loadAutoSavePosition: setting top-left point to \(NSStringFromPoint(point))")
                window.setFrameTopLeftPoint(point)
            }
            return
        }

        // Put it on the correct display
        DLog("loadAutoSavePosition: no saved position, using preferredOrigin=\(NSStringFromPoint(preferredOrigin))")
        frame.origin = preferredOrigin
        window.setFrame(frame, display: false)

        // And then move it to a nicer spot.
        DLog("loadAutoSavePosition: calling smartLayout")
        window.smartLayout()

        DLog("loadAutoSavePosition: final frame=\(NSStringFromRect(window.frame))")
    }
}
