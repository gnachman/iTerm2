import AppKit

class ClaudeCodeStatusPopoverViewController: NSViewController {
    private var tableView: NSTableView!
    private var sessions: [iTermSessionTabStatus] = []

    override var preferredContentSize: NSSize {
        get { NSSize(width: 320, height: 200) }
        set {}
    }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        view.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        tableView = ClickableTableView()
        tableView.allowsMultipleSelection = false
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 32
        tableView.selectionHighlightStyle = .none

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.width = 210
        nameColumn.minWidth = 100
        tableView.addTableColumn(nameColumn)

        let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusColumn.width = 96
        statusColumn.minWidth = 70
        tableView.addTableColumn(statusColumn)

        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view.widthAnchor.constraint(equalToConstant: preferredContentSize.width),
            view.heightAnchor.constraint(equalToConstant: preferredContentSize.height),
        ])

        reloadSessions()

        // TODO: Add Allow/Deny buttons here once a mechanism exists for injecting
        // keystrokes into Claude's TUI without ambiguity about which session to target.
    }

    private func reloadSessions() {
        sessions = claudeCodeSessions()
        tableView?.reloadData()
    }

    private func claudeCodeSessions() -> [iTermSessionTabStatus] {
        let filtered = SessionStatusController.instance.statuses.values.filter {
            ClaudeCodeSummaryBuilder.isClaudeCodeStatus($0.statusText)
        }
        return filtered.sorted { lhs, rhs in
            sortOrder(lhs.statusText) < sortOrder(rhs.statusText)
        }
    }

    private func sortOrder(_ statusText: String?) -> Int {
        switch statusText {
        case ClaudeCodeSummaryBuilder.waitingText: return 0
        case ClaudeCodeSummaryBuilder.workingText: return 1
        case ClaudeCodeSummaryBuilder.idleText:    return 2
        default: return 3
        }
    }

    private func sessionName(for sessionID: String) -> String {
        guard let session = iTermController.sharedInstance()?.session(withGUID: sessionID) else {
            return sessionID
        }
        return session.name ?? sessionID
    }

    private func pillColor(for status: iTermSessionTabStatus) -> NSColor {
        guard status.hasStatusTextColor else { return .secondaryLabelColor }
        let c = status.statusTextColor
        return NSColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
    }
}

// MARK: - Table view with pointing hand cursor and no selection highlight

private class ClickableTableView: NSTableView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                      options: [.cursorUpdate, .activeInActiveApp, .inVisibleRect],
                                      owner: self,
                                      userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
}

// MARK: - Pill view

private class StatusPillView: NSView {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { it_fatalError() }

    func configure(text: String, color: NSColor) {
        label.stringValue = text
        layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor
    }
}

// MARK: - NSTableViewDataSource

extension ClaudeCodeStatusPopoverViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return sessions.count
    }
}

// MARK: - NSTableViewDelegate

extension ClaudeCodeStatusPopoverViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let status = sessions[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("name")

        if identifier.rawValue == "name" {
            let cellID = NSUserInterfaceItemIdentifier("ClaudeCell-name")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = cellID
                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byTruncatingTail
                cell.textField = textField
                cell.addSubview(textField)
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            cell.textField?.stringValue = sessionName(for: status.sessionID)
            cell.textField?.textColor = .labelColor
            return cell

        } else {
            let cellID = NSUserInterfaceItemIdentifier("ClaudeCell-status")
            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView,
               let pill = reused.subviews.first as? StatusPillView {
                pill.configure(text: status.statusText ?? "", color: pillColor(for: status))
                return reused
            }
            let cell = NSTableCellView()
            cell.identifier = cellID
            let pill = StatusPillView()
            pill.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(pill)
            NSLayoutConstraint.activate([
                pill.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                pill.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -16),
                pill.widthAnchor.constraint(equalToConstant: 64),
                pill.heightAnchor.constraint(equalToConstant: 18),
            ])
            pill.configure(text: status.statusText ?? "", color: pillColor(for: status))
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 && row < sessions.count else { return }
        let sessionID = sessions[row].sessionID
        iTermController.sharedInstance()?.revealSession(withGUID: sessionID)
        view.window?.performClose(nil)
    }
}
