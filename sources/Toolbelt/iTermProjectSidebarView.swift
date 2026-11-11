import AppKit

@objc protocol iTermProjectSidebarDelegate: AnyObject {
    func projectSidebar(_ sidebar: iTermProjectSidebarView, didSelectProject project: iTermProjectDirectory)
    func projectSidebarAddFolder(_ sidebar: iTermProjectSidebarView)
    func projectSidebarAddCurrentDirectory(_ sidebar: iTermProjectSidebarView)
    func projectSidebar(_ sidebar: iTermProjectSidebarView, removeProject project: iTermProjectDirectory)
}

@objcMembers
final class iTermProjectSidebarView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: iTermProjectSidebarDelegate?
    var projects = [iTermProjectDirectory]() { didSet { reloadProjects() } }
    var selectedProjectIdentifier: String? { didSet { updateSelection() } }
    var canAddCurrentDirectory = false { didSet { currentButton.isEnabled = canAddCurrentDirectory } }
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let addButton = NSButton()
    private let currentButton = NSButton()
    private let removeButton = NSButton()
    private var updatingSelection = false
    private let emptyLabel = NSTextField(wrappingLabelWithString: String(localized: "ProjectSidebar.Empty", defaultValue: "Add a folder to get started.", comment: "Empty state in the project sidebar"))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Project"))) // Localization unneeded: cell identifier.
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = .controlBackgroundColor
        table.setAccessibilityLabel(String(localized: "ProjectSidebar.Projects", defaultValue: "Projects", comment: "Accessible project list name"))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        addSubview(scroll)
        emptyLabel.textColor = .secondaryLabelColor
        addSubview(emptyLabel)
        configure(addButton, title: String(localized: "ProjectSidebar.AddFolder", defaultValue: "Add Folder…", comment: "Choose a folder to add as a project"), action: #selector(addFolder(_:)))
        configure(currentButton, title: String(localized: "ProjectSidebar.AddCurrent", defaultValue: "Add Current Directory", comment: "Add current terminal directory as a project"), action: #selector(addCurrent(_:)))
        configure(removeButton, title: String(localized: "ProjectSidebar.Remove", defaultValue: "Remove Project", comment: "Remove selected project from the list"), action: #selector(remove(_:)))
        currentButton.isEnabled = false
        reloadProjects()
    }

    required init?(coder: NSCoder) { it_fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    private func configure(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        addSubview(button)
    }
    override func layout() {
        super.layout()
        let margin: CGFloat = 6
        let height: CGFloat = 26
        for (index, button) in [addButton, currentButton, removeButton].enumerated() {
            button.frame = NSRect(x: margin, y: bounds.height - CGFloat(3 - index) * (height + margin), width: max(0, bounds.width - 2 * margin), height: height)
        }
        scroll.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - 3 * (height + margin) - margin))
        emptyLabel.frame = NSRect(x: margin + 4, y: 20, width: max(0, bounds.width - 2 * margin - 8), height: 60)
    }
    private func reloadProjects() {
        updatingSelection = true
        table.reloadData()
        updatingSelection = false
        emptyLabel.isHidden = !projects.isEmpty
        updateSelection()
    }
    private func updateSelection() {
        updatingSelection = true
        if let row = projects.firstIndex(where: { $0.identifier == selectedProjectIdentifier }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else { table.deselectAll(nil) }
        updatingSelection = false
        removeButton.isEnabled = table.selectedRow >= 0
    }
    func numberOfRows(in tableView: NSTableView) -> Int { projects.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard projects.indices.contains(row) else { return nil }
        let text = NSTextField(labelWithString: projects[row].name)
        text.lineBreakMode = .byTruncatingTail
        text.toolTip = projects[row].rootDirectory
        text.setAccessibilityLabel(projects[row].name)
        text.setAccessibilityHelp(projects[row].rootDirectory)
        return text
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingSelection else { return }
        removeButton.isEnabled = projects.indices.contains(table.selectedRow)
        guard projects.indices.contains(table.selectedRow) else { return }
        let project = projects[table.selectedRow]
        selectedProjectIdentifier = project.identifier
        delegate?.projectSidebar(self, didSelectProject: project)
    }
    @objc private func addFolder(_ sender: Any?) { delegate?.projectSidebarAddFolder(self) }
    @objc private func addCurrent(_ sender: Any?) { delegate?.projectSidebarAddCurrentDirectory(self) }
    @objc private func remove(_ sender: Any?) {
        guard projects.indices.contains(table.selectedRow) else { return }
        delegate?.projectSidebar(self, removeProject: projects[table.selectedRow])
    }
}
