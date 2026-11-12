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
    private(set) var selectionGeneration: UInt64 = 0
    private(set) var selectedProjectIdentifier: String?
    var sidebarVisible = false
    var sidebarWidth: CGFloat = 220 {
        didSet { sidebarWidth = sidebarWidth.isFinite ? min(360, max(180, sidebarWidth)) : 220 }
    }
    var selectedProject: iTermProjectDirectory? {
        selectedProjectIdentifier.flatMap { catalog.project(withIdentifier: $0) }
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
    }

    func activeTabDidChange() {
        guard let delegate = delegate else { return }
        selectionGeneration &+= 1
        currentDirectoryActionGeneration = nil
        tabsDidChange()
        let associations = delegate.projectTabAssociations
        selectedProjectIdentifier = delegate.projectActiveTabIdentifier.flatMap { associations[$0] }
            .flatMap { catalog.project(withIdentifier: $0)?.identifier }
        if let project = selectedProjectIdentifier, let tab = delegate.projectActiveTabIdentifier {
            rememberedTabs[project] = tab
            completedWorkingDirectories.insert(tab)
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
            self.catalog.addDirectoryIfCurrent(atPath: path, reuseContainingProject: true, shouldAdd: { [weak self] in
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

    func selectProject(_ project: iTermProjectDirectory) {
        guard catalog.project(withIdentifier: project.identifier) != nil, let delegate = delegate else { return }
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
        if removedAssociation || (selectedProjectIdentifier != nil && selectedProject == nil) { activeTabDidChange() }
        else { delegate.projectStateDidChange() }
    }

    // Localization unneeded: arrangement field names.
    func restorableState() -> [String: Any] {
        var state: [String: Any] = ["visible": sidebarVisible, "width": sidebarWidth, "remembered": rememberedTabs]
        if let selected = selectedProjectIdentifier { state["selected"] = selected }
        return state
    }

    @objc(restoreFromState:)
    func restore(from state: [String: Any]) {
        // A newly opened window starts with its panels collapsed, retaining width and tab associations.
        sidebarVisible = false
        sidebarWidth = (state["width"] as? NSNumber)?.doubleValue ?? 220
        selectedProjectIdentifier = (state["selected"] as? String).flatMap { catalog.project(withIdentifier: $0)?.identifier }
        rememberedTabs = state["remembered"] as? [String: String] ?? [:]
    }
}
