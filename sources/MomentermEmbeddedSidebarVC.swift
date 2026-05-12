//
//  MomentermEmbeddedSidebarVC.swift
//  iTerm2
//
//  Created by MomenTerm on 2026-04-19.
//  Embedded left-sidebar for the terminal window.
//  Rules: no Auto Layout, no fatalError, no NSUserDefaults (use iTermUserDefaults).

import AppKit

// MARK: - Delegate

@objc protocol MomentermEmbeddedSidebarDelegate: AnyObject {
    /// Called when the user opens a project from the sidebar.
    func sidebarDidRequestOpenProject(path: String, spaceName: String, projectName: String, inNewTab: Bool, aiCommand: String?)
    /// Called when the user requests the file tree panel for a project.
    func sidebarDidRequestShowFileTree(path: String, projectName: String)
}

// MARK: - WorkspaceCellView (hover "+" button)

private final class WorkspaceCellView: NSTableCellView {
    private(set) var addBtn: NSButton!
    private var trackArea: NSTrackingArea?
    var addAction: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        addBtn = NSButton()
        addBtn.isBordered = false
        addBtn.imagePosition = .imageOnly
        addBtn.image = NSImage(systemSymbolName: "plus.circle",
                               accessibilityDescription: "프로젝트 추가")
        addBtn.contentTintColor = .tertiaryLabelColor
        addBtn.target = self
        addBtn.action = #selector(addTapped)
        addBtn.alphaValue = 0
        addSubview(addBtn)
    }
    required init?(coder: NSCoder) { it_fatalError("init(coder:) not supported") }

    @objc private func addTapped() { addAction?() }

    func positionAddButton() {
        let s: CGFloat = 14
        addBtn.frame = NSRect(x: bounds.width - s - 4, y: (bounds.height - s) / 2.0, width: s, height: s)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackArea { removeTrackingArea(ta); trackArea = nil }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                owner: self, userInfo: nil)
        trackArea = ta
        addTrackingArea(ta)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.addBtn.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.addBtn.animator().alphaValue = 0
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        addBtn.alphaValue = 0
        addAction = nil
    }
}

// MARK: - DropOverlayView (custom, high-visibility drop indicator)

/// Transparent overlay drawn above the outline view during a sidebar drag.
/// Shows a soft workspace highlight and a subtle insertion line. Kept very
/// low-contrast on purpose — the built-in gap indicator is invisible for
/// empty workspaces and flickers when `setDropItem` remaps, so the overlay
/// exists solely to give the user a quiet, consistent visual anchor.
private final class DropOverlayView: NSView {
    struct Guide {
        /// Line rect in this overlay's (flipped) coordinate space.
        let lineRect: NSRect
        /// Workspace header rect (in this overlay's coords) to highlight, or nil.
        let workspaceRect: NSRect?
    }

    var guide: Guide? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let g = guide else { return }
        let accent = NSColor.controlAccentColor

        if let ws = g.workspaceRect {
            let p = NSBezierPath(roundedRect: ws.insetBy(dx: 2, dy: 1),
                                 xRadius: 5, yRadius: 5)
            accent.withAlphaComponent(0.08).setFill()
            p.fill()
            accent.withAlphaComponent(0.22).setStroke()
            p.lineWidth = 1
            p.stroke()
        }

        let line = g.lineRect
        accent.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: line,
                     xRadius: line.height / 2.0,
                     yRadius: line.height / 2.0).fill()
    }
}

// MARK: - MtSidebarOutlineView (hooks drag lifecycle to clear overlay)

private final class MtSidebarOutlineView: NSOutlineView {
    var dragStateDidClear: (() -> Void)?

    // NOTE: `draggingExited`, `draggingEnded`, and `concludeDragOperation` are
    // *optional* `NSDraggingDestination` methods with no default implementation
    // on NSView/NSTableView. Calling `super` on any of them forwards all the
    // way to NSObject's default handler, which crashes with an unrecognized
    // selector ("Trace/BPT trap: 5"). Override-only; DO NOT call super.

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragStateDidClear?()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        dragStateDidClear?()
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dragStateDidClear?()
    }
}

// MARK: - SidebarItem

private enum SidebarItem {
    case space(MomentermProjectSpace)
    case project(MomentermProject, space: MomentermProjectSpace)
}

// MARK: - DropTarget (shared computation result for validate + accept)

private struct DropTarget {
    let destSpaceId: String
    let destSpaceName: String
    let insertIndex: Int
    let aboveName: String?
    let belowName: String?
    /// Item/childIndex values to pass to NSOutlineView.setDropItem.
    let dropItem: Any
    let dropChildIndex: Int
    /// Line rect in OUTLINE VIEW coordinates (flipped).
    let lineRectInOutline: NSRect
    /// Workspace header rect in OUTLINE VIEW coordinates (flipped).
    let workspaceRectInOutline: NSRect?
}

// MARK: - View Controller

@objc final class MomentermEmbeddedSidebarVC: NSViewController {

    @objc weak var sidebarDelegate: MomentermEmbeddedSidebarDelegate?

    private var store: MomentermProjectStore = MomentermProjectStorage.shared.load()
    private var filteredItems: [SidebarItem]?  // nil → full tree; non-nil → flat filtered list

    private var searchField: NSSearchField!
    private var addButton: NSButton!
    private var settingsButton: NSButton!
    private var separator: NSBox!
    private var outlineView: MtSidebarOutlineView!
    private var scrollView: NSScrollView!
    private var dropOverlay: DropOverlayView!
    private var keyMonitor: Any?
    /// Temporary strong reference to keep the path-picker trampoline alive during a modal alert.
    private var _retainedPathPicker: AnyObject?

