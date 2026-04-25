//
//  iTermWorkgroupDetailViewController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import AppKit

// One-per-settings-panel node wrapper so NSOutlineView can key on pointer
// identity. Rebuilt on every load — expansion state is not preserved
// across reloads in Phase 1.
private class WorkgroupSessionNode: NSObject {
    let sessionID: String
    var children: [WorkgroupSessionNode] = []

    init(sessionID: String) {
        self.sessionID = sessionID
    }
}

@objc(iTermWorkgroupDetailViewController)
class iTermWorkgroupDetailViewController: NSViewController {
    weak var parentEditor: iTermWorkgroupsEditingViewController?

    private var currentWorkgroup: iTermWorkgroup?
    private var rootNode: WorkgroupSessionNode?

    private var nameField: NSTextField!
    private var outlineScroll: NSScrollView!
    private var outlineView: NSOutlineView!
    private var visualView: WorkgroupVisualView!
    private var segmented: NSSegmentedControl!
    private var sessionDetailContainer: NSView!
    private var sessionDetailViewController: iTermWorkgroupSessionDetailViewController!
    private var emptyLabel: NSTextField!
    private var whatIsButton: NSButton!

    private let margin: CGFloat = 8
    private let rowHeight: CGFloat = 24

    private let segmentedHeight: CGFloat = 24

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))

        emptyLabel = NSTextField(labelWithString:
            "Select a workgroup on the left or click + to create one.")
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        root.addSubview(emptyLabel)

        whatIsButton = NSButton(title: "What is a Workgroup?",
                                target: self,
                                action: #selector(whatIsAWorkgroupClicked(_:)))
        whatIsButton.bezelStyle = .rounded
        whatIsButton.controlSize = .regular
        whatIsButton.sizeToFit()
        root.addSubview(whatIsButton)

        nameField = NSTextField(frame: .zero)
        nameField.placeholderString = "Workgroup name"
        nameField.delegate = self
        root.addSubview(nameField)

        segmented = NSSegmentedControl(
            images: [
                NSImage(named: NSImage.addTemplateName) ?? NSImage(),
                NSImage(named: NSImage.removeTemplateName) ?? NSImage(),
            ],
            trackingMode: .momentary,
            target: self,
            action: #selector(segmentClicked(_:)))
        segmented.segmentStyle = .smallSquare
        root.addSubview(segmented)

        outlineScroll = NSScrollView(frame: .zero)
        outlineScroll.hasVerticalScroller = true
        outlineScroll.borderType = .bezelBorder

        outlineView = NSOutlineView(frame: .zero)
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .default
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("node"))
        col.resizingMask = .autoresizingMask
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col
        outlineView.indentationPerLevel = 14
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineScroll.documentView = outlineView
        root.addSubview(outlineScroll)

        visualView = WorkgroupVisualView(frame: .zero)
        visualView.delegate = self
        root.addSubview(visualView)

        // The outline stays around as the canonical selection-holder
        // (add/remove/mode-switcher logic keys off it) but is not shown.
        outlineScroll.isHidden = true

        sessionDetailContainer = NSView(frame: .zero)
        root.addSubview(sessionDetailContainer)

        sessionDetailViewController = iTermWorkgroupSessionDetailViewController()
        sessionDetailViewController.parentDetail = self
        sessionDetailContainer.addSubview(sessionDetailViewController.view)

        self.view = root
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutAll()
    }

    private func layoutAll() {
        let bounds = view.bounds

        // Empty-state label centered when visible, with the explainer
        // button just below it.
        let emptySize = emptyLabel.fittingSize
        let buttonSize = whatIsButton.fittingSize
        let buttonGap: CGFloat = 8
        let stackHeight = emptySize.height + buttonGap + buttonSize.height
        let stackTop = bounds.midY + stackHeight / 2
        emptyLabel.frame = NSRect(x: 0,
                                  y: stackTop - emptySize.height,
                                  width: bounds.width,
                                  height: emptySize.height)
        whatIsButton.frame = NSRect(
            x: bounds.midX - buttonSize.width / 2,
            y: stackTop - emptySize.height - buttonGap - buttonSize.height,
            width: buttonSize.width,
            height: buttonSize.height)

        // Split the available width evenly between the visual column
        // and the session-detail column, with a single margin-sized gap
        // between them. The visual preview was cramped at a fixed 220pt;
        // making both columns equal gives it room to breathe.
        let leftPad: CGFloat = 0
        let columnGap = margin
        let columnWidth = max(0, (bounds.width - leftPad - columnGap) / 2)

        let nameHeight: CGFloat = 22
        let nameRowY = bounds.height - nameHeight
        nameField.frame = NSRect(
            x: leftPad,
            y: nameRowY,
            width: columnWidth,
            height: nameHeight)

        // Left column: segmented strip anchored to the bottom. Visual
        // view fills from the top of the segmented strip up to just
        // below the name field.
        let segmentedY: CGFloat = 0
        segmented.frame = NSRect(x: leftPad,
                                 y: segmentedY,
                                 width: 60,
                                 height: segmentedHeight)

        let nameToVisualGap: CGFloat = 4
        let visualY = segmentedY + segmentedHeight
        let visualRect = NSRect(
            x: leftPad,
            y: visualY,
            width: columnWidth,
            height: max(0, nameRowY - nameToVisualGap - visualY))
        visualView.frame = visualRect
        // Outline is off-screen; it's only used as a data model for
        // selection state.
        outlineScroll.frame = visualRect

        let detailX = leftPad + columnWidth + columnGap
        let detailWidth = max(0, bounds.width - detailX)
        sessionDetailContainer.frame = NSRect(
            x: detailX,
            y: 0,
            width: detailWidth,
            height: bounds.height)
        sessionDetailViewController.view.frame = sessionDetailContainer.bounds
    }

    // MARK: - Load

    func load(workgroup: iTermWorkgroup?) {
        // Remember what was selected before so edits that round-trip
        // through the model (which rebuilds this view) don't silently
        // kick the selection back to the root.
        let previousWorkgroupID = currentWorkgroup?.uniqueIdentifier
        let previousSelectedSessionID = selectedNode?.sessionID

        currentWorkgroup = workgroup
        if workgroup == nil {
            emptyLabel.isHidden = false
            whatIsButton.isHidden = false
            nameField.isHidden = true
            visualView.isHidden = true
            segmented.isHidden = true
            sessionDetailContainer.isHidden = true
            sessionDetailViewController.load(session: nil, in: nil)
            visualView.set(workgroup: nil, selectedSessionID: nil)
            return
        }
        emptyLabel.isHidden = true
        whatIsButton.isHidden = true
        nameField.isHidden = false
        visualView.isHidden = false
        segmented.isHidden = false
        sessionDetailContainer.isHidden = false

        // Don't stomp the user's edit-in-progress in the name field; only
        // overwrite it when a *different* workgroup is being shown.
        let isSameWorkgroup =
            previousWorkgroupID == workgroup?.uniqueIdentifier
        if !isSameWorkgroup {
            nameField.stringValue = workgroup?.name ?? ""
        }
        rebuildTree()
        outlineView.reloadData()
        outlineView.expandItem(rootNode, expandChildren: true)

        // Restore previous selection if still valid; otherwise select root.
        let restoreID: String?
        if isSameWorkgroup,
           let id = previousSelectedSessionID,
           workgroup?.session(withUniqueIdentifier: id) != nil {
            restoreID = id
        } else {
            restoreID = rootNode?.sessionID
        }
        if let id = restoreID,
           let row = outlineRow(forSessionID: id) {
            outlineView.selectRowIndexes(IndexSet(integer: row),
                                         byExtendingSelection: false)
        }
        updateSessionDetailForSelection()
        updateSegmentedEnabled()
        visualView.set(workgroup: workgroup,
                       selectedSessionID: selectedNode?.sessionID)
    }

    private func outlineRow(forSessionID sessionID: String) -> Int? {
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? WorkgroupSessionNode,
               node.sessionID == sessionID {
                return row
            }
        }
        return nil
    }

    private func rebuildTree() {
        guard let wg = currentWorkgroup, let root = wg.root else {
            rootNode = nil
            return
        }
        let rootNode = WorkgroupSessionNode(sessionID: root.uniqueIdentifier)
        var byID: [String: WorkgroupSessionNode] = [root.uniqueIdentifier: rootNode]
        for s in wg.sessions where s.parentID != nil {
            byID[s.uniqueIdentifier] = WorkgroupSessionNode(sessionID: s.uniqueIdentifier)
        }
        for s in wg.sessions where s.parentID != nil {
            guard let parentNode = byID[s.parentID!],
                  let childNode = byID[s.uniqueIdentifier] else { continue }
            parentNode.children.append(childNode)
        }
        self.rootNode = rootNode
    }

    // MARK: - Selection

    private var selectedNode: WorkgroupSessionNode? {
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? WorkgroupSessionNode
    }

    private var selectedSession: iTermWorkgroupSessionConfig? {
        guard let id = selectedNode?.sessionID else { return nil }
        return currentWorkgroup?.session(withUniqueIdentifier: id)
    }

    private func updateSessionDetailForSelection() {
        sessionDetailViewController.load(session: selectedSession,
                                         in: currentWorkgroup)
    }

    private func updateSegmentedEnabled() {
        let node = selectedNode
        let haveSelection = node != nil
        let isRoot = node?.sessionID == rootNode?.sessionID
        segmented.setEnabled(haveSelection, forSegment: 0)
        segmented.setEnabled(haveSelection && !isRoot, forSegment: 1)
    }

    // MARK: - + / − actions

    @objc private func whatIsAWorkgroupClicked(_ sender: NSButton) {
        let markdown = """
            A **Workgroup** transforms a single session into a group of
            related sessions that share a toolbar.

            When a Workgroup is entered on a session (called the **main
            session**) it can add:

            - **Peers**: multiple sessions or split panes in the a place of a single split pane. A mode
              switcher in the toolbar flips between them. Useful when you
              want to see different "modes" of the same context, like a
              terminal and a diff of your working tree.
            - **Split panes**: additional panes carved out of the main
              session's area, each configured with its own profile and
              command.
            - **Tabs**: whole new window tabs, attached to the main
              session's lifetime.

            Each session in the workgroup can be configured with its own
            profile, command or URL, and toolbar items.

            Configure Workgroups here, and enter one via a trigger on a
            profile or a menu item.
            """
        sender.it_showInformativeMessage(withMarkdown: markdown)
    }

    @objc private func segmentClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: showAddMenu()
        case 1: removeSelectedNode()
        default: break
        }
    }

    private func showAddMenu() {
        guard let selID = selectedNode?.sessionID else { return }
        let menu = NSMenu()
        // Disable AppKit's target-based auto-enable so our own
        // isEnabled flags aren't overridden right before display.
        menu.autoenablesItems = false
        let peer = menu.addItem(withTitle: "Add Peer",
                                action: #selector(addPeer),
                                keyEquivalent: "")
        peer.target = self
        let split = menu.addItem(withTitle: "Add Split",
                                 action: #selector(addSplit),
                                 keyEquivalent: "")
        split.target = self
        // No split from anywhere inside a peer group — that includes
        // both the host (ambiguous target) and the peers themselves.
        split.isEnabled = !sessionIsInPeerGroup(selID: selID)
        let tab = menu.addItem(withTitle: "Add Tab",
                               action: #selector(addTab),
                               keyEquivalent: "")
        tab.target = self

        let point = NSPoint(x: segmented.frame.minX,
                            y: segmented.frame.maxY + 2)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    private func sessionIsInPeerGroup(selID: String) -> Bool {
        guard let wg = currentWorkgroup else { return false }
        // It is itself a peer.
        if let s = wg.session(withUniqueIdentifier: selID),
           case .peer = s.kind {
            return true
        }
        // Or it has at least one peer child (it's a host).
        return wg.sessions.contains { child in
            guard child.parentID == selID else { return false }
            if case .peer = child.kind { return true }
            return false
        }
    }

    @objc private func addPeer() {
        // Peers cannot be direct children of peers — two peers of each
        // other share a "host" (a non-peer ancestor). If the user has a
        // peer selected, hoist the new peer up to that peer's host so the
        // two become siblings. Otherwise attach under the selected node.
        guard let selID = selectedNode?.sessionID,
              let wg = currentWorkgroup else { return }
        let parentID: String
        if let selSession = wg.session(withUniqueIdentifier: selID),
           case .peer = selSession.kind,
           let host = selSession.parentID {
            parentID = host
        } else {
            parentID = selID
        }
        addChild(kind: .peer,
                 displayName: WorkgroupAnimalNames.pick(taken: takenNames(in: wg)),
                 parentOverride: parentID)
    }

    // Every session in the workgroup that already has a non-empty
    // display name. Used to keep freshly-generated animal names unique.
    private func takenNames(in wg: iTermWorkgroup) -> Set<String> {
        return Set(wg.sessions.compactMap { s -> String? in
            return s.displayName.isEmpty ? nil : s.displayName
        })
    }

    @objc private func addSplit() {
        guard let wg = currentWorkgroup else { return }
        addChild(kind: .split(SplitSettings(
            orientation: .vertical,
            side: .trailingOrBottom,
            location: 0.5)),
                 displayName: WorkgroupAnimalNames.pick(taken: takenNames(in: wg)))
    }

    @objc private func addTab() {
        guard let wg = currentWorkgroup else { return }
        // Tabs always attach directly to the root — they represent new
        // window tabs, not further nesting under a split or peer.
        addChild(kind: .tab,
                 displayName: WorkgroupAnimalNames.pick(taken: takenNames(in: wg)),
                 parentOverride: rootNode?.sessionID)
    }

    private func addChild(kind: iTermWorkgroupSessionConfig.Kind,
                          displayName: String = "",
                          parentOverride: String? = nil) {
        guard var wg = currentWorkgroup,
              let parentID = parentOverride ?? selectedNode?.sessionID else { return }
        let newSession = iTermWorkgroupSessionConfig(
            uniqueIdentifier: UUID().uuidString,
            parentID: parentID,
            kind: kind,
            profileGUID: nil,
            command: "",
            urlString: "",
            toolbarItems: [],
            displayName: displayName)
        wg.sessions.append(newSession)
        enforceModeSwitcherInvariant(on: &wg)
        parentEditor?.replaceSelectedWorkgroup(wg, actionName: "Add Session")
        // Select the newly-added session so the user can configure it
        // straight away (and so the visual preview shows it).
        if let row = outlineRow(forSessionID: newSession.uniqueIdentifier) {
            outlineView.selectRowIndexes(IndexSet(integer: row),
                                         byExtendingSelection: false)
        }
    }

    private func removeSelectedNode() {
        guard var wg = currentWorkgroup,
              let id = selectedNode?.sessionID,
              id != rootNode?.sessionID else { return }
        // Remove the selected session and every descendant.
        var toDelete = Set<String>([id])
        var keepGoing = true
        while keepGoing {
            keepGoing = false
            for s in wg.sessions where !toDelete.contains(s.uniqueIdentifier) {
                if let parent = s.parentID, toDelete.contains(parent) {
                    toDelete.insert(s.uniqueIdentifier)
                    keepGoing = true
                }
            }
        }
        wg.sessions.removeAll { toDelete.contains($0.uniqueIdentifier) }
        enforceModeSwitcherInvariant(on: &wg)
        parentEditor?.replaceSelectedWorkgroup(wg, actionName: "Remove Session")
    }

    // Each "peer group" is a non-peer session (the host) plus every
    // peer-kind child of it. Every member of such a group needs the mode
    // switcher — without it on a given session, navigating back to the
    // rest of the group would be impossible once that session is active.
    // Sessions not in any peer group get the mode switcher stripped.
    private func enforceModeSwitcherInvariant(on wg: inout iTermWorkgroup) {
        var needSwitcher = Set<String>()
        for host in wg.sessions {
            if case .peer = host.kind { continue }  // peers don't host peers
            let peerChildren = wg.sessions.filter { child in
                guard child.parentID == host.uniqueIdentifier else { return false }
                if case .peer = child.kind { return true }
                return false
            }
            guard !peerChildren.isEmpty else { continue }
            needSwitcher.insert(host.uniqueIdentifier)
            for peer in peerChildren {
                needSwitcher.insert(peer.uniqueIdentifier)
            }
        }
        for i in wg.sessions.indices {
            let id = wg.sessions[i].uniqueIdentifier
            let hasMS = wg.sessions[i].toolbarItems.contains {
                $0.kind == .modeSwitcher
            }
            if needSwitcher.contains(id) && !hasMS {
                wg.sessions[i].toolbarItems.insert(.modeSwitcher, at: 0)
            } else if !needSwitcher.contains(id) && hasMS {
                wg.sessions[i].toolbarItems.removeAll {
                    $0.kind == .modeSwitcher
                }
            }
        }
    }

    // MARK: - Session detail callback

    // Called by the session detail VC when the user edits a session.
    func sessionDetail(_ sender: iTermWorkgroupSessionDetailViewController,
                       didUpdate session: iTermWorkgroupSessionConfig,
                       actionName: String) {
        guard var wg = currentWorkgroup,
              let idx = wg.sessions.firstIndex(where: {
                  $0.uniqueIdentifier == session.uniqueIdentifier
              }) else { return }
        wg.sessions[idx] = session
        enforceModeSwitcherInvariant(on: &wg)
        parentEditor?.replaceSelectedWorkgroup(wg, actionName: actionName)
    }
}

