//
//  WindowLocationLock.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/23/26.
//

import AppKit

/// Remembers where a window was when the user locked its location so it can be
/// put back when something else moves it.
///
/// The anchor is a display, that display’s size at the time the lock was taken,
/// and the window’s frame relative to the display’s origin. It is enforced only
/// while that display is attached at that size. Otherwise the lock lies in wait:
/// when a display is unplugged (which is what a sleeping laptop looks like to
/// AppKit) macOS relocates its windows onto whatever display is left, and there
/// is no frame worth defending until the anchor display comes back. If it comes
/// back at a different resolution the remembered frame no longer describes a
/// place the user chose, so the lock stays dormant rather than guess.
///
/// # Dormancy
///
/// A lock also has to know when *not* to learn. The remembered frame follows
/// legitimate resizes (see `absorbResize(of:)`), and a resize cannot be told from
/// a move by inspecting it: a font size change, a toolbelt toggle, a new split, a
/// tmux layout, and the Python API all resize windows with no mouse button down
/// and no live-resize bracket. What can be told apart is *when*, so the lock goes
/// dormant the moment the displays change and learns nothing until the window has
/// verifiably been put back where it belongs. The one thing it will still learn
/// from is a live resize, which is unambiguously the user with the mouse down.
///
/// # Display identity
///
/// Displays are identified by -[NSScreen it_uniqueKey], which is built from the
/// model, vendor, and serial numbers. Many displays report a serial number of 0,
/// so two monitors of the same model produce the same key. The anchor therefore
/// also records which of the matching displays it was, by position in the
/// arrangement, and how many there were. Any change in that count, in either
/// direction, means the twins can no longer be told apart, so the lock lies in
/// wait rather than guess at one. Rearranging two identical monitors in System
/// Settings keeps the count the same while swapping which one the ordinal picks
/// out, and that is not detectable: indistinguishable displays are exactly that.
@objc(iTermWindowLocationLock)
@MainActor
class WindowLocationLock: NSObject {
    private static let screenArrangementKey = "Location Lock Screen"
    private static let screenOrdinalArrangementKey = "Location Lock Screen Ordinal"
    private static let screenDuplicateCountArrangementKey = "Location Lock Screen Duplicate Count"
    private static let screenSizeArrangementKey = "Location Lock Screen Size"
    private static let frameArrangementKey = "Location Lock Frame"

    /// Identifies the anchor display. See -[NSScreen it_uniqueKey].
    private let screenKey: String

    /// Which of the displays sharing `screenKey` the anchor is, by position in the
    /// arrangement, and how many of them there were when the lock was taken.
    private let screenOrdinal: Int
    private let screenDuplicateCount: Int

    /// The anchor display’s size when the lock was taken.
    private let screenSize: NSSize

    /// The window’s frame relative to the anchor display’s frame origin.
    private var relativeFrame: NSRect

    /// Whether the displays have changed since the window was last known to be
    /// where it belongs. While this is set, no frame change is trustworthy, so
    /// nothing is learned from one.
    private var dormant = false

    @objc var isDormant: Bool {
        return dormant
    }

    /// Takes an anchor from the window’s current screen and frame. Fails for a
    /// window that is not on any screen, which has no location to lock.
    @objc(initWithWindow:)
    init?(window: NSWindow) {
        guard let screen = window.screen else {
            DLog("Refusing to lock the location of offscreen window \(window)")
            return nil
        }
        let key = screen.it_uniqueKey()
        let twins = Self.screens(matching: key)
        screenKey = key
        screenOrdinal = twins.firstIndex { NSEqualRects($0.frame, screen.frame) } ?? 0
        screenDuplicateCount = twins.count
        screenSize = screen.frame.size
        relativeFrame = Self.frame(window.frame, relativeTo: screen)
        super.init()
        DLog("Locked \(window) to \(self)")
    }

    private init(screenKey: String,
                 screenOrdinal: Int,
                 screenDuplicateCount: Int,
                 screenSize: NSSize,
                 relativeFrame: NSRect) {
        self.screenKey = screenKey
        self.screenOrdinal = screenOrdinal
        self.screenDuplicateCount = screenDuplicateCount
        self.screenSize = screenSize
        self.relativeFrame = relativeFrame
        super.init()
    }

