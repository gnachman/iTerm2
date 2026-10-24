//
//  iTermSessionSelector.swift
//  iTerm2
//
//  Created by George Nachman on 2/16/25.
//

@objc(iTermSessionSelector)
class SessionSelector: NSObject {
    @objc static let statusDidChange = NSNotification.Name("SessionSelectorStatusDidChange")
    // Which sessions offer a "Select this Session" button. nil means any
    // kind (terminal or browser).
    private struct Entry {
        var terminal: Bool?
        var reason: String
        var reveal: (() -> Void)?
        var promise: iTermPromise<PTYSession>
        var seal: iTermPromiseSeal

        init(terminal: Bool?, reason: String, reveal: (() -> Void)?) {
            self.terminal = terminal
            self.reason = reason
            self.reveal = reveal
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
    // Shows whatever made the active request, if it offered a way to.
    @objc static var currentRevealAction: (() -> Void)? {
        return entries.last?.reveal
    }

    // Whether the active request accepts a terminal (true) or browser (false)
    // session.
    @objc(wantsSessionOfKindTerminal:)
    static func wantsSession(terminal: Bool) -> Bool {
        guard let entry = entries.last else {
            return false
        }
        return entry.terminal.map { $0 == terminal } ?? true
    }

    // Pass nil for `terminal` to accept either kind of session. When `reveal`
    // is given, each session also offers a button that calls it, so the user
    // can find their way back to whoever asked.
    static func select(terminal: Bool?,
                       reason: String,
                       reveal: (() -> Void)? = nil) -> iTermPromise<PTYSession> {
        let entry = Entry(terminal: terminal, reason: reason, reveal: reveal)
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
        let i = entries.firstIndex { $0.promise === promise}
        guard let i else {
            return
        }
        // Session views show the top entry, so they need to hear about it
        // whenever the top changes, not only when the stack empties.
        let wasTop = (i == entries.count - 1)
        let entry = entries.remove(at: i)
        if wasTop {
            NotificationCenter.default.post(name: statusDidChange, object: nil)
        }
        entry.seal.reject(NSError(domain: "com.iterm2.session-selector", code: 0))
    }
}
