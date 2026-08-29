//
//  iTermSleepPreventionCoordinator.swift
//  iTerm2SharedARC
//
//  Holds a single system-idle-sleep assertion while at least one live session has the
//  KEY_PREVENT_SLEEP profile setting enabled, subject to an AC-power preference. The held
//  state is always re-derived from current state (never an incremental counter), so it cannot
//  leak an assertion: any transient inconsistency is corrected by the next recompute.
//

import Foundation

@objc(iTermSleepPreventionCoordinator)
class SleepPreventionCoordinator: NSObject {
    @objc static let instance = SleepPreventionCoordinator()

    // Posted (on the main thread) whenever either published count changes.
    @objc static let didChangeNotification = NSNotification.Name("iTermSleepPreventionCoordinatorDidChange")

    // The number of sessions currently keeping the machine awake: the requesters when the assertion
    // is held, else 0 (no requesters, or gated off on battery). Observe didChangeNotification to
    // track changes.
    @objc private(set) var numberOfSessionsPreventingSleep: Int = 0

    // The number of sessions that WANT to prevent sleep (KEY_PREVENT_SLEEP enabled, not exited),
    // regardless of the AC-power gate. When this is > 0 but numberOfSessionsPreventingSleep is 0,
    // the requesters exist but are gated off on battery -- the status label distinguishes that from
    // "no sessions want to prevent sleep".
    @objc private(set) var numberOfSessionsRequestingPreventSleep: Int = 0

    // The NSProcessInfo activity token. Non-nil exactly while we are holding the assertion.
    private var activity: NSObjectProtocol?

    private override init() {
        super.init()
        DLog("SleepPreventionCoordinator initializing")

        let center = NotificationCenter.default
        // Session lifecycle: a session appearing/disappearing changes the set we fold over.
        center.addObserver(self, selector: #selector(recomputeFromNotification(_:)),
                           name: .PTYSessionCreated, object: nil)
        center.addObserver(self, selector: #selector(recomputeFromNotification(_:)),
                           name: .PTYSessionRevived, object: nil)
        center.addObserver(self, selector: #selector(recomputeFromNotification(_:)),
                           name: .iTermSessionWillTerminate, object: nil)
        // A session's profile changed (including a trigger toggling KEY_PREVENT_SLEEP via a
        // session-specific override). kSessionProfileDidChange is only posted on the divorced
        // (session-specific) path, so also observe the general profile reload that drives the
        // common non-divorced case (toggling the checkbox on a shared profile in Settings).
        center.addObserver(self, selector: #selector(recomputeFromNotification(_:)),
                           name: NSNotification.Name(kSessionProfileDidChange), object: nil)
        center.addObserver(self, selector: #selector(recomputeFromNotification(_:)),
                           name: NSNotification.Name(kReloadAllProfiles), object: nil)
        // Power source changed: the AC-only gate may now permit or forbid the assertion.
        center.addObserver(self, selector: #selector(recomputeFromNotification(_:)),
                           name: NSNotification.Name(iTermPowerManagerStateDidChange), object: nil)
        // The preventSleepOnBatteryToo advanced setting may have changed.
        center.addObserver(self, selector: #selector(recomputeFromNotification(_:)),
                           name: NSNotification.Name(iTermAdvancedSettingsDidChange), object: nil)
        // A session was buried or un-buried. Buried sessions still exist (and still count as
        // requesters), but they leave their window so allSessions() no longer enumerates them.
        center.addObserver(self, selector: #selector(recomputeFromNotification(_:)),
                           name: .iTermSessionBuriedStateChangeTab, object: nil)

        recompute()
    }

    @objc private func recomputeFromNotification(_ notification: Notification) {
        if notification.name == .iTermSessionWillTerminate,
           let session = notification.object as? PTYSession {
            // At -iTermSessionWillTerminate time the terminating session is still enumerated by
            // allSessions() (it is not removed from its tab until later in -terminate, and delivery
            // is synchronous). Exclude it explicitly; otherwise, when it is the last requester,
            // want would stay true and the assertion would be held until some unrelated recompute.
            recompute(excluding: session)
        } else if notification.name == NSNotification.Name(kReloadAllProfiles) {
            // kReloadAllProfiles is ALSO observed by each PseudoTerminal, which is what actually
            // updates a session's _profile (reloadBookmarks -> sharedProfileDidChange -> setProfile:).
            // NSNotificationCenter delivers in registration order and this singleton registered
            // early (at app launch), so it would otherwise run before the sessions update their
            // profiles and read the stale (pre-toggle) KEY_PREVENT_SLEEP. Defer to the next
            // main-queue turn so every session has updated its profile first (coalesced).
            scheduleDeferredRecompute()
        } else {
            recompute(excluding: nil)
        }
    }