    /// Temporary strong reference for the AI tool picker trampoline.
    private var _retainedAITrampoline: AIToolPickerTrampoline?

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 400))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        setupUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)

        // Cmd+Opt+O → 세부 파일보기
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])
            if mods == [.command, .option],
               event.charactersIgnoringModifiers?.lowercased() == "o" {
                self.openFileTreeForSelectedOrActiveProject()
                return nil
            }
            return event
        }
    }

    deinit {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Setup

    private func setupUI() {
        let w: CGFloat = 220

        // Search field — top left
        searchField = NSSearchField(frame: NSRect(x: 8, y: 0, width: w - 64, height: 22))
        searchField.autoresizingMask = [.width, .minYMargin]
        searchField.placeholderString = "검색..."
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.controlSize = .small
        view.addSubview(searchField)

        // "+" button — second from right
        addButton = NSButton(frame: NSRect(x: w - 50, y: 1, width: 20, height: 20))
        addButton.autoresizingMask = [.minXMargin, .minYMargin]
        addButton.bezelStyle = .inline
        addButton.isBordered = false
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "새 Workspace")
        addButton.target = self
        addButton.action = #selector(addSpaceTapped)
        view.addSubview(addButton)

        // Settings gear — rightmost
        settingsButton = NSButton(frame: NSRect(x: w - 26, y: 2, width: 18, height: 18))
        settingsButton.autoresizingMask = [.minXMargin, .minYMargin]
        settingsButton.isBordered = false
        settingsButton.imagePosition = .imageOnly
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "설정")
        settingsButton.contentTintColor = .secondaryLabelColor
        settingsButton.target = self
        settingsButton.action = #selector(settingsTapped)
        view.addSubview(settingsButton)

        // Separator between search bar and list
        separator = NSBox(frame: NSRect(x: 0, y: 0, width: w, height: 1))
        separator.boxType = .separator
        separator.autoresizingMask = [.width, .minYMargin]
        view.addSubview(separator)

        // Scroll view below the top bar
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: w, height: 400 - 28))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        outlineView = MtSidebarOutlineView()
        outlineView.style = .sourceList
        outlineView.rowHeight = 22
        outlineView.indentationPerLevel = 12
        outlineView.intercellSpacing = NSSize(width: 0, height: 2)
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(doubleClicked)
        outlineView.dragStateDidClear = { [weak self] in
            self?.dropOverlay?.guide = nil
        }

        let ctxMenu = NSMenu()
        ctxMenu.delegate = self
        outlineView.menu = ctxMenu

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarCol"))
        col.isEditable = false
        col.minWidth = 100
        col.width = w - 4
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineView.registerForDraggedTypes([MomentermEmbeddedSidebarVC.projectDragType])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        // We draw our own indicator; disable the built-in one so the two don't fight.
        outlineView.draggingDestinationFeedbackStyle = .none

        scrollView.documentView = outlineView
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        view.addSubview(scrollView)

        // Transparent overlay that sits on top of the scroll view and draws the
        // drop line + workspace highlight + label during a drag. Because it
        // hit-tests through, NSOutlineView still receives the drag events.
        dropOverlay = DropOverlayView(frame: scrollView.frame)
        dropOverlay.autoresizingMask = [.width, .height]
        view.addSubview(dropOverlay, positioned: .above, relativeTo: scrollView)

        positionControls()
    }

    private func positionControls() {
        let h = view.bounds.height
        let w = view.bounds.width
        let topH: CGFloat = 36   // search bar height — matches file tree kHeaderH
        let sepH: CGFloat = 1
        searchField.frame    = NSRect(x: 8, y: h - topH + 7, width: w - 64, height: 22)
        addButton.frame      = NSRect(x: w - 50, y: h - topH + 8, width: 20, height: 20)
        settingsButton.frame = NSRect(x: w - 26, y: h - topH + 9, width: 18, height: 18)
        separator.frame      = NSRect(x: 0, y: h - topH - sepH, width: w, height: sepH)
        scrollView.frame     = NSRect(x: 0, y: 0, width: w, height: h - topH - sepH)
        dropOverlay?.frame   = scrollView.frame
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        positionControls()
    }

    // MARK: - Data

    @objc func reloadData() {
        store = MomentermProjectStorage.shared.load()
        applyFilter(query: searchField?.stringValue ?? "")
    }

    /// Selects the sidebar row whose project path matches `path`.
    /// Called from PseudoTerminal when the active tab changes.
    @objc func selectProjectForPath(_ path: String) {
        guard !path.isEmpty, filteredItems == nil else { return }
        let resolved = (path as NSString).resolvingSymlinksInPath
        for row in 0..<outlineView.numberOfRows {
            guard let item = outlineView.item(atRow: row) as? SidebarItem,
                  case .project(let project, _) = item else { continue }
            let projResolved = (project.path as NSString).resolvingSymlinksInPath
            if projResolved == resolved {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
                return
            }
        }
        // No match — clear selection so stale highlight doesn't mislead
        outlineView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
    }

    private func applyFilter(query: String) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            filteredItems = nil
            outlineView.reloadData()
            outlineView.expandItem(nil, expandChildren: true)
            return
        }
        var results: [SidebarItem] = []
        for space in store.spaces {
            if space.name.lowercased().contains(q) {
                results.append(.space(space))
            }
            for project in space.projects where project.name.lowercased().contains(q) {
                results.append(.project(project, space: space))
            }
        }
        filteredItems = results
        outlineView.reloadData()
    }

    // MARK: - Actions

    @objc private func searchChanged(_ sender: NSSearchField) {
        applyFilter(query: sender.stringValue)
    }

    @objc private func addSpaceTapped() {
        let alert = NSAlert()
        alert.messageText = "새 Workspace 만들기"
        alert.informativeText = "Workspace 이름을 입력하세요:"
        alert.addButton(withTitle: "만들기")
        alert.addButton(withTitle: "취소")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        tf.placeholderString = "Workspace 이름"
        alert.accessoryView = tf
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = tf.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Handle storage here; no need to bounce through the delegate
        _ = MomentermProjectStorage.shared.addSpace(named: name)
        reloadData()
    }

    @objc private func doubleClicked() {
        let row = outlineView.clickedRow
        guard row >= 0 else { return }

        let item: SidebarItem?
        if let filtered = filteredItems {
            guard row < filtered.count else { return }
            item = filtered[row]
        } else {
            item = outlineView.item(atRow: row) as? SidebarItem
        }
        guard let item = item, case .project(let project, let space) = item else { return }

        let alert = NSAlert()
        alert.messageText = "\u{201C}\(project.name)\u{201D} 열기"
        alert.addButton(withTitle: "새 탭")
        alert.addButton(withTitle: "새 창")
        alert.addButton(withTitle: "취소")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            sidebarDelegate?.sidebarDidRequestOpenProject(path: project.path,
                                                         spaceName: space.name,
                                                         projectName: project.name,
                                                         inNewTab: true,
                                                         aiCommand: nil)
        } else if response == .alertSecondButtonReturn {
            sidebarDelegate?.sidebarDidRequestOpenProject(path: project.path,
                                                         spaceName: space.name,
                                                         projectName: project.name,
                                                         inNewTab: false,
                                                         aiCommand: nil)
        }
    }

    // MARK: - Settings Popover and Menu

    @objc private func settingsTapped() {
        let menu = NSMenu()

        let shortcutsItem = NSMenuItem(title: "키보드 단축키...", action: #selector(showShortcutsPopover), keyEquivalent: "")
        shortcutsItem.target = self
        menu.addItem(shortcutsItem)

        menu.addItem(NSMenuItem.separator())

        let passkeyTitle = MomentermPasskeyManager.shared.isPasskeySet ? "패스키 변경/해제..." : "패스키 설정..."
        let passkeyItem = NSMenuItem(title: passkeyTitle, action: #selector(managePasskey), keyEquivalent: "")
        passkeyItem.target = self
        menu.addItem(passkeyItem)

        let btnFrame = settingsButton.convert(settingsButton.bounds, to: nil)
        menu.popUp(positioning: menu.items[0], at: NSPoint(x: btnFrame.minX, y: btnFrame.minY), in: settingsButton.window?.contentView)
    }

    @objc private func showShortcutsPopover() {
        let popover = NSPopover()
        popover.behavior = .transient

        let sections: [(title: String, items: [(key: String, desc: String)])] = [
            ("탭/창 관리", [
                ("⌘T",    "새 탭"),
                ("⌘D",    "창 수직 분할"),
                ("⇧⌘D",  "창 수평 분할"),
                ("⌘←/→", "탭 이동 (또는 ⌘1-9)"),
                ("⌘[/]",  "분할 화면 간 이동"),
            ]),
            ("화면 조작", [
                ("⌘K",   "화면 지우기 (버퍼 초기화)"),
                ("⌘↩",  "전체 화면 전환"),
                ("⌘W",   "탭 닫기"),
            ]),
            ("MomenTerm", [
                ("⌘⌥O", "세부 파일보기"),
            ]),
            ("유용한 팁", [
                ("⌘⌥I", "모든 분할 화면 동시 입력"),
            ]),
        ]

        let w: CGFloat = 290
        let pad: CGFloat = 10
        let rowH: CGFloat = 20
        let hdrH: CGFloat = 18
        let secGap: CGFloat = 6
        let keyW: CGFloat = 52

        // Pre-compute total height
        var totalH: CGFloat = pad * 2
        for (i, sec) in sections.enumerated() {
            totalH += hdrH + CGFloat(sec.items.count) * rowH
            if i < sections.count - 1 { totalH += secGap }
        }

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: w, height: totalH))
        var curY: CGFloat = totalH - pad   // layout top-down

        for (i, sec) in sections.enumerated() {
            curY -= hdrH
            let hdrLbl = NSTextField(labelWithString: sec.title.uppercased())
            hdrLbl.font = .systemFont(ofSize: 9, weight: .semibold)
            hdrLbl.textColor = .tertiaryLabelColor
            hdrLbl.frame = NSRect(x: pad, y: curY, width: w - pad * 2, height: hdrH - 2)
            contentView.addSubview(hdrLbl)

            for item in sec.items {
                curY -= rowH
                let keyLbl = NSTextField(labelWithString: item.key)
                keyLbl.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
                keyLbl.textColor = .secondaryLabelColor
                keyLbl.alignment = .right
                keyLbl.frame = NSRect(x: pad, y: curY, width: keyW, height: rowH - 2)
                contentView.addSubview(keyLbl)

                let descLbl = NSTextField(labelWithString: item.desc)
                descLbl.font = .systemFont(ofSize: 11)
                descLbl.frame = NSRect(x: pad + keyW + 8, y: curY,
                                       width: w - pad * 2 - keyW - 8, height: rowH - 2)
                contentView.addSubview(descLbl)
            }

            if i < sections.count - 1 { curY -= secGap }
        }

        let vc = NSViewController()
        vc.view = contentView
        popover.contentViewController = vc
        popover.contentSize = contentView.frame.size
        popover.show(relativeTo: settingsButton.bounds, of: settingsButton, preferredEdge: .maxY)
    }

    @objc private func managePasskey() {
        if MomentermPasskeyManager.shared.isPasskeySet {
            let alert = NSAlert()
            alert.messageText = "패스키 관리"
            alert.addButton(withTitle: "패스키 변경")
            alert.addButton(withTitle: "패스키 해제")
            alert.addButton(withTitle: "취소")
            let r = alert.runModal()
            if r == .alertFirstButtonReturn {
                promptSetPasskey(isChange: true)
            } else if r == .alertSecondButtonReturn {
                MomentermPasskeyManager.shared.clearPasskey()
            }
        } else {
            promptSetPasskey(isChange: false)
        }
    }

    private func promptSetPasskey(isChange: Bool) {
        let alert = NSAlert()
        alert.messageText = isChange ? "패스키 변경" : "새 패스키 설정"
        alert.informativeText = "4자리 이상 입력하세요:"
        alert.addButton(withTitle: "설정")
        alert.addButton(withTitle: "취소")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let val = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard val.count >= 4 else {
            let err = NSAlert()
            err.messageText = "너무 짧습니다. 4자리 이상 입력하세요."
            err.runModal()
            return
        }
        MomentermPasskeyManager.shared.setPasskey(val)
    }

    // MARK: - File Tree Helper (Cmd+Opt+O)

    private func openFileTreeForSelectedOrActiveProject() {
        let row = outlineView.selectedRow
        guard row >= 0 else { return }
        let sidebarItem: SidebarItem?
        if let filtered = filteredItems {
            guard row < filtered.count else { return }
            sidebarItem = filtered[row]
        } else {
            sidebarItem = outlineView.item(atRow: row) as? SidebarItem
        }
        guard let sidebarItem, case .project(let project, _) = sidebarItem else { return }
        sidebarDelegate?.sidebarDidRequestShowFileTree(path: project.path, projectName: project.name)
    }
}

