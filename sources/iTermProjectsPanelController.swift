// iTermProjectsPanelController.swift
// iTerm2
//
// Panel UI for per-window project archives.
//
// Left pane  — project tree.  Each project shows both live (open, bold) and
//              archived (closed, grey) windows. Drag source & drop target.
// Right pane — open windows only, grouped by their associated project.
//              "Unassociated" section for windows with no project.
//              Drag source & drop target.
//
// Drag-and-drop semantics
//   right live window  → left project          archive + close
//   right live window  → right project group   reassign association (keep open)
//   right live window  → right root / Unassoc  disassociate (keep open)
//   right project group → left pane            close-all (archive + close all)
//   left archived window → right pane          restore (remove archive entry)
//   left project         → right pane          restore all windows in project

import AppKit

// MARK: - Drag Pasteboard Types

private let kLiveWindowDragType     = NSPasteboard.PasteboardType("com.iterm2.projects.live-window")
private let kArchivedWindowDragType = NSPasteboard.PasteboardType("com.iterm2.projects.archived-window")
private let kProjectDragType        = NSPasteboard.PasteboardType("com.iterm2.projects.project")
private let kProjectGroupDragType   = NSPasteboard.PasteboardType("com.iterm2.projects.project-group")

// MARK: - Sort Order

enum ProjectSortOrder { case name, recent }

// MARK: - Item Wrappers

/// An archived (closed) window shown as a leaf in the left pane.
final class iTermArchivedWindowBox: NSObject {
    let window: iTermArchivedWindow
    let project: iTermWindowProject
    init(_ window: iTermArchivedWindow, project: iTermWindowProject) {
        self.window = window
        self.project = project
    }
}

/// A live (open) window shown as a leaf in the left pane under its associated project.
final class iTermLiveWindowBox: NSObject {
    let terminal: PseudoTerminal
    let project: iTermWindowProject
    init(_ terminal: PseudoTerminal, project: iTermWindowProject) {
        self.terminal = terminal
        self.project = project
    }
}

/// One group row in the right pane.  nil project = "Unassociated".
final class iTermOpenProjectGroup: NSObject {
    let project: iTermWindowProject?
    var terminals: [PseudoTerminal]
    init(project: iTermWindowProject?, terminals: [PseudoTerminal]) {
        self.project = project
        self.terminals = terminals
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
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 540),
            styleMask: [.titled, .closable, .resizable, .miniaturizable,
                        .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: true)
        panel.title = "Window Projects"
        panel.minSize = NSSize(width: 620, height: 380)
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
            self?.windowsVC.updateActionButtons()
        }
        windowsVC.projectsController = projectsVC

        let left  = NSSplitViewItem(viewController: projectsVC)
        left.minimumThickness  = 220
        left.maximumThickness  = 480
        left.preferredThicknessFraction = 0.44

        let right = NSSplitViewItem(viewController: windowsVC)
        right.minimumThickness = 240

        addSplitViewItem(left)
        addSplitViewItem(right)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        splitView.setPosition(380, ofDividerAt: 0)
    }

    func reloadAll() {
        projectsVC.reload()
        windowsVC.reload()
    }
}

// MARK: - Left Pane: Project Tree (open + archived windows)

