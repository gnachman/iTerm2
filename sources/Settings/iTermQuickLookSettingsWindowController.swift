//
//  iTermQuickLookSettingsWindowController.swift
//  iTerm2SharedARC
//
//  The sheet that Settings > Pointer > Configure… opens: the web Quick Look engine, hover timing,
//  and the domains Quick Look may preview on hover. The hover mode itself stays in the Pointer
//  pane. Built programmatically; the domain list uses CRUD.swift.
//

import AppKit

private struct QuickLookDomainRow: CRUDRow {
    var domain: String

    func format(column: Int) -> CRUDFormatted {
        return .string(domain)
    }
}

private final class QuickLookDomainDataProvider: CRUDDataProvider {
    weak var owner: iTermQuickLookSettingsWindowController?
    var domains = iTermQuickLookDomainAllowlist.savedDomains() {
        didSet {
            iTermPreferences.setObject(domains, forKey: kPreferenceKeyQuickLookHoverDomainAllowlist)
        }
    }

    var count: Int { domains.count }
    var supportsReorder: Bool { false }
    var supportsInlineEditing: Bool { true }

    subscript(_ index: Int) -> CRUDRow {
        QuickLookDomainRow(domain: domains[index])
    }

    func delete(_ indexes: IndexSet) {
        domains.remove(atOffsets: indexes)
    }

    func makeNew(completion: @escaping (Int) -> ()) {
        owner?.promptForNewDomain(completion: completion)
    }

    func reorder(from sourceIndex: Int, to destinationIndex: Int) {
    }
}

@objc(iTermQuickLookSettingsWindowController)
final class iTermQuickLookSettingsWindowController: NSWindowController, CRUDTableViewControllerDelegate, NSTextFieldDelegate {
    typealias CRUDState = [String]

    private static let width: CGFloat = 560
    private static let margin: CGFloat = 20

    private let dataProvider = QuickLookDomainDataProvider()
    private(set) var crudController: CRUDTableViewController<iTermQuickLookSettingsWindowController>?

    private(set) var browserEngineCheckbox: NSButton!
    private(set) var pluginNote: NSTextField!
    private(set) var hoverDelayField: NSTextField!
    private(set) var autoCloseDelayField: NSTextField!
    private(set) var neverCloseCheckbox: NSButton!
    private(set) var plainTextCheckbox: NSButton!
    private(set) var allowAllCheckbox: NSButton!

