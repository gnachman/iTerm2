// iTermProjectsPanelController.swift
// iTerm2
//
// Panel UI for per-window project archives.
// Layout: split view — left: project tree (NSOutlineView),
//                       right: open windows list (NSTableView).
// Hover over any row shows a preview popover.

import AppKit

// MARK: - Sort Order

enum ProjectSortOrder { case name, recent }

// MARK: - Outline View Item Wrapper

/// NSObject box so archived windows can serve as NSOutlineView items.
final class iTermArchivedWindowBox: NSObject {
    let window: iTermArchivedWindow
    let project: iTermWindowProject
    init(_ window: iTermArchivedWindow, project: iTermWindowProject) {
        self.window = window
        self.project = project
    }
}

// MARK: - Panel Window Controller

@objc final class iTermProjectsPanelController: NSWindowController, NSWindowDelegate {

    @objc static let shared: iTermProjectsPanelController = {
        iTermProjectsPanelController()
    }()

    private var splitVC: iTermProjectsSplitViewController!

    private convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable,
                        .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: true)
        panel.title = "Window Projects"
        panel.minSize = NSSize(width: 600, height: 380)
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        self.init(window: panel)
        panel.delegate = self
        let svc = iTermProjectsSplitViewController()
        splitVC = svc
        panel.contentViewController = svc
    }

    @objc func showPanel() {
        if !(window?.isVisible ?? false) {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        splitVC.reloadAll()
    }
}

// MARK: - Split View Controller

final class iTermProjectsSplitViewController: NSSplitViewController {
    let projectsVC = iTermProjectsOutlineController()
    let windowsVC  = iTermOpenWindowsController()

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .paneSplitter

        projectsVC.onSelectionChange = { [weak self] in
            self?.windowsVC.updateArchiveButton()
        }
        windowsVC.projectsController = projectsVC

        let left  = NSSplitViewItem(viewController: projectsVC)
        left.minimumThickness  = 220
        left.maximumThickness  = 480
        left.preferredThicknessFraction = 0.42

        let right = NSSplitViewItem(viewController: windowsVC)
        right.minimumThickness = 240

        addSplitViewItem(left)
        addSplitViewItem(right)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        splitView.setPosition(360, ofDividerAt: 0)
    }

    func reloadAll() {
        projectsVC.reload()
        windowsVC.reload()
    }
}

// MARK: - Projects Outline Controller