// MARK: - NSOutlineViewDataSource

extension MomentermEmbeddedSidebarVC: NSOutlineViewDataSource {

    static let projectDragType = NSPasteboard.PasteboardType("com.momenterm.sidebar.project")

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let filtered = filteredItems {
            return item == nil ? filtered.count : 0
        }
        if item == nil { return store.spaces.count }
        if let row = item as? SidebarItem, case .space(let s) = row { return s.projects.count }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let filtered = filteredItems {
            return filtered[index]
        }
        if item == nil { return SidebarItem.space(store.spaces[index]) }
        guard let row = item as? SidebarItem, case .space(let s) = row else {
            it_fatalError("Unexpected nil children in embedded sidebar")
        }
        return SidebarItem.project(s.projects[index], space: s)
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if filteredItems != nil { return false }
        guard let row = item as? SidebarItem, case .space(let s) = row else { return false }
        return !s.projects.isEmpty
    }

    // MARK: Drag-and-drop reordering

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard filteredItems == nil,
              let row = item as? SidebarItem,
              case .project(let project, let space) = row else { return nil }
        let pb = NSPasteboardItem()
        pb.setString("\(space.id)|\(project.id)", forType: Self.projectDragType)
        return pb
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard filteredItems == nil,
              info.draggingPasteboard.string(forType: Self.projectDragType) != nil else {
            dropOverlay?.guide = nil
            return []
        }

        guard let target = computeDropTarget(info: info,
                                             proposedItem: item,
                                             proposedIndex: index) else {
            dropOverlay?.guide = nil
            return []
        }

        // Make sure our accept call-back and indicator point to the same slot.
        outlineView.setDropItem(target.dropItem, dropChildIndex: target.dropChildIndex)

        // Translate geometry from outline-view coords into the overlay's coords
        // so the rect stays correct even when the list has scrolled.
        let lineInOverlay = dropOverlay.convert(target.lineRectInOutline, from: outlineView)
        let wsInOverlay = target.workspaceRectInOutline.map {
            dropOverlay.convert($0, from: outlineView)
        }
        dropOverlay.guide = DropOverlayView.Guide(lineRect: lineInOverlay,
                                                  workspaceRect: wsInOverlay)
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                     item: Any?, childIndex index: Int) -> Bool {
        defer { dropOverlay?.guide = nil }
        guard filteredItems == nil,
              let token = info.draggingPasteboard.string(forType: Self.projectDragType) else {
            return false
        }

        // Re-derive the destination from the same helper used for the guide so
        // what-you-see is exactly what-you-get.
        guard let target = computeDropTarget(info: info,
                                             proposedItem: item,
                                             proposedIndex: index) else { return false }

        let parts = token.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let (srcSpaceId, projectId) = (parts[0], parts[1])

        var s = MomentermProjectStorage.shared.load()
        guard let srcIdx = s.spaces.firstIndex(where: { $0.id == srcSpaceId }),
              let projIdx = s.spaces[srcIdx].projects.firstIndex(where: { $0.id == projectId }),
              let destIdx = s.spaces.firstIndex(where: { $0.id == target.destSpaceId })
        else { return false }

        let project = s.spaces[srcIdx].projects.remove(at: projIdx)

        // `insertIndex` is the intended insertion point in the PRE-REMOVAL array.
        // For same-space moves, the remove shifts indices above it down by 1 —
        // adjust BEFORE clamping so a first→last move doesn't land at the wrong slot.
        var insertAt = target.insertIndex
        if srcIdx == destIdx && projIdx < insertAt {
            insertAt -= 1
        }
        insertAt = min(max(0, insertAt), s.spaces[destIdx].projects.count)
        s.spaces[destIdx].projects.insert(project, at: insertAt)
        MomentermProjectStorage.shared.save(s)
        reloadData()
        return true
    }

    // MARK: Drop target computation (shared by validate + accept)

    /// Resolves a dragging cursor position into a concrete (workspace, insertion
    /// index) plus the rects needed to render the overlay. Returns nil when the
    /// drag is not over any valid drop location.
    fileprivate func computeDropTarget(info: NSDraggingInfo,
                                       proposedItem item: Any?,
                                       proposedIndex index: Int) -> DropTarget? {
        guard filteredItems == nil else { return nil }
        let localPt = outlineView.convert(info.draggingLocation, from: nil)

        // NOTE on item identity: NSOutlineView caches `id` pointers returned from
        // `child:ofItem:`. When Swift bridges our `SidebarItem` enum to `id`, each
        // bridge creates a fresh `_SwiftValue`. `row(forItem:)`/`parent(forItem:)`
        // look up items via `isEqual:`, and since our enum's associated values
        // (MomentermProject/Space structs) aren't Equatable, lookup of a *fresh*
        // box fails silently (returns -1 / nil). To keep identity intact we only
        // ever pass `item` (the original AppKit-provided Any) or items obtained
        // from `outlineView.item(atRow:)` back into NSOutlineView APIs.
        var destSpace: MomentermProjectSpace?
        var destSpaceItem: Any?
        var insertIndex: Int = -1

        if let rawItem = item, let si = rawItem as? SidebarItem {
            switch si {
            case .space(let space):
                destSpace = space
                destSpaceItem = rawItem
                if index >= 0 {
                    insertIndex = index
                } else {
                    let r = outlineView.row(forItem: rawItem)
                    if r >= 0 {
                        let rect = outlineView.rect(ofRow: r)
                        insertIndex = (localPt.y < rect.midY) ? 0 : space.projects.count
                    } else {
                        insertIndex = space.projects.count
                    }
                }
            case .project(let project, let space):
                guard let projIdx = space.projects.firstIndex(where: { $0.id == project.id })
                else { return nil }
                let r = outlineView.row(forItem: rawItem)
                guard r >= 0 else { return nil }
                // Resolve the parent space by id via numberOfRows rather than
                // parent(forItem:), which depends on item-identity equality.
                var parentRef: Any?
                for row in stride(from: r - 1, through: 0, by: -1) {
                    if let cached = outlineView.item(atRow: row),
                       let csi = cached as? SidebarItem,
                       case .space(let cs) = csi, cs.id == space.id {
                        parentRef = cached
                        break
                    }
                }
                guard let parent = parentRef else { return nil }
                let rect = outlineView.rect(ofRow: r)
                destSpace = space
                destSpaceItem = parent
                insertIndex = (localPt.y < rect.midY) ? projIdx : (projIdx + 1)
            }
        } else {
            // Dead zone between/after all rows — append to nearest workspace above.
            let cursorRow = outlineView.row(at: localPt)
            let searchFrom = cursorRow >= 0 ? cursorRow : outlineView.numberOfRows - 1
            guard searchFrom >= 0 else { return nil }
            for row in stride(from: searchFrom, through: 0, by: -1) {
                if let cached = outlineView.item(atRow: row),
                   let si = cached as? SidebarItem,
                   case .space(let space) = si {
                    destSpace = space
                    destSpaceItem = cached
                    insertIndex = space.projects.count
                    break
                }
            }
        }

        guard let space = destSpace,
              let spaceItem = destSpaceItem,
              insertIndex >= 0 else { return nil }

        // Expand the workspace so we can measure child row rects.
        if !outlineView.isItemExpanded(spaceItem) {
            outlineView.expandItem(spaceItem)
        }

        let spaceRow = outlineView.row(forItem: spaceItem)
        let workspaceRect: NSRect? = spaceRow >= 0 ? outlineView.rect(ofRow: spaceRow) : nil

        let lineRect = indicatorRectInOutline(space: space,
                                              spaceRow: spaceRow,
                                              insertIndex: insertIndex)

        let aboveName: String? = (insertIndex > 0 && insertIndex <= space.projects.count)
            ? space.projects[insertIndex - 1].name : nil
        let belowName: String? = (insertIndex < space.projects.count)
            ? space.projects[insertIndex].name : nil

        return DropTarget(destSpaceId: space.id,
                          destSpaceName: space.name,
                          insertIndex: insertIndex,
                          aboveName: aboveName,
                          belowName: belowName,
                          dropItem: spaceItem,
                          dropChildIndex: insertIndex,
                          lineRectInOutline: lineRect,
                          workspaceRectInOutline: workspaceRect)
    }

    /// Compute the drop line rect in outline-view (flipped) coordinates.
    private func indicatorRectInOutline(space: MomentermProjectSpace,
                                        spaceRow: Int,
                                        insertIndex: Int) -> NSRect {
        let thickness: CGFloat = 3
        let inset: CGFloat = 6
        let width = max(outlineView.bounds.width - inset * 2, 0)
        let x = inset

        // Spaces are rendered as single rows; their projects, when expanded,
        // occupy the rows immediately below (spaceRow+1 ... spaceRow+count).
        if space.projects.isEmpty || spaceRow < 0 {
            // Just below the space header.
            if spaceRow >= 0 {
                let sr = outlineView.rect(ofRow: spaceRow)
                return NSRect(x: x, y: sr.maxY - thickness / 2.0,
                              width: width, height: thickness)
            }
            return NSRect(x: x, y: 0, width: width, height: thickness)
        }

        let firstProjRow = spaceRow + 1
        if insertIndex <= 0 {
            let r = outlineView.rect(ofRow: firstProjRow)
            return NSRect(x: x, y: r.minY - thickness / 2.0,
                          width: width, height: thickness)
        }

        let aboveRow = firstProjRow + insertIndex - 1
        let safeRow = min(aboveRow, outlineView.numberOfRows - 1)
        let r = outlineView.rect(ofRow: safeRow)
        return NSRect(x: x, y: r.maxY - thickness / 2.0,
                      width: width, height: thickness)
    }

}

