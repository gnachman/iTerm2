//
//  IT2HostGrantsViewController.swift
//  iTerm2SharedARC
//
//  The list of remote hosts the user chose to always allow to use the iTerm2 API over SSH
//  integration (see IT2HostGrants). Shown as a tab of the permissions sheet in General > Magic
//  (see ScriptingPermissionsWindowController). Read-only apart from removing a host, since a
//  grant can only be minted from the authorization prompt, where the host proves it can
//  receive the secret.
//
//  Built in code rather than a xib, and laid out with auto layout.
//

import AppKit

final class IT2HostGrantsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private static let hostColumn = NSUserInterfaceItemIdentifier("host")
    private static let grantedColumn = NSUserInterfaceItemIdentifier("granted")

    private let store: IT2HostGrantStore
    private var grants: [IT2HostGrant] = []
    private let tableView = NSTableView()
    private let removeButton = NSButton()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let dateFormatter = makeDateFormatter(
        nonEnglishUILanguage: LocalizedUnitFormatter.nonEnglishUILanguage)

    /// In the UI language when it isn't English, as iTerm2's other formatted values are (see
    /// LocalizedUnitFormatter); otherwise in the user's own locale. A German UI on a US region
    /// otherwise showed an English month in a German sheet.
    static func makeDateFormatter(nonEnglishUILanguage: String?) -> DateFormatter {
        let formatter = DateFormatter()
        if let nonEnglishUILanguage {
            formatter.locale = Locale(identifier: nonEnglishUILanguage)
        }
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    init(store: IT2HostGrantStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        view = content
        buildContent(in: content)
        reload()
    }

    // MARK: - Layout

    private func buildContent(in content: NSView) {

        let explanation = NSTextField(wrappingLabelWithString: String(
            localized: "IT2HostGrants.Explanation",
            defaultValue: "These hosts can use the iTerm2 API over SSH integration without asking first. Removing a host makes it ask again the next time it connects.",
            comment: "Explanation at the top of the list of remote hosts always allowed to use the iTerm2 API"))
        explanation.translatesAutoresizingMaskIntoConstraints = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        let host = NSTableColumn(identifier: Self.hostColumn)
        host.title = String(localized: "IT2HostGrants.HostColumn",
                            defaultValue: "Host",
                            comment: "Column header for the remote host in the list of hosts always allowed to use the iTerm2 API")
        host.width = 300
        let granted = NSTableColumn(identifier: Self.grantedColumn)
        granted.title = String(localized: "IT2HostGrants.GrantedColumn",
                               defaultValue: "Allowed Since",
                               comment: "Column header for when a remote host was first always allowed to use the iTerm2 API")
        granted.width = 170
        tableView.addTableColumn(host)
        tableView.addTableColumn(granted)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.stringValue = String(
            localized: "IT2HostGrants.Empty",
            defaultValue: "No remote hosts are always allowed. Choose Always Allow This Host when a remote host asks to control iTerm2.",
            comment: "Shown in place of the list when no remote hosts are always allowed to use the iTerm2 API")
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        removeButton.title = String(localized: "IT2HostGrants.Remove",
                                    defaultValue: "Remove",
                                    comment: "Button that stops always allowing the selected remote hosts to use the iTerm2 API")
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeSelected(_:))
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [explanation, scrollView, emptyLabel, removeButton] {
            content.addSubview(view)
        }
        let margin: CGFloat = 20
        NSLayoutConstraint.activate([
            explanation.topAnchor.constraint(equalTo: content.topAnchor, constant: margin),
            explanation.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            explanation.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),

            scrollView.topAnchor.constraint(equalTo: explanation.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),

            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: margin),
            emptyLabel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -margin),

            removeButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            removeButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            removeButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -margin),
        ])
    }

    // MARK: - Data

    /// Re-read the store, sorted by host so the order is stable.
    func reload() {
        grants = store.all.sorted { $0.host.localizedStandardCompare($1.host) == .orderedAscending }
        tableView.reloadData()
        emptyLabel.isHidden = !grants.isEmpty
        updateRemoveEnabled()
    }

    private func updateRemoveEnabled() {
        removeButton.isEnabled = !tableView.selectedRowIndexes.isEmpty
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return grants.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < grants.count else {
            return nil
        }
        let grant = grants[row]
        let text: String
        switch tableColumn.identifier {
        case Self.hostColumn:
            text = grant.host
        case Self.grantedColumn:
            text = dateFormatter.string(from: grant.granted)
        default:
            return nil
        }
        // A bare text field is pinned to the top of the row; wrap it to center it vertically.
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: text)
        field.lineBreakMode = .byTruncatingMiddle
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveEnabled()
    }

    // MARK: - Actions

    /// Revokes rather than just deleting the record, so a live connection the grant had let in
    /// asks again on its next command instead of staying allowed until it reconnects.
    @objc private func removeSelected(_ sender: Any?) {
        let hosts = tableView.selectedRowIndexes.compactMap { $0 < grants.count ? grants[$0].host : nil }
        for host in hosts {
            store.revoke(host: host)
        }
        reload()
    }

    // MARK: - Testing

    /// The hosts in the order shown. For tests.
    var displayedHosts: [String] {
        _ = view  // Loads it
        return grants.map(\.host)
    }

    /// Select rows by index and remove them, as the Remove button does. For tests.
    func removeRows(_ rows: IndexSet) {
        _ = view  // Loads it
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
        removeSelected(nil)
    }

    var isShowingEmptyState: Bool {
        _ = view  // Loads it
        return !emptyLabel.isHidden
    }

    var canRemove: Bool {
        _ = view  // Loads it
        return removeButton.isEnabled
    }
}
