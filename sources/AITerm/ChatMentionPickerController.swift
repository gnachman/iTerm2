//
//  ChatMentionPickerController.swift
//  iTerm2
//
//  The autocomplete popup shown while the user types an @-mention in an
//  orchestration chat. It lists the current terminal sessions in a
//  window > tab > pane > peer outline (the peer level is omitted for panes with
//  no peers) and shows a live snapshot of the highlighted session in an
//  adjoining preview, reusing iTermSessionPreviewPanel (the same panel Open
//  Quickly uses). Only session rows are selectable; window/tab rows are just
//  hierarchy. Choosing a session reports its guid and display name back to the
//  caller, which inserts a ChatSessionMentionAttachment.
//
//  The panel never takes key focus: it is a non-activating child window driven
//  programmatically (moveSelectionUp/Down/commitSelection) from the chat input's
//  field editor, so the user keeps typing into the text view the whole time.
//

import AppKit

final class ChatMentionPickerController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    // One row of the outline. Session rows carry a PTYSession and are
    // selectable; window/tab rows carry nil and exist only for hierarchy.
    final class Node {
        enum Kind { case window, tab, session }
        let kind: Kind
        let title: String
        let session: PTYSession?
        var children: [Node]

        init(kind: Kind, title: String, session: PTYSession?, children: [Node]) {
            self.kind = kind
            self.title = title
            self.session = session
            self.children = children
        }

        var isSelectable: Bool { session != nil }
    }

    private let panel: NSPanel
    private let outlineView: NSOutlineView
    private let scrollView: NSScrollView
    private let column: NSTableColumn
    private let previewPanel = iTermSessionPreviewPanel()
    // A colored overlay laid over the highlighted session's real view so the
    // user can see in the workspace which session the selected row points at.
    private weak var highlightedSessionView: NSView?
    private weak var highlightOverlay: NSView?
    private var roots: [Node] = []
    private var onChoose: ((_ guid: String, _ displayName: String) -> Void)?
    private weak var anchorView: NSView?
    private weak var hostWindow: NSWindow?
    private(set) var isVisible = false

    private static let panelWidth: CGFloat = 280
    private static let rowHeight: CGFloat = 22
    private static let maxVisibleRows = 12

    override init() {
        let outline = NSOutlineView(frame: .zero)
        let scroll = NSScrollView(frame: .zero)
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: ChatMentionPickerController.panelWidth, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: true)
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mention"))
        panel = p
        outlineView = outline
        scrollView = scroll
        column = col
        super.init()

        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true

        let contentView = NSView(frame: p.contentLayoutRect)
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 8
        contentView.layer?.masksToBounds = true
        p.contentView = contentView

        let visual = NSVisualEffectView(frame: contentView.bounds)
        visual.autoresizingMask = [.width, .height]
        visual.blendingMode = .behindWindow
        visual.material = .menu
        visual.state = .active
        contentView.addSubview(visual)

        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = ChatMentionPickerController.rowHeight
        outline.backgroundColor = .clear
        outline.indentationPerLevel = 14
        outline.selectionHighlightStyle = .regular
        outline.allowsEmptySelection = true
        outline.allowsMultipleSelection = false
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked)
        outline.action = #selector(singleClicked)
        outline.autoresizingMask = [.width, .height]
        if #available(macOS 11.0, *) {
            outline.style = .inset
        }

        scroll.frame = contentView.bounds
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = outline
        contentView.addSubview(scroll)
    }

    // MARK: - Presentation

    func show(anchorView: NSView,
              query: String,
              onChoose: @escaping (_ guid: String, _ displayName: String) -> Void) {
        self.anchorView = anchorView
        self.hostWindow = anchorView.window
        self.onChoose = onChoose
        rebuild(query: query)
        guard !roots.isEmpty else {
            hide()
            return
        }
        if !isVisible {
            hostWindow?.addChildWindow(panel, ordered: .above)
            isVisible = true
        }
        reposition()
        selectFirstSelectableRow()
        refreshPreview()
    }

    func update(query: String) {
        guard isVisible else { return }
        rebuild(query: query)
        if roots.isEmpty {
            hide()
            return
        }
        reposition()
        selectFirstSelectableRow()
        refreshPreview()
    }

    func hide() {
        guard isVisible else { return }
        setHighlightedSession(nil)
        previewPanel.teardown()
        if let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        panel.orderOut(nil)
        isVisible = false
        onChoose = nil
    }

    // MARK: - Keyboard-driven selection (called from the chat input field editor)

    func moveSelectionDown() {
        moveSelection(by: 1)
    }

    func moveSelectionUp() {
        moveSelection(by: -1)
    }

    func commitSelection() {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node,
              let session = node.session else {
            return
        }
        let choose = onChoose
        hide()
        choose?(session.guid, ChatMentionDisplay.displayName(for: session))
    }

    private func moveSelection(by delta: Int) {
        let count = outlineView.numberOfRows
        guard count > 0 else { return }
        var row = outlineView.selectedRow
        // Step in `delta`'s direction, skipping non-selectable (window/tab) rows.
        var steps = 0
        while steps < count {
            row += delta
            if row < 0 { row = count - 1 }
            if row >= count { row = 0 }
            if let node = outlineView.item(atRow: row) as? Node, node.isSelectable {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
                refreshPreview()
                return
            }
            steps += 1
        }
    }

    private func selectFirstSelectableRow() {
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? Node, node.isSelectable {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
                return
            }
        }
    }

    // MARK: - Model

    // Rebuild the outline from the live session list, pruned to `query`.
    private func rebuild(query: String) {
        roots = Self.buildRoots(query: query)
        outlineView.reloadData()
        for root in roots {
            outlineView.expandItem(root, expandChildren: true)
        }
    }

    private static func buildRoots(query: String) -> [Node] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matches: (PTYSession) -> Bool = { session in
            needle.isEmpty || session.name.lowercased().contains(needle)
        }
        guard let controller = iTermController.sharedInstance() else { return [] }
        // Window/tab names usually duplicate the session name, so append the
        // keyboard shortcut that activates them (when one exists) to make the
        // rows worth their space. Both modifiers are user-configurable.
        let tabGlyphs = modifierGlyphs(forTag: Int(iTermPreferences.int(forKey: kPreferenceKeySwitchTabModifier)))
        let windowGlyphs = modifierGlyphs(forTag: Int(iTermPreferences.int(forKey: kPreferenceKeySwitchWindowModifier)))
        var windowNodes: [Node] = []
        for term in controller.terminals() {
            let tabs = term.tabs() ?? []
            var tabNodes: [Node] = []
            for (index, tab) in tabs.enumerated() {
                let paneNodes = paneNodes(for: tab, matches: matches)
                if !paneNodes.isEmpty {
                    let shortcut = tabShortcut(index: index, count: tabs.count, glyphs: tabGlyphs)
                    tabNodes.append(Node(kind: .tab,
                                         title: appendShortcut(tab.title, shortcut),
                                         session: nil,
                                         children: paneNodes))
                }
            }
            if !tabNodes.isEmpty {
                let base = (term.window?.title.isEmpty == false) ? term.window!.title : "Window \(term.number + 1)"
                let shortcut = windowShortcut(number: Int(term.number), glyphs: windowGlyphs)
                windowNodes.append(Node(kind: .window,
                                        title: appendShortcut(base, shortcut),
                                        session: nil,
                                        children: tabNodes))
            }
        }
        return windowNodes
    }

    private static func appendShortcut(_ title: String, _ shortcut: String?) -> String {
        guard let shortcut else { return title }
        return "\(title)  \(shortcut)"
    }

    // The glyph string for a switch-tab/switch-window modifier preference tag
    // (iTermPreferencesModifierTag), or nil when no modifier is assigned. Order
    // follows the macOS canonical ⌃⌥⇧⌘.
    private static func modifierGlyphs(forTag tag: Int) -> String? {
        switch tag {
        case 1: return "⌃"          // legacy/either control
        case 2, 3, 5: return "⌥"    // left/right/either option
        case 4, 7, 8: return "⌘"    // either/left/right command
        case 6: return "⌥⌘"         // command and option
        case 10: return "fn"
        default: return nil         // 9 = none, or unknown
        }
    }

    // Mirrors iTermApplication.switchToTabInTabView: digits 1-8 select tabs by
    // position; digit 9 always selects the last tab.
    private static func tabShortcut(index: Int, count: Int, glyphs: String?) -> String? {
        guard let glyphs else { return nil }
        let digit: Int
        if index < 8 {
            digit = index + 1
        } else if index == count - 1 {
            digit = 9
        } else {
            return nil
        }
        return "\(glyphs)\(digit)"
    }

    // Mirrors iTermApplication.switchToWindowByNumber: digits 1-9 map to window
    // numbers 0-8.
    private static func windowShortcut(number: Int, glyphs: String?) -> String? {
        guard let glyphs, number >= 0, number <= 8 else { return nil }
        return "\(glyphs)\(number + 1)"
    }

    private static func paneNodes(for tab: PTYTab, matches: (PTYSession) -> Bool) -> [Node] {
        guard let sessions = tab.orderedSessions as? [PTYSession] else { return [] }
        var result: [Node] = []
        for session in sessions {
            // A pane that belongs to a workgroup peer group exposes its peers as
            // children; otherwise it's a plain leaf (the peer level is omitted).
            // Use the workgroup port's ordered accessor so the peers appear in
            // the same order as the peer switcher control; fall back to the
            // unordered set for non-workgroup peer ports.
            let peers: [PTYSession]
            if let wgPort = session.peerPort as? iTermWorkgroupPeerPort {
                peers = wgPort.orderedRealizedPeerSessions
            } else {
                peers = session.peerPort?.realizedPeerSessions ?? []
            }
            if peers.count > 1 {
                let peerNodes = peers
                    .filter(matches)
                    .map { Node(kind: .session, title: ChatMentionDisplay.displayName(for: $0), session: $0, children: []) }
                if !peerNodes.isEmpty {
                    // The peer group spans multiple roles, so name it for the
                    // workgroup, not any one peer.
                    let groupTitle = ChatMentionDisplay.context(for: session)?.workgroup ?? session.name
                    result.append(Node(kind: .tab,
                                       title: groupTitle.isEmpty ? "Workgroup" : groupTitle,
                                       session: nil,
                                       children: peerNodes))
                }
            } else if matches(session) {
                result.append(Node(kind: .session, title: ChatMentionDisplay.displayName(for: session), session: session, children: []))
            }
        }
        return result
    }

    // MARK: - Geometry

    private func reposition() {
        guard let anchorView, let hostWindow else { return }
        let height = panelHeight()
        let anchorInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorOnScreen = hostWindow.convertToScreen(anchorInWindow)
        let screen = hostWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchorOnScreen

        var originX = anchorOnScreen.minX
        originX = min(originX, visible.maxX - Self.panelWidth)
        originX = max(originX, visible.minX)

        // Prefer floating above the input field; drop below if it would clip the
        // top of the screen.
        let gap: CGFloat = 4
        var originY = anchorOnScreen.maxY + gap
        if originY + height > visible.maxY {
            originY = anchorOnScreen.minY - gap - height
        }
        originY = max(originY, visible.minY)

        panel.setFrame(NSRect(x: originX, y: originY, width: Self.panelWidth, height: height), display: true)

        // The single column doesn't track the outline's width on its own, so it
        // keeps its default width and labels truncate early. Size it to the clip
        // view now that the panel (and thus the scroll view) has its real width.
        scrollView.layoutSubtreeIfNeeded()
        let contentWidth = scrollView.contentView.bounds.width
        if contentWidth > 0 {
            column.width = contentWidth
        }
    }

    private func panelHeight() -> CGFloat {
        let rows = min(max(outlineView.numberOfRows, 1), Self.maxVisibleRows)
        return CGFloat(rows) * Self.rowHeight + 8
    }

    private func refreshPreview() {
        let session = selectedSession()
        setHighlightedSession(session)
        guard isVisible, let session, let hostWindow else {
            previewPanel.hide()
            return
        }
        previewPanel.show(for: session,
                          title: session.name,
                          detail: detail(for: session),
                          parentFrame: panel.frame,
                          parentWindow: hostWindow)
    }

    private func selectedSession() -> PTYSession? {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node else {
            return nil
        }
        return node.session
    }

    // Move the colored overlay onto `session`'s real view (or remove it when
    // nil). No-op when the highlighted session is unchanged.
    private func setHighlightedSession(_ session: PTYSession?) {
        let newView = session?.view
        if newView === highlightedSessionView {
            return
        }
        highlightOverlay?.removeFromSuperview()
        highlightOverlay = nil
        highlightedSessionView = nil
        guard let view = newView else {
            return
        }
        let overlay = MentionHighlightOverlay(frame: view.bounds)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.selectedContentBackgroundColor
            .withAlphaComponent(0.30).cgColor
        overlay.autoresizingMask = [.width, .height]
        // SessionView forbids plain -addSubview:; this is its supported hook for
        // overlays (keeps the overlay above content but below the find bar).
        view.addSubview(belowFind: overlay)
        highlightOverlay = overlay
        highlightedSessionView = view
    }

    private func detail(for session: PTYSession) -> String {
        guard let tab = session.delegate as? PTYTab else { return "" }
        let windowTitle = tab.realParentWindow()?.window?.title ?? ""
        if windowTitle.isEmpty {
            return "Tab \(tab.objectCount)"
        }
        return "Tab \(tab.objectCount) · \(windowTitle)"
    }

    // MARK: - Actions

    @objc private func singleClicked() {
        refreshPreview()
    }

    @objc private func doubleClicked() {
        commitSelection()
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? Node else { return roots.count }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? Node else { return roots[index] }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return (item as? Node).map { !$0.children.isEmpty } ?? false
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return (item as? Node)?.isSelectable ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("MentionCell")
        let cell: MentionCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? MentionCellView {
            cell = reused
        } else {
            cell = MentionCellView()
            cell.identifier = identifier
        }
        // The cell is reused across node kinds, so the indentation, font, and
        // color must be reset on every pass — not just at creation — or a
        // recycled session cell keeps a header's metrics (and vice versa).
        cell.leadingConstraint.constant = node.isSelectable ? 18 : 2
        cell.textField?.stringValue = node.title
        if node.isSelectable {
            cell.textField?.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            cell.textField?.textColor = .labelColor
        } else {
            cell.textField?.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            cell.textField?.textColor = .secondaryLabelColor
        }
        return cell
    }
}

// One row of the mention outline. Holds its leading constraint so the
// indentation can be reconfigured when AppKit recycles the cell for a
// different node kind.
private final class MentionCellView: NSTableCellView {
    private(set) var leadingConstraint: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        textField = field
        leadingConstraint = field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2)
        NSLayoutConstraint.activate([
            leadingConstraint,
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
}

// A purely visual highlight that never intercepts mouse events, so the
// highlighted terminal session stays interactive beneath it.
private final class MentionHighlightOverlay: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
