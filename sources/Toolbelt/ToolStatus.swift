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

    private var statuses = [Status]()
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
        // Re-sort all statuses and reload the table.
        statuses.sort()
        _tableView?.reloadData()
        updateSelectionWithoutChangingFirstResponder()
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
        guard let tableView = _tableView, !statuses.isEmpty else {
            return
        }
        // Active-session changes can shift many rows at once (every
        // peer-of-focus row gains or loses its ⌥⇧⌘N shortcut), so
        // reload all rows rather than chase a per-row diff that has
        // to stay in sync with the active-session computation. The
        // toolbelt is small so the cost is trivial;
        // reloadData(forRowIndexes:) preserves selection/scroll,
        // unlike full reloadData().
        let allRows = IndexSet(integersIn: 0..<statuses.count)
        tableView.reloadData(forRowIndexes: allRows,
                             columnIndexes: IndexSet(integer: 0))
    }

    func updateSelectionWithoutChangingFirstResponder() {
        disableSelectionCount += 1
        defer {
            disableSelectionCount -= 1
        }
        let guid = toolWrapper()?.delegate?.delegate?.toolbeltCurrentSessionGUID()
        let i = statuses.firstIndex { status in
            status.sessionID == guid
        }
        if let i {
            _tableView?.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        } else {
            _tableView?.selectRowIndexes(IndexSet(), byExtendingSelection: false)
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
        // The session's iTermSessionTabStatus is a stable per-session reference
        // whose state accumulates across partial updates, so the canonical
        // current state is whatever the controller holds right now. Compare
        // local presence to controller presence to derive the effective change:
        // [.removed, .added] collapses to .updated, [.added, .removed] to a no-op.
        // Wrap the whole loop so multi-key bursts coalesce into one animation
        // instead of N cascading ones (the inner begin/endUpdates inside
        // applyChange become harmless nested calls).
        _tableView?.beginUpdates()
        for key in keys {
            let inLocal = statuses.contains { $0.sessionID == key }
            let current = SessionStatusController.instance.statuses[key]
            switch (inLocal, current) {
            case (false, .some(let v)):
                applyChange(key: key, value: v, change: .added)
            case (true, .some(let v)):
                applyChange(key: key, value: v, change: .updated)
            case (true, .none):
                applyChange(key: key, value: nil, change: .removed)
            case (false, .none):
                continue
            }
        }
        _tableView?.endUpdates()
        updateSelectionWithoutChangingFirstResponder()
    }

    private func applyChange(key: String, value: iTermSessionTabStatus?, change: NotifyingDictionaryChange) {
        DLog("ToolStatus applyChange: key=\(key) change=\(change) window=\(window.d)")
        switch change {
        case .added:
            let contains = windowContains(sessionGUID: key)
            DLog("ToolStatus didChange .added: contains=\(contains)")
            guard contains else {
                return
            }
            let newValue = Status(tabStatus: value!, sessionID: key)
            var updated = statuses
            updated.append(newValue)
            updated = updated.sorted { lhs, rhs in
                lhs < rhs
            }
            let j = updated.firstIndex { $0.sessionID == key }
            if let j {
                statuses = updated
                _tableView?.beginUpdates()
                _tableView?.insertRows(at: IndexSet(integer: j))
                _tableView?.endUpdates()
            }
        case .removed:
            let i = statuses.firstIndex { candidate in
                candidate.sessionID == key
            }
            if let i {
                _tableView?.beginUpdates()
                statuses.remove(at: i)
                _tableView?.removeRows(at: IndexSet(integer: i))
                _tableView?.endUpdates()
            }
        case .updated:
            guard windowContains(sessionGUID: key) else {
                return
            }
            guard let i = statuses.firstIndex(where: { $0.sessionID == key }) else {
                it_assert(false, "applyChange(.updated) for \(key) but session is not in statuses; flushPendingChanges should only route here when inLocal is true")
                return
            }
            let newValue = Status(tabStatus: value!, sessionID: key)
            var updated = statuses
            updated[i] = newValue
            updated = updated.sorted { lhs, rhs in
                lhs < rhs
            }
            let j = updated.firstIndex { $0.sessionID == key }
            if let j {
                _tableView?.beginUpdates()
                statuses = updated
                if i != j {
                    _tableView?.moveRow(at: i, to: j)
                }
                _tableView?.reloadData(forRowIndexes: IndexSet(integer: j), columnIndexes: IndexSet(integer: 0))
                // reloadData reloads cell content but keeps the cached row
                // height; detail text can wrap 1–3 lines so height must be
                // recomputed whenever tabStatus changes.
                _tableView?.noteHeightOfRows(withIndexesChanged: IndexSet(integer: j))
                _tableView?.endUpdates()
            }
        }
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
        let status = statuses[row]
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
        return statuses.count
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
        let guid = statuses[row].sessionID
        guard let session = iTermController.sharedInstance()?.anySession(withGUID: guid) else {
            DLog("No session with ID \(guid)")
            return
        }
        session.reveal()
        window?.makeFirstResponder(_tableView)
    }
}
