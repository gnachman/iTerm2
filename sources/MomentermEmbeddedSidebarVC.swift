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
    /// Called when the user double-clicks a project and picks a mode.
    /// - Parameters:
    ///   - path:      The project's filesystem path
    ///   - spaceName: The name of the Space that owns this project (used for tab color)
    ///   - inNewTab:  true = open in new tab in current window; false = open in a new window
    func sidebarDidRequestOpenProject(path: String, spaceName: String, inNewTab: Bool)
}

// MARK: - SidebarItem

private enum SidebarItem {
    case space(MomentermProjectSpace)
    case project(MomentermProject, space: MomentermProjectSpace)
}

// MARK: - View Controller

@objc final class MomentermEmbeddedSidebarVC: NSViewController {

    @objc weak var sidebarDelegate: MomentermEmbeddedSidebarDelegate?

    private var store: MomentermProjectStore = MomentermProjectStorage.shared.load()
    private var filteredItems: [SidebarItem]?  // nil → full tree; non-nil → flat filtered list

    private var searchField: NSSearchField!
    private var addButton: NSButton!
    private var separator: NSBox!
    private var outlineView: NSOutlineView!
    private var scrollView: NSScrollView!
    /// Temporary strong reference to keep the path-picker trampoline alive during a modal alert.
    private var _retainedPathPicker: AnyObject?

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
    }

    // MARK: - Setup

    private func setupUI() {
        let w: CGFloat = 220

        // Search field — top left
        searchField = NSSearchField(frame: NSRect(x: 8, y: 0, width: w - 40, height: 22))
        searchField.autoresizingMask = [.width, .minYMargin]
        searchField.placeholderString = "검색..."
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.controlSize = .small
        view.addSubview(searchField)

        // "+" button — top right
        addButton = NSButton(frame: NSRect(x: w - 28, y: 1, width: 20, height: 20))
        addButton.autoresizingMask = [.minXMargin, .minYMargin]
        addButton.bezelStyle = .inline
        addButton.isBordered = false
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "새 Space")
        addButton.target = self
        addButton.action = #selector(addSpaceTapped)
        view.addSubview(addButton)

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

        outlineView = NSOutlineView()
        outlineView.style = .sourceList
        outlineView.rowHeight = 22
        outlineView.indentationPerLevel = 14
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(doubleClicked)

        let ctxMenu = NSMenu()
        ctxMenu.delegate = self
        outlineView.menu = ctxMenu

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarCol"))
        col.isEditable = false
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col

        scrollView.documentView = outlineView
        view.addSubview(scrollView)

        positionControls()
    }

    private func positionControls() {
        let h = view.bounds.height
        let w = view.bounds.width
        let topH: CGFloat = 30   // search bar height
        let sepH: CGFloat = 1
        searchField.frame = NSRect(x: 8, y: h - topH + 4, width: w - 40, height: 22)
        addButton.frame  = NSRect(x: w - 28, y: h - topH + 5, width: 20, height: 20)
        separator.frame  = NSRect(x: 0, y: h - topH - sepH, width: w, height: sepH)
        scrollView.frame = NSRect(x: 0, y: 0, width: w, height: h - topH - sepH)
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
        alert.messageText = "새 Space 만들기"
        alert.informativeText = "Space 이름을 입력하세요:"
        alert.addButton(withTitle: "만들기")
        alert.addButton(withTitle: "취소")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        tf.placeholderString = "Space 이름"
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
                                                         inNewTab: true)
        } else if response == .alertSecondButtonReturn {
            sidebarDelegate?.sidebarDidRequestOpenProject(path: project.path,
                                                         spaceName: space.name,
                                                         inNewTab: false)
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension MomentermEmbeddedSidebarVC: NSOutlineViewDataSource {

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
}

// MARK: - NSOutlineViewDelegate

extension MomentermEmbeddedSidebarVC: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let row = item as? SidebarItem else { return nil }
        switch row {
        case .space(let space):
            return makeCell(outlineView, text: space.name.uppercased(), symbol: "folder.fill",
                            isHeader: true, accent: false)
        case .project(let project, _):
            return makeCell(outlineView, text: project.name, symbol: "chevron.left.slash.chevron.right",
                            isHeader: false, accent: !project.pathExists)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let row = item as? SidebarItem, case .space = row else { return false }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let row = item as? SidebarItem else { return false }
        if case .space = row { return false }
        return true
    }

    private func makeCell(_ ov: NSOutlineView, text: String, symbol: String,
                          isHeader: Bool, accent: Bool) -> NSTableCellView {
        let id = NSUserInterfaceItemIdentifier(isHeader ? "MtSpaceCell" : "MtProjectCell")
        let cell = (ov.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = id
        cell.subviews.forEach { $0.removeFromSuperview() }

        // Leading icon — 16×16 for better readability
        let iconView = NSImageView(frame: NSRect(x: 2, y: 2, width: 16, height: 16))
        iconView.autoresizingMask = .height
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iconView.image = img
        }
        iconView.contentTintColor = isHeader ? .secondaryLabelColor
                                  : (accent ? .systemRed : .controlAccentColor)

        // Label — shifted right to give the larger icon room.
        // When showing a warning badge (accent), reserve 18px on the right for it.
        let labelX: CGFloat = 24
        let labelRightPad: CGFloat = accent ? 20 : 4
        let label = NSTextField(labelWithString: text)
        label.autoresizingMask = .width
        label.frame = NSRect(x: labelX, y: 3, width: max(0, cell.bounds.width - labelX - labelRightPad), height: 16)
        label.font = isHeader ? .systemFont(ofSize: 10, weight: .semibold) : .systemFont(ofSize: 12)
        label.textColor = isHeader ? .secondaryLabelColor : (accent ? .systemRed : .labelColor)
        label.lineBreakMode = .byTruncatingTail

        cell.addSubview(iconView)
        cell.addSubview(label)
        cell.textField = label

        // Warning badge for projects whose directory no longer exists
        if !isHeader && accent {
            let warnSize: CGFloat = 12
            let warnView = NSImageView(frame: NSRect(x: labelX, y: 3, width: warnSize, height: warnSize))
            warnView.autoresizingMask = [.minXMargin]
            if let warnImg = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "경로 없음") {
                warnView.image = warnImg
            }
            warnView.contentTintColor = .systemRed
            // Position warning to the right of the label
            warnView.frame = NSRect(x: cell.bounds.width - warnSize - 4, y: 3, width: warnSize, height: warnSize)
            cell.addSubview(warnView)
        }

        return cell
    }
}

