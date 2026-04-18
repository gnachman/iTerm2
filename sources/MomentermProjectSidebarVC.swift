//
//  MomentermProjectSidebarVC.swift
//  iTerm2
//
//  Created by MomenTerm on 2026-04-19.
//

import AppKit

// MARK: - Delegate

protocol MomentermProjectSidebarDelegate: AnyObject {
    func sidebarDidSelectProject(_ project: MomentermProject, inSpace space: MomentermProjectSpace)
    func sidebarDidSelectSpace(_ space: MomentermProjectSpace)
    func sidebarDidRequestAddSpace()
    func sidebarDidRequestAddProject(toSpace space: MomentermProjectSpace)
    func sidebarDidRequestOpenProject(_ project: MomentermProject, mode: MomentermOpenMode)
    func sidebarDidRequestDeleteProject(_ project: MomentermProject)
    func sidebarDidRequestDeleteSpace(_ space: MomentermProjectSpace)
}

enum MomentermOpenMode {
    case newTab
    case newWindow
}

// MARK: - Sidebar Item

private enum SidebarItem {
    case space(MomentermProjectSpace)
    case project(MomentermProject, space: MomentermProjectSpace)
}

// MARK: - View Controller

final class MomentermProjectSidebarVC: NSViewController {

    weak var delegate: MomentermProjectSidebarDelegate?

    private var store: MomentermProjectStore = MomentermProjectStorage.shared.load()
    private var outlineView: NSOutlineView!
    private var scrollView: NSScrollView!

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        setupOutlineView()
        setupToolbar()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadData()
    }

    // MARK: - Setup

    private func setupOutlineView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        outlineView = NSOutlineView()
        outlineView.style = .sourceList
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 16
        outlineView.allowsMultipleSelection = false
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(outlineViewDoubleClicked)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Main"))
        column.isEditable = false
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView
        view.addSubview(scrollView)

        // Bottom toolbar for Add buttons
        let toolbar = makeBottomToolbar()
        view.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 32),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
        ])
    }

    private func makeBottomToolbar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor

        let addSpaceBtn = makeIconButton(systemName: "folder.badge.plus", tooltip: "Add Space", action: #selector(addSpaceTapped))
        let addProjectBtn = makeIconButton(systemName: "plus", tooltip: "Add Project", action: #selector(addProjectTapped))

        bar.addSubview(addSpaceBtn)
        bar.addSubview(addProjectBtn)

        NSLayoutConstraint.activate([
            addSpaceBtn.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            addSpaceBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            addProjectBtn.leadingAnchor.constraint(equalTo: addSpaceBtn.trailingAnchor, constant: 4),
            addProjectBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func makeIconButton(systemName: String, tooltip: String, action: Selector) -> NSButton {
        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.toolTip = tooltip
        btn.target = self
        btn.action = action
        if let img = NSImage(systemSymbolName: systemName, accessibilityDescription: tooltip) {
            btn.image = img
        } else {
            btn.title = "+"
        }
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 22),
            btn.heightAnchor.constraint(equalToConstant: 22),
        ])
        return btn
    }

    private func setupToolbar() {
        // Handled inside setupOutlineView
    }

    // MARK: - Data

    func reloadData() {
        store = MomentermProjectStorage.shared.load()
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
    }

    // MARK: - Actions

    @objc private func addSpaceTapped() {
        delegate?.sidebarDidRequestAddSpace()
    }

    @objc private func addProjectTapped() {
        guard let row = selectedRow() else { return }
        switch row {
        case .space(let space):
            delegate?.sidebarDidRequestAddProject(toSpace: space)
        case .project(_, let space):
            delegate?.sidebarDidRequestAddProject(toSpace: space)
        }
    }

    @objc private func outlineViewDoubleClicked() {
        guard let row = selectedRow() else { return }
        if case .project(let project, _) = row {
            delegate?.sidebarDidRequestOpenProject(project, mode: .newTab)
        }
    }

    private func selectedRow() -> SidebarItem? {
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? SidebarItem
    }
}

// MARK: - NSOutlineViewDataSource

extension MomentermProjectSidebarVC: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return store.spaces.count
        }
        if let row = item as? SidebarItem, case .space(let space) = row {
            return space.projects.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return SidebarItem.space(store.spaces[index])
        }
        if let row = item as? SidebarItem, case .space(let space) = row {
            return SidebarItem.project(space.projects[index], space: space)
        }
        it_fatalError("Unexpected item in outline view")
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let row = item as? SidebarItem else { return false }
        if case .space(let space) = row {
            return !space.projects.isEmpty
        }
        return false
    }
}

