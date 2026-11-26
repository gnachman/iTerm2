//
//  iTermSpacesRestorationNotice.swift
//  iTerm2
//
//  “Restore windows to same Spaces” now defaults to on. The first time a user
//  who never changed that setting gets a window restored to a Space other than
//  the current one, explain what happened and offer to turn it back off.
//  Launches where AppKit would have restored Spaces anyway (after an update
//  restart, or the system relaunching apps after a restart or logout) don’t
//  count, since nothing changed for the user.
//

import AppKit

@objc(iTermSpacesRestorationNotice)
final class SpacesRestorationNotice: NSObject {
    // Localization unneeded
    private static let shownKey = "NoSyncRestoreWindowsToSameSpacesNoticeShown"
    // Whether the conditions known before restoration allow the notice. Cleared once restored
    // windows have been handed over, so it is decided at most once per launch.
    private static var eligible = false
    // Whether loginwindow relaunched iTerm2 to reopen its windows after a restart or logout. Nil
    // until applicationDidFinishLaunching, when the launch's open-application event can be read.
    private static var relaunchedByLoginWindow: Bool?
    // Restored windows handed over before relaunchedByLoginWindow was known.
    private static var pendingWindows: [WeakBox<NSWindow>]?

    // Call from applicationWillFinishLaunching, before window restoration begins. forcedByUpdate is
    // true when windows return to their Spaces for a one-time reason (such as an update restart)
    // that predates the new default, in which case nothing changed for the user and there is
    // nothing to explain.
    @objc(applicationWillRestoreWindowsForcedByUpdate:)
    static func applicationWillRestoreWindows(forcedByUpdate: Bool) {
        if iTermUserDefaults.userDefaults().bool(forKey: shownKey) {
            eligible = false
            return
        }
        let key = kPreferenceKeyRestoreWindowsToSameSpaces
        // Windows opened from an arrangement at startup may be moved to their saved Spaces on
        // purpose, which has nothing to do with this setting. The setting applies only when
        // windows come from system window restoration.
        let opensArrangementOrNothing = (iTermPreferences.bool(forKey: kPreferenceKeyOpenArrangementAtStartup) ||
                                         iTermPreferences.bool(forKey: kPreferenceKeyOpenNoWindowsAtStartup))
        eligible = (!forcedByUpdate &&
                    !opensArrangementOrNothing &&
                    iTermPreferences.bool(forKey: key) &&
                    !iTermPreferences.valueIsExplicitlySet(forKey: key))
        DLog("forcedByUpdate=\(forcedByUpdate) opensArrangementOrNothing=\(opensArrangementOrNothing) eligible=\(eligible)")
    }

    // Call from applicationDidFinishLaunching. AppKit posts WillFinishLaunching before it
    // dispatches the launch's open-application event, and DidFinishLaunching from that event's
    // handler, so this is where the event can be read.
    @objc
    static func applicationDidFinishLaunching() {
        let value = wasRelaunchedByLoginWindow()
        relaunchedByLoginWindow = value
        DLog("relaunchedByLoginWindow=\(value)")
        if let pending = pendingWindows {
            pendingWindows = nil
            considerShowingNotice(for: pending.compactMap(\.value))
        }
    }

