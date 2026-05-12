//
//  MomentermGitGraphWindowController.swift
//  iTerm2
//
//  Standalone window that shows the git DAG of the cwd from the terminal
//  window that triggered it, presented as an NSTableView with the columns
//  every git client needs: Graph | Description | Date | Author | Commit.
//  The leftmost Graph column is drawn by MomentermGitGraphCellView.
//

import AppKit

@objc(MomentermGitGraphWindowController)
final class MomentermGitGraphWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    @objc static let shared = MomentermGitGraphWindowController()

    private var currentCwd: String = ""
    private var commits: [MomentermGitCommit] = []
    private var filtered: [MomentermGitCommit] = []
    private var layout: MomentermGitGraphLayout = .empty

    private let header = NSView()
    private let cwdLabel = NSTextField(labelWithString: "(no repository)")
    private let searchField = NSSearchField()
    private let refreshButton = NSButton(title: "↻", target: nil, action: nil)

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true)
        window.title = "MomenTerm — Git Graph"
        window.minSize = NSSize(width: 640, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupSubviews()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(graphUpdated(_:)),
            name: MomentermGitGraphPoller.didUpdateNotification,
            object: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    @objc func showForCwd(_ cwd: String) {
        setCwd(cwd)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleForCwd(_ cwd: String) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            showForCwd(cwd)
        }
    }

    // MARK: - Setup

    private func setupSubviews() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        header.translatesAutoresizingMaskIntoConstraints = false
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        cwdLabel.translatesAutoresizingMaskIntoConstraints = false
        cwdLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cwdLabel.textColor = .secondaryLabelColor
        cwdLabel.lineBreakMode = .byTruncatingMiddle

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search commits, refs, authors"
        searchField.delegate = self

        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.bezelStyle = .regularSquare
        refreshButton.isBordered = false
        refreshButton.font = .systemFont(ofSize: 14, weight: .medium)
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        refreshButton.toolTip = "Refresh git graph"

        header.addSubview(cwdLabel)
        header.addSubview(searchField)
        header.addSubview(refreshButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 24
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true

        let graphCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("graph"))
        graphCol.title = "Graph"
        graphCol.width = 120
        graphCol.minWidth = 60
        graphCol.maxWidth = 320
        tableView.addTableColumn(graphCol)

        let descCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("description"))
        descCol.title = "Description"
        descCol.width = 460
        descCol.minWidth = 220
        tableView.addTableColumn(descCol)

        let dateCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateCol.title = "Date"
        dateCol.width = 130
        dateCol.minWidth = 90
        tableView.addTableColumn(dateCol)

        let authorCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("author"))
        authorCol.title = "Author"
        authorCol.width = 140
        authorCol.minWidth = 80
        tableView.addTableColumn(authorCol)

        let commitCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("commit"))
        commitCol.title = "Commit"
        commitCol.width = 90
        commitCol.minWidth = 70
        commitCol.maxWidth = 140
        tableView.addTableColumn(commitCol)

        scrollView.documentView = tableView

        content.addSubview(header)
        content.addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 36),

            cwdLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            cwdLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            cwdLabel.trailingAnchor.constraint(lessThanOrEqualTo: searchField.leadingAnchor, constant: -12),

            searchField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 260),
            searchField.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -8),

            refreshButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            refreshButton.widthAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    // MARK: - Data flow

    @objc private func setCwd(_ cwd: String) {
        currentCwd = cwd
        cwdLabel.stringValue = (cwd as NSString).abbreviatingWithTildeInPath
        let cached = MomentermGitGraphPoller.shared.commits(forCwd: cwd)
        if !cached.isEmpty {
            commits = cached
            applyFilter()
        }
        refresh()
    }

    @objc private func refresh() {
        guard !currentCwd.isEmpty else { return }
        MomentermGitGraphPoller.shared.refresh(cwd: currentCwd)
    }

    @objc private func graphUpdated(_ note: Notification) {
        guard let cwd = note.userInfo?["cwd"] as? String, cwd == currentCwd else { return }
        commits = MomentermGitGraphPoller.shared.commits(forCwd: cwd)
        applyFilter()
    }

    private func applyFilter() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            filtered = commits
        } else {
            filtered = commits.filter { c in
                if c.summary.lowercased().contains(q) { return true }
                if c.author.lowercased().contains(q) { return true }
                if c.shortSha.lowercased().contains(q) { return true }
                if c.refs.contains(where: { $0.lowercased().contains(q) }) { return true }
                return false
            }
        }
        layout = MomentermGitGraphLayouter.layout(commits: filtered)
        tableView.reloadData()
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return filtered.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let col = tableColumn else { return nil }
        let commit = filtered[row]
        switch col.identifier.rawValue {
        case "graph":
            let id = NSUserInterfaceItemIdentifier("MomentermGitGraphCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? MomentermGitGraphCellView) ?? MomentermGitGraphCellView()
            cell.identifier = id
            cell.layout = layout
            cell.rowIndex = row
            return cell
        case "description":
            return descriptionCell(for: commit, in: tableView)
        case "date":
            return textCell(in: tableView, identifier: "date",
                            string: dateFormatter.string(from: commit.date),
                            font: .systemFont(ofSize: 11),
                            color: .secondaryLabelColor)
        case "author":
            return textCell(in: tableView, identifier: "author",
                            string: commit.author,
                            font: .systemFont(ofSize: 11),
                            color: .secondaryLabelColor)
        case "commit":
            return textCell(in: tableView, identifier: "commit",
                            string: commit.shortSha,
                            font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                            color: .tertiaryLabelColor)
        default:
            return nil
        }
    }

    // MARK: - Cell builders

    private func textCell(in tableView: NSTableView, identifier: String, string: String,
                          font: NSFont, color: NSColor) -> NSTableCellView {
        let id = NSUserInterfaceItemIdentifier("MomentermGitGraph-\(identifier)")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? makeTextCell(identifier: id)
        cell.textField?.font = font
        cell.textField?.textColor = color
        cell.textField?.stringValue = string
        return cell
    }

    private func makeTextCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.lineBreakMode = .byTruncatingTail
        tf.cell?.usesSingleLineMode = true
        cell.addSubview(tf)
        cell.textField = tf
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func descriptionCell(for commit: MomentermGitCommit, in tableView: NSTableView) -> NSView {
        let id = NSUserInterfaceItemIdentifier("MomentermGitGraph-description")
        if let cell = tableView.makeView(withIdentifier: id, owner: self) as? DescriptionCellView {
            cell.configure(commit: commit)
            return cell
        }
        let cell = DescriptionCellView()
        cell.identifier = id
        cell.configure(commit: commit)
        return cell
    }
}

// MARK: - Description cell

private final class DescriptionCellView: NSTableCellView {

    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not supported")
    }

    func configure(commit: MomentermGitCommit) {
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        for ref in commit.refs.prefix(4) {
            stack.addArrangedSubview(RefPill(ref: ref))
        }
        let summary = NSTextField(labelWithString: commit.summary)
        summary.font = .systemFont(ofSize: 12)
        summary.textColor = .labelColor
        summary.lineBreakMode = .byTruncatingTail
        summary.cell?.usesSingleLineMode = true
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(summary)
    }
}

private final class RefPill: NSView {
    init(ref: String) {
        super.init(frame: .zero)
        wantsLayer = true
        let isHEAD = ref.contains("HEAD")
        let display = ref.replacingOccurrences(of: "HEAD -> ", with: "")
        let color: NSColor = isHEAD ? .controlAccentColor : .systemYellow
        layer?.cornerRadius = 4
        layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor

        let label = NSTextField(labelWithString: display)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = color
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not supported")
    }
}
