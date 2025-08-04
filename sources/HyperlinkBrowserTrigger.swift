//
//  HyperlinkBrowserTrigger.swift
//  iTerm2
//
//  Created by George Nachman on 8/3/25.
//

class HyperlinkBrowserTrigger: Trigger {
    override var description: String {
        "Make Hyperlink with URL “\(param as? String ?? "(nil)")”"
    }
    override static var title: String {
        "Make Hyperlink…"
    }
    override func takesParameter() -> Bool {
        true
    }
    override var isIdempotent: Bool {
        true
    }
    override func triggerOptionalParameterPlaceholder(withInterpolation interpolation: Bool) -> String? {
        return triggerOptionalDefaultParameterValue(withInterpolation: interpolation)
    }
    override func triggerOptionalDefaultParameterValue(withInterpolation interpolation: Bool) -> String? {
        if interpolation {
            "https://\\(match0)"
        } else {
            "https://\\0"
        }
    }
    override var allowedMatchTypes: Set<NSNumber> {
        return Set([ NSNumber(value: iTermTriggerMatchType.pageContentRegex.rawValue )])
    }
    override var matchType: iTermTriggerMatchType {
        .pageContentRegex
    }
}

extension HyperlinkBrowserTrigger: BrowserTrigger {
    func performBrowserAction(matchID: String?,
                              urlCaptures: [String],
                              contentCaptures: [String]?,
                              in client: any BrowserTriggerClient) async -> [BrowserTriggerAction] {
        guard let matchID else {
            DLog("No match id")
            return []
        }
        let scheduler = client.scopeProvider.triggerCallbackScheduler()
        paramWithBackreferencesReplaced(withValues: urlCaptures + (contentCaptures ?? []),
                                        absLine: -1,
                                        scope: client.scopeProvider,
                                        useInterpolation: client.useInterpolation).then { message in
            scheduler.scheduleTriggerCallback {
                client.triggerDelegate?.browserTriggerMakeHyperlink(matchID: matchID,
                                                                    url: message as String)
            }
        }
        return []
    }
}
