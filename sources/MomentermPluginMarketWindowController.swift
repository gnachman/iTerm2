//
//  MomentermPluginMarketWindowController.swift
//  iTerm2
//
//  Cmd+Opt+P marketplace panel. Lists Claude Code plugins + MCP servers
//  from MomentermPluginRegistry, lets the user install each via
//  MomentermPluginInstaller, and offers a quick "Edit plugins.json"
//  button to extend the curated list.
//

import AppKit

@objc(MomentermPluginMarketWindowController)
final class MomentermPluginMarketWindowController: NSWindowController {

    @objc static let shared = MomentermPluginMarketWindowController()

    private let contentVC = MomentermPluginMarketVC()

    private init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        window.title = "MomenTerm — Plugin Marketplace"
        window.minSize = NSSize(width: 600, height: 380)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = contentVC

        if let screen = NSScreen.main {
            let frame = window.frame
            let x = screen.visibleFrame.midX - frame.width / 2
            let y = screen.visibleFrame.midY - frame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not supported")
    }

    @objc static func toggle() {
        let wc = shared
        if wc.window?.isVisible == true {
            wc.window?.orderOut(nil)
        } else {
            wc.showWindow(nil)
            wc.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc static func show() {
        shared.showWindow(nil)
        shared.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - View Controller

private final class MomentermPluginMarketVC: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    private let registry = MomentermPluginRegistry.shared
    private let installer = MomentermPluginInstaller.shared

    private var visibleItems: [MomentermPluginItem] = []

    private let searchField = NSSearchField()
    private let segmented = NSSegmentedControl()
    private let countLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let editButton = NSButton(title: "Edit plugins.json…", target: nil, action: nil)
    private let reloadButton = NSButton(title: "Reload", target: nil, action: nil)

    private enum Filter: Int { case all = 0, plugins = 1, mcp = 2 }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 520))
        view.wantsLayer = true
        setupSubviews()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registryChanged),
            name: MomentermPluginRegistry.didChangeNotification,
            object: nil)
        refreshItems()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupSubviews() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search plugins and MCP servers"
        searchField.delegate = self

        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.segmentStyle = .texturedRounded
        segmented.trackingMode = .selectOne
        segmented.segmentCount = 3
        segmented.setLabel("All", forSegment: 0)
        segmented.setLabel("Plugins", forSegment: 1)
        segmented.setLabel("MCP", forSegment: 2)
        segmented.selectedSegment = 0
        segmented.target = self
        segmented.action = #selector(filterChanged)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        tableView.headerView = nil
        tableView.rowHeight = 64
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.style = .inset
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("PluginItem"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        scrollView.documentView = tableView

        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.bezelStyle = .rounded
        editButton.target = self
        editButton.action = #selector(openUserFile)

        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.bezelStyle = .rounded
        reloadButton.target = self
        reloadButton.action = #selector(reloadRegistry)

        view.addSubview(searchField)
        view.addSubview(segmented)
        view.addSubview(countLabel)
        view.addSubview(scrollView)
        view.addSubview(editButton)
        view.addSubview(reloadButton)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: segmented.leadingAnchor, constant: -12),

            segmented.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            segmented.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            countLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            countLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),

            scrollView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            scrollView.bottomAnchor.constraint(equalTo: editButton.topAnchor, constant: -10),

            editButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            editButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            reloadButton.leadingAnchor.constraint(equalTo: editButton.trailingAnchor, constant: 8),
            reloadButton.centerYAnchor.constraint(equalTo: editButton.centerYAnchor),
        ])
    }

    // MARK: - Data

    @objc private func registryChanged() {
        refreshItems()
    }

    @objc private func filterChanged() {
        refreshItems()
    }

    @objc private func reloadRegistry() {
        _ = registry.reload()
    }

    @objc private func openUserFile() {
        let path = registry.userPluginsPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func currentFilter() -> Filter {
        return Filter(rawValue: segmented.selectedSegment) ?? .all
    }

    private func refreshItems() {
        let kind: MomentermPluginKind?
        switch currentFilter() {
        case .all:     kind = nil
        case .plugins: kind = .claudePlugin
        case .mcp:     kind = .mcp
        }
        visibleItems = registry.filter(query: searchField.stringValue, kind: kind)
        countLabel.stringValue = "\(visibleItems.count) item\(visibleItems.count == 1 ? "" : "s")"
        tableView.reloadData()
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        refreshItems()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return visibleItems.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = visibleItems[row]
        let identifier = NSUserInterfaceItemIdentifier("MomentermPluginRowView")
        let cell: PluginRowView
        if let recycled = tableView.makeView(withIdentifier: identifier, owner: self) as? PluginRowView {
            cell = recycled
        } else {
            cell = PluginRowView(frame: .zero)
            cell.identifier = identifier
        }
        let installKey = MomentermPluginInstaller.key(for: item)
        cell.configure(item: item, status: installer.status(forKey: installKey)) { [weak self] action in
            self?.handle(action: action, item: item, in: cell)
        }
        return cell
    }

    private func handle(action: PluginRowView.Action, item: MomentermPluginItem, in cell: PluginRowView) {
        switch action {
        case .install:
            cell.markInstalling()
            installer.install(item: item, progress: { line in
                cell.appendProgressLine(line)
            }, completion: { [weak cell] success, log in
                cell?.markFinished(success: success, log: log)
            })
        case .openSource:
            if let s = item.source, let url = URL(string: s) {
                NSWorkspace.shared.open(url)
            }
        case .copyInstall:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(item.install, forType: .string)
        }
    }
}

