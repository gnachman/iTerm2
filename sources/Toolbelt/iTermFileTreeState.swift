import Foundation

/// Main-thread expansion, restoration and pending-read state for a file tree.
final class iTermFileTreeState {
    let source: iTermFileTreeDataSource
    private(set) var rootDirectory: String?
    var expandedPaths = Set<String>()
    var loadingPaths = Set<String>()
    private var expansionByRoot = [String: Set<String>]()
    private var publishedRootDirectory: String?
    private var publishedDirectories = [String: [iTermFileTreeEntry]]()
    private struct CachedRoot {
        let showsHiddenFiles: Bool
        let listings: [String: iTermFileTreeDataSource.Listing]
    }
    // Memory only: retain at most four archived roots in addition to the active IO cache.
    // Large trees remain usable but are omitted from recent-root retention.
    private var cachedRoots = [String: CachedRoot]()
    private var recentRoots = [String]()

    init(source: iTermFileTreeDataSource = iTermFileTreeDataSource()) {
        self.source = source
    }

    func setRoot(_ root: String?) {
        guard root != rootDirectory else { return }
        let incomingCache = root.flatMap { cachedRoots[$0] }
        if let rootDirectory {
            expansionByRoot[rootDirectory] = expandedPaths
            rememberCache(forRoot: rootDirectory)
        }
        rootDirectory = root
        expandedPaths = root.flatMap { expansionByRoot[$0] } ?? []
        loadingPaths.removeAll()
        source.reset(rootPath: root)
        if let incomingCache, incomingCache.showsHiddenFiles == source.showsHiddenFiles {
            source.restoreCachedListings(incomingCache.listings)
        }
    }

    private func rememberCache(forRoot root: String) {
        cachedRoots.removeValue(forKey: root)
        recentRoots.removeAll { $0 == root }
        let listings = source.cachedListings
        guard listings.count <= 20_000 else { return }
        var entryCount = 0
        for listing in listings.values {
            if case .success(let children) = listing { entryCount += children.count }
            if entryCount > 20_000 { return }
        }
        guard !listings.isEmpty else { return }
        cachedRoots[root] = CachedRoot(showsHiddenFiles: source.showsHiddenFiles, listings: listings)
        recentRoots.append(root)
        while recentRoots.count > 4 {
            cachedRoots.removeValue(forKey: recentRoots.removeFirst())
        }
    }

    func loadDirectory(atPath path: String, completion: @escaping (iTermFileTreeDataSource.Listing) -> Void) {
        guard loadingPaths.insert(path).inserted else { return }
        let generation = source.generation
        source.loadDirectory(atPath: path) { [weak self] result in
            guard let self, self.source.generation == generation else { return }
            self.loadingPaths.remove(path)
            completion(result)
        }
    }

    func directoriesNeedingLoad() -> [String] {
        source.directoriesNeedingLoad(expandedPaths: expandedPaths)
    }

    /// Outline row counts and child lookups use the last published listing, not the IO cache.
    func publishedChildren(of entry: iTermFileTreeEntry?) -> [iTermFileTreeEntry] {
        guard let path = entry?.path ?? publishedRootDirectory else { return [] }
        return publishedDirectories[path] ?? []
    }

    /// Clear immediately before reloading the outline when switching roots or restoring state.
    func clearPublishedTree() {
        publishedRootDirectory = rootDirectory
        publishedDirectories.removeAll()
    }

    /// Hydrate the next outline snapshot without IO, preserving cached entry identities.
    /// The caller reloads AppKit immediately after installing these canonical entries.
    func preparePublishedTreeFromCache() -> [String: iTermFileTreeEntry] {
        clearPublishedTree()
        guard let rootDirectory else { return [:] }
        let listings = source.cachedListings
        var entries = [String: iTermFileTreeEntry]()
        func publish(_ path: String) {
            guard case .success(let children)? = listings[path] else { return }
            // This is a fresh snapshot: no previous descendants need reconciliation.
            publishedDirectories[path] = children
            for child in children {
                entries[child.path] = child
                if child.isExpandable { publish(child.path) }
            }
        }
        publish(rootDirectory)
        return entries
    }

    func publishDirectory(_ children: [iTermFileTreeEntry], atPath path: String) {
        guard let rootDirectory,
              path == rootDirectory || path.hasPrefix(rootDirectory == "/" ? "/" : rootDirectory + "/") else { return }
        if publishedRootDirectory != rootDirectory { clearPublishedTree() }
        let childPaths = Set(children.filter(\.isExpandable).map(\.path))
        let prefix = path == "/" ? "/" : path + "/"
        for descendant in Array(publishedDirectories.keys) where descendant != path && descendant.hasPrefix(prefix) {
            let name = descendant.dropFirst(prefix.count).split(separator: "/").first.map(String.init) ?? ""
            if !childPaths.contains(prefix + name) { publishedDirectories.removeValue(forKey: descendant) }
        }
        publishedDirectories[path] = children
    }

    func restorableState() -> [AnyHashable: Any] {
        if let rootDirectory { expansionByRoot[rootDirectory] = expandedPaths }
        // Localization unneeded: restoration keys. Paths have explicit plist sanitizer rules.
        var state: [AnyHashable: Any] = ["ProjectFileTreeExpandedPaths": expansionByRoot.mapValues { Array($0) },
                                       "ProjectFileTreeShowHidden": source.showsHiddenFiles]
        if let rootDirectory { state["ProjectFileTreeRoot"] = rootDirectory }
        return state
    }

    func restore(from state: [AnyHashable: Any]) {
        cachedRoots.removeAll()
        recentRoots.removeAll()
        let remembered = state["ProjectFileTreeExpandedPaths"] as? [String: [String]] ?? [:]
        expansionByRoot = remembered.reduce(into: [:]) { output, record in
            guard NSString(string: record.key).isAbsolutePath, !record.key.contains("\0"), URL(fileURLWithPath: record.key).standardizedFileURL.path == record.key else { return }
            output[record.key] = Set(record.value.filter { $0.hasPrefix(record.key == "/" ? "/" : record.key + "/") && !$0.contains("\0") && URL(fileURLWithPath: $0).standardizedFileURL.path == $0 })
        }
        // Restoring replaces live expansion, even when the selected root is already installed.
        // Do not call setRoot: its normal switching behavior would save the old live expansion
        // over the newly restored record for that root.
        if let root = state["ProjectFileTreeRoot"] as? String, NSString(string: root).isAbsolutePath, !root.contains("\0") {
            rootDirectory = root
        }
        expandedPaths = rootDirectory.flatMap { expansionByRoot[$0] } ?? []
        loadingPaths.removeAll()
        source.showsHiddenFiles = state["ProjectFileTreeShowHidden"] as? Bool == true
        source.reset(rootPath: rootDirectory)
    }
}
