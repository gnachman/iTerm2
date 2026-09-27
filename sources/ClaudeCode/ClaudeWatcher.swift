//
//  ClaudeWatcher.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/6/26.
//

import Foundation

@objc(iTermClaudeWatcher)
class ClaudeWatcher: NSObject {
    private(set) static var instance: ClaudeWatcher?
    private static let disabledUserDefaultsKey = "NoSyncDisableClaudeWatcher"
    private(set) var sessionIDs = Set<String>()
    private let threshold: Int

    // Set once the app begins terminating. GlobalJobMonitor posts a storm of
    // job-change notifications as windows close and sessions tear down during
    // quit (sessionWillTerminate -> stopObserving -> postNotification). Acting
    // on those crashed: thresholdReached offered the upsell to sessions that
    // were mid-teardown. An upsell has no business appearing during quit
    // anyway, so we go inert as soon as termination begins. iTermApplicationWillTerminate
    // is posted from applicationShouldTerminate, before the window-close
    // cascade that triggered the crash, so the flag is set in time.
    private var isTerminating = false

    // Test seams. In production these reach into the live app. Tests inject
    // fakes so the notification -> threshold -> offer path can be exercised
    // without a real controller, live sessions, or UI.

    // Returns whether the session for a GUID has exited, or nil if there is no
    // such session.
    private let sessionExitedProvider: (String) -> Bool?
    // If non-nil, called instead of the real nagging-controller offer. Tests
    // use it to record which sessions would have been offered the upsell.
    private let offerOverride: ((String) -> Void)?

    init?(threshold: Int = 3,
          seedFromJobMonitor: Bool = true,
          bypassEnabledCheck: Bool = false,
          sessionExitedProvider: ((String) -> Bool?)? = nil,
          offerOverride: ((String) -> Void)? = nil) {
        self.threshold = threshold
        self.sessionExitedProvider = sessionExitedProvider ?? { guid in
            guard let session = iTermController.sharedInstance().session(withGUID: guid) else {
                return nil
            }
            return session.exited
        }
        self.offerOverride = offerOverride
        super.init()
        if !bypassEnabledCheck && !Self.enabled {
            RLog("ClaudeWatcher not enabled, returning nil")
            return nil
        }
        DLog("ClaudeWatcher initialized")
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(jobMonitorDidChange(_:)),
                                               name: GlobalJobMonitor.didChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillTerminate(_:)),
                                               name: Notification.Name(iTermApplicationWillTerminate),
                                               object: nil)
        // First observer to touch the singleton receives the seed
        // notifications inline from GlobalJobMonitor.init; we
        // happen to be that first observer at app launch (per
        // iTermApplicationDelegate's start order), so an explicit
        // replay would just deliver everything to us a second
        // time. Later observers (e.g. ClaudeIntegrationHealthMonitor)
        // are responsible for calling replayCurrentState themselves
        // after registering.
        if seedFromJobMonitor {
            _ = GlobalJobMonitor.instance
        }
    }
}

// MARK: - API
@objc
extension ClaudeWatcher {
    @objc static func start() {
        DLog("ClaudeWatcher.start()")
        instance = ClaudeWatcher()
        DLog("ClaudeWatcher instance is \(instance == nil ? "nil" : "non-nil")")
    }
}

// MARK: - Private Methods
extension ClaudeWatcher {
    static var enabled: Bool {
        if iTermUserDefaults.userDefaults().bool(forKey: Self.disabledUserDefaultsKey) {
            DLog("ClaudeWatcher disabled by user default")
            return false
        }
        if iTermUserDefaults.userDefaults().float(forKey: ToolStatus.statusToolLastUseUserDefaultsKey) > 0 {
            DLog("ClaudeWatcher disabled because status tool has been used")
            return false
        }
        if iTermToolbeltView.shouldShowTool(kStatusToolName, profileType: .terminal) {
            DLog("ClaudeWatcher disabled because status tool is already visible")
            return false
        }
        return true
    }

