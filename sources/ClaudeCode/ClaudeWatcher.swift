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
    private let threshold = 3

    private init?(_ placeholder: Void = ()) {
        super.init()
        if !Self.enabled {
            DLog("ClaudeWatcher not enabled, returning nil")
            return nil
        }
        DLog("ClaudeWatcher initialized")
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(jobMonitorDidChange(_:)),
                                               name: GlobalJobMonitor.didChangeNotification,
                                               object: nil)
        // Ensure it's running
        _ = GlobalJobMonitor.instance
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
private extension ClaudeWatcher {
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

    @objc
    func jobMonitorDidChange(_ notification: Notification) {
        defer {
            if !Self.enabled {
                DLog("ClaudeWatcher no longer enabled, nilling instance")
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
        DLog("ClaudeWatcher got \(sessions.count) claude session(s)")
        sessionIDs = sessions
        if sessionIDs.count >= threshold {
            DLog("ClaudeWatcher threshold reached (\(threshold))")
            thresholdReached()
        }
    }

    func thresholdReached() {
        for sessionID in sessionIDs {
            guard let session = iTermController.sharedInstance().session(withGUID: sessionID) else {
                DLog("ClaudeWatcher session \(sessionID) not found")
                continue
            }
            DLog("ClaudeWatcher offering status tool to session \(sessionID)")
            offerClaudeCodeStatusTool(session: session)
        }
    }

    func offerClaudeCodeStatusTool(session: PTYSession) {
        session.naggingController.offerClaudeCodeStatusTool { [weak self] status in
            DLog("ClaudeWatcher user responded: \(status)")
            switch status {
            case .never:
                DLog("ClaudeWatcher user chose never")
                iTermUserDefaults.userDefaults().set(true, forKey: Self.disabledUserDefaultsKey)
            case .accept:
                DLog("ClaudeWatcher user accepted")
                iTermUserDefaults.userDefaults().set(true, forKey: Self.disabledUserDefaultsKey)
                self?.userDidAccept()
            case .askLater:
                DLog("ClaudeWatcher user chose ask later")
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