// MARK: - Drag-drop source lifecycle (clear overlay if user cancels the drag)

extension MomentermEmbeddedSidebarVC {
    // NSOutlineViewDataSource optional — called by AppKit when our drag ends.
    // Objective-C exposure is automatic because the extension conforms via the
    // earlier extension's data-source conformance.
    func outlineView(_ outlineView: NSOutlineView,
                     draggingSession session: NSDraggingSession,
                     endedAt screenPoint: NSPoint,
                     operation: NSDragOperation) {
        dropOverlay?.guide = nil
    }
}

// MARK: - NSOutlineViewDelegate

extension MomentermEmbeddedSidebarVC: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let row = item as? SidebarItem else { return nil }
        switch row {
        case .space(let space):
            return makeCell(outlineView, text: space.name.uppercased(), symbol: "folder.fill",
                            isHeader: true, accent: false, aiTool: nil,
                            addProjectHandler: { [weak self] in self?.addProjectToSpaceCore(space) })
        case .project(let project, _):
            return makeCell(outlineView, text: project.name, symbol: "chevron.left.slash.chevron.right",
                            isHeader: false, accent: !project.pathExists,
                            aiTool: project.aiTool, localBackend: project.localLLMBackend)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let row = item as? SidebarItem else { return false }
        if case .space = row { return false }
        return true
    }

    private func makeCell(_ ov: NSOutlineView, text: String, symbol: String,
                          isHeader: Bool, accent: Bool,
                          aiTool: MomentermAITool? = nil,
                          localBackend: MomentermLocalLLMBackend? = nil,
                          addProjectHandler: (() -> Void)? = nil) -> NSTableCellView {
        let id = NSUserInterfaceItemIdentifier(isHeader ? "MtSpaceCell" : "MtProjectCell")
        let cellW = max(ov.bounds.width, 220)
        let cell: NSTableCellView
        if isHeader {
            if let reused = ov.makeView(withIdentifier: id, owner: nil) as? WorkspaceCellView {
                cell = reused
            } else {
                cell = WorkspaceCellView(frame: NSRect(x: 0, y: 0, width: cellW, height: 24))
            }
            // Remove all subviews except the built-in addBtn
            cell.subviews.filter { $0 !== (cell as? WorkspaceCellView)?.addBtn }.forEach { $0.removeFromSuperview() }
        } else {
            if let reused = ov.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.frame = NSRect(x: 0, y: 0, width: cellW, height: 24)
            }
            cell.subviews.forEach { $0.removeFromSuperview() }
        }
        cell.identifier = id

        // Leading icon
        let iconView = NSImageView(frame: NSRect(x: 4, y: 4, width: 16, height: 16))
        iconView.autoresizingMask = []
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iconView.image = img
        }
        iconView.contentTintColor = isHeader ? .secondaryLabelColor
                                  : (accent ? .systemRed : .controlAccentColor)
        cell.addSubview(iconView)

        // Label — project cells reserve 38px right for folder + AI badge
        let labelX: CGFloat = 24
        let labelRightPad: CGFloat = isHeader ? 20 : 38
        let label = NSTextField(labelWithString: text)
        label.autoresizingMask = .width
        label.frame = NSRect(x: labelX, y: 4, width: max(0, cell.bounds.width - labelX - labelRightPad), height: 16)
        label.font = isHeader ? .systemFont(ofSize: 10, weight: .semibold) : .systemFont(ofSize: 12)
        label.textColor = isHeader ? .secondaryLabelColor : (accent ? .systemRed : .labelColor)
        label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label)
        cell.textField = label

        if isHeader {
            // Wire up the hover "+" button for workspace rows
            if let wc = cell as? WorkspaceCellView {
                wc.positionAddButton()
                wc.addAction = addProjectHandler
            }
            return cell
        }

        // ── Project cell right-side badges ────────────────────────────
        // Layout (right-to-left): [folder] [AI/warning]
        let badgeSize: CGFloat = 14
        let folderX = cell.bounds.width - badgeSize - 4  // Folder icon (rightmost)
        let aiX = folderX - badgeSize - 4                 // AI/warning badge (left of folder)

        // Folder icon — always shown, opens file tree (rightmost)
        let folderBtn = NSButton(frame: NSRect(x: folderX, y: 5, width: badgeSize, height: badgeSize))
        folderBtn.autoresizingMask = [.minXMargin]
        folderBtn.isBordered = false
        folderBtn.imagePosition = .imageOnly
        folderBtn.imageScaling = .scaleProportionallyUpOrDown
        let folderCfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        if let img = NSImage(systemSymbolName: "folder", accessibilityDescription: "파일 보기")?
                .withSymbolConfiguration(folderCfg) {
            folderBtn.image = img
        }
        folderBtn.contentTintColor = .tertiaryLabelColor
        folderBtn.target = self
        folderBtn.action = #selector(folderIconClicked(_:))
        cell.addSubview(folderBtn)

        // Left badge: warning takes priority over AI icon
        if accent {
            let warnView = NSImageView(frame: NSRect(x: aiX, y: 5, width: badgeSize, height: badgeSize))
            warnView.autoresizingMask = [.minXMargin]
            warnView.imageScaling = .scaleProportionallyUpOrDown
            warnView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            if let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "경로 없음") {
                warnView.image = img
            }
            warnView.contentTintColor = .systemRed
            cell.addSubview(warnView)
        } else if let tool = aiTool {
            let spec = AIIconSpec.spec(for: tool, localBackend: localBackend)
            let aiBtn = NSButton(frame: NSRect(x: aiX, y: 5, width: badgeSize, height: badgeSize))
            aiBtn.autoresizingMask = [.minXMargin]
            aiBtn.isBordered = false
            aiBtn.imagePosition = .imageOnly
            aiBtn.imageScaling = .scaleProportionallyUpOrDown
            if let assetName = spec.assetName, let asset = NSImage(named: assetName) {
                aiBtn.image = asset
                aiBtn.contentTintColor = nil  // brand asset is multi-color; do not tint
            } else {
                let symConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                aiBtn.image = NSImage(systemSymbolName: spec.symbolName, accessibilityDescription: nil)?
                    .withSymbolConfiguration(symConfig)
                aiBtn.contentTintColor = spec.tint
            }
            aiBtn.target = self
            aiBtn.action = #selector(aiIconClicked(_:))
            cell.addSubview(aiBtn)
        }

        return cell
    }

    /// Handles taps on the per-project AI tool icon.
    /// Asks the user to confirm closing the default terminal, then opens with AI command.
    @objc private func aiIconClicked(_ sender: NSButton) {
        // Walk up to the enclosing NSTableCellView to find the row index.
        var view: NSView? = sender
        while let v = view, !(v is NSTableCellView) { view = v.superview }
        guard let cellView = view else { return }
        let row = outlineView.row(for: cellView)
        guard row >= 0 else { return }

        let sidebarItem: SidebarItem?
        if let filtered = filteredItems {
            guard row < filtered.count else { return }
            sidebarItem = filtered[row]
        } else {
            sidebarItem = outlineView.item(atRow: row) as? SidebarItem
        }
        guard let sidebarItem, case .project(let project, let space) = sidebarItem else { return }

        sidebarDelegate?.sidebarDidRequestOpenProject(
            path: project.path,
            spaceName: space.name,
            projectName: project.name,
            inNewTab: true,
            aiCommand: project.aiLaunchCommand
        )
    }

    /// Handles taps on the per-project folder icon — opens the file tree panel.
    @objc private func folderIconClicked(_ sender: NSButton) {
        var view: NSView? = sender
        while let v = view, !(v is NSTableCellView) { view = v.superview }
        guard let cellView = view else { return }
        let row = outlineView.row(for: cellView)
        guard row >= 0 else { return }

        let sidebarItem: SidebarItem?
        if let filtered = filteredItems {
            guard row < filtered.count else { return }
            sidebarItem = filtered[row]
        } else {
            sidebarItem = outlineView.item(atRow: row) as? SidebarItem
        }
        guard let sidebarItem, case .project(let project, _) = sidebarItem else { return }
        sidebarDelegate?.sidebarDidRequestShowFileTree(path: project.path, projectName: project.name)
    }
}

