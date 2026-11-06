//
//  BrowserScriptingPermissionsViewController.swift
//  iTerm2SharedARC
//
//  Lists the websites on which Python API scripts may (or may not) load URLs or run
//  JavaScript in a browser session. Shown as a tab of the permissions sheet in
//  Settings > General > Magic (see ScriptingPermissionsWindowController). Built
//  programmatically on CRUD.swift.
//

import AppKit

private struct BrowserScriptingPermissionRow: CRUDRow {
    var entry: iTermBrowserScriptingPermissions.Entry

    func format(column: Int) -> CRUDFormatted {
        switch column {
        case 0:
            return .string(entry.site)
        case 1:
            return .string(entry.kind.localizedName)
        case 2:
            return .boolean(entry.allowed)
        default:
            return .string("")
        }
    }
}

private final class BrowserScriptingPermissionsDataProvider: CRUDDataProvider {
    weak var owner: BrowserScriptingPermissionsViewController?
    // A snapshot of user defaults, kept in the order shown.
    var entries = iTermBrowserScriptingPermissions.entries()

    var count: Int { entries.count }
    var supportsReorder: Bool { false }
    var supportsInlineEditing: Bool { false }

    subscript(_ index: Int) -> CRUDRow {
        BrowserScriptingPermissionRow(entry: entries[index])
    }

    func delete(_ indexes: IndexSet) {
        for index in indexes {
            iTermBrowserScriptingPermissions.remove(entries[index])
        }
        entries.remove(atOffsets: indexes)
    }

    func makeNew(completion: @escaping (Int) -> ()) {
        owner?.promptForNewEntry(completion: completion)
    }

    func reorder(from sourceIndex: Int, to destinationIndex: Int) {
    }

    // Changes user defaults from `entries` to `newEntries`, touching only what differs.
    func replaceAll(with newEntries: [iTermBrowserScriptingPermissions.Entry]) {
        let newSet = Set(newEntries)
        for entry in entries where !newSet.contains(entry) {
            iTermBrowserScriptingPermissions.remove(entry)
        }
        let oldSet = Set(entries)
        for entry in newEntries where !oldSet.contains(entry) {
            iTermBrowserScriptingPermissions.save(entry)
        }
        entries = newEntries
    }
}

final class BrowserScriptingPermissionsViewController: NSViewController, CRUDTableViewControllerDelegate {
    typealias CRUDState = [iTermBrowserScriptingPermissions.Entry]

    private static let permissionColumnWidth: CGFloat = 130
    private static let allowedColumnWidth: CGFloat = 60
    // Room around the text in a row beyond the text itself.
    private static let cellPadding: CGFloat = 12

    // The width `column` needs to show its header and each of `cellTexts` in
    // full, and at least `minimum`. Translations of the header and of the
    // permission names can be much longer than English.
    static func width(toFit column: NSTableColumn, cellTexts: [String], minimum: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textWidths = cellTexts.map { ($0 as NSString).size(withAttributes: [.font: font]).width + cellPadding }
        let widest = ([column.headerCell.cellSize.width] + textWidths).max() ?? 0
        return max(minimum, ceil(widest))
    }

    private let dataProvider = BrowserScriptingPermissionsDataProvider()
    private var crudController: CRUDTableViewController<BrowserScriptingPermissionsViewController>?

    var crudState: CRUDState {
        get {
            dataProvider.entries
        }
        set {
            dataProvider.replaceAll(with: newValue)
        }
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        dataProvider.owner = self
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        buildContentView()
    }

    // Picks up answers remembered elsewhere, such as at a script's prompt. Undo works by
    // restoring snapshots of the list, so an undo from before such a change would revert it
    // too. Forget the undo history when that happens.
    func refresh() {
        let saved = iTermBrowserScriptingPermissions.entries()
        guard Set(saved) != Set(dataProvider.entries) else {
            return
        }
        DLog("Permissions changed outside the panel")
        view.window?.undoManager?.removeAllActions()
        dataProvider.entries = saved
        crudController?.reload()
    }

    // MARK: - Layout

