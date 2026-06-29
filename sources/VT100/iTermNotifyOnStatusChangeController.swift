//
//  iTermNotifyOnStatusChangeController.swift
//  iTerm2SharedARC
//
//  Centralized "notify on status change" state. Both windows and
//  individual sessions can be "armed": the next time a relevant
//  session's status text changes, an alert is shown and that entity is
//  automatically disarmed (a one-shot watch).
//
//  This used to live entirely inside the Session Status toolbelt tool,
//  which meant the window-level toggle only existed while that tool was
//  visible. Centralizing it here lets the Window menu, the toolbelt
//  bell, and the Cockpit window all share one source of truth, and adds
//  a per-session scope on top of the original per-window one.
//

import AppKit

@objc(iTermNotifyOnStatusChangeController)
class NotifyOnStatusChangeController: NSObject {
    @objc static let instance = NotifyOnStatusChangeController()

    // Posted whenever the set of armed windows or sessions changes, so
    // UIs (toolbelt bell, Window menu, Cockpit) can refresh. Broadcast
    // with no object; observers re-read state.
    @objc static let armedDidChangeNotification = Notification.Name(
        "iTermNotifyOnStatusChangeArmedDidChange")

    // Armed entities. Presence in the set means "armed": the next status-text
    // change of a relevant session fires an alert and disarms that entity.
    private var armedWindows = Set<String>()
    private var armedSessions = Set<String>()
    // Per-session arm-time baseline for the session scope. Captured from the
    // controller's current value when a session is armed, so a change already in
    // flight at that moment (recorded by the controller but not yet flushed) is
    // part of the baseline and does not fire. One-shot: dropped when the watch
    // fires or is disarmed. The window scope deliberately does not use this; see
    // below.
    private var sessionArmBaseline = [String: String]()
    // Window-scope baseline: each session's status text as of the last coalesced
    // flush, maintained for all sessions regardless of arm state. A window watch
    // fires when a session's current text differs from this, so it naturally
    // covers sessions created after the window was armed (no frozen per-window
    // session set). A flicker that nets back to the prior value within the
    // debounce window absorbs to no change. Entries drop when a status clears.
    private var lastSeenStatusText = [String: String]()

    private var token: NotifyingDictionaryObserverToken!

    // Coalesce bursts of status changes the same way ToolStatus does, so
    // a flicker (A -> B -> A) within the debounce window nets out and
    // never fires.
    private static let debounceInterval: TimeInterval = 0.05
    private var pendingKeys = Set<String>()
    private var pendingFlush: DispatchWorkItem?

