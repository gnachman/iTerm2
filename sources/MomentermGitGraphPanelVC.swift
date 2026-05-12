//
//  MomentermGitGraphPanelVC.swift
//  iTerm2
//
//  Embeddable Git Graph viewer. Lives in iTermRootTerminalView's right-
//  side panel slot (mirroring the browser panel) so clicking the Git
//  Graph button in the bottom strip splits the terminal's right half
//  into a five-column commit table. The view controller owns the
//  NSTableView + header and reuses MomentermGitGraphCellView for the
//  custom Graph column.
//

import AppKit

@objc(MomentermGitGraphPanelDelegate)
protocol MomentermGitGraphPanelDelegate: AnyObject {
    /// Toggle whether the panel is embedded inline or in its own floating window.
    func momentermGitGraphPanelRequestDetachToggle()

    /// Close (hide) the panel.
    func momentermGitGraphPanelRequestClose()
}

@objc(MomentermGitGraphPanelVC)
final class MomentermGitGraphPanelVC: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    @objc weak var delegate: MomentermGitGraphPanelDelegate?

    @objc var isDetached: Bool = false {
        didSet { refreshDetachButtonIcon() }
    }

    private var currentCwd: String = ""
    private var commits: [MomentermGitCommit] = []
    private var filtered: [MomentermGitCommit] = []
    private var layout: MomentermGitGraphLayout = .empty

    private let header = NSView()
    private let cwdLabel = NSTextField(labelWithString: "(no repository)")
    private let searchField = NSSearchField()
    private let refreshButton = NSButton()
    private let detachButton = NSButton()
    private let closeButton = NSButton()

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 600))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        setupSubviews()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(graphUpdated(_:)),
            name: MomentermGitGraphPoller.didUpdateNotification,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    @objc func setCwd(_ cwd: String) {
        guard cwd != currentCwd else {
            refresh()
            return
        }
        currentCwd = cwd
        cwdLabel.stringValue = (cwd as NSString).abbreviatingWithTildeInPath
        let cached = MomentermGitGraphPoller.shared.commits(forCwd: cwd)
        if !cached.isEmpty {
            commits = cached
            applyFilter()
        }
        refresh()
    }

    @objc func refresh() {
        guard !currentCwd.isEmpty else { return }
        MomentermGitGraphPoller.shared.refresh(cwd: currentCwd)
    }

    @objc private func detachToggle() {
        delegate?.momentermGitGraphPanelRequestDetachToggle()
    }

    @objc private func closeTapped() {
        delegate?.momentermGitGraphPanelRequestClose()
    }

    private func refreshDetachButtonIcon() {
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let symbol = isDetached ? "rectangle.portrait.and.arrow.forward" : "rectangle.portrait.and.arrow.right"
        detachButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
        detachButton.toolTip = isDetached ? "Re-attach to terminal window" : "Detach into a separate window"
    }

    // MARK: - Setup

    private func setupSubviews() {
        header.translatesAutoresizingMaskIntoConstraints = false
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        cwdLabel.translatesAutoresizingMaskIntoConstraints = false
        cwdLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        cwdLabel.textColor = .secondaryLabelColor
        cwdLabel.lineBreakMode = .byTruncatingMiddle

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search"
        searchField.delegate = self
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: 11)

        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        func symBtn(_ btn: NSButton, sym: String, selector: Selector, tip: String) {
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.image = NSImage(systemSymbolName: sym, accessibilityDescription: tip)?.withSymbolConfiguration(cfg)
            btn.imagePosition = .imageOnly
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            btn.contentTintColor = .secondaryLabelColor
            btn.target = self
            btn.action = selector
            btn.toolTip = tip
        }
        symBtn(refreshButton, sym: "arrow.clockwise", selector: #selector(refresh), tip: "Refresh git graph")
        symBtn(detachButton, sym: "rectangle.portrait.and.arrow.right",
               selector: #selector(detachToggle), tip: "Detach into a separate window")
        detachButton.isHidden = true
        symBtn(closeButton, sym: "xmark", selector: #selector(closeTapped), tip: "Close panel")
        refreshDetachButtonIcon()

        header.addSubview(cwdLabel)
        header.addSubview(searchField)
        header.addSubview(refreshButton)
        header.addSubview(detachButton)
        header.addSubview(closeButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 22
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true

        addColumn("graph", title: "Graph", width: 110, min: 60, max: 220)
        addColumn("description", title: "Description", width: 220, min: 140, max: nil)
        addColumn("date", title: "Date", width: 120, min: 80, max: nil)
        addColumn("author", title: "Author", width: 110, min: 60, max: nil)
        addColumn("commit", title: "Commit", width: 80, min: 60, max: 140)

        scrollView.documentView = tableView

        view.addSubview(header)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 32),

            cwdLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            cwdLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            cwdLabel.trailingAnchor.constraint(lessThanOrEqualTo: searchField.leadingAnchor, constant: -8),

            searchField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 140),
            searchField.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -6),

            refreshButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: detachButton.leadingAnchor, constant: -2),
            refreshButton.widthAnchor.constraint(equalToConstant: 22),

            detachButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            detachButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: 0),
            detachButton.widthAnchor.constraint(equalToConstant: 0),

            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 22),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func addColumn(_ id: String, title: String, width: CGFloat, min: CGFloat, max: CGFloat?) {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        col.title = title
        col.width = width
        col.minWidth = min
        if let m = max { col.maxWidth = m }
        tableView.addTableColumn(col)
    }

    // MARK: - Data

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
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func descriptionCell(for commit: MomentermGitCommit, in tableView: NSTableView) -> NSView {
        let id = NSUserInterfaceItemIdentifier("MomentermGitGraph-description")
        if let cell = tableView.makeView(withIdentifier: id, owner: self) as? PanelDescriptionCellView {
            cell.configure(commit: commit)
            return cell
        }
        let cell = PanelDescriptionCellView()
        cell.identifier = id
        cell.configure(commit: commit)
        return cell
    }
}

// MARK: - Description cell

private final class PanelDescriptionCellView: NSTableCellView {

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
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not supported")
    }

    func configure(commit: MomentermGitCommit) {
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        for ref in commit.refs.prefix(3) {
            stack.addArrangedSubview(PanelRefPill(ref: ref))
        }
        let summary = NSTextField(labelWithString: commit.summary)
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .labelColor
        summary.lineBreakMode = .byTruncatingTail
        summary.cell?.usesSingleLineMode = true
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(summary)
    }
}

private final class PanelRefPill: NSView {
    init(ref: String) {
        super.init(frame: .zero)
        wantsLayer = true
        let isHEAD = ref.contains("HEAD")
        let display = ref.replacingOccurrences(of: "HEAD -> ", with: "")
        let color: NSColor = isHEAD ? .controlAccentColor : .systemYellow
        layer?.cornerRadius = 3
        layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor

        let label = NSTextField(labelWithString: display)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = color
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not supported")
    }
}
