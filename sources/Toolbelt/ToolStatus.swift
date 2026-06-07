//
//  ToolStatus.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/5/26.
//

import Foundation

@objc
class ToolStatus: NSView {
    private var scrollView: NSScrollView?
    private var _tableView: NSTableView?
    private var measuringCell: ToolStatusCellView?
    private var token: NotifyingDictionaryObserverToken!
    private var disableSelectionCount = 0
    private var helpButton: PopoverHelpButton!
    private var settingsButton: NSButton!
    private var notifyButton: NSButton!
    // When true, the next visible status-text transition fires an alert. We
    // snapshot each visible session's status text at arm time so changes are
    // measured against the moment the user enabled notifications.
    private var notifyArmed = false
    private var notifyStatusTextSnapshot = [String: String]()
    private static let buttonHeight: CGFloat = 23
    private static let margin: CGFloat = 5
    static let statusToolLastUseUserDefaultsKey = "NoSyncStatusToolLastUseDate"

    private struct Status: Comparable {
        var tabStatus: iTermSessionTabStatus {
            didSet {
                lastChanged = NSDate.it_timeSinceBoot()
            }
        }
        var sessionID: String
        var lastChanged = NSDate.it_timeSinceBoot()

        static func < (lhs: ToolStatus.Status, rhs: ToolStatus.Status) -> Bool {
            if lhs.tabStatus.priority != rhs.tabStatus.priority {
                return lhs.tabStatus.priority < rhs.tabStatus.priority
            }
            if lhs.lastChanged != rhs.lastChanged {
                // Let stale ones rise to the top
                return lhs.lastChanged < rhs.lastChanged
            }
            return lhs.sessionID < rhs.sessionID
        }
    }

    // The full per-session model, kept sorted. This is the source of truth and
    // is what the merge-off code path animates directly.
    private var statuses = [Status]()
    // What the table actually renders. Equal to `statuses` when workgroup
    // merging is off; otherwise each workgroup collapses to one representative
    // row here while `statuses` keeps every session.
    private var displayedStatuses = [Status]()
    // Coalesce bursts of status changes from the controller. Triggers can fire
    // several times in quick succession (e.g. an Idle match followed immediately
    // by a Working match when an interactive TUI repaints); collecting them and
    // applying the net effect avoids spurious row-slide animations.
    private static let debounceInterval: TimeInterval = 0.05
    private var pendingKeys = Set<String>()
    private var pendingFlush: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // Help button
        helpButton = PopoverHelpButton(helpText: Self.helpMarkdown)
        helpButton.controlSize = .small
        helpButton.sizeToFit()
        helpButton.autoresizingMask = [.minXMargin]
        addSubview(helpButton)

        // Settings button
        settingsButton = NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        settingsButton.bezelStyle = .regularSquare
        settingsButton.isBordered = false
        settingsButton.image = NSImage(systemSymbolName: "gearshape",
                                       accessibilityDescription: "Settings")
        settingsButton.imagePosition = .imageOnly
        settingsButton.target = self
        settingsButton.action = #selector(showSettings(_:))
        settingsButton.autoresizingMask = []
        addSubview(settingsButton)

        // Notify toggle — bottom-left. When armed, the next time any visible
        // session's waiting/idle/busy status text changes we show an alert and
        // disarm ourselves.
        notifyButton = NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        notifyButton.bezelStyle = .regularSquare
        notifyButton.setButtonType(.toggle)
        notifyButton.isBordered = false
        notifyButton.imagePosition = .imageOnly
        notifyButton.target = self
        notifyButton.action = #selector(toggleNotify(_:))
        notifyButton.autoresizingMask = []
        updateNotifyButtonAppearance()
        addSubview(notifyButton)

