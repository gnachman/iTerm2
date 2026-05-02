//
//  iTermLayoutEnvironment.swift
//  iTerm2SharedARC
//
//  Production implementation of `LayoutResolverEnvironment`. Wraps
//  `iTermController` for live-state lookups during layout resolution.
//

import Foundation

@objc(iTermLayoutEnvironment)
final class iTermLayoutEnvironment: NSObject, LayoutResolverEnvironment {

    private let controller: iTermController

    @objc init(controller: iTermController) {
        self.controller = controller
        super.init()
    }

    @objc convenience override init() {
        self.init(controller: iTermController.sharedInstance())
    }

    func sessionGUIDExists(_ guid: String) -> Bool {
        controller.session(withGUID: guid) != nil
    }

    func tabIDExists(_ tabID: String) -> Bool {
        controller.tab(withID: tabID) != nil
    }

    func windowGUIDExists(_ guid: String) -> Bool {
        controller.terminal(withGuid: guid) != nil
    }

    func tabID(containingSession sessionGUID: String) -> String? {
        guard let session = controller.session(withGUID: sessionGUID),
              let tab = controller.tab(for: session) else {
            return nil
        }
        return "\(tab.uniqueId)"
    }

    func sessionGUIDs(inTab tabID: String) -> [String] {
        guard let tab = controller.tab(withID: tabID),
              let sessions = tab.sessions() as? [PTYSession] else {
            return []
        }
        return sessions.compactMap { $0.guid }
    }

    func isTmuxTab(_ tabID: String) -> Bool {
        guard let tab = controller.tab(withID: tabID) else { return false }
        return tab.isTmuxTab
    }
}
