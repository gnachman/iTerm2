import AppKit

/// An opt-in navigator for coding harnesses across windows. It never sends terminal input.
@objc final class SessionDirectorySidebar: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
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
        needsLayout = true
    }

    required init?(coder: NSCoder) { it_fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        heading.frame = NSRect(x: 10, y: max(0, bounds.height - 28), width: max(0, bounds.width - 20), height: 20)
        scroll.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - 32))
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
            guard let self, event.window === self.window,
                  let index = Self.shortcutIndex(event),
                  index < self.groups.flatMap({ $0.sessions }).count else { return event }
            if event.isARepeat { return nil }
            let entry = self.groups.flatMap { $0.sessions }[index]
            if let group = self.groups.first(where: { $0.sessions.contains(entry) }) {
                self.outline.expandItem(group)
            }
            self.activate(entry)
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
                title = harness.name + " — " + local.name
            } else if harness.tmuxSocket != nil {
                title = harness.name + " · tmux · " + String(harness.pid)
            } else {
                let source = String(localized: "SessionDirectorySidebar.Native", defaultValue: "native",
                    comment: "Source label for a native harness process outside this iTerm2 instance")
                title = harness.name + " · " + source + " · " + String(harness.pid)
            }
            entries.removeAll { $0.id == id }
            entries.append(Entry(id: id, name: title, runID: harness.id, key: key,
                                 external: local == nil ? harness : nil))
        }
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

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { item is Entry }

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
        } else if let entry = item as? Entry {
            if let index = groups.flatMap({ $0.sessions }).firstIndex(of: entry), index < 9 {
                field.stringValue = "⌥⌘\(index + 1)  " + entry.name
            } else {
                field.stringValue = entry.name
            }
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
        if let session = iTermController.sharedInstance()?.anySession(withGUID: entry.id) {
            session.reveal()
            return
        }
        guard let external = entry.external,
              iTermLSOF.startTime(forProcess: external.pid) == external.started else { return }
        if let socket = external.tmuxSocket, let pane = external.tmuxPane {
            let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
                .filter { $0.hasPrefix("/") }.map { String($0) + "/tmux" }
            let executable = (searchPaths + ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"])
                .first { FileManager.default.isExecutableFile(atPath: $0) }
            guard let executable, pendingAttachments.insert(external.id).inserted else { return }
            let command = [executable, "-N", "-S", socket, "attach-session", "-t", pane]
                .map { ($0 as NSString).withEscapedShellCharacters(includingNewlines: true) }
                .joined(separator: " ")
            iTermSessionLauncher.launchBookmark(nil,
                in: iTermController.sharedInstance()?.currentTerminal, style: .tab, withURL: nil,
                hotkeyWindowType: .none, makeKey: true, canActivate: true,
                respectTabbingMode: false, index: nil, command: command, makeSession: nil,
                didMakeSession: nil, completion: { [weak self] session, ok in
                    self?.pendingAttachments.remove(external.id)
                    if ok { self?.attachedSessionIDs[external.id] = session.guid }
                })
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

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !refreshing, outline.selectedRow >= 0, let entry = outline.item(atRow: outline.selectedRow) as? Entry else { return }
        activate(entry)
    }
}
