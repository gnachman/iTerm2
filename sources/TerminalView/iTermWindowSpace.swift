//
//  iTermWindowSpace.swift
//  iTerm2
//

import AppKit
import ColorSync

/// Remembers which Space (virtual desktop) a window is on and puts it back there.
///
/// macOS has no public API for this, so it uses private CoreGraphics functions
/// looked up at runtime. If one is missing, the methods that need it do nothing
/// and the window stays wherever macOS opened it.
///
/// A Space is saved by the UUID macOS keeps for it, and also by its display and
/// its position among that display's desktops. Restoring uses the UUID while
/// that desktop exists. macOS never reuses a closed desktop's UUID, so after it
/// is closed the window goes to the desktop now in the same position, the way
/// the user sees it numbered in Mission Control. Space IDs (ManagedSpaceID) are
/// not stable and are never stored.
///
/// Since macOS 14.5 the window server only lets a process move windows it owns,
/// and it ignores other moves without reporting an error. iTerm2 only moves its
/// own windows, but a later macOS could tighten this further, so a move that did
/// not take is logged.
@objc(iTermWindowSpace)
class iTermWindowSpace: NSObject {
    /// The window arrangement key holding the value from arrangementValue(for:).
    @objc static let arrangementKey = "Space"

    private static let uuidKey = "UUID"  // Localization unneeded
    private static let displayKey = "Display"  // Localization unneeded
    private static let indexKey = "Index"  // Localization unneeded

    /// CGSCopySpacesForWindows mask meaning “all Spaces the window is on”.
    private static let allSpacesMask: Int32 = 7

    /// The "type" of an ordinary desktop in CGSCopyManagedDisplaySpaces. Full
    /// screen Spaces have other types and are left to macOS.
    private static let desktopType = 0

    /// The "Display Identifier" used when all displays share one set of Spaces.
    private static let sharedDisplayIdentifier = "Main"

    // MARK: - Private functions

    private typealias MainConnectionFunction = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFunction = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindowsFunction = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias MoveWindowsToManagedSpaceFunction = @convention(c) (Int32, CFArray, UInt64) -> Void