    // When macOS relaunches apps after a restart or logout (“Reopen windows when logging back
    // in”), AppKit already puts windows back on their Spaces, so the new default changes nothing.
    // loginwindow marks that relaunch with 'rsto' = 'yes ' in the open-application event (seen on
    // macOS 27). An ordinary login item launch is marked differently (keyAEPropData =
    // keyAELaunchedAsLogInItem, with no 'rsto'), and AppKit did not restore Spaces for it before,
    // so it stays eligible, as does a launch by the user.
    private static func wasRelaunchedByLoginWindow() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        DLog("Launch Apple event: \(String(describing: event))")
        guard let event,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication) else {
            return false
        }
        // A parameter of type typeType whose value is 'yes '.
        guard let value = event.paramDescriptor(forKeyword: fourCharCode("rsto")) else {
            return false
        }
        return value.typeCodeValue == fourCharCode("yes ")
    }

    private static func fourCharCode(_ string: String) -> FourCharCode {
        return string.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    // Call once restoration has finished. Shows the notice at most once ever, and only if a
    // window actually landed on a Space other than the current one.
    @objc(windowsDidFinishRestoring:)
    static func windowsDidFinishRestoring(_ windows: [NSWindow]) {
        guard eligible else {
            return
        }
        eligible = false
        guard relaunchedByLoginWindow != nil else {
            DLog("Restoration finished before applicationDidFinishLaunching; deciding later")
            pendingWindows = windows.map { WeakBox($0) }
            return
        }
        considerShowingNotice(for: windows)
    }

    // How long to wait for the window server to put restored windows on their Spaces. It normally
    // takes a fraction of a second; this only bounds the wait if a window never gets one.
    private static let placementTimeout: TimeInterval = 5
    // How long to wait for the moveToActiveSpace fallback to bring a window over before logging
    // that it didn't.
    private static let fallbackTimeout: TimeInterval = 2

    private static func considerShowingNotice(for windows: [NSWindow]) {
        if relaunchedByLoginWindow == true {
            DLog("Relaunched by loginwindow, which restores Spaces anyway; no notice")
            return
        }
        let candidates = windows.filter(couldBeOffSpace)
        guard !candidates.isEmpty else {
            DLog("None of \(windows.count) restored windows could be on another Space")
            return
        }
        // When restoration reports that it's done, AppKit may not have put the windows on their
        // Spaces yet. Until it does, the window server reports no Space for a window and
        // isOnActiveSpace is true, so wait until every candidate has a Space.
        let weakCandidates = candidates.map { WeakBox($0) }
        let weakRestored = windows.map { WeakBox($0) }
        WindowConditionWaiter.wait(timeout: placementTimeout,
                                   condition: {
            weakCandidates.compactMap(\.value).allSatisfy {
                // Nil means the private functions are missing; then there's nothing to wait for.
                iTermWindowSpace.isOnAnySpace($0) != false
            }
        }, completion: { placed in
            if !placed {
                DLog("Timed out waiting for restored windows to be put on Spaces; deciding anyway")
            }
            decide(candidates: weakCandidates.compactMap(\.value),
                   restored: weakRestored,
                   total: windows.count)
        })
    }

    private static func decide(candidates: [NSWindow], restored: [WeakBox<NSWindow>], total: Int) {
        let offSpace = candidates.filter { couldBeOffSpace($0) && !$0.isOnActiveSpace }
        DLog("\(offSpace.count) of \(total) restored windows are on another Space")
        guard !offSpace.isEmpty else {
            return
        }
        iTermUserDefaults.userDefaults().set(true, forKey: shownKey)
        // When the notice closes, AppKit makes the window that was key before it key again, and if
        // that window is on another Space the user is switched there. So pick the key window now.
        keepUserOnCurrentSpace(restoredWindows: restored)
        showNotice(offSpaceWindows: offSpace.map { WeakBox($0) }, restoredWindows: restored)
    }

    // Whether this setting could be why the window is not on the current Space, not counting
    // where it is now. A full screen window always gets its own Space, and a window on all Spaces
    // is on the current one anyway. A window from an arrangement (such as one an AutoLaunch script
    // restores) may have been put on its saved Space by the arrangement, which this setting has
    // nothing to do with.
    private static func couldBeOffSpace(_ window: NSWindow) -> Bool {
        return (window.isVisible &&
                !window.isMiniaturized &&
                !window.styleMask.contains(.fullScreen) &&
                !window.collectionBehavior.contains(.canJoinAllSpaces) &&
                !WindowSpaceRestorer.shared.wasAskedToMove(window))
    }

    // Turns the setting off and brings the windows that landed on other Spaces to the current
    // one. The notice is asynchronous, so this re-checks each window: it may have closed, or the
    // user may have moved it or switched Spaces while the notice was up.
    private static func revert(offSpaceWindows: [WeakBox<NSWindow>]) {
        DLog("User turned off restoring windows to same Spaces")
        iTermPreferences.setBool(false, forKey: kPreferenceKeyRestoreWindowsToSameSpaces)
        for window in offSpaceWindows.compactMap(\.value) where couldBeOffSpace(window) && !window.isOnActiveSpace {
            switch iTermWindowSpace.moveToCurrentSpace(window) {
            case .moved:
                continue
            case .refused:
                DLog("Leaving \(window) where it is: its display's current Space is not a desktop")
                continue
            case .unavailable:
                break
            }
            // moveToActiveSpace goes to the active Space, which is on the display the user is
            // working on. Use it only when that is the window's own display, so it can't pull a
            // window across displays.
            guard !NSScreen.screensHaveSeparateSpaces || window.screen == NSScreen.main else {
                DLog("Leaving \(window) where it is: it is not on the display with the active Space")
                continue
            }
            // Without the private functions (or if the window server ignored the move), have
            // AppKit bring the window to the active Space. moveToActiveSpace acts when the window
            // is made active, so it must become key; merely ordering it front could switch the user
            // to the window's Space instead.
            DLog("Falling back to moveToActiveSpace for \(window)")
            let savedBehavior = window.collectionBehavior
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            let weakWindow = WeakBox(window)
            WindowConditionWaiter.wait(timeout: fallbackTimeout,
                                       condition: { weakWindow.value?.isOnActiveSpace ?? true },
                                       completion: { moved in
                guard let window = weakWindow.value else {
                    return
                }
                window.collectionBehavior = savedBehavior
                if !moved {
                    DLog("Fallback did not bring \(window) to the active Space")
                }
            })
        }
    }

    // If the key window is on another Space, make a restored window on the current Space key
    // instead, so that AppKit doesn't switch the user to the key window's Space.
    private static func keepUserOnCurrentSpace(restoredWindows: [WeakBox<NSWindow>]) {
        if let key = NSApp.keyWindow, key.isOnActiveSpace {
            return
        }
        guard let window = restoredWindows.compactMap(\.value).first(where: {
            $0.isVisible && !$0.isMiniaturized && $0.isOnActiveSpace
        }) else {
            DLog("No restored window on the current Space to make key")
            return
        }
        DLog("Making \(window) key so the user stays on the current Space")
        window.makeKeyAndOrderFront(nil)
    }

    private static func showNotice(offSpaceWindows: [WeakBox<NSWindow>],
                                   restoredWindows: [WeakBox<NSWindow>]) {
        let warning = iTermWarning()
        warning.heading = String(localized: "SpacesRestorationNotice.Heading",
                                 defaultValue: "Windows Restored to Their Spaces",
                                 comment: "Heading of a one-time notice shown after iTerm2 relaunches and puts restored windows back on the Spaces (virtual desktops) they were on, instead of on the current Space")
        warning.title = String(localized: "SpacesRestorationNotice.Body",
                               defaultValue: "iTerm2 now puts restored windows back on the Spaces they were on when it quit, so some of your windows are on other Spaces. You can change this later with “Restore windows to same Spaces” in Settings > General > Startup.",
                               comment: "Body of a one-time notice explaining that restored windows were put back on their original Spaces (virtual desktops). “Restore windows to same Spaces” is the title of a checkbox in Settings and should match its translation.")
        warning.actionLabels = [
            String(localized: "SpacesRestorationNotice.Keep",
                   defaultValue: "Keep Windows on Their Spaces",
                   comment: "Button in a one-time notice that keeps the new behavior of restoring windows to their original Spaces"),
            String(localized: "SpacesRestorationNotice.Revert",
                   defaultValue: "Restore Windows to Current Space",
                   comment: "Button in a one-time notice that moves the restored windows to the current Space now and turns off restoring windows to their original Spaces, so future relaunches put every window on the current Space")
        ]
        warning.warningType = .kiTermWarningTypePersistent
        // runModalAsync does not run iTermWarningAction blocks, so act on the selection here.
        warning.runModalAsync { selection, _ in
            if selection == .kiTermWarningSelection1 {
                revert(offSpaceWindows: offSpaceWindows)
            } else {
                DLog("User kept restoring windows to same Spaces")
            }
            // Check again once AppKit has finished restoring key status after the notice.
            DispatchQueue.main.async {
                keepUserOnCurrentSpace(restoredWindows: restoredWindows)
            }
        }
    }
}

