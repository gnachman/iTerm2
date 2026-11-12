import Foundation

@objc enum iTermProjectSidebarNodeKind: Int { case folder, repository, worktree }

/// Frozen children are published as a unit before AppKit reloads its row cache.
@objcMembers final class iTermProjectSidebarNode: NSObject {
    let identifier: String
    let kind: iTermProjectSidebarNodeKind
    let project: iTermProjectDirectory?
    let repository: iTermGitRepositorySnapshot?
    let worktree: iTermGitWorktree?
    let children: [iTermProjectSidebarNode]
    let title: String
    let tooltip: String
    let hasError: Bool
    let isLoading: Bool

    init(identifier: String, kind: iTermProjectSidebarNodeKind, project: iTermProjectDirectory? = nil,
         repository: iTermGitRepositorySnapshot? = nil, worktree: iTermGitWorktree? = nil,
         children: [iTermProjectSidebarNode] = [], error: NSError? = nil, loading: Bool = false) {
        self.identifier = identifier; self.kind = kind; self.project = project
        self.repository = repository; self.worktree = worktree; self.children = children
        hasError = error != nil || worktree?.available == false
        isLoading = loading
        if let worktree {
            let name = worktree.branch ?? (worktree.head.isEmpty ? (worktree.rootDirectory as NSString).lastPathComponent : String(worktree.head.prefix(8)))
            if !worktree.available {
                title = String(localized: "Projects.WorktreeUnavailableTitle", defaultValue: "\(name) · Unavailable", comment: "Worktree row for an unavailable directory; placeholder is its branch or name")
            } else if worktree.isMain && worktree.locked {
                title = String(localized: "Projects.MainLockedWorktreeTitle", defaultValue: "\(name) · Main · Locked", comment: "Main checkout row with a Git lock; placeholder is its branch or name")
            } else if worktree.isMain {
                title = String(localized: "Projects.MainWorktreeTitle", defaultValue: "\(name) · Main", comment: "Main checkout row; placeholder is its branch or name")
            } else if worktree.locked {
                title = String(localized: "Projects.LockedWorktreeTitle", defaultValue: "\(name) · Locked", comment: "Git-locked worktree row; placeholder is its branch or name")
            } else { title = name }
            tooltip = title + "\n" + worktree.rootDirectory
        } else if let repository {
            let name = (repository.rootDirectory as NSString).lastPathComponent
            if error != nil {
                title = String(localized: "Projects.RepositoryReadFailedTitle", defaultValue: "\(name) · Read Failed", comment: "Repository heading whose worktrees could not be refreshed; placeholder is repository name")
            } else if loading && children.isEmpty {
                title = String(localized: "Projects.RepositoryLoadingTitle", defaultValue: "\(name) · Loading…", comment: "Repository heading while its first worktree list loads; placeholder is repository name")
            } else { title = name }
            tooltip = repository.rootDirectory + (error.map { "\n" + $0.localizedDescription } ?? "")
        } else {
            title = project?.name ?? ""
            tooltip = (project?.rootDirectory ?? "") + (error.map { "\n" + $0.localizedDescription } ?? "")
        }
    }

    @nonobjc func isEquivalent(to other: iTermProjectSidebarNode) -> Bool {
        identifier == other.identifier && kind == other.kind && title == other.title && tooltip == other.tooltip &&
            hasError == other.hasError && isLoading == other.isLoading && children.count == other.children.count &&
            zip(children, other.children).allSatisfy { $0.isEquivalent(to: $1) }
    }
}

@objcMembers final class iTermProjectSidebarTree: NSObject {
    let roots: [iTermProjectSidebarNode]
    private let nodes: [String: iTermProjectSidebarNode]
    private let projectNodes: [String: iTermProjectSidebarNode]

    init(catalog: iTermProjectCatalog) {
        var roots = [iTermProjectSidebarNode]()
        var nodes = [String: iTermProjectSidebarNode]()
        var repositories = [String: iTermGitRepositorySnapshot]()
        for repository in catalog.repositories { repositories[repository.identifier] = repository }
        var admitted = Set<String>()
        for project in catalog.projects {
            if let common = project.gitCommonDirectory, let repository = repositories[common] {
                guard admitted.insert(common).inserted else { continue }
                var worktrees = repository.worktrees
                var seen = Set(worktrees.map(\.identifier))
                for remembered in catalog.projects where remembered.gitCommonDirectory == common {
                    guard let item = catalog.worktree(forProjectIdentifier: remembered.identifier), seen.insert(item.identifier).inserted else { continue }
                    worktrees.append(item)
                }
                worktrees.sort {
                    if $0.isMain != $1.isMain { return $0.isMain }
                    let first = $0.branch ?? $0.rootDirectory, second = $1.branch ?? $1.rootDirectory
                    return first == second ? $0.rootDirectory < $1.rootDirectory : first.localizedStandardCompare(second) == .orderedAscending
                }
                let children = worktrees.map { item in
                    iTermProjectSidebarNode(identifier: "worktree:" + item.identifier, kind: .worktree,
                                            repository: repository, worktree: item)
                }
                let node = iTermProjectSidebarNode(identifier: "repository:" + common, kind: .repository,
                    repository: repository, children: children, error: catalog.repositoryError(forIdentifier: common),
                    loading: catalog.isRefreshingRepository(common))
                roots.append(node); nodes[node.identifier] = node
                for child in children { nodes[child.identifier] = child }
            } else {
                let node = iTermProjectSidebarNode(identifier: "folder:" + project.identifier, kind: .folder,
                                                   project: project, error: catalog.projectError(forIdentifier: project.identifier))
                roots.append(node); nodes[node.identifier] = node
            }
        }
        var projectNodes = [String: iTermProjectSidebarNode]()
        for project in catalog.projects {
            let key: String
            if let worktree = project.gitWorktreeDirectory { key = "worktree:" + worktree }
            else if let common = project.gitCommonDirectory { key = "repository:" + common }
            else { key = "folder:" + project.identifier }
            projectNodes[project.identifier] = nodes[key]
        }
        self.roots = roots; self.nodes = nodes; self.projectNodes = projectNodes
    }

    func node(withIdentifier identifier: String) -> iTermProjectSidebarNode? { nodes[identifier] }
    func node(forProjectIdentifier identifier: String) -> iTermProjectSidebarNode? { projectNodes[identifier] }
    func isEquivalent(to other: iTermProjectSidebarTree) -> Bool {
        roots.count == other.roots.count && zip(roots, other.roots).allSatisfy { $0.isEquivalent(to: $1) }
    }
}
