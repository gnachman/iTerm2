import Foundation

/// Window integration uses stable tab IDs, never retaining a tab, session or window.
@objc protocol iTermProjectWindowDelegate: AnyObject {
    var projectTabAssociations: [String: String] { get }
    var projectActiveTabIdentifier: String? { get }
    func projectSelectTab(_ identifier: String)
    func projectAssign(_ project: String?, toTab identifier: String)
    func projectLaunch(_ project: iTermProjectDirectory, directory: String, completion: @escaping (String?) -> Void)
    func projectStateDidChange()
}

@objcMembers final class iTermProjectWindowController: NSObject {
    weak var delegate: iTermProjectWindowDelegate?
    private let catalog: iTermProjectCatalog
    private var observer: NSObjectProtocol?
    private var rememberedTabs = [String: String]()
    private var pending = Set<String>()
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
    }

    func activeTabDidChange() {
        guard let delegate = delegate else { return }
        selectionGeneration &+= 1
        tabsDidChange()
        let associations = delegate.projectTabAssociations
        selectedProjectIdentifier = delegate.projectActiveTabIdentifier.flatMap { associations[$0] }
            .flatMap { catalog.project(withIdentifier: $0)?.identifier }
        if let project = selectedProjectIdentifier, let tab = delegate.projectActiveTabIdentifier {
            rememberedTabs[project] = tab
        }
        delegate.projectStateDidChange()
    }

    func selectProject(_ project: iTermProjectDirectory) {
        guard catalog.project(withIdentifier: project.identifier) != nil, let delegate = delegate else { return }
        if selectedProjectIdentifier != project.identifier { selectionGeneration &+= 1 }
        selectedProjectIdentifier = project.identifier
        delegate.projectStateDidChange()
        let associations = delegate.projectTabAssociations
        let remembered = rememberedTabs[project.identifier].flatMap { associations[$0] == project.identifier ? $0 : nil }
        if let tab = remembered ?? associations.keys.sorted().first(where: { associations[$0] == project.identifier }) {
            rememberedTabs[project.identifier] = tab
            delegate.projectSelectTab(tab)
            return
        }
        guard pending.insert(project.identifier).inserted else { return }
        let generation = selectionGeneration
        delegate.projectLaunch(project, directory: project.rootDirectory) { [weak self] tab in
            guard let self = self else { return }
            self.pending.remove(project.identifier)
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
        for (tab, project) in delegate.projectTabAssociations where !project.isEmpty && catalog.project(withIdentifier: project) == nil {
            delegate.projectAssign(nil, toTab: tab)
        }
        activeTabDidChange()
    }

    // Localization unneeded: arrangement field names.
    func restorableState() -> [String: Any] {
        var state: [String: Any] = ["visible": sidebarVisible, "width": sidebarWidth, "remembered": rememberedTabs]
        if let selected = selectedProjectIdentifier { state["selected"] = selected }
        return state
    }

    @objc(restoreFromState:)
    func restore(from state: [String: Any]) {
        sidebarVisible = state["visible"] as? Bool ?? false
        sidebarWidth = (state["width"] as? NSNumber)?.doubleValue ?? 220
        selectedProjectIdentifier = (state["selected"] as? String).flatMap { catalog.project(withIdentifier: $0)?.identifier }
        rememberedTabs = state["remembered"] as? [String: String] ?? [:]
    }
}
