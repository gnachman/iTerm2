import AppKit

@objcMembers
final class iTermToolFileTree: NSView, ToolbeltTool, NSOutlineViewDataSource, NSOutlineViewDelegate {
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
    private let options = NSButton()
    private let folderIcon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let folderImage = NSImage(systemSymbolName: SFSymbol.folder.rawValue, accessibilityDescription: nil)
    private let documentImage = NSImage(systemSymbolName: SFSymbol.docText.rawValue, accessibilityDescription: nil)
    private var hiddenItem: NSMenuItem!
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
    private var openError: String?
    private var watcher: iTermFileTreeWatcher?
    private var refreshWork: DispatchWorkItem?
    private var changedPaths = Set<String>()
    private var observers = [NSObjectProtocol]()
    private var stopped = false
    private var visible = false
    private var restoring = false
    private var pendingResults = [String: iTermFileTreeDataSource.Listing]()
    private var publicationWork: DispatchWorkItem?
    private var refreshOnResume = false
    private var resumeRefreshWork: DispatchWorkItem?
    private var statusLayout: (hasFooter: Bool, hasRetry: Bool)?
    private var spinnerIsRunning = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileTree")) // Localization unneeded: column identifier.
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        column.minWidth = 40
        outline.rowHeight = 24
        outline.intercellSpacing = .zero
        outline.indentationPerLevel = 14
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.autoresizesOutlineColumn = false
        outline.style = .sourceList
        outline.focusRingType = .none
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
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.isHidden = true
        folderIcon.image = folderImage
        folderIcon.contentTintColor = .controlAccentColor
        folderIcon.imageScaling = .scaleProportionallyDown
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        for view in [folderIcon, header, status, spinner, options, refresh, retry] { addSubview(view) }
        configureIconButton(refresh, symbol: .arrowClockwise, action: #selector(refreshAll(_:)))
        configureIconButton(options, symbol: .ellipsis, action: #selector(showOptions(_:)))
        options.toolTip = String(localized: "FileTree.Options", defaultValue: "File Tree Options", comment: "Tooltip for the file tree options menu")
        options.setAccessibilityLabel(options.toolTip)
        let menu = NSMenu()
        hiddenItem = NSMenuItem(title: String(localized: "FileTree.ShowHidden", defaultValue: "Show Hidden Files", comment: "Toggle visibility of hidden files"), action: #selector(toggleHidden(_:)), keyEquivalent: "")
        hiddenItem.target = self
        menu.addItem(hiddenItem)
        options.menu = menu
        retry.target = self
        retry.action = #selector(retryRead(_:))
        retry.controlSize = .small
        retry.isHidden = true
        retry.setAccessibilityLabel(retry.title)
        watcher = iTermFileTreeWatcher { [weak self] root, paths in
            self?.fileTreePathsChanged(paths, root: root)
        }
        outline.menu = makeMenu()
        header.stringValue = String(localized: "FileTree.NoProject", defaultValue: "Select a Project", comment: "File tree header when no project is selected")
    }
    required init?(coder: NSCoder) { it_fatalError("init(coder:) has not been implemented") }
    static func isDynamic() -> Bool { false }
    required convenience init!(frame: NSRect, url: URL!, identifier: String!) {
        self.init(frame: frame)
    }
    static var supportedProfileTypes: ProfileType { .terminal }
    func minimumHeight() -> CGFloat { 100 }
    override var isFlipped: Bool { true }
    private func configureIconButton(_ button: NSButton, symbol: SFSymbol, action: Selector) {
        let label = button.title
        button.image = NSImage(systemSymbolName: symbol.rawValue, accessibilityDescription: nil)
        button.title = ""
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.controlSize = .small
        button.target = self
        button.action = action
    }
    override func layout() {
        super.layout()
        setFrame(NSRect(x: 10, y: 10, width: 16, height: 16), for: folderIcon)
        setFrame(NSRect(x: 33, y: 9, width: max(0, bounds.width - 112), height: 18), for: header)
        setFrame(NSRect(x: max(36, bounds.width - 76), y: 10, width: 16, height: 16), for: spinner)
        setFrame(NSRect(x: max(36, bounds.width - 57), y: 5, width: 24, height: 24), for: refresh)
        setFrame(NSRect(x: max(60, bounds.width - 31), y: 5, width: 24, height: 24), for: options)
        let footerHeight: CGFloat = hasStatusFooter ? 38 : 0
        setFrame(NSRect(x: 0, y: 35, width: bounds.width, height: max(0, bounds.height - 35 - footerHeight)), for: scroll)
        if let column = outline.outlineTableColumn, scroll.contentSize.width > 0 {
            let width = max(40, scroll.contentSize.width)
            if column.width != width { column.width = width }
        }
        if footerHeight > 0 {
            if status.alignment != .left { status.alignment = .left }
            setFrame(NSRect(x: 10, y: max(35, bounds.height - 35), width: max(0, bounds.width - (retry.isHidden ? 20 : 82)), height: 30), for: status)
            setFrame(NSRect(x: max(10, bounds.width - 68), y: max(35, bounds.height - 31), width: 58, height: 23), for: retry)
        } else {
            if status.alignment != .center { status.alignment = .center }
            let retryY = max(35, min(100, bounds.height - 28))
            let statusHeight = retry.isHidden ? 48 : max(0, min(48, retryY - 42))
            setFrame(NSRect(x: 18, y: retry.isHidden ? 48 : 38, width: max(0, bounds.width - 36), height: statusHeight), for: status)
            setFrame(NSRect(x: max(10, (bounds.width - 58) / 2), y: retryY, width: 58, height: 23), for: retry)
        }
    }
    private func setFrame(_ frame: NSRect, for view: NSView) {
        if view.frame != frame { view.frame = frame }
    }
    private var hasStatusFooter: Bool { (!readErrors.isEmpty || openError != nil) && !entries.isEmpty }
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
        openError = nil
        publicationWork?.cancel()
        publicationWork = nil
        pendingResults.removeAll()
        entries = treeState.preparePublishedTreeFromCache()
        refreshOnResume = source.cachedListing(atPath: rootDirectory ?? "") != nil
        restoreOutline()
        header.stringValue = rootDirectory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? String(localized: "FileTree.NoProject", defaultValue: "Select a Project", comment: "File tree header when no project is selected")
        header.toolTip = rootDirectory
        updateStatus()
        updateVisibility(preparedForRoot: true)
    }

    private func updateVisibility(preparedForRoot: Bool = false) {
        let nowVisible = !stopped && !isHiddenOrHasHiddenAncestor && window?.isVisible == true && window?.isMiniaturized == false && window?.occlusionState.contains(.visible) == true
        if !nowVisible {
            stopWatching()
            if visible {
                loading.removeAll()
                source.cancelPendingRequests()
                publicationWork?.cancel()
                publicationWork = nil
                pendingResults.removeAll()
                refreshOnResume = true
            }
        }
        let wasVisible = visible
        visible = nowVisible
        if nowVisible, let rootDirectory {
            if !wasVisible && !preparedForRoot {
                entries = treeState.preparePublishedTreeFromCache()
                restoreOutline()
            }
            watcher?.watch(root: rootDirectory)
            request(rootDirectory)
            if refreshOnResume {
                scheduleResumeRefresh()
            }
        }
        updateStatus()
    }
    private func scheduleResumeRefresh() {
        guard resumeRefreshWork == nil else { return }
        let generation = source.generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.visible, !self.stopped, self.source.generation == generation else { return }
            self.resumeRefreshWork = nil
            self.refreshAll(nil)
        }
        resumeRefreshWork = work
        // Present retained rows first and coalesce rapid tab/project switches before refreshing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    private func stopWatching() {
        watcher?.stop()
        resumeRefreshWork?.cancel()
        resumeRefreshWork = nil
        refreshWork?.cancel()
        refreshWork = nil
        changedPaths.removeAll()
    }
    func shutdown() {
        stopped = true
        publicationWork?.cancel()
        publicationWork = nil
        pendingResults.removeAll()
        stopWatching()
        loading.removeAll()
        source.reset(rootPath: nil)
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
    deinit {
        watcher?.stop()
        refreshWork?.cancel()
        resumeRefreshWork?.cancel()
        publicationWork?.cancel()
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
        let identifier = NSUserInterfaceItemIdentifier("FileTreeCell") // Localization unneeded: reuse identifier.
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? iTermSidebarCellView ?? iTermSidebarCellView(frame: .zero)
        cell.identifier = identifier
        cell.configure(name: entry.name, path: entry.path, image: entry.isDirectory ? folderImage : documentImage, folder: entry.isDirectory)
        return cell
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
        guard visible, !stopped, (path == rootDirectory || entries[path]?.isExpandable == true), !loading.contains(path), source.cachedListing(atPath: path) == nil else { return }
        treeState.loadDirectory(atPath: path) { [weak self] result in
            guard let self, !self.stopped else { return }
            self.pendingResults[path] = result
            self.schedulePublication()
        }
        updateStatus()
    }
    private func schedulePublication() {
        guard publicationWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.publishPendingResults() }
        publicationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: work)
    }
    private func publishPendingResults() {
        publicationWork = nil
        guard !stopped, visible else { pendingResults.removeAll(); return }
        let results = pendingResults
        pendingResults.removeAll()
        var publications = [String: [iTermFileTreeEntry]]()
        var changed = Set<String>()
        for path in results.keys.sorted(by: { $0.count < $1.count }) {
            guard path == rootDirectory || entries[path]?.isExpandable == true, let result = results[path] else { continue }
            switch result {
            case .success(let children):
                let expandablePaths = Set(children.filter(\.isExpandable).map(\.path))
                let childPaths = Set(children.map(\.path))
                let parent = path == rootDirectory ? nil : entries[path]
                let removed = treeState.publishedChildren(of: parent).filter {
                    !childPaths.contains($0.path) || ($0.isExpandable && !expandablePaths.contains($0.path))
                }
                for item in removed {
                    let prefix = item.path + "/"
                    for descendant in Array(entries.keys) where descendant == item.path || descendant.hasPrefix(prefix) { entries.removeValue(forKey: descendant) }
                    let obsolete = Set(readErrors.keys).union(loading).union(expandedPaths).filter { $0 == item.path || $0.hasPrefix(prefix) }
                    for descendant in obsolete { readErrors.removeValue(forKey: descendant) }
                    loading.subtract(obsolete)
                    expandedPaths.subtract(obsolete)
                    if let selectedPath, selectedPath == item.path || selectedPath.hasPrefix(prefix) { self.selectedPath = nil }
                }
                for entry in children {
                    if let existing = entries[entry.path], existing.isExpandable == entry.isExpandable, existing.isDirectory == entry.isDirectory { continue }
                    entries[entry.path] = entry
                }
                publications[path] = children.map { entries[$0.path] ?? $0 }
                readErrors.removeValue(forKey: path)
                changed.insert(path)
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    readErrors[path] = String(localized: "FileTree.ReadError", defaultValue: "Couldn’t read folder: \(error.localizedDescription)", comment: "Directory read failed; placeholder is system error description")
                }
            }
        }
        updateStatus()
        // Publish immediately before outline invalidation, so old row counts never see IO cache changes.
        for path in publications.keys.sorted(by: { $0.count < $1.count }) {
            treeState.publishDirectory(publications[path] ?? [], atPath: path)
        }
        if !changed.isEmpty { treeState.cachePublishedTree(canonicalEntries: entries) }
        if !changed.isEmpty { restoreOutline(reloading: changed) }
    }
    private func updateStatus() {
        retryPath = readErrors.keys.sorted().first
        let retryHidden = retryPath == nil
        if retry.isHidden != retryHidden { retry.isHidden = retryHidden }
        let text: String?
        if let openError {
            text = openError
        } else if let retryPath {
            text = readErrors[retryPath] ?? ""
        } else if rootDirectory == nil {
            text = String(localized: "FileTree.NoProject", defaultValue: "Select a Project", comment: "File tree prompt when no project is selected")
        } else if entries.isEmpty, loading.isEmpty, case .success(let children)? = source.cachedListing(atPath: rootDirectory ?? ""), children.isEmpty {
            text = String(localized: "FileTree.Empty", defaultValue: "This folder is empty.", comment: "Empty project root folder")
        } else {
            text = nil
        }
        if let text, status.stringValue != text { status.stringValue = text }
        if status.isHidden != (text == nil) { status.isHidden = text == nil }
        let running = !loading.isEmpty
        if spinnerIsRunning != running {
            spinnerIsRunning = running
            if running { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        }
        let layout = (hasFooter: hasStatusFooter, hasRetry: !retryHidden)
        if statusLayout?.hasFooter != layout.hasFooter || statusLayout?.hasRetry != layout.hasRetry {
            statusLayout = layout
            needsLayout = true
        }
    }
    private func restoreOutline(reloading paths: Set<String>? = nil) {
        restoring = true
        let fullReload = paths == nil || paths?.contains(rootDirectory ?? "") == true
        if fullReload { outline.reloadData() }
        else if let paths {
            for path in paths.sorted(by: { $0.count < $1.count }) {
                if let entry = entries[path] { outline.reloadItem(entry, reloadChildren: true) }
            }
        }
        let expansions = expandedPaths.filter { path in fullReload || paths?.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) == true }
        for path in expansions.sorted(by: { $0.count < $1.count }) {
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
    @objc private func showOptions(_ sender: Any?) {
        hiddenItem.state = source.showsHiddenFiles ? .on : .off
        options.menu?.popUp(positioning: nil, at: NSPoint(x: options.frame.minX, y: options.frame.maxY), in: self)
    }
    @objc private func toggleHidden(_ sender: Any?) {
        resumeRefreshWork?.cancel()
        resumeRefreshWork = nil
        refreshOnResume = false
        publicationWork?.cancel()
        publicationWork = nil
        pendingResults.removeAll()
        loading.removeAll()
        readErrors.removeAll()
        source.showsHiddenFiles.toggle()
        hiddenItem.state = source.showsHiddenFiles ? .on : .off
        if let rootDirectory { request(rootDirectory) }
    }
    @objc private func refreshAll(_ sender: Any?) {
        resumeRefreshWork?.cancel()
        resumeRefreshWork = nil
        refreshOnResume = false
        openError = nil
        for path in treeState.refreshVisibleDirectories() { request(path) }
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
    private func fileTreePathsChanged(_ paths: [String], root: String) {
        guard visible, !stopped, rootDirectory == root else { return }
        let generation = source.generation
        changedPaths.formUnion(paths)
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.visible, !self.stopped, self.rootDirectory == root,
                  self.source.generation == generation else { return }
            let paths = Set(self.source.loadedDirectoryPaths.filter { loaded in
                self.changedPaths.contains { changed in
                    loaded == changed || changed == "/" || loaded == "/" || loaded.hasPrefix(changed + "/") || changed.hasPrefix(loaded + "/")
                }
            })
            self.changedPaths.removeAll()
            self.refreshDirectories(paths)
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
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
        openError = nil
        updateStatus()
        if entry.isExpandable {
            if outline.isItemExpanded(entry) { outline.collapseItem(entry) } else { outline.expandItem(entry) }
        } else {
            let generation = source.generation
            NSWorkspace.shared.open(URL(fileURLWithPath: entry.path), configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                if let error {
                    DispatchQueue.main.async {
                        guard let self, self.source.generation == generation else { return }
                        self.openError = String(localized: "FileTree.OpenError", defaultValue: "Couldn’t open file: \(error.localizedDescription)", comment: "Default application could not open a file; placeholder is error description")
                        self.updateStatus()
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
        hiddenItem.state = source.showsHiddenFiles ? .on : .off
        rootDirectory = treeState.rootDirectory
        if previousRoot == rootDirectory { resetViewForRoot() }
        if visible { restoreOutline() }
    }
}