final class iTermProjectsOutlineController: NSViewController,
                                             NSOutlineViewDataSource,
                                             NSOutlineViewDelegate {
    var onSelectionChange: (() -> Void)?

    private(set) var outlineView = NSOutlineView()
    private var scrollView = NSScrollView()
    private var addProjectButton   = NSButton()
    private var addSubprojectButton = NSButton()
    private var deleteButton       = NSButton()
    private var restoreButton      = NSButton()
    private var restoreAllButton   = NSButton()

    private var sortOrder = ProjectSortOrder.recent
    private var sortSegment = NSSegmentedControl()

    // Hover preview
    private var previewPopover  = NSPopover()
    private var previewTimer: Timer?
    private var previewRow = -1

    // Current selection helpers
    var selectedProject: iTermWindowProject? {
        outlineView.item(atRow: outlineView.selectedRow) as? iTermWindowProject
    }
    var selectedArchivedWindowBox: iTermArchivedWindowBox? {
        outlineView.item(atRow: outlineView.selectedRow) as? iTermArchivedWindowBox
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupOutlineView()
        setupBottomBar()
        setupPreviewPopover()
        setupObserver()
    }

    private func setupOutlineView() {
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.title = ""
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col
        outlineView.headerView = nil
        outlineView.rowHeight = 22
        outlineView.dataSource = self
        outlineView.delegate   = self
        outlineView.allowsEmptySelection = true
        outlineView.allowsMultipleSelection = false
        outlineView.focusRingType = .none
        outlineView.setDraggingSourceOperationMask(.every, forLocal: false)

        scrollView.documentView = outlineView

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sep)

        let header = makeProjectsHeader()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sep.topAnchor),

            sep.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -32),
            sep.heightAnchor.constraint(equalToConstant: 1),
        ])

        // Track mouse for hover preview
        let tracking = NSTrackingArea(rect: .zero,
                                      options: [.mouseMoved, .mouseEnteredAndExited,
                                                .activeInKeyWindow, .inVisibleRect],
                                      owner: self,
                                      userInfo: nil)
        outlineView.addTrackingArea(tracking)
    }

    private func makeProjectsHeader() -> NSView {
        let box = NSView()

        let tf = NSTextField(labelWithString: "PROJECTS")
        tf.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        tf.textColor = .secondaryLabelColor
        tf.translatesAutoresizingMaskIntoConstraints = false

        sortSegment = NSSegmentedControl(labels: ["Name", "Recent"],
                                         trackingMode: .selectOne,
                                         target: self,
                                         action: #selector(sortOrderChanged(_:)))
        sortSegment.selectedSegment = 1  // "Recent" by default
        sortSegment.controlSize = .mini
        sortSegment.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(tf)
        box.addSubview(sortSegment)
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            tf.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            sortSegment.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -6),
            sortSegment.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        return box
    }

    @objc private func sortOrderChanged(_ sender: NSSegmentedControl) {
        sortOrder = sender.selectedSegment == 0 ? .name : .recent
        outlineView.reloadData()
    }

    private func sortedProjects(_ projects: [iTermWindowProject]) -> [iTermWindowProject] {
        switch sortOrder {
        case .name:
            return projects.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .recent:
            return projects.sorted { $0.lastUsed > $1.lastUsed }
        }
    }

    private func setupBottomBar() {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 32),
        ])

        configure(&addProjectButton,   label: "+",    tip: "New project",
                  action: #selector(addProject(_:)))
        configure(&addSubprojectButton,label: "+sub",  tip: "New sub-project under selection",
                  action: #selector(addSubproject(_:)))
        configure(&deleteButton,       label: "−",    tip: "Delete selection",
                  action: #selector(deleteSelected(_:)))
        configure(&restoreButton,      label: "Restore",     tip: "Restore selected archived window",
                  action: #selector(restoreSelectedWindow(_:)))
        configure(&restoreAllButton,   label: "Restore All", tip: "Restore all windows in selected project",
                  action: #selector(restoreAllInProject(_:)))

        let stack = NSStackView(views: [addProjectButton, addSubprojectButton, deleteButton,
                                        NSView(), restoreButton, restoreAllButton])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])
    }

    private func setupPreviewPopover() {
        previewPopover.behavior = .transient
        previewPopover.animates = false
    }

    private func setupObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelChanged(_:)),
            name: iTermWindowProjectsModel.didChangeNotification,
            object: nil)
    }

    func reload() {
        outlineView.reloadData()
    }

    // MARK: Data Source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return iTermWindowProjectsModel.shared.rootProjects.count
        }
        if let project = item as? iTermWindowProject {
            return project.children.count + project.windows.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return sortedProjects(iTermWindowProjectsModel.shared.rootProjects)[index]
        }
        let project = item as! iTermWindowProject
        let sortedChildren = sortedProjects(project.children)
        if index < sortedChildren.count {
            return sortedChildren[index]
        }
        let win = project.windows[index - sortedChildren.count]
        return iTermArchivedWindowBox(win, project: project)
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let p = item as? iTermWindowProject {
            return p.children.count + p.windows.count > 0
        }
        return false
    }

    // MARK: Delegate

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("ProjectCell")
        let cell: NSTableCellView
        if let existing = outlineView.makeView(withIdentifier: id, owner: nil)
            as? NSTableCellView {
            cell = existing
        } else {
            cell = makeProjectCell(identifier: id)
        }

        if let project = item as? iTermWindowProject {
            let count = project.totalWindowCount
            let suffix = count == 0 ? "" : " (\(count))"
            cell.textField?.stringValue = project.name + suffix
            cell.imageView?.image = NSImage(systemSymbolName: "folder",
                                            accessibilityDescription: nil)
        } else if let box = item as? iTermArchivedWindowBox {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let age = formatter.localizedString(for: box.window.timestamp, relativeTo: Date())
            cell.textField?.stringValue = "\(box.window.name)  \(age)"
            cell.imageView?.image = NSImage(systemSymbolName: "terminal",
                                            accessibilityDescription: nil)
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
        onSelectionChange?()
    }

    // MARK: Button Actions

    @objc private func addProject(_ sender: Any?) {
        promptForName(title: "New Project", prompt: "Project name:") { [weak self] name in
            iTermWindowProjectsModel.shared.createProject(named: name)
            self?.reload()
        }
    }

    @objc private func addSubproject(_ sender: Any?) {
        guard let parent = selectedProject else {
            showAlert("Select a project first to add a sub-project.")
            return
        }
        promptForName(title: "New Sub-Project", prompt: "Sub-project name:") { [weak self] name in
            iTermWindowProjectsModel.shared.createProject(named: name, parent: parent)
            self?.reload()
            self?.outlineView.expandItem(parent)
        }
    }

    @objc private func deleteSelected(_ sender: Any?) {
        if let box = selectedArchivedWindowBox {
            iTermWindowProjectsModel.shared.removeWindow(box.window, from: box.project)
            reload()
        } else if let project = selectedProject {
            let alert = NSAlert()
            alert.messageText = "Delete "\(project.name)"?"
            alert.informativeText = "This removes the project and all its archived windows. Open windows are unaffected."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            alert.buttons[0].hasDestructiveAction = true
            if alert.runModal() == .alertFirstButtonReturn {
                iTermWindowProjectsModel.shared.deleteProject(project)
                reload()
            }
        }
    }

    @objc func restoreSelectedWindow(_ sender: Any?) {
        guard let box = selectedArchivedWindowBox else { return }
        iTermWindowProjectsModel.shared.restoreWindow(box.window)
    }

    @objc func restoreAllInProject(_ sender: Any?) {
        guard let project = selectedProject else { return }
        iTermWindowProjectsModel.shared.restoreAllWindows(in: project)
    }

    // MARK: Context Menu

    override func rightMouseDown(with event: NSEvent) {
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row = outlineView.row(at: point)
        guard row >= 0 else { super.rightMouseDown(with: event); return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)

        let menu = NSMenu()
        if let box = selectedArchivedWindowBox {
            menu.addItem(NSMenuItem(title: "Restore Window",
                                   action: #selector(restoreSelectedWindow(_:)),
                                   keyEquivalent: ""))
            menu.addItem(.separator())
            let del = NSMenuItem(title: "Remove from Project",
                                 action: #selector(deleteSelected(_:)),
                                 keyEquivalent: "")
            menu.addItem(del)
            _ = box // suppress unused warning
        } else if let project = selectedProject {
            menu.addItem(NSMenuItem(title: "Restore All Windows",
                                   action: #selector(restoreAllInProject(_:)),
                                   keyEquivalent: ""))
            menu.addItem(.separator())
            let rename = NSMenuItem(title: "Rename…",
                                   action: #selector(renameProject(_:)),
                                   keyEquivalent: "")
            menu.addItem(rename)
            let sub = NSMenuItem(title: "New Sub-Project…",
                                 action: #selector(addSubproject(_:)),
                                 keyEquivalent: "")
            menu.addItem(sub)
            menu.addItem(.separator())
            let del = NSMenuItem(title: "Delete Project",
                                 action: #selector(deleteSelected(_:)),
                                 keyEquivalent: "")
            menu.addItem(del)
            _ = project // suppress unused warning
        }
        menu.items.forEach { $0.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: outlineView)
    }

    @objc private func renameProject(_ sender: Any?) {
        guard let project = selectedProject else { return }
        promptForName(title: "Rename Project",
                      prompt: "New name:",
                      initial: project.name) { [weak self] name in
            iTermWindowProjectsModel.shared.renameProject(project, to: name)
            self?.reload()
        }
    }

    // MARK: Hover Preview

    override func mouseMoved(with event: NSEvent) {
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row = outlineView.row(at: point)
        if row == previewRow { return }
        cancelPreview()
        guard row >= 0 else { return }
        previewRow = row
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.showPreview(forRow: row)
        }
    }

    override func mouseExited(with event: NSEvent) {
        cancelPreview()
    }

    private func cancelPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        previewRow = -1
        previewPopover.close()
    }

    private func showPreview(forRow row: Int) {
        guard let item = outlineView.item(atRow: row) as? iTermArchivedWindowBox,
              let arrangement = item.window.arrangement else { return }
        let rowRect = outlineView.rect(ofRow: row)
        guard rowRect != .zero else { return }

        let previewView = ArrangementPreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        previewView.setArrangement([arrangement as Any])

        let vc = NSViewController()
        vc.view = previewView
        previewPopover.contentViewController = vc
        previewPopover.contentSize = previewView.frame.size
        previewPopover.show(relativeTo: rowRect, of: outlineView, preferredEdge: .maxX)
    }

    // MARK: Notifications

    @objc private func modelChanged(_ note: Notification) {
        reload()
    }

    // MARK: Helpers

    private func updateButtons() {
        let hasProject = selectedProject != nil
        let hasWindow  = selectedArchivedWindowBox != nil
        addSubprojectButton.isEnabled = hasProject
        deleteButton.isEnabled        = hasProject || hasWindow
        restoreButton.isEnabled       = hasWindow
        restoreAllButton.isEnabled    = hasProject
    }

    private func makeProjectCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.imageScaling = .scaleProportionallyDown
        cell.imageView = iv

        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.lineBreakMode = .byTruncatingTail
        cell.textField = tf

        cell.addSubview(iv)
        cell.addSubview(tf)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 4),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

