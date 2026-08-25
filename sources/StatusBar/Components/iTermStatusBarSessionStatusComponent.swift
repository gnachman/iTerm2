//
//  iTermStatusBarSessionStatusComponent.swift
//  iTerm2SharedARC
//

import Foundation

/// One session's status as rendered by the Session Status status bar
/// component and its popover.
///
/// `lastChanged` is tracked by the component rather than read off
/// `iTermSessionTabStatus`, which carries no timestamp of its own. It
/// mirrors what ToolStatus keeps so both order equal-priority entries the
/// same way.
struct SessionStatusEntry {
    var sessionID: String
    var tabStatus: iTermSessionTabStatus
    var lastChanged: TimeInterval
}

/// The status bar counterpart to the Session Status toolbelt tool
/// (`ToolStatus`): the same data in one line, with the full list in a
/// popover on click.
///
/// The Session Status system is generic — any program can set status text,
/// an indicator dot, and colors on any session via OSC 21337 or a Set Tab
/// Status trigger — so nothing here matches on particular status strings.
/// Membership is `iTermSessionTabStatus.hasActiveStatus` and ordering comes
/// from the user-configurable `StatusPrioritySettings`, exactly as in the
/// toolbelt tool.
@objc(iTermStatusBarSessionStatusComponent)
class StatusBarSessionStatusComponent: iTermStatusBarTextComponent {
    // Coalesce bursts of status changes. Triggers can fire several times in
    // quick succession as an interactive TUI repaints; applying the net
    // effect avoids relaying out the status bar for each one. Matches
    // ToolStatus and NotifyOnStatusChangeController.
    private static let debounceInterval: TimeInterval = 0.05

    private var token: NotifyingDictionaryObserverToken?
    private var pendingFlush: DispatchWorkItem?
    private var lastChangedBySessionID = [String: TimeInterval]()
    private var entries = [SessionStatusEntry]()
    private var popover: NSPopover?

    required init(configuration: [iTermStatusBarComponentConfigurationKey : Any],
                  scope: iTermVariableScope?) {
        super.init(configuration: configuration, scope: scope)
        startObserving()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        startObserving()
    }

    private func startObserving() {
        token = SessionStatusController.instance.addObserver { [weak self] key, _, _ in
            self?.enqueue(key: key)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(prioritiesDidChange(_:)),
            name: StatusPrioritySettings.didChangeNotification,
            object: nil)
        // The set of sessions in this window changes independently of any
        // status change, and window membership is what scopes this
        // component, so a session moving in or out must re-filter even
        // though no status text moved.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionsDidChange(_:)),
            name: .init("iTermNumberOfSessionsDidChange"),
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pendingFlush?.cancel()
    }

    // MARK: - Change handling

