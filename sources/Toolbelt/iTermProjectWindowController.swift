import Foundation

/// Window integration uses stable IDs, never retaining a tab, session or window.
@objc protocol iTermProjectWindowDelegate: AnyObject {
    var projectTabAssociations: [String: String] { get }
    var projectActiveTabIdentifier: String? { get }
    func projectSelectTab(_ identifier: String)
    func projectAssign(_ project: String?, toTab identifier: String)
    func projectLaunch(_ project: iTermProjectDirectory, directory: String, completion: @escaping (String?) -> Void)
    func projectStateDidChange()
    @objc(projectWorkingDirectoryWithCompletion:)
    optional func projectWorkingDirectory(completion: @escaping (String?) -> Void)
    @objc optional var projectSessionContexts: [iTermProjectSessionContext] { get }
    @objc optional var projectActiveSessionIdentifier: String? { get }
    @objc optional func projectSelectSession(_ identifier: String)
    @objc optional func projectAssignSession(_ project: String?, toSession identifier: String)
    @objc(projectCanLaunchWithStyle:)
    optional func projectCanLaunch(style: iTermOpenStyle) -> Bool
    @objc(projectLaunch:directory:style:targetSessionIdentifier:completion:)
    optional func projectLaunch(_ project: iTermProjectDirectory, directory: String, style: iTermOpenStyle,
                                targetSessionIdentifier: String?, completion: @escaping (iTermProjectTerminalLaunchResult?) -> Void)
    @objc optional func projectReportError(_ error: NSError)
}

@objcMembers final class iTermProjectWindowController: NSObject {
    weak var delegate: iTermProjectWindowDelegate?
    private let catalog: iTermProjectCatalog
    private var observer: NSObjectProtocol?
    private var legacyRememberedTabs = [String: String]()
    private var rememberedSessions = [String: String]()
    private var rememberedTabs: [String: String] {
        get { sessionContexts == nil ? legacyRememberedTabs : rememberedSessions }
        set { if sessionContexts == nil { legacyRememberedTabs = newValue } else { rememberedSessions = newValue } }
    }
    @nonobjc private var sessionContexts: [iTermProjectSessionContext]? {
        delegate?.projectSessionContexts?.filter { !$0.exited }
    }
    private var activeTargetIdentifier: String? {
        if sessionContexts != nil { return delegate?.projectActiveSessionIdentifier ?? nil }
        return delegate?.projectActiveTabIdentifier
    }
    private var targetAssociations: [String: String] {
        guard let contexts = sessionContexts else { return delegate?.projectTabAssociations ?? [:] }
        return contexts.reduce(into: [:]) { result, context in
            result[context.sessionIdentifier] = iTermProjectSessionOwnership.effectiveIdentifier(
                context.projectIdentifier, inheriting: delegate?.projectTabAssociations[context.tabIdentifier]) ?? ""
        }
    }
    private func selectTarget(_ identifier: String) {
        if sessionContexts != nil { delegate?.projectSelectSession?(identifier) }
        else { delegate?.projectSelectTab(identifier) }
    }
    private func assign(_ project: String?, toTarget identifier: String) {
        if sessionContexts != nil { delegate?.projectAssignSession?(project, toSession: identifier) }
        else { delegate?.projectAssign(project, toTab: identifier) }
    }
    private func targetTabIdentifier(_ target: String?) -> String? {
        guard let target else { return nil }
        if let contexts = sessionContexts { return contexts.first { $0.sessionIdentifier == target }?.tabIdentifier }
        return targetAssociations[target] == nil ? nil : target
    }
    private struct Activation: Equatable {
        let identifier: String?
        let tab: String?
        let owner: String?
    }
    @nonobjc private var lastActivation: Activation?
    private var explicitLaunchPending = false
    private var launchOrigin: (generation: UInt64, target: String?, tab: String?)?
    private var workingDirectoryTabs = [String: String]()
    private var pending = [String: (identifier: UUID, generation: UInt64)]()
    private var pendingWorkingDirectories = [String: (identifier: UUID, generation: UInt64)]()
    private var completedWorkingDirectories = Set<String>()
    private var currentDirectoryActionGeneration: UInt64?
    private var legacyRememberedWorktreeTabs = [String: String]()
    private var rememberedWorktreeSessions = [String: String]()
    private var rememberedWorktreeTabs: [String: String] {
        get { sessionContexts == nil ? legacyRememberedWorktreeTabs : rememberedWorktreeSessions }
        set { if sessionContexts == nil { legacyRememberedWorktreeTabs = newValue } else { rememberedWorktreeSessions = newValue } }
    }
    private var tabVisits = [String: UInt64]()
    private var visitGeneration: UInt64 = 0
    private var worktreeIntent: iTermGitWorktree?
    private var pendingWorktrees = [String: (identifier: UUID, generation: UInt64)]()
    private(set) var selectionGeneration: UInt64 = 0
    private(set) var selectedProjectIdentifier: String?
    var sidebarVisible = false
    var sidebarWidth: CGFloat = 220 {
        didSet { sidebarWidth = sidebarWidth.isFinite ? min(360, max(180, sidebarWidth)) : 220 }
    }
    var selectedProject: iTermProjectDirectory? {
        selectedProjectIdentifier.flatMap { catalog.project(withIdentifier: $0) }
    }
    var selectedWorktreeIdentifier: String? {
        worktreeIntent?.identifier ?? selectedProjectIdentifier.flatMap { catalog.worktree(forProjectIdentifier: $0)?.identifier }
    }
    var selectedRootDirectory: String? {
        worktreeIntent?.rootDirectory ?? selectedProjectIdentifier.flatMap { catalog.worktree(forProjectIdentifier: $0)?.rootDirectory } ?? selectedProject?.rootDirectory
    }