    /// Looks up a function in ApplicationServices, which re-exports the
    /// window server functions, or returns nil if this macOS lacks it.
    private static func function<T>(named name: String, as type: T.Type) -> T? {
        let url = URL(fileURLWithPath: "/System/Library/Frameworks/ApplicationServices.framework") as CFURL
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url),
              let pointer = CFBundleGetFunctionPointerForName(bundle, name as CFString) else {
            DLog("\(name) is not available")
            return nil
        }
        return unsafeBitCast(pointer, to: type)
    }

    private static let mainConnection = function(named: "CGSMainConnectionID",
                                                 as: MainConnectionFunction.self)
    private static let copyManagedDisplaySpaces = function(named: "CGSCopyManagedDisplaySpaces",
                                                           as: CopyManagedDisplaySpacesFunction.self)
    private static let copySpacesForWindows = function(named: "CGSCopySpacesForWindows",
                                                       as: CopySpacesForWindowsFunction.self)
    private static let moveWindowsToManagedSpace = function(named: "CGSMoveWindowsToManagedSpace",
                                                            as: MoveWindowsToManagedSpaceFunction.self)

    // MARK: - Desktops

    struct Desktop: Equatable {
        var spaceID: UInt64
        /// The Space's UUID. Some macOS versions report an empty one for a
        /// display's original desktop.
        var uuid: String
        /// A display UUID, or "Main" when displays share Spaces.
        var displayIdentifier: String
        /// The position among the display's ordinary desktops, from 0. Mission
        /// Control calls it Desktop index+1.
        var index: Int
    }

    /// Every ordinary desktop on every display, in order.
    static func desktops() -> [Desktop]? {
        guard let mainConnection, let copyManagedDisplaySpaces else {
            return nil
        }
        guard let displays = copyManagedDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else {
            DLog("CGSCopyManagedDisplaySpaces returned something unexpected")
            return nil
        }
        var result = [Desktop]()
        for display in displays {
            guard let displayIdentifier = display["Display Identifier"] as? String,
                  let spaces = display["Spaces"] as? [[String: Any]] else {
                continue
            }
            var index = 0
            for space in spaces {
                guard let spaceID = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value,
                      (space["type"] as? NSNumber)?.intValue == desktopType else {
                    continue
                }
                result.append(Desktop(spaceID: spaceID,
                                      uuid: (space["uuid"] as? String) ?? "",
                                      displayIdentifier: displayIdentifier,
                                      index: index))
                index += 1
            }
        }
        return result
    }

    /// The arrangement value describing a desktop.
    static func arrangementValue(for desktop: Desktop) -> [String: Any] {
        var value: [String: Any] = [displayKey: desktop.displayIdentifier,
                                    indexKey: desktop.index]
        if !desktop.uuid.isEmpty {
            value[uuidKey] = desktop.uuid
        }
        return value
    }

    /// The desktop an arrangement value refers to: the one with its UUID if that
    /// still exists, or else the one in its position on its display, or nil if
    /// that display has too few desktops. Values saved before the position was
    /// recorded have only a UUID.
    static func desktop(forArrangementValue value: [String: Any], among desktops: [Desktop]) -> Desktop? {
        if let uuid = value[uuidKey] as? String, !uuid.isEmpty,
           let desktop = desktops.first(where: { $0.uuid == uuid }) {
            return desktop
        }
        guard let display = value[displayKey] as? String,
              let index = (value[indexKey] as? NSNumber)?.intValue else {
            return nil
        }
        return desktops.first {
            $0.index == index && $0.displayIdentifier.caseInsensitiveCompare(display) == .orderedSame
        }
    }

    /// The IDs of the Spaces the window is on.
    private static func spaceIDs(of window: NSWindow) -> [UInt64]? {
        guard let mainConnection, let copySpacesForWindows, window.windowNumber > 0 else {
            return nil
        }
        let ids = copySpacesForWindows(mainConnection(),
                                       allSpacesMask,
                                       [window.windowNumber] as CFArray)?.takeRetainedValue() as? [NSNumber]
        return ids?.map { $0.uint64Value }
    }

    /// The UUID CGSCopyManagedDisplaySpaces uses for the screen's display.
    static func displayIdentifier(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// A desktop an arrangement value refers to that does not exist because its
    /// display, which is connected, has too few desktops. The user can fix that
    /// by adding desktops in Mission Control.
    struct MissingDesktop: Equatable {
        /// A display UUID, or "Main" when displays share Spaces.
        var displayIdentifier: String
        /// The position among the display's desktops, from 0.
        var index: Int
    }

    /// Why desktop(forArrangementValue:among:) found nothing, when the answer is
    /// that the display needs more desktops. Nil when there is a desktop, when the
    /// value has no position, or when its display is not connected.
    static func missingDesktop(forArrangementValue value: [String: Any], among desktops: [Desktop]) -> MissingDesktop? {
        if desktop(forArrangementValue: value, among: desktops) != nil {
            return nil
        }
        guard let display = value[displayKey] as? String,
              let index = (value[indexKey] as? NSNumber)?.intValue,
              index >= 0 else {
            return nil
        }
        let onDisplay = desktops.filter { $0.displayIdentifier.caseInsensitiveCompare(display) == .orderedSame }
        guard let first = onDisplay.first, index >= onDisplay.count else {
            return nil
        }
        return MissingDesktop(displayIdentifier: first.displayIdentifier, index: index)
    }

    /// The name of a connected display, or nil when displays share Spaces or it
    /// is not connected.
    static func displayName(forIdentifier identifier: String) -> String? {
        guard identifier != sharedDisplayIdentifier else {
            return nil
        }
        return NSScreen.screens.first {
            displayIdentifier(of: $0)?.caseInsensitiveCompare(identifier) == .orderedSame
        }?.localizedName
    }

    /// Whether the window server has put the window on at least one Space. Right
    /// after state restoration AppKit may not have yet, and then the window has
    /// none. Nil if the private functions are missing.
    static func isOnAnySpace(_ window: NSWindow) -> Bool? {
        guard let ids = spaceIDs(of: window) else {
            return nil
        }
        return !ids.isEmpty
    }

    /// What CGSCopyManagedDisplaySpaces says is showing on a window's display.
    private enum CurrentSpace {
        /// An ordinary desktop, with its ID.
        case desktop(UInt64)
        /// Something a window must not be moved into, such as a full screen
        /// app's Space, or a display that can't be matched up.
        case notADesktop
        /// The private functions are missing or returned something unexpected.
        case unavailable
    }

    /// The Space currently shown on the display holding the window's frame.
    /// When displays share Spaces there is one current Space for all.
    private static func currentSpace(forDisplayOf window: NSWindow) -> CurrentSpace {
        guard let mainConnection, let copyManagedDisplaySpaces else {
            return .unavailable
        }
        guard let displays = copyManagedDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else {
            DLog("CGSCopyManagedDisplaySpaces returned something unexpected")
            return .unavailable
        }
        let screenIdentifier = window.screen.flatMap { displayIdentifier(of: $0) }
        let display = displays.first { display in
            guard let identifier = display["Display Identifier"] as? String else {
                return false
            }
            if identifier == sharedDisplayIdentifier {
                return true
            }
            guard let screenIdentifier else {
                return false
            }
            return identifier.caseInsensitiveCompare(screenIdentifier) == .orderedSame
        }
        guard let display,
              let current = display["Current Space"] as? [String: Any],
              let spaceID = (current["ManagedSpaceID"] as? NSNumber)?.uint64Value else {
            DLog("No current Space found for the display of window \(window)")
            return .notADesktop
        }
        // A display showing a full screen app has that app's Space as its current one. Never put
        // a window there; full screen Spaces are left to macOS.
        guard (current["type"] as? NSNumber)?.intValue == desktopType else {
            DLog("Current Space \(spaceID) for the display of window \(window) is not an ordinary desktop")
            return .notADesktop
        }
        return .desktop(spaceID)
    }

    enum MoveToCurrentSpaceResult {
        /// The window is on its display's current Space.
        case moved
        /// The private functions are missing, or the window server ignored the
        /// move. Some other way of moving the window may still work.
        case unavailable
        /// The window must not be moved: its display's current Space is not an
        /// ordinary desktop (as when it is showing a full screen app), or the
        /// display couldn't be matched up. Don't try another way.
        case refused
    }

    /// Moves the window to the Space currently shown on the display its frame is
    /// on. It never moves a window to another display's Space, for the same
    /// reason move(_:toSpaceFromArrangementValue:) refuses to.
    static func moveToCurrentSpace(_ window: NSWindow) -> MoveToCurrentSpaceResult {
        guard let mainConnection, let moveWindowsToManagedSpace, window.windowNumber > 0 else {
            DLog("Can't move window \(window): function or window number unavailable")
            return .unavailable
        }
        let spaceID: UInt64
        switch currentSpace(forDisplayOf: window) {
        case .desktop(let id):
            spaceID = id
        case .notADesktop:
            return .refused
        case .unavailable:
            return .unavailable
        }
        if spaceIDs(of: window) == [spaceID] {
            DLog("Window \(window) is already on current Space \(spaceID)")
            return .moved
        }
        DLog("Move window \(window) to current Space \(spaceID)")
        moveWindowsToManagedSpace(mainConnection(), [window.windowNumber] as CFArray, spaceID)
        let after = spaceIDs(of: window)
        if after != [spaceID] {
            DLog("Window \(window) is on Spaces \(String(describing: after)) after the move, not \(spaceID). The window server may have ignored it.")
            return .unavailable
        }
        return .moved
    }

    // MARK: - API

    /// Whether this macOS has the functions needed to save and restore Spaces.
    @objc static var isAvailable: Bool {
        return mainConnection != nil &&
            copyManagedDisplaySpaces != nil &&
            copySpacesForWindows != nil &&
            moveWindowsToManagedSpace != nil
    }

    /// A copy of a window's arrangement that opens on the current Space.
    @objc(arrangementByRemovingSpace:)
    static func arrangementByRemovingSpace(_ arrangement: [AnyHashable: Any]) -> [AnyHashable: Any] {
        var result = arrangement
        result.removeValue(forKey: arrangementKey)
        return result
    }

    /// A dictionary describing the Space the window is on, suitable for an
    /// arrangement, or nil if the window is not on exactly one ordinary desktop
    /// (for example when it is on all Spaces or in full screen).
    @objc(arrangementValueForWindow:)
    static func arrangementValue(for window: NSWindow) -> [String: Any]? {
        if window.collectionBehavior.contains(.canJoinAllSpaces) {
            return nil
        }
        guard let ids = spaceIDs(of: window) else {
            return nil
        }
        guard ids.count == 1, let id = ids.first else {
            DLog("Window \(window) is on \(ids.count) Spaces; not saving one")
            return nil
        }
        guard let desktop = desktops()?.first(where: { $0.spaceID == id }) else {
            DLog("Space \(id) of window \(window) is not an ordinary desktop")
            return nil
        }
        return arrangementValue(for: desktop)
    }

    /// Moves the window to the Space described by a value from
    /// arrangementValue(for:) (see desktop(forArrangementValue:among:)). Does
    /// nothing if there is no such desktop, since there is no supported way to
    /// create one, or if it belongs to a display other than the one the window is
    /// on, since moving it there would leave its frame on a display that is not
    /// showing it.
    @objc(moveWindow:toSpaceFromArrangementValue:)
    static func move(_ window: NSWindow, toSpaceFromArrangementValue value: [String: Any]?) {
        guard let value, !value.isEmpty else {
            return
        }
        guard let mainConnection, let moveWindowsToManagedSpace, window.windowNumber > 0 else {
            DLog("Can't move window \(window): function or window number unavailable")
            return
        }
        guard let desktop = desktop(forArrangementValue: value, among: desktops() ?? []) else {
            DLog("No desktop matches \(value); leaving window \(window) where it is")
            return
        }
        if desktop.displayIdentifier != sharedDisplayIdentifier,
           let screen = window.screen,
           let screenIdentifier = displayIdentifier(of: screen),
           screenIdentifier.caseInsensitiveCompare(desktop.displayIdentifier) != .orderedSame {
            DLog("Desktop \(desktop) is on display \(desktop.displayIdentifier) but window \(window) is on \(screenIdentifier); leaving it where it is")
            return
        }
        if spaceIDs(of: window) == [desktop.spaceID] {
            DLog("Window \(window) is already on Space \(desktop.spaceID)")
            return
        }
        DLog("Move window \(window) to desktop \(desktop)")
        moveWindowsToManagedSpace(mainConnection(), [window.windowNumber] as CFArray, desktop.spaceID)
        let after = spaceIDs(of: window)
        if after != [desktop.spaceID] {
            DLog("Window \(window) is on Spaces \(String(describing: after)) after the move, not \(desktop.spaceID). The window server may have ignored it.")
        }
    }
}