        scrollView = NSScrollView.scrollViewWithTableViewForToolbelt(container: self,
                                                                     insets: NSEdgeInsets(),
                                                                     rowHeight: 0,
                                                                     keyboardNavigable: false)
        _tableView = scrollView!.documentView! as? NSTableView
        _tableView!.allowsMultipleSelection = false
        _tableView!.reloadData()
        _tableView!.backgroundColor = .clear
        relayout()
        token = SessionStatusController.instance.addObserver { [weak self] key, value, change in
            self?.didChange(key: key, value: value, change: change)
        }
        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(activeSessionDidChange(_:)),
                       name: NSNotification.Name(iTermSessionBecameKey),
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(needsShortcutReload(_:)),
                       name: .psmModifierChanged,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(needsShortcutReload(_:)),
                       name: .init("iTermNumberOfSessionsDidChange"),
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(needsShortcutReload(_:)),
                       name: .init(iTermSelectedTabDidChange),
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(needsShortcutReload(_:)),
                       name: .iTermTabDidChangePositionInWindow,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(prioritiesDidChange(_:)),
                       name: StatusPrioritySettings.didChangeNotification,
                       object: nil)
    }

    required init!(frame: NSRect, url: URL!, identifier: String!) {
        it_fatalError()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
}

extension ToolStatus: ToolbeltTool {
    func minimumHeight() -> CGFloat {
        return 36.0
    }

    static func isDynamic() -> Bool {
        return false
    }

    static var supportedProfileTypes: ProfileType {
        ProfileType(rawValue: ProfileType.terminal.rawValue | ProfileType.browser.rawValue)
    }

    @objc func shutdown() {
    }

    @objc func relayout() {
        let m = Self.margin
        let bh = Self.buttonHeight

        // Help button — bottom-right
        helpButton.frame = NSRect(x: frame.width - helpButton.frame.width,
                                  y: 2,
                                  width: helpButton.frame.width,
                                  height: helpButton.frame.height)

        // Settings button — left of help
        settingsButton.frame = NSRect(x: helpButton.frame.origin.x - settingsButton.frame.width - m,
                                      y: 0,
                                      width: settingsButton.frame.width,
                                      height: settingsButton.frame.height)

        // Notify toggle — bottom-left
        notifyButton.frame = NSRect(x: 0,
                                    y: 0,
                                    width: notifyButton.frame.width,
                                    height: notifyButton.frame.height)

        // Scroll view — above buttons
        let scrollY = bh + m
        scrollView!.frame = NSRect(x: 0, y: scrollY, width: frame.width, height: frame.height - scrollY)
        let contentSize = self.contentSize()
        _tableView!.frame = NSRect(origin: .zero, size: contentSize)
        if it_isVisible {
            iTermUserDefaults.userDefaults().set(Date.timeIntervalSinceReferenceDate,
                                                 forKey: Self.statusToolLastUseUserDefaultsKey)
        }
    }
}

// MARK: - NSView overrides
extension ToolStatus {
    @objc override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        relayout()
    }

    override func viewDidMoveToWindow() {
        let delegate = toolWrapper()?.delegate?.delegate
        DLog("ToolStatus viewDidMoveToWindow: window=\(window.d), delegate=\(delegate.d), statuses in controller=\(SessionStatusController.instance.statuses.keys.map { $0 })")
        // The fresh reload below is authoritative — drop any in-flight debounced work.
        pendingFlush?.cancel()
        pendingFlush = nil
        pendingKeys.removeAll()
        statuses = SessionStatusController.instance.statuses.values.compactMap { status in
            let contains = windowContains(sessionGUID: status.sessionID)
            DLog("ToolStatus viewDidMoveToWindow: sessionID=\(status.sessionID) contains=\(contains) hasActive=\(status.hasActiveStatus)")
            if contains {
                return Status(tabStatus: status, sessionID: status.sessionID)
            } else {
                return nil
            }
        }.sorted()
        DLog("ToolStatus viewDidMoveToWindow: populated \(statuses.count) statuses")
        rebuildDisplayed()
        _tableView?.reloadData()
        updateSelectionWithoutChangingFirstResponder()
    }
}