    override init() {
        super.init()
        token = SessionStatusController.instance.addObserver { [weak self] key, _, _ in
            self?.enqueue(key: key)
        }
        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(sessionWillTerminate(_:)),
                       name: .iTermSessionWillTerminate,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(windowDidClose(_:)),
                       name: .iTermWindowDidClose,
                       object: nil)
    }

    // MARK: - Window scope

    @objc(isWindowArmedForGuid:)
    func isWindowArmed(forGuid guid: String) -> Bool {
        return armedWindows.contains(guid)
    }

    @objc(toggleWindowArmedForGuid:)
    func toggleWindowArmed(forGuid guid: String) {
        if armedWindows.contains(guid) {
            disarmWindow(guid)
        } else {
            armWindow(guid)
        }
    }

    private func armWindow(_ guid: String) {
        armedWindows.insert(guid)
        // Absorb any change already in flight for a session in this window so
        // that arming within its debounce window is treated as "before arming"
        // and does not fire. Only pending (not-yet-flushed) keys can be stale
        // relative to the controller; everything else is already current in
        // lastSeenStatusText. Restricting to this window's sessions leaves other
        // armed windows' pending changes untouched.
        let controller = iTermController.sharedInstance()
        for key in pendingKeys where controller?.windowForSession(withGUID: key)?.terminalGuid == guid {
            advanceBaseline(forKey: key)
        }
        postArmedDidChange()
    }

    private func disarmWindow(_ guid: String) {
        guard armedWindows.contains(guid) else { return }
        armedWindows.remove(guid)
        postArmedDidChange()
    }

    // MARK: - Session scope

    func isSessionArmed(forGuid guid: String) -> Bool {
        return armedSessions.contains(guid)
    }

    func toggleSessionArmed(forGuid guid: String) {
        if armedSessions.contains(guid) {
            disarmSession(guid)
        } else {
            armSession(guid)
        }
    }

    private func armSession(_ guid: String) {
        armedSessions.insert(guid)
        // Capture the baseline from the controller's current value, which
        // already reflects any change still sitting in the debounce queue, so
        // arming within that change's window does not fire a spurious alert.
        if let text = SessionStatusController.instance.statuses[guid]?.statusText {
            sessionArmBaseline[guid] = text
        } else {
            sessionArmBaseline.removeValue(forKey: guid)
        }
        postArmedDidChange()
    }

    private func disarmSession(_ guid: String) {
        guard armedSessions.contains(guid) else { return }
        armedSessions.remove(guid)
        sessionArmBaseline.removeValue(forKey: guid)
        postArmedDidChange()
    }

    // MARK: - Change handling

    // Every status change is enqueued, even when nothing is armed, so the
    // window-scope `lastSeenStatusText` baseline stays current. That way a window
    // armed later measures the next change against the value from just before it,
    // rather than a stale one. The debounce coalesces bursts, so the steady-state
    // cost is one flush per 50ms window of activity.
    private func enqueue(key: String) {
        pendingKeys.insert(key)
        if pendingFlush != nil {
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    // Sets lastSeenStatusText[key] to the controller's current value (or drops
    // it when the status cleared). The window-scope baseline; advanced at flush
    // and when arming a window absorbs an in-flight change.
    private func advanceBaseline(forKey key: String) {
        if let text = SessionStatusController.instance.statuses[key]?.statusText {
            lastSeenStatusText[key] = text
        } else {
            lastSeenStatusText.removeValue(forKey: key)
        }
    }

    private func flush() {
        pendingFlush = nil
        let keys = pendingKeys
        pendingKeys.removeAll()
        if keys.isEmpty {
            return
        }
        let controller = iTermController.sharedInstance()
        var didChange = false
        for key in keys {
            let current = SessionStatusController.instance.statuses[key]?.statusText
            // The window-scope baseline from before this change, captured before
            // we advance it for the next burst. A net no-change (e.g. a flicker
            // that returned to it) advances nothing of consequence.
            let windowBaseline = lastSeenStatusText[key]
            advanceBaseline(forKey: key)
            if armedSessions.isEmpty && armedWindows.isEmpty {
                // Nothing armed: we only keep the baseline current.
                continue
            }
            let name = controller?.anySession(withGUID: key)?.name
            let terminal = controller?.windowForSession(withGUID: key)
            // A single change can satisfy both the session watch and its
            // window watch (the two scopes are armed independently). Both
            // should consume the change, but the user should see only one
            // alert, so disarm each satisfied scope and present at most once.
            var alerted = false

            // Session scope: measured from the value captured when this session
            // was armed (which already folded in any then-in-flight change).
            if armedSessions.contains(key), current != sessionArmBaseline[key] {
                armedSessions.remove(key)
                let from = sessionArmBaseline.removeValue(forKey: key)
                didChange = true
                presentAlert(sessionName: name, sessionGuid: key,
                             from: from, to: current, window: terminal?.window())
                alerted = true
            }

            // Window scope: the changed session's window, if armed. Measured
            // from the running baseline, so it covers sessions created after the
            // window was armed (membership is resolved live here).
            if let terminal, let windowGuid = terminal.terminalGuid,
               armedWindows.contains(windowGuid), current != windowBaseline {
                armedWindows.remove(windowGuid)
                didChange = true
                if !alerted {
                    presentAlert(sessionName: name, sessionGuid: key,
                                 from: windowBaseline, to: current, window: terminal.window())
                }
            }
        }
        if didChange {
            postArmedDidChange()
        }
    }

    // MARK: - Alert

    private func presentAlert(sessionName: String?,
                              sessionGuid: String?,
                              from: String?,
                              to: String?,
                              window: NSWindow?) {
        let name = sessionName ?? "A session"
        let fromText = from ?? "none"
        let toText = to ?? "none"
        // Present asynchronously so the modal alert doesn't run
        // reentrantly while the status-change notification is still
        // being dispatched.
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Session status changed"
            alert.informativeText = "\(name) changed from “\(fromText)” to “\(toText)”."
            alert.addButton(withTitle: "OK")
            // Offer Reveal only when the session can still be resolved; it may
            // have gone away between the change and the alert being shown.
            let canReveal = sessionGuid.flatMap {
                iTermController.sharedInstance()?.anySession(withGUID: $0)
            } != nil
            if canReveal {
                alert.addButton(withTitle: "Reveal")
            }
            let reveal: () -> Void = {
                if let sessionGuid {
                    iTermController.sharedInstance()?.anySession(withGUID: sessionGuid)?.reveal()
                }
            }
            if let window {
                alert.beginSheetModal(for: window) { response in
                    if response == .alertSecondButtonReturn {
                        reveal()
                    }
                }
            } else {
                let response = alert.runModal()
                if response == .alertSecondButtonReturn {
                    reveal()
                }
            }
        }
    }

    // MARK: - Cleanup

    @objc private func sessionWillTerminate(_ notification: Notification) {
        guard let session = notification.object as? PTYSession else { return }
        disarmSession(session.guid)
    }

    @objc private func windowDidClose(_ notification: Notification) {
        // Best-effort: drop any armed window whose terminal no longer
        // exists. Guids are never reused, so stale entries are harmless,
        // but pruning keeps the armed set honest for observers.
        guard let controller = iTermController.sharedInstance() else { return }
        let live = Set(controller.terminals().compactMap { $0.terminalGuid })
        let stale = armedWindows.subtracting(live)
        guard !stale.isEmpty else { return }
        for guid in stale {
            armedWindows.remove(guid)
        }
        postArmedDidChange()
    }

    private func postArmedDidChange() {
        NotificationCenter.default.post(name: Self.armedDidChangeNotification, object: nil)
    }
}
