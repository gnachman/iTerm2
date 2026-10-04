//
//  iTermIT2HostGrantsWindowController.swift
//  iTerm2SharedARC
//
//  The list of remote hosts the user chose to always allow to use the iTerm2 API over SSH
//  integration (see IT2HostGrants). Presented as a sheet from General > Magic. Read-only apart
//  from removing a host, since a grant can only be minted from the authorization prompt, where
//  the host proves it can receive the secret.
//
//  Built in code rather than a xib, and laid out with auto layout, because it is its own window.
//

import AppKit

@objc(iTermIT2HostGrantsWindowController)
final class IT2HostGrantsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    /// Held while the sheet is up. A sheet does not retain its window controller, so without
    /// this the controller would be released as soon as presentSheet returned.
    private static var presented: IT2HostGrantsWindowController?

    private static let hostColumn = NSUserInterfaceItemIdentifier("host")
    private static let grantedColumn = NSUserInterfaceItemIdentifier("granted")

    private let store: IT2HostGrantStore
    private var grants: [IT2HostGrant] = []
    private let tableView = NSTableView()
    private let removeButton = NSButton()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    @objc(presentSheetFor:)
    static func presentSheet(for parent: NSWindow?) {
        guard let parent else {
            return
        }
        let controller = IT2HostGrantsWindowController(store: .shared)
        presented = controller
        guard let sheet = controller.window else {
            return
        }
        parent.beginSheet(sheet) { _ in
            presented = nil
        }
    }

    init(store: IT2HostGrantStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: true)
        window.title = String(localized: "IT2HostGrants.WindowTitle",
                              defaultValue: "Remote Hosts Allowed to Control iTerm2",
                              comment: "Title of the sheet listing remote hosts always allowed to use the iTerm2 API over SSH integration")
        super.init(window: window)
        buildContent(in: window)
        reload()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    private func buildContent(in window: NSWindow) {
        let content = NSView()
        window.contentView = content

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

        let done = NSButton(title: String(localized: "IT2HostGrants.Done",
                                          defaultValue: "Done",
                                          comment: "Button that closes the list of remote hosts always allowed to use the iTerm2 API"),
                            target: self,
                            action: #selector(done(_:)))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.translatesAutoresizingMaskIntoConstraints = false

        for view in [explanation, scrollView, emptyLabel, removeButton, done] {
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

            done.centerYAnchor.constraint(equalTo: removeButton.centerYAnchor),
            done.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            done.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
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

    @objc private func done(_ sender: Any?) {
        guard let window, let parent = window.sheetParent else {
            window?.orderOut(nil)
            return
        }
        parent.endSheet(window)
    }

    // MARK: - Testing

    /// The hosts in the order shown. For tests.
    var displayedHosts: [String] {
        return grants.map(\.host)
    }

    /// Select rows by index and remove them, as the Remove button does. For tests.
    func removeRows(_ rows: IndexSet) {
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
        removeSelected(nil)
    }

    var isShowingEmptyState: Bool {
        return !emptyLabel.isHidden
    }

    var canRemove: Bool {
        return removeButton.isEnabled
    }
}
