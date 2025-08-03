//
//  ReaderModeBrowserTrigger.swift
//  iTerm2
//
//  Created by George Nachman on 8/3/25.
//

@objc
class ReaderModeBrowserTrigger: Trigger {
    override var description: String {
        return "Enter Reader Mode"
    }

    override static var title: String {
        return "Enter Reader Mode"
    }

    override func takesParameter() -> Bool {
        false
    }
}

extension ReaderModeBrowserTrigger: BrowserTrigger {
    func performBrowserAction(urlCaptures: [String],
                              contentCaptures: [String],
                              in client: any BrowserTriggerClient) async -> [BrowserTriggerAction] {
        let scheduler = client.scopeProvider.triggerCallbackScheduler()
        paramWithBackreferencesReplaced(withValues: urlCaptures + contentCaptures,
                                        absLine: -1,
                                        scope: client.scopeProvider,
                                        useInterpolation: client.useInterpolation).then { message in
            scheduler.scheduleTriggerCallback {
                client.triggerDelegate?.browserTriggerEnterReaderMode()
            }
        }
        return []
    }
}
