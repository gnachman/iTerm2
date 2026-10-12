//
//  RestoredArrangementFrameGuard.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/12/26.
//

import AppKit

/// Keeps a window that was just restored from a saved arrangement on the
/// display the arrangement put it on. Issue 13002.
///
/// When displays have separate Spaces, the window joins the active Space when it
/// is first ordered in, and that Space may be on a different display than the
/// arrangement. Some time after the restore finishes, macOS moves the window to
/// its Space's display. That move comes from the window server: AppKit applies
/// it in -_setFrameCommon:display:fromServer: without ever calling
/// -setFrame:display:, so -it_preventFrameChange can't block it. The delay was
/// measured at anywhere from 1.4 to 2.8 seconds after the restore, so a fixed
/// time window can't be relied on to catch it either.
///
/// Instead, this recognizes the move by what it is: the window landed on a
/// different display, and the frame it has now is not one the app gave it. The
/// window records the last frame set through -setFrame:display: or
/// -setFrameOrigin:, and a frame that differs from it came from outside the app.
/// That spares moves iTerm2 makes on purpose, such as an API script moving the
/// window to another display.
///
/// It stands down for good when the user drags or resizes the window, when the
/// displays change, after it has put the window back `maxReassertions` times (so
/// a disagreement with macOS can't turn into the window bouncing between
/// displays), or after `lifetime` seconds. The lifetime is not what catches the
/// move. It bounds how long a move by another app, which looks identical to the
/// one this is after (for example, an accessibility-based window manager), gets
/// overridden.
@objc(iTermRestoredArrangementFrameGuard)
@MainActor
class RestoredArrangementFrameGuard: NSObject {
    static let maxReassertions = 2
    static let lifetime: TimeInterval = 30

    private struct Armed {
        var frame: NSRect
        var screenConfiguration: NSArray
        var deadline: TimeInterval
        var reassertions = 0
    }

    private var armed: Armed?
    private let now: () -> TimeInterval

    @objc
    override init() {
        now = { NSDate.it_timeSinceBoot() }
        super.init()
    }

    init(now: @escaping () -> TimeInterval) {
        self.now = now
        super.init()
    }

    @objc var isArmed: Bool {
        return armed != nil
    }

    /// Starts defending `frame`. `screenConfiguration` describes the displays at
    /// this moment; if it changes, the guard stands down.
    @objc(armWithFrame:screenConfiguration:)
    func arm(frame: NSRect, screenConfiguration: NSArray) {
        RLog("Arm restored arrangement frame guard for \(NSStringFromRect(frame))")
        armed = Armed(frame: frame,
                      screenConfiguration: screenConfiguration,
                      deadline: now() + Self.lifetime)
    }

    @objc(disarmBecause:)
    func disarm(because reason: String) {
        guard armed != nil else {
            return
        }
        RLog("Disarm restored arrangement frame guard: \(reason)")
        armed = nil
    }

    /// Call when the window changes screens. Returns the frame to put the window
    /// back to, or nil to let the change stand.
    ///
    /// - Parameters:
    ///   - windowFrame: The window's frame now.
    ///   - lastFrameSetByApp: The window's frame right after the app last set it.
    ///   - screenFrames: The frame of each display, in NSScreen.screens order.
    ///   - screenConfiguration: The same description passed to arm(), for now.
    func frameToRestore(windowFrame: NSRect,
                        lastFrameSetByApp: NSRect,
                        screenFrames: [NSRect],
                        screenConfiguration: NSArray) -> NSRect? {
        guard let state = armed else {
            return nil
        }
        if now() >= state.deadline {
            disarm(because: "its lifetime ended")
            return nil
        }
        if !state.screenConfiguration.isEqual(screenConfiguration) {
            disarm(because: "the displays changed")
            return nil
        }
        let desiredDisplay = Self.displayIndex(for: state.frame, screenFrames: screenFrames)
        let actualDisplay = Self.displayIndex(for: windowFrame, screenFrames: screenFrames)
        if desiredDisplay == actualDisplay {
            RLog("Restored arrangement frame guard: window is still on display \(String(describing: actualDisplay))")
            return nil
        }
        if NSEqualRects(windowFrame, lastFrameSetByApp) {
            // The app moved it there itself, so it's on purpose.
            disarm(because: "the app moved the window to display \(String(describing: actualDisplay)) at \(NSStringFromRect(windowFrame))")
            return nil
        }
        if state.reassertions >= Self.maxReassertions {
            disarm(because: "it already put the window back \(state.reassertions) times and macOS keeps moving it to \(NSStringFromRect(windowFrame))")
            return nil
        }
        armed?.reassertions += 1
        RLog("Restored arrangement frame guard: window was moved from outside the app to \(NSStringFromRect(windowFrame)) on display \(String(describing: actualDisplay)). Putting it back at \(NSStringFromRect(state.frame)) on display \(String(describing: desiredDisplay)) (attempt \(state.reassertions + 1) of \(Self.maxReassertions))")
        return state.frame
    }

    /// Objective-C entry point. Returns NSZeroRect to let the change stand.
    @objc(frameToRestoreForWindowFrame:lastFrameSetByApp:screenConfiguration:)
    func frameToRestore(windowFrame: NSRect,
                        lastFrameSetByApp: NSRect,
                        screenConfiguration: NSArray) -> NSRect {
        return frameToRestore(windowFrame: windowFrame,
                              lastFrameSetByApp: lastFrameSetByApp,
                              screenFrames: NSScreen.screens.map(\.frame),
                              screenConfiguration: screenConfiguration) ?? .zero
    }

    /// The index of the display holding most of `frame`, or nil if it's on none.
    /// This is how NSWindow decides which screen it is on.
    static func displayIndex(for frame: NSRect, screenFrames: [NSRect]) -> Int? {
        var best: Int?
        var bestArea = CGFloat(0)
        for (i, screenFrame) in screenFrames.enumerated() {
            let intersection = frame.intersection(screenFrame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            if area > bestArea {
                best = i
                bestArea = area
            }
        }
        return best
    }
}
