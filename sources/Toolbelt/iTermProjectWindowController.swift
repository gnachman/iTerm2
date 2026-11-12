import Foundation

/// Window integration uses stable tab IDs, never retaining a tab, session or window.
@objc protocol iTermProjectWindowDelegate: AnyObject {
    var projectTabAssociations: [String: String] { get }
    var projectActiveTabIdentifier: String? { get }
    func projectSelectTab(_ identifier: String)
    func projectAssign(_ project: String?, toTab identifier: String)
    func projectLaunch(_ project: iTermProjectDirectory, directory: String, completion: @escaping (String?) -> Void)
    func projectStateDidChange()
    @objc(projectWorkingDirectoryWithCompletion:)
    optional func projectWorkingDirectory(completion: @escaping (String?) -> Void)
    @objc optional func projectReportError(_ error: NSError)
}

@objcMembers final class iTermProjectWindowController: NSObject {
    weak var delegate: iTermProjectWindowDelegate?
    private let catalog: iTermProjectCatalog
    private var observer: NSObjectProtocol?
    private var rememberedTabs = [String: String]()
    private var pending = [String: (identifier: UUID, generation: UInt64)]()
    private var pendingWorkingDirectories = [String: (identifier: UUID, generation: UInt64)]()
    private var completedWorkingDirectories = Set<String>()
    private var currentDirectoryActionGeneration: UInt64?
    private var rememberedWorktreeTabs = [String: String]()
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
        let associations = delegate?.projectTabAssociations ?? [:]
        rememberedTabs = rememberedTabs.filter { associations[$0.value] == $0.key }
        completedWorkingDirectories = completedWorkingDirectories.filter { associations[$0] != nil }
        pendingWorkingDirectories = pendingWorkingDirectories.filter { associations[$0.key] != nil }
        tabVisits = tabVisits.filter { associations[$0.key] != nil }
        rememberedWorktreeTabs = rememberedWorktreeTabs.filter { worktree, tab in
            associations[tab].flatMap { catalog.worktree(forProjectIdentifier: $0)?.identifier } == worktree
        }
    }

    func activeTabDidChange() {
        guard let delegate = delegate else { return }
        selectionGeneration &+= 1
        currentDirectoryActionGeneration = nil
        worktreeIntent = nil
        tabsDidChange()
        let associations = delegate.projectTabAssociations
        selectedProjectIdentifier = delegate.projectActiveTabIdentifier.flatMap { associations[$0] }
            .flatMap { catalog.project(withIdentifier: $0)?.identifier }
        if let project = selectedProjectIdentifier, let tab = delegate.projectActiveTabIdentifier {
            rememberedTabs[project] = tab
            completedWorkingDirectories.insert(tab)
        }
        if let tab = delegate.projectActiveTabIdentifier {
            visitGeneration &+= 1
            tabVisits[tab] = visitGeneration
            if let worktree = selectedWorktreeIdentifier { rememberedWorktreeTabs[worktree] = tab }
        }
        delegate.projectStateDidChange()
        selectInitialWorkingDirectoryIfNeeded()
    }

    func selectInitialWorkingDirectoryIfNeeded() {
        guard let delegate, let tab = delegate.projectActiveTabIdentifier,
              delegate.projectTabAssociations[tab] == "", selectedProjectIdentifier == nil,
              !completedWorkingDirectories.contains(tab), pendingWorkingDirectories[tab]?.generation != selectionGeneration,
              let readDirectory = delegate.projectWorkingDirectory else { return }
        let request = UUID()
        let generation = selectionGeneration
        pendingWorkingDirectories[tab] = (request, generation)
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
        guard generation == selectionGeneration, delegate?.projectActiveTabIdentifier == tab,
              delegate?.projectTabAssociations[tab] == "", selectedProjectIdentifier == nil else {
            pendingWorkingDirectories.removeValue(forKey: tab)
            return false
        }
        return true
    }

    private func assignInitialProject(_ project: iTermProjectDirectory, toTab tab: String, request: UUID, generation: UInt64) {
        guard isCurrentWorkingDirectoryRequest(tab, request: request, generation: generation) else { return }
        pendingWorkingDirectories.removeValue(forKey: tab)
        completedWorkingDirectories.insert(tab)
        delegate?.projectAssign(project.identifier, toTab: tab)
        selectedProjectIdentifier = project.identifier
        rememberedTabs[project.identifier] = tab
        delegate?.projectStateDidChange()
    }

    @objc(addCurrentDirectoryWithCompletion:)
    func addCurrentDirectory(completion: @escaping (iTermProjectDirectory?, NSError?) -> Void) {
        guard let delegate, let tab = delegate.projectActiveTabIdentifier,
              delegate.projectTabAssociations[tab] != nil,
              let readDirectory = delegate.projectWorkingDirectory else {
            completion(nil, nil)
            return
        }
        // Explicitly associate the current tab, superseding pending automatic selection or launches.
        worktreeIntent = nil
        selectedProjectIdentifier = delegate.projectTabAssociations[tab].flatMap { catalog.project(withIdentifier: $0)?.identifier }
        selectionGeneration &+= 1
        let generation = selectionGeneration
        currentDirectoryActionGeneration = generation
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
                    self.delegate?.projectAssign(project.identifier, toTab: tab)
                    self.activeTabDidChange()
                }
                completion(project, error)
            }
        }
    }

    private func isCurrentDirectoryAction(_ tab: String, generation: UInt64) -> Bool {
        currentDirectoryActionGeneration == generation && generation == selectionGeneration && delegate?.projectActiveTabIdentifier == tab &&
            delegate?.projectTabAssociations[tab] != nil
    }

    private func finishCurrentDirectoryAction(generation: UInt64) {
        if currentDirectoryActionGeneration == generation { currentDirectoryActionGeneration = nil }
    }

    @objc(addDirectoryAtPath:completion:)
    func addDirectory(atPath path: String, completion: @escaping (iTermProjectDirectory?, NSError?) -> Void) {
        guard let delegate else { completion(nil, nil); return }
        let tab = delegate.projectActiveTabIdentifier
        worktreeIntent = nil
        selectionGeneration &+= 1
        let generation = selectionGeneration
        currentDirectoryActionGeneration = generation
        let isCurrent: () -> Bool = { [weak self] in
            self?.currentDirectoryActionGeneration == generation && self?.selectionGeneration == generation &&
                self?.delegate?.projectActiveTabIdentifier == tab
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
        guard catalog.project(withIdentifier: project.identifier) != nil, let delegate = delegate else { return }
        if let worktree = catalog.worktree(forProjectIdentifier: project.identifier) { selectWorktree(worktree); return }
        worktreeIntent = nil
        if selectedProjectIdentifier != project.identifier || currentDirectoryActionGeneration != nil { selectionGeneration &+= 1 }
        currentDirectoryActionGeneration = nil
        selectedProjectIdentifier = project.identifier
        delegate.projectStateDidChange()
        let associations = delegate.projectTabAssociations
        let remembered = rememberedTabs[project.identifier].flatMap { associations[$0] == project.identifier ? $0 : nil }
        if let tab = remembered ?? associations.keys.sorted().first(where: { associations[$0] == project.identifier }) {
            rememberedTabs[project.identifier] = tab
            delegate.projectSelectTab(tab)
            return
        }
        let generation = selectionGeneration
        guard pending[project.identifier]?.generation != generation else { return }
        let requestIdentifier = UUID()
        pending[project.identifier] = (requestIdentifier, generation)
        delegate.projectLaunch(project, directory: project.rootDirectory) { [weak self] tab in
            guard let self = self,
                  self.pending[project.identifier]?.identifier == requestIdentifier else { return }
            self.pending.removeValue(forKey: project.identifier)
            guard self.catalog.project(withIdentifier: project.identifier) != nil, let tab = tab,
                  generation == self.selectionGeneration else { return }
            self.rememberedTabs[project.identifier] = tab
            if self.selectedProjectIdentifier == project.identifier { self.delegate?.projectSelectTab(tab) }
        }
    }

    func selectWorktree(_ worktree: iTermGitWorktree) {
        guard let current = catalog.worktree(withIdentifier: worktree.identifier), let delegate else { return }
        if selectedWorktreeIdentifier != current.identifier || currentDirectoryActionGeneration != nil { selectionGeneration &+= 1 }
        currentDirectoryActionGeneration = nil
        let associations = delegate.projectTabAssociations
        let tabs = associations.keys.filter { tab in
            associations[tab].flatMap { catalog.worktree(forProjectIdentifier: $0)?.identifier } == current.identifier
        }
        let remembered = rememberedWorktreeTabs[current.identifier].flatMap { tabs.contains($0) ? $0 : nil }
        let persisted = rememberedTabs.values.filter { tabs.contains($0) }.sorted().first
        let recent = tabs.sorted().max { (tabVisits[$0] ?? 0) < (tabVisits[$1] ?? 0) }
        if let tab = remembered ?? recent ?? persisted {
            worktreeIntent = nil
            selectedProjectIdentifier = associations[tab]
            rememberedWorktreeTabs[current.identifier] = tab
            delegate.projectStateDidChange()
            delegate.projectSelectTab(tab)
            return
        }
        guard current.available else {
            activeTabDidChange()
            delegate.projectReportError?(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Projects.WorktreeUnavailable", defaultValue: "The worktree directory is unavailable. Refresh the list or choose another worktree.", comment: "Error when opening a terminal in a missing worktree")]))
            return
        }
        worktreeIntent = current
        selectedProjectIdentifier = catalog.projects.first { $0.rootDirectory == current.rootDirectory }?.identifier
        delegate.projectStateDidChange()
        let generation = selectionGeneration
        guard pendingWorktrees[current.identifier]?.generation != generation else { return }
        let request = UUID()
        pendingWorktrees[current.identifier] = (request, generation)
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
            self.delegate?.projectLaunch(project, directory: current.rootDirectory) { [weak self] tab in
                guard let self, self.pendingWorktrees[current.identifier]?.identifier == request else { return }
                self.pendingWorktrees.removeValue(forKey: current.identifier)
                guard generation == self.selectionGeneration, self.selectedWorktreeIdentifier == current.identifier, let tab else { return }
                self.rememberedWorktreeTabs[current.identifier] = tab
                self.rememberedTabs[project.identifier] = tab
                self.delegate?.projectSelectTab(tab)
            }
        }
    }

    private func isCurrentWorktreeRequest(_ worktree: String, request: UUID, generation: UInt64) -> Bool {
        pendingWorktrees[worktree]?.identifier == request && generation == selectionGeneration &&
            worktreeIntent?.identifier == worktree && catalog.worktree(withIdentifier: worktree)?.available == true
    }

    func openTerminal(inDirectory directory: String) {
        guard let project = selectedProject else { return }
        let generation = selectionGeneration
        delegate?.projectLaunch(project, directory: directory) { [weak self] tab in
            guard let self = self, let tab = tab, generation == self.selectionGeneration else { return }
            if self.selectedProjectIdentifier == project.identifier { self.delegate?.projectSelectTab(tab) }
        }
    }

    private func catalogDidChange() {
        guard let delegate = delegate else { return }
        var removedAssociation = false
        for (tab, project) in delegate.projectTabAssociations where !project.isEmpty && catalog.project(withIdentifier: project) == nil {
            delegate.projectAssign(nil, toTab: tab)
            removedAssociation = true
        }
        let unavailableIntent = worktreeIntent.map { catalog.worktree(withIdentifier: $0.identifier)?.available != true } ?? false
        if removedAssociation || (selectedProjectIdentifier != nil && selectedProject == nil) || unavailableIntent { activeTabDidChange() }
        else {
            if worktreeIntent == nil, let worktree = selectedWorktreeIdentifier, let tab = delegate.projectActiveTabIdentifier {
                rememberedWorktreeTabs[worktree] = tab
            }
            delegate.projectStateDidChange()
        }
    }

    // Localization unneeded: arrangement field names.
    func restorableState() -> [String: Any] {
        var state: [String: Any] = ["visible": sidebarVisible, "width": sidebarWidth, "remembered": rememberedTabs]
        if let selected = selectedProjectIdentifier { state["selected"] = selected }
        // Persist only opaque project and tab IDs, never filesystem-path dictionary keys.
        state["worktreeRemembered"] = rememberedWorktreeTabs.reduce(into: [String: String]()) { result, entry in
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
        rememberedTabs = state["remembered"] as? [String: String] ?? [:]
        rememberedWorktreeTabs.removeAll()
        for (project, tab) in state["worktreeRemembered"] as? [String: String] ?? [:] {
            if let worktree = catalog.worktree(forProjectIdentifier: project) { rememberedWorktreeTabs[worktree.identifier] = tab }
        }
    }
}
