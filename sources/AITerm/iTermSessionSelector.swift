//
//  iTermSessionSelector.swift
//  iTerm2
//
//  Created by George Nachman on 2/16/25.
//

@objc(iTermSessionSelector)
class SessionSelector: NSObject {
    @objc static let statusDidChange = NSNotification.Name("SessionSelectorStatusDidChange")
    private struct Entry {
        var terminal: Bool
        var reason: String
        var promise: iTermPromise<PTYSession>
        var seal: iTermPromiseSeal

        init(terminal: Bool, reason: String) {
            self.terminal = terminal
            self.reason = reason
            var promiseSeal: iTermPromiseSeal?
            self.promise = iTermPromise { promiseSeal = $0 }
            self.seal = promiseSeal!
        }
    }
    private static var entries = [Entry]()
    @objc static var isActive: Bool { !entries.isEmpty }

    @objc static var currentReason: String? {
        return entries.last?.reason
    }
    @objc static var wantsTerminal: Bool {
        return entries.last?.terminal == true
    }

    static func select(terminal: Bool, reason: String) -> iTermPromise<PTYSession> {
        let entry = Entry(terminal: terminal, reason: reason)
        entries.append(entry)
        NotificationCenter.default.post(name: statusDidChange, object: reason)
        return entry.promise
    }

    @objc static func didSelect(_ session: PTYSession) {
        if let entry = entries.popLast() {
            NotificationCenter.default.post(name: statusDidChange, object: nil)
            entry.seal.fulfill(session)
        }
    }

    @objc static func cancel(_ promise: iTermPromise<PTYSession>) {
        let wasEmpty = entries.isEmpty
        let i = entries.firstIndex { $0.promise === promise}
        guard let i else {
            return
        }
        entries[i].seal.reject(NSError(domain: "com.iterm2.session-selector", code: 0))
        entries.remove(at: IndexSet(integer: i))
        if entries.isEmpty && !wasEmpty {
            NotificationCenter.default.post(name: statusDidChange, object: nil)
        }
    }
}