// MARK: - NSMenuDelegate

extension MomentermEmbeddedSidebarVC: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let addItem = NSMenuItem(title: "새 Space 추가", action: #selector(addSpaceTapped), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)

        let row = outlineView.clickedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? SidebarItem else { return }

        menu.addItem(NSMenuItem.separator())
        switch item {
        case .space(let space):
            let createItem = NSMenuItem(title: "프로젝트 생성...",
                                        action: #selector(addProjectToSpace(_:)), keyEquivalent: "")
            createItem.representedObject = space
            createItem.target = self
            menu.addItem(createItem)

            let del = NSMenuItem(title: "\u{201C}\(space.name)\u{201D} 삭제",
                                 action: #selector(deleteSpace(_:)), keyEquivalent: "")
            del.representedObject = space
            del.target = self
            menu.addItem(del)
        case .project(let project, _):
            let del = NSMenuItem(title: "\u{201C}\(project.name)\u{201D} 제거",
                                 action: #selector(deleteProject(_:)), keyEquivalent: "")
            del.representedObject = project
            del.target = self
            menu.addItem(del)
        }
    }

    @objc private func addProjectToSpace(_ sender: NSMenuItem) {
        guard let space = sender.representedObject as? MomentermProjectSpace else { return }

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
        aiLabel.frame = NSRect(x: 0, y: 0, width: 260, height: 16)
        aiLabel.font = .systemFont(ofSize: 11)
        aiLabel.textColor = .secondaryLabelColor

        let aiPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        aiPopup.addItems(withTitles: ["Claude Code", "Codex", "없음"])

        // Manual frame layout (no Auto Layout — CLAUDE.md rule applies across all windows)
        // Layout bottom-up: y=0 is bottom of accessory view
        let w: CGFloat = 260
        aiPopup.frame    = NSRect(x: 0, y: 0,   width: w, height: 24)
        aiLabel.frame    = NSRect(x: 0, y: 28,  width: w, height: 16)
        pathRow.frame    = NSRect(x: 0, y: 52,  width: w, height: 24)
        pathLabel.frame  = NSRect(x: 0, y: 80,  width: w, height: 16)
        nameField.frame  = NSRect(x: 0, y: 100, width: w, height: 24)
        nameLabel.frame  = NSRect(x: 0, y: 128, width: w, height: 16)

        let accessoryH: CGFloat = 144
        let stack = NSView(frame: NSRect(x: 0, y: 0, width: w, height: accessoryH))
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
            return
        }
        _retainedPathPicker = nil

        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let aiTool: MomentermAITool
        switch aiPopup.indexOfSelectedItem {
        case 0: aiTool = .claudeCode
        case 1: aiTool = .codex
        default: aiTool = .none
        }

        let project = MomentermProject(name: name, path: selectedPath, aiTool: aiTool)
        MomentermProjectStorage.shared.addProject(project, toSpace: space.id)
        reloadData()
    }

    @objc private func deleteSpace(_ sender: NSMenuItem) {
        guard let space = sender.representedObject as? MomentermProjectSpace else { return }
        var s = MomentermProjectStorage.shared.load()
        s.spaces.removeAll { $0.id == space.id }
        MomentermProjectStorage.shared.save(s)
        reloadData()
    }

    @objc private func deleteProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? MomentermProject else { return }
        var s = MomentermProjectStorage.shared.load()
        for i in s.spaces.indices {
            s.spaces[i].projects.removeAll { $0.id == project.id }
        }
        MomentermProjectStorage.shared.save(s)
        reloadData()
    }
}