    var crudState: CRUDState {
        get {
            dataProvider.domains
        }
        set {
            dataProvider.domains = newValue
        }
    }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 520),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: true)
        super.init(window: window)
        dataProvider.owner = self
        buildContent(in: window)
        load()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(secureUserDefaultsDidChange(_:)),
                                               name: iTermSecureUserDefaults.didChange,
                                               object: nil)
        // A hover announcement can add a domain while the sheet is open.
        iTermPreferenceDidChangeNotification.subscribe(self) { [weak self] notification in
            if notification.key == kPreferenceKeyQuickLookHoverDomainAllowlist {
                self?.domainsDidChange()
            }
        }
    }

    private func domainsDidChange() {
        let saved = iTermQuickLookDomainAllowlist.savedDomains()
        guard saved != dataProvider.domains else {
            return
        }
        dataProvider.domains = saved
        crudController?.reload()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    // MARK: - Seconds fields

    private static func secondsFormatter(_ locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 3
        return formatter
    }

    // Parses a number of seconds with the locale's decimal separator, also accepting a period.
    // Nil for text that isn't a number.
    static func seconds(from string: String, locale: Locale) -> Double? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = secondsFormatter(locale).number(from: trimmed) {
            return number.doubleValue
        }
        return secondsFormatter(Locale(identifier: "en_US_POSIX")).number(from: trimmed)?.doubleValue
    }

    static func string(fromSeconds seconds: Double, locale: Locale) -> String {
        return secondsFormatter(locale).string(from: NSNumber(value: seconds)) ?? ""
    }

    // MARK: - Layout

    private func label(_ string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.alignment = .right
        return label
    }

    private func note(_ string: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = Self.width - 2 * Self.margin
        return label
    }

    private func secondsField(action: Selector) -> NSTextField {
        let field = NSTextField(string: "")
        field.target = self
        field.action = action
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 60).isActive = true
        return field
    }

    private func checkbox(_ title: String, action: Selector) -> NSButton {
        return NSButton(checkboxWithTitle: title, target: self, action: action)
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 6
        return stack
    }

    private func buildContent(in window: NSWindow) {
        window.title = String(localized: "QuickLookSettings.Title",
                              defaultValue: "Quick Look",
                              comment: "Title of the sheet with Quick Look settings")
        let content = NSView()

        browserEngineCheckbox = checkbox(String(localized: "QuickLookSettings.UseBrowserEngine",
                                                defaultValue: "Use the iTerm2 browser engine for web previews",
                                                comment: "Checkbox: web Quick Look uses the built-in browser’s engine and shares its sign-ins"),
                                         action: #selector(browserEngineChanged(_:)))
        browserEngineCheckbox.toolTip = String(localized: "QuickLookSettings.UseBrowserEngineToolTip",
                                               defaultValue: "Requires the iTerm2 Browser Plugin. Previews you open with force press or the context menu then share sign-ins with the built-in browser, and sign-in pop-ups work. Previews opened by hovering never use your sign-ins.",
                                               comment: "Tooltip for the checkbox that makes web Quick Look use the built-in browser’s engine")
        pluginNote = note("")

        let hoverHeading = NSTextField(labelWithString: String(localized: "QuickLookSettings.HoverHeading",
                                                               defaultValue: "Previews on Hover",
                                                               comment: "Heading of the section of the Quick Look settings about previews opened by hovering a link"))
        hoverHeading.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)

        hoverDelayField = secondsField(action: #selector(hoverDelayChanged(_:)))
        autoCloseDelayField = secondsField(action: #selector(autoCloseDelayChanged(_:)))
        neverCloseCheckbox = checkbox(String(localized: "QuickLookSettings.NeverClose",
                                             defaultValue: "Never",
                                             comment: "Checkbox next to the close delay: a hover preview never closes by itself"),
                                      action: #selector(neverCloseChanged(_:)))
        let seconds = String(localized: "QuickLookSettings.Seconds",
                             defaultValue: "seconds",
                             comment: "Unit after a number of seconds in the Quick Look settings")
        let grid = NSGridView(views: [
            [label(String(localized: "QuickLookSettings.HoverDelay",
                          defaultValue: "Open after resting on a link for:",
                          comment: "Label for how long the pointer must rest on a link before its preview opens")),
             row([hoverDelayField, NSTextField(labelWithString: seconds)])],
            [label(String(localized: "QuickLookSettings.AutoCloseDelay",
                          defaultValue: "Close after the pointer leaves for:",
                          comment: "Label for how long after the pointer leaves a hover preview and its link the preview closes")),
             row([autoCloseDelayField, NSTextField(labelWithString: seconds), neverCloseCheckbox])],
        ])
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        // Keep the grid at its natural size so the stack doesn't give it spare room.
        grid.setContentHuggingPriority(.required, for: .vertical)
        grid.setContentHuggingPriority(.required, for: .horizontal)

        plainTextCheckbox = checkbox(String(localized: "QuickLookSettings.PlainTextURLs",
                                            defaultValue: "Also preview web addresses that aren’t hyperlinks",
                                            comment: "Checkbox: hovering also previews plain-text web addresses, not just hyperlinks programs add to their output"),
                                     action: #selector(plainTextChanged(_:)))
        plainTextCheckbox.toolTip = String(localized: "QuickLookSettings.PlainTextURLsToolTip",
                                           defaultValue: "When off, hovering previews only hyperlinks that programs add to their output. Force press and the context menu preview any web address.",
                                           comment: "Tooltip for the checkbox that makes hovering also preview plain-text web addresses")

        let domainsLabel = NSTextField(wrappingLabelWithString: String(
            localized: "QuickLookSettings.DomainsExplanation",
            defaultValue: "Hovering previews only links to these domains and their subdomains. A hover preview never sends your cookies, and until you click into it, it can’t leave these domains.",
            comment: "Explanation above the list of domains that Quick Look may preview on hover"))
        domainsLabel.preferredMaxLayoutWidth = Self.width - 2 * Self.margin

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: Self.width - 2 * Self.margin, height: 140))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let tableView = CompetentTableView(frame: scrollView.bounds)
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.rowHeight = NSTableView.heightForTextCell(using: .systemFont(ofSize: NSFont.systemFontSize))
        // Localization unneeded
        let domainColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Domain"))
        domainColumn.title = String(localized: "QuickLookSettings.DomainColumn",
                                    defaultValue: "Domain",
                                    comment: "Column header in the list of domains Quick Look may preview on hover")
        domainColumn.width = scrollView.contentSize.width
        tableView.addTableColumn(domainColumn)
        scrollView.documentView = tableView
        scrollView.heightAnchor.constraint(equalToConstant: 140).isActive = true

        let addRemove = NSSegmentedControl(images: [
            NSImage(systemSymbolName: SFSymbol.plus.rawValue, accessibilityDescription: iTermLocalizedAdd())!,
            NSImage(systemSymbolName: SFSymbol.minus.rawValue, accessibilityDescription: iTermLocalizedRemove())!
        ], trackingMode: .momentary, target: nil, action: nil)
        addRemove.widthAnchor.constraint(equalToConstant: 60).isActive = true

        allowAllCheckbox = checkbox(String(localized: "QuickLookSettings.AllowAllDomains",
                                           defaultValue: "Preview links to any domain on hover",
                                           comment: "Checkbox: hover previews links to every domain, not just the listed ones. Changing it needs an administrator password."),
                                    action: #selector(allowAllChanged(_:)))
        let allowAllNote = note(String(localized: "QuickLookSettings.AllowAllDomainsNote",
                                       defaultValue: "Any program that prints a link could then make iTerm2 load it when you rest the pointer on it. Turning this on needs an administrator password. Local network addresses must still be listed.",
                                       comment: "Explanation under the checkbox that lets hover preview links to every domain"))

        let done = NSButton(title: String(localized: "QuickLookSettings.Done",
                                          defaultValue: "Done",
                                          comment: "Button that closes the Quick Look settings sheet"),
                            target: self,
                            action: #selector(done(_:)))
        done.keyEquivalent = "\r"

        let doneRow = NSStackView(views: [done])
        doneRow.orientation = .horizontal
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        doneRow.insertView(spacer, at: 0, in: .leading)

        let stack = NSStackView(views: [browserEngineCheckbox,
                                        pluginNote,
                                        hoverHeading,
                                        grid,
                                        plainTextCheckbox,
                                        domainsLabel,
                                        scrollView,
                                        addRemove,
                                        allowAllCheckbox,
                                        allowAllNote,
                                        doneRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(4, after: browserEngineCheckbox)
        stack.setCustomSpacing(18, after: pluginNote)
        stack.setCustomSpacing(14, after: plainTextCheckbox)
        stack.setCustomSpacing(4, after: scrollView)
        stack.setCustomSpacing(14, after: addRemove)
        stack.setCustomSpacing(4, after: allowAllCheckbox)
        stack.setCustomSpacing(16, after: allowAllNote)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.margin),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.margin),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.margin),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Self.margin),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            doneRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            content.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        window.contentView = content
        window.setContentSize(content.fittingSize)

        crudController = CRUDTableViewController(tableView: tableView,
                                                 addRemove: addRemove,
                                                 schema: CRUDSchema(columns: [CRUDColumn(type: .string)],
                                                                    dataProvider: dataProvider))
        crudController?.delegate = self
    }

    // MARK: - Loading

    private func load() {
        browserEngineCheckbox.state = iTermPreferences.bool(forKey: kPreferenceKeyQuickLookUsesBrowserEngine) ? .on : .off
        hoverDelayField.stringValue = Self.string(fromSeconds: iTermPreferences.double(forKey: kPreferenceKeyQuickLookHoverDelay),
                                                  locale: .current)
        plainTextCheckbox.state = iTermPreferences.bool(forKey: kPreferenceKeyQuickLookHoverIncludesPlainTextURLs) ? .on : .off
        loadAllowAll()
        loadAutoClose()
        updatePluginNote()
    }

    // The domain list does nothing while every domain is allowed, so it can't be edited then.
    private func loadAllowAll() {
        let allowsAll = SecureUserDefaults.instance.quickLookHoverAllowsAllDomains.value
        allowAllCheckbox.state = allowsAll ? .on : .off
        crudController?.isEnabled = !allowsAll
    }

    // The setting can change outside the sheet, for example with the defaults command.
    @objc private func secureUserDefaultsDidChange(_ notification: Notification) {
        loadAllowAll()
    }

    private func loadAutoClose() {
        let delay = iTermPreferences.double(forKey: kPreferenceKeyQuickLookHoverAutoCloseDelay)
        autoCloseDelayField.stringValue = Self.string(fromSeconds: delay, locale: .current)
        neverCloseCheckbox.state = delay <= 0 ? .on : .off
        autoCloseDelayField.isEnabled = delay > 0
    }

    // Explains why the browser engine setting has no effect.
    static func pluginNote(browserEngineOn: Bool,
                           browserProfilesOn: Bool,
                           pluginAvailable: () -> Bool) -> String? {
        guard browserEngineOn else {
            return nil
        }
        guard browserProfilesOn else {
            return String(localized: "PointerPreferences.QuickLookBrowserProfilesOff",
                          defaultValue: "“Enable browser-style profiles” is off in Settings > Advanced; using the basic preview.",
                          comment: "Note under the Quick Look browser engine checkbox when the advanced setting that enables the built-in browser is off")
        }
        guard pluginAvailable() else {
            return String(localized: "PointerPreferences.QuickLookPluginNotInstalled",
                          defaultValue: "Browser Plugin not installed; using the basic preview.",
                          comment: "Note under the Quick Look browser engine checkbox when the Browser Plugin is not installed")
        }
        return nil
    }

    private func updatePluginNote() {
        let text = Self.pluginNote(browserEngineOn: browserEngineCheckbox.state == .on,
                                   browserProfilesOn: iTermAdvancedSettingsModel.browserProfiles(),
                                   pluginAvailable: { iTermBrowserGateway.browserAllowed(checkIfNo: true) })
        pluginNote.stringValue = text ?? ""
        pluginNote.isHidden = text == nil
    }

    // MARK: - Actions

    @objc private func browserEngineChanged(_ sender: NSButton) {
        iTermPreferences.setBool(sender.state == .on, forKey: kPreferenceKeyQuickLookUsesBrowserEngine)
        updatePluginNote()
    }

    // Stores the field's seconds if it holds a number (negative becomes 0), then shows what is
    // stored.
    private func storeSeconds(from field: NSTextField, key: String) {
        if let seconds = Self.seconds(from: field.stringValue, locale: .current) {
            iTermPreferences.setDouble(max(0, seconds), forKey: key)
        }
        field.stringValue = Self.string(fromSeconds: iTermPreferences.double(forKey: key), locale: .current)
    }

    @objc private func hoverDelayChanged(_ sender: NSTextField) {
        storeSeconds(from: sender, key: kPreferenceKeyQuickLookHoverDelay)
    }

    @objc private func autoCloseDelayChanged(_ sender: NSTextField) {
        storeSeconds(from: sender, key: kPreferenceKeyQuickLookHoverAutoCloseDelay)
        loadAutoClose()
    }

    // Checked stores 0 (never close); unchecked restores the default close delay.
    @objc private func neverCloseChanged(_ sender: NSButton) {
        let defaultDelay = (iTermPreferences.defaultObject(forKey: kPreferenceKeyQuickLookHoverAutoCloseDelay) as? NSNumber)?.doubleValue ?? 1.5
        iTermPreferences.setDouble(sender.state == .on ? 0 : defaultDelay,
                                   forKey: kPreferenceKeyQuickLookHoverAutoCloseDelay)
        loadAutoClose()
    }

    @objc private func plainTextChanged(_ sender: NSButton) {
        iTermPreferences.setBool(sender.state == .on, forKey: kPreferenceKeyQuickLookHoverIncludesPlainTextURLs)
    }

    // Turning it on asks for an administrator password; turning it off doesn't.
    @objc private func allowAllChanged(_ sender: NSButton) {
        let wantsOn = sender.state == .on
        do {
            if wantsOn {
                try SecureUserDefaults.instance.quickLookHoverAllowsAllDomains.set(true)
            } else {
                try SecureUserDefaults.instance.quickLookHoverAllowsAllDomains.set(nil)
            }
        } catch {
            RLog("Failed to change the Quick Look allow-all-domains setting: \(error.localizedDescription)")
        }
        loadAllowAll()
    }

    @objc private func done(_ sender: Any?) {
        guard let window else {
            return
        }
        // Commit a seconds field that is still being edited.
        window.makeFirstResponder(nil)
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else {
            return
        }
        if field === hoverDelayField {
            hoverDelayChanged(field)
        } else if field === autoCloseDelayField {
            autoCloseDelayChanged(field)
        }
    }

    // MARK: - Adding domains

    fileprivate func promptForNewDomain(completion: @escaping (Int) -> ()) {
        guard let window else {
            return
        }
        let warning = iTermWarning()
        warning.heading = String(localized: "QuickLookSettings.AddDomainHeading",
                                 defaultValue: "Preview a Domain on Hover",
                                 comment: "Heading of the dialog for adding a domain that Quick Look may preview on hover")
        warning.title = String(localized: "QuickLookSettings.AddDomainInfo",
                               defaultValue: "Enter a domain, such as github.com. Links to it and its subdomains will preview when you rest the pointer on them.",
                               comment: "Explains the dialog for adding a domain that Quick Look may preview on hover")
        warning.actionLabels = [iTermLocalizedAdd(), iTermLocalizedCancel()]
        warning.cancelLabel = iTermLocalizedCancel()
        warning.warningType = .kiTermWarningTypePersistent
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        // Localization unneeded
        textField.placeholderString = "github.com"
        warning.accessory = textField
        warning.remoteInputs = [.textInput(withIdentifier: "domain",  // Localization unneeded
                                           label: nil,
                                           textField: textField)]
        warning.initialFirstResponder = textField
        warning.window = window
        warning.runModalAsync { [weak self] selection, _ in
            guard selection == .kiTermWarningSelection0 else {
                return
            }
            self?.add(input: textField.stringValue, completion: completion)
        }
    }

    private func showInvalidDomain(_ input: String) {
        iTermWarning.show(withTitle: String(localized: "QuickLookSettings.InvalidDomain",
                                            defaultValue: "“\(input)” is not a domain. Enter one like github.com.",
                                            comment: "Error shown when the user enters something that is not a domain; placeholder is what they entered"),
                          actions: [iTermLocalizedOK()],
                          identifier: nil,
                          silenceable: .kiTermWarningTypePersistent,
                          window: window)
    }

    private func add(input: String, completion: @escaping (Int) -> ()) {
        guard let domain = iTermQuickLookDomainAllowlist.normalizedEntry(input) else {
            showInvalidDomain(input)
            return
        }
        if dataProvider.domains.contains(domain) {
            return
        }
        crudController?.undoable {
            let index = iTermQuickLookDomainAllowlist.insertionIndex(of: domain, in: dataProvider.domains)
            dataProvider.domains.insert(domain, at: index)
            completion(index)
        }
    }

    // MARK: - CRUDTableViewControllerDelegate

    func crudTableSelectionDidChange(_ sender: CRUDTableViewController<iTermQuickLookSettingsWindowController>,
                                     selectedRows: IndexSet) {
    }

    func crudTextFieldDidChange(_ sender: CRUDTableViewController<iTermQuickLookSettingsWindowController>,
                                row: Int,
                                column: Int,
                                newValue: String) {
        guard row < dataProvider.domains.count else {
            return
        }
        guard let domain = iTermQuickLookDomainAllowlist.normalizedEntry(newValue) else {
            showInvalidDomain(newValue)
            sender.reload(row: row)
            return
        }
        guard domain != dataProvider.domains[row] else {
            sender.reload(row: row)
            return
        }
        if dataProvider.domains.contains(domain) {
            // Already listed: editing this row into a duplicate removes it.
            _ = sender.undoable {
                dataProvider.domains.remove(at: row)
            }
            sender.reload()
            return
        }
        sender.undoable {
            dataProvider.domains[row] = domain
        }
        sender.reload(row: row)
    }

    func crudDoubleClick(_ sender: CRUDTableViewController<iTermQuickLookSettingsWindowController>,
                         row: Int,
                         column: Int) {
    }
}