    override convenience init() { self.init(catalog: .shared) }

    init(catalog: iTermProjectCatalog) {
        self.catalog = catalog
        super.init()
        observer = NotificationCenter.default.addObserver(forName: Notification.Name(iTermProjectCatalog.didChangeNotification),
                                                          object: catalog, queue: nil) { [weak self] _ in
            self?.catalogDidChange()
        }
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    func tabsDidChange() {
        let associations = targetAssociations
        rememberedTabs = rememberedTabs.filter { associations[$0.value] == $0.key }
        completedWorkingDirectories = completedWorkingDirectories.filter { associations[$0] != nil }
        pendingWorkingDirectories = pendingWorkingDirectories.filter { associations[$0.key] != nil }
        workingDirectoryTabs = workingDirectoryTabs.filter { associations[$0.key] != nil }
        tabVisits = tabVisits.filter { associations[$0.key] != nil }
        rememberedWorktreeTabs = rememberedWorktreeTabs.filter { worktree, tab in
            associations[tab].flatMap { catalog.worktree(forProjectIdentifier: $0)?.identifier } == worktree
        }
    }

    func activeTabDidChange() { activeSessionDidChange() }

    func activeSessionDidChange() {
        guard let delegate = delegate else { return }
        let activation = Activation(identifier: activeTargetIdentifier, tab: targetTabIdentifier(activeTargetIdentifier),
                                    owner: activeTargetIdentifier.flatMap { targetAssociations[$0] })
        let selectionIsAvailable = (selectedProjectIdentifier == nil || selectedProject != nil) &&
            (worktreeIntent.map { catalog.worktree(withIdentifier: $0.identifier)?.available == true } ?? true)
        if sessionContexts != nil, activation == lastActivation, selectionIsAvailable {
            tabsDidChange()
            delegate.projectStateDidChange()
            selectInitialWorkingDirectoryIfNeeded()
            return
        }
        lastActivation = activation
        selectionGeneration &+= 1
        currentDirectoryActionGeneration = nil
        explicitLaunchPending = false
        launchOrigin = nil
        worktreeIntent = nil
        tabsDidChange()
        let associations = targetAssociations
        selectedProjectIdentifier = activeTargetIdentifier.flatMap { associations[$0] }
            .flatMap { catalog.project(withIdentifier: $0)?.identifier }
        if let project = selectedProjectIdentifier, let tab = activeTargetIdentifier {
            rememberedTabs[project] = tab
            completedWorkingDirectories.insert(tab)
        }
        if let tab = activeTargetIdentifier {
            visitGeneration &+= 1
            tabVisits[tab] = visitGeneration
            if let worktree = selectedWorktreeIdentifier { rememberedWorktreeTabs[worktree] = tab }
        }
        delegate.projectStateDidChange()
        selectInitialWorkingDirectoryIfNeeded()
    }

    func selectInitialWorkingDirectoryIfNeeded() {
        guard let delegate, let tab = activeTargetIdentifier,
              targetAssociations[tab] == "", selectedProjectIdentifier == nil,
              !completedWorkingDirectories.contains(tab), pendingWorkingDirectories[tab]?.generation != selectionGeneration,
              let readDirectory = delegate.projectWorkingDirectory else { return }
        let request = UUID()
        let generation = selectionGeneration
        pendingWorkingDirectories[tab] = (request, generation)
        workingDirectoryTabs[tab] = targetTabIdentifier(tab)
        readDirectory { [weak self] path in
            guard let self, self.isCurrentWorkingDirectoryRequest(tab, request: request, generation: generation) else { return }
            guard let path, NSString(string: path).isAbsolutePath, !path.contains("\0") else {
                self.pendingWorkingDirectories.removeValue(forKey: tab)
                return
            }
            self.catalog.addWorkingDirectory(atPath: path, shouldAdd: { [weak self] in
                    self?.isCurrentWorkingDirectoryRequest(tab, request: request, generation: generation) == true
                }) { [weak self] project, _ in
                    guard let self else { return }
                    if let project { self.assignInitialProject(project, toTab: tab, request: request, generation: generation) }
                    else if self.pendingWorkingDirectories[tab]?.identifier == request { self.pendingWorkingDirectories.removeValue(forKey: tab) }
                }
        }
    }

    private func isCurrentWorkingDirectoryRequest(_ tab: String, request: UUID, generation: UInt64) -> Bool {
        guard pendingWorkingDirectories[tab]?.identifier == request else { return false }
        guard generation == selectionGeneration, activeTargetIdentifier == tab,
              workingDirectoryTabs[tab] == targetTabIdentifier(tab),
              targetAssociations[tab] == "", selectedProjectIdentifier == nil else {
            pendingWorkingDirectories.removeValue(forKey: tab)
            return false
        }
        return true
    }

    private func assignInitialProject(_ project: iTermProjectDirectory, toTab tab: String, request: UUID, generation: UInt64) {
        guard isCurrentWorkingDirectoryRequest(tab, request: request, generation: generation) else { return }
        pendingWorkingDirectories.removeValue(forKey: tab)
        completedWorkingDirectories.insert(tab)
        assign(project.identifier, toTarget: tab)
        selectedProjectIdentifier = project.identifier
        rememberedTabs[project.identifier] = tab
        delegate?.projectStateDidChange()
    }

    @objc(addCurrentDirectoryWithCompletion:)
    func addCurrentDirectory(completion: @escaping (iTermProjectDirectory?, NSError?) -> Void) {
        guard let delegate, let tab = activeTargetIdentifier,
              targetAssociations[tab] != nil,
              let readDirectory = delegate.projectWorkingDirectory else {
            completion(nil, nil)
            return
        }
        // Associate only the active target, superseding automatic selection or earlier launches.
        worktreeIntent = nil
        selectedProjectIdentifier = targetAssociations[tab].flatMap { catalog.project(withIdentifier: $0)?.identifier }
        selectionGeneration &+= 1
        let generation = selectionGeneration
        currentDirectoryActionGeneration = generation
        workingDirectoryTabs[tab] = targetTabIdentifier(tab)
        readDirectory { [weak self] path in
            guard let self, self.isCurrentDirectoryAction(tab, generation: generation), let path else {
                self?.finishCurrentDirectoryAction(generation: generation)
                completion(nil, nil)
                return
            }
            self.catalog.addDirectoryIfCurrent(atPath: path, shouldAdd: { [weak self] in
                self?.isCurrentDirectoryAction(tab, generation: generation) == true
            }) { [weak self] project, error in
                guard let self, self.isCurrentDirectoryAction(tab, generation: generation) else {
                    self?.finishCurrentDirectoryAction(generation: generation)
                    completion(nil, nil)
                    return
                }
                self.finishCurrentDirectoryAction(generation: generation)
                if let project {
                    self.assign(project.identifier, toTarget: tab)
                    self.activeTabDidChange()
                }
                completion(project, error)
            }
        }
    }

    private func isCurrentDirectoryAction(_ tab: String, generation: UInt64) -> Bool {
        currentDirectoryActionGeneration == generation && generation == selectionGeneration && activeTargetIdentifier == tab &&
            targetAssociations[tab] != nil && workingDirectoryTabs[tab] == targetTabIdentifier(tab)
    }

    private func finishCurrentDirectoryAction(generation: UInt64) {
        if currentDirectoryActionGeneration == generation { currentDirectoryActionGeneration = nil }
    }

    @objc(addDirectoryAtPath:completion:)
    func addDirectory(atPath path: String, completion: @escaping (iTermProjectDirectory?, NSError?) -> Void) {
        guard delegate != nil else { completion(nil, nil); return }
        let tab = activeTargetIdentifier
        worktreeIntent = nil
        selectionGeneration &+= 1
        let generation = selectionGeneration
        currentDirectoryActionGeneration = generation
        let isCurrent: () -> Bool = { [weak self] in
            self?.currentDirectoryActionGeneration == generation && self?.selectionGeneration == generation &&
                self?.activeTargetIdentifier == tab
        }
        catalog.addDirectoryIfCurrent(atPath: path, shouldAdd: isCurrent) { [weak self] project, error in
            guard let self, isCurrent() else { completion(nil, nil); return }
            guard let project else {
                self.finishCurrentDirectoryAction(generation: generation)
                completion(nil, error); return
            }
            self.catalog.refreshProject(withIdentifier: project.identifier) { [weak self] _ in
                guard let self, isCurrent(), self.catalog.project(withIdentifier: project.identifier) != nil else { completion(nil, nil); return }
                self.finishCurrentDirectoryAction(generation: generation)
                self.selectProject(project)
                completion(project, nil)
            }
        }
    }

    func selectProject(_ project: iTermProjectDirectory) {
        selectProject(project, openIfNeeded: true)
    }

    func selectProject(_ project: iTermProjectDirectory, openIfNeeded: Bool) {
        guard catalog.project(withIdentifier: project.identifier) != nil, let delegate = delegate else { return }
        if let worktree = catalog.worktree(forProjectIdentifier: project.identifier) {
            selectWorktree(worktree, openIfNeeded: openIfNeeded)
            return
        }
        let associations = targetAssociations
        let remembered = rememberedTabs[project.identifier].flatMap { associations[$0] == project.identifier ? $0 : nil }
        let existing = remembered ?? associations.keys.sorted().first(where: { associations[$0] == project.identifier })
        guard openIfNeeded || existing != nil else {
            selectUnopenedProject(project.identifier, worktree: nil)
            return
        }
        worktreeIntent = nil
        if selectedProjectIdentifier != project.identifier || currentDirectoryActionGeneration != nil || explicitLaunchPending {
            selectionGeneration &+= 1
            launchOrigin = nil
            explicitLaunchPending = false
        }
        currentDirectoryActionGeneration = nil
        selectedProjectIdentifier = project.identifier
        delegate.projectStateDidChange()
        if let tab = existing {
            rememberedTabs[project.identifier] = tab
            selectTarget(tab)
            return
        }
        let generation = selectionGeneration
        guard pending[project.identifier]?.generation != generation else { return }
        let requestIdentifier = UUID()
        pending[project.identifier] = (requestIdentifier, generation)
        launch(project, directory: project.rootDirectory) { [weak self] tab in
            guard let self = self,
                  self.pending[project.identifier]?.identifier == requestIdentifier else { return }
            self.pending.removeValue(forKey: project.identifier)
            guard self.catalog.project(withIdentifier: project.identifier) != nil, let tab = tab,
                  generation == self.selectionGeneration else { return }
            self.rememberedTabs[project.identifier] = tab
            if self.selectedProjectIdentifier == project.identifier { self.selectTarget(tab) }
        }
    }

    func selectWorktree(_ worktree: iTermGitWorktree) {
        selectWorktree(worktree, openIfNeeded: true)
    }

    func selectWorktree(_ worktree: iTermGitWorktree, openIfNeeded: Bool) {
        guard let current = catalog.worktree(withIdentifier: worktree.identifier), let delegate else { return }
        let associations = targetAssociations
        let tabs = associations.keys.filter { tab in
            associations[tab].flatMap { catalog.worktree(forProjectIdentifier: $0)?.identifier } == current.identifier
        }
        let remembered = rememberedWorktreeTabs[current.identifier].flatMap { tabs.contains($0) ? $0 : nil }
        let persisted = rememberedTabs.values.filter { tabs.contains($0) }.sorted().first
        let recent = tabs.sorted().max { (tabVisits[$0] ?? 0) < (tabVisits[$1] ?? 0) }
        let existing = remembered ?? recent ?? persisted
        guard openIfNeeded || existing != nil else {
            selectUnopenedProject(catalog.projects.first { $0.rootDirectory == current.rootDirectory }?.identifier, worktree: current)
            return
        }
        if selectedWorktreeIdentifier != current.identifier || currentDirectoryActionGeneration != nil || explicitLaunchPending {
            selectionGeneration &+= 1
            launchOrigin = nil
            explicitLaunchPending = false
        }
        currentDirectoryActionGeneration = nil
        if let tab = existing {
            worktreeIntent = nil
            selectedProjectIdentifier = associations[tab]
            rememberedWorktreeTabs[current.identifier] = tab
            delegate.projectStateDidChange()
            selectTarget(tab)
            return
        }
        guard current.available else {
            activeTabDidChange()
            reportUnavailableWorktree()
            return
        }
        worktreeIntent = current
        selectedProjectIdentifier = catalog.projects.first { $0.rootDirectory == current.rootDirectory }?.identifier
        delegate.projectStateDidChange()
        let generation = selectionGeneration
        guard pendingWorktrees[current.identifier]?.generation != generation else { return }
        let request = UUID()
        pendingWorktrees[current.identifier] = (request, generation)
        if sessionContexts != nil { launchOrigin = (generation, activeTargetIdentifier, targetTabIdentifier(activeTargetIdentifier)) }
        catalog.ensureWorktreeProject(current, shouldAdd: { [weak self] in
            self?.isCurrentWorktreeRequest(current.identifier, request: request, generation: generation) == true
        }) { [weak self] project, error in
            guard let self, self.isCurrentWorktreeRequest(current.identifier, request: request, generation: generation) else { return }
            guard let project else {
                self.pendingWorktrees.removeValue(forKey: current.identifier)
                self.activeTabDidChange()
                if let error, error.code != NSUserCancelledError { self.delegate?.projectReportError?(error) }
                return
            }
            self.selectedProjectIdentifier = project.identifier
            self.delegate?.projectStateDidChange()
            self.launch(project, directory: current.rootDirectory) { [weak self] tab in
                guard let self, self.pendingWorktrees[current.identifier]?.identifier == request else { return }
                self.pendingWorktrees.removeValue(forKey: current.identifier)
                guard generation == self.selectionGeneration, self.selectedWorktreeIdentifier == current.identifier, let tab else { return }
                self.rememberedWorktreeTabs[current.identifier] = tab
                self.rememberedTabs[project.identifier] = tab
                self.selectTarget(tab)
            }
        }
    }

    private func cancelPendingSidebarLaunch() {
        selectionGeneration &+= 1
        launchOrigin = nil
        explicitLaunchPending = false
        currentDirectoryActionGeneration = nil
    }

    private func selectUnopenedProject(_ identifier: String?, worktree: iTermGitWorktree?) {
        cancelPendingSidebarLaunch()
        worktreeIntent = worktree
        selectedProjectIdentifier = identifier
        delegate?.projectStateDidChange()
    }

    func selectRepository(_ repository: iTermGitRepositorySnapshot, openIfNeeded: Bool) {
        guard let current = catalog.repositories.first(where: { $0.identifier == repository.identifier }) else { return }
        if let worktree = current.rootWorktree { selectWorktree(worktree, openIfNeeded: openIfNeeded); return }
        if let project = catalog.projects.first(where: { $0.rootDirectory == current.rootDirectory }) {
            selectProject(project, openIfNeeded: openIfNeeded)
            return
        }
        if openIfNeeded { openRepository(current, style: .tab) }
        else { cancelPendingSidebarLaunch() }
    }

    private func isCurrentWorktreeRequest(_ worktree: String, request: UUID, generation: UInt64) -> Bool {
        pendingWorktrees[worktree]?.identifier == request && generation == selectionGeneration &&
            worktreeIntent?.identifier == worktree && catalog.worktree(withIdentifier: worktree)?.available == true &&
            (sessionContexts == nil || isLaunchRequestCurrent(targetSessionIdentifier: launchOrigin?.target, generation: generation))
    }

    func openTerminal(inDirectory directory: String) {
        guard let project = selectedProject else { return }
        let generation = selectionGeneration
        launch(project, directory: directory) { [weak self] tab in
            guard let self = self, let tab = tab, generation == self.selectionGeneration else { return }
            if self.selectedProjectIdentifier == project.identifier { self.selectTarget(tab) }
        }
    }

    /// Explicit creation captures the source pane before any asynchronous validation.
    func openProject(_ project: iTermProjectDirectory, style: iTermOpenStyle) {
        guard let current = catalog.project(withIdentifier: project.identifier) else { return }
        if let worktree = catalog.worktree(forProjectIdentifier: current.identifier) {
            openWorktree(worktree, style: style)
            return
        }
        beginExplicitLaunch(project: current, directory: current.rootDirectory, style: style)
    }

    func openRepository(_ repository: iTermGitRepositorySnapshot, style: iTermOpenStyle) {
        guard let current = catalog.repositories.first(where: { $0.identifier == repository.identifier }) else { return }
        if let worktree = current.rootWorktree {
            openWorktree(worktree, style: style)
            return
        }
        // Bare repositories have a directory heading without a corresponding worktree row.
        let origin = beginLaunchIntent()
        guard canLaunch(style) else { return }
        let isCurrent = { [weak self] in
            guard let self else { return false }
            return self.isLaunchRequestCurrent(targetSessionIdentifier: origin.target, generation: origin.generation) &&
                self.catalog.repositories.contains { $0.identifier == current.identifier && $0.rootDirectory == current.rootDirectory }
        }
        catalog.addDirectoryIfCurrent(atPath: current.rootDirectory, shouldAdd: isCurrent) { [weak self] project, error in
            guard let self, isCurrent() else { return }
            guard let project else {
                if let error, error.code != NSUserCancelledError { self.delegate?.projectReportError?(error) }
                return
            }
            self.performExplicitLaunch(project, directory: current.rootDirectory, style: style, origin: origin)
        }
    }

    func openWorktree(_ worktree: iTermGitWorktree, style: iTermOpenStyle) {
        openWorktree(worktree, directory: worktree.rootDirectory, style: style)
    }

    @nonobjc private func openWorktree(_ worktree: iTermGitWorktree, directory: String, style: iTermOpenStyle) {
        guard let current = catalog.worktree(withIdentifier: worktree.identifier) else { return }
        let origin = beginLaunchIntent()
        guard current.available else { reportUnavailableWorktree(); return }
        guard canLaunch(style) else { return }
        catalog.ensureWorktreeProject(current, shouldAdd: { [weak self] in
            self?.isLaunchRequestCurrent(targetSessionIdentifier: origin.target, generation: origin.generation) == true &&
                self?.catalog.worktree(withIdentifier: current.identifier)?.available == true
        }) { [weak self] project, error in
            guard let self, self.isLaunchRequestCurrent(targetSessionIdentifier: origin.target, generation: origin.generation),
                  self.catalog.worktree(withIdentifier: current.identifier)?.available == true else { return }
            guard let project else {
                if let error, error.code != NSUserCancelledError { self.delegate?.projectReportError?(error) }
                return
            }
            self.performExplicitLaunch(project, directory: directory, style: style, origin: origin)
        }
    }

    func openTerminal(inDirectory directory: String, style: iTermOpenStyle) {
        if let worktree = worktreeIntent {
            openWorktree(worktree, directory: directory, style: style)
            return
        }
        guard let project = selectedProject else { return }
        if let worktree = catalog.worktree(forProjectIdentifier: project.identifier), !worktree.available {
            _ = beginLaunchIntent()
            reportUnavailableWorktree()
            return
        }
        beginExplicitLaunch(project: project, directory: directory, style: style)
    }

    func isLaunchRequestCurrent(targetSessionIdentifier: String?, generation: UInt64) -> Bool {
        guard generation == selectionGeneration, activeTargetIdentifier == targetSessionIdentifier else { return false }
        if let targetSessionIdentifier, targetTabIdentifier(targetSessionIdentifier) == nil { return false }
        if let origin = launchOrigin, origin.generation == generation {
            return origin.target == targetSessionIdentifier && origin.tab == targetTabIdentifier(targetSessionIdentifier)
        }
        return true
    }

    @nonobjc private func beginLaunchIntent() -> (generation: UInt64, target: String?, tab: String?) {
        selectionGeneration &+= 1
        currentDirectoryActionGeneration = nil
        let origin = (selectionGeneration, activeTargetIdentifier, targetTabIdentifier(activeTargetIdentifier))
        explicitLaunchPending = true
        launchOrigin = origin
        return origin
    }

    private func beginExplicitLaunch(project: iTermProjectDirectory, directory: String, style: iTermOpenStyle) {
        let origin = beginLaunchIntent()
        guard canLaunch(style) else { return }
        performExplicitLaunch(project, directory: directory, style: style, origin: origin)
    }

    @nonobjc private func performExplicitLaunch(_ project: iTermProjectDirectory, directory: String, style: iTermOpenStyle,
                                               origin: (generation: UInt64, target: String?, tab: String?)) {
        guard isLaunchRequestCurrent(targetSessionIdentifier: origin.target, generation: origin.generation),
              catalog.project(withIdentifier: project.identifier) != nil else { return }
        launch(project, directory: directory, style: style) { [weak self] identifier in
            guard let self, let identifier,
                  self.isLaunchCompletionCurrent(target: origin.target, tab: origin.tab, generation: origin.generation,
                                                 resultIdentifier: identifier, projectIdentifier: project.identifier) else { return }
            self.launchOrigin = nil
            self.explicitLaunchPending = false
            guard style != .window else { return }
            self.rememberedTabs[project.identifier] = identifier
            if let worktree = self.catalog.worktree(forProjectIdentifier: project.identifier) {
                self.rememberedWorktreeTabs[worktree.identifier] = identifier
            }
            self.selectedProjectIdentifier = project.identifier
            self.worktreeIntent = nil
            self.selectTarget(identifier)
            self.delegate?.projectStateDidChange()
        }
    }

    /// Legacy delegates can create tabs. Native delegates always receive an explicit style and pane ID.
    private func launch(_ project: iTermProjectDirectory, directory: String, style: iTermOpenStyle = .tab,
                        completion: @escaping (String?) -> Void) {
        guard let delegate, canLaunch(style) else { completion(nil); return }
        if let nativeLaunch = delegate.projectLaunch(_:directory:style:targetSessionIdentifier:completion:) {
            let generation = selectionGeneration
            let target = activeTargetIdentifier
            let tab = targetTabIdentifier(target)
            launchOrigin = (generation, target, tab)
            nativeLaunch(project, directory, style, target) { [weak self] result in
                guard let self, self.isLaunchCompletionCurrent(target: target, tab: tab, generation: generation,
                    resultIdentifier: result?.sessionIdentifier, projectIdentifier: project.identifier) else {
                    completion(nil); return
                }
                if style != .window, let contexts = self.sessionContexts, let result {
                    guard let context = contexts.first(where: { $0.sessionIdentifier == result.sessionIdentifier }),
                          context.tabIdentifier == result.tabIdentifier,
                          self.targetAssociations[context.sessionIdentifier] == project.identifier else {
                        completion(nil)
                        return
                    }
                }
                completion(result?.sessionIdentifier)
            }
        } else {
            delegate.projectLaunch(project, directory: directory, completion: completion)
        }
    }

    private func isLaunchCompletionCurrent(target: String?, tab: String?, generation: UInt64,
                                           resultIdentifier: String?, projectIdentifier: String) -> Bool {
        guard generation == selectionGeneration, tab == targetTabIdentifier(target),
              catalog.project(withIdentifier: projectIdentifier) != nil else { return false }
        if let target, targetTabIdentifier(target) == nil { return false }
        if activeTargetIdentifier == target { return true }
        // A native tab/split factory may activate its newly created pane while activation callbacks
        // are suspended. Only that returned, live, correctly owned pane can complete this request.
        return resultIdentifier != nil && activeTargetIdentifier == resultIdentifier &&
            resultIdentifier.flatMap { targetAssociations[$0] } == projectIdentifier
    }

    private func canLaunch(_ style: iTermOpenStyle) -> Bool {
        guard let delegate else { return false }
        let hasNativeLaunch = delegate.projectLaunch(_:directory:style:targetSessionIdentifier:completion:) != nil
        let supportedStyle = [.window, .tab, .verticalSplit, .horizontalSplit].contains(style)
        let allowed = supportedStyle && (delegate.projectCanLaunch?(style: style) ?? true) &&
            (hasNativeLaunch || (sessionContexts == nil && style == .tab))
        if !allowed {
            delegate.projectReportError?(NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Projects.TerminalModeUnavailable",
                    defaultValue: "This terminal opening mode is unavailable in the current window.",
                    comment: "Error when the requested project terminal tab, split, or window cannot be created")]))
        }
        return allowed
    }

    private func reportUnavailableWorktree() {
        delegate?.projectReportError?(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError,
            userInfo: [NSLocalizedDescriptionKey: String(localized: "Projects.WorktreeUnavailable",
                defaultValue: "The worktree directory is unavailable. Refresh the list or choose another worktree.",
                comment: "Error when opening a terminal in a missing worktree")]))
    }

    private func catalogDidChange() {
        guard let delegate = delegate else { return }
        var removedAssociation = false
        for (tab, project) in targetAssociations where !project.isEmpty && catalog.project(withIdentifier: project) == nil {
            assign(nil, toTarget: tab)
            removedAssociation = true
        }
        let unavailableIntent = worktreeIntent.map { catalog.worktree(withIdentifier: $0.identifier)?.available != true } ?? false
        if removedAssociation || (selectedProjectIdentifier != nil && selectedProject == nil) || unavailableIntent { activeTabDidChange() }
        else {
            if worktreeIntent == nil, let worktree = selectedWorktreeIdentifier, let tab = activeTargetIdentifier {
                rememberedWorktreeTabs[worktree] = tab
            }
            delegate.projectStateDidChange()
        }
    }

    // Localization unneeded: arrangement field names.
    func restorableState() -> [String: Any] {
        var state: [String: Any] = ["visible": sidebarVisible, "width": sidebarWidth,
                                    "remembered": legacyRememberedTabs, "sessionRemembered": rememberedSessions]
        if let selected = selectedProjectIdentifier { state["selected"] = selected }
        // Persist only opaque project and tab IDs, never filesystem-path dictionary keys.
        state["worktreeRemembered"] = legacyRememberedWorktreeTabs.reduce(into: [String: String]()) { result, entry in
            if let project = catalog.projects.first(where: { $0.gitWorktreeDirectory == entry.key }) { result[project.identifier] = entry.value }
        }
        state["worktreeSessionRemembered"] = rememberedWorktreeSessions.reduce(into: [String: String]()) { result, entry in
            if let project = catalog.projects.first(where: { $0.gitWorktreeDirectory == entry.key }) { result[project.identifier] = entry.value }
        }
        return state
    }

    @objc(restoreFromState:)
    func restore(from state: [String: Any]) {
        // A newly opened window starts with its panels collapsed, retaining width and tab associations.
        sidebarVisible = false
        sidebarWidth = (state["width"] as? NSNumber)?.doubleValue ?? 220
        selectedProjectIdentifier = (state["selected"] as? String).flatMap { catalog.project(withIdentifier: $0)?.identifier }
        legacyRememberedTabs = state["remembered"] as? [String: String] ?? [:]
        rememberedSessions = state["sessionRemembered"] as? [String: String] ?? [:]
        legacyRememberedWorktreeTabs.removeAll()
        rememberedWorktreeSessions.removeAll()
        for (project, tab) in state["worktreeRemembered"] as? [String: String] ?? [:] {
            if let worktree = catalog.worktree(forProjectIdentifier: project) { legacyRememberedWorktreeTabs[worktree.identifier] = tab }
        }
        for (project, session) in state["worktreeSessionRemembered"] as? [String: String] ?? [:] {
            if let worktree = catalog.worktree(forProjectIdentifier: project) { rememberedWorktreeSessions[worktree.identifier] = session }
        }
    }
}
