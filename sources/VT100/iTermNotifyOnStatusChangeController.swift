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

    // Armed entities. Presence in the set means "armed." The companion
    // snapshot dictionaries record each watched session's status text at
    // arm time so a later change is measured from the moment the user
    // armed it (and a flicker that returns to the snapshot nets to no
    // change). Sessions whose status text was nil at arm time are simply
    // absent from the snapshot, so any later non-nil text counts.
    private var armedWindows = Set<String>()
    private var windowSnapshots = [String: [String: String]]()  // windowGuid -> sessionGuid -> text
    private var armedSessions = Set<String>()
    private var sessionSnapshots = [String: String]()            // sessionGuid -> text

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
        windowSnapshots[guid] = snapshotStatusText(forWindowGuid: guid)
        postArmedDidChange()
    }

    private func disarmWindow(_ guid: String) {
        guard armedWindows.contains(guid) else { return }
        armedWindows.remove(guid)
        windowSnapshots.removeValue(forKey: guid)
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
        if let text = SessionStatusController.instance.statuses[guid]?.statusText {
            sessionSnapshots[guid] = text
        } else {
            sessionSnapshots.removeValue(forKey: guid)
        }
        postArmedDidChange()
    }

    private func disarmSession(_ guid: String) {
        guard armedSessions.contains(guid) else { return }
        armedSessions.remove(guid)
        sessionSnapshots.removeValue(forKey: guid)
        postArmedDidChange()
    }

    // MARK: - Snapshotting

    // Status text of every session currently belonging to a window,
    // keyed by session guid. Only sessions that have status text are
    // included; the rest read as "no text" at compare time.
    private func snapshotStatusText(forWindowGuid windowGuid: String) -> [String: String] {
        guard let controller = iTermController.sharedInstance() else { return [:] }
        var result = [String: String]()
        for status in SessionStatusController.instance.statuses.values {
            let sessionGuid = status.sessionID
            guard controller.windowForSession(withGUID: sessionGuid)?.terminalGuid == windowGuid,
                  let text = status.statusText else {
                continue
            }
            result[sessionGuid] = text
        }
        return result
    }

    // MARK: - Change handling

    private func enqueue(key: String) {
        guard !armedWindows.isEmpty || !armedSessions.isEmpty else {
            return
        }
        pendingKeys.insert(key)
        if pendingFlush != nil {
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
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
            let name = controller?.anySession(withGUID: key)?.name
            let terminal = controller?.windowForSession(withGUID: key)
            // A single change can satisfy both the session watch and its
            // window watch (the two scopes are armed independently). Both
            // should consume the change, but the user should see only one
            // alert, so disarm each satisfied scope and present at most once.
            var alerted = false

            // Session scope.
            if armedSessions.contains(key) {
                let old = sessionSnapshots[key]
                if current != old {
                    armedSessions.remove(key)
                    sessionSnapshots.removeValue(forKey: key)
                    didChange = true
                    presentAlert(sessionName: name, from: old, to: current,
                                 window: terminal?.window())
                    alerted = true
                }
            }

            // Window scope: the changed session's window, if armed.
            if let terminal, let windowGuid = terminal.terminalGuid,
               armedWindows.contains(windowGuid) {
                let old = windowSnapshots[windowGuid]?[key]
                if current != old {
                    armedWindows.remove(windowGuid)
                    windowSnapshots.removeValue(forKey: windowGuid)
                    didChange = true
                    if !alerted {
                        presentAlert(sessionName: name, from: old, to: current,
                                     window: terminal.window())
                    }
                }
            }
        }
        if didChange {
            postArmedDidChange()
        }
    }

    // MARK: - Alert

    private func presentAlert(sessionName: String?,
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
            if let window {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
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
            windowSnapshots.removeValue(forKey: guid)
        }
        postArmedDidChange()
    }

    private func postArmedDidChange() {
        NotificationCenter.default.post(name: Self.armedDidChangeNotification, object: nil)
    }
}