final class iTermProjectsOutlineController: NSViewController,
                                             NSOutlineViewDataSource,
                                             NSOutlineViewDelegate {
    var onSelectionChange: (() -> Void)?

    private(set) var outlineView = NSOutlineView()
    private var scrollView       = NSScrollView()
    private var addProjectButton    = NSButton()
    private var addSubprojectButton = NSButton()
    private var deleteButton        = NSButton()
    private var restoreButton       = NSButton()
    private var restoreAllButton    = NSButton()
    private var closeProjectButton  = NSButton()

    private var sortOrder   = ProjectSortOrder.recent
    private var sortSegment = NSSegmentedControl()

    // Hover preview
    private var previewPopover = NSPopover()
    private var previewTimer: Timer?
    private var previewRow = -1

    // MARK: Selection helpers

    var selectedProject: iTermWindowProject? {
        outlineView.item(atRow: outlineView.selectedRow) as? iTermWindowProject
    }
    var selectedArchivedBox: iTermArchivedWindowBox? {
        outlineView.item(atRow: outlineView.selectedRow) as? iTermArchivedWindowBox
    }
    var selectedLiveBox: iTermLiveWindowBox? {
        outlineView.item(atRow: outlineView.selectedRow) as? iTermLiveWindowBox
    }

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupOutlineView()
        setupBottomBar()
        setupPreviewPopover()
        setupObservers()
    }

    // MARK: Setup

    private func setupOutlineView() {
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.borderType          = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.title = ""
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col
        outlineView.headerView      = nil
        outlineView.rowHeight       = 22
        outlineView.dataSource      = self
        outlineView.delegate        = self
        outlineView.allowsEmptySelection    = true
        outlineView.allowsMultipleSelection = false
        outlineView.focusRingType   = .none
        outlineView.doubleAction    = #selector(doubleClicked(_:))
        outlineView.target          = self

        // Drag source + destination
        outlineView.setDraggingSourceOperationMask(.every, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.every, forLocal: false)
        outlineView.registerForDraggedTypes([kLiveWindowDragType,
                                             kArchivedWindowDragType,
                                             kProjectGroupDragType])

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
        tf.font       = NSFont.systemFont(ofSize: 10, weight: .semibold)
        tf.textColor  = .secondaryLabelColor
        tf.translatesAutoresizingMaskIntoConstraints = false

        sortSegment = NSSegmentedControl(labels: ["Name", "Recent"],
                                         trackingMode: .selectOne,
                                         target: self,
                                         action: #selector(sortOrderChanged(_:)))
        sortSegment.selectedSegment = 1
        sortSegment.controlSize     = .mini
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
        case .name:   return projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recent: return projects.sorted { $0.lastUsed > $1.lastUsed }
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

        configure(&addProjectButton,    label: "+",           tip: "New project",
                  action: #selector(addProject(_:)))
        configure(&addSubprojectButton, label: "+sub",        tip: "New sub-project under selection",
                  action: #selector(addSubproject(_:)))
        configure(&deleteButton,        label: "−",           tip: "Delete selection",
                  action: #selector(deleteSelected(_:)))
        configure(&restoreButton,       label: "Restore",     tip: "Restore selected archived window",
                  action: #selector(restoreSelectedWindow(_:)))
        configure(&restoreAllButton,    label: "Restore All", tip: "Restore all archived windows in selected project",
                  action: #selector(restoreAllInProject(_:)))
        configure(&closeProjectButton,  label: "Close All",   tip: "Close and archive all open windows in selected project",
                  action: #selector(closeSelectedProject(_:)))

        let spacer = NSView()
        let stack  = NSStackView(views: [addProjectButton, addSubprojectButton, deleteButton,
                                         spacer,
                                         restoreButton, restoreAllButton, closeProjectButton])
        stack.orientation = .horizontal
        stack.spacing     = 4
        stack.edgeInsets  = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
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

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelChanged(_:)),
            name: iTermWindowProjectsModel.didChangeNotification,
            object: nil)
    }

    func reload() { outlineView.reloadData() }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return sortedProjects(iTermWindowProjectsModel.shared.rootProjects).count
        }
        if let project = item as? iTermWindowProject {
            let liveCount = iTermWindowProjectsModel.shared.liveWindows(for: project).count
            return project.children.count + liveCount + project.windows.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return sortedProjects(iTermWindowProjectsModel.shared.rootProjects)[index]
        }
        let project       = item as! iTermWindowProject
        let sortedKids    = sortedProjects(project.children)
        if index < sortedKids.count {
            return sortedKids[index]
        }
        let afterKids  = index - sortedKids.count
        let liveWins   = iTermWindowProjectsModel.shared.liveWindows(for: project)
        if afterKids < liveWins.count {
            return iTermLiveWindowBox(liveWins[afterKids], project: project)
        }
        let archivedIdx = afterKids - liveWins.count
        return iTermArchivedWindowBox(project.windows[archivedIdx], project: project)
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let p = item as? iTermWindowProject {
            let liveCount = iTermWindowProjectsModel.shared.liveWindows(for: p).count
            return p.children.count + liveCount + p.windows.count > 0
        }
        return false
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        let id   = NSUserInterfaceItemIdentifier("ProjectCell")
        let cell: NSTableCellView
        if let existing = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = makeProjectCell(identifier: id)
        }

        if let project = item as? iTermWindowProject {
            let liveCount = iTermWindowProjectsModel.shared.liveWindows(for: project).count
            let archCount = project.totalWindowCount
            var suffix = ""
            if liveCount > 0 || archCount > 0 {
                let parts = [liveCount > 0 ? "\(liveCount) open" : nil,
                             archCount > 0 ? "\(archCount) archived" : nil].compactMap { $0 }
                suffix = " (\(parts.joined(separator: ", ")))"
            }
            cell.textField?.stringValue = project.name + suffix
            cell.textField?.font        = .systemFont(ofSize: NSFont.systemFontSize)
            cell.textField?.textColor   = .labelColor
            cell.imageView?.image       = NSImage(systemSymbolName: "folder",
                                                  accessibilityDescription: nil)

        } else if let liveBox = item as? iTermLiveWindowBox {
            let title = liveBox.terminal.window()?.title ?? "Window"
            cell.textField?.stringValue = title
            cell.textField?.font        = .boldSystemFont(ofSize: NSFont.systemFontSize)
            cell.textField?.textColor   = .labelColor
            cell.imageView?.image       = NSImage(systemSymbolName: "terminal.fill",
                                                  accessibilityDescription: nil)

        } else if let box = item as? iTermArchivedWindowBox {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let age = formatter.localizedString(for: box.window.timestamp, relativeTo: Date())
            cell.textField?.stringValue = "\(box.window.name)  \(age)"
            cell.textField?.font        = .systemFont(ofSize: NSFont.systemFontSize)
            cell.textField?.textColor   = .secondaryLabelColor
            cell.imageView?.image       = NSImage(systemSymbolName: "terminal",
                                                  accessibilityDescription: nil)
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
        onSelectionChange?()
    }

    // MARK: Double-click

    @objc private func doubleClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0 else { return }
        let item = outlineView.item(atRow: row)
        if let box = item as? iTermArchivedWindowBox {
            iTermWindowProjectsModel.shared.restoreWindow(box.window)
        } else if let liveBox = item as? iTermLiveWindowBox {
            liveBox.terminal.window()?.makeKeyAndOrderFront(nil)
        }
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
        if let box = selectedArchivedBox {
            iTermWindowProjectsModel.shared.removeWindow(box.window, from: box.project)
            reload()
        } else if let project = selectedProject {
            let alert = NSAlert()
            alert.messageText     = "Delete “\(project.name)“?"
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
        guard let box = selectedArchivedBox else { return }
        iTermWindowProjectsModel.shared.restoreWindow(box.window)
    }

    @objc func restoreAllInProject(_ sender: Any?) {
        guard let project = selectedProject else { return }
        iTermWindowProjectsModel.shared.restoreAllWindows(in: project)
    }

    @objc private func closeSelectedProject(_ sender: Any?) {
        guard let project = selectedProject else { return }
        guard iTermWindowProjectsModel.shared.hasLiveWindows(for: project) else {
            showAlert("No open windows are associated with “\(project.name)“.")
            return
        }
        iTermWindowProjectsModel.shared.closeProject(project)
        reload()
    }

    // MARK: Context Menu

    override func rightMouseDown(with event: NSEvent) {
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row   = outlineView.row(at: point)
        guard row >= 0 else { super.rightMouseDown(with: event); return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)

        let menu = NSMenu()
        if let box = selectedArchivedBox {
            menu.addItem(NSMenuItem(title: "Restore Window",
                                   action: #selector(restoreSelectedWindow(_:)),
                                   keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Remove from Project",
                                   action: #selector(deleteSelected(_:)),
                                   keyEquivalent: ""))
            _ = box
        } else if let liveBox = selectedLiveBox {
            let bringItem = NSMenuItem(title: "Bring to Front",
                                      action: #selector(bringLiveWindowToFront(_:)),
                                      keyEquivalent: "")
            menu.addItem(bringItem)
            menu.addItem(.separator())
            let archiveItem = NSMenuItem(title: "Close & Archive Now",
                                        action: #selector(closeAndArchiveLiveWindow(_:)),
                                        keyEquivalent: "")
            menu.addItem(archiveItem)
            let disItem = NSMenuItem(title: "Disassociate from Project",
                                     action: #selector(disassociateLiveWindow(_:)),
                                     keyEquivalent: "")
            menu.addItem(disItem)
            _ = liveBox
        } else if let project = selectedProject {
            menu.addItem(NSMenuItem(title: "Restore All Windows",
                                   action: #selector(restoreAllInProject(_:)),
                                   keyEquivalent: ""))
            if iTermWindowProjectsModel.shared.hasLiveWindows(for: project) {
                menu.addItem(NSMenuItem(title: "Close All Open Windows",
                                       action: #selector(closeSelectedProject(_:)),
                                       keyEquivalent: ""))
            }
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Rename…",
                                   action: #selector(renameProject(_:)),
                                   keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "New Sub-Project…",
                                   action: #selector(addSubproject(_:)),
                                   keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Delete Project",
                                   action: #selector(deleteSelected(_:)),
                                   keyEquivalent: ""))
            _ = project
        }
        menu.items.forEach { $0.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: outlineView)
    }

    @objc private func renameProject(_ sender: Any?) {
        guard let project = selectedProject else { return }
        promptForName(title: "Rename Project", prompt: "New name:", initial: project.name) { [weak self] name in
            iTermWindowProjectsModel.shared.renameProject(project, to: name)
            self?.reload()
        }
    }

    @objc private func bringLiveWindowToFront(_ sender: Any?) {
        selectedLiveBox?.terminal.window()?.makeKeyAndOrderFront(nil)
    }

    @objc private func closeAndArchiveLiveWindow(_ sender: Any?) {
        guard let liveBox = selectedLiveBox else { return }
        let keepJobs = NSEvent.modifierFlags.contains(.option)
        iTermWindowProjectsModel.shared.archiveWindow(liveBox.terminal,
                                                      to: liveBox.project,
                                                      andClose: true,
                                                      keepJobsRunning: keepJobs)
        reload()
    }

    @objc private func disassociateLiveWindow(_ sender: Any?) {
        guard let liveBox = selectedLiveBox else { return }
        iTermWindowProjectsModel.shared.disassociateWindow(liveBox.terminal)
        reload()
    }

    // MARK: Drag Source

    func outlineView(_ outlineView: NSOutlineView,
                     pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        if let box = item as? iTermArchivedWindowBox {
            let pb = NSPasteboardItem()
            pb.setString(box.window.id.uuidString, forType: kArchivedWindowDragType)
            return pb
        }
        if let box = item as? iTermLiveWindowBox {
            guard let wn = box.terminal.window()?.windowNumber, wn > 0 else { return nil }
            let pb = NSPasteboardItem()
            pb.setString(String(wn), forType: kLiveWindowDragType)
            return pb
        }
        if let project = item as? iTermWindowProject {
            let pb = NSPasteboardItem()
            pb.setString(project.id.uuidString, forType: kProjectDragType)
            return pb
        }
        return nil
    }

    // MARK: Drop Destination

    func outlineView(_ outlineView: NSOutlineView,
                     validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        let pb = info.draggingPasteboard
        
        // Live window dropped onto a project
        if pb.availableType(from: [kLiveWindowDragType]) != nil,
           item is iTermWindowProject {
            return .move
        }
        
        // Archived window dropped onto a project
        if pb.availableType(from: [kArchivedWindowDragType]) != nil,
           item is iTermWindowProject {
            return .move
        }
        
        // Project group dropped anywhere on left → close all
        if pb.availableType(from: [kProjectGroupDragType]) != nil {
            // Redirect to root if dropped on a leaf or nothing
            if item == nil || item is iTermWindowProject {
                return .move
            }
            outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .move
        }
        return []
    }

    func outlineView(_ outlineView: NSOutlineView,
                     acceptDrop info: NSDraggingInfo,
                     item: Any?,
                     childIndex index: Int) -> Bool {
        let pb = info.draggingPasteboard
        let isInternalDrag = (info.draggingSource as? NSOutlineView) === outlineView

        // Drop live window onto project
        if let wnStr    = pb.string(forType: kLiveWindowDragType),
           let wn       = Int(wnStr),
           let project  = item as? iTermWindowProject {
            let all = (iTermController.sharedInstance().terminals() as? [PseudoTerminal]) ?? []
            guard let terminal = all.first(where: { $0.window()?.windowNumber == wn }) else {
                return false
            }
            if isInternalDrag {
                // Dragged from left to left (reassociate / reassign project, keep open!)
                iTermWindowProjectsModel.shared.associateWindow(terminal, with: project)
            } else {
                // Dragged from right to left (archive + close!)
                let keepJobs = NSEvent.modifierFlags.contains(.option)
                iTermWindowProjectsModel.shared.archiveWindow(terminal, to: project, andClose: true, keepJobsRunning: keepJobs)
            }
            return true
        }

        // Drop archived window onto project
        if let uuidStr  = pb.string(forType: kArchivedWindowDragType),
           let uuid     = UUID(uuidString: uuidStr),
           let project  = item as? iTermWindowProject {
            if let (archived, oldProject) = iTermWindowProjectsModel.shared.archivedWindow(id: uuid) {
                oldProject.windows.removeAll { $0.id == archived.id }
                project.windows.append(archived)
                iTermWindowProjectsModel.shared.save()
                return true
            }
        }

        // Drop project group → close-all for that project
        if let uuidStr = pb.string(forType: kProjectGroupDragType),
           let uuid    = UUID(uuidString: uuidStr),
           let project = iTermWindowProjectsModel.shared.project(id: uuid) {
            iTermWindowProjectsModel.shared.closeProject(project)
            return true
        }

        return false
    }

    // MARK: Hover Preview

    override func mouseMoved(with event: NSEvent) {
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row   = outlineView.row(at: point)
        if row == previewRow { return }
        cancelPreview()
        guard row >= 0 else { return }
        previewRow = row
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.showPreview(forRow: row)
        }
    }

    override func mouseExited(with event: NSEvent) { cancelPreview() }

    private func cancelPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        previewRow   = -1
        previewPopover.close()
    }

    private func showPreview(forRow row: Int) {
        let item = outlineView.item(atRow: row)

        if let box = item as? iTermArchivedWindowBox {
            let rowRect = outlineView.rect(ofRow: row)
            guard rowRect != .zero else { return }
            let fileURL = iTermWindowProjectsModel.thumbnailURL(for: box.window.id)
            if FileManager.default.fileExists(atPath: fileURL.path),
               let img = NSImage(contentsOf: fileURL) {
                let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: 320, height: img.size.height))
                iv.image = img
                iv.imageScaling = .scaleProportionallyUpOrDown
                showPopover(contentView: iv, anchor: rowRect, preferredEdge: .maxX)
            } else if let arrangement = box.window.arrangement {
                let pv = ArrangementPreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
                pv.setArrangement([arrangement as Any])
                showPopover(contentView: pv, anchor: rowRect, preferredEdge: .maxX)
            }
            return
        }

        if let liveBox = item as? iTermLiveWindowBox,
           let nsWindow = liveBox.terminal.window(),
           nsWindow.windowNumber > 0 {
            showLivePreview(windowNumber: CGWindowID(nsWindow.windowNumber),
                            anchor: outlineView.rect(ofRow: row),
                            preferredEdge: .maxX)
        }
    }

    // MARK: Notifications

    @objc private func modelChanged(_ note: Notification) { reload() }

    // MARK: Helpers

    private func updateButtons() {
        let hasProject  = selectedProject != nil
        let hasArchived = selectedArchivedBox != nil
        addSubprojectButton.isEnabled = hasProject
        deleteButton.isEnabled        = hasProject || hasArchived
        restoreButton.isEnabled       = hasArchived
        restoreAllButton.isEnabled    = hasProject
        if let proj = selectedProject {
            closeProjectButton.isEnabled = iTermWindowProjectsModel.shared.hasLiveWindows(for: proj)
        } else {
            closeProjectButton.isEnabled = false
        }
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

    private func showPopover(contentView: NSView, anchor: NSRect, preferredEdge: NSRectEdge) {
        let vc = NSViewController()
        vc.view = contentView
        previewPopover.contentViewController = vc
        previewPopover.contentSize = contentView.frame.size
        previewPopover.show(relativeTo: anchor, of: outlineView, preferredEdge: preferredEdge)
    }
}