    override var description: String {
        return "<\(Self.self): screen=\(screenKey) #\(screenOrdinal)/\(screenDuplicateCount) screenSize=\(NSStringFromSize(screenSize)) relativeFrame=\(NSStringFromRect(relativeFrame)) dormant=\(dormant)>"
    }

    private static func frame(_ frame: NSRect, relativeTo screen: NSScreen) -> NSRect {
        return NSRect(origin: NSPoint(x: frame.origin.x - screen.frame.origin.x,
                                      y: frame.origin.y - screen.frame.origin.y),
                      size: frame.size)
    }

    /// Displays sharing a unique key, in a stable left-to-right order so that an
    /// ordinal taken now still picks out the same monitor later.
    private static func screens(matching key: String) -> [NSScreen] {
        return NSScreen.screens.filter {
            $0.it_uniqueKey() == key
        }.sorted {
            if $0.frame.origin.x != $1.frame.origin.x {
                return $0.frame.origin.x < $1.frame.origin.x
            }
            return $0.frame.origin.y < $1.frame.origin.y
        }
    }

    // MARK: - Dormancy

    /// Stop trusting frames.
    ///
    /// Called the instant the displays change, before macOS has finished moving
    /// windows around and before -visibleFrame is even accurate. It deliberately
    /// does not ask what changed: at that moment nothing macOS hands us is the
    /// user’s intent, and a comparison against stale geometry could wrongly
    /// conclude that nothing happened.
    @objc
    func latchDormant() {
        if !dormant {
            DLog("Going dormant: the displays changed. \(self)")
        }
        dormant = true
    }

    /// Called after enforcement with the caller’s verdict on whether the window is
    /// home: at `desiredFrame` when the lock is defending a frame, on the anchor
    /// display when it is defending only a display. Learning resumes only once it
    /// is, and only while the anchor display is there at the size it was locked
    /// at. What other displays exist is irrelevant by then: the state dormancy
    /// guards against is macOS mid-shuffle, and a window sitting where the lock
    /// put it is proof the shuffle is over.
    @objc(clearDormancyIfWindowIsHome:)
    func clearDormancyIfWindowIsHome(_ isHome: Bool) {
        guard dormant, isHome, anchorScreen != nil else {
            return
        }
        DLog("Waking: the window is home. \(self)")
        dormant = false
    }

    // MARK: - Enforcement

    /// The anchor display if it is attached at all, whatever size it is now. This
    /// is all a window whose frame is computed from its screen needs, since the
    /// frame gets recomputed for the new size anyway. Nil means the lock is lying
    /// in wait.
    @objc var anchorDisplay: NSScreen? {
        let matches = Self.screens(matching: screenKey)
        guard matches.count == screenDuplicateCount else {
            // Displays sharing this key have come or gone. Either way there is no
            // longer any way to tell which one the lock was taken on, and guessing
            // would move a window that was pinned not to move.
            DLog("Display \(screenKey) had \(screenDuplicateCount) matching display(s) but \(matches.count) are attached")
            dormant = true
            return nil
        }
        guard screenOrdinal < matches.count else {
            DLog("Display \(screenKey) #\(screenOrdinal) is not attached")
            dormant = true
            return nil
        }
        return matches[screenOrdinal]
    }

    /// The anchor display, if it is attached at the size it had when the lock was
    /// taken. Restoring a remembered frame onto a display that has been resized
    /// would put the window somewhere the user never chose, so that is treated as
    /// lying in wait too.
    private var anchorScreen: NSScreen? {
        guard let screen = anchorDisplay else {
            return nil
        }
        guard NSEqualSizes(screen.frame.size, screenSize) else {
            DLog("Display \(screenKey) is \(NSStringFromSize(screen.frame.size)) but was \(NSStringFromSize(screenSize)) when locked")
            dormant = true
            return nil
        }
        return screen
    }

    /// Whether the lock currently has a frame it can defend.
    @objc var isEnforceable: Bool {
        return anchorScreen != nil
    }

