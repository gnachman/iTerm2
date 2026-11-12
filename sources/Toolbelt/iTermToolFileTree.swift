import AppKit

@objcMembers
final class iTermToolFileTree: NSView, ToolbeltTool, NSOutlineViewDataSource, NSOutlineViewDelegate, SCEventListenerProtocol {
    var rootDirectory: String? {
        didSet {
            guard oldValue != rootDirectory else { return }
            treeState.setRoot(rootDirectory)
            resetViewForRoot()
        }
    }
    var openTerminal: ((String) -> Void)?
    private let treeState = iTermFileTreeState()
    private var source: iTermFileTreeDataSource { treeState.source }
    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private let header = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let hiddenButton = NSButton(checkboxWithTitle: String(localized: "FileTree.ShowHidden", defaultValue: "Show Hidden Files", comment: "Toggle visibility of hidden files"), target: nil, action: nil)
    private let refresh = NSButton(title: String(localized: "FileTree.Refresh", defaultValue: "Refresh", comment: "Refresh the loaded file tree"), target: nil, action: nil)
    private let retry = NSButton(title: String(localized: "FileTree.Retry", defaultValue: "Retry", comment: "Retry a failed directory read"), target: nil, action: nil)
    private var entries = [String: iTermFileTreeEntry]()
    private var loading: Set<String> {
        get { treeState.loadingPaths }
        set { treeState.loadingPaths = newValue }
    }
    private var expandedPaths: Set<String> {
        get { treeState.expandedPaths }
        set { treeState.expandedPaths = newValue }
    }
    private var selectedPath: String?
    private var retryPath: String?
    private var readErrors = [String: String]()
    private let watcher = SCEvents()
    private var refreshWork: DispatchWorkItem?
    private var changedPaths = Set<String>()
    private var observers = [NSObjectProtocol]()
    private var stopped = false
    private var visible = false
    private var restoring = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileTree")) // Localization unneeded: column identifier.
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(openSelection(_:))
        outline.backgroundColor = .controlBackgroundColor
        outline.setAccessibilityLabel(String(localized: "FileTree.Files", defaultValue: "Project Files", comment: "Accessible file tree name"))
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        addSubview(scroll)
        header.lineBreakMode = .byTruncatingMiddle
        status.textColor = .secondaryLabelColor
        for view in [header, status, hiddenButton, refresh, retry] { addSubview(view) }
        hiddenButton.target = self
        hiddenButton.action = #selector(toggleHidden(_:))
        refresh.target = self
        refresh.action = #selector(refreshAll(_:))
        retry.target = self
        retry.action = #selector(retryRead(_:))
        for button in [hiddenButton, refresh, retry] { button.setAccessibilityLabel(button.title) }
        retry.isHidden = true
        watcher._delegate = self
        watcher._notificationLatency = 0.5
        outline.menu = makeMenu()
        header.stringValue = String(localized: "FileTree.NoProject", defaultValue: "Select a Project", comment: "File tree header when no project is selected")
    }
    required init?(coder: NSCoder) { it_fatalError("init(coder:) has not been implemented") }
    static func isDynamic() -> Bool { false }
    required convenience init!(frame: NSRect, url: URL!, identifier: String!) {
        self.init(frame: frame)
    }
    static var supportedProfileTypes: ProfileType { .terminal }
    func minimumHeight() -> CGFloat { 150 }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        let width = max(0, bounds.width - 12)
        header.frame = NSRect(x: 6, y: 6, width: width, height: 22)
        hiddenButton.frame = NSRect(x: 6, y: 32, width: max(0, width - 72), height: 24)
        refresh.frame = NSRect(x: max(6, bounds.width - 78), y: 32, width: 72, height: 24)
        status.frame = NSRect(x: 6, y: max(60, bounds.height - 62), width: width, height: 34)
        retry.frame = NSRect(x: 6, y: max(94, bounds.height - 28), width: 70, height: 24)
        scroll.frame = NSRect(x: 0, y: 60, width: bounds.width, height: max(0, bounds.height - 124))
    }
    func relayout() { needsLayout = true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                    if notification.name == NSWindow.willCloseNotification { self?.shutdown() }
                    else { self?.updateVisibility() }
                })
            }
        }
        updateVisibility()
    }
    override func viewDidHide() { super.viewDidHide(); updateVisibility() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateVisibility() }
    private func resetViewForRoot() {
        stopWatching()
        selectedPath = nil
        readErrors.removeAll()
        entries.removeAll()
        treeState.clearPublishedTree()
        outline.reloadData()
        header.stringValue = rootDirectory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? String(localized: "FileTree.NoProject", defaultValue: "Select a Project", comment: "File tree header when no project is selected")
        header.toolTip = rootDirectory
        status.stringValue = ""
        retry.isHidden = true
        updateVisibility()
    }

    private func updateVisibility() {
        let nowVisible = !stopped && !isHiddenOrHasHiddenAncestor && window?.isVisible == true && window?.isMiniaturized == false && window?.occlusionState.contains(.visible) == true
        if !nowVisible {
            stopWatching()
            if visible {
                loading.removeAll()
                source.reset(rootPath: rootDirectory)
            }
        } else if let rootDirectory {
            if !watcher.isWatchingPaths { watcher.startWatchingPaths([rootDirectory]) }
            request(rootDirectory)
        }
        visible = nowVisible
    }
    private func stopWatching() {
        watcher.stopWatchingPaths()
        refreshWork?.cancel()
        refreshWork = nil
        changedPaths.removeAll()
    }
    func shutdown() {
        stopped = true
        stopWatching()
        loading.removeAll()
        source.reset(rootPath: nil)
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
    deinit {
        watcher.stopWatchingPaths()
        watcher._delegate = nil
        refreshWork?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    private func children(_ item: Any?) -> [iTermFileTreeEntry] {
        treeState.publishedChildren(of: item as? iTermFileTreeEntry)
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { children(item).count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { children(item)[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? iTermFileTreeEntry)?.isExpandable == true }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let entry = item as? iTermFileTreeEntry else { return nil }
        let label = NSTextField(labelWithString: entry.name)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = entry.path
        return label
    }
    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let entry = notification.userInfo?["NSObject"] as? iTermFileTreeEntry else { return }
        expandedPaths.insert(entry.path)
        request(entry.path)
    }
    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !restoring, let entry = notification.userInfo?["NSObject"] as? iTermFileTreeEntry else { return }
        expandedPaths.remove(entry.path)
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !restoring else { return }
        selectedPath = (outline.item(atRow: outline.selectedRow) as? iTermFileTreeEntry)?.path
    }
    private func request(_ path: String) {
        guard !stopped, (path == rootDirectory || entries[path]?.isExpandable == true), !loading.contains(path), source.cachedListing(atPath: path) == nil else { return }
        treeState.loadDirectory(atPath: path) { [weak self] result in
            guard let self else { return }
            guard path == self.rootDirectory || self.entries[path]?.isExpandable == true else { return }
            switch result {
            case .success(let children):
                let childPaths = Set(children.map(\.path))
                let expandablePaths = Set(children.filter(\.isExpandable).map(\.path))
                let removedPaths = self.entries.keys.filter {
                    URL(fileURLWithPath: $0).deletingLastPathComponent().path == path && (!childPaths.contains($0) || (self.entries[$0]?.isExpandable == true && !expandablePaths.contains($0)))
                }
                for removed in removedPaths {
                    let descendants = self.entries.keys.filter { $0 == removed || $0.hasPrefix(removed + "/") }
                    for descendant in descendants { self.entries.removeValue(forKey: descendant) }
                    let obsolete = Set(self.readErrors.keys).union(self.loading).union(self.expandedPaths).filter {
                        $0 == removed || $0.hasPrefix(removed + "/")
                    }
                    for descendant in obsolete { self.readErrors.removeValue(forKey: descendant) }
                    self.loading.subtract(obsolete)
                    self.expandedPaths.subtract(obsolete)
                    if let selected = self.selectedPath, selected == removed || selected.hasPrefix(removed + "/") { self.selectedPath = nil }
                }
                for entry in children {
                    if let existing = self.entries[entry.path], existing.isExpandable == entry.isExpandable { continue }
                    self.entries[entry.path] = entry
                }
                self.readErrors.removeValue(forKey: path)
                self.status.stringValue = children.isEmpty && path == self.rootDirectory ? String(localized: "FileTree.Empty", defaultValue: "This folder is empty.", comment: "Empty project root folder") : ""
            case .failure(let error):
                if (error as NSError).code == NSUserCancelledError { return }
                self.readErrors[path] = String(localized: "FileTree.ReadError", defaultValue: "Couldn’t read folder: \(error.localizedDescription)", comment: "Directory read failed; placeholder is system error description")
            }
            self.retryPath = self.readErrors.keys.sorted().first
            self.retry.isHidden = self.retryPath == nil
            if let failedPath = self.retryPath { self.status.stringValue = self.readErrors[failedPath] ?? "" }
            if case .success(let children) = result {
                self.treeState.publishDirectory(children.map { self.entries[$0.path] ?? $0 }, atPath: path)
            }
            self.restoreOutline()
        }
    }
    private func restoreOutline() {
        restoring = true
        outline.reloadData()
        for path in expandedPaths.sorted(by: { $0.count < $1.count }) {
            if let entry = entries[path], outline.row(forItem: entry) >= 0 { outline.expandItem(entry) }
        }
        if let selectedPath, let entry = entries[selectedPath] {
            let row = outline.row(forItem: entry)
            if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        }
        restoring = false
        // An already-expanded NSOutline item does not emit willExpand after cache reset.
        // Drive visible remembered expansions from current listings instead.
        for path in treeState.directoriesNeedingLoad() { request(path) }
    }
    @objc private func toggleHidden(_ sender: Any?) {
        loading.removeAll()
        readErrors.removeAll()
        source.showsHiddenFiles = hiddenButton.state == .on
        outline.reloadData()
        if let rootDirectory { request(rootDirectory) }
    }
    @objc private func refreshAll(_ sender: Any?) {
        var paths = Set(source.loadedDirectoryPaths)
        if let rootDirectory { paths.insert(rootDirectory) }
        refreshDirectories(paths)
    }
    private func refreshDirectories(_ paths: Set<String>) {
        DLog("Refreshing \(paths.count) loaded file tree directories")
        source.invalidate(directoryPaths: paths)
        loading.subtract(paths)
        for path in paths.sorted() { request(path) }
    }
    @objc private func retryRead(_ sender: Any?) {
        if let retryPath { refreshDirectories([retryPath]) }
    }
    func pathWatcher(_ pathWatcher: SCEvents!, eventOccurred event: SCEvent!) {
        guard let path = event?._eventPath else { return }
        let generation = source.generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.visible, !self.stopped, self.source.generation == generation else { return }
            self.changedPaths.insert(path)
            self.refreshWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let paths = Set(self.source.loadedDirectoryPaths.filter { loaded in
                    self.changedPaths.contains { changed in
                        loaded == changed || changed == "/" || loaded == "/" || loaded.hasPrefix(changed + "/") || changed.hasPrefix(loaded + "/")
                    }
                })
                self.changedPaths.removeAll()
                self.refreshDirectories(paths)
            }
            self.refreshWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }
    private func menuEntry() -> iTermFileTreeEntry? {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        return outline.item(atRow: row) as? iTermFileTreeEntry
    }
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let actions: [(String, Selector)] = [
            (String(localized: "FileTree.CopyRelative", defaultValue: "Copy Relative Path", comment: "Copy path relative to project root"), #selector(copyRelative(_:))),
            (String(localized: "FileTree.CopyAbsolute", defaultValue: "Copy Absolute Path", comment: "Copy full filesystem path"), #selector(copyAbsolute(_:))),
            (String(localized: "FileTree.Reveal", defaultValue: "Reveal in Finder", comment: "Show selected file in Finder"), #selector(reveal(_:))),
            (String(localized: "FileTree.NewTerminal", defaultValue: "New Terminal Here", comment: "Open terminal in selected directory or file parent"), #selector(newTerminal(_:)))
        ]
        for (title, selector) in actions { let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item) }
        return menu
    }
    @objc private func openSelection(_ sender: Any?) {
        guard let entry = outline.item(atRow: outline.clickedRow) as? iTermFileTreeEntry else { return }
        if entry.isExpandable {
            if outline.isItemExpanded(entry) { outline.collapseItem(entry) } else { outline.expandItem(entry) }
        } else {
            let generation = source.generation
            NSWorkspace.shared.open(URL(fileURLWithPath: entry.path), configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                if let error {
                    DispatchQueue.main.async {
                        guard let self, self.source.generation == generation else { return }
                        self.status.stringValue = String(localized: "FileTree.OpenError", defaultValue: "Couldn’t open file: \(error.localizedDescription)", comment: "Default application could not open a file; placeholder is error description")
                    }
                }
            }
        }
    }
    @objc private func copyAbsolute(_ sender: Any?) { if let entry = menuEntry() { copy(entry.path) } }
    @objc private func copyRelative(_ sender: Any?) {
        guard let entry = menuEntry(), let rootDirectory else { return }
        let prefix = rootDirectory == "/" ? "/" : rootDirectory + "/"
        if entry.path.hasPrefix(prefix) { copy(String(entry.path.dropFirst(prefix.count))) }
    }
    private func copy(_ path: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string) }
    @objc private func reveal(_ sender: Any?) { if let entry = menuEntry() { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) } }
    @objc private func newTerminal(_ sender: Any?) {
        guard let entry = menuEntry() else { return }
        openTerminal?(entry.isDirectory ? entry.path : URL(fileURLWithPath: entry.path).deletingLastPathComponent().path)
    }
    func restorableState() -> [AnyHashable: Any] { treeState.restorableState() }
    func restore(fromState state: [AnyHashable: Any]) {
        let previousRoot = rootDirectory
        treeState.restore(from: state)
        hiddenButton.state = source.showsHiddenFiles ? .on : .off
        rootDirectory = treeState.rootDirectory
        if previousRoot == rootDirectory { resetViewForRoot() }
        if visible { restoreOutline() }
    }
}
