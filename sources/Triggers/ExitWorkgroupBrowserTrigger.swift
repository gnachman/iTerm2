//
//  ExitWorkgroupBrowserTrigger.swift
//  iTerm2SharedARC
//

import Foundation

// Browser-mode counterpart to ExitWorkgroupTrigger. Fires on URL
// matches and exits whatever workgroup is currently active on the
// browser session.
@objc(iTermExitWorkgroupBrowserTrigger)
class ExitWorkgroupBrowserTrigger: Trigger {
    override static var title: String {
        return "Exit Workgroup"
    }

    override var description: String {
        return "Exit Workgroup"
    }

    override func takesParameter() -> Bool {
        return false
    }

    override var isIdempotent: Bool {
        return true
    }

    override var matchType: iTermTriggerMatchType {
        return .urlRegex
    }

    override var allowedMatchTypes: Set<NSNumber> {
        return Set([NSNumber(value: iTermTriggerMatchType.urlRegex.rawValue)])
    }

    override var isBrowserTrigger: Bool {
        return true
    }
}

extension ExitWorkgroupBrowserTrigger: BrowserTrigger {
    func performBrowserAction(matchID: String?,
                              urlCaptures: [String],
                              contentCaptures: [String]?,
                              in client: any BrowserTriggerClient) async -> [BrowserTriggerAction] {
        let scheduler = client.scopeProvider.triggerCallbackScheduler()
        await withCheckedContinuation { continuation in
            scheduler.scheduleTriggerCallback {
                client.triggerDelegate?.browserTriggerExitWorkgroup()
                continuation.resume()
            }
        }
        return []
    }
}
