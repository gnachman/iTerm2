//
//  EnterWorkgroupBrowserTrigger.swift
//  iTerm2SharedARC
//

import Foundation

// Browser-mode counterpart to EnterWorkgroupTrigger. Fires on URL
// matches and enters the configured workgroup on the browser session
// the page belongs to. Same workgroup popup as the terminal trigger
// — both read from iTermWorkgroupModel — so a workgroup the user
// installed via the Claude Code installer is pickable here too.
@objc(iTermEnterWorkgroupBrowserTrigger)
class EnterWorkgroupBrowserTrigger: Trigger {
    override static var title: String {
        return "Enter Workgroup…"
    }

    override var description: String {
        return "Enter Workgroup “\(displayLabel(forID: effectiveID))”"
    }

    override func takesParameter() -> Bool {
        return true
    }

    override func paramIsPopupButton() -> Bool {
        return true
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

    // MARK: - Popup (mirrors EnterWorkgroupTrigger)

    private var availableWorkgroups: [iTermWorkgroup] {
        return iTermWorkgroupModel.instance.workgroups
    }

    private var effectiveID: String? {
        if let s = self.param as? String, !s.isEmpty {
            return s
        }
        return firstSortedWorkgroupID
    }

    private var firstSortedWorkgroupID: String? {
        guard let dict = menuItemsForPoupupButton() else { return nil }
        return objectsSortedByValue(inDict: dict).first as? String
    }

    private func displayLabel(forID id: String?) -> String {
        guard let id, !id.isEmpty else { return "(unset)" }
        if let wg = availableWorkgroups.first(where: { $0.uniqueIdentifier == id }) {
            return wg.name.isEmpty ? "Untitled" : wg.name
        }
        return "(missing)"
    }

    override func menuItemsForPoupupButton() -> [AnyHashable: Any]? {
        var dict: [AnyHashable: Any] = [:]
        for wg in availableWorkgroups {
            let label = wg.name.isEmpty ? "Untitled" : wg.name
            dict[wg.uniqueIdentifier] = label
        }
        return dict
    }

    override func index(for object: Any?) -> Int {
        guard let dict = menuItemsForPoupupButton() else { return -1 }
        return objectsSortedByValue(inDict: dict).firstIndex { obj in
            (obj as? String) == (object as? String)
        } ?? -1
    }

    override func object(at index: Int) -> Any? {
        guard let dict = menuItemsForPoupupButton() else { return nil }
        let sorted = objectsSortedByValue(inDict: dict)
        guard index >= 0, index < sorted.count else { return nil }
        return sorted[index]
    }

    override func paramAttributedString() -> NSAttributedString? {
        return NSAttributedString(string: displayLabel(forID: effectiveID),
                                  attributes: regularAttributes())
    }
}

extension EnterWorkgroupBrowserTrigger: BrowserTrigger {
    func performBrowserAction(matchID: String?,
                              urlCaptures: [String],
                              contentCaptures: [String]?,
                              in client: any BrowserTriggerClient) async -> [BrowserTriggerAction] {
        guard let id = effectiveID, !id.isEmpty else { return [] }
        let scheduler = client.scopeProvider.triggerCallbackScheduler()
        await withCheckedContinuation { continuation in
            scheduler.scheduleTriggerCallback {
                client.triggerDelegate?.browserTriggerEnterWorkgroup(uniqueIdentifier: id)
                continuation.resume()
            }
        }
        return []
    }
}
