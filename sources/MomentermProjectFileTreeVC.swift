//
//  MomentermProjectFileTreeVC.swift
//  iTerm2
//
//  Created by MomenTerm on 2026-04-19.
//

import AppKit

// MARK: - Delegate

protocol MomentermFileTreeDelegate: AnyObject {
    func fileTreeDidSelectFile(atPath path: String)
    func fileTreeDidSelectDirectory(atPath path: String)
}

// MARK: - File Node

private final class FileNode {
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileNode]?
    var isLoaded: Bool = false

    init(name: String, path: String, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
    }

    var displayName: String { name }

    var icon: NSImage? {
        if isDirectory {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }
}

// MARK: - Constants

private let ignoredDirectories: Set<String> = [
    ".git", "node_modules", ".next", "dist", "build", "out", ".cache",
    "__pycache__", ".mypy_cache", ".pytest_cache", "coverage", ".turbo",
    "vendor", ".pnpm-store", "Pods", ".build", "DerivedData",
]

// MARK: - View Controller

final class MomentermProjectFileTreeVC: NSViewController {

    weak var delegate: MomentermFileTreeDelegate?

    private var rootPath: String? {
        didSet {
            if oldValue != rootPath {
                loadRoot()
            }
        }
    }

    private var rootNode: FileNode?
    private var outlineView: NSOutlineView!
    private var scrollView: NSScrollView!
    private var pathLabel: NSTextField!
    private var searchField: NSSearchField!
    /// When non-nil, the outline view shows a flat list of search matches.
    private var searchResults: [FileNode]?
    private var agentIgnorePatterns: [String] = []

    // MARK: - Public API

    func setRootPath(_ path: String) {
        rootPath = path
        loadAgentIgnore(in: path)
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        setupUI()
    }

    private func setupUI() {
        // Path header
        pathLabel = NSTextField(labelWithString: "")
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        view.addSubview(pathLabel)

        // Search field
        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search files\u{2026}"
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        view.addSubview(searchField)

        // Scroll + outline
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        outlineView = NSOutlineView()
        outlineView.style = .sourceList
        outlineView.rowHeight = 20
        outlineView.indentationPerLevel = 14
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(doubleClicked)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileCol"))
        col.isEditable = false
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col

        scrollView.documentView = outlineView
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            pathLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            pathLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            pathLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            pathLabel.heightAnchor.constraint(equalToConstant: 16),

            searchField.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 4),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Data loading

    private func loadRoot() {
        guard let path = rootPath else {
            rootNode = nil
            outlineView?.reloadData()
            return
        }
        pathLabel?.stringValue = (path as NSString).abbreviatingWithTildeInPath
        let node = FileNode(name: (path as NSString).lastPathComponent, path: path, isDirectory: true)
        loadChildren(of: node)
        rootNode = node
        outlineView?.reloadData()
        outlineView?.expandItem(node)
    }

    private func loadChildren(of node: FileNode) {
        guard node.isDirectory, !node.isLoaded else { return }
        node.isLoaded = true

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: node.path) else {
            node.children = []
            return
        }

        var children: [FileNode] = []
        for name in contents.sorted() {
            if name.hasPrefix(".") && !name.hasSuffix(".md") { continue }
            if ignoredDirectories.contains(name) { continue }
            if isAgentIgnored(name: name, parent: node.path) { continue }

            let childPath = (node.path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: childPath, isDirectory: &isDir)
            children.append(FileNode(name: name, path: childPath, isDirectory: isDir.boolValue))
        }

        // Directories first, then files
        node.children = children.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name < $1.name
        }
    }

    private func loadAgentIgnore(in dir: String) {
        let ignorePath = (dir as NSString).appendingPathComponent(".agentignore")
        guard let content = try? String(contentsOfFile: ignorePath) else {
            agentIgnorePatterns = []
            return
        }
        agentIgnorePatterns = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private func isAgentIgnored(name: String, parent: String) -> Bool {
        for pattern in agentIgnorePatterns {
            let clean = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
            if name == clean || name.hasSuffix(clean) { return true }
        }
        return false
    }

    // MARK: - Actions

    @objc private func doubleClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
        if !node.isDirectory {
            delegate?.fileTreeDidSelectFile(atPath: node.path)
        }
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        let query = sender.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            searchResults = nil
        } else {
            var matches: [FileNode] = []
            if let root = rootNode {
                collectMatches(node: root, query: query, into: &matches)
            }
            searchResults = matches
        }
        outlineView.reloadData()
    }

    private func collectMatches(node: FileNode, query: String, into results: inout [FileNode]) {
        loadChildren(of: node)
        guard let children = node.children else { return }
        for child in children {
            if child.name.lowercased().contains(query) {
                results.append(child)
            }
            if child.isDirectory {
                collectMatches(node: child, query: query, into: &results)
            }
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension MomentermProjectFileTreeVC: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let results = searchResults {
            return item == nil ? results.count : 0
        }
        if item == nil { return rootNode != nil ? 1 : 0 }
        guard let node = item as? FileNode else { return 0 }
        loadChildren(of: node)
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let results = searchResults {
            return results[index]
        }
        if item == nil { return rootNode! }
        guard let node = item as? FileNode, let children = node.children else {
            it_fatalError("Unexpected nil children in file tree")
        }
        return children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if searchResults != nil { return false }
        guard let node = item as? FileNode else { return false }
        return node.isDirectory
    }
}

// MARK: - NSOutlineViewDelegate

extension MomentermProjectFileTreeVC: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("FileNodeCell")
        let cell = (outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = identifier

        cell.subviews.forEach { $0.removeFromSuperview() }

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let icon = node.icon {
            iconView.image = icon
        }

        let label = NSTextField(labelWithString: node.displayName)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail

        cell.addSubview(iconView)
        cell.addSubview(label)
        cell.textField = label
        cell.imageView = iconView

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
        if node.isDirectory {
            delegate?.fileTreeDidSelectDirectory(atPath: node.path)
        } else {
            delegate?.fileTreeDidSelectFile(atPath: node.path)
        }
    }
}