    // Whether the upsell should be offered to a session, given the app's
    // termination state and the session's liveness. Pure so the crash
    // condition (threshold reached while terminating) is unit-testable
    // without a live app. sessionExited is nil when no session exists for the
    // GUID.
    static func shouldOffer(isTerminating: Bool, sessionExited: Bool?) -> Bool {
        if isTerminating {
            return false
        }
        guard let sessionExited else {
            // No live session for this GUID (it may have already been torn
            // down between the notification and now).
            return false
        }
        return !sessionExited
    }

    @objc
    func applicationWillTerminate(_ notification: Notification) {
        DLog("ClaudeWatcher noting app termination")
        isTerminating = true
    }

    // This handler must be idempotent: notifications for the
    // claude job can fire repeatedly as the foreground ancestor
    // chain churns, and a future observer that calls
    // GlobalJobMonitor.replayCurrentState (the health monitor
    // already does, others may follow) will deliver them to every
    // registered observer including this one. Re-assigning
    // sessionIDs to the same value and re-running thresholdReached
    // is harmless because offerClaudeCodeStatusTool routes through
    // the nag controller's naggingControllerCanShowMessageWithIdentifier
    // gate, which suppresses a repeat offer for the same identifier.
    // Be careful adding work here that doesn't have its own
    // idempotency guarantee.
    @objc
    func jobMonitorDidChange(_ notification: Notification) {
        guard !isTerminating else {
            DLog("ClaudeWatcher ignoring job change during termination")
            return
        }
        defer {
            if !Self.enabled {
                RLog("ClaudeWatcher no longer enabled, nilling instance")
                Self.instance = nil
            }
        }
        guard let userInfo = notification.userInfo,
              let job = userInfo[GlobalJobMonitor.jobNameKey] as? String,
              job == "claude",
              let sessions = userInfo[GlobalJobMonitor.sessionGUIDsKey] as? Set<String> else {
            DLog("ClaudeWatcher ignoring notification: \(notification.userInfo ?? [:])")
            return
        }
        RLog("ClaudeWatcher got \(sessions.count) claude session(s)")
        sessionIDs = sessions
        if sessionIDs.count >= threshold {
            RLog("ClaudeWatcher threshold reached (\(threshold))")
            thresholdReached()
        }
    }

    func thresholdReached() {
        for sessionID in sessionIDs {
            guard Self.shouldOffer(isTerminating: isTerminating,
                                   sessionExited: sessionExitedProvider(sessionID)) else {
                DLog("ClaudeWatcher not offering to \(sessionID)")
                continue
            }
            RLog("ClaudeWatcher offering status tool to session \(sessionID)")
            if let offerOverride {
                offerOverride(sessionID)
            } else {
                offerClaudeCodeStatusTool(sessionID: sessionID)
            }
        }
    }

    func offerClaudeCodeStatusTool(sessionID: String) {
        guard let session = iTermController.sharedInstance().session(withGUID: sessionID) else {
            DLog("ClaudeWatcher session \(sessionID) not found")
            return
        }
        session.naggingController.offerClaudeCodeStatusTool { [weak self] status in
            RLog("ClaudeWatcher user responded: \(status)")
            switch status {
            case .never:
                RLog("ClaudeWatcher user chose never")
                iTermUserDefaults.userDefaults().set(true, forKey: Self.disabledUserDefaultsKey)
            case .accept:
                RLog("ClaudeWatcher user accepted")
                iTermUserDefaults.userDefaults().set(true, forKey: Self.disabledUserDefaultsKey)
                self?.userDidAccept()
            case .askLater:
                RLog("ClaudeWatcher user chose ask later")
                if let self {
                    NotificationCenter.default.removeObserver(self)
                }
                Self.instance = nil
            @unknown default:
                it_fatalError()
            }
        }
    }

    func userDidAccept() {
        ClaudeCodeOnboarding.show()
    }
}