// Calls completion(true) once condition() holds, or completion(false) after the timeout. It
// re-evaluates when any window's occlusion state changes or the active Space changes, and also
// every pollInterval: the window server puts a restored window on a hidden Space without any
// notification (the window stays occluded), so there is nothing to observe for that. The first
// check is on the next turn of the main queue, so completion never runs inside the caller.
private final class WindowConditionWaiter {
    private static var waiters = [ObjectIdentifier: WindowConditionWaiter]()

    private let condition: () -> Bool
    private let completion: (Bool) -> Void
    private var observers = [(NotificationCenter, NSObjectProtocol)]()
    private var pollTimer: Timer?
    private var finished = false
    private static let pollInterval: TimeInterval = 0.1

    static func wait(timeout: TimeInterval,
                     condition: @escaping () -> Bool,
                     completion: @escaping (Bool) -> Void) {
        let waiter = WindowConditionWaiter(condition: condition, completion: completion)
        waiters[ObjectIdentifier(waiter)] = waiter
        waiter.start(timeout: timeout)
    }

    private init(condition: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        self.condition = condition
        self.completion = completion
    }

    private func start(timeout: TimeInterval) {
        let check: (Notification) -> Void = { [weak self] _ in
            self?.check()
        }
        observers.append((NotificationCenter.default,
                          NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                                 object: nil,
                                                                 queue: .main,
                                                                 using: check)))
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append((workspaceCenter,
                          workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                      object: nil,
                                                      queue: .main,
                                                      using: check)))
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(false)
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.check()
        }
        DispatchQueue.main.async { [weak self] in
            self?.check()
        }
    }

    private func check() {
        if condition() {
            finish(true)
        }
    }

    private func finish(_ satisfied: Bool) {
        if finished {
            return
        }
        finished = true
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        Self.waiters.removeValue(forKey: ObjectIdentifier(self))
        completion(satisfied)
    }
}
