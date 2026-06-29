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
        // Snoozed rows sink to the bottom of the list and render dimmed.
        // This is transient per-tool UI state, not part of the session's
        // tab status, so it lives here rather than in iTermSessionTabStatus.
        var snoozed = false

        static func < (lhs: ToolStatus.Status, rhs: ToolStatus.Status) -> Bool {
            if lhs.snoozed != rhs.snoozed {
                // Snoozed entries always sort after un-snoozed ones,
                // regardless of priority or recency.
                return !lhs.snoozed
            }
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
    // Session GUIDs the user has snoozed via the row context menu. Transient
    // per-tool UI state (not persisted): snoozed rows sink to the bottom and
    // render dimmed, and auto-un-snooze when their status next changes.
    private var snoozedSessionIDs = Set<String>()
    // Holds the memoized lookup result weakly, so a key present with a
    // now-nil session means "was resolved, but that session has since
    // died" — which resolveSessionForReload reports the same as a miss
    // (nil), blanking the cell. This makes the memo self-healing for
    // session deaths: even if some reload path forgets to drop it, a
    // dead session can never be rendered as alive, and a terminated
    // session isn't retained for the rest of the cycle.
    private final class WeakSessionBox {
        weak var session: PTYSession?
        init(_ session: PTYSession?) { self.session = session }
    }
    // Per-reload session-resolution memo. configureCell runs twice per
    // row per reload (height pass + view pass) and an unresolvable
    // GUID pays the full five-leg session-lookup walk on every miss,
    // so each reload entry point drops the memo and the passes share
    // one resolution per GUID. The box records known misses too. The
    // weak box bounds correctness on deaths; the explicit clears (one
    // per reload entry point) handle the opposite direction, where a
    // previously-unresolvable GUID becomes resolvable.
    private var resolvedSessionsForReload: [String: WeakSessionBox] = [:]

    // Internal (not private) so tests can pin the memo/invalidate
    // contract without standing up the whole toolbelt table pipeline.
    func resolveSessionForReload(guid: String) -> PTYSession? {
        if let box = resolvedSessionsForReload[guid] {
            return box.session
        }
        let session = iTermController.sharedInstance()?.anySession(withGUID: guid)
        resolvedSessionsForReload[guid] = WeakSessionBox(session)
        return session
    }

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
        // Right-click menu for snoozing rows. Populated per right-click in
        // menuNeedsUpdate from the table's clickedRow.
        let rowMenu = NSMenu()
        rowMenu.delegate = self
        _tableView!.menu = rowMenu
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
        // The armed state now lives in the centralized controller (so the
        // Window menu and Cockpit share it); keep the bell in sync when it
        // changes from anywhere.
        nc.addObserver(self,
                       selector: #selector(notifyArmedDidChange(_:)),
                       name: NotifyOnStatusChangeController.armedDidChangeNotification,
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
        resolvedSessionsForReload.removeAll()
        pendingFlush?.cancel()
        pendingFlush = nil
        pendingKeys.removeAll()
        statuses = SessionStatusController.instance.statuses.values.compactMap { status in
            let contains = windowContains(sessionGUID: status.sessionID)
            DLog("ToolStatus viewDidMoveToWindow: sessionID=\(status.sessionID) contains=\(contains) hasActive=\(status.hasActiveStatus)")
            if contains {
                return makeStatus(tabStatus: status, sessionID: status.sessionID)
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
        resolvedSessionsForReload.removeAll()
        statuses.sort()
        rebuildDisplayed()
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

    ### Snoozing

    Right-click a row and choose **Snooze** to move it to the bottom of the list and \
    dim it. A snoozed entry automatically un-snoozes the next time its status changes.
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
        // The window guid is derived from the active session, so refresh
        // the bell once the window is established (e.g. the toolbelt was
        // opened for a window that was already armed elsewhere).
        updateNotifyButtonAppearance()
    }

    @objc
    func needsShortcutReload(_ notification: Notification) {
        guard let tableView = _tableView, !displayedStatuses.isEmpty else {
            return
        }
        // Session/tab topology changed (these notifications include
        // session creation/destruction), so resolvability may have too.
        resolvedSessionsForReload.removeAll()
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
        // This programmatic change skips tableViewSelectionDidChange (it's
        // suppressed by disableSelectionCount), so refresh the bell here.
        updateNotifyButtonAppearance()
    }

    // MARK: - Status-change notifications

    // What the bell acts on: the selected session if a row is selected,
    // otherwise the whole window.
    private enum NotifyTarget {
        case session(String)
        case window(String)
    }

    // Note: the session target is NOT gated on the GUID resolving via
    // anySession(withGUID:). NotifyOnStatusChangeController arms and
    // fires purely off the status dictionary keyed by GUID, so arming
    // works even for a session the lookup can't reach (the blank-row
    // shape); only a genuinely exited session leaves the bell armed
    // forever, which is harmless and less surprising than silently
    // rescoping the click to the whole window.
    private var notifyTarget: NotifyTarget? {
        if let row = _tableView?.selectedRow, row >= 0, row < displayedStatuses.count {
            return .session(displayedStatuses[row].sessionID)
        }
        if let windowGuid {
            return .window(windowGuid)
        }
        return nil
    }

    // The bell toggles the centralized armed state for the current target.
    // The button's visual state is driven by the controller (via
    // notifyArmedDidChange) and the selection, not by the click itself.
    @objc private func toggleNotify(_ sender: NSButton) {
        let controller = NotifyOnStatusChangeController.instance
        switch notifyTarget {
        case .session(let guid):
            controller.toggleSessionArmed(forGuid: guid)
        case .window(let guid):
            controller.toggleWindowArmed(forGuid: guid)
        case nil:
            break
        }
        updateNotifyButtonAppearance()
    }

    @objc private func notifyArmedDidChange(_ notification: Notification) {
        // This is a reload entry point like the others, so it must
        // drop the session memo too: a session can exit between
        // topology notifications, and rendering this reload from the
        // stale hit would resurrect the recycled-row symptom (and
        // retain the dead session) until the next flush.
        resolvedSessionsForReload.removeAll()
        updateNotifyButtonAppearance()
        // Per-session bell indicators may have changed; refresh visible
        // rows (preserves selection/scroll, unlike full reloadData()).
        if let tableView = _tableView, !displayedStatuses.isEmpty {
            tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<displayedStatuses.count),
                                 columnIndexes: IndexSet(integer: 0))
        }
    }

    // The terminal guid of the window hosting this toolbelt, derived from
    // its current session (works even when the toolbelt is detached into
    // its own window).
    private var windowGuid: String? {
        guard let sessionGuid = toolWrapper()?.delegate?.delegate?.toolbeltCurrentSessionGUID(),
              !sessionGuid.isEmpty else {
            return nil
        }
        return iTermController.sharedInstance()?
            .windowForSession(withGUID: sessionGuid)?.terminalGuid
    }

    private func updateNotifyButtonAppearance() {
        // Resolve the target once; computing it involves table and
        // window lookups and this runs on every status flush.
        let target = notifyTarget
        let controller = NotifyOnStatusChangeController.instance
        let armed: Bool
        let targetingSession: Bool
        switch target {
        case .session(let guid):
            armed = controller.isSessionArmed(forGuid: guid)
            targetingSession = true
        case .window(let guid):
            armed = controller.isWindowArmed(forGuid: guid)
            targetingSession = false
        case nil:
            armed = false
            targetingSession = false
        }
        let symbol: SFSymbol = armed ? .bellBadge : .bell
        notifyButton.state = armed ? .on : .off
        notifyButton.image = NSImage(systemSymbolName: symbol.rawValue,
                                     accessibilityDescription: "Notify on status change")
        if armed {
            notifyButton.toolTip = targetingSession
                ? "Watching the selected session for a status change. An alert will appear on the next change, then turn this off."
                : "Watching this window for a session status change. An alert will appear on the next change, then turn this off."
        } else {
            notifyButton.toolTip = targetingSession
                ? "Notify with an alert when the selected session’s status changes."
                : "Notify with an alert when any session in this window changes status."
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
        resolvedSessionsForReload.removeAll()
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
        // A status change can auto-un-snooze a row, shifting the snoozed/active
        // boundary onto a row the per-row animation above didn't reload. Refresh
        // the separator on every row so the divider lands in the right place.
        refreshSeparators()
        updateSelectionWithoutChangingFirstResponder()
    }

    /// Re-renders every row so each cell's snoozed-group divider reflects the
    /// current ordering. Cheap (the toolbelt is small) and preserves selection
    /// and scroll, unlike a full reloadData(). No-op when nothing is snoozed.
    private func refreshSeparators() {
        guard !snoozedSessionIDs.isEmpty,
              let tableView = _tableView,
              !displayedStatuses.isEmpty else {
            return
        }
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<displayedStatuses.count),
                             columnIndexes: IndexSet(integer: 0))
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
            updated.append(makeStatus(tabStatus: value!, sessionID: key))
            updated.sort()
            guard let j = updated.firstIndex(where: { $0.sessionID == key }) else {
                return .none
            }
            statuses = updated
            return .inserted(at: j)
        case .removed:
            // Drop any snooze so a session whose status later reappears
            // comes back un-snoozed, and so the set doesn't accumulate
            // GUIDs of gone sessions.
            snoozedSessionIDs.remove(key)
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
            // A status change auto-un-snoozes the row. makeStatus reads the
            // snooze set, so clear it first to get snoozed == false.
            snoozedSessionIDs.remove(key)
            var updated = statuses
            updated[i] = makeStatus(tabStatus: value!, sessionID: key)
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
    /// sorts the representatives by the standard table order. Solo sessions (not
    /// in any workgroup) each remain their own entry.
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

    private static func groupKey(forSessionID sessionID: String) -> GroupKey {
        guard let session = iTermController.sharedInstance()?.anySession(withGUID: sessionID) else {
            return .solo(sessionID)
        }
        let workgroupInstanceID = iTermWorkgroupController.instance
            .workgroupInstance(on: session)?.instanceUniqueIdentifier
        let peerPortIdentity = session.peerPort.map { ObjectIdentifier($0) }
        return groupKey(sessionID: sessionID,
                        workgroupInstanceID: workgroupInstanceID,
                        peerPortIdentity: peerPortIdentity)
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
    ///
    /// A snoozed member *loses* representation: the merged row should surface
    /// the group's liveliest non-snoozed member rather than let one snoozed
    /// peer's stale status hide an active sibling (e.g. a snoozed idle chat
    /// peer must not bury a code-review peer that just started waiting for
    /// input). A workgroup therefore only renders as snoozed (dimmed, at the
    /// bottom) when *every* member is snoozed, leaving a snoozed representative
    /// as the sole candidate.
    private static func mergePrefers(_ candidate: Status, over current: Status) -> Bool {
        return mergeRepresentativePrefers(
            candidateSnoozed: candidate.snoozed,
            candidateLastChanged: candidate.lastChanged,
            candidatePriority: candidate.tabStatus.priority,
            candidateSessionID: candidate.sessionID,
            currentSnoozed: current.snoozed,
            currentLastChanged: current.lastChanged,
            currentPriority: current.tabStatus.priority,
            currentSessionID: current.sessionID)
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

    // iTermController's generic unresolvable-session topology dump plus
    // the one line only this tool can add: the status-controller keys.
    // A status row whose GUID resolves to nothing renders as a blank
    // cell and its click does nothing, so when that happens this dump
    // should show which link in the lookup chain is broken (e.g. an
    // alive session that is in no tab, not buried, and in no reachable
    // peer port).
    static func diagnosis(unresolvableGUID guid: String) -> String {
        let base = iTermController.sharedInstance()?.diagnosis(unresolvableGUID: guid)
            ?? "Diagnosis for unresolvable session \(guid): no iTermController"
        return "\(base)\n  status controller keys: \(SessionStatusController.instance.statuses.keys.sorted())"
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

    // True for the topmost snoozed row, which draws the divider separating
    // the snoozed group from the active rows above it. Snoozed rows always
    // sort to the end, so this is the first snoozed entry whose predecessor
    // is not snoozed. A snoozed row at index 0 has no active rows above it
    // (everything is snoozed), so it draws no divider.
    private func isFirstSnoozedRow(_ row: Int) -> Bool {
        guard row > 0, row < displayedStatuses.count, displayedStatuses[row].snoozed else {
            return false
        }
        return !displayedStatuses[row - 1].snoozed
    }

    // Builds a Status carrying the session's current snooze state.
    private func makeStatus(tabStatus: iTermSessionTabStatus, sessionID: String) -> Status {
        return Status(tabStatus: tabStatus,
                      sessionID: sessionID,
                      snoozed: snoozedSessionIDs.contains(sessionID))
    }

    func configureCell(_ cell: ToolStatusCellView, for row: Int) {
        let status = displayedStatuses[row]
        guard let session = resolveSessionForReload(guid: status.sessionID) else {
            // One dump per GUID per debug-logging session: configureCell
            // runs on every reload and height pass, and undeduped repeats
            // would rotate the dump out of the capped log. The dedup
            // lives in DebugLogging (global across windows, re-armed
            // when a new logging session starts, untouched while logging
            // is off), and the message block only runs when it will log.
            // Clicking the row emits an undeduped on-demand dump.
            DLogOncePerLoggingSession("ToolStatus.unresolvableGUID.\(status.sessionID)") {
                "ToolStatus configureCell: anySession(withGUID:) failed for guid=\(status.sessionID) statusText=\(status.tabStatus.statusText.d) detail=\(status.tabStatus.detailText.d); blanking the cell\n\(Self.diagnosis(unresolvableGUID: status.sessionID))"
            }
            // This path skips configure() (which is self-clearing), so
            // blank the cell directly: it may be a recycled cell or
            // the manually reused measuring cell, either of which
            // would otherwise keep a previous row's content.
            cell.clear()
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
                       detail: tabStatus.detailText,
                       armed: NotifyOnStatusChangeController.instance.isSessionArmed(forGuid: status.sessionID),
                       dimmed: status.snoozed,
                       showSeparator: isFirstSnoozedRow(row))
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
        // The bell targets the selected session, so keep it in sync.
        updateNotifyButtonAppearance()
        let row = _tableView!.selectedRow
        if row == -1 {
            return
        }
        let guid = displayedStatuses[row].sessionID
        guard let session = iTermController.sharedInstance()?.anySession(withGUID: guid) else {
            // Deliberately NOT deduped via DLogOncePerLoggingSession:
            // clicking a blank row is an explicit user action and the
            // on-demand way to capture a diagnosis (configureCell's
            // one-shot may have fired before logging was enabled, and
            // an unreachable session generates no reload that would
            // re-trigger it).
            DLog("No session with ID \(guid)\n\(Self.diagnosis(unresolvableGUID: guid))")
            return
        }
        session.reveal()
        window?.makeFirstResponder(_tableView)
    }
}

// MARK: - Snooze context menu
extension ToolStatus: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let tableView = _tableView else {
            return
        }
        let row = tableView.clickedRow
        guard row >= 0, row < displayedStatuses.count else {
            return
        }
        let sessionID = displayedStatuses[row].sessionID
        // A merged row stands for a whole workgroup, so its checkmark reflects
        // (and its toggle affects) every member, not just the representative.
        let members = groupMemberSessionIDs(forRepresentative: sessionID)
        let item = NSMenuItem(title: "Snooze",
                              action: #selector(toggleSnooze(_:)),
                              keyEquivalent: "")
        item.target = self
        item.state = allSnoozed(members) ? .on : .off
        item.representedObject = sessionID
        menu.addItem(item)
    }

    @objc func toggleSnooze(_ sender: NSMenuItem) {
        guard let sessionID = sender.representedObject as? String else {
            return
        }
        let members = groupMemberSessionIDs(forRepresentative: sessionID)
        // Toggle the group as a unit: if every member is already snoozed,
        // un-snooze them all; otherwise snooze them all so the merged row
        // reads as snoozed (a snoozed member only represents when all are).
        setSnoozed(!allSnoozed(members), forSessionIDs: members)
    }

    // The session IDs in `statuses` that share the clicked representative's
    // merge group. With merging off each row is its own session, so this is
    // just that one session.
    private func groupMemberSessionIDs(forRepresentative sessionID: String) -> [String] {
        guard mergeWorkgroups else {
            return [sessionID]
        }
        let targetKey = Self.groupKey(forSessionID: sessionID)
        return statuses
            .map { $0.sessionID }
            .filter { Self.groupKey(forSessionID: $0) == targetKey }
    }

    private func allSnoozed(_ sessionIDs: [String]) -> Bool {
        return !sessionIDs.isEmpty && sessionIDs.allSatisfy { snoozedSessionIDs.contains($0) }
    }

    private func setSnoozed(_ snoozed: Bool, forSessionIDs sessionIDs: [String]) {
        let ids = Set(sessionIDs)
        guard !ids.isEmpty else {
            return
        }
        if snoozed {
            snoozedSessionIDs.formUnion(ids)
        } else {
            snoozedSessionIDs.subtract(ids)
        }
        // Reflect the new flags on the model, re-sort so snoozed rows sink to
        // the bottom, and reload. A snooze toggle can move rows across the
        // whole list, so a full reload is simpler than animating each move.
        for i in statuses.indices where ids.contains(statuses[i].sessionID) {
            statuses[i].snoozed = snoozed
        }
        statuses.sort()
        rebuildDisplayed()
        _tableView?.reloadData()
        updateSelectionWithoutChangingFirstResponder()
    }
}

// MARK: - Workgroup merge grouping (internal for testing)
extension ToolStatus {
    enum GroupKey: Hashable {
        // Every member of a workgroup shares its instance's stable id, so all
        // of a workgroup's sessions collapse to one row even when they span
        // several peer ports (the main port plus nested ports for split hosts)
        // or are port-less split/tab children.
        case workgroup(String)
        // A workgroup peer port that couldn't be resolved to a registered
        // instance (e.g. a stale back-pointer). Falls back to port identity so
        // such peers still merge, matching the previous behavior.
        case peerPort(ObjectIdentifier)
        // Sessions in no workgroup; key by session so each is its own row.
        case solo(String)
    }

    /// Pure grouping rule, separated from the live session/workgroup lookups so
    /// it can be unit-tested: a session's workgroup instance is the strongest
    /// signal (it spans every peer port of the workgroup), then peer-port
    /// identity as a fallback, then solo.
    static func groupKey(sessionID: String,
                         workgroupInstanceID: String?,
                         peerPortIdentity: ObjectIdentifier?) -> GroupKey {
        if let workgroupInstanceID {
            return .workgroup(workgroupInstanceID)
        }
        if let peerPortIdentity {
            return .peerPort(peerPortIdentity)
        }
        return .solo(sessionID)
    }

    /// Pure representative-preference rule (see `mergePrefers`), separated from
    /// `Status` so it can be unit-tested. Non-snoozed beats snoozed, then
    /// recency beats priority beats sessionID.
    static func mergeRepresentativePrefers(candidateSnoozed: Bool,
                                           candidateLastChanged: TimeInterval,
                                           candidatePriority: Int,
                                           candidateSessionID: String,
                                           currentSnoozed: Bool,
                                           currentLastChanged: TimeInterval,
                                           currentPriority: Int,
                                           currentSessionID: String) -> Bool {
        if candidateSnoozed != currentSnoozed {
            // A snoozed member loses representation, so the merged row shows
            // the liveliest non-snoozed peer; the group only reads as snoozed
            // when every member is.
            return !candidateSnoozed
        }
        if candidateLastChanged != currentLastChanged {
            return candidateLastChanged > currentLastChanged
        }
        if candidatePriority != currentPriority {
            return candidatePriority < currentPriority
        }
        return candidateSessionID < currentSessionID
    }
}
