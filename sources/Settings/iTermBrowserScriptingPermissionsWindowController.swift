//
//  iTermBrowserScriptingPermissionsWindowController.swift
//  iTerm2SharedARC
//
//  Settings > General > Magic sheet listing the websites on which Python API scripts
//  may (or may not) load URLs or run JavaScript in a browser session. Built
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
    weak var owner: iTermBrowserScriptingPermissionsWindowController?
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

@objc(iTermBrowserScriptingPermissionsWindowController)
final class iTermBrowserScriptingPermissionsWindowController: NSWindowController, CRUDTableViewControllerDelegate {
    typealias CRUDState = [iTermBrowserScriptingPermissions.Entry]

    private static let permissionColumnWidth: CGFloat = 130
    private static let allowedColumnWidth: CGFloat = 60

    private let dataProvider = BrowserScriptingPermissionsDataProvider()
    private var crudController: CRUDTableViewController<iTermBrowserScriptingPermissionsWindowController>?

    var crudState: CRUDState {
        get {
            dataProvider.entries
        }
        set {
            dataProvider.replaceAll(with: newValue)
        }
    }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
                              styleMask: [.titled, .resizable],
                              backing: .buffered,
                              defer: false)
        window.minSize = NSSize(width: 440, height: 260)
        super.init(window: window)
        dataProvider.owner = self
        buildContentView()
        // A script may be approved while this is open.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(windowDidBecomeKey(_:)),
                                               name: NSWindow.didBecomeKeyNotification,
                                               object: window)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    // Shows the panel as a sheet on `parent`.
    @objc(beginSheetModalForWindow:)
    func beginSheet(for parent: NSWindow) {
        guard let window else {
            return
        }
        refresh()
        parent.beginSheet(window) { [weak self] _ in
            // This controller is reused, and the next showing may follow changes made
            // elsewhere.
            self?.window?.undoManager?.removeAllActions()
        }
    }

    // Picks up answers remembered elsewhere, such as at a script's prompt. Undo works by
    // restoring snapshots of the list, so an undo from before such a change would revert it
    // too. Forget the undo history when that happens.
    private func refresh() {
        let saved = iTermBrowserScriptingPermissions.entries()
        guard Set(saved) != Set(dataProvider.entries) else {
            return
        }
        DLog("Permissions changed outside the panel")
        window?.undoManager?.removeAllActions()
        dataProvider.entries = saved
        crudController?.reload()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    @objc private func done(_ sender: Any?) {
        guard let window else {
            return
        }
        window.sheetParent?.endSheet(window)
    }

    // MARK: - Layout

    private func buildContentView() {
        guard let window else {
            return
        }
        let bounds = NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size)
        let container = NSView(frame: bounds)
        let margin: CGFloat = 20
        let gap: CGFloat = 8
        let buttonHeight: CGFloat = 32
        let segmentHeight: CGFloat = 24
        let labelHeight: CGFloat = 48

        let doneButton = NSButton(title: String(localized: "General.Done", defaultValue: "Done", comment: "Done button"),
                                  target: self,
                                  action: #selector(done(_:)))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.sizeToFit()
        doneButton.frame = NSRect(x: bounds.width - margin - max(doneButton.frame.width, 80),
                                  y: margin,
                                  width: max(doneButton.frame.width, 80),
                                  height: buttonHeight)
        doneButton.autoresizingMask = [.minXMargin, .maxYMargin]
        container.addSubview(doneButton)

        let addRemove = NSSegmentedControl(images: [
            NSImage(systemSymbolName: SFSymbol.plus.rawValue, accessibilityDescription: iTermLocalizedAdd())!,
            NSImage(systemSymbolName: SFSymbol.minus.rawValue, accessibilityDescription: iTermLocalizedRemove())!
        ], trackingMode: .momentary, target: nil, action: nil)
        addRemove.frame = NSRect(x: margin,
                                 y: margin + (buttonHeight - segmentHeight) / 2,
                                 width: 60,
                                 height: segmentHeight)
        addRemove.autoresizingMask = [.maxXMargin, .maxYMargin]
        container.addSubview(addRemove)

        let label = NSTextField(wrappingLabelWithString: String(
            localized: "BrowserScriptingPermissions.Explanation",
            defaultValue: "Before a script loads URLs or runs JavaScript on a website in a browser session, iTerm2 asks you. Remembered answers are listed here and apply to all scripts.",
            comment: "Explanation at the top of the panel listing websites that scripts may control in a browser session"))
        label.frame = NSRect(x: margin,
                             y: bounds.height - margin - labelHeight,
                             width: bounds.width - 2 * margin,
                             height: labelHeight)
        label.autoresizingMask = [.width, .minYMargin]
        container.addSubview(label)

        let scrollY = margin + buttonHeight + gap
        let scrollView = NSScrollView(frame: NSRect(x: margin,
                                                    y: scrollY,
                                                    width: bounds.width - 2 * margin,
                                                    height: label.frame.minY - gap - scrollY))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autoresizingMask = [.width, .height]

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
        siteColumn.width = scrollView.contentSize.width - Self.permissionColumnWidth - Self.allowedColumnWidth - 3 * tableView.intercellSpacing.width
        tableView.addTableColumn(siteColumn)

        // Localization unneeded
        let permissionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Permission"))
        permissionColumn.title = String(localized: "BrowserScriptingPermissions.PermissionColumn",
                                        defaultValue: "Permission",
                                        comment: "Column header for what scripts may do on a website, such as Run JavaScript")
        permissionColumn.width = Self.permissionColumnWidth
        permissionColumn.minWidth = Self.permissionColumnWidth
        tableView.addTableColumn(permissionColumn)

        // Localization unneeded
        let allowedColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Allowed"))
        allowedColumn.title = String(localized: "BrowserScriptingPermissions.AllowedColumn",
                                     defaultValue: "Allowed",
                                     comment: "Column header for a checkbox saying whether scripts may do something on a website; unchecked means always denied")
        allowedColumn.width = Self.allowedColumnWidth
        allowedColumn.minWidth = Self.allowedColumnWidth
        allowedColumn.maxWidth = Self.allowedColumnWidth
        tableView.addTableColumn(allowedColumn)

        scrollView.documentView = tableView
        container.addSubview(scrollView)

        let schema = CRUDSchema(columns: [CRUDColumn(type: .string),
                                          CRUDColumn(type: .string),
                                          CRUDColumn(type: .boolean)],
                                dataProvider: dataProvider)
        crudController = CRUDTableViewController(tableView: tableView,
                                                 addRemove: addRemove,
                                                 schema: schema)
        crudController?.delegate = self

        window.contentView = container
        window.initialFirstResponder = tableView
    }

    // MARK: - Adding

    fileprivate func promptForNewEntry(completion: @escaping (Int) -> ()) {
        guard let window else {
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
                              window: window)
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

    func crudTableSelectionDidChange(_ sender: CRUDTableViewController<iTermBrowserScriptingPermissionsWindowController>,
                                     selectedRows: IndexSet) {
    }

    func crudTextFieldDidChange(_ sender: CRUDTableViewController<iTermBrowserScriptingPermissionsWindowController>,
                                row: Int,
                                column: Int,
                                newValue: String) {
    }

    func crudDoubleClick(_ sender: CRUDTableViewController<iTermBrowserScriptingPermissionsWindowController>,
                         row: Int,
                         column: Int) {
    }

    func crudCheckboxDidChange(_ sender: CRUDTableViewController<iTermBrowserScriptingPermissionsWindowController>,
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
