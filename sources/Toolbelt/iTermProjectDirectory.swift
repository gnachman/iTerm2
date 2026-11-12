import Foundation
import Darwin

@objcMembers
final class iTermProjectDirectory: NSObject {
    let identifier: String
    let rootDirectory: String
    fileprivate(set) var gitCommonDirectory: String?
    fileprivate(set) var gitRepositoryRoot: String?
    fileprivate(set) var gitWorktreeDirectory: String?
    var name: String {
        let component = (rootDirectory as NSString).lastPathComponent
        return component.isEmpty ? rootDirectory : component
    }

    init(identifier: String, rootDirectory: String) {
        self.identifier = identifier
        self.rootDirectory = rootDirectory
        super.init()
    }
}

/// Main-thread catalog. All filesystem inspection is confined to the serial IO queue.
@objcMembers
final class iTermProjectCatalog: NSObject {
    // Localization unneeded: persisted identifiers and notification names.
    static let defaultsKey = "NoSyncProjectDirectories"
    static let didChangeNotification = "iTermProjectCatalogDidChange"
    static let shared = iTermProjectCatalog(defaults: iTermUserDefaults.userDefaults())
    private(set) var projects = [iTermProjectDirectory]()
    private let defaults: UserDefaults
    private let ioQueue = DispatchQueue(label: "com.iterm2.project-catalog", qos: .utility)
    private let scanner: iTermGitWorktreeScanning
    private var repositorySnapshots = [String: iTermGitRepositorySnapshot]()
    private var rememberedWorktrees = [String: iTermGitWorktree]()
    private var repositoryErrors = [String: NSError]()
    private var projectErrors = [String: NSError]()
    private struct Discovery {
        let token: UUID
        let generation: UInt64
        var completions: [(NSError?) -> Void]
    }
    private var discoveries = [String: Discovery]()
    private var membershipGeneration: UInt64 = 0
    private var removedRepositories = [String: UInt64]()
    var isScanning: Bool { !discoveries.isEmpty }
    var repositories: [iTermGitRepositorySnapshot] {
        var seen = Set<String>()
        return projects.compactMap { project in
            guard let common = project.gitCommonDirectory, seen.insert(common).inserted else { return nil }
            return repositorySnapshots[common] ?? iTermGitRepositorySnapshot(
                commonDirectory: common, rootDirectory: project.gitRepositoryRoot ?? project.rootDirectory, worktrees: [])
        }
    }

    @nonobjc init(defaults: UserDefaults, scanner: iTermGitWorktreeScanning = iTermGitWorktreeScanner.makeDefault()) {
        self.defaults = defaults
        self.scanner = scanner
        super.init()
        // Loading metadata does not touch the filesystem. A missing disk is still a remembered project.
        for record in defaults.array(forKey: Self.defaultsKey) as? [[String: String]] ?? [] {
            guard let path = record["rootDirectory"], NSString(string: path).isAbsolutePath,
                  Self.validRecordedPath(path), let identifier = record["identifier"], UUID(uuidString: identifier) != nil,
                  !projects.contains(where: { $0.rootDirectory == path || $0.identifier == identifier }) else { continue }
            let project = iTermProjectDirectory(identifier: identifier, rootDirectory: path)
            if let common = record["gitCommonDirectory"], let root = record["gitRepositoryRoot"],
               [common, root].allSatisfy(Self.validRecordedPath) {
                project.gitCommonDirectory = common
                project.gitRepositoryRoot = root
                if let worktree = record["gitWorktreeDirectory"], Self.validRecordedPath(worktree) { project.gitWorktreeDirectory = worktree }
            }
            projects.append(project)
        }
        DispatchQueue.main.async { [weak self] in self?.refreshRepositories(nil) }
    }

    @objc(projectWithIdentifier:)
    func project(withIdentifier identifier: String) -> iTermProjectDirectory? {
        projects.first { $0.identifier == identifier }
    }

