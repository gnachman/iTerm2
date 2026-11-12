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
    var projects = [iTermProjectDirectory]() {
        didSet {
            guard !oldValue.elementsEqual(projects, by: { $0.identifier == $1.identifier && $0.rootDirectory == $1.rootDirectory }) else { return }
            reloadProjects()
        }
    }
    var selectedProjectIdentifier: String? { didSet { if oldValue != selectedProjectIdentifier { updateSelection() } } }
    var canAddCurrentDirectory = false { didSet { currentButton.isEnabled = canAddCurrentDirectory } }
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let addButton = NSButton()
    private let currentButton = NSButton()
    private let removeButton = NSButton()
    private let title = NSTextField(labelWithString: String(localized: "ProjectSidebar.Projects", defaultValue: "Projects", comment: "Project sidebar heading"))
    private let folderImage = NSImage(systemSymbolName: SFSymbol.folder.rawValue, accessibilityDescription: nil)
    private var updatingSelection = false
    private let emptyLabel = NSTextField(wrappingLabelWithString: String(localized: "ProjectSidebar.Empty", defaultValue: "Add a folder to get started.", comment: "Empty state in the project sidebar"))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Project"))) // Localization unneeded: cell identifier.
        table.headerView = nil
        table.rowHeight = 26
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.style = .sourceList
        table.focusRingType = .none
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = .controlBackgroundColor
        table.setAccessibilityLabel(String(localized: "ProjectSidebar.Projects", defaultValue: "Projects", comment: "Accessible project list name"))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        addSubview(scroll)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        addSubview(title)
        emptyLabel.textColor = .secondaryLabelColor
        addSubview(emptyLabel)
        configure(addButton, title: String(localized: "ProjectSidebar.AddFolder", defaultValue: "Add Folder…", comment: "Choose a folder to add as a project"), action: #selector(addFolder(_:)))
        configure(currentButton, title: String(localized: "ProjectSidebar.AddCurrent", defaultValue: "Add Current Directory", comment: "Add current terminal directory as a project"), action: #selector(addCurrent(_:)))
        configure(removeButton, title: String(localized: "ProjectSidebar.Remove", defaultValue: "Remove Project", comment: "Remove selected project from the list"), action: #selector(remove(_:)))
        addButton.image = NSImage(systemSymbolName: SFSymbol.plus.rawValue, accessibilityDescription: nil)
        currentButton.image = NSImage(systemSymbolName: SFSymbol.folderBadgePlus.rawValue, accessibilityDescription: nil)
        removeButton.image = NSImage(systemSymbolName: SFSymbol.minus.rawValue, accessibilityDescription: nil)
        currentButton.isEnabled = false
        reloadProjects()
    }

    required init?(coder: NSCoder) { it_fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    private func configure(_ button: NSButton, title: String, action: Selector) {
        button.title = ""
        button.imagePosition = .imageOnly
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.isBordered = false
        button.controlSize = .small
        button.target = self
        button.action = action
        addSubview(button)
    }
    override func layout() {
        super.layout()
        let margin: CGFloat = 8
        title.frame = NSRect(x: 10, y: 9, width: max(0, bounds.width - 96), height: 18)
        for (index, button) in [addButton, currentButton, removeButton].enumerated() {
            button.frame = NSRect(x: bounds.width - margin - CGFloat(3 - index) * 25, y: 5, width: 24, height: 24)
        }
        scroll.frame = NSRect(x: 0, y: 34, width: bounds.width, height: max(0, bounds.height - 34))
        emptyLabel.frame = NSRect(x: margin + 4, y: 48, width: max(0, bounds.width - 2 * margin - 8), height: 60)
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
        let identifier = NSUserInterfaceItemIdentifier("ProjectSidebarCell") // Localization unneeded: reuse identifier.
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? iTermSidebarCellView ?? iTermSidebarCellView(frame: .zero)
        cell.identifier = identifier
        let project = projects[row]
        cell.configure(name: project.name, path: project.rootDirectory, image: folderImage, folder: true)
        return cell
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