// MARK: - NSMenuDelegate

extension MomentermEmbeddedSidebarVC: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let row = outlineView.clickedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? SidebarItem else { return }

        switch item {
        case .space(let space):
            let createItem = NSMenuItem(title: "프로젝트 생성",
                                        action: #selector(addProjectToSpace(_:)), keyEquivalent: "")
            createItem.representedObject = space
            createItem.target = self
            menu.addItem(createItem)

            let renameItem = NSMenuItem(title: "이름 변경",
                                        action: #selector(renameSpace(_:)), keyEquivalent: "")
            renameItem.representedObject = space
            renameItem.target = self
            menu.addItem(renameItem)

            menu.addItem(NSMenuItem.separator())
            let del = NSMenuItem(title: "\u{201C}\(space.name)\u{201D} 삭제",
                                 action: #selector(deleteSpace(_:)), keyEquivalent: "")
            del.representedObject = space
            del.target = self
            menu.addItem(del)

        case .project(let project, _):
            let edit = NSMenuItem(title: "편집", action: #selector(editProject(_:)), keyEquivalent: "")
            edit.representedObject = project
            edit.target = self
            menu.addItem(edit)

            let dup = NSMenuItem(title: "복제", action: #selector(duplicateProject(_:)), keyEquivalent: "")
            dup.representedObject = project
            dup.target = self
            menu.addItem(dup)

            let fileTree = NSMenuItem(title: "세부 파일보기", action: #selector(showFileTree(_:)), keyEquivalent: "")
            fileTree.representedObject = project
            fileTree.target = self
            menu.addItem(fileTree)

            menu.addItem(NSMenuItem.separator())
            let del = NSMenuItem(title: "\u{201C}\(project.name)\u{201D} 삭제",
                                 action: #selector(deleteProject(_:)), keyEquivalent: "")
            del.representedObject = project
            del.target = self
            menu.addItem(del)
        }
    }

    @objc private func addProjectToSpace(_ sender: NSMenuItem) {
        guard let space = sender.representedObject as? MomentermProjectSpace else { return }
        addProjectToSpaceCore(space)
    }

    private func addProjectToSpaceCore(_ space: MomentermProjectSpace) {

        // Build accessory view: name field + path selector + AI tool picker
        var selectedPath: String = ""

        let nameLabel = NSTextField(labelWithString: "프로젝트 이름")
        nameLabel.frame = NSRect(x: 0, y: 0, width: 260, height: 16)
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = .secondaryLabelColor

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        nameField.placeholderString = "예: MyApp"

        let pathLabel = NSTextField(labelWithString: "프로젝트 경로")
        pathLabel.frame = NSRect(x: 0, y: 0, width: 260, height: 16)
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor

        let pathDisplay = NSTextField(labelWithString: "폴더를 선택하세요")
        pathDisplay.frame = NSRect(x: 0, y: 0, width: 200, height: 20)
        pathDisplay.textColor = .secondaryLabelColor
        pathDisplay.lineBreakMode = .byTruncatingMiddle

        let pathButton = NSButton(frame: NSRect(x: 0, y: 0, width: 90, height: 24))
        pathButton.title = "폴더 선택..."
        pathButton.bezelStyle = .rounded

        let pathRow = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        pathDisplay.frame = NSRect(x: 0, y: 2, width: 164, height: 20)
        pathButton.frame = NSRect(x: 168, y: 0, width: 92, height: 24)
        pathRow.addSubview(pathDisplay)
        pathRow.addSubview(pathButton)

        let aiLabel = NSTextField(labelWithString: "AI 도구")
        aiLabel.font = .systemFont(ofSize: 11)
        aiLabel.textColor = .secondaryLabelColor

        let aiPopup = NSPopUpButton()
        aiPopup.addItems(withTitles: AIToolPickerTrampoline.items)

        let statusLabel = NSTextField(labelWithString: "로컬 LLM 감지 중…")
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let modelLabel = NSTextField(labelWithString: "모델")
        modelLabel.font = .systemFont(ofSize: 11)
        modelLabel.textColor = .secondaryLabelColor

        let modelPopup = NSPopUpButton()
        modelPopup.addItem(withTitle: "감지 대기 중…")
        modelPopup.isEnabled = false

        let trampoline = AIToolPickerTrampoline(aiPopup: aiPopup, modelPopup: modelPopup, statusLabel: statusLabel)
        _retainedAITrampoline = trampoline
        trampoline.detect()

        // Manual frame layout (no Auto Layout — CLAUDE.md rule applies across all windows)
        // Layout bottom-up: y=0 is bottom of accessory view
        let w: CGFloat = 260
        modelPopup.frame  = NSRect(x: 0, y: 0,   width: w, height: 24)
        modelLabel.frame  = NSRect(x: 0, y: 28,  width: w, height: 16)
        statusLabel.frame = NSRect(x: 0, y: 48,  width: w, height: 14)
        aiPopup.frame     = NSRect(x: 0, y: 68,  width: w, height: 24)
        aiLabel.frame     = NSRect(x: 0, y: 96,  width: w, height: 16)
        pathRow.frame     = NSRect(x: 0, y: 120, width: w, height: 24)
        pathLabel.frame   = NSRect(x: 0, y: 148, width: w, height: 16)
        nameField.frame   = NSRect(x: 0, y: 168, width: w, height: 24)
        nameLabel.frame   = NSRect(x: 0, y: 196, width: w, height: 16)

        let accessoryH: CGFloat = 212
        let stack = NSView(frame: NSRect(x: 0, y: 0, width: w, height: accessoryH))
        stack.addSubview(modelPopup)
        stack.addSubview(modelLabel)
        stack.addSubview(statusLabel)
        stack.addSubview(aiPopup)
        stack.addSubview(aiLabel)
        stack.addSubview(pathRow)
        stack.addSubview(pathLabel)
        stack.addSubview(nameField)
        stack.addSubview(nameLabel)

        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "선택"

        let pathDisplayRef = pathDisplay
        let alert = NSAlert()
        alert.messageText = "\u{201C}\(space.name)\u{201D}에 프로젝트 추가"
        alert.addButton(withTitle: "추가")
        alert.addButton(withTitle: "취소")
        alert.accessoryView = stack

        // NSAlert runs a nested event loop; use a trampoline NSObject so the path button
        // can open NSOpenPanel from within the running modal loop.
        final class PathPickerTarget: NSObject {
            var handler: () -> Void = {}
            @objc func pick(_ sender: Any) { handler() }
        }
        let picker = PathPickerTarget()
        picker.handler = {
            if openPanel.runModal() == .OK, let url = openPanel.url {
                selectedPath = url.path
                pathDisplayRef.stringValue = (url.path as NSString).abbreviatingWithTildeInPath
                pathDisplayRef.textColor = .labelColor
            }
        }
        pathButton.target = picker
        pathButton.action = #selector(PathPickerTarget.pick(_:))

        // Keep picker alive during the modal loop via a stored property
        _retainedPathPicker = picker

        guard alert.runModal() == .alertFirstButtonReturn else {
            _retainedPathPicker = nil
            _retainedAITrampoline = nil
            return
        }
        _retainedPathPicker = nil

        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            _retainedAITrampoline = nil
            return
        }

        let aiTool = trampoline.selectedTool()
        let backend = trampoline.selectedBackend()
        let model = trampoline.selectedModel()
        _retainedAITrampoline = nil

        var project = MomentermProject(name: name, path: selectedPath, aiTool: aiTool)
        project.localLLMBackend = backend
        project.localLLMModel = model
        MomentermProjectStorage.shared.addProject(project, toSpace: space.id)
        reloadData()
    }

    @objc private func deleteSpace(_ sender: NSMenuItem) {
        guard let space = sender.representedObject as? MomentermProjectSpace else { return }
        let alert = NSAlert()
        alert.messageText = "\u{201C}\(space.name)\u{201D} 삭제"
        alert.informativeText = "이 Workspace와 모든 프로젝트 항목이 제거됩니다. 실제 파일은 삭제되지 않습니다."
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var s = MomentermProjectStorage.shared.load()
        s.spaces.removeAll { $0.id == space.id }
        MomentermProjectStorage.shared.save(s)
        reloadData()
    }

    @objc private func deleteProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? MomentermProject else { return }
        let confirm = NSAlert()
        confirm.messageText = "\u{201C}\(project.name)\u{201D}을(를) 삭제하시겠습니까?"
        confirm.informativeText = "삭제된 프로젝트는 복구할 수 없습니다."
        confirm.addButton(withTitle: "삭제")
        confirm.addButton(withTitle: "취소")
        confirm.buttons[0].hasDestructiveAction = true
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        var s = MomentermProjectStorage.shared.load()
        for i in s.spaces.indices {
            s.spaces[i].projects.removeAll { $0.id == project.id }
        }
        MomentermProjectStorage.shared.save(s)
        reloadData()
    }

    @objc private func editProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? MomentermProject else { return }

        var selectedPath: String = project.path

        let nameLabel = NSTextField(labelWithString: "프로젝트 이름")
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = .secondaryLabelColor

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        nameField.stringValue = project.name

        let pathLabel = NSTextField(labelWithString: "프로젝트 경로")
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor

        let pathDisplay = NSTextField(labelWithString: project.displayPath)
        pathDisplay.textColor = .labelColor
        pathDisplay.lineBreakMode = .byTruncatingMiddle

        let pathButton = NSButton(frame: NSRect(x: 0, y: 0, width: 90, height: 24))
        pathButton.title = "폴더 선택..."
        pathButton.bezelStyle = .rounded

        let pathRow = NSView()
        pathDisplay.frame = NSRect(x: 0, y: 2, width: 164, height: 20)
        pathButton.frame  = NSRect(x: 168, y: 0, width: 92, height: 24)
        pathRow.addSubview(pathDisplay)
        pathRow.addSubview(pathButton)

        let aiLabel = NSTextField(labelWithString: "AI 도구")
        aiLabel.font = .systemFont(ofSize: 11)
        aiLabel.textColor = .secondaryLabelColor

        let aiPopup = NSPopUpButton()
        aiPopup.addItems(withTitles: AIToolPickerTrampoline.items)
        aiPopup.selectItem(at: AIToolPickerTrampoline.popupIndex(for: project.aiTool))

        let statusLabel = NSTextField(labelWithString: "로컬 LLM 감지 중…")
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let modelLabel = NSTextField(labelWithString: "모델")
        modelLabel.font = .systemFont(ofSize: 11)
        modelLabel.textColor = .secondaryLabelColor

        let modelPopup = NSPopUpButton()
        modelPopup.addItem(withTitle: "감지 대기 중…")
        modelPopup.isEnabled = false

        let trampoline = AIToolPickerTrampoline(aiPopup: aiPopup, modelPopup: modelPopup, statusLabel: statusLabel)
        _retainedAITrampoline = trampoline
        trampoline.detect(preselectModel: project.localLLMModel)

        let w: CGFloat = 260
        modelPopup.frame  = NSRect(x: 0, y: 0,   width: w, height: 24)
        modelLabel.frame  = NSRect(x: 0, y: 28,  width: w, height: 16)
        statusLabel.frame = NSRect(x: 0, y: 48,  width: w, height: 14)
        aiPopup.frame     = NSRect(x: 0, y: 68,  width: w, height: 24)
        aiLabel.frame     = NSRect(x: 0, y: 96,  width: w, height: 16)
        pathRow.frame     = NSRect(x: 0, y: 120, width: w, height: 24)
        pathLabel.frame   = NSRect(x: 0, y: 148, width: w, height: 16)
        nameField.frame   = NSRect(x: 0, y: 168, width: w, height: 24)
        nameLabel.frame   = NSRect(x: 0, y: 196, width: w, height: 16)

        let stack = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 212))
        stack.addSubview(modelPopup)
        stack.addSubview(modelLabel)
        stack.addSubview(statusLabel)
        stack.addSubview(aiPopup)
        stack.addSubview(aiLabel)
        stack.addSubview(pathRow)
        stack.addSubview(pathLabel)
        stack.addSubview(nameField)
        stack.addSubview(nameLabel)

        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "선택"
        if !project.path.isEmpty {
            openPanel.directoryURL = URL(fileURLWithPath: project.path)
        }

        let pathDisplayRef = pathDisplay
        final class PathPickerTarget: NSObject {
            var handler: () -> Void = {}
            @objc func pick(_ sender: Any) { handler() }
        }
        let picker = PathPickerTarget()
        picker.handler = {
            if openPanel.runModal() == .OK, let url = openPanel.url {
                selectedPath = url.path
                pathDisplayRef.stringValue = (url.path as NSString).abbreviatingWithTildeInPath
            }
        }
        pathButton.target = picker
        pathButton.action = #selector(PathPickerTarget.pick(_:))
        _retainedPathPicker = picker

        let alert = NSAlert()
        alert.messageText = "\u{201C}\(project.name)\u{201D} 편집"
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "취소")
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else {
            _retainedPathPicker = nil
            _retainedAITrampoline = nil
            return
        }
        _retainedPathPicker = nil

        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            _retainedAITrampoline = nil
            return
        }

        let aiTool = trampoline.selectedTool()
        let backend = trampoline.selectedBackend()
        let model = trampoline.selectedModel()
        _retainedAITrampoline = nil

        var s = MomentermProjectStorage.shared.load()
        for i in s.spaces.indices {
            if let j = s.spaces[i].projects.firstIndex(where: { $0.id == project.id }) {
                s.spaces[i].projects[j].name = name
                s.spaces[i].projects[j].path = selectedPath
                s.spaces[i].projects[j].aiTool = aiTool
                s.spaces[i].projects[j].localLLMBackend = backend
                s.spaces[i].projects[j].localLLMModel = model
                break
            }
        }
        MomentermProjectStorage.shared.save(s)
        reloadData()
    }

    @objc private func renameSpace(_ sender: NSMenuItem) {
        guard let space = sender.representedObject as? MomentermProjectSpace else { return }

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        nameField.stringValue = space.name

        let alert = NSAlert()
        alert.messageText = "\u{201C}\(space.name)\u{201D} 이름 변경"
        alert.addButton(withTitle: "변경")
        alert.addButton(withTitle: "취소")
        alert.accessoryView = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != space.name else { return }

        var s = MomentermProjectStorage.shared.load()
        if let i = s.spaces.firstIndex(where: { $0.id == space.id }) {
            s.spaces[i].name = newName
        }
        MomentermProjectStorage.shared.save(s)
        reloadData()
    }

    @objc private func duplicateProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? MomentermProject else { return }
        var s = MomentermProjectStorage.shared.load()
        for i in s.spaces.indices {
            if let j = s.spaces[i].projects.firstIndex(where: { $0.id == project.id }) {
                var copy = project
                copy.id = UUID().uuidString
                copy.name = project.name + " (복사됨)"
                s.spaces[i].projects.insert(copy, at: j + 1)
                break
            }
        }
        MomentermProjectStorage.shared.save(s)
        reloadData()
    }

    @objc private func showFileTree(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? MomentermProject else { return }
        sidebarDelegate?.sidebarDidRequestShowFileTree(path: project.path, projectName: project.name)
    }
}