// MARK: - Row view

private final class PluginRowView: NSTableCellView {

    enum Action {
        case install
        case openSource
        case copyInstall
    }

    private let nameLabel = NSTextField(labelWithString: "")
    private let kindChip = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let installButton = NSButton(title: "Install", target: nil, action: nil)
    private let sourceButton = NSButton(title: "Source", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let progressLabel = NSTextField(labelWithString: "")

    private var actionHandler: ((Action) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not supported")
    }

    private func setupSubviews() {
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail

        kindChip.translatesAutoresizingMaskIntoConstraints = false
        kindChip.font = .systemFont(ofSize: 10, weight: .medium)
        kindChip.textColor = .secondaryLabelColor
        kindChip.alignment = .center
        kindChip.wantsLayer = true
        kindChip.layer?.cornerRadius = 4
        kindChip.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        kindChip.drawsBackground = false
        kindChip.isBezeled = false
        kindChip.isEditable = false

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2

        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.font = .systemFont(ofSize: 10, weight: .regular)
        progressLabel.textColor = .tertiaryLabelColor
        progressLabel.lineBreakMode = .byTruncatingHead
        progressLabel.maximumNumberOfLines = 1

        installButton.translatesAutoresizingMaskIntoConstraints = false
        installButton.bezelStyle = .rounded
        installButton.controlSize = .small
        installButton.target = self
        installButton.action = #selector(installTapped)

        sourceButton.translatesAutoresizingMaskIntoConstraints = false
        sourceButton.bezelStyle = .accessoryBarAction
        sourceButton.controlSize = .small
        sourceButton.target = self
        sourceButton.action = #selector(sourceTapped)

        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.bezelStyle = .accessoryBarAction
        copyButton.controlSize = .small
        copyButton.target = self
        copyButton.action = #selector(copyTapped)

        addSubview(nameLabel)
        addSubview(kindChip)
        addSubview(detailLabel)
        addSubview(progressLabel)
        addSubview(installButton)
        addSubview(sourceButton)
        addSubview(copyButton)

        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            kindChip.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            kindChip.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            kindChip.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            kindChip.heightAnchor.constraint(equalToConstant: 16),

            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: installButton.leadingAnchor, constant: -16),

            progressLabel.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 2),
            progressLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            progressLabel.trailingAnchor.constraint(equalTo: installButton.leadingAnchor, constant: -16),

            installButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            installButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            installButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),

            sourceButton.trailingAnchor.constraint(equalTo: installButton.leadingAnchor, constant: -6),
            sourceButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: sourceButton.leadingAnchor, constant: -6),
            copyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(item: MomentermPluginItem,
                   status: MomentermPluginInstaller.Status,
                   handler: @escaping (Action) -> Void) {
        actionHandler = handler
        nameLabel.stringValue = item.name
        kindChip.stringValue = " \(item.kind.displayName) "
        detailLabel.stringValue = item.detail
        sourceButton.isHidden = (item.source == nil)
        progressLabel.stringValue = ""
        applyStatus(status)
    }

    func markInstalling() {
        applyStatus(.installing)
    }

    func markFinished(success: Bool, log: String) {
        applyStatus(success ? .installed : .failed(log))
        if !success {
            // Surface the last line of log so the row hints at the failure.
            let lastLine = log.split(whereSeparator: { $0.isNewline }).last.map(String.init) ?? ""
            progressLabel.stringValue = lastLine
            progressLabel.textColor = .systemRed
        } else {
            progressLabel.textColor = .tertiaryLabelColor
        }
    }

    func appendProgressLine(_ line: String) {
        progressLabel.textColor = .tertiaryLabelColor
        progressLabel.stringValue = line
    }

    private func applyStatus(_ status: MomentermPluginInstaller.Status) {
        switch status {
        case .idle:
            installButton.title = "Install"
            installButton.isEnabled = true
        case .installing:
            installButton.title = "Installing…"
            installButton.isEnabled = false
        case .installed:
            installButton.title = "Installed"
            installButton.isEnabled = false
        case .failed:
            installButton.title = "Retry"
            installButton.isEnabled = true
        }
    }

    @objc private func installTapped() { actionHandler?(.install) }
    @objc private func sourceTapped() { actionHandler?(.openSource) }
    @objc private func copyTapped() { actionHandler?(.copyInstall) }
}
