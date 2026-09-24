import AppKit

/// An opt-in navigator for coding harnesses across windows. It never sends terminal input.
@objc final class SessionDirectorySidebar: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private final class ResizeGrip: NSView {
        var resize: ((CGFloat) -> Void)?
        var finished: (() -> Void)?
        private var startX: CGFloat = 0
        private var startWidth: CGFloat = 0
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
        override func mouseDown(with event: NSEvent) {
            startX = event.locationInWindow.x
            startWidth = superview?.bounds.width ?? 220
        }
        override func mouseDragged(with event: NSEvent) {
            resize?(startWidth + event.locationInWindow.x - startX)
        }
        override func mouseUp(with event: NSEvent) { finished?() }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.separatorColor.setFill()
            NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
        }
    }
    private let resizeGrip = ResizeGrip()
    private static let widthKey = "NoSyncHarnessSidebarWidth"
    @objc static var preferredWidth: CGFloat {
        let value = iTermUserDefaults.userDefaults().double(forKey: widthKey)
        return value > 0 ? min(640, max(160, value)) : 220
    }
    @objc var requestedWidth: CGFloat = SessionDirectorySidebar.preferredWidth
    @objc var widthDidChange: (() -> Void)?
    @objc var widthDidFinishChanging: (() -> Void)?

    private final class Group: NSObject {
        let key: SessionDirectoryKey
        var sessions: [Entry] = []
        init(key: SessionDirectoryKey) { self.key = key }
    }

    private final class Entry: NSObject {
        let id: String
        let name: String
        let runID: String
        let key: SessionDirectoryKey
        let external: HarnessProcessDiscovery.Harness?
        init(id: String, name: String, runID: String, key: SessionDirectoryKey, external: HarnessProcessDiscovery.Harness? = nil) {
            self.id = id
            self.name = name
            self.runID = runID
            self.key = key
            self.external = external
        }
        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Entry else { return false }
            return id == other.id && name == other.name && runID == other.runID && key == other.key && external == other.external
        }
        override var hash: Int { id.hashValue }
    }

    @objc var selectProjectTabAtIndex: ((Int) -> Void)?
    /// `reselect` is true only for an intentional project change. Refreshes and tab
    /// selection pass false so the selected tab stays visible and selection does not move.
    @objc var projectFilterDidChange: ((NSSet?, Bool) -> Bool)?

    private let heading = NSTextField(labelWithString: String(localized: "SessionDirectorySidebar.Title",
        defaultValue: "Coding harnesses", comment: "Title of the coding harness navigator"))
    private let emptyLabel = NSTextField(wrappingLabelWithString: String(localized: "SessionDirectorySidebar.Empty",
        defaultValue: "No coding harnesses detected.", comment: "Empty state of the coding harness navigator"))
    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private var groups: [Group] = []
    private var snapshot: [Entry] = []
    private var timer: Timer?
    private var activeSessionObserver: NSObjectProtocol?
    /// App-wide. Each sidebar is per window, so a per-instance set lets two windows
    /// stop or attach the same harness.
    private static var reservedHarnessIDs = Set<String>()
    private var ownedReservations = Set<String>()
    private static var attachedSessionIDs: [String: String] = [:]
    /// A session keeps its project when its tab moves between windows.
    private static var projectSessionKeys: [String: SessionDirectoryKey] = [:]
    /// Session ids that were in this window on the previous refresh. The first
    /// observation is only a baseline; later arrivals can join the selected project.
    private var observedWindowSessionIDs: Set<String>?
    private var selectedEntryID: String?
    private var selectedProject: SessionDirectoryKey?
    private var filterActive = false
    private let allProjectsButton = NSButton(title: String(localized: "SessionDirectorySidebar.AllProjects",
        defaultValue: "All projects", comment: "Clear the project tab filter"), target: nil, action: nil)
    private var refreshing = false
    private var nativeMonitors: [String: iTermTmuxOptionMonitor] = [:]
    private var pendingProbes = Set<String>()
    private var tmuxPanes: [String: HarnessTmuxProbe.Pane] = [:]
    private var tmuxClients: [String: HarnessTmuxProbe.Client] = [:]


    override init(frame: NSRect) {
        super.init(frame: frame)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("session"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 24
        outline.indentationPerLevel = 12
        outline.style = .sourceList
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clickedNativeHarness)
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
        allProjectsButton.target = self
        allProjectsButton.action = #selector(showAllProjects)
        addSubview(allProjectsButton)
        outline.setAccessibilityLabel(String(localized: "SessionDirectorySidebar.Accessibility",
            defaultValue: "Coding harnesses by directory", comment: "Accessibility label for the session navigator"))
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        scroll.frame = bounds
        addSubview(scroll)
        heading.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        addSubview(heading)
        emptyLabel.textColor = .secondaryLabelColor
        addSubview(emptyLabel)
        resizeGrip.resize = { [weak self] width in
            guard let self else { return }
            self.requestedWidth = min(640, max(160, width))
            self.widthDidChange?()
        }
        resizeGrip.finished = { [weak self] in
            guard let self else { return }
            iTermUserDefaults.userDefaults().set(self.requestedWidth, forKey: Self.widthKey)
            self.widthDidFinishChanging?()
        }
        addSubview(resizeGrip)
        needsLayout = true
    }

    required init?(coder: NSCoder) { it_fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        resizeGrip.frame = NSRect(x: max(0, bounds.width - 6), y: 0, width: 6, height: bounds.height)
        heading.frame = NSRect(x: 10, y: max(0, bounds.height - 28), width: max(0, bounds.width - 20), height: 20)
        scroll.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - 62))
        allProjectsButton.frame = NSRect(x: 10, y: max(0, bounds.height - 58), width: max(0, bounds.width - 20), height: 24)
        emptyLabel.frame = NSRect(x: 10, y: max(0, bounds.height - 92), width: max(0, bounds.width - 20), height: 52)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        if let activeSessionObserver {
            NotificationCenter.default.removeObserver(activeSessionObserver)
            self.activeSessionObserver = nil
        }
        guard window != nil else { return }
        activeSessionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(iTermSessionBecameKey), object: nil, queue: .main) { [weak self] notification in
                guard let self, let session = notification.object as? PTYSession,
                      let terminal = self.window?.windowController as? PseudoTerminal,
                      session.delegate?.realParentWindow() === terminal,
                      terminal.currentSession()?.guid == session.guid else { return }
                self.selectedTabDidChange(toSessionGUID: session.guid)
            }
        refresh()
        // Session metadata also changes without a tab insertion/removal (e.g. shell integration).
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 0.2
    }

    deinit {
        timer?.invalidate()
        if let activeSessionObserver { NotificationCenter.default.removeObserver(activeSessionObserver) }
        for monitor in nativeMonitors.values { monitor.invalidate() }
        for id in ownedReservations { Self.releaseHarnessOperation(id) }
    }

    // Called by iTermApplication after checking the focused editor and key mappings.
    @objc func handleProjectShortcut(_ event: NSEvent, digit: Int) -> Bool {
        guard event.type == .keyDown, event.window == nil || event.window === window else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        switch Self.shortcutAction(flags: flags, digit: digit,
                                   projectMask: Self.shortcutMask(for: kPreferenceKeySwitchWindowModifier),
                                   tabMask: Self.shortcutMask(for: kPreferenceKeySwitchTabModifier),
                                   projectCount: groups.count, filterActive: filterActive) {
        case .project(let index):
            if event.isARepeat { return true }
            let group = groups[index]
            outline.expandItem(group)
            selectProject(group)
            return true
        case .tab(let index):
            if !event.isARepeat { selectProjectTabAtIndex?(index) }
            return true
        case .pass:
            return false
        }
    }

    enum ShortcutAction: Equatable {
        case project(Int)
        case tab(Int)
        case pass
    }

    static func shortcutAction(flags: NSEvent.ModifierFlags, digit: Int,
                               projectMask: NSEvent.ModifierFlags?, tabMask: NSEvent.ModifierFlags?,
                               projectCount: Int, filterActive: Bool) -> ShortcutAction {
        guard (1...9).contains(digit) else { return .pass }
        if let projectMask, flags == projectMask, digit <= projectCount {
            return .project(digit - 1)
        }
        if filterActive, let tabMask, flags == tabMask { return .tab(digit - 1) }
        return .pass
    }

    private static func shortcutMask(for key: String) -> NSEvent.ModifierFlags? {
        guard let tag = iTermPreferencesModifierTag(rawValue: iTermPreferences.int(forKey: key)),
              tag != .preferenceModifierTagNone else { return nil }
        let mask = NSEvent.ModifierFlags(rawValue: iTermPreferences.mask(for: tag))
            .intersection([.command, .option, .shift, .control])
        return mask.isEmpty ? nil : mask
    }

    private static func launcherExecutable(_ process: iTermProcessInfo) -> String? {
        let name = SessionDirectoryKey.harnessName(executable: process.name, arguments: process.arguments)
            ?? SessionDirectoryKey.harnessName(executable: process.argv0, arguments: process.arguments)
        return name.flatMap { executable(forHarness: $0) }
    }

    private static func executable(forHarness name: String) -> String? {
        switch name {
        case "Codex": return "codex"
        case "Claude": return "claude"
        case "Gemini": return "gemini"
        case "Antigravity": return "agy"
        case "OpenCode": return "opencode"
        case "Aider": return "aider"
        default: return nil
        }
    }

    private func entry(for session: PTYSession) -> Entry? {
        let scope = session.genericScope
        var ordinaryTmux = false
        defer {
            if !ordinaryTmux {
                tmuxClients.removeValue(forKey: session.guid)
                tmuxPanes.removeValue(forKey: session.guid)
            }
        }
        var runID = ""
        var command = scope.stringValue(forVariableName: iTermVariableKeySessionJob)
        var path = scope.stringValue(forVariableName: iTermVariableKeySessionPath)
        if session.isTmuxClient, let gateway = session.tmuxController?.gateway {
            if nativeMonitors[session.guid] == nil {
                let monitor = iTermTmuxOptionMonitor(gateway: gateway,
                    format: "#{pane_current_command}\u{1f}#{pane_current_path}\u{1f}#{pane_pid}\u{1f}#{pane_start_command}",
                    target: "%\(session.tmuxPane)", block: nil)
                nativeMonitors[session.guid] = monitor
                monitor.startTimerIfSubscriptionsUnsupported()
                monitor.updateOnce()
            }
            let fields = nativeMonitors[session.guid]?.lastValue?.split(separator: "\u{1f}",
                maxSplits: 3, omittingEmptySubsequences: false)
            guard let fields, fields.count == 4 else { return nil }
            command = String(fields[0])
            path = String(fields[1])
            runID = String(fields[2])
            if command == "node" {
                let arguments = (String(fields[3]) as NSString).componentsInShellCommand()
                if let harness = SessionDirectoryKey.harnessName(executable: arguments.first, arguments: arguments) {
                    command = Self.executable(forHarness: harness) ?? command
                }
            }
            // Local tmux panes can be inspected through the process cache as well. Never
            // interpret an unverified remote PID as a local process ID.
            if session.screen.lastRemoteHost()?.isLocalhost == true,
               let pid = Int32(fields[2]), let process = session.processInfoProvider?.processInfo(for: pid) {
                command = Self.launcherExecutable(process) ?? command
            }
        } else if session.sshIdentity == nil && !(session.processInfoProvider is SSHProcessInfoProvider) {
            // Walk foreground ancestry: a harness can temporarily have a tool as its deepest job.
            var process = session.processInfoProvider?.deepestForegroundJob(for: session.shell.pid)
                ?? session.processInfoProvider?.processInfo(for: session.shell.pid)
            var visited = Set<Int32>()
            while let current = process, visited.insert(current.processID).inserted {
                if let executable = Self.launcherExecutable(current) {
                    runID = String(current.processID)
                    command = executable
                    break
                }
                if current.name == "tmux", let executable = current.executable,
                   executable.hasPrefix("/"), let arguments = current.arguments,
                   let socketArguments = HarnessTmuxProbe.socketArguments(arguments) {
                    ordinaryTmux = true
                    let client = HarnessTmuxProbe.Client(executable: executable,
                        socketArguments: socketArguments, pid: current.processID)
                    if tmuxClients[session.guid] != client {
                        tmuxClients[session.guid] = client
                        tmuxPanes.removeValue(forKey: session.guid)
                    }
                    if pendingProbes.insert(session.guid).inserted {
                        let id = session.guid
                        HarnessTmuxProbe.read(client) { [weak self] pane in
                            guard let self else { return }
                            self.pendingProbes.remove(id)
                            guard self.tmuxClients[id] == client else { return }
                            self.tmuxPanes[id] = pane
                            // Render on the next refresh; do not recursively start another probe.
                        }
                    }
                    guard let pane = tmuxPanes[session.guid] else { return nil }
                    runID = pane.id + ":" + String(pane.pid ?? 0)
                    command = pane.command
                    if let pid = pane.pid, let paneProcess = session.processInfoProvider?.processInfo(for: pid) {
                        command = Self.launcherExecutable(paneProcess) ?? command
                    }
                    path = pane.path
                    break
                }
                if current.processID == session.shell.pid { break }
                process = current.parent
            }
        }
        guard let harness = SessionDirectoryKey.harnessName(executable: command) else { return nil }
        let candidate = SessionDirectoryKey(
            host: scope.stringValue(forVariableName: iTermVariableKeySessionHostname),
            user: scope.stringValue(forVariableName: iTermVariableKeySessionUsername),
            path: path, sessionID: session.guid)
        let identity = harness + ":" + runID
        // Capture the first known directory for this harness run so tool-driven cd does not move it.
        let previous = snapshot.first { $0.id == session.guid && $0.runID == identity }
        let key: SessionDirectoryKey
        if let previous, previous.key.path != nil,
           previous.key.host == candidate.host, previous.key.user == candidate.user {
            key = previous.key
        } else {
            key = candidate
        }
        let isTmux = session.isTmuxClient || ordinaryTmux
        let name = isTmux ? harness + " · tmux — " + session.name : harness + " — " + session.name
        return Entry(id: session.guid, name: name, runID: identity, key: key)
    }

    private func refresh() {
        let sessions = (iTermController.sharedInstance()?.allSessions() ?? []).filter { !$0.exited }
        let ids = Set(sessions.map { $0.guid })
        Self.projectSessionKeys = Self.projectSessionKeys.filter { ids.contains($0.key) }
        Self.attachedSessionIDs = Self.attachedSessionIDs.filter { ids.contains($0.value) }
        for id in Array(nativeMonitors.keys) where !ids.contains(id) {
            nativeMonitors.removeValue(forKey: id)?.invalidate()
        }
        tmuxClients = tmuxClients.filter { ids.contains($0.key) }
        tmuxPanes = tmuxPanes.filter { ids.contains($0.key) }
        HarnessProcessDiscovery.shared.refreshIfNeeded()
        var entries = sessions.compactMap { entry(for: $0) }
        for harness in HarnessProcessDiscovery.shared.harnesses {
            let local = sessions.first { session in
                if Self.attachedSessionIDs[harness.id] == session.guid { return true }
                if harness.pid == session.shell.pid || harness.ancestors.contains(session.shell.pid) { return true }
                if let pane = tmuxPanes[session.guid], let pid = pane.pid,
                   harness.pid == pid || harness.ancestors.contains(pid) { return true }
                if session.isTmuxClient, session.screen.lastRemoteHost()?.isLocalhost == true,
                   let value = nativeMonitors[session.guid]?.lastValue {
                    let fields = value.split(separator: "\u{1f}", omittingEmptySubsequences: false)
                    if fields.count >= 3, let pid = Int32(fields[2]) {
                        return harness.pid == pid || harness.ancestors.contains(pid)
                    }
                }
                return false
            }
            let id = local?.guid ?? harness.id
            let candidate = SessionDirectoryKey(host: nil, user: NSUserName(),
                                                path: harness.directory, sessionID: id)
            let previous = snapshot.first { $0.id == id && $0.runID == harness.id && $0.key.path != nil }
            let key = previous?.key ?? candidate
            let title: String
            if let local {
                title = harness.name + (harness.tmuxSocket != nil ? " · tmux — " : " — ") + local.name
            } else if harness.tmuxSocket != nil {
                title = harness.name + " · tmux · " + String(harness.pid)
            } else if harness.tmuxUnverified {
                let source = String(localized: "SessionDirectorySidebar.MultiplexerUnverified",
                    defaultValue: "multiplexer unverified", comment: "Unverified multiplexer source label")
                title = harness.name + " · " + source + " · " + String(harness.pid)
            } else {
                let source = String(localized: "SessionDirectorySidebar.Native", defaultValue: "native",
                    comment: "Source label for a native harness process outside this iTerm2 instance")
                title = harness.name + " · " + source + " · " + String(harness.pid)
            }
            entries.removeAll { $0.id == id }
            entries.append(Entry(id: id, name: title, runID: harness.id, key: key,
                                 external: harness))
        }
        let windowIDs = windowSessionIDs(among: sessions)
        Self.projectSessionKeys = Self.adoptingWindowArrivals(keys: Self.projectSessionKeys,
                                                          previousWindowSessionIDs: observedWindowSessionIDs,
                                                          windowSessionIDs: windowIDs,
                                                          selectedProject: selectedProject)
        for entry in entries {
            let previousRun = snapshot.first { $0.id == entry.id }
            if let previousRun, previousRun.runID != entry.runID {
                Self.projectSessionKeys[entry.id] = entry.key
            } else if Self.projectSessionKeys[entry.id] == nil {
                Self.projectSessionKeys[entry.id] = entry.key
            }
        }
        observedWindowSessionIDs = windowIDs
        applyProjectFilter(.refresh)
        emptyLabel.isHidden = !entries.isEmpty
        guard entries != snapshot else {
            syncSelection()
            return
        }
        refreshing = true
        defer { refreshing = false }
        let oldGroups = Dictionary(uniqueKeysWithValues: groups.map { ($0.key, $0) })
        let collapsed = Set(groups.filter { !outline.isItemExpanded($0) }.map { $0.key })
        var byKey: [SessionDirectoryKey: Group] = [:]
        var next: [Group] = []
        // Keep existing group order when windows/tabs move. Append newly discovered directories.
        for key in groups.map({ $0.key }) + entries.map({ $0.key }) {
            guard byKey[key] == nil, entries.contains(where: { $0.key == key }) else { continue }
            let group = oldGroups[key] ?? Group(key: key)
            let oldOrder = Dictionary(uniqueKeysWithValues: group.sessions.enumerated().map { ($0.element.id, $0.offset) })
            group.sessions = entries.filter { $0.key == key }.enumerated().sorted {
                (oldOrder[$0.element.id] ?? (oldOrder.count + $0.offset)) <
                    (oldOrder[$1.element.id] ?? (oldOrder.count + $1.offset))
            }.map { $0.element }
            byKey[key] = group
            next.append(group)
        }
        groups = next
        snapshot = entries
        outline.reloadData()
        for group in groups where !collapsed.contains(group.key) { outline.expandItem(group) }
        syncSelection()
    }

    private func syncSelection() {
        let wasRefreshing = refreshing
        refreshing = true
        defer { refreshing = wasRefreshing }
        let terminal = window?.windowController as? PseudoTerminal
        let activeID = terminal?.currentSession()?.guid
        let selected = selectedEntryID.flatMap { id in snapshot.first { $0.id == id || $0.runID == id } }
        let row = (0..<outline.numberOfRows).first { row in
            if let entry = outline.item(atRow: row) as? Entry {
                if let selected { return entry.id == selected.id }
                return entry.id == activeID && (selectedProject == nil || entry.key == selectedProject)
            }
            return false
        } ?? (0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? Group)?.key == selectedProject }
        if let row {
            if outline.selectedRow != row { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        } else {
            outline.deselectAll(nil)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Group)?.sessions.count ?? (item == nil ? groups.count : 0)
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let group = item as? Group { return group.sessions[index] }
        return groups[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { item is Group }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { true }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingMiddle
        if let group = item as? Group {
            field.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            field.stringValue = group.key.path ?? String(localized: "SessionDirectorySidebar.UnknownDirectory",
                defaultValue: "Directory unavailable", comment: "Group label when no session directory is known")
            if let host = group.key.host {
                let identity = group.key.user.map { $0 + "@" + host } ?? host
                field.stringValue += " — " + identity
            }
            field.toolTip = field.stringValue
            if let index = groups.firstIndex(of: group), index < 9,
               let mask = Self.shortcutMask(for: kPreferenceKeySwitchWindowModifier) {
                field.stringValue = "\(NSString.modifierSymbols(mask: mask.rawValue))\(index + 1)  " + field.stringValue
            }
        } else if let entry = item as? Entry {
            field.stringValue = entry.name
            if let external = entry.external, external.isNative,
               iTermController.sharedInstance()?.anySession(withGUID: entry.id) == nil {
                field.toolTip = String(localized: "SessionDirectorySidebar.NativeTooltip",
                    defaultValue: "Open this saved conversation in a tmux-backed or native iTerm2 tab. The conversation is identified automatically; transferring closes the original process.",
                    comment: "Explains the resume choices for an external native harness")
            } else {
                field.toolTip = entry.name
            }
        }
        return field
    }

    private func activate(_ entry: Entry) {
        selectedEntryID = entry.runID
        if let session = iTermController.sharedInstance()?.anySession(withGUID: entry.id) {
            let destination = session.delegate?.realParentWindow() as? PseudoTerminal
            if let destination, destination.window !== window {
                selectedProject = nil
                selectedEntryID = nil
                applyProjectFilter(.projectChange)
            } else if destination == nil {
                selectedProject = entry.key
                applyProjectFilter(.projectChange)
            }
            session.reveal()
            destination?.selectHarnessProjectContainingSessionGUID(session.guid)
            return
        }
        selectedProject = entry.key
        applyProjectFilter(.projectChange)
        guard let external = entry.external, !external.tmuxUnverified,
              iTermLSOF.startTime(forProcess: external.pid) == external.started else { return }
        if let socket = external.tmuxSocket, let pane = external.tmuxPane {
            guard let executable = Self.tmuxExecutable else {
                showError(String(localized: "SessionDirectorySidebar.TmuxMissing", defaultValue: "Install tmux to attach this harness.", comment: "Missing tmux executable"))
                return
            }
            launchProjectTab(entry, arguments: [executable, "-N", "-S", socket, "attach-session", "-t", pane])
        } else {
            resumeNative(entry)
        }
    }

    @objc private func showAllProjects() {
        selectedProject = nil
        selectedEntryID = nil
        applyProjectFilter(.projectChange)
    }

    @objc(selectProjectContainingSessionGUID:)
    func selectProjectContainingSessionGUID(_ guid: String) {
        if !snapshot.contains(where: { $0.id == guid }) { refresh() }
        guard let entry = snapshot.first(where: { $0.id == guid }) else {
            showAllProjects()
            return
        }
        selectedProject = entry.key
        selectedEntryID = entry.runID
        applyProjectFilter(.projectChange)
        syncSelection()
    }

    enum ProjectFilterUpdate: Equatable {
        case refresh
        case projectChange
        case selectedTab
    }

    static func projectFilterReselects(_ update: ProjectFilterUpdate) -> Bool {
        update == .projectChange
    }

    /// Assigns the selected project to session ids that newly appeared in this window
    /// and do not already belong to a project. Existing keys are left alone, and the
    /// first observation (nil previous set) adopts nothing.
    static func adoptingWindowArrivals(keys: [String: SessionDirectoryKey],
                                        previousWindowSessionIDs: Set<String>?,
                                        windowSessionIDs: Set<String>,
                                        selectedProject: SessionDirectoryKey?) -> [String: SessionDirectoryKey] {
        guard let previousWindowSessionIDs, let selectedProject else { return keys }
        var adopted = keys
        for id in windowSessionIDs where !previousWindowSessionIDs.contains(id) && adopted[id] == nil {
            adopted[id] = selectedProject
        }
        return adopted
    }

    static func reserveHarnessOperation(_ id: String) -> Bool {
        reservedHarnessIDs.insert(id).inserted
    }

    static func releaseHarnessOperation(_ id: String) {
        reservedHarnessIDs.remove(id)
    }

    private func reserveOperation(_ id: String) -> Bool {
        guard Self.reserveHarnessOperation(id) else { return false }
        ownedReservations.insert(id)
        return true
    }

    private func releaseOperation(_ id: String) {
        ownedReservations.remove(id)
        Self.releaseHarnessOperation(id)
    }

    static func replacementLaunchFailureMessage(handoffPath: String) -> String {
        String(format: String(localized: "SessionDirectorySidebar.ReplacementLaunchFailed",
            defaultValue: "The original harness exited, but the replacement tab could not be opened. The recovery handoff is saved at %@.",
            comment: "Replacement session launch failed after the original process had already exited. %@ is the saved handoff file path."),
            handoffPath)
    }

    @objc(selectedTabDidChangeToSessionGUID:)
    func selectedTabDidChange(toSessionGUID guid: String?) {
        if let guid, !guid.isEmpty, let previous = observedWindowSessionIDs, !previous.contains(guid) {
            Self.projectSessionKeys = Self.adoptingWindowArrivals(keys: Self.projectSessionKeys,
                                                              previousWindowSessionIDs: previous,
                                                              windowSessionIDs: previous.union([guid]),
                                                              selectedProject: selectedProject)
            observedWindowSessionIDs?.insert(guid)
        }
        if let guid, let selectedProject, let tabProject = Self.projectSessionKeys[guid], tabProject != selectedProject {
            self.selectedProject = tabProject
            selectedEntryID = nil
        }
        applyProjectFilter(.selectedTab)
        syncSelection()
    }

    private func windowSessionIDs(among sessions: [PTYSession]) -> Set<String> {
        let controller = window?.windowController
        return Set(sessions.compactMap { session in
            guard session.delegate?.realParentWindow() === controller else { return nil }
            return session.guid
        })
    }

    private func applyProjectFilter(_ update: ProjectFilterUpdate) {
        let reselect = Self.projectFilterReselects(update)
        guard let selectedProject else {
            filterActive = false
            _ = projectFilterDidChange?(nil, reselect)
            return
        }
        let ids = Self.projectSessionKeys.filter { $0.value == selectedProject }.map { $0.key }
        filterActive = projectFilterDidChange?(NSSet(array: ids), reselect) ?? false
    }

    private static var tmuxExecutable: String? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .filter { $0.hasPrefix("/") }.map { String($0) + "/tmux" }
        return (paths + ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"])
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func shellCommand(_ arguments: [String]) -> String {
        arguments.map { ($0 as NSString).withEscapedShellCharacters(includingNewlines: true) }.joined(separator: " ")
    }

    private func launchProjectTab(_ entry: Entry, arguments: [String], holdsReservation: Bool = false, handoffPath: String? = nil) {
        let runID = entry.external?.id ?? entry.id
        if let id = Self.attachedSessionIDs[runID],
           let session = iTermController.sharedInstance()?.anySession(withGUID: id), !session.exited {
            if holdsReservation { releaseOperation(runID) }
            session.reveal()
            return
        }
        if !holdsReservation && !reserveOperation(runID) {
            DLog("Harness attach already reserved for \(runID)")
            return
        }
        selectedProject = entry.key
        iTermSessionLauncher.launchBookmark(nil,
            in: window?.windowController as? PseudoTerminal, style: .tab, withURL: nil,
            hotkeyWindowType: .none, makeKey: true, canActivate: true,
            respectTabbingMode: false, index: nil, command: Self.shellCommand(arguments), makeSession: nil,
            didMakeSession: { session in
                Self.projectSessionKeys[session.guid] = entry.key
            }, completion: { [self] session, ok in
                releaseOperation(runID)
                if ok {
                    Self.attachedSessionIDs[runID] = session.guid
                    Self.projectSessionKeys[session.guid] = entry.key
                    if let tab = session.delegate as? PTYTab, let path = entry.key.path {
                        tab.titleOverride = (path as NSString).lastPathComponent + " — " + (entry.external?.name ?? entry.name)
                    }
                } else if let handoffPath {
                    self.showError(Self.replacementLaunchFailureMessage(handoffPath: handoffPath))
                } else {
                    self.showError(String(localized: "SessionDirectorySidebar.LaunchFailed",
                        defaultValue: "Could not open the harness tab.", comment: "Session launch failed"))
                }
                self.applyProjectFilter(.refresh)
            })
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        if let window, window.isVisible {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard outline.clickedRow >= 0 else { return }
        if let group = outline.item(atRow: outline.clickedRow) as? Group {
            let item = NSMenuItem(title: String(localized: "SessionDirectorySidebar.AttachProject",
                defaultValue: "Attach Tmux Harnesses in Project", comment: "Open each tmux harness in this directory in its own tab"),
                action: #selector(attachProjectFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = group
            menu.addItem(item)
            return
        }
        guard let entry = outline.item(atRow: outline.clickedRow) as? Entry,
              let harness = entry.external, !harness.tmuxUnverified,
              iTermController.sharedInstance()?.anySession(withGUID: entry.id) == nil else { return }
        let title = harness.tmuxSocket != nil
            ? String(localized: "SessionDirectorySidebar.Attach", defaultValue: "Attach in Project Tab", comment: "Attach a running tmux harness")
            : String(localized: "SessionDirectorySidebar.Resume", defaultValue: "Open in iTerm2…", comment: "Choose a tmux or native tab for an external harness")
        let item = NSMenuItem(title: title, action: #selector(attachFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = entry
        menu.addItem(item)
    }

    @objc private func attachProjectFromMenu(_ sender: NSMenuItem) {
        guard let group = sender.representedObject as? Group else { return }
        for entry in group.sessions where entry.external?.tmuxSocket != nil { activate(entry) }
    }

    @objc private func attachFromMenu(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? Entry, let harness = entry.external,
              !harness.tmuxUnverified,
              iTermController.sharedInstance()?.anySession(withGUID: entry.id) == nil else { return }
        if harness.tmuxSocket != nil {
            activate(entry)
        } else {
            resumeNative(entry)
        }
    }

    @objc private func clickedNativeHarness() {
        guard outline.clickedRow >= 0,
              let entry = outline.item(atRow: outline.clickedRow) as? Entry,
              entry.external?.isNative == true,
              iTermController.sharedInstance()?.anySession(withGUID: entry.id) == nil else { return }
        activate(entry)
    }

    private func resumeNative(_ entry: Entry) {
        guard let harness = entry.external, harness.isNative,
              let directory = entry.key.path, window != nil,
              iTermController.sharedInstance()?.anySession(withGUID: entry.id) == nil else { return }
        guard reserveOperation(harness.id) else {
            DLog("Harness transfer already reserved for \(harness.id)")
            return
        }
        if let id = Self.attachedSessionIDs[harness.id],
           let session = iTermController.sharedInstance()?.anySession(withGUID: id), !session.exited {
            releaseOperation(harness.id)
            session.reveal()
            return
        }
        let visible = iTermController.sharedInstance()?.allSessions() ?? []
        let buried = iTermBuriedSessions.sharedInstance()?.buriedSessions() ?? []
        let hosted = visible + buried
        let protectedTTYs = Set((hosted + hosted.flatMap { $0.peerPort?.realizedPeerSessions ?? [] })
            .filter { !$0.exited }
            .compactMap { $0.tty }
            .compactMap { HarnessProcessDiscovery.ttyRdev(path: $0) })
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = HarnessProcessDiscovery.resumeTarget(for: harness, protectedTTYs: protectedTTYs)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let window = self.window else {
                    self.releaseOperation(harness.id)
                    return
                }
                guard case .success(let target) = result else {
                    self.releaseOperation(harness.id)
                    if case .failure(let block) = result { self.showError(Self.transferBlockMessage(block)) }
                    return
                }
                let alert = NSAlert()
                alert.messageText = String(localized: "SessionDirectorySidebar.OpenNativeTitle",
                    defaultValue: "Transfer Harness to iTerm2", comment: "Choose how to resume an external native harness")
                alert.informativeText = String(localized: "SessionDirectorySidebar.OpenNativeExplanation",
                    defaultValue: "Transfer only when the harness is idle. iTerm2 will save a recovery handoff, request that the original harness exit, and wait for it to close before resuming its saved conversation here. Unsaved input is not transferred.", comment: "Explain automatic conversation resume and original process lifecycle")
                alert.addButton(withTitle: String(localized: "SessionDirectorySidebar.OpenTmux",
                    defaultValue: "Transfer to Tmux Tab", comment: "Resume detected conversation in tmux"))
                alert.addButton(withTitle: String(localized: "SessionDirectorySidebar.OpenNative",
                    defaultValue: "Transfer to Native Tab", comment: "Resume detected conversation directly in iTerm2"))
                alert.addButton(withTitle: String(localized: "SessionDirectorySidebar.Cancel",
                    defaultValue: "Cancel", comment: "Cancel native resume"))
                alert.buttons[0].isEnabled = Self.tmuxExecutable != nil
                alert.beginSheetModal(for: window) { [weak self] response in
                    guard let self else { return }
                    guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else {
                        self.releaseOperation(harness.id)
                        return
                    }
                    guard iTermLSOF.startTime(forProcess: harness.pid) == harness.started else {
                        self.releaseOperation(harness.id)
                        self.showError(String(localized: "SessionDirectorySidebar.ProcessChanged",
                            defaultValue: "The original process has exited. Refresh the sidebar before opening it.", comment: "Process identity changed during resume prompt"))
                        return
                    }
                    do {
                        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                            appropriateFor: nil, create: true).appendingPathComponent("iTerm2/HarnessHandoffs", isDirectory: true)
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                            attributes: [.posixPermissions: 0o700])
                        let token = UUID().uuidString
                        let record: [String: Any] = ["directory": directory, "harness": harness.name,
                            "conversationID": target.conversationID, "transcript": target.transcript,
                            "originalPID": harness.pid, "originalStarted": harness.started.timeIntervalSince1970,
                            "created": Date().timeIntervalSince1970,
                            "handoff": "Resume the saved conversation for task context, changes, checks, and next steps. The user requested graceful shutdown of the original before resuming; unsaved state is not transferred."]
                        let file = folder.appendingPathComponent(token + ".json")
                        try JSONSerialization.data(withJSONObject: record, options: .prettyPrinted).write(to: file, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                        let command = Self.shellCommand(target.command)
                        let arguments: [String]
                        if response == .alertFirstButtonReturn, let tmux = Self.tmuxExecutable {
                            arguments = [tmux, "-L", "iterm2-harnesses", "new-session",
                                         "-s", "harness-" + token, "-c", directory, command]
                        } else if response == .alertSecondButtonReturn {
                            arguments = ["/bin/sh", "-c",
                                         "cd " + Self.shellCommand([directory]) + " && exec " + command]
                        } else {
                            self.releaseOperation(harness.id)
                            return
                        }
                        let handoffPath = file.path
                        // Once the original is told to exit, retain the handoff owner
                        // through the replacement launch even if its sidebar is hidden.
                        HarnessProcessDiscovery.stopForTransfer(harness, target: target,
                            protectedTTYs: protectedTTYs) { [self] outcome in
                            guard case .success = outcome else {
                                self.releaseOperation(harness.id)
                                if case .failure(let block) = outcome {
                                    self.showError(Self.transferFailureMessage(block, handoffPath: handoffPath))
                                }
                                return
                            }
                            self.launchProjectTab(entry, arguments: arguments, holdsReservation: true, handoffPath: handoffPath)
                        }
                    } catch {
                        self.releaseOperation(harness.id)
                        self.showError(error.localizedDescription)
                    }
                }
            }
        }
    }

    private static func transferBlockMessage(_ block: HarnessProcessDiscovery.TransferBlock) -> String {
        switch block {
        case .processChanged:
            return String(localized: "SessionDirectorySidebar.ProcessChanged",
                defaultValue: "The original process changed or exited. Refresh the sidebar before transferring it.",
                comment: "Process identity changed during transfer")
        case .insideMultiplexer:
            return String(localized: "SessionDirectorySidebar.UnverifiedMultiplexer",
                defaultValue: "This harness may be inside a terminal multiplexer, but its pane could not be verified. Transfer is unavailable.",
                comment: "Unverified terminal multiplexer prevents transfer")
        case .hostedByITerm:
            return String(localized: "SessionDirectorySidebar.AlreadyHosted",
                defaultValue: "This harness is already hosted by iTerm2. Select its existing tab instead.",
                comment: "Prevent transfer of an iTerm2-hosted process")
        case .unsupportedArguments(let names), .credentialEnvironment(let names):
            let reason = names.joined(separator: ", ")
            return String(format: String(localized: "SessionDirectorySidebar.UnsafeLaunch",
                defaultValue: "Transfer cannot safely reproduce these launch settings: %@. The original harness was not stopped.",
                comment: "Original launch options or credential environment cannot be carried"), reason)
        case .unsupportedHarness, .identityUnavailable, .busy:
            return String(localized: "SessionDirectorySidebar.IdentityUnavailable",
                defaultValue: "This harness’s saved conversation or launch settings could not be verified. Its original process was not stopped.",
                comment: "No exact process-linked conversation identity or safe launch settings found")
        case .didNotExit:
            return String(localized: "SessionDirectorySidebar.TransferIncomplete",
                defaultValue: "The original harness did not exit within 15 seconds. No replacement was started. The recovery handoff is saved. Check the original terminal before trying again.",
                comment: "Graceful transfer timed out without force killing the harness")
        }
    }

    static func transferFailureMessage(_ block: HarnessProcessDiscovery.TransferBlock,
                                       handoffPath: String) -> String {
        let location = String(format: String(localized: "SessionDirectorySidebar.SavedHandoffAt",
            defaultValue: "Recovery handoff saved at %@.",
            comment: "Location of a saved harness handoff after transfer did not complete"), handoffPath)
        return transferBlockMessage(block) + "\n\n" + location
    }

    private func selectProject(_ group: Group) {
        selectedProject = group.key
        applyProjectFilter(.projectChange)
        let local = group.sessions.first { iTermController.sharedInstance()?.anySession(withGUID: $0.id) != nil }
        selectedEntryID = nil
        let tmux = group.sessions.first { $0.external?.tmuxSocket != nil }
        if let entry = local ?? tmux { activate(entry) }
        else { syncSelection() }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !refreshing, outline.selectedRow >= 0 else { return }
        if let group = outline.item(atRow: outline.selectedRow) as? Group {
            selectProject(group)
        } else if let entry = outline.item(atRow: outline.selectedRow) as? Entry {
            activate(entry)
        }
    }
}