    @nonobjc func project(containingDirectory path: String) -> iTermProjectDirectory? {
        projects.filter {
            path == $0.rootDirectory || path.hasPrefix($0.rootDirectory == "/" ? "/" : $0.rootDirectory + "/")
        }.max { $0.rootDirectory.count < $1.rootDirectory.count }
    }

    @objc(addDirectoryAtPath:completion:)
    func addDirectory(atPath path: String, completion: @escaping (iTermProjectDirectory?, NSError?) -> Void) {
        addDirectoryIfCurrent(atPath: path, shouldAdd: { true }, completion: completion)
    }

    @nonobjc func addDirectoryIfCurrent(atPath path: String, reuseContainingProject: Bool = false, requiredWorktreeRoot: String? = nil, shouldAdd: @escaping () -> Bool,
                                       completion: @escaping (iTermProjectDirectory?, NSError?) -> Void) {
        let existingProjects = projects
        ioQueue.async {
            let result = Self.canonicalDirectory(path)
            var matchedProjects = [(identifier: String, depth: Int)]()
            if case .success(let canonical) = result {
                for project in existingProjects {
                    guard case .success(let root) = Self.canonicalDirectory(project.rootDirectory),
                          canonical == root || (reuseContainingProject && canonical.hasPrefix(root == "/" ? "/" : root + "/")) else { continue }
                    if let requiredWorktreeRoot, root != requiredWorktreeRoot &&
                        !root.hasPrefix(requiredWorktreeRoot == "/" ? "/" : requiredWorktreeRoot + "/") { continue }
                    matchedProjects.append((project.identifier, root.count))
                }
            }
            let canonicalMatches = matchedProjects
            DispatchQueue.main.async {
                guard shouldAdd() else {
                    completion(nil, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
                    return
                }
                switch result {
                case .failure(let error): completion(nil, error as NSError)
                case .success(let canonical):
                    var existing: iTermProjectDirectory?
                    if reuseContainingProject, let requiredWorktreeRoot {
                        existing = self.projects.filter {
                            let root = $0.rootDirectory
                            return (canonical == root || canonical.hasPrefix(root == "/" ? "/" : root + "/")) &&
                                (root == requiredWorktreeRoot || root.hasPrefix(requiredWorktreeRoot == "/" ? "/" : requiredWorktreeRoot + "/"))
                        }.max { $0.rootDirectory.count < $1.rootDirectory.count }
                    } else {
                        existing = reuseContainingProject ? self.project(containingDirectory: canonical) :
                            self.projects.first(where: { $0.rootDirectory == canonical })
                    }
                    var existingDepth = existing?.rootDirectory.count ?? -1
                    for canonicalMatch in canonicalMatches {
                        if let normalized = self.project(withIdentifier: canonicalMatch.identifier),
                           canonicalMatch.depth > existingDepth {
                            existing = normalized
                            existingDepth = canonicalMatch.depth
                        }
                    }
                    if let existing {
                        completion(existing, nil)
                        return
                    }
                    let project = iTermProjectDirectory(identifier: UUID().uuidString, rootDirectory: canonical)
                    self.projects.append(project)
                    self.persist()
                    completion(project, nil)
                    self.refreshProject(withIdentifier: project.identifier) { _ in }
                }
            }
        }
    }

    @objc(removeProjectWithIdentifier:)
    func removeProject(withIdentifier identifier: String) {
        guard projects.contains(where: { $0.identifier == identifier }) else { return }
        let cancelled = discoveries.removeValue(forKey: identifier)
        projectErrors.removeValue(forKey: identifier)
        projects.removeAll { $0.identifier == identifier }
        discardUnusedRepositories()
        persist()
        cancelled?.completions.forEach { $0(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) }
    }

    private func persist() {
        defaults.set(projects.map { project -> [String: String] in
            var record = ["identifier": project.identifier, "rootDirectory": project.rootDirectory]
            record["gitCommonDirectory"] = project.gitCommonDirectory
            record["gitRepositoryRoot"] = project.gitRepositoryRoot
            record["gitWorktreeDirectory"] = project.gitWorktreeDirectory
            return record
        }, forKey: Self.defaultsKey)
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Notification.Name(Self.didChangeNotification), object: self)
    }