// MARK: - Name field

extension iTermWorkgroupDetailViewController: NSTextFieldDelegate {
    // Commit on every keystroke so the workgroups table on the left
    // reflects the name as the user types, rather than waiting for
    // focus loss.
    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSTextField === nameField,
              var wg = currentWorkgroup,
              wg.name != nameField.stringValue else { return }
        wg.name = nameField.stringValue
        parentEditor?.replaceSelectedWorkgroup(wg, actionName: "Rename Workgroup")
    }
}

// MARK: - NSOutlineView data source / delegate

extension iTermWorkgroupDetailViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView,
                     numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return rootNode == nil ? 0 : 1
        }
        return (item as? WorkgroupSessionNode)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView,
                     child index: Int,
                     ofItem item: Any?) -> Any {
        if item == nil {
            return rootNode as Any
        }
        return (item as! WorkgroupSessionNode).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView,
                     isItemExpandable item: Any) -> Bool {
        return !((item as? WorkgroupSessionNode)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("WorkgroupNodeCell")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier,
                                             owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let text = NSTextField(labelWithString: "")
            text.frame = NSRect(x: 0, y: 2, width: 200, height: 17)
            text.autoresizingMask = [.width]
            text.lineBreakMode = .byTruncatingTail
            cell.addSubview(text)
            cell.textField = text
        }
        if let node = item as? WorkgroupSessionNode,
           let session = currentWorkgroup?.session(withUniqueIdentifier: node.sessionID) {
            cell.textField?.stringValue = displayLabel(for: session)
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        updateSessionDetailForSelection()
        updateSegmentedEnabled()
        visualView.set(workgroup: currentWorkgroup,
                       selectedSessionID: selectedNode?.sessionID)
    }

    private func displayLabel(for session: iTermWorkgroupSessionConfig) -> String {
        switch session.kind {
        case .root:
            return "Main session"
        case .peer:
            return "Peer: \(session.displayName)"
        case .split(let s):
            let dir = s.orientation == .vertical ? "Vertical" : "Horizontal"
            let pct = Int((s.location * 100).rounded())
            return "Split: \(dir) \(pct)%"
        case .tab:
            return "Tab"
        }
    }
}