// MARK: - AI Tool Picker Trampoline

/// Wires the AI tool NSPopUpButton to a local-LLM detection flow.
/// Owns the model picker and status label; updates them as detection completes
/// and as the user changes the AI tool selection.
fileprivate final class AIToolPickerTrampoline: NSObject {
    let aiPopup: NSPopUpButton
    let modelPopup: NSPopUpButton
    let statusLabel: NSTextField
    private var detected: MomentermLocalLLMStatus = .unavailable

    /// Map popup index → tool. Keep this aligned with the popup item order below.
    static let items = ["Claude Code", "Codex", "Gemini", "Local LLM", "없음"]

    init(aiPopup: NSPopUpButton, modelPopup: NSPopUpButton, statusLabel: NSTextField) {
        self.aiPopup = aiPopup
        self.modelPopup = modelPopup
        self.statusLabel = statusLabel
        super.init()
        aiPopup.target = self
        aiPopup.action = #selector(toolChanged(_:))
    }

    @objc func toolChanged(_ sender: Any) { applyEnablement() }

    func applyEnablement() {
        let isLocal = (aiPopup.indexOfSelectedItem == 3)
        modelPopup.isEnabled = isLocal && detected.isAvailable
        if isLocal {
            statusLabel.textColor = detected.isAvailable ? .systemGreen : .systemOrange
        } else {
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    func detect(preselectModel: String? = nil) {
        statusLabel.stringValue = "로컬 LLM 감지 중…"
        MomentermLocalLLMDetector.detect { [weak self] status in
            guard let self else { return }
            self.detected = status
            self.modelPopup.removeAllItems()
            if status.isAvailable {
                if status.models.isEmpty {
                    self.modelPopup.addItem(withTitle: "(설치된 모델 없음)")
                } else {
                    self.modelPopup.addItems(withTitles: status.models)
                    if let preselect = preselectModel, status.models.contains(preselect) {
                        self.modelPopup.selectItem(withTitle: preselect)
                    }
                }
                self.statusLabel.stringValue = "\(status.backend.displayName) 감지됨 · 모델 \(status.models.count)개"
            } else {
                self.modelPopup.addItem(withTitle: "감지된 LLM 없음")
                self.statusLabel.stringValue = "로컬 LLM 미감지 — Ollama(ollama serve) 또는 LM Studio 실행 필요"
            }
            self.applyEnablement()
        }
    }

    func selectedTool() -> MomentermAITool {
        switch aiPopup.indexOfSelectedItem {
        case 0: return .claudeCode
        case 1: return .codex
        case 2: return .gemini
        case 3: return .localLLM
        default: return .none
        }
    }

    func selectedBackend() -> MomentermLocalLLMBackend? {
        return selectedTool() == .localLLM ? detected.backend : nil
    }

    func selectedModel() -> String? {
        guard selectedTool() == .localLLM, modelPopup.isEnabled,
              let title = modelPopup.titleOfSelectedItem,
              !title.hasPrefix("(") && title != "감지된 LLM 없음" else { return nil }
        return title
    }

    /// Pre-selects popup based on a tool, used by edit form.
    static func popupIndex(for tool: MomentermAITool) -> Int {
        switch tool {
        case .claudeCode, .both: return 0
        case .codex:             return 1
        case .gemini:            return 2
        case .localLLM:          return 3
        case .none:              return 4
        }
    }
}

// MARK: - AI Tool Icon Mapping

private struct AIIconSpec {
    let assetName: String?     // brand PNG in MomentermAssets.xcassets, or nil
    let symbolName: String     // SF Symbol fallback
    let tint: NSColor          // applied only when SF Symbol is used

    static func spec(for tool: MomentermAITool, localBackend: MomentermLocalLLMBackend? = nil) -> AIIconSpec {
        switch tool {
        case .claudeCode:
            return AIIconSpec(assetName: "ai-claude-code",
                              symbolName: "sparkles",
                              tint: .systemOrange)
        case .codex:
            return AIIconSpec(assetName: "ai-codex",
                              symbolName: "chevron.left.slash.chevron.right",
                              tint: .labelColor)
        case .gemini:
            return AIIconSpec(assetName: "ai-gemini",
                              symbolName: "sparkle",
                              tint: .systemBlue)
        case .localLLM:
            switch localBackend {
            case .some(.ollama):
                return AIIconSpec(assetName: "ai-ollama",
                                  symbolName: "cpu",
                                  tint: .systemPurple)
            case .some(.lmStudio):
                return AIIconSpec(assetName: "ai-lmstudio",
                                  symbolName: "cpu",
                                  tint: .systemPurple)
            case .some(.none), nil:
                return AIIconSpec(assetName: nil,
                                  symbolName: "cpu",
                                  tint: .systemPurple)
            }
        case .both:
            return AIIconSpec(assetName: nil,
                              symbolName: "square.stack.3d.up.fill",
                              tint: .controlAccentColor)
        case .none:
            return AIIconSpec(assetName: nil,
                              symbolName: "terminal.fill",
                              tint: .secondaryLabelColor)
        }
    }
}
