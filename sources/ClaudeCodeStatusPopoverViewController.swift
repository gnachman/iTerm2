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
        scrollView.drawsBackground = false

        tableView = SessionTableView()
        tableView.allowsMultipleSelection = false
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 36
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = NSSize(width: 0, height: 2)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("session"))
        column.minWidth = 200
        tableView.addTableColumn(column)

        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
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

// MARK: - Table view

private class SessionTableView: NSTableView {
    private var hoveredRow: Int = -1

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                      options: [.mouseMoved, .mouseEnteredAndExited,
                                                .cursorUpdate, .activeInActiveApp, .inVisibleRect],
                                      owner: self,
                                      userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if row(at: point) >= 0 {
            NSCursor.pointingHand.set()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHover(for: event)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateHover(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHoveredRow(-1)
    }

    private func updateHover(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setHoveredRow(row(at: point))
    }

    private func setHoveredRow(_ row: Int) {
        guard row != hoveredRow else { return }
        let previous = hoveredRow
        hoveredRow = row
        if previous >= 0 {
            (rowView(atRow: previous, makeIfNecessary: false) as? SessionRowView)?.isHovered = false
        }
        if row >= 0 {
            (rowView(atRow: row, makeIfNecessary: false) as? SessionRowView)?.isHovered = true
        }
    }
}

// MARK: - Row view with hover

private class SessionRowView: NSTableRowView {
    var isHovered = false {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovered else { return }
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

// MARK: - Session cell

private class SessionCellView: NSTableCellView {
    let nameLabel = NSTextField(labelWithString: "")
    let pill = StatusPillView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.textColor = .labelColor
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        textField = nameLabel
        addSubview(nameLabel)
        addSubview(pill)
        pill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pill.widthAnchor.constraint(equalToConstant: 68),
            pill.heightAnchor.constraint(equalToConstant: 20),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: pill.leadingAnchor, constant: -8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { it_fatalError() }
}

// MARK: - Pill view

private class StatusPillView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
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
        sessions.count
    }
}

// MARK: - NSTableViewDelegate

extension ClaudeCodeStatusPopoverViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("SessionRow")
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? SessionRowView {
            return reused
        }
        let rowView = SessionRowView()
        rowView.identifier = id
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let status = sessions[row]
        let id = NSUserInterfaceItemIdentifier("SessionCell")
        let cell: SessionCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? SessionCellView {
            cell = reused
        } else {
            cell = SessionCellView()
            cell.identifier = id
        }
        cell.nameLabel.stringValue = sessionName(for: status.sessionID)
        cell.pill.configure(text: status.statusText ?? "", color: pillColor(for: status))
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 && row < sessions.count else { return }
        iTermController.sharedInstance()?.revealSession(withGUID: sessions[row].sessionID)
        view.window?.performClose(nil)
    }
}