// MARK: - WorkgroupVisualViewDelegate

extension iTermWorkgroupDetailViewController: WorkgroupVisualViewDelegate {
    func visualView(_ view: WorkgroupVisualView,
                    didSelectSessionID sessionID: String) {
        // Route the click through the outline so all existing selection-
        // driven logic (session detail refresh, +/- enabled states) runs
        // the same way regardless of which mode is active.
        guard let row = outlineRow(forSessionID: sessionID) else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row),
                                     byExtendingSelection: false)
    }

    func visualView(_ view: WorkgroupVisualView,
                    didDragSplit sessionID: String,
                    location: Double) {
        sessionDetailViewController.syncSplitLocation(
            location, forSessionID: sessionID)
    }

    func visualView(_ view: WorkgroupVisualView,
                    didFinishDraggingSplit sessionID: String,
                    location: Double) {
        guard var wg = currentWorkgroup,
              var s = wg.session(withUniqueIdentifier: sessionID),
              case .split(var settings) = s.kind else { return }
        settings.location = location
        s.kind = .split(settings)
        guard let idx = wg.sessions.firstIndex(where: {
            $0.uniqueIdentifier == sessionID
        }) else { return }
        wg.sessions[idx] = s
        parentEditor?.replaceSelectedWorkgroup(wg,
                                               actionName: "Change Split Location")
    }
}