// MARK: - Right Pane: Open Windows (grouped by project)

final class iTermOpenWindowsController: NSViewController,
                                         NSOutlineViewDataSource,
                                         NSOutlineViewDelegate {
    weak var projectsController: iTermProjectsOutlineController?

    private var outlineView  = NSOutlineView()
    private var scrollView   = NSScrollView()
    private var associateButton = NSButton()
    private var statusLabel     = NSTextField(labelWithString: "")

    // Hover preview
    private var previewPopover = NSPopover()
    private var previewTimer: Timer?
    private var previewRow = -1

    private var groups: [iTermOpenProjectGroup] = []

    private var terminals: [PseudoTerminal] {
        (iTermController.sharedInstance().terminals() as? [PseudoTerminal]) ?? []
    }

    var selectedTerminal: PseudoTerminal? {
        outlineView.item(atRow: outlineView.selectedRow) as? PseudoTerminal
    }
    var selectedGroup: iTermOpenProjectGroup? {
        outlineView.item(atRow: outlineView.selectedRow) as? iTermOpenProjectGroup
    }

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupOutlineView()
        setupBottomBar()
        setupPreviewPopover()
        setupObservers()
        updateActionButtons()
    }

    // MARK: Setup

    private func recomputeGroups() {
        let model    = iTermWindowProjectsModel.shared
        let allTerms = terminals

        var byProjectID: [UUID: (project: iTermWindowProject, terminals: [PseudoTerminal])] = [:]
        var unassociated: [PseudoTerminal] = []

        for terminal in allTerms {
            if let proj = model.project(for: terminal) {
                if byProjectID[proj.id] != nil {
                    byProjectID[proj.id]!.terminals.append(terminal)
                } else {
                    byProjectID[proj.id] = (project: proj, terminals: [terminal])
                }
            } else {
                unassociated.append(terminal)
            }
        }

        groups = byProjectID.values
            .sorted { $0.project.name.localizedCaseInsensitiveCompare($1.project.name) == .orderedAscending }
            .map { iTermOpenProjectGroup(project: $0.project, terminals: $0.terminals) }

        if !unassociated.isEmpty {
            groups.append(iTermOpenProjectGroup(project: nil, terminals: unassociated))
        }
    }

    private func setupOutlineView() {
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.borderType          = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.title = ""
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col
        outlineView.headerView      = nil
        outlineView.rowHeight       = 22
        outlineView.dataSource      = self
        outlineView.delegate        = self
        outlineView.allowsEmptySelection    = true
        outlineView.allowsMultipleSelection = false
        outlineView.focusRingType   = .none

        // Drag source + destination
        outlineView.setDraggingSourceOperationMask(.every, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.every, forLocal: false)
        outlineView.registerForDraggedTypes([kLiveWindowDragType,
                                             kArchivedWindowDragType,
                                             kProjectDragType])

        scrollView.documentView = outlineView

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
        outlineView.addTrackingArea(tracking)
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

        statusLabel.font      = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        configure(&associateButton,
                  label: "Associate with Project",
                  tip: "Mark the selected open window as belonging to the selected project (auto-archives on close)",
                  action: #selector(associateSelected(_:)))

        let stack = NSStackView(views: [statusLabel, NSView(), associateButton])
        stack.orientation  = .horizontal
        stack.spacing      = 6
        stack.edgeInsets   = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
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

    private func setupObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(reload),
                       name: iTermWindowProjectsModel.didChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(reload),
                       name: NSWindow.willCloseNotification, object: nil)
        nc.addObserver(self, selector: #selector(reload),
                       name: NSWindow.didBecomeMainNotification, object: nil)
    }

    @objc func reload() {
        recomputeGroups()
        outlineView.reloadData()
        let n = terminals.count
        statusLabel.stringValue = n == 1 ? "1 window" : "\(n) windows"
        updateActionButtons()
        for group in groups {
            outlineView.expandItem(group)
        }
    }

    func updateActionButtons() {
        let hasTerminal = selectedTerminal != nil
        let hasProject  = projectsController?.selectedProject != nil
        associateButton.isEnabled = hasTerminal && hasProject
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return groups.count }
        if let group = item as? iTermOpenProjectGroup { return group.terminals.count }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return groups[index] }
        return (item as! iTermOpenProjectGroup).terminals[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is iTermOpenProjectGroup
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        if let group = item as? iTermOpenProjectGroup {
            let id = NSUserInterfaceItemIdentifier("GroupCell")
            let cell: NSTableCellView
            if let existing = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
                cell = existing
            } else {
                cell = makeGroupCell(identifier: id)
            }
            let count    = group.terminals.count
            let countStr = count == 1 ? "1 window" : "\(count) windows"
            if let proj = group.project {
                cell.textField?.stringValue = "\(proj.name)  \(countStr)"
                cell.textField?.textColor   = .labelColor
                cell.imageView?.image       = NSImage(systemSymbolName: "folder.fill",
                                                      accessibilityDescription: nil)
            } else {
                cell.textField?.stringValue = "Unassociated  \(countStr)"
                cell.textField?.textColor   = .secondaryLabelColor
                cell.imageView?.image       = NSImage(systemSymbolName: "questionmark.folder",
                                                      accessibilityDescription: nil)
            }
            return cell
        }

        if let terminal = item as? PseudoTerminal {
            let id = NSUserInterfaceItemIdentifier("WindowCell")
            let cell: NSTableCellView
            if let existing = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
                cell = existing
            } else {
                cell = makeWindowCell(identifier: id)
            }
            cell.textField?.stringValue = terminal.window()?.title ?? "Window"
            cell.imageView?.image       = NSImage(systemSymbolName: "terminal",
                                                  accessibilityDescription: nil)
            return cell
        }
        return nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        item is iTermOpenProjectGroup
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        updateActionButtons()
    }

    // MARK: Actions

    @objc private func associateSelected(_ sender: Any?) {
        guard let terminal = selectedTerminal,
              let project  = projectsController?.selectedProject else { return }
        iTermWindowProjectsModel.shared.associateWindow(terminal, with: project)
        reload()
        projectsController?.reload()
    }

    // MARK: Context Menu

    override func rightMouseDown(with event: NSEvent) {
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row   = outlineView.row(at: point)
        guard row >= 0 else { super.rightMouseDown(with: event); return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)

        let menu = NSMenu()
        if let terminal = selectedTerminal {
            menu.addItem(NSMenuItem(title: "Bring to Front",
                                   action: #selector(bringSelectedToFront(_:)),
                                   keyEquivalent: ""))
            let isAssociated = iTermWindowProjectsModel.shared.project(for: terminal) != nil
            if isAssociated {
                menu.addItem(.separator())
                menu.addItem(NSMenuItem(title: "Close & Archive to Project",
                                       action: #selector(closeAndArchiveSelected(_:)),
                                       keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Disassociate from Project",
                                       action: #selector(disassociateSelected(_:)),
                                       keyEquivalent: ""))
            }
        } else if let group = selectedGroup {
            if let proj = group.project {
                menu.addItem(NSMenuItem(title: "Close All in “\(proj.name)”",
                                       action: #selector(closeSelectedGroup(_:)),
                                       keyEquivalent: ""))
                menu.addItem(.separator())
                menu.addItem(NSMenuItem(title: "Disassociate All from “\(proj.name)”",
                                       action: #selector(disassociateSelectedGroup(_:)),
                                       keyEquivalent: ""))
            }
            _ = group
        }
        menu.items.forEach { $0.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: outlineView)
    }

    @objc private func bringSelectedToFront(_ sender: Any?) {
        selectedTerminal?.window()?.makeKeyAndOrderFront(nil)
    }

    @objc private func closeAndArchiveSelected(_ sender: Any?) {
        guard let terminal = selectedTerminal,
              let project  = iTermWindowProjectsModel.shared.project(for: terminal) else { return }
        let keepJobs = NSEvent.modifierFlags.contains(.option)
        iTermWindowProjectsModel.shared.archiveWindow(terminal, to: project, andClose: true, keepJobsRunning: keepJobs)
    }

    @objc private func disassociateSelected(_ sender: Any?) {
        guard let terminal = selectedTerminal else { return }
        iTermWindowProjectsModel.shared.disassociateWindow(terminal)
    }

    @objc private func closeSelectedGroup(_ sender: Any?) {
        guard let proj = selectedGroup?.project else { return }
        let keepJobs = NSEvent.modifierFlags.contains(.option)
        iTermWindowProjectsModel.shared.closeProject(proj, keepJobsRunning: keepJobs)
    }

    @objc private func disassociateSelectedGroup(_ sender: Any?) {
        guard let group = selectedGroup else { return }
        for terminal in group.terminals {
            iTermWindowProjectsModel.shared.disassociateWindow(terminal)
        }
    }

    // MARK: Drag Source (right → left: archive; right → right: reassign)

    func outlineView(_ outlineView: NSOutlineView,
                     pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        if let terminal = item as? PseudoTerminal {
            guard let wn = terminal.window()?.windowNumber, wn > 0 else { return nil }
            let pb = NSPasteboardItem()
            pb.setString(String(wn), forType: kLiveWindowDragType)
            return pb
        }
        if let group = item as? iTermOpenProjectGroup, let proj = group.project {
            let pb = NSPasteboardItem()
            pb.setString(proj.id.uuidString, forType: kProjectGroupDragType)
            return pb
        }
        return nil
    }

    // MARK: Drop Destination (left → right: restore; right → right: reassign/disassociate)

    func outlineView(_ outlineView: NSOutlineView,
                     validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        let pb = info.draggingPasteboard

        // Live window from right dropped on a group → reassign or disassociate
        if pb.availableType(from: [kLiveWindowDragType]) != nil {
            if item is iTermOpenProjectGroup || item == nil {
                return .link
            }
            // Redirect drops on terminal children to the parent group
            if let terminal = item as? PseudoTerminal,
               let parentGroup = groups.first(where: { $0.terminals.contains { $0 === terminal } }) {
                outlineView.setDropItem(parentGroup, dropChildIndex: NSOutlineViewDropOnItemIndex)
                return .link
            }
            return []
        }

        // Archived window from left → restore anywhere in the right pane
        if pb.availableType(from: [kArchivedWindowDragType]) != nil {
            outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .copy
        }

        // Project from left → restore all, anywhere in the right pane
        if pb.availableType(from: [kProjectDragType]) != nil {
            outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .copy
        }

        return []
    }

    func outlineView(_ outlineView: NSOutlineView,
                     acceptDrop info: NSDraggingInfo,
                     item: Any?,
                     childIndex index: Int) -> Bool {
        let pb = info.draggingPasteboard

        // Live window → reassign or disassociate
        if let wnStr = pb.string(forType: kLiveWindowDragType), let wn = Int(wnStr) {
            let all = (iTermController.sharedInstance().terminals() as? [PseudoTerminal]) ?? []
            guard let terminal = all.first(where: { $0.window()?.windowNumber == wn }) else {
                return false
            }
            if let group = item as? iTermOpenProjectGroup, let proj = group.project {
                iTermWindowProjectsModel.shared.associateWindow(terminal, with: proj)
            } else {
                // Dropped on "Unassociated" group or root → disassociate
                iTermWindowProjectsModel.shared.disassociateWindow(terminal)
            }
            return true
        }

        // Archived window → restore (and remove archive entry)
        if let uuidStr = pb.string(forType: kArchivedWindowDragType),
           let uuid    = UUID(uuidString: uuidStr),
           let (archived, project) = iTermWindowProjectsModel.shared.archivedWindow(id: uuid) {
            iTermWindowProjectsModel.shared.restoreWindow(archived)
            iTermWindowProjectsModel.shared.removeWindow(archived, from: project)
            return true
        }

        // Project → restore all
        if let uuidStr = pb.string(forType: kProjectDragType),
           let uuid    = UUID(uuidString: uuidStr),
           let project = iTermWindowProjectsModel.shared.project(id: uuid) {
            iTermWindowProjectsModel.shared.restoreAllWindows(in: project)
            return true
        }

        return false
    }

    // MARK: Hover Preview

    override func mouseMoved(with event: NSEvent) {
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row   = outlineView.row(at: point)
        if row == previewRow { return }
        cancelPreview()
        guard row >= 0 else { return }
        previewRow = row
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.showPreview(forRow: row)
        }
    }

    override func mouseExited(with event: NSEvent) { cancelPreview() }

    private func cancelPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        previewRow   = -1
        previewPopover.close()
    }

    private func showPreview(forRow row: Int) {
        guard let terminal = outlineView.item(atRow: row) as? PseudoTerminal,
              let nsWindow  = terminal.window(),
              nsWindow.windowNumber > 0 else { return }
        let rowRect = outlineView.rect(ofRow: row)
        guard rowRect != .zero else { return }
        showLivePreview(windowNumber: CGWindowID(nsWindow.windowNumber),
                        anchor: rowRect,
                        preferredEdge: .minX)
    }

    private func showLivePreview(windowNumber: CGWindowID,
                                  anchor: NSRect,
                                  preferredEdge: NSRectEdge) {
        let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowNumber,
            [.boundsIgnoreFraming, .bestResolution])
        guard let cgImage else { return }
        let img      = NSImage(cgImage: cgImage, size: .zero)
        let aspectW: CGFloat = 320
        let aspectH  = cgImage.height == 0 ? 200
                       : aspectW * CGFloat(cgImage.height) / CGFloat(cgImage.width)
        let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: aspectW, height: min(aspectH, 240)))
        iv.image        = img
        iv.imageScaling = .scaleProportionallyUpOrDown

        let vc     = NSViewController()
        vc.view    = iv
        previewPopover.contentViewController = vc
        previewPopover.contentSize = iv.frame.size
        previewPopover.show(relativeTo: anchor, of: outlineView, preferredEdge: preferredEdge)
    }

    // MARK: Cell Factories

    private func makeGroupCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.imageScaling = .scaleProportionallyDown
        cell.imageView = iv

        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.lineBreakMode = .byTruncatingTail
        tf.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
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