    @nonobjc private static func validRecordedPath(_ path: String) -> Bool {
        guard NSString(string: path).isAbsolutePath, !path.contains("\0") else { return false }
        if path == "/" { return true }
        return !path.hasSuffix("/") && !path.contains("//") &&
            !path.split(separator: "/").contains { $0 == "." || $0 == ".." }
    }

    @nonobjc func addWorkingDirectory(atPath path: String, shouldAdd: @escaping () -> Bool,
                                      completion: @escaping (iTermProjectDirectory?, NSError?) -> Void) {
        let generation = membershipGeneration
        ioQueue.async { [weak self] in
            let result = Self.canonicalDirectory(path)
            DispatchQueue.main.async { [weak self] in
                guard let self, shouldAdd() else { completion(nil, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)); return }
                guard case .success(let canonical) = result else {
                    if case .failure(let error) = result { completion(nil, error as NSError) }
                    return
                }
                self.scanner.scan(directory: canonical) { [weak self] snapshot, error in
                    guard let self, shouldAdd() else { completion(nil, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)); return }
                    if let snapshot, (self.removedRepositories[snapshot.identifier] ?? 0) > generation {
                        completion(nil, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)); return
                    }
                    let worktree = snapshot?.worktrees.filter {
                        canonical == $0.rootDirectory || canonical.hasPrefix($0.rootDirectory == "/" ? "/" : $0.rootDirectory + "/")
                    }.max { $0.rootDirectory.count < $1.rootDirectory.count }
                    let canCommit: () -> Bool = { [weak self] in
                        guard let self, shouldAdd() else { return false }
                        return snapshot.map { (self.removedRepositories[$0.identifier] ?? 0) <= generation } ?? true
                    }
                    self.addDirectoryIfCurrent(atPath: canonical, reuseContainingProject: worktree != nil || (snapshot == nil && error == nil),
                                               requiredWorktreeRoot: worktree?.rootDirectory, shouldAdd: canCommit) { [weak self] project, addError in
                        guard let self, let project else { completion(nil, addError); return }
                        if let snapshot, (self.removedRepositories[snapshot.identifier] ?? 0) > generation {
                            self.removeProject(withIdentifier: project.identifier)
                            completion(nil, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)); return
                        }
                        guard shouldAdd() else { completion(nil, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)); return }
                        if let snapshot, worktree != nil || canonical == snapshot.commonDirectory {
                            self.cacheRepositorySnapshot(snapshot)
                            if self.setMetadata(project, repository: snapshot, worktreeRoot: worktree?.rootDirectory) { self.persist() }
                        }
                        if let error { self.projectErrors[project.identifier] = error; self.notifyChanged() }
                        completion(project, addError)
                    }
                }
            }
        }
    }

    @nonobjc func worktree(forProjectIdentifier identifier: String) -> iTermGitWorktree? {
        guard let project = project(withIdentifier: identifier), let root = project.gitWorktreeDirectory else { return nil }
        return worktree(withIdentifier: root)
    }

    @nonobjc func worktree(withIdentifier identifier: String) -> iTermGitWorktree? {
        for repository in repositories {
            if let worktree = repository.worktrees.first(where: { $0.identifier == identifier }) { return worktree }
        }
        guard projects.contains(where: { $0.gitWorktreeDirectory == identifier }) else { return nil }
        let previous = rememberedWorktrees[identifier]
        return iTermGitWorktree(rootDirectory: identifier, branch: previous?.branch, head: previous?.head ?? "",
                                isMain: previous?.isMain ?? false, locked: previous?.locked ?? false,
                                prunable: true, available: false)
    }

    @nonobjc func repository(forWorktreeIdentifier identifier: String) -> iTermGitRepositorySnapshot? {
        repositories.first { repository in
            repository.worktrees.contains { $0.identifier == identifier } ||
                projects.contains { $0.gitCommonDirectory == repository.identifier && $0.gitWorktreeDirectory == identifier }
        }
    }

    func repositoryError(forIdentifier identifier: String) -> NSError? { repositoryErrors[identifier] }
    func projectError(forIdentifier identifier: String) -> NSError? { projectErrors[identifier] }
    func isRefreshingRepository(_ identifier: String) -> Bool {
        projects.contains { $0.gitCommonDirectory == identifier && discoveries[$0.identifier] != nil }
    }

    func refreshRepositories(_ identifiers: [String]?) {
        if let identifiers {
            for common in Set(identifiers) {
                guard let project = projects.first(where: { $0.gitCommonDirectory == common }) else { continue }
                refreshProject(withIdentifier: project.identifier) { _ in }
            }
        } else {
            for project in projects { refreshProject(withIdentifier: project.identifier) { _ in } }
        }
    }

    func refreshProject(withIdentifier identifier: String, completion: @escaping (NSError?) -> Void) {
        guard let project = project(withIdentifier: identifier) else {
            completion(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)); return
        }
        if var existing = discoveries[identifier] {
            existing.completions.append(completion); discoveries[identifier] = existing; return
        }
        let token = UUID()
        discoveries[identifier] = Discovery(token: token, generation: membershipGeneration, completions: [completion])
        if project.gitCommonDirectory != nil { notifyChanged() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.finishDiscovery(identifier, token: token, canonicalInput: nil, snapshot: nil,
                error: NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
                               userInfo: [NSLocalizedDescriptionKey: String(localized: "Projects.WorktreeScanTimeout", defaultValue: "Reading Git worktrees timed out. Try refreshing the list.", comment: "Error when repository discovery does not finish before its deadline")]))
        }
        let path = project.rootDirectory
        let fallback = project.gitRepositoryRoot
        ioQueue.async { [weak self] in
            let result = Self.canonicalDirectory(path)
            let canonical = try? result.get()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.discoveries[identifier]?.token == token, self.project(withIdentifier: identifier) != nil else { return }
                guard let directory = canonical ?? fallback else {
                    let error: NSError?
                    if case .failure(let failure) = result { error = failure as NSError } else { error = nil }
                    self.finishDiscovery(identifier, token: token, canonicalInput: canonical, snapshot: nil, error: error)
                    return
                }
                self.scanner.scan(directory: directory) { [weak self] snapshot, error in
                    self?.finishDiscovery(identifier, token: token, canonicalInput: canonical, snapshot: snapshot, error: error)
                }
            }
        }
    }

    @nonobjc private func finishDiscovery(_ identifier: String, token: UUID, canonicalInput: String?,
                                          snapshot: iTermGitRepositorySnapshot?, error: NSError?) {
        guard let request = discoveries[identifier], request.token == token,
              let project = project(withIdentifier: identifier) else { return }
        if let snapshot, (removedRepositories[snapshot.identifier] ?? 0) > request.generation {
            removeProject(withIdentifier: identifier)
            return
        }
        discoveries.removeValue(forKey: identifier)
        var metadataChanged = false
        if let error {
            projectErrors[identifier] = error
            if let common = project.gitCommonDirectory { repositoryErrors[common] = error }
        } else if let snapshot {
            projectErrors.removeValue(forKey: identifier)
            repositoryErrors.removeValue(forKey: snapshot.identifier)
            cacheRepositorySnapshot(snapshot)
            if let canonicalInput, let worktree = snapshot.worktrees.filter({
                canonicalInput == $0.rootDirectory || canonicalInput.hasPrefix($0.rootDirectory == "/" ? "/" : $0.rootDirectory + "/")
            }).max(by: { $0.rootDirectory.count < $1.rootDirectory.count }) {
                metadataChanged = setMetadata(project, repository: snapshot, worktreeRoot: worktree.rootDirectory)
            } else if canonicalInput == snapshot.commonDirectory {
                metadataChanged = setMetadata(project, repository: snapshot, worktreeRoot: nil)
            }
            for other in projects where other.gitCommonDirectory == snapshot.identifier {
                if other.gitRepositoryRoot != snapshot.rootDirectory {
                    other.gitRepositoryRoot = snapshot.rootDirectory; metadataChanged = true
                }
            }
        } else if canonicalInput != nil {
            projectErrors.removeValue(forKey: identifier)
            metadataChanged = project.gitCommonDirectory != nil
            project.gitCommonDirectory = nil; project.gitRepositoryRoot = nil; project.gitWorktreeDirectory = nil
        }
        discardUnusedRepositories()
        if metadataChanged { persist() } else if snapshot != nil || error != nil || project.gitCommonDirectory != nil { notifyChanged() }
        request.completions.forEach { $0(error) }
    }

    @nonobjc private func setMetadata(_ project: iTermProjectDirectory, repository: iTermGitRepositorySnapshot, worktreeRoot: String?) -> Bool {
        let changed = project.gitCommonDirectory != repository.identifier || project.gitRepositoryRoot != repository.rootDirectory ||
            project.gitWorktreeDirectory != worktreeRoot
        project.gitCommonDirectory = repository.identifier
        project.gitRepositoryRoot = repository.rootDirectory
        project.gitWorktreeDirectory = worktreeRoot
        return changed
    }

    @nonobjc private func cacheRepositorySnapshot(_ snapshot: iTermGitRepositorySnapshot) {
        for old in repositorySnapshots[snapshot.identifier]?.worktrees ?? [] { rememberedWorktrees[old.identifier] = old }
        repositorySnapshots[snapshot.identifier] = snapshot
        for item in snapshot.worktrees { rememberedWorktrees[item.identifier] = item }
    }

    @nonobjc private func discardUnusedRepositories() {
        let used = Set(projects.compactMap(\.gitCommonDirectory))
        repositorySnapshots = repositorySnapshots.filter { used.contains($0.key) }
        repositoryErrors = repositoryErrors.filter { used.contains($0.key) }
        let remembered = Set(projects.compactMap(\.gitWorktreeDirectory)).union(repositorySnapshots.values.flatMap { $0.worktrees.map(\.identifier) })
        rememberedWorktrees = rememberedWorktrees.filter { remembered.contains($0.key) }
    }

    @nonobjc func ensureWorktreeProject(_ worktree: iTermGitWorktree, shouldAdd: @escaping () -> Bool,
                                       completion: @escaping (iTermProjectDirectory?, NSError?) -> Void) {
        guard let repository = repository(forWorktreeIdentifier: worktree.identifier) else {
            completion(nil, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)); return
        }
        addDirectoryIfCurrent(atPath: worktree.rootDirectory, shouldAdd: { [weak self] in
            shouldAdd() && self?.repositories.contains(where: { $0.identifier == repository.identifier }) == true
        }) { [weak self] project, error in
            if let self, let project, self.setMetadata(project, repository: repository, worktreeRoot: worktree.rootDirectory) { self.persist() }
            completion(project, error)
        }
    }

    func removeRepository(withIdentifier identifier: String) {
        membershipGeneration &+= 1
        removedRepositories[identifier] = membershipGeneration
        let removed = projects.filter { $0.gitCommonDirectory == identifier }
        for project in removed { removeProject(withIdentifier: project.identifier) }
    }

    @nonobjc static func canonicalDirectory(_ path: String) -> Result<String, Error> {
        guard NSString(string: path).isAbsolutePath, !path.contains("\0") else {
            return .failure(NSError(domain: NSCocoaErrorDomain, code: NSFileReadInvalidFileNameError))
        }
        guard let resolved = realpath((path as NSString).fileSystemRepresentation, nil) else {
            return .failure(NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
        }
        defer { free(resolved) }
        let canonical = FileManager.default.string(withFileSystemRepresentation: resolved, length: strlen(resolved))
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical, isDirectory: &directory), directory.boolValue else {
            return .failure(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTDIR)))
        }
        return .success(canonical)
    }
}