    private var deferredRecomputeScheduled = false

    private func scheduleDeferredRecompute() {
        if deferredRecomputeScheduled {
            return
        }
        deferredRecomputeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.deferredRecomputeScheduled = false
            self.recompute()
        }
    }

    /// The GUIDs of sessions that currently want the assertion held. Includes buried sessions:
    /// they still exist (the profile doc says the assertion is held "while a session with this
    /// setting enabled exists"), but allSessions() only enumerates sessions in a window.
    private func requestingSessionGUIDs() -> [String] {
        let live = iTermController.sharedInstance().allSessions() ?? []
        let buried = iTermBuriedSessions.sharedInstance()?.buriedSessions() ?? []
        return (live + buried).compactMap { session -> String? in
            // A session whose process has died but whose pane is still open (endAction "Do
            // nothing") is not doing work; it must not keep the Mac awake. brokenPipe posts nothing
            // this coordinator observes, so exclude exited sessions here and recompute on brokenPipe.
            guard !session.exited,
                  let profile = session.profile,
                  iTermProfilePreferences.bool(forKey: KEY_PREVENT_SLEEP, inProfile: profile) else {
                return nil
            }
            return session.guid
        }
    }

    /// The number of distinct sessions that keep the machine awake given the current requester
    /// GUIDs, a session to exclude (e.g. one that is terminating), and the power gate. Deduplicates
    /// GUIDs because a session transiently appears in both allSessions() and buriedSessions() while
    /// it is being buried. Extracted so it can be unit-tested without live sessions or NSProcessInfo.
    static func numberOfSessionsPreventingSleep(requesterGUIDs: [String],
                                                excludingGUID: String?,
                                                connectedToPower: Bool,
                                                allowedOnBattery: Bool) -> Int {
        guard connectedToPower || allowedOnBattery else {
            return 0
        }
        return numberOfSessionsRequestingPreventSleep(requesterGUIDs: requesterGUIDs,
                                                      excludingGUID: excludingGUID)
    }

    /// The number of distinct sessions that WANT to prevent sleep, ignoring the power gate.
    static func numberOfSessionsRequestingPreventSleep(requesterGUIDs: [String],
                                                       excludingGUID: String?) -> Int {
        return Set(requesterGUIDs.filter { $0 != excludingGUID }).count
    }

    /// Re-derive whether the assertion should be held and reconcile the token to match.
    @objc func recompute() {
        recompute(excluding: nil)
    }

    private func recompute(excluding excludedSession: PTYSession?) {
        iTermGCD.assertMainQueueSafe()
        let requesterGUIDs = requestingSessionGUIDs()
        let onPower = iTermPowerManager.sharedInstance().connectedToPower
        let allowedOnBattery = iTermAdvancedSettingsModel.preventSleepOnBatteryToo()
        let count = Self.numberOfSessionsPreventingSleep(requesterGUIDs: requesterGUIDs,
                                                         excludingGUID: excludedSession?.guid,
                                                         connectedToPower: onPower,
                                                         allowedOnBattery: allowedOnBattery)
        let requesters = Self.numberOfSessionsRequestingPreventSleep(requesterGUIDs: requesterGUIDs,
                                                                     excludingGUID: excludedSession?.guid)
        let want = count > 0

        DLog("SleepPreventionCoordinator recompute: requesters=\(requesters) excluding=\(excludedSession?.guid ?? "(none)") onPower=\(onPower) allowedOnBattery=\(allowedOnBattery) count=\(count) held=\(activity != nil)")

        if want && activity == nil {
            RLog("SleepPreventionCoordinator: taking system idle sleep assertion (\(count) session(s))")
            activity = ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled,
                                                             reason: "iTerm2: profile prevents sleep")
        } else if !want, let activity {
            RLog("SleepPreventionCoordinator: releasing system idle sleep assertion")
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }

        // Publish both counts for the status label; notify observers if either changed.
        let changed = (numberOfSessionsPreventingSleep != count) ||
                      (numberOfSessionsRequestingPreventSleep != requesters)
        numberOfSessionsPreventingSleep = count
        numberOfSessionsRequestingPreventSleep = requesters
        if changed {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
}