// MARK: - Actions
extension ToolStatus {
    @objc func showSettings(_ sender: Any?) {
        StatusPrioritySettings.shared.showSettingsPopover(
            relativeTo: settingsButton.bounds,
            of: settingsButton,
            preferredEdge: .maxY)
    }

    @objc func prioritiesDidChange(_ notification: Notification) {
        // Fires for priority-order edits and for toggling workgroup merging.
        // Re-sort the full model, recompute the rendered view, and reload.
        statuses.sort()
        rebuildDisplayed()
        _tableView?.reloadData()
        updateSelectionWithoutChangingFirstResponder()
    }

    // Exposed (non-private so it reaches the generated ObjC header) for the
    // Window > Notify on Status Change menu item.
    @objc var isNotifyArmed: Bool {
        notifyArmed
    }

    @objc func toggleNotifyArmed() {
        if notifyArmed {
            disarmNotify()
        } else {
            armNotify()
        }
    }

    static let helpMarkdown = """
    ## Session Status

    The **Session Status** tool shows the status of sessions across all tabs. Each entry displays the \
    session name, a colored indicator dot, status text, and a keyboard shortcut to jump to that session.

    ### Setting Status

    **Triggers:** Add a **Set Tab Status** trigger in **Prefs > Profiles > Advanced > Triggers**. \
    It lets you set the status text, dot color, and text color when a regex matches terminal output.

    **Control Sequence (OSC 21337):** Programs can set tab status directly:

    `printf '\\e]21337;status=Working;indicator=#ffa500\\a'`

    Supported keys (separated by `;`):

    * `status=TEXT` — Sets the status text (e.g., \u{201c}Working\u{201d}, \u{201c}Waiting\u{201d}).
    * `indicator=COLOR` — Sets the dot color.
    * `status-color=COLOR` — Sets the status text color.
    * `detail=TEXT` — Sets optional detail text shown below the status (wraps up to 3 lines).

    Colors use xterm format: `rgb:RR/GG/BB` (hex, 1–4 digits per component) or `#RRGGBB`.

    Set a key to empty to clear it: `status=` clears the status text.

    **Clear all status:** `printf '\\e]21337;status=;indicator=\\a'`

    ### Priority Sorting

    Sessions are sorted by priority. Click the ⚙ button to configure which status \
    keywords have the highest priority. The default order is: waiting, working, idle.
    """
}

// MARK: - Private methods
private extension ToolStatus {
    @objc
    func activeSessionDidChange(_ notification: Notification) {
        if window == nil {
            return
        }
        updateSelectionWithoutChangingFirstResponder()
        needsShortcutReload(notification)
    }

    @objc
    func needsShortcutReload(_ notification: Notification) {
        guard let tableView = _tableView, !displayedStatuses.isEmpty else {
            return
        }
        // Active-session changes can shift many rows at once (every
        // peer-of-focus row gains or loses its ⌥⇧⌘N shortcut), so
        // reload all rows rather than chase a per-row diff that has
        // to stay in sync with the active-session computation. The
        // toolbelt is small so the cost is trivial;
        // reloadData(forRowIndexes:) preserves selection/scroll,
        // unlike full reloadData().
        let allRows = IndexSet(integersIn: 0..<displayedStatuses.count)
        tableView.reloadData(forRowIndexes: allRows,
                             columnIndexes: IndexSet(integer: 0))
    }

