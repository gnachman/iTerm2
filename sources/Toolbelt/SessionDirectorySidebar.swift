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
    @objc var projectFilterDidChange: ((NSSet?) -> Void)?

    private let heading = NSTextField(labelWithString: String(localized: "SessionDirectorySidebar.Title",
        defaultValue: "Coding harnesses", comment: "Title of the coding harness navigator"))
    private let emptyLabel = NSTextField(wrappingLabelWithString: String(localized: "SessionDirectorySidebar.Empty",
        defaultValue: "No coding harnesses detected.", comment: "Empty state of the coding harness navigator"))
    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private var groups: [Group] = []
    private var snapshot: [Entry] = []
    private var timer: Timer?
    private var keyMonitor: Any?
    private var pendingAttachments = Set<String>()
    private var attachedSessionIDs: [String: String] = [:]
    private var observedSessionIDs: Set<String>?
    private var lastActiveSessionID: String?
    private var selectedProject: SessionDirectoryKey?
    private var projectSessionKeys: [String: SessionDirectoryKey] = [:]
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
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if self.selectedProject != nil,
               event.modifierFlags.intersection([.command, .option, .shift, .control]) == [.command],
               let character = event.characters(byApplyingModifiers: []), character.count == 1,
               let number = Int(character), (1...9).contains(number) {
                if !event.isARepeat { self.selectProjectTabAtIndex?(number - 1) }
                return nil
            }
            guard let index = Self.shortcutIndex(event),
                  index < self.groups.count else { return event }
            if event.isARepeat { return nil }
            let group = self.groups[index]
            self.outline.expandItem(group)
            self.selectProject(group)
            return nil
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
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        for monitor in nativeMonitors.values { monitor.invalidate() }
    }

    static func shortcutIndex(_ event: NSEvent) -> Int? {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        guard flags == [.command, .option],
              let characters = event.characters(byApplyingModifiers: []),
              characters.count == 1, let number = Int(characters), (1...9).contains(number) else { return nil }
        return number - 1
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
        projectSessionKeys = projectSessionKeys.filter { ids.contains($0.key) }
        attachedSessionIDs = attachedSessionIDs.filter { ids.contains($0.value) }
        for id in Array(nativeMonitors.keys) where !ids.contains(id) {
            nativeMonitors.removeValue(forKey: id)?.invalidate()
        }
        tmuxClients = tmuxClients.filter { ids.contains($0.key) }
        tmuxPanes = tmuxPanes.filter { ids.contains($0.key) }
        HarnessProcessDiscovery.shared.refreshIfNeeded()
        var entries = sessions.compactMap { entry(for: $0) }
        for harness in HarnessProcessDiscovery.shared.harnesses {
            let local = sessions.first { session in
                if attachedSessionIDs[harness.id] == session.guid { return true }
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
            } else {
                let source = String(localized: "SessionDirectorySidebar.Native", defaultValue: "native",
                    comment: "Source label for a native harness process outside this iTerm2 instance")
                title = harness.name + " · " + source + " · " + String(harness.pid)
            }
            entries.removeAll { $0.id == id }
            entries.append(Entry(id: id, name: title, runID: harness.id, key: key,
                                 external: harness))
        }
        for entry in entries { projectSessionKeys[entry.id] = entry.key }
        if let selectedProject, let observedSessionIDs {
            for session in sessions where !observedSessionIDs.contains(session.guid) && projectSessionKeys[session.guid] == nil {
                if session.delegate?.realParentWindow() === window?.windowController {
                    projectSessionKeys[session.guid] = selectedProject
                }
            }
        }
        observedSessionIDs = ids
        if let terminal = window?.windowController as? PseudoTerminal,
           let active = terminal.currentSession(), active.guid != lastActiveSessionID {
            lastActiveSessionID = active.guid
            if selectedProject != nil, let key = projectSessionKeys[active.guid] { selectedProject = key }
        }
        applyProjectFilter()
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
        guard let activeID = iTermController.sharedInstance()?.currentTerminal?.currentSession()?.guid else {
            outline.deselectAll(nil)
            return
        }
        if let row = (0..<outline.numberOfRows).first(where: { (outline.item(atRow: $0) as? Entry)?.id == activeID }) {
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
            if let index = groups.firstIndex(of: group), index < 9 {
                field.stringValue = "⌥⌘\(index + 1)  " + field.stringValue
            }
        } else if let entry = item as? Entry {
            field.stringValue = entry.name
            if let external = entry.external, external.tmuxSocket == nil {
                field.toolTip = String(localized: "SessionDirectorySidebar.NativeTooltip",
                    defaultValue: "Running native process. Use its original terminal to interact; selecting this row brings that application forward when available.",
                    comment: "Explains the limits of interacting with a native process owned by another application")
            } else {
                field.toolTip = entry.name
            }
        }
        return field
    }

    private func activate(_ entry: Entry) {
        selectedProject = entry.key
        applyProjectFilter()
        if let session = iTermController.sharedInstance()?.anySession(withGUID: entry.id) {
            session.reveal()
            return
        }
        guard let external = entry.external,
              iTermLSOF.startTime(forProcess: external.pid) == external.started else { return }
        if let socket = external.tmuxSocket, let pane = external.tmuxPane {
            guard let executable = Self.tmuxExecutable else {
                showError(String(localized: "SessionDirectorySidebar.TmuxMissing", defaultValue: "Install tmux to attach this harness.", comment: "Missing tmux executable"))
                return
            }
            launchProjectTab(entry, arguments: [executable, "-N", "-S", socket, "attach-session", "-t", pane])
        } else {
            // Native PTYs cannot be transplanted. Reveal their owning application when known.
            for pid in external.ancestors {
                if let owner = NSRunningApplication(processIdentifier: pid), let url = owner.bundleURL {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                    break
                }
            }
        }
    }

    @objc private func showAllProjects() {
        selectedProject = nil
        applyProjectFilter()
    }

    private func applyProjectFilter() {
        guard let selectedProject else {
            projectFilterDidChange?(nil)
            return
        }
        let ids = projectSessionKeys.filter { $0.value == selectedProject }.map { $0.key }
        projectFilterDidChange?(NSSet(array: ids))
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

    private func launchProjectTab(_ entry: Entry, arguments: [String]) {
        let runID = entry.external?.id ?? entry.id
        if let id = attachedSessionIDs[runID],
           let session = iTermController.sharedInstance()?.anySession(withGUID: id), !session.exited {
            session.reveal()
            return
        }
        guard pendingAttachments.insert(runID).inserted else { return }
        selectedProject = entry.key
        iTermSessionLauncher.launchBookmark(nil,
            in: window?.windowController as? PseudoTerminal, style: .tab, withURL: nil,
            hotkeyWindowType: .none, makeKey: true, canActivate: true,
            respectTabbingMode: false, index: nil, command: Self.shellCommand(arguments), makeSession: nil,
            didMakeSession: { [weak self] session in
                self?.projectSessionKeys[session.guid] = entry.key
            }, completion: { [weak self] session, ok in
                guard let self else { return }
                self.pendingAttachments.remove(runID)
                if ok {
                    self.attachedSessionIDs[runID] = session.guid
                    self.projectSessionKeys[session.guid] = entry.key
                    if let tab = session.delegate as? PTYTab, let path = entry.key.path {
                        tab.titleOverride = (path as NSString).lastPathComponent + " — " + (entry.external?.name ?? entry.name)
                    }
                } else {
                    self.showError(String(localized: "SessionDirectorySidebar.LaunchFailed",
                        defaultValue: "Could not open the harness tab.", comment: "Session launch failed"))
                }
                self.applyProjectFilter()
            })
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        if let window { alert.beginSheetModal(for: window) }
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
              let harness = entry.external else { return }
        let title = harness.tmuxSocket != nil
            ? String(localized: "SessionDirectorySidebar.Attach", defaultValue: "Attach in Project Tab", comment: "Attach a running tmux harness")
            : String(localized: "SessionDirectorySidebar.Resume", defaultValue: "Resume in Tmux…", comment: "Save a handoff and resume a native harness in tmux")
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
        guard let entry = sender.representedObject as? Entry, let harness = entry.external else { return }
        if harness.tmuxSocket != nil {
            activate(entry)
        } else {
            resumeNative(entry)
        }
    }

    static func resumeArguments(harness: String, conversationID: String) -> [String]? {
        // Require a specific identity, never an option or an implicit latest conversation.
        guard !conversationID.isEmpty, !conversationID.hasPrefix("-"),
              conversationID.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        switch harness {
        case "Codex": return ["resume", conversationID]
        case "Claude": return ["--resume", conversationID]
        case "Antigravity": return ["--conversation", conversationID]
        default: return nil
        }
    }

    private func resumeNative(_ entry: Entry) {
        guard let harness = entry.external, let directory = entry.key.path,
              let tmux = Self.tmuxExecutable, let window,
              iTermLSOF.startTime(forProcess: harness.pid) == harness.started else {
            showError(String(localized: "SessionDirectorySidebar.ResumeUnavailable",
                defaultValue: "Resuming requires tmux, a running harness, and a known project directory.", comment: "Native resume prerequisites"))
            return
        }
        guard Self.resumeArguments(harness: harness.name, conversationID: "id") != nil else {
            showError(String(localized: "SessionDirectorySidebar.UnsupportedResume",
                defaultValue: "Resuming in tmux is supported for Codex, Claude, and Antigravity.", comment: "Unsupported harness resume"))
            return
        }
        var executableName: NSString?
        guard let argv = iTermLSOF.rawCommandLineArguments(forProcess: harness.pid, execName: &executableName),
              let executable = executableName as String?, executable.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: executable) else { return }
        var prefix = [executable]
        if (executable as NSString).lastPathComponent == "node", argv.count > 1 {
            prefix.append(argv[1])
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "SessionDirectorySidebar.ResumeTitle",
            defaultValue: "Resume Harness in Tmux", comment: "Native harness handoff dialog")
        alert.informativeText = String(localized: "SessionDirectorySidebar.ResumeExplanation",
            defaultValue: "Wait until the original harness is idle. Enter its saved conversation ID and a handoff with changes, checks, and next steps. This opens a resumed process in a project tab; the original stays open. Use only one copy of the conversation at a time.", comment: "Explain handoff and resume without moving or stopping the native process")
        alert.addButton(withTitle: String(localized: "SessionDirectorySidebar.SaveAndResume",
            defaultValue: "Save Handoff and Resume", comment: "Save handoff before starting a resumed harness"))
        alert.addButton(withTitle: String(localized: "SessionDirectorySidebar.Cancel",
            defaultValue: "Cancel", comment: "Cancel native resume"))
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 145))
        let identity = NSTextField(frame: NSRect(x: 0, y: 112, width: 420, height: 24))
        identity.placeholderString = String(localized: "SessionDirectorySidebar.ConversationID",
            defaultValue: "Saved conversation ID", comment: "Conversation identity input")
        let handoff = NSTextField(frame: NSRect(x: 0, y: 32, width: 420, height: 72))
        handoff.placeholderString = String(localized: "SessionDirectorySidebar.Handoff",
            defaultValue: "Changes, checks, next steps…", comment: "Recovery handoff input")
        handoff.usesSingleLineMode = false
        let idle = NSButton(checkboxWithTitle: String(localized: "SessionDirectorySidebar.Idle",
            defaultValue: "The original harness is idle", comment: "User confirms original process is idle"), target: nil, action: nil)
        idle.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
        accessory.addSubview(identity)
        accessory.addSubview(handoff)
        accessory.addSubview(idle)
        alert.accessoryView = accessory
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let id = identity.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = handoff.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard idle.state == .on, !note.isEmpty,
                  let resume = Self.resumeArguments(harness: harness.name, conversationID: id),
                  iTermLSOF.startTime(forProcess: harness.pid) == harness.started else {
                self.showError(String(localized: "SessionDirectorySidebar.HandoffRequired",
                    defaultValue: "Confirm the original harness is idle and provide its conversation ID and handoff before resuming.", comment: "Incomplete native handoff"))
                return
            }
            do {
                let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true).appendingPathComponent("iTerm2/HarnessHandoffs", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                let token = UUID().uuidString
                let file = folder.appendingPathComponent(token + ".json")
                let record: [String: Any] = ["directory": directory, "harness": harness.name,
                    "conversationID": id, "handoff": note, "originalPID": harness.pid,
                    "created": Date().timeIntervalSince1970]
                try JSONSerialization.data(withJSONObject: record, options: .prettyPrinted).write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                // An isolated named server leaves existing tmux configuration and sessions alone.
                self.launchProjectTab(entry, arguments: [tmux, "-L", "iterm2-harnesses", "new-session",
                    "-s", "harness-" + token, "-c", directory, Self.shellCommand(prefix + resume)])
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    private func selectProject(_ group: Group) {
        selectedProject = group.key
        applyProjectFilter()
        let local = group.sessions.first { iTermController.sharedInstance()?.anySession(withGUID: $0.id) != nil }
        if let entry = local ?? group.sessions.first { activate(entry) }
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