/// The left pane uses this to show live-window previews (screenshots).
private extension iTermProjectsOutlineController {
    func showLivePreview(windowNumber: CGWindowID, anchor: NSRect, preferredEdge: NSRectEdge) {
        let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowNumber,
            [.boundsIgnoreFraming, .bestResolution])
        guard let cgImage else { return }
        let img      = NSImage(cgImage: cgImage, size: .zero)
        let aspectW: CGFloat = 320
        let aspectH  = cgImage.height == 0 ? 200
                       : aspectW * CGFloat(cgImage.height) / CGFloat(cgImage.width)
        let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: aspectW, height: min(aspectH, 240)))
        iv.image        = img
        iv.imageScaling = .scaleProportionallyUpOrDown
        let vc  = NSViewController()
        vc.view = iv
        previewPopover.contentViewController = vc
        previewPopover.contentSize = iv.frame.size
        previewPopover.show(relativeTo: anchor, of: outlineView, preferredEdge: preferredEdge)
    }
}

private func makeSectionHeader(_ title: String) -> NSView {
    let box = NSView()
    let tf  = NSTextField(labelWithString: title)
    tf.font      = NSFont.systemFont(ofSize: 10, weight: .semibold)
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
    button.bezelStyle  = .inline
    button.controlSize = .small
    button.toolTip     = tip
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
    tf.stringValue       = initial
    tf.placeholderString = prompt
    alert.accessoryView  = tf
    alert.window.initialFirstResponder = tf
    if alert.runModal() == .alertFirstButtonReturn {
        let name = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { completion(name) }
    }
}