    private func buildContentView() {
        let bounds = NSRect(x: 0, y: 0, width: 560, height: 340)
        let container = NSView(frame: bounds)
        let margin: CGFloat = 20
        let gap: CGFloat = 8

        let addRemove = NSSegmentedControl(images: [
            NSImage(systemSymbolName: SFSymbol.plus.rawValue, accessibilityDescription: iTermLocalizedAdd())!,
            NSImage(systemSymbolName: SFSymbol.minus.rawValue, accessibilityDescription: iTermLocalizedRemove())!
        ], trackingMode: .momentary, target: nil, action: nil)
        addRemove.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(addRemove)

        let label = NSTextField(wrappingLabelWithString: String(
            localized: "BrowserScriptingPermissions.Explanation",
            defaultValue: "Before a script loads URLs or runs JavaScript on a website in a browser session, iTerm2 asks you. Remembered answers are listed here and apply to all scripts.",
            comment: "Explanation at the top of the panel listing websites that scripts may control in a browser session"))
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        // The initial frame only sizes the columns; constraints position it.
        let scrollView = NSScrollView(frame: NSRect(x: 0,
                                                    y: 0,
                                                    width: bounds.width - 2 * margin,
                                                    height: 200))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let tableView = CompetentTableView(frame: scrollView.bounds)
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.rowHeight = NSTableView.heightForTextCell(using: .systemFont(ofSize: NSFont.systemFontSize))

        // Localization unneeded
        let siteColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Site"))
        siteColumn.title = String(localized: "BrowserScriptingPermissions.WebsiteColumn",
                                  defaultValue: "Website",
                                  comment: "Column header for the website a permission applies to")
        tableView.addTableColumn(siteColumn)

        // Localization unneeded
        let permissionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Permission"))
        permissionColumn.title = String(localized: "BrowserScriptingPermissions.PermissionColumn",
                                        defaultValue: "Permission",
                                        comment: "Column header for what scripts may do on a website, such as Run JavaScript")
        let permissionWidth = Self.width(toFit: permissionColumn,
                                         cellTexts: iTermBrowserScriptingPermissions.Kind.allCases.map { $0.localizedName },
                                         minimum: Self.permissionColumnWidth)
        permissionColumn.width = permissionWidth
        permissionColumn.minWidth = permissionWidth
        tableView.addTableColumn(permissionColumn)

        // Localization unneeded
        let allowedColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Allowed"))
        allowedColumn.title = String(localized: "BrowserScriptingPermissions.AllowedColumn",
                                     defaultValue: "Allowed",
                                     comment: "Column header for a checkbox saying whether scripts may do something on a website; unchecked means always denied")
        let allowedWidth = Self.width(toFit: allowedColumn, cellTexts: [], minimum: Self.allowedColumnWidth)
        allowedColumn.width = allowedWidth
        allowedColumn.minWidth = allowedWidth
        allowedColumn.maxWidth = allowedWidth
        tableView.addTableColumn(allowedColumn)

        siteColumn.width = scrollView.contentSize.width - permissionWidth - allowedWidth - 3 * tableView.intercellSpacing.width

        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: margin),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),

            scrollView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),

            addRemove.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: gap),
            addRemove.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            addRemove.widthAnchor.constraint(equalToConstant: 60),
            addRemove.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -margin),
        ])

        let schema = CRUDSchema(columns: [CRUDColumn(type: .string),
                                          CRUDColumn(type: .string),
                                          CRUDColumn(type: .boolean)],
                                dataProvider: dataProvider)
        crudController = CRUDTableViewController(tableView: tableView,
                                                 addRemove: addRemove,
                                                 schema: schema)
        crudController?.delegate = self

        view = container
    }

    // MARK: - Adding

    fileprivate func promptForNewEntry(completion: @escaping (Int) -> ()) {
        guard let window = view.window else {
            return
        }
        let allowJavaScript = String(localized: "BrowserScriptingPermissions.AllowJavaScriptButton",
                                     defaultValue: "Allow Running JavaScript",
                                     comment: "Button that lets scripts run JavaScript on the website the user entered")
        let allowLoadingURLs = String(localized: "BrowserScriptingPermissions.AllowLoadingURLsButton",
                                      defaultValue: "Allow Loading URLs",
                                      comment: "Button that lets scripts load URLs from the website the user entered")
        let warning = iTermWarning()
        warning.heading = String(localized: "BrowserScriptingPermissions.AddHeading",
                                 defaultValue: "Allow Scripts on a Website",
                                 comment: "Heading of the dialog for adding a website that scripts may control without asking")
        warning.title = String(localized: "BrowserScriptingPermissions.AddInfo",
                               defaultValue: "Enter a website, such as https://example.com. Scripts will be able to do this on it without asking.",
                               comment: "Explains the dialog for adding a website that scripts may control; the buttons say what they will be able to do")
        warning.actionLabels = [allowJavaScript, allowLoadingURLs, iTermLocalizedCancel()]
        warning.cancelLabel = iTermLocalizedCancel()
        warning.warningType = .kiTermWarningTypePersistent

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        // Localization unneeded
        textField.placeholderString = "https://example.com"
        warning.accessory = textField
        warning.remoteInputs = [.textInput(withIdentifier: "website",  // Localization unneeded
                                           label: nil,
                                           textField: textField)]
        warning.initialFirstResponder = textField
        warning.window = window

        warning.runModalAsync { [weak self] selection, _ in
            let kind: iTermBrowserScriptingPermissions.Kind
            switch selection {
            case .kiTermWarningSelection0:
                kind = .runJavaScript
            case .kiTermWarningSelection1:
                kind = .loadURL
            default:
                return
            }
            self?.add(input: textField.stringValue, kind: kind, completion: completion)
        }
    }

    private func add(input: String,
                     kind: iTermBrowserScriptingPermissions.Kind,
                     completion: @escaping (Int) -> ()) {
        guard let site = iTermBrowserScriptingPermissions.site(from: input, kind: kind) else {
            iTermWarning.show(withTitle: String(localized: "BrowserScriptingPermissions.InvalidWebsite",
                                                defaultValue: "“\(input)” is not a website address. Enter one like https://example.com.",
                                                comment: "Error shown when the user enters something that is not a web address; placeholder is what they entered"),
                              actions: [iTermLocalizedOK()],
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              window: view.window)
            return
        }
        let entry = iTermBrowserScriptingPermissions.Entry(kind: kind, site: site, allowed: true)
        if let existing = dataProvider.entries.firstIndex(where: { $0.kind == kind && $0.site == site }) {
            crudController?.undoable {
                iTermBrowserScriptingPermissions.save(entry)
                dataProvider.entries[existing] = entry
            }
            crudController?.reload(row: existing)
            return
        }
        crudController?.undoable {
            iTermBrowserScriptingPermissions.save(entry)
            let index = dataProvider.entries.firstIndex {
                $0.site.localizedStandardCompare(site) == .orderedDescending
            } ?? dataProvider.entries.count
            dataProvider.entries.insert(entry, at: index)
            completion(index)
        }
    }

    // MARK: - CRUDTableViewControllerDelegate

    func crudTableSelectionDidChange(_ sender: CRUDTableViewController<BrowserScriptingPermissionsViewController>,
                                     selectedRows: IndexSet) {
    }

    func crudTextFieldDidChange(_ sender: CRUDTableViewController<BrowserScriptingPermissionsViewController>,
                                row: Int,
                                column: Int,
                                newValue: String) {
    }

    func crudDoubleClick(_ sender: CRUDTableViewController<BrowserScriptingPermissionsViewController>,
                         row: Int,
                         column: Int) {
    }

    func crudCheckboxDidChange(_ sender: CRUDTableViewController<BrowserScriptingPermissionsViewController>,
                               row: Int,
                               column: Int,
                               newValue: Bool) {
        guard row < dataProvider.entries.count else {
            return
        }
        crudController?.undoable {
            dataProvider.entries[row].allowed = newValue
            iTermBrowserScriptingPermissions.save(dataProvider.entries[row])
        }
    }
}