    func updateSelectionWithoutChangingFirstResponder() {
        disableSelectionCount += 1
        defer {
            disableSelectionCount -= 1
        }
        let guid = toolWrapper()?.delegate?.delegate?.toolbeltCurrentSessionGUID()
        let i: Int?
        if let guid, mergeWorkgroups {
            // The active session may be a non-representative peer that has no
            // row of its own, so match by workgroup: select the displayed
            // representative whose group contains the active session.
            let activeGroup = Self.groupKey(forSessionID: guid)
            i = displayedStatuses.firstIndex { status in
                Self.groupKey(forSessionID: status.sessionID) == activeGroup
            }
        } else {
            i = displayedStatuses.firstIndex { status in
                status.sessionID == guid
            }
        }
        if let i {
            _tableView?.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        } else {
            _tableView?.selectRowIndexes(IndexSet(), byExtendingSelection: false)
        }
    }

    // MARK: - Status-change notifications

    @objc private func toggleNotify(_ sender: NSButton) {
        if sender.state == .on {
            armNotify()
        } else {
            disarmNotify()
        }
    }

    private func armNotify() {
        notifyArmed = true
        // Snapshot current status text per visible session so the next change is
        // measured from now, not from whatever was on screen earlier.
        notifyStatusTextSnapshot.removeAll()
        for status in SessionStatusController.instance.statuses.values {
            guard windowContains(sessionGUID: status.sessionID),
                  let text = status.statusText else {
                continue
            }
            notifyStatusTextSnapshot[status.sessionID] = text
        }
        updateNotifyButtonAppearance()
    }

    private func disarmNotify() {
        notifyArmed = false
        notifyStatusTextSnapshot.removeAll()
        updateNotifyButtonAppearance()
    }

    private func updateNotifyButtonAppearance() {
        let symbol: SFSymbol = notifyArmed ? .bellBadge : .bell
        notifyButton.state = notifyArmed ? .on : .off
        notifyButton.image = NSImage(systemSymbolName: symbol.rawValue,
                                     accessibilityDescription: "Notify on status change")
        notifyButton.toolTip = notifyArmed
            ? "Watching for a session status change. An alert will appear on the next transition, then turn this off."
            : "Notify with an alert when any session’s status changes (waiting/idle/busy)."
    }

    // Fires when a session's status text has, on net, moved away from the value
    // captured when notifications were armed. Run against the coalesced flush
    // (not the raw event stream) so a flicker that returns to the snapshot value
    // nets to no change and never alerts, matching the debounce behavior the rest
    // of the tool relies on. Compares the controller's *current* status text, the
    // canonical net state after coalescing. Only the status (not detail) counts.
    private func checkNotifyTransitions(keys: Set<String>) {
        guard notifyArmed else {
            return
        }
        for key in keys {
            guard windowContains(sessionGUID: key) else {
                continue
            }
            let newStatusText = SessionStatusController.instance.statuses[key]?.statusText
            let oldStatusText = notifyStatusTextSnapshot[key]
            guard newStatusText != oldStatusText else {
                continue
            }
            let sessionName = iTermController.sharedInstance()?.anySession(withGUID: key)?.name
            // Disarm before presenting so the button is off the moment the alert shows.
            disarmNotify()
            presentNotifyAlert(sessionName: sessionName,
                               from: oldStatusText,
                               to: newStatusText)
            // Fire at most once per coalesced flush.
            return
        }
    }

    private func presentNotifyAlert(sessionName: String?, from: String?, to: String?) {
        let name = sessionName ?? "A session"
        let fromText = from ?? "none"
        let toText = to ?? "none"
        // Present asynchronously so the modal alert doesn't run reentrantly while
        // the status-change notification is still being dispatched.
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            let alert = NSAlert()
            alert.messageText = "Session status changed"
            alert.informativeText = "\(name) changed from “\(fromText)” to “\(toText)”."
            alert.addButton(withTitle: "OK")
            if let window = self.window {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
        }
    }