    private func enqueue(key: String) {
        lastChangedBySessionID[key] = NSDate.it_timeSinceBoot()
        if pendingFlush != nil {
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingFlush = nil
            self?.reload()
        }
        pendingFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    @objc private func prioritiesDidChange(_ notification: Notification) {
        reload()
    }

    @objc private func sessionsDidChange(_ notification: Notification) {
        reload()
    }

    private func reload() {
        entries = currentEntries()
        // Drop timestamps for sessions the controller no longer tracks so
        // the map can't grow for the life of the window.
        let live = Set(SessionStatusController.instance.statuses.keys)
        lastChangedBySessionID = lastChangedBySessionID.filter { live.contains($0.key) }
        updateTextFieldIfNeeded()
    }

    // MARK: - Model

    /// This component's own session, or nil in the status bar setup UI,
    /// which builds components with a nil scope.
    private var currentSessionGUID: String? {
        guard let value = scope?.value(forVariableName: iTermVariableKeySessionID) as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Every status belonging to this component's window, highest priority
    /// first. Scoped to the window rather than the app so the label
    /// describes what the user is looking at, matching the toolbelt tool.
    private func currentEntries() -> [SessionStatusEntry] {
        guard let guid = currentSessionGUID,
              let terminal = iTermController.sharedInstance()?.windowForSession(withGUID: guid) else {
            return []
        }
        let sessions = terminal.allSessions() ?? []
        var result = [SessionStatusEntry]()
        for (sessionID, tabStatus) in SessionStatusController.instance.statuses {
            guard tabStatus.hasActiveStatus,
                  Self.windowContains(sessionGUID: sessionID, among: sessions) else {
                continue
            }
            result.append(SessionStatusEntry(sessionID: sessionID,
                                             tabStatus: tabStatus,
                                             lastChanged: lastChangedBySessionID[sessionID] ?? 0))
        }
        return result.sorted(by: Self.orderedBefore)
    }

    /// Mirrors PseudoTerminal's -toolbeltWindowContainsSessionWithGUID:,
    /// which the toolbelt reaches through its wrapper's delegate chain. A
    /// status bar component has no such chain (see
    /// iTermStatusBarComponentDelegate, which vends no session or window),
    /// so the same test is made here from the window's own session list: a
    /// status belongs to this window iff a session here owns the GUID, or
    /// one of them has it as a workgroup peer — including a peer that is
    /// buried rather than in a tab.
    private static func windowContains(sessionGUID guid: String,
                                       among sessions: [PTYSession]) -> Bool {
        return sessions.contains { session in
            session.guid == guid || session.peerPort?.containsPeer(guid: guid) == true
        }
    }

    /// Same ordering as ToolStatus.Status: user-configured priority, then
    /// age (stale entries rise), then session ID as a stable tiebreak.
    /// Snooze is deliberately absent — it is per-tool UI state that lives
    /// in the toolbelt, not in the shared status model.
    private static func orderedBefore(_ lhs: SessionStatusEntry,
                                      _ rhs: SessionStatusEntry) -> Bool {
        if lhs.tabStatus.priority != rhs.tabStatus.priority {
            return lhs.tabStatus.priority < rhs.tabStatus.priority
        }
        if lhs.lastChanged != rhs.lastChanged {
            return lhs.lastChanged < rhs.lastChanged
        }
        return lhs.sessionID < rhs.sessionID
    }

    // MARK: - Label

    /// Candidate labels for the bar to choose from by available width; the
    /// widest that fits wins, so order here is immaterial.
    ///
    /// The lead text is whatever the highest-priority session's status
    /// says. A status may carry only an indicator dot and no text, in which
    /// case there is nothing to name and the count stands alone.
    private static func variants(for entries: [SessionStatusEntry]) -> [String] {
        guard !entries.isEmpty else {
            return []
        }
        let count = entries.count
        guard let top = entries.first?.tabStatus.statusText, !top.isEmpty else {
            return [countLabel(count), "\(count)"]
        }
        if count == 1 {
            return [top]
        }
        return ["\(top) +\(count - 1)", top, "\(count)"]
    }

    private static func countLabel(_ count: Int) -> String {
        return count == 1 ? "1 session" : "\(count) sessions"
    }

    // MARK: - iTermStatusBarComponent

    override static var compatibleProfileTypes: ProfileType {
        [.terminal]
    }

    override func statusBarComponentIcon() -> NSImage? {
        return NSImage(systemSymbolName: SFSymbol.listBulletCircle.rawValue,
                       accessibilityDescription: "Session Status")
    }

    override func statusBarComponentShortDescription() -> String {
        return "Session Status"
    }

    override func statusBarComponentDetailedDescription() -> String {
        return "Summarizes the status of sessions in this window, as set by " +
               "Set Tab Status triggers or the OSC 21337 control sequence. " +
               "Click to list them and jump to one."
    }

    // Illustrates the shape of the label — some session's status text plus a
    // count of the others. Not one of the shipped default priority patterns,
    // so it can't read as a status this component treats specially.
    override func statusBarComponentExemplar(withBackgroundColor backgroundColor: NSColor,
                                             textColor: NSColor) -> Any {
        return "Compiling +2"
    }

    override func statusBarComponentCanStretch() -> Bool {
        return true
    }

    // stringValueForCurrentWidth() is deliberately NOT overridden: the base
    // class picks the widest of these that fits the space it was given, and
    // overriding it would pin the label to one variant and defeat that.
    override var stringVariants: [String]? {
        return Self.variants(for: entries)
    }

    override func statusBarComponentIsEmpty() -> Bool {
        return entries.isEmpty
    }

    override func statusBarComponentUpdate() {
        entries = currentEntries()
        super.statusBarComponentUpdate()
    }

    override func statusBarComponentDidMoveToWindow() {
        super.statusBarComponentDidMoveToWindow()
        reload()
    }

    // Clicks only. Handling mouse-down as well would fire twice for one
    // click — the container installs a click recognizer *and* forwards
    // mouseDown when statusBarComponentHandlesMouseDown is true — which a
    // menu absorbs (see iTermStatusBarTriggersComponent) but a popover
    // would flicker open and shut.
    override func statusBarComponentHandlesClicks() -> Bool {
        return true
    }

    override func statusBarComponentDidClick(with view: NSView) {
        togglePopover(over: view)
    }

    // MARK: - Popover

    private func togglePopover(over view: NSView) {
        if let popover, popover.isShown {
            popover.close()
            self.popover = nil
            return
        }
        entries = currentEntries()
        guard !entries.isEmpty else {
            return
        }
        let viewController = SessionStatusPopoverViewController(
            entries: entries,
            activeSessionGUID: currentSessionGUID)
        viewController.onSelect = { [weak self] sessionID in
            iTermController.sharedInstance()?.anySession(withGUID: sessionID)?.reveal()
            self?.popover?.close()
            self?.popover = nil
        }
        // Force the view to load so preferredContentSize reflects the table's
        // measured height rather than the provisional set in init.
        _ = viewController.view
        let popover = NSPopover()
        popover.contentViewController = viewController
        popover.behavior = .semitransient
        popover.appearance = view.effectiveAppearance
        popover.contentSize = viewController.preferredContentSize

        // Open away from the bar: a status bar pinned to the top of the
        // window drops its popover downward, and one at the bottom opens
        // upward.
        let position = iTermPreferences.unsignedInteger(forKey: kPreferenceKeyStatusBarPosition)
        let edge: NSRectEdge = (position == iTermStatusBarPosition.top.rawValue) ? .maxY : .minY
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: edge)
        self.popover = popover
    }
}