    /// The frame the window belongs in, or NSZeroRect while lying in wait.
    /// Callers must check `isEnforceable` first.
    @objc var desiredFrame: NSRect {
        guard let screen = anchorScreen else {
            return .zero
        }
        return NSRect(origin: NSPoint(x: relativeFrame.origin.x + screen.frame.origin.x,
                                      y: relativeFrame.origin.y + screen.frame.origin.y),
                      size: relativeFrame.size)
    }

    /// Whether the window is sitting on the anchor display right now, regardless
    /// of whether that display has been resized.
    @objc(windowIsOnAnchorDisplay:)
    func windowIsOnAnchorDisplay(_ window: NSWindow) -> Bool {
        guard let anchor = anchorDisplay, let windowScreen = window.screen else {
            return false
        }
        // Compare frames rather than unique keys: two identical monitors share a
        // key, and being on the twin is not being home.
        return NSEqualRects(windowScreen.frame, anchor.frame)
    }

    /// Moves the anchor to follow a resize.
    ///
    /// Size belongs to Lock Size, not Lock Location. AppKit does not send
    /// -windowDidMove: when a resize changes the origin, so a frame change that
    /// changes the size is taken to be a resize and absorbed whole, origin
    /// included. A frame change that preserves the size is a move, and moves are
    /// what this lock exists to fight.
    ///
    /// Learns nothing while dormant unless the window is in a live resize, which
    /// only happens with the user dragging an edge. Learns nothing unless the
    /// window is on the anchor display at the size that display had when the lock
    /// was taken.
    @objc(absorbResizeOfWindow:)
    func absorbResize(of window: NSWindow) {
        guard !dormant || window.inLiveResize else {
            DLog("Not absorbing a resize while dormant: \(self)")
            return
        }
        guard !NSEqualSizes(relativeFrame.size, window.frame.size) else {
            return
        }
        guard let screen = anchorScreen,
              let windowScreen = window.screen,
              NSEqualRects(windowScreen.frame, screen.frame) else {
            return
        }
        let updated = Self.frame(window.frame, relativeTo: screen)
        DLog("Absorb resize to \(NSStringFromRect(updated)) into \(self)")
        relativeFrame = updated
    }

    // MARK: - Arrangements

    @objc(populateInArrangement:)
    func populate(in arrangement: iTermEncoderAdapter) {
        arrangement.setObject(screenKey, forKey: Self.screenArrangementKey)
        arrangement.setObject(screenOrdinal, forKey: Self.screenOrdinalArrangementKey)
        arrangement.setObject(screenDuplicateCount, forKey: Self.screenDuplicateCountArrangementKey)
        arrangement.setObject(NSStringFromSize(screenSize), forKey: Self.screenSizeArrangementKey)
        arrangement.setObject(NSStringFromRect(relativeFrame), forKey: Self.frameArrangementKey)
    }

    /// Reconstructs a lock from an arrangement. Returns nil when the arrangement
    /// has no lock in it, which is the case for every arrangement written before
    /// this feature existed.
    ///
    /// The result starts dormant: a lock coming out of an arrangement has no idea
    /// what the displays did while the app was closed. That also earns it a
    /// full-frame restore on its first enforcement rather than an origin-only one.
    @objc(lockFromArrangement:)
    static func lock(from arrangement: [AnyHashable: Any]) -> WindowLocationLock? {
        guard let screenKey = arrangement[screenArrangementKey] as? String,
              let screenSizeString = arrangement[screenSizeArrangementKey] as? String,
              let frameString = arrangement[frameArrangementKey] as? String else {
            return nil
        }
        let lock = WindowLocationLock(
            screenKey: screenKey,
            screenOrdinal: (arrangement[screenOrdinalArrangementKey] as? Int) ?? 0,
            screenDuplicateCount: (arrangement[screenDuplicateCountArrangementKey] as? Int) ?? 1,
            screenSize: NSSizeFromString(screenSizeString),
            relativeFrame: NSRectFromString(frameString))
        lock.dormant = true
        DLog("Restored \(lock) from arrangement")
        return lock
    }
}