@objc
extension PseudoTerminal {
    /// Records the window’s Space in its arrangement. Called only for a window’s
    /// own arrangement: tabs saved on their own open in a new window, which
    /// should appear where the user is. A hotkey window has no Space of its own,
    /// since it appears on whatever Space the hotkey is pressed on.
    @objc(addSpaceToArrangement:)
    func addSpace(toArrangement arrangement: NSMutableDictionary) {
        guard !isHotKeyWindow(),
              let window,
              let value = iTermWindowSpace.arrangementValue(for: window) else {
            return
        }
        arrangement[iTermWindowSpace.arrangementKey] = value
    }

    /// Puts the window back on the Space it was saved from.
    ///
    /// This waits a turn of the runloop so the window has been ordered in at its
    /// saved frame first; otherwise ordering it in would put it back on the
    /// active Space. A window that joins all Spaces stays that way.
    ///
    /// Session restoration also loads arrangements, but there macOS decides the
    /// Space (Settings > General > Startup > Restore windows to same Spaces), so
    /// only arrangements the user opens are moved. Hotkey windows are skipped.
    @objc(restoreSpaceFromArrangement:)
    func restoreSpace(fromArrangement arrangement: [AnyHashable: Any]) {
        guard let value = arrangement[iTermWindowSpace.arrangementKey] as? [String: Any],
              !isPerformingSessionRestoration,
              !isHotKeyWindow(),
              let window,
              !window.collectionBehavior.contains(.canJoinAllSpaces) else {
            return
        }
        WindowSpaceRestorer.shared.enqueue(window, value: value)
    }
}
