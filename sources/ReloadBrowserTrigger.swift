//
//  ReloadBrowserTrigger.swift
//  iTerm2
//
//  Created by George Nachman on 9/19/25.
//

@objc(ReloadBrowserTrigger)
class ReloadBrowserTrigger: Trigger {
    override var description: String {
        return "Reload After Delay)"
    }

    override static var title: String {
        return "Reload After Delay"
    }

    override func takesParameter() -> Bool {
        true
    }
    override var isIdempotent: Bool {
        false
    }
    override func triggerOptionalParameterPlaceholder(withInterpolation interpolation: Bool) -> String? {
        return "Delay in seconds"
    }
    override func triggerOptionalDefaultParameterValue(withInterpolation interpolation: Bool) -> String? {
        "60"
    }
    override var allowedMatchTypes: Set<NSNumber> {
        return Set([ NSNumber(value: iTermTriggerMatchType.urlRegex.rawValue )])
    }
    override var matchType: iTermTriggerMatchType {
        .urlRegex
    }
    override var isBrowserTrigger: Bool {
        true
    }
}

extension ReloadBrowserTrigger: BrowserTrigger {
    func performBrowserAction(matchID: String?,
                              urlCaptures: [String],
                              contentCaptures: [String]?,
                              in client: any BrowserTriggerClient) async -> [BrowserTriggerAction] {
        let scheduler = client.scopeProvider.triggerCallbackScheduler()
        await withCheckedContinuation { continuation in
            paramWithBackreferencesReplaced(withValues: urlCaptures + (contentCaptures ?? []),
                                            absLine: -1,
                                            scope: client.scopeProvider,
                                            useInterpolation: client.useInterpolation).then { message in
                scheduler.scheduleTriggerCallback {
                    Task {
                        let js = """
                        function reloadAfter(seconds) {
                            if (typeof seconds !== "number" || seconds < 0) {
                                throw new Error("seconds must be a non-negative number");
                            }
                            setTimeout(() => {
                                window.location.reload();
                            }, seconds * 1000);
                        }
                        reloadAfter(\(message as String));
                        """
                        client.triggerDelegate?.browserTriggerInject(js)
                        continuation.resume()
                    }
                }
            }
        }
        return []
    }
}