    func didChange(key: String, value: iTermSessionTabStatus?, change: NotifyingDictionaryChange) {
        DLog("ToolStatus didChange enqueue: key=\(key) change=\(change) window=\(window.d)")
        pendingKeys.insert(key)
        if pendingFlush != nil {
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.flushPendingChanges() }
        pendingFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    private func flushPendingChanges() {
        pendingFlush = nil
        let keys = pendingKeys
        pendingKeys.removeAll()
        if keys.isEmpty {
            return
        }
        // Evaluate notification transitions on the coalesced net state, before
        // mutating the model, so a flicker that returns to the snapshot value is
        // absorbed just like the row animations below.
        checkNotifyTransitions(keys: keys)
        // The session's iTermSessionTabStatus is a stable per-session reference
        // whose state accumulates across partial updates, so the canonical
        // current state is whatever the controller holds right now. Compare
        // local presence to controller presence to derive the effective change:
        // [.removed, .added] collapses to .updated, [.added, .removed] to a no-op.
        if mergeWorkgroups {
            // In merge mode a single session change can add, remove, or move a
            // workgroup's representative row, and which row is representative
            // depends on the group's other members. Those reorderings can't be
            // derived locally, so update the model and rebuild the merged view
            // in one reload rather than animating individual rows.
            for key in keys {
                applyModelChange(forKey: key)
            }
            rebuildDisplayed()
            _tableView?.reloadData()
            updateSelectionWithoutChangingFirstResponder()
            return
        }
        // Merge off: animate each row. Wrap the whole loop so multi-key bursts
        // coalesce into one animation instead of N cascading ones (the inner
        // begin/endUpdates inside animateRowMutation become harmless nested
        // calls).
        _tableView?.beginUpdates()
        for key in keys {
            let mutation = applyModelChange(forKey: key)
            // displayedStatuses mirrors statuses exactly while merging is off;
            // sync it before animating so the indices the mutation reports line
            // up with what the table reads back.
            displayedStatuses = statuses
            animateRowMutation(mutation)
        }
        _tableView?.endUpdates()
        updateSelectionWithoutChangingFirstResponder()
    }

    /// Describes how a single key's change moved the corresponding row within
    /// the full `statuses` model, so the merge-off path can animate the table.
    private enum RowMutation {
        case none
        case inserted(at: Int)
        case removed(from: Int)
        case moved(from: Int, to: Int)
    }

    /// Reconciles `statuses` with the controller's current state for one key and
    /// returns how the corresponding row moved. Mutates the model only; never
    /// touches the table.
    @discardableResult
    private func applyModelChange(forKey key: String) -> RowMutation {
        let inLocal = statuses.contains { $0.sessionID == key }
        let current = SessionStatusController.instance.statuses[key]
        switch (inLocal, current) {
        case (false, .some(let v)):
            return mutateModel(key: key, value: v, change: .added)
        case (true, .some(let v)):
            return mutateModel(key: key, value: v, change: .updated)
        case (true, .none):
            return mutateModel(key: key, value: nil, change: .removed)
        case (false, .none):
            return .none
        }
    }

    private func mutateModel(key: String,
                             value: iTermSessionTabStatus?,
                             change: NotifyingDictionaryChange) -> RowMutation {
        DLog("ToolStatus mutateModel: key=\(key) change=\(change) window=\(window.d)")
        switch change {
        case .added:
            let contains = windowContains(sessionGUID: key)
            DLog("ToolStatus didChange .added: contains=\(contains)")
            guard contains else {
                return .none
            }
            var updated = statuses
            updated.append(Status(tabStatus: value!, sessionID: key))
            updated.sort()
            guard let j = updated.firstIndex(where: { $0.sessionID == key }) else {
                return .none
            }
            statuses = updated
            return .inserted(at: j)
        case .removed:
            guard let i = statuses.firstIndex(where: { $0.sessionID == key }) else {
                return .none
            }
            statuses.remove(at: i)
            return .removed(from: i)
        case .updated:
            guard windowContains(sessionGUID: key) else {
                return .none
            }
            guard let i = statuses.firstIndex(where: { $0.sessionID == key }) else {
                it_assert(false, "mutateModel(.updated) for \(key) but session is not in statuses; applyModelChange should only route here when inLocal is true")
                return .none
            }
            var updated = statuses
            updated[i] = Status(tabStatus: value!, sessionID: key)
            updated.sort()
            guard let j = updated.firstIndex(where: { $0.sessionID == key }) else {
                return .none
            }
            statuses = updated
            return .moved(from: i, to: j)
        }
    }

    private func animateRowMutation(_ mutation: RowMutation) {
        switch mutation {
        case .none:
            break
        case .inserted(let j):
            _tableView?.beginUpdates()
            _tableView?.insertRows(at: IndexSet(integer: j))
            _tableView?.endUpdates()
        case .removed(let i):
            _tableView?.beginUpdates()
            _tableView?.removeRows(at: IndexSet(integer: i))
            _tableView?.endUpdates()
        case .moved(let i, let j):
            _tableView?.beginUpdates()
            if i != j {
                _tableView?.moveRow(at: i, to: j)
            }
            _tableView?.reloadData(forRowIndexes: IndexSet(integer: j), columnIndexes: IndexSet(integer: 0))
            // reloadData reloads cell content but keeps the cached row height;
            // detail text can wrap 1–3 lines so height must be recomputed
            // whenever tabStatus changes.
            _tableView?.noteHeightOfRows(withIndexesChanged: IndexSet(integer: j))
            _tableView?.endUpdates()
        }
    }

    private var mergeWorkgroups: Bool {
        StatusPrioritySettings.shared.mergeWorkgroups
    }

    /// Recomputes the table-facing `displayedStatuses` from the full model.
    func rebuildDisplayed() {
        guard mergeWorkgroups else {
            displayedStatuses = statuses
            return
        }
        displayedStatuses = Self.mergeByWorkgroup(statuses)
    }

    /// Groups sessions by workgroup, keeping one representative per group, then
    /// sorts the representatives by the standard table order. Solo sessions (no
    /// workgroup peer port) each remain their own entry.
    private static func mergeByWorkgroup(_ all: [Status]) -> [Status] {
        var representatives = [GroupKey: Status]()
        for status in all {
            let key = groupKey(forSessionID: status.sessionID)
            if let existing = representatives[key] {
                if mergePrefers(status, over: existing) {
                    representatives[key] = status
                }
            } else {
                representatives[key] = status
            }
        }
        return representatives.values.sorted()
    }

    private enum GroupKey: Hashable {
        // All peers in a workgroup share the same peer-port object.
        case workgroup(ObjectIdentifier)
        // Solo sessions have no peer port; key by session so each is its own row.
        case solo(String)
    }

    private static func groupKey(forSessionID sessionID: String) -> GroupKey {
        if let session = iTermController.sharedInstance()?.anySession(withGUID: sessionID),
           let port = session.peerPort {
            return .workgroup(ObjectIdentifier(port))
        }
        return .solo(sessionID)
    }

    /// Within a workgroup, the representative is the peer whose status changed
    /// most recently. Recency, not priority, is the right signal here: inside a
    /// workgroup an idle peer is often idle *because* a sibling is busy (e.g. a
    /// chat session waiting for its code-review peer to finish), so the
    /// freshest transition tracks where the action is. `lastChanged` is a
    /// reliable proxy for "last genuine transition" because the status pipeline
    /// only notifies on real changes (screenSetTabStatus bails when
    /// iTermSessionTabStatus.apply reports no change), so repaint spam never
    /// bumps it. Ties (e.g. right after a rebuild reset every timestamp to the
    /// same instant) fall back to priority, then sessionID. Note this is
    /// independent of the table's overall row ordering, which still sorts the
    /// chosen representatives by priority.
    private static func mergePrefers(_ candidate: Status, over current: Status) -> Bool {
        if candidate.lastChanged != current.lastChanged {
            return candidate.lastChanged > current.lastChanged
        }
        if candidate.tabStatus.priority != current.tabStatus.priority {
            return candidate.tabStatus.priority < current.tabStatus.priority
        }
        return candidate.sessionID < current.sessionID
    }

    func contentSize() -> NSSize {
        var size = scrollView!.contentSize
        size.height = _tableView!.intrinsicContentSize.height
        return size
    }

    // Mirrors WorkgroupModeSwitcherItem's segment labels: a peer with a
    // configured custom peerSwitchShortcut shows that shortcut; otherwise
    // peers 1..8 get their numeric digit, the *last* peer gets ⌥⇧⌘9
    // (which is what activatePeer(byShortcutDigit: 9) does), and peers
    // between 9 and count-1 get nothing.
    func peerSwitchShortcutLabel(port: iTermWorkgroupPeerPort,
                                 peerID: String) -> String? {
        if let custom = port.customShortcutLabel(forPeerID: peerID) {
            return custom
        }
        let position = port.position(forPeerID: peerID)
        guard position > 0 else {
            return nil
        }
        if position <= 8 {
            return "⌥⇧⌘\(position)"
        }
        if position == port.peerCount {
            return "⌥⇧⌘9"
        }
        return nil
    }

    func shortcutString(for sessionID: String) -> String? {
        guard let controller = iTermController.sharedInstance() else {
            return nil
        }
        guard let session = controller.anySession(withGUID: sessionID) else {
            return nil
        }

        // Peer-of-focus sessions get their ⌥⇧⌘<digit> peer-switch
        // shortcut, which always wins over pane/tab shortcuts: the
        // user wants the keystroke that switches *the focused pane*
        // to this peer, not the keystroke that focuses some other
        // split. This also applies to the row for the currently
        // active peer — the shortcut still identifies which peer the
        // row represents (and pressing it is a harmless no-op).
        // Non-visible peers are reached via anySession(withGUID:)'s
        // peer-port fallback; their delegate may not match this tab
        // but their peerPort reference survives.
        if let activeGUID = toolWrapper()?.delegate?.delegate?.toolbeltCurrentSessionGUID(),
           let activeSession = controller.anySession(withGUID: activeGUID),
           let activePort = activeSession.peerPort as? iTermWorkgroupPeerPort,
           activePort.contains(session: session),
           let peerID = activePort.identifier(for: session),
           let label = peerSwitchShortcutLabel(port: activePort, peerID: peerID) {
            return label
        }

        // For pane/tab shortcuts we need a session that's actually in
        // a tab. If `session` itself isn't (e.g. it's a non-visible
        // workgroup peer of some other pane), use its port's active
        // peer instead — that's the in-tab representative of the
        // group, and clicking the row activates this peer into that
        // pane, so "Pane N" of the active peer is the right shortcut.
        let visible: PTYSession
        if controller.terminal(with: session) != nil {
            visible = session
        } else if let activePeer = session.peerPort?.activeSession,
                  controller.terminal(with: activePeer) != nil {
            visible = activePeer
        } else {
            return nil
        }
        guard let terminal = controller.terminal(with: visible) else {
            return nil
        }
        guard let sessionTab = visible.delegate as? PTYTab else {
            return nil
        }
        let currentTab = terminal.currentTab()

        if sessionTab === currentTab && sessionTab.sessions().count > 1 {
            // Session (or its in-tab peer) is in the current tab —
            // show pane shortcut.
            let ordinal = visible.view?.ordinal ?? 0
            if ordinal != 0 {
                let paneTag = iTermPreferencesModifierTag(
                    rawValue: iTermPreferences.int(forKey: kPreferenceKeySwitchPaneModifier))
                if let paneTag, paneTag.rawValue != iTermPreferencesModifierTag.preferenceModifierTagNone.rawValue {
                    let mask = iTermPreferences.mask(for: paneTag)
                    let modString = NSString.modifierSymbols(mask: mask)
                    return "\(modString)\(ordinal)"
                }
                return "Pane \(ordinal)"
            }
        }
        // Session is in a different tab — show tab shortcut
        let tabIndex = Int(terminal.index(of: sessionTab)) + 1  // 0-based to 1-based
        if tabIndex < 1 || tabIndex > 9 {
            return nil
        }
        guard let tabTag = iTermPreferencesModifierTag(
            rawValue: iTermPreferences.int(forKey: kPreferenceKeySwitchTabModifier)) else {
            return nil
        }
        if tabTag.rawValue == iTermPreferencesModifierTag.preferenceModifierTagNone.rawValue {
            return "Tab \(tabIndex)"
        }
        let mask = iTermPreferences.mask(for: tabTag)
        let modString = NSString.modifierSymbols(mask: mask)
        return "\(modString)\(tabIndex)"
    }

    // A status belongs in this toolbelt's window iff the session has a
    // *live home* there. The window is authoritative: it walks its
    // tabs and asks each in-tab session's peer port whether it owns
    // the GUID. So a workgroup peer's status surfaces in the window
    // hosting any of its peers — whether the queried peer is in a
    // tab, properly buried, or orphaned (i.e. addBuriedSession failed
    // to register it). Solo buried sessions have no peer port and so
    // surface nowhere — they're orphans without a live home.
    func windowContains(sessionGUID guid: String) -> Bool {
        return toolWrapper()?.delegate?.delegate?
            .toolbeltWindowContainsSession(withGUID: guid) == true
    }

    func configureCell(_ cell: ToolStatusCellView, for row: Int) {
        let status = displayedStatuses[row]
        guard let session = iTermController.sharedInstance()?.anySession(withGUID: status.sessionID) else {
            return
        }
        let tabStatus = status.tabStatus

        var dotImage: NSImage?
        if tabStatus.hasIndicator {
            let c = tabStatus.indicatorColor
            let color = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
            dotImage = iTermSessionTabStatus.dotImage(color: color, size: 10, dotDiameter: 6)
        }

        var statusColor: NSColor?
        if tabStatus.hasStatusTextColor {
            let c = tabStatus.statusTextColor
            statusColor = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        }

        cell.configure(scope: session.genericScope,
                       dotImage: dotImage,
                       peerLabel: session.peerDisplayLabel,
                       shortcut: shortcutString(for: status.sessionID),
                       statusText: tabStatus.statusText,
                       statusColor: statusColor,
                       detail: tabStatus.detailText)
    }
}

extension ToolStatus: NSTableViewDataSource {
    @objc
    func numberOfRows(in tableView: NSTableView) -> Int {
        return displayedStatuses.count
    }
}

extension ToolStatus: NSTableViewDelegate {
    @objc(tableView:viewForTableColumn:row:)
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ToolStatusCell")
        let cell: ToolStatusCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? ToolStatusCellView {
            cell = reused
        } else {
            cell = ToolStatusCellView(frame: .zero)
            cell.identifier = identifier
        }
        configureCell(cell, for: row)
        return cell
    }

    @objc(tableView:heightOfRow:)
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if measuringCell == nil {
            measuringCell = ToolStatusCellView(frame: .zero)
        }
        configureCell(measuringCell!, for: row)
        measuringCell!.frame = NSRect(x: 0, y: 0, width: tableView.frame.width, height: 0)
        measuringCell!.needsLayout = true
        measuringCell!.layoutSubtreeIfNeeded()
        return measuringCell!.fittingSize.height
    }

    @objc
    func tableViewSelectionDidChange(_ notification: Notification) {
        if disableSelectionCount > 0 {
            return
        }
        let row = _tableView!.selectedRow
        if row == -1 {
            return
        }
        let guid = displayedStatuses[row].sessionID
        guard let session = iTermController.sharedInstance()?.anySession(withGUID: guid) else {
            DLog("No session with ID \(guid)")
            return
        }
        session.reveal()
        window?.makeFirstResponder(_tableView)
    }
}
