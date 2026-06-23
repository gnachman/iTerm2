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

// MARK: - Drag payload + drop-overlay zones

/// What a drag is carrying, classified once when the drag begins (from the dragged
/// model items) so the split controller can decide which drop overlay — if any — to
/// show on the destination pane. See iTermProjectsSplitViewController.dragDidBegin.
enum iTermProjectsDragPayload {
    case liveWindows([PseudoTerminal])               // open windows (right pane)
    case projectGroups([iTermWindowProject])          // right-pane project group(s)
    case archivedWindows([iTermArchivedWindowBox])    // saved windows (left pane)
    case projects([iTermWindowProject])               // left-pane project(s)
    case other
}

/// LEFT-pane overlay: drag an associated open window (or project group) here to
/// Archive (close + save, process dies) or Detach (close + save, keep process). Archive
/// is the large default target; Detach is the smaller, special band.
private let kArchiveDetachZones: [iTermProjectsDropZone] = [
    iTermProjectsDropZone(id: "archive", title: "Archive (close)",
                          symbol: "archivebox", fraction: 0.75, operation: .move),
    iTermProjectsDropZone(id: "detach", title: "Detach (keep running)",
                          symbol: "bolt.horizontal.circle", fraction: 0.25, operation: .move),
]
private let kArchiveDetachDragTypes = [kLiveWindowDragType, kProjectGroupDragType]

/// RIGHT-pane overlay: drag a saved window (or project) here to Restore it.
private let kRestoreZones: [iTermProjectsDropZone] = [
    iTermProjectsDropZone(id: "restore", title: "Restore",
                          symbol: "arrow.up.left.and.arrow.down.right",
                          fraction: 1.0, operation: .copy),
]
private let kRestoreDragTypes = [kArchivedWindowDragType, kProjectDragType]

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

final class iTermProjectsSplitViewController: NSSplitViewController, iTermProjectsDropOverlayDelegate {
    let projectsVC = iTermProjectsOutlineController()
    let windowsVC  = iTermOpenWindowsController()

    /// The payload of the in-flight drag, captured when it begins so the overlay's
    /// drop handler can act on the real model objects (not re-parse the pasteboard).
    private var pendingPayload: iTermProjectsDragPayload = .other

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .paneSplitter

        projectsVC.onSelectionChange = { [weak self] in
            self?.windowsVC.updateActionButtons()
        }
        windowsVC.projectsController = projectsVC
        projectsVC.splitController = self
        windowsVC.splitController  = self

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

    // MARK: Drop-overlay coordination

    /// Called by either outline controller when a drag begins. Decides which drop
    /// overlay (if any) to show on the *other* pane, based on the drag's payload and
    /// origin. When no overlay is shown, the destination outline's own row-drop
    /// handlers stay active (e.g. drop an unassociated window on a project = associate).
    func dragDidBegin(_ payload: iTermProjectsDragPayload, from source: NSViewController) {
        pendingPayload = payload
        if source === windowsVC {
            // Right → left: only associated windows / project groups get the
            // Archive|Detach overlay. Unassociated windows fall through to the left
            // pane's row-drop (= associate onto a project).
            switch payload {
            case .liveWindows(let terminals):
                let associated = terminals.filter {
                    iTermWindowProjectsModel.shared.project(for: $0) != nil
                }
                guard !associated.isEmpty else { return }
                pendingPayload = .liveWindows(associated)
                projectsVC.showDropOverlay(zones: kArchiveDetachZones,
                                           dragTypes: kArchiveDetachDragTypes,
                                           delegate: self)
            case .projectGroups(let projects) where !projects.isEmpty:
                projectsVC.showDropOverlay(zones: kArchiveDetachZones,
                                           dragTypes: kArchiveDetachDragTypes,
                                           delegate: self)
            default:
                break
            }
        } else if source === projectsVC {
            // Left → right: saved windows / projects get the Restore overlay.
            switch payload {
            case .archivedWindows(let boxes) where !boxes.isEmpty:
                windowsVC.showDropOverlay(zones: kRestoreZones,
                                          dragTypes: kRestoreDragTypes,
                                          delegate: self)
            case .projects(let projects) where !projects.isEmpty:
                windowsVC.showDropOverlay(zones: kRestoreZones,
                                          dragTypes: kRestoreDragTypes,
                                          delegate: self)
            default:
                break
            }
        }
    }

    func dragDidEnd() {
        projectsVC.removeDropOverlay()
        windowsVC.removeDropOverlay()
        pendingPayload = .other
    }

    // MARK: iTermProjectsDropOverlayDelegate

    func dropOverlay(_ overlay: iTermProjectsDropOverlay,
                     didDropZone zone: iTermProjectsDropZone,
                     info: NSDraggingInfo) -> Bool {
        let model = iTermWindowProjectsModel.shared
        switch zone.id {
        case "archive", "detach":
            let keepJobs = (zone.id == "detach")
            switch pendingPayload {
            case .liveWindows(let terminals):
                for terminal in terminals {
                    guard let project = model.project(for: terminal) else { continue }
                    model.archiveWindow(terminal, to: project, andClose: true, keepJobsRunning: keepJobs)
                }
            case .projectGroups(let projects):
                for project in projects {
                    model.closeProject(project, keepJobsRunning: keepJobs)
                }
            default:
                return false
            }
            reloadAll()
            return true
        case "restore":
            switch pendingPayload {
            case .archivedWindows(let boxes):
                for box in boxes { model.restoreWindow(box.window) }
            case .projects(let projects):
                for project in projects { model.restoreAllWindows(in: project) }
            default:
                return false
            }
            reloadAll()
            return true
        default:
            return false
        }
    }
}