// MARK: - Open Windows Controller

final class iTermOpenWindowsController: NSViewController,
                                         NSTableViewDataSource,
                                         NSTableViewDelegate {
    weak var projectsController: iTermProjectsOutlineController?

    private var tableView   = NSTableView()
    private var scrollView  = NSScrollView()
    private var archiveButton    = NSButton()
    private var closeArchiveButton = NSButton()
    private var statusLabel = NSTextField(labelWithString: "")

    // Hover preview
    private var previewPopover = NSPopover()
    private var previewTimer: Timer?
    private var previewRow = -1

    private var terminals: [PseudoTerminal] {
        (iTermController.sharedInstance().terminals as? [PseudoTerminal]) ?? []
    }

    var selectedTerminal: PseudoTerminal? {
        let row = tableView.selectedRow
        guard row >= 0, row < terminals.count else { return nil }
        return terminals[row]
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
        setupBottomBar()
        setupPreviewPopover()
        updateArchiveButton()
    }

    private func setupTableView() {
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.title = ""
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.allowsEmptySelection = true
        tableView.focusRingType = .none

        scrollView.documentView = tableView

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sep)

        let header = makeSectionHeader("OPEN WINDOWS")
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sep.topAnchor),

            sep.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -32),
            sep.heightAnchor.constraint(equalToConstant: 1),
        ])

        let tracking = NSTrackingArea(rect: .zero,
                                      options: [.mouseMoved, .mouseEnteredAndExited,
                                                .activeInKeyWindow, .inVisibleRect],
                                      owner: self,
                                      userInfo: nil)
        tableView.addTrackingArea(tracking)
    }

    private func setupBottomBar() {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 32),
        ])

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        configure(&archiveButton,
                  label: "Archive to Project",
                  tip: "Save selected window into the selected project (keeps it open)",
                  action: #selector(archiveSelected(_:)))
        configure(&closeArchiveButton,
                  label: "Close & Archive",
                  tip: "Save selected window into the selected project and close it",
                  action: #selector(closeAndArchive(_:)))

        let stack = NSStackView(views: [statusLabel, NSView(),
                                        archiveButton, closeArchiveButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])
    }

    private func setupPreviewPopover() {
        previewPopover.behavior = .transient
        previewPopover.animates = false
    }

    func reload() {
        tableView.reloadData()
        let n = terminals.count
        statusLabel.stringValue = n == 1 ? "1 window" : "\(n) windows"
        updateArchiveButton()
    }

    func updateArchiveButton() {
        let hasWindow  = selectedTerminal != nil
        let hasProject = projectsController?.selectedProject != nil
        archiveButton.isEnabled      = hasWindow && hasProject
        closeArchiveButton.isEnabled = hasWindow && hasProject
    }

    // MARK: Data Source

    func numberOfRows(in tableView: NSTableView) -> Int { terminals.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("WindowCell")
        let cell: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: id, owner: nil)
            as? NSTableCellView {
            cell = existing
        } else {
            cell = makeWindowCell(identifier: id)
        }
        let terminal = terminals[row]
        let title    = terminal.window()?.title ?? "Window \(row + 1)"
        cell.textField?.stringValue = title
        cell.imageView?.image = NSImage(systemSymbolName: "rectangle.on.rectangle",
                                        accessibilityDescription: nil)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateArchiveButton()
    }

    // MARK: Actions

    @objc private func archiveSelected(_ sender: Any?) {
        archive(andClose: false)
    }

    @objc private func closeAndArchive(_ sender: Any?) {
        archive(andClose: true)
    }

    private func archive(andClose close: Bool) {
        guard let terminal = selectedTerminal,
              let project = projectsController?.selectedProject else { return }
        iTermWindowProjectsModel.shared.archiveWindow(terminal, to: project, andClose: close)
        reload()
        projectsController?.reload()
    }

    // MARK: Hover Preview

    override func mouseMoved(with event: NSEvent) {
        let point = tableView.convert(event.locationInWindow, from: nil)
        let row = tableView.row(at: point)
        if row == previewRow { return }
        cancelPreview()
        guard row >= 0 else { return }
        previewRow = row
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.showPreview(forRow: row)
        }
    }

    override func mouseExited(with event: NSEvent) {
        cancelPreview()
    }

    private func cancelPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        previewRow = -1
        previewPopover.close()
    }

    private func showPreview(forRow row: Int) {
        guard row < terminals.count else { return }
        let terminal = terminals[row]
        guard let nsWindow = terminal.window(),
              nsWindow.windowNumber > 0 else { return }
        let rowRect = tableView.rect(ofRow: row)
        guard rowRect != .zero else { return }

        let windowID = CGWindowID(nsWindow.windowNumber)
        let cgImage  = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution])

        guard let cgImage else { return }
        let img = NSImage(cgImage: cgImage, size: .zero)

        let aspectW: CGFloat = 320
        let aspectH = cgImage.height == 0 ? 200
            : aspectW * CGFloat(cgImage.height) / CGFloat(cgImage.width)
        let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: aspectW, height: min(aspectH, 240)))
        iv.image = img
        iv.imageScaling = .scaleProportionallyUpOrDown

        let vc = NSViewController()
        vc.view = iv
        previewPopover.contentViewController = vc
        previewPopover.contentSize = iv.frame.size
        previewPopover.show(relativeTo: rowRect, of: tableView, preferredEdge: .minX)
    }

    // MARK: Helpers

    private func makeWindowCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.imageScaling = .scaleProportionallyDown
        cell.imageView = iv

        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.lineBreakMode = .byTruncatingTail
        cell.textField = tf

        cell.addSubview(iv)
        cell.addSubview(tf)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 4),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

// MARK: - Shared Helpers

private func makeSectionHeader(_ title: String) -> NSView {
    let box = NSView()
    let tf = NSTextField(labelWithString: title)
    tf.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    tf.textColor = .secondaryLabelColor
    tf.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(tf)
    NSLayoutConstraint.activate([
        tf.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
        tf.centerYAnchor.constraint(equalTo: box.centerYAnchor),
    ])
    return box
}

private func configure(_ button: inout NSButton,
                        label: String,
                        tip: String,
                        action: Selector) {
    button = NSButton(title: label, target: nil, action: action)
    button.bezelStyle = .inline
    button.controlSize = .small
    button.toolTip = tip
}

private func showAlert(_ message: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.runModal()
}

private func promptForName(title: String,
                            prompt: String,
                            initial: String = "",
                            completion: @escaping (String) -> Void) {
    let alert = NSAlert()
    alert.messageText = title
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    tf.stringValue = initial
    tf.placeholderString = prompt
    alert.accessoryView = tf
    alert.window.initialFirstResponder = tf
    if alert.runModal() == .alertFirstButtonReturn {
        let name = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { completion(name) }
    }
}