// MARK: - NSOutlineViewDelegate

extension MomentermProjectSidebarVC: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let row = item as? SidebarItem else { return nil }
        switch row {
        case .space(let space):
            return makeCellView(outlineView, text: space.name.uppercased(), isHeader: true)
        case .project(let project, _):
            return makeCellView(outlineView, text: project.name, subtext: project.displayPath, isHeader: false, pathMissing: !project.pathExists)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let row = item as? SidebarItem else { return false }
        if case .space = row { return true }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let row = item as? SidebarItem else { return false }
        if case .space = row { return false }
        return true
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let row = selectedRow() else { return }
        switch row {
        case .space(let space):
            delegate?.sidebarDidSelectSpace(space)
        case .project(let project, let space):
            delegate?.sidebarDidSelectProject(project, inSpace: space)
        }
    }

    // MARK: - Context menu

    func outlineView(_ outlineView: NSOutlineView, menuFor item: Any?) -> NSMenu? {
        guard let row = item as? SidebarItem else { return nil }
        let menu = NSMenu()
        switch row {
        case .project(let project, _):
            let openTab = NSMenuItem(title: "Open in New Tab", action: #selector(openInNewTab(_:)), keyEquivalent: "")
            openTab.representedObject = project
            openTab.target = self
            let openWindow = NSMenuItem(title: "Open in New Window", action: #selector(openInNewWindow(_:)), keyEquivalent: "")
            openWindow.representedObject = project
            openWindow.target = self
            let delete = NSMenuItem(title: "Remove Project", action: #selector(deleteProject(_:)), keyEquivalent: "")
            delete.representedObject = project
            delete.target = self
            menu.addItem(openTab)
            menu.addItem(openWindow)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(delete)
        case .space(let space):
            let addProj = NSMenuItem(title: "Add Project to \u{201C}\(space.name)\u{201D}", action: #selector(addProjectToSpace(_:)), keyEquivalent: "")
            addProj.representedObject = space
            addProj.target = self
            let deleteSpace = NSMenuItem(title: "Delete Space", action: #selector(deleteSpace(_:)), keyEquivalent: "")
            deleteSpace.representedObject = space
            deleteSpace.target = self
            menu.addItem(addProj)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(deleteSpace)
        }
        return menu
    }

    @objc private func openInNewTab(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? MomentermProject else { return }
        delegate?.sidebarDidRequestOpenProject(project, mode: .newTab)
    }

    @objc private func openInNewWindow(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? MomentermProject else { return }
        delegate?.sidebarDidRequestOpenProject(project, mode: .newWindow)
    }

    @objc private func deleteProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? MomentermProject else { return }
        delegate?.sidebarDidRequestDeleteProject(project)
    }

    @objc private func addProjectToSpace(_ sender: NSMenuItem) {
        guard let space = sender.representedObject as? MomentermProjectSpace else { return }
        delegate?.sidebarDidRequestAddProject(toSpace: space)
    }

    @objc private func deleteSpace(_ sender: NSMenuItem) {
        guard let space = sender.representedObject as? MomentermProjectSpace else { return }
        delegate?.sidebarDidRequestDeleteSpace(space)
    }
}

// MARK: - Cell factory

private func makeCellView(
    _ outlineView: NSOutlineView,
    text: String,
    subtext: String? = nil,
    isHeader: Bool,
    pathMissing: Bool = false
) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier(isHeader ? "SpaceCell" : "ProjectCell")
    let cell = (outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView) ?? NSTableCellView()
    cell.identifier = identifier

    // Clear subviews
    cell.subviews.forEach { $0.removeFromSuperview() }

    let label = NSTextField(labelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = isHeader ? .systemFont(ofSize: 10, weight: .semibold) : .systemFont(ofSize: 12)
    label.textColor = isHeader ? .secondaryLabelColor : (pathMissing ? .systemRed : .labelColor)
    label.lineBreakMode = .byTruncatingTail

    cell.addSubview(label)
    cell.textField = label

    if let sub = subtext, !isHeader {
        let sublabel = NSTextField(labelWithString: sub)
        sublabel.translatesAutoresizingMaskIntoConstraints = false
        sublabel.font = .systemFont(ofSize: 10)
        sublabel.textColor = .tertiaryLabelColor
        sublabel.lineBreakMode = .byTruncatingMiddle
        cell.addSubview(sublabel)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 2),
            sublabel.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            sublabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            sublabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 1),
        ])
    } else {
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
    }

    return cell
}