// MARK: - Left Pane: Project Tree (open + archived windows)

final class iTermProjectsOutlineController: NSViewController,
                                             NSOutlineViewDataSource,
                                             NSOutlineViewDelegate {
    var onSelectionChange: (() -> Void)?
    weak var splitController: iTermProjectsSplitViewController?
    private var dropOverlay: iTermProjectsDropOverlay?

    private(set) var outlineView = NSOutlineView()
    private var scrollView       = NSScrollView()
    var addProjectButton    = NSButton()
    var addSubprojectButton = NSButton()
    var deleteButton        = NSButton()
    var restoreButton       = NSButton()
    var closeProjectButton  = NSButton()
    var freezeProjectButton = NSButton()

    private var sortOrder   = ProjectSortOrder.recent
    private var sortSegment = NSSegmentedControl()

    // Hover preview (pinned to the left so it never covers the right pane)
    private let preview = iTermProjectsSidePreview(side: .left)
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

    /// All selected items of a given kind (multi-select).
    private func selectedItems<T>(_ type: T.Type) -> [T] {
        outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) as? T }
    }
    var selectedProjects: [iTermWindowProject]       { selectedItems(iTermWindowProject.self) }
    var selectedArchivedBoxes: [iTermArchivedWindowBox] { selectedItems(iTermArchivedWindowBox.self) }
    var selectedLiveBoxes: [iTermLiveWindowBox]      { selectedItems(iTermLiveWindowBox.self) }

    /// Number of saved windows the current selection would restore. A selected project
    /// contributes its own saved windows (restoreAllWindows is non-recursive); archived
    /// rows count as one each. Drives the Restore button's count label.
    private var restorableSelectionCount: Int {
        selectedArchivedBoxes.count + selectedProjects.reduce(0) { $0 + $1.windows.count }
    }

    /// Projects whose *open* windows the Archive All / Detach All buttons act on: the
    /// selected projects plus the projects of any directly-selected open windows; or —
    /// only when nothing at all is selected — every project. Returns empty when the
    /// selection contains only saved (closed/detached) windows, so the buttons stay off
    /// (there's nothing open to archive or detach).
    private var archiveDetachTargetProjects: [iTermWindowProject] {
        let projects     = selectedProjects
        let liveProjects = selectedLiveBoxes.map { $0.project }
        if !projects.isEmpty || !liveProjects.isEmpty {
            var seen = Set<UUID>()
            return (projects + liveProjects).filter { seen.insert($0.id).inserted }
        }
        return outlineView.selectedRowIndexes.isEmpty
            ? iTermWindowProjectsModel.shared.rootProjects
            : []
    }

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupOutlineView()
        setupBottomBar()
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
        outlineView.allowsMultipleSelection = true
        outlineView.focusRingType   = .none
        outlineView.doubleAction    = #selector(doubleClicked(_:))
        outlineView.target          = self

        // Drag source + destination. (Project-group drags from the right pane are
        // handled by the Archive|Detach overlay, not a row drop here.)
        outlineView.setDraggingSourceOperationMask(.every, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.every, forLocal: false)
        outlineView.registerForDraggedTypes([kLiveWindowDragType,
                                             kArchivedWindowDragType])

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

        configure(&addProjectButton,    label: "+",           tip: "New project", target: self,
                  action: #selector(addProject(_:)))
        configure(&addSubprojectButton, label: "+sub",        tip: "New sub-project under selection", target: self,
                  action: #selector(addSubproject(_:)))
        configure(&deleteButton,        label: "−",           tip: "Delete selection", target: self,
                  action: #selector(deleteSelected(_:)))
        configure(&restoreButton,       label: "Restore All…", tip: "Restore the selected saved windows (or all of them if nothing is selected)", target: self,
                  action: #selector(restoreSelected(_:)))
        configure(&closeProjectButton,  label: "Archive All", tip: "Close and archive all open windows in the selected project(s)", target: self,
                  action: #selector(closeSelectedProject(_:)))
        configure(&freezeProjectButton, label: "Detach All",  tip: "Close and archive all open windows in the selected project(s), keeping their jobs running", target: self,
                  action: #selector(freezeSelectedProjectAndKeepJobs(_:)))

        let spacer = NSView()
        let stack  = NSStackView(views: [addProjectButton, addSubprojectButton, deleteButton,
                                         spacer,
                                         restoreButton, closeProjectButton, freezeProjectButton])
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

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelChanged(_:)),
            name: iTermWindowProjectsModel.didChangeNotification,
            object: nil)
    }

    func reload() {
        outlineView.reloadData()
        updateButtons()
    }

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
            let (detached, closed) = Self.savedCounts(project)
            // Distinguish saved windows by state; omit any zero category.
            let parts = [liveCount > 0 ? "\(liveCount) open" : nil,
                         detached > 0 ? "\(detached) detached" : nil,
                         closed   > 0 ? "\(closed) closed"     : nil].compactMap { $0 }
            let suffix = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
            cell.textField?.stringValue = project.name + suffix
            cell.textField?.font        = .systemFont(ofSize: NSFont.systemFontSize)
            cell.textField?.textColor   = .labelColor
            cell.imageView?.image       = NSImage(systemSymbolName: "folder",
                                                  accessibilityDescription: nil)

        } else if let liveBox = item as? iTermLiveWindowBox {
            let title = liveBox.terminal.ptyWindow()?.title ?? "Window"
            cell.textField?.stringValue = title
            cell.textField?.font        = .boldSystemFont(ofSize: NSFont.systemFontSize)
            cell.textField?.textColor   = .labelColor
            cell.imageView?.image       = NSImage(systemSymbolName: "terminal.fill",
                                                  accessibilityDescription: nil)

        } else if let box = item as? iTermArchivedWindowBox {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let age = formatter.localizedString(for: box.window.timestamp, relativeTo: Date())

            // A saved window whose process is still alive is “detached”; otherwise “closed”.
            let isRunning = box.window.isOrphanedAndRunning
            let state = isRunning ? "Detached" : "Closed"
            cell.textField?.stringValue = "\(box.window.name)  \(age) · \(state)"
            cell.textField?.font        = .systemFont(ofSize: NSFont.systemFontSize)
            cell.textField?.textColor   = isRunning ? .labelColor : .secondaryLabelColor

            let iconName = isRunning ? "terminal.fill" : "terminal"
            cell.imageView?.image       = NSImage(systemSymbolName: iconName,
                                                  accessibilityDescription: nil)
        }
        return cell
    }

    /// (detached, closed) saved-window counts for a project and all descendants.
    /// detached = process still alive (`isOrphanedAndRunning`); closed = the rest.
    static func savedCounts(_ project: iTermWindowProject) -> (detached: Int, closed: Int) {
        var detached = 0, closed = 0
        func walk(_ p: iTermWindowProject) {
            for w in p.windows {
                if w.isOrphanedAndRunning { detached += 1 } else { closed += 1 }
            }
            p.children.forEach(walk)
        }
        walk(project)
        return (detached, closed)
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
            liveBox.terminal.ptyWindow()?.makeKeyAndOrderFront(nil)
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
        let model    = iTermWindowProjectsModel.shared
        let boxes    = selectedArchivedBoxes
        let projects = selectedProjects
        guard !boxes.isEmpty || !projects.isEmpty else { return }

        if !projects.isEmpty {
            let alert = NSAlert()
            alert.messageText = projects.count == 1
                ? "Delete “\(projects[0].name)”?"
                : "Delete \(projects.count) projects?"
            alert.informativeText = "This removes the project(s) and all their saved windows. Open windows are unaffected."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            alert.buttons[0].hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            for project in projects { model.deleteProject(project) }
        }
        for box in boxes { model.removeWindow(box.window, from: box.project) }
        reload()
    }

    /// Restores the current selection (saved windows and/or whole projects). With no
    /// selection, confirms then restores every saved window in every project.
    @objc func restoreSelected(_ sender: Any?) {
        let model    = iTermWindowProjectsModel.shared
        let boxes    = selectedArchivedBoxes
        let projects = selectedProjects
        if boxes.isEmpty && projects.isEmpty {
            let alert = NSAlert()
            alert.messageText     = "Restore all saved windows?"
            alert.informativeText = "Nothing is selected. This will restore every saved window in every project."
            alert.addButton(withTitle: "Restore All")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            for project in model.rootProjects { model.restoreAllWindows(in: project) }
            reload()
            return
        }
        for box in boxes { model.restoreWindow(box.window) }
        for project in projects { model.restoreAllWindows(in: project) }
        reload()
    }

    @objc private func closeSelectedProject(_ sender: Any?) {
        archiveOrDetachSelectedProjects(keepJobs: false)
    }

    @objc private func freezeSelectedProjectAndKeepJobs(_ sender: Any?) {
        archiveOrDetachSelectedProjects(keepJobs: true)
    }

    /// Archives (keepJobs=false) or detaches (keepJobs=true) every open window in the
    /// selected project(s) — or, if no project is selected, across all projects.
    private func archiveOrDetachSelectedProjects(keepJobs: Bool) {
        let model   = iTermWindowProjectsModel.shared
        let targets = archiveDetachTargetProjects.filter { model.hasLiveWindows(for: $0) }
        guard !targets.isEmpty else {
            showAlert("No open windows are associated with the selected project(s).")
            return
        }
        for project in targets { model.closeProject(project, keepJobsRunning: keepJobs) }
        reload()
    }

    @objc private func detachLiveWindow(_ sender: Any?) {
        let boxes = selectedLiveBoxes
        guard !boxes.isEmpty else { return }
        for box in boxes {
            iTermWindowProjectsModel.shared.archiveWindow(box.terminal,
                                                          to: box.project,
                                                          andClose: true,
                                                          keepJobsRunning: true)
        }
        reload()
    }

    // MARK: Context Menu

    override func rightMouseDown(with event: NSEvent) {
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row   = outlineView.row(at: point)
        guard row >= 0 else { super.rightMouseDown(with: event); return }
        // Keep an existing multi-selection if the clicked row is part of it; otherwise
        // select just the clicked row.
        if !outlineView.selectedRowIndexes.contains(row) {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        let clicked = outlineView.item(atRow: row)
        let menu = NSMenu()
        if clicked is iTermArchivedWindowBox {
            menu.addItem(NSMenuItem(title: "Restore",
                                   action: #selector(restoreSelected(_:)),
                                   keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Remove from Project",
                                   action: #selector(deleteSelected(_:)),
                                   keyEquivalent: ""))
        } else if clicked is iTermLiveWindowBox {
            menu.addItem(NSMenuItem(title: "Bring to Front",
                                   action: #selector(bringLiveWindowToFront(_:)),
                                   keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Archive (close)",
                                   action: #selector(archiveLiveWindow(_:)),
                                   keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Detach (keep running)",
                                   action: #selector(detachLiveWindow(_:)),
                                   keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Disassociate from Project",
                                   action: #selector(disassociateLiveWindow(_:)),
                                   keyEquivalent: ""))
        } else if let project = clicked as? iTermWindowProject {
            menu.addItem(NSMenuItem(title: "Restore",
                                   action: #selector(restoreSelected(_:)),
                                   keyEquivalent: ""))
            if iTermWindowProjectsModel.shared.hasLiveWindows(for: project) {
                menu.addItem(NSMenuItem(title: "Archive All Open Windows",
                                       action: #selector(closeSelectedProject(_:)),
                                       keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Detach All (Keep Jobs Running)",
                                       action: #selector(freezeSelectedProjectAndKeepJobs(_:)),
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
        for box in selectedLiveBoxes {
            box.terminal.ptyWindow()?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func archiveLiveWindow(_ sender: Any?) {
        let boxes = selectedLiveBoxes
        guard !boxes.isEmpty else { return }
        for box in boxes {
            iTermWindowProjectsModel.shared.archiveWindow(box.terminal,
                                                          to: box.project,
                                                          andClose: true,
                                                          keepJobsRunning: false)
        }
        reload()
    }

    @objc private func disassociateLiveWindow(_ sender: Any?) {
        for box in selectedLiveBoxes {
            iTermWindowProjectsModel.shared.disassociateWindow(box.terminal)
        }
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
            guard let wn = box.terminal.ptyWindow()?.windowNumber, wn > 0 else { return nil }
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

    /// The project a drop targets: the row itself if it's a project, or the owning
    /// project if the row is one of its window leaves. Used to force whole-project drop
    /// targeting (no confusing between-rows insertion lines).
    private func projectDropTarget(for item: Any?) -> iTermWindowProject? {
        if let project = item as? iTermWindowProject { return project }
        if let box = item as? iTermArchivedWindowBox { return box.project }
        if let box = item as? iTermLiveWindowBox      { return box.project }
        return nil
    }

    func outlineView(_ outlineView: NSOutlineView,
                     validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        let pb = info.draggingPasteboard
        // Live windows (associate) and archived windows (move between projects) may only
        // be dropped ONTO a project. Retarget to the whole project so there's never a
        // between-rows insertion line.
        let accepts = pb.availableType(from: [kLiveWindowDragType]) != nil
                   || pb.availableType(from: [kArchivedWindowDragType]) != nil
        guard accepts, let project = projectDropTarget(for: item) else { return [] }
        outlineView.setDropItem(project, dropChildIndex: NSOutlineViewDropOnItemIndex)
        // Use .link so the cursor shows the same redirect-arrow badge as the right pane.
        return .link
    }

    func outlineView(_ outlineView: NSOutlineView,
                     acceptDrop info: NSDraggingInfo,
                     item: Any?,
                     childIndex index: Int) -> Bool {
        let model = iTermWindowProjectsModel.shared
        guard let project = projectDropTarget(for: item) else { return false }

        // Live window(s) onto a project → associate (keep open).
        let wnStrings = info.allStrings(forType: kLiveWindowDragType)
        if !wnStrings.isEmpty {
            let numbers  = Set(wnStrings.compactMap { Int($0) })
            let all      = iTermController.sharedInstance().terminals() ?? []
            let dragged  = all.filter { numbers.contains($0.ptyWindow()?.windowNumber ?? -1) }
            for terminal in dragged { model.associateWindow(terminal, with: project) }
            return !dragged.isEmpty
        }

        // Archived window(s) onto a project → move between projects.
        let uuidStrings = info.allStrings(forType: kArchivedWindowDragType)
        if !uuidStrings.isEmpty {
            var moved = false
            for s in uuidStrings {
                guard let uuid = UUID(uuidString: s),
                      let (archived, oldProject) = model.archivedWindow(id: uuid) else { continue }
                oldProject.windows.removeAll { $0.id == archived.id }
                project.windows.append(archived)
                moved = true
            }
            if moved { model.save() }
            return moved
        }

        return false
    }

    // MARK: Drag session → drop overlays

    func outlineView(_ outlineView: NSOutlineView,
                     draggingSession session: NSDraggingSession,
                     willBeginAt screenPoint: NSPoint,
                     forItems draggedItems: [Any]) {
        let boxes    = draggedItems.compactMap { $0 as? iTermArchivedWindowBox }
        let projects = draggedItems.compactMap { $0 as? iTermWindowProject }
        let payload: iTermProjectsDragPayload
        if !boxes.isEmpty {
            payload = .archivedWindows(boxes)
        } else if !projects.isEmpty {
            payload = .projects(projects)
        } else {
            payload = .other
        }
        splitController?.dragDidBegin(payload, from: self)
    }

    func outlineView(_ outlineView: NSOutlineView,
                     draggingSession session: NSDraggingSession,
                     endedAt screenPoint: NSPoint,
                     operation: NSDragOperation) {
        splitController?.dragDidEnd()
    }

    func showDropOverlay(zones: [iTermProjectsDropZone],
                         dragTypes: [NSPasteboard.PasteboardType],
                         delegate: iTermProjectsDropOverlayDelegate) {
        removeDropOverlay()
        let overlay = iTermProjectsDropOverlay(zones: zones, dragTypes: dragTypes)
        overlay.delegate = delegate
        overlay.frame = scrollView.frame
        view.addSubview(overlay, positioned: .above, relativeTo: scrollView)
        dropOverlay = overlay
    }

    func removeDropOverlay() {
        dropOverlay?.removeFromSuperview()
        dropOverlay = nil
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
        preview.close()
    }

    private func showPreview(forRow row: Int) {
        let item = outlineView.item(atRow: row)

        if let box = item as? iTermArchivedWindowBox {
            let rowRect = outlineView.rect(ofRow: row)
            guard rowRect != .zero else { return }
            let fileURL = iTermWindowProjectsModel.thumbnailURL(for: box.window.id)
            if FileManager.default.fileExists(atPath: fileURL.path),
               let img = NSImage(contentsOf: fileURL) {
                // Display at a fixed 320pt width, height from the image's aspect ratio
                // (so the higher-resolution saved PNG stays crisp without distorting).
                let aspectH = img.size.width > 0 ? 320 * img.size.height / img.size.width : 200
                let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: 320, height: min(aspectH, 240)))
                iv.image = img
                iv.imageScaling = .scaleProportionallyUpOrDown
                preview.show(iv, rowRect: rowRect, anchorView: outlineView)
            } else if let arrangement = box.window.arrangement {
                let pv = ArrangementPreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
                pv.setArrangement([arrangement as Any])
                preview.show(pv, rowRect: rowRect, anchorView: outlineView)
            }
            return
        }

        if let liveBox = item as? iTermLiveWindowBox,
           let nsWindow = liveBox.terminal.ptyWindow(),
           nsWindow.windowNumber > 0 {
            showLivePreview(windowNumber: CGWindowID(nsWindow.windowNumber),
                            rowRect: outlineView.rect(ofRow: row))
        }
    }

    // MARK: Notifications

    @objc private func modelChanged(_ note: Notification) { reload() }

    // MARK: Helpers

    private var anyProjectHasLiveWindows: Bool {
        return iTermWindowProjectsModel.shared.rootProjects.contains { p in
            iTermWindowProjectsModel.shared.hasLiveWindows(for: p)
        }
    }

    private var anyProjectHasArchivedWindows: Bool {
        return iTermWindowProjectsModel.shared.rootProjects.contains { p in
            p.totalWindowCount > 0
        }
    }

    private func updateButtons() {
        let projects    = selectedProjects
        let hasArchived = !selectedArchivedBoxes.isEmpty

        addSubprojectButton.isEnabled = projects.count == 1   // one parent for the new sub-project
        deleteButton.isEnabled        = !projects.isEmpty || hasArchived

        // Single Restore button: label carries the count; empty selection restores all.
        let count = restorableSelectionCount
        switch count {
        case 0:
            restoreButton.title     = "Restore All…"
            restoreButton.isEnabled = anyProjectHasArchivedWindows
        case 1:
            restoreButton.title     = "Restore"
            restoreButton.isEnabled = true
        default:
            restoreButton.title     = "Restore \(count)"
            restoreButton.isEnabled = true
        }

        // Archive All / Detach All only when the effective target projects actually
        // have open windows (selecting only closed windows leaves them off).
        let model   = iTermWindowProjectsModel.shared
        let hasLive = archiveDetachTargetProjects.contains { model.hasLiveWindows(for: $0) }
        closeProjectButton.isEnabled  = hasLive
        freezeProjectButton.isEnabled = hasLive
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

// MARK: - Right Pane: Open Windows (grouped by project)

final class iTermOpenWindowsController: NSViewController,
                                         NSOutlineViewDataSource,
                                         NSOutlineViewDelegate {
    weak var projectsController: iTermProjectsOutlineController?
    weak var splitController: iTermProjectsSplitViewController?
    private var dropOverlay: iTermProjectsDropOverlay?

    private var outlineView  = NSOutlineView()
    private var scrollView   = NSScrollView()
    private var associateButton = NSButton()
    private var archiveButton   = NSButton()
    private var detachButton    = NSButton()
    private var statusLabel     = NSTextField(labelWithString: "")

    // Hover preview
    private let preview = iTermProjectsSidePreview(side: .right)
    private var previewTimer: Timer?
    private var previewRow = -1

    private var groups: [iTermOpenProjectGroup] = []

    private var terminals: [PseudoTerminal] {
        iTermController.sharedInstance().terminals() ?? []
    }

    var selectedTerminal: PseudoTerminal? {
        outlineView.item(atRow: outlineView.selectedRow) as? PseudoTerminal
    }
    var selectedGroup: iTermOpenProjectGroup? {
        outlineView.item(atRow: outlineView.selectedRow) as? iTermOpenProjectGroup
    }

    /// All selected items of a given kind (multi-select).
    private func selectedItems<T>(_ type: T.Type) -> [T] {
        outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) as? T }
    }
    var selectedTerminals: [PseudoTerminal]        { selectedItems(PseudoTerminal.self) }
    var selectedGroups: [iTermOpenProjectGroup]    { selectedItems(iTermOpenProjectGroup.self) }

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupOutlineView()
        setupBottomBar()
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

        let projectGroups = byProjectID.values
            .sorted { $0.project.name.localizedCaseInsensitiveCompare($1.project.name) == .orderedAscending }
            .map { iTermOpenProjectGroup(project: $0.project, terminals: $0.terminals) }

        // The Unassociated group is always present and pinned on top: it doubles as the
        // disassociate drop target (drag an associated window onto it), so it must exist
        // even when empty. Dropping into empty space no longer disassociates.
        groups = [iTermOpenProjectGroup(project: nil, terminals: unassociated)] + projectGroups
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
        outlineView.allowsMultipleSelection = true
        outlineView.focusRingType   = .none

        // Drag source + destination. (Saved-window / project drags from the left pane
        // are handled by the Restore overlay, not a row drop here — so this pane only
        // registers the live-window type for in-pane reassign/disassociate.)
        outlineView.setDraggingSourceOperationMask(.every, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.every, forLocal: false)
        outlineView.registerForDraggedTypes([kLiveWindowDragType])

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
                  tip: "Mark the selected open window(s) as belonging to the selected project",
                  target: self,
                  action: #selector(associateSelected(_:)))

        configure(&archiveButton,
                  label: "Archive",
                  tip: "Close and archive the selected open window(s) into their project",
                  target: self,
                  action: #selector(archiveSelected(_:)))

        configure(&detachButton,
                  label: "Detach",
                  tip: "Close and archive the selected open window(s) into their project, keeping their jobs running",
                  target: self,
                  action: #selector(detachSelected(_:)))

        let stack = NSStackView(views: [statusLabel, NSView(), detachButton, archiveButton, associateButton])
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
        let terminals  = selectedTerminals
        let hasProject = projectsController?.selectedProject != nil
        associateButton.isEnabled = !terminals.isEmpty && hasProject
        // Archive/Detach act on a window's own project, so they need at least one
        // selected window that is already associated.
        let anyAssociated = terminals.contains {
            iTermWindowProjectsModel.shared.project(for: $0) != nil
        }
        archiveButton.isEnabled = anyAssociated
        detachButton.isEnabled  = anyAssociated
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
                cell.textField?.stringValue = count == 0 ? "Unassociated" : "Unassociated  \(countStr)"
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
            cell.textField?.stringValue = terminal.ptyWindow()?.title ?? "Window"
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
        guard let project = projectsController?.selectedProject else { return }
        let terminals = selectedTerminals
        guard !terminals.isEmpty else { return }
        for terminal in terminals {
            iTermWindowProjectsModel.shared.associateWindow(terminal, with: project)
        }
        reload()
        projectsController?.reload()
    }

    // MARK: Context Menu

    override func rightMouseDown(with event: NSEvent) {
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row   = outlineView.row(at: point)
        guard row >= 0 else { super.rightMouseDown(with: event); return }
        // Keep an existing multi-selection if the clicked row is part of it.
        if !outlineView.selectedRowIndexes.contains(row) {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        let clicked = outlineView.item(atRow: row)
        let menu = NSMenu()
        if clicked is PseudoTerminal {
            menu.addItem(NSMenuItem(title: "Bring to Front",
                                   action: #selector(bringSelectedToFront(_:)),
                                   keyEquivalent: ""))
            // Show archive/detach only if at least one selected window is associated.
            let anyAssociated = selectedTerminals.contains {
                iTermWindowProjectsModel.shared.project(for: $0) != nil
            }
            if anyAssociated {
                menu.addItem(.separator())
                menu.addItem(NSMenuItem(title: "Archive (close)",
                                       action: #selector(archiveSelected(_:)),
                                       keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Detach (keep running)",
                                       action: #selector(detachSelected(_:)),
                                       keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Disassociate from Project",
                                       action: #selector(disassociateSelected(_:)),
                                       keyEquivalent: ""))
            }
        } else if let proj = (clicked as? iTermOpenProjectGroup)?.project {
            menu.addItem(NSMenuItem(title: "Archive All in “\(proj.name)”",
                                   action: #selector(closeSelectedGroup(_:)),
                                   keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Detach All in “\(proj.name)” (Keep Jobs)",
                                   action: #selector(freezeSelectedGroupAndKeepJobs(_:)),
                                   keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Disassociate All from “\(proj.name)”",
                                   action: #selector(disassociateSelectedGroup(_:)),
                                   keyEquivalent: ""))
        }
        menu.items.forEach { $0.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: outlineView)
    }

    @objc private func bringSelectedToFront(_ sender: Any?) {
        for terminal in selectedTerminals {
            terminal.ptyWindow()?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func archiveSelected(_ sender: Any?) {
        archiveOrDetachSelectedWindows(keepJobs: false)
    }

    @objc private func detachSelected(_ sender: Any?) {
        archiveOrDetachSelectedWindows(keepJobs: true)
    }

    private func archiveOrDetachSelectedWindows(keepJobs: Bool) {
        let model = iTermWindowProjectsModel.shared
        for terminal in selectedTerminals {
            guard let project = model.project(for: terminal) else { continue }
            model.archiveWindow(terminal, to: project, andClose: true, keepJobsRunning: keepJobs)
        }
    }

    @objc private func disassociateSelected(_ sender: Any?) {
        for terminal in selectedTerminals {
            iTermWindowProjectsModel.shared.disassociateWindow(terminal)
        }
    }

    @objc private func closeSelectedGroup(_ sender: Any?) {
        for proj in selectedGroups.compactMap({ $0.project }) {
            iTermWindowProjectsModel.shared.closeProject(proj, keepJobsRunning: false)
        }
    }

    @objc private func freezeSelectedGroupAndKeepJobs(_ sender: Any?) {
        for proj in selectedGroups.compactMap({ $0.project }) {
            iTermWindowProjectsModel.shared.closeProject(proj, keepJobsRunning: true)
        }
    }

    @objc private func disassociateSelectedGroup(_ sender: Any?) {
        for group in selectedGroups {
            for terminal in group.terminals {
                iTermWindowProjectsModel.shared.disassociateWindow(terminal)
            }
        }
    }

    // MARK: Drag Source (right → left: archive; right → right: reassign)

    func outlineView(_ outlineView: NSOutlineView,
                     pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        if let terminal = item as? PseudoTerminal {
            guard let wn = terminal.ptyWindow()?.windowNumber, wn > 0 else { return nil }
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

        // Live window(s) from this pane dropped on a group → reassign (project group)
        // or disassociate (the always-present Unassociated group). Only group rows are
        // valid targets — dropping into empty space does nothing, so a window can't be
        // disassociated by accident. (Saved-window / project drags from the left are
        // handled by the Restore overlay, which covers this pane during such a drag.)
        if pb.availableType(from: [kLiveWindowDragType]) != nil {
            let group: iTermOpenProjectGroup?
            if let g = item as? iTermOpenProjectGroup {
                group = g
            } else if let terminal = item as? PseudoTerminal {
                group = groups.first { $0.terminals.contains { $0 === terminal } }
            } else {
                group = nil
            }
            if let group = group {
                // Force drop-on (never a between-rows insertion line).
                outlineView.setDropItem(group, dropChildIndex: NSOutlineViewDropOnItemIndex)
                return .link
            }
        }
        return []
    }

    func outlineView(_ outlineView: NSOutlineView,
                     acceptDrop info: NSDraggingInfo,
                     item: Any?,
                     childIndex index: Int) -> Bool {
        // Live window(s) → reassign to the target group's project, or disassociate when
        // dropped on the Unassociated group / root.
        let wnStrings = info.allStrings(forType: kLiveWindowDragType)
        guard !wnStrings.isEmpty else { return false }
        let numbers = Set(wnStrings.compactMap { Int($0) })
        let all     = iTermController.sharedInstance().terminals() ?? []
        let dragged = all.filter { numbers.contains($0.ptyWindow()?.windowNumber ?? -1) }
        guard !dragged.isEmpty else { return false }
        // Only a group is a valid drop target (validateDrop enforces this). A project
        // group reassigns; the Unassociated group disassociates.
        guard let group = item as? iTermOpenProjectGroup else { return false }
        let model = iTermWindowProjectsModel.shared
        if let proj = group.project {
            for terminal in dragged { model.associateWindow(terminal, with: proj) }
        } else {
            for terminal in dragged { model.disassociateWindow(terminal) }
        }
        return true
    }

    // MARK: Drag session → drop overlays

    func outlineView(_ outlineView: NSOutlineView,
                     draggingSession session: NSDraggingSession,
                     willBeginAt screenPoint: NSPoint,
                     forItems draggedItems: [Any]) {
        let terminals = draggedItems.compactMap { $0 as? PseudoTerminal }
        let projects  = draggedItems.compactMap { ($0 as? iTermOpenProjectGroup)?.project }
        let payload: iTermProjectsDragPayload
        if !terminals.isEmpty {
            payload = .liveWindows(terminals)
        } else if !projects.isEmpty {
            payload = .projectGroups(projects)
        } else {
            payload = .other
        }
        splitController?.dragDidBegin(payload, from: self)
    }

    func outlineView(_ outlineView: NSOutlineView,
                     draggingSession session: NSDraggingSession,
                     endedAt screenPoint: NSPoint,
                     operation: NSDragOperation) {
        splitController?.dragDidEnd()
    }

    func showDropOverlay(zones: [iTermProjectsDropZone],
                         dragTypes: [NSPasteboard.PasteboardType],
                         delegate: iTermProjectsDropOverlayDelegate) {
        removeDropOverlay()
        let overlay = iTermProjectsDropOverlay(zones: zones, dragTypes: dragTypes)
        overlay.delegate = delegate
        overlay.frame = scrollView.frame
        view.addSubview(overlay, positioned: .above, relativeTo: scrollView)
        dropOverlay = overlay
    }

    func removeDropOverlay() {
        dropOverlay?.removeFromSuperview()
        dropOverlay = nil
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
        preview.close()
    }

    private func showPreview(forRow row: Int) {
        guard let terminal = outlineView.item(atRow: row) as? PseudoTerminal,
              let nsWindow  = terminal.ptyWindow(),
              nsWindow.windowNumber > 0 else { return }
        let rowRect = outlineView.rect(ofRow: row)
        guard rowRect != .zero,
              let iv = liveWindowPreviewImageView(windowNumber: CGWindowID(nsWindow.windowNumber)) else { return }
        preview.show(iv, rowRect: rowRect, anchorView: outlineView)
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
    func showLivePreview(windowNumber: CGWindowID, rowRect: NSRect) {
        guard rowRect != .zero,
              let iv = liveWindowPreviewImageView(windowNumber: windowNumber) else { return }
        preview.show(iv, rowRect: rowRect, anchorView: outlineView)
    }
}

/// Builds an NSImageView holding a screenshot of the given window, sized to a 320pt
/// width (capped height), or nil if the window can't be captured.
func liveWindowPreviewImageView(windowNumber: CGWindowID) -> NSImageView? {
    let cgImage = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        windowNumber,
        [.boundsIgnoreFraming, .bestResolution])
    guard let cgImage else { return nil }
    let img      = NSImage(cgImage: cgImage, size: .zero)
    let aspectW: CGFloat = 320
    let aspectH  = cgImage.height == 0 ? 200
                   : aspectW * CGFloat(cgImage.height) / CGFloat(cgImage.width)
    let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: aspectW, height: min(aspectH, 240)))
    iv.image        = img
    iv.imageScaling = .scaleProportionallyUpOrDown
    return iv
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

/// `.inline` buttons barely dim when disabled, which made it hard to tell what was
/// actionable. Dim the whole button so the disabled state is unmistakable.
private final class iTermDimmableButton: NSButton {
    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1.0 : 0.35 }
    }
}

private func configure(_ button: inout NSButton,
                        label: String,
                        tip: String,
                        target: Any?,
                        action: Selector) {
    let b = iTermDimmableButton(title: label, target: target as AnyObject?, action: action)
    b.bezelStyle  = .inline
    b.controlSize = .small
    b.toolTip     = tip
    button = b
}

extension NSDraggingInfo {
    /// Every string of `type` across all dragged pasteboard items (a multi-row drag
    /// produces one item per row), not just the first.
    func allStrings(forType type: NSPasteboard.PasteboardType) -> [String] {
        (draggingPasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: type) }
    }
}

/// A hover preview pinned to one side of the panel window. Unlike NSPopover — which
/// flips to the opposite edge when the preferred side lacks screen room, which is what
/// put the right pane's previews over the left pane — this always appears on its own
/// side, clamped to the screen, so the two panes' previews never cover each other.
final class iTermProjectsSidePreview {
    enum Side { case left, right }
    private let side: Side
    private var window: NSWindow?

    init(side: Side) { self.side = side }

    /// Shows `content` beside `anchorView`'s window, vertically centered on `rowRect`
    /// (in `anchorView` coordinates), with a little arrow pointing back at the row.
    func show(_ content: NSView, rowRect: NSRect, anchorView: NSView) {
        guard let panel  = anchorView.window,
              let screen = panel.screen ?? NSScreen.main else { return }
        let contentSize = content.frame.size
        // Preview on the left → arrow on its right edge; on the right → arrow on its
        // left edge (always pointing back toward the panel/row).
        let arrowOnRight = (side == .left)
        let bubble  = iTermProjectsPreviewBubble(content: content, arrowOnRight: arrowOnRight)
        let winSize = NSSize(width: contentSize.width + iTermProjectsPreviewBubble.arrowSize,
                             height: contentSize.height)

        let w = window ?? makeWindow()
        window = w
        w.setContentSize(winSize)
        w.contentView = bubble
        bubble.frame = NSRect(origin: .zero, size: winSize)

        let rowOnScreen = panel.convertToScreen(anchorView.convert(rowRect, to: nil))
        let visible = screen.visibleFrame
        let gap: CGFloat = 2
        var x = arrowOnRight ? panel.frame.minX - gap - winSize.width
                             : panel.frame.maxX + gap
        x = min(max(x, visible.minX), visible.maxX - winSize.width)
        var y = rowOnScreen.midY - winSize.height / 2
        y = min(max(y, visible.minY), visible.maxY - winSize.height)
        w.setFrameOrigin(NSPoint(x: x, y: y))

        bubble.arrowY = rowOnScreen.midY - y   // keep the arrow aligned with the row
        bubble.needsDisplay = true
        w.orderFront(nil)
    }

    func close() { window?.orderOut(nil) }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: [.borderless],
                         backing: .buffered, defer: true)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.transient, .ignoresCycle]
        return w
    }
}

/// Hosts the preview content and draws a small arrow on its inner edge pointing back at
/// the hovered row (the affordance the old NSPopover gave for free).
private final class iTermProjectsPreviewBubble: NSView {
    static let arrowSize: CGFloat = 9
    private let content: NSView
    private let arrowOnRight: Bool
    /// Arrow tip Y in view coordinates (origin bottom-left).
    var arrowY: CGFloat = 0

    init(content: NSView, arrowOnRight: Bool) {
        self.content = content
        self.arrowOnRight = arrowOnRight
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(content)
    }
    required init?(coder: NSCoder) { it_fatalError("not implemented") }

    private var contentRect: NSRect {
        let a = Self.arrowSize
        return arrowOnRight ? NSRect(x: 0, y: 0, width: bounds.width - a, height: bounds.height)
                            : NSRect(x: a, y: 0, width: bounds.width - a, height: bounds.height)
    }

    override func layout() {
        super.layout()
        content.frame = contentRect
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = contentRect
        let y     = min(max(arrowY, body.minY + Self.arrowSize), body.maxY - Self.arrowSize)
        let tipX  = arrowOnRight ? bounds.maxX : bounds.minX
        let baseX = arrowOnRight ? body.maxX  : body.minX
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: baseX, y: y + Self.arrowSize))
        tri.line(to: NSPoint(x: tipX, y: y))
        tri.line(to: NSPoint(x: baseX, y: y - Self.arrowSize))
        tri.close()
        NSColor.windowBackgroundColor.setFill()
        tri.fill()
        NSColor.separatorColor.setStroke()
        tri.lineWidth = 1
        tri.stroke()
    }
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
