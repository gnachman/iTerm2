//
//  BrowserTrigger.swift
//  iTerm2
//
//  Created by George Nachman on 8/3/25.
//

@MainActor
protocol BrowserTriggerDelegate {
    func browserTriggerEnterReaderMode() async
    func browserTriggerHighlightText(matchID: String, textColor: String?, backgroundColor: String?)
    func browserTriggerMakeHyperlink(matchID: String, url: String)
    func browserTriggerInject(_ script: String)
}

@MainActor
protocol BrowserTriggerClient {
    var scopeProvider: iTermTriggerScopeProvider { get }
    var triggerDelegate: BrowserTriggerDelegate? { get }
    var useInterpolation: Bool { get }
}

enum BrowserTriggerAction {
    case stop
}

@MainActor
protocol BrowserTrigger {
    var matchType: iTermTriggerMatchType { get }
    var isEnabled: Bool { get }

    // NOTE: This should be idempotent. It may be called more than once on the same page.
    // For example, if the user navigates "back".
    func performBrowserAction(matchID: String?,
                              urlCaptures: [String],
                              contentCaptures: [String]?,
                              in client: BrowserTriggerClient) async -> [BrowserTriggerAction]
}

extension Trigger {
    var isEnabled: Bool {
        !self.disabled
    }
}
