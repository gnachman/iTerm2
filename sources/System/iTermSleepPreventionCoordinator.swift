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

    /// External state and side effects, injectable so tests can drive the coordinator without live
    /// sessions, a real power assertion, or real run loop turns.
    struct Environment {
        /// GUIDs of sessions that currently want the assertion held (may contain duplicates).
        var requesterGUIDs: () -> [String]
        var connectedToPower: () -> Bool
        var allowedOnBattery: () -> Bool
        /// Runs a block on a later main-queue turn.
        var scheduleOnNextTurn: (@escaping () -> Void) -> Void
        var beginAssertion: () -> NSObjectProtocol
        var endAssertion: (NSObjectProtocol) -> Void
    }

    private let environment: Environment
    private let notificationCenter: NotificationCenter

    private override convenience init() {
        self.init(environment: Environment(
            requesterGUIDs: { SleepPreventionCoordinator.liveRequesterGUIDs() },
            connectedToPower: { iTermPowerManager.sharedInstance().connectedToPower },
            allowedOnBattery: { iTermAdvancedSettingsModel.preventSleepOnBatteryToo() },
            scheduleOnNextTurn: { block in DispatchQueue.main.async(execute: block) },
            beginAssertion: {
                ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled,
                                                      reason: "iTerm2: profile prevents sleep")
            },
            endAssertion: { ProcessInfo.processInfo.endActivity($0) }),
                  notificationCenter: .default)
    }

    init(environment: Environment, notificationCenter center: NotificationCenter) {
        self.environment = environment
        self.notificationCenter = center
        super.init()
        DLog("SleepPreventionCoordinator initializing")

        // Session lifecycle: a session appearing/disappearing changes the set we fold over.
        center.addObserver(self, selector: #selector(recomputeFromNotification(_:)),
                           name: .PTYSessionCreated, object: nil)
        center.addObserver(self, selector: #selector(recomputeFromNotification(_:)),
                           name: .PTYSessionRevived, object: nil)
        center.addObserver(self, selector: #selector(recomputeFromNotification(_:)),
                           name: .iTermSessionWillTerminate, object: nil)
        // A session's process died or a new one was started in its place (Restart Session, on a
        // live or an exited shell). Exited sessions are not requesters, so this changes the fold.
        center.addObserver(self, selector: #selector(recomputeFromNotification(_:)),
                           name: .PTYSessionExitedDidChange, object: nil)
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
        } else if notification.name == .PTYSessionRevived {
            // -revive posts this before its caller puts the session back in a window (every Undo
            // Close path calls -revive first and only then -addRevivedSession: or rebuilds the
            // tab, all in the same main-queue turn). allSessions() would not yet enumerate it, so
            // defer to the next turn, when it is back in its window.
            scheduleDeferredRecompute()
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
        environment.scheduleOnNextTurn { [weak self] in
            guard let self else { return }
            self.deferredRecomputeScheduled = false
            self.recompute()
        }
    }

    /// The GUIDs of sessions that currently want the assertion held. Includes buried sessions:
    /// they still exist (the profile doc says the assertion is held "while a session with this
    /// setting enabled exists"), but allSessions() only enumerates sessions in a window.
    /// Internal (not private) only so tests can use it; it does not apply the WillTerminate exclusion.
    static func liveRequesterGUIDs() -> [String] {
        // During app termination +[iTermController releaseSharedInstance] nils the shared
        // controller while session-teardown notifications still fire (Sparkle's Install and
        // Relaunch, or an ordinary quit, closes windows, which posts iTermSessionWillTerminate).
        // sharedInstance() imports into Swift as an implicitly unwrapped optional, so unwrapping
        // the now-nil singleton would trap. Nothing needs to stay awake once we are quitting, so
        // treat its absence as no requesters.
        guard let controller = iTermController.sharedInstance() else { return [] }
        let live = controller.allSessions() ?? []
        let buried = iTermBuriedSessions.sharedInstance()?.buriedSessions() ?? []
        return (live + buried).compactMap { session -> String? in
            // A session whose process has died but whose pane is still open (endAction "Do
            // nothing") is not doing work; it must not keep the Mac awake. Exclude exited sessions
            // here; PTYSessionExitedDidChange triggers a recompute when that state flips.
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
        let requesterGUIDs = environment.requesterGUIDs()
        let onPower = environment.connectedToPower()
        let allowedOnBattery = environment.allowedOnBattery()
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
            activity = environment.beginAssertion()
        } else if !want, let activity {
            RLog("SleepPreventionCoordinator: releasing system idle sleep assertion")
            environment.endAssertion(activity)
            self.activity = nil
        }

        // Publish both counts for the status label; notify observers if either changed.
        let changed = (numberOfSessionsPreventingSleep != count) ||
                      (numberOfSessionsRequestingPreventSleep != requesters)
        numberOfSessionsPreventingSleep = count
        numberOfSessionsRequestingPreventSleep = requesters
        if changed {
            notificationCenter.post(name: Self.didChangeNotification, object: self)
        }
    }
}
