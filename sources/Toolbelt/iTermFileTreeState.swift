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
    private struct PreparedTree {
        let snapshot: iTermFileTreeDataSource.CacheSnapshot
        let directories: [String: [iTermFileTreeEntry]]
        let entries: [String: iTermFileTreeEntry]
    }
    private var preparedTree: PreparedTree?
    private var preparedRevision = -1
    // Memory only: retain at most four archived roots in addition to the active IO cache.
    // Large trees remain usable but are omitted from recent-root retention.
    private var cachedRoots = [String: PreparedTree]()
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
        preparedTree = nil
        if let incomingCache, incomingCache.snapshot.showsHiddenFiles == source.showsHiddenFiles {
            source.restoreCacheSnapshot(incomingCache.snapshot)
            preparedTree = incomingCache
            preparedRevision = source.cacheRevision
        }
    }

    private func rememberCache(forRoot root: String) {
        cachedRoots.removeValue(forKey: root)
        recentRoots.removeAll { $0 == root }
        guard let snapshot = source.cacheSnapshot(), snapshot.rootPath == root,
              snapshot.listings.count <= 20_000, snapshot.entryCount <= 20_000,
              !snapshot.listings.isEmpty, let prepared = prepareTree(snapshot: snapshot) else { return }
        cachedRoots[root] = prepared
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

    /// Refresh visible branches now; collapsed branches reload lazily when expanded again.
    func refreshVisibleDirectories() -> [String] {
        let tracked = Set(source.loadedDirectoryPaths).union(loadingPaths)
        var visible = expandedPaths.intersection(tracked)
        if let rootDirectory { visible.insert(rootDirectory) }
        let invalidated = tracked.union(visible)
        source.invalidate(directoryPaths: invalidated)
        loadingPaths.subtract(invalidated)
        return visible.sorted()
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
        guard let snapshot = source.cacheSnapshot(), let prepared = prepareTree(snapshot: snapshot) else {
            clearPublishedTree()
            return [:]
        }
        publishedRootDirectory = rootDirectory
        publishedDirectories = prepared.directories
        return prepared.entries
    }

    /// Called once after the view publishes an IO batch. Share its complete canonical map so
    /// the next root switch does not build another dictionary for the same displayed entries.
    func cachePublishedTree(canonicalEntries: [String: iTermFileTreeEntry]) {
        guard publishedRootDirectory == rootDirectory, let snapshot = source.cacheSnapshot() else { return }
        var directoryCount = 0
        let matches = snapshot.listings.allSatisfy { path, listing in
            guard case .success(let children) = listing else { return true }
            directoryCount += 1
            guard let published = publishedDirectories[path], children.count == published.count else { return false }
            return zip(children, published).allSatisfy { child, existing in
                child.path == existing.path && child.name == existing.name &&
                    child.isDirectory == existing.isDirectory && child.isExpandable == existing.isExpandable &&
                    canonicalEntries[existing.path] === existing
            }
        }
        if matches, directoryCount == publishedDirectories.count, canonicalEntries.count == snapshot.entryCount {
            preparedTree = PreparedTree(snapshot: snapshot, directories: publishedDirectories, entries: canonicalEntries)
            preparedRevision = source.cacheRevision
        } else {
            // Invalidated collapsed branches or partial publications cannot seed the fast path.
            _ = prepareTree(snapshot: snapshot)
        }
    }

    private func prepareTree(snapshot: iTermFileTreeDataSource.CacheSnapshot) -> PreparedTree? {
        guard snapshot.rootPath == rootDirectory else { return nil }
        if let preparedTree, preparedRevision == source.cacheRevision { return preparedTree }
        let listings = snapshot.listings
        var directories = [String: [iTermFileTreeEntry]]()
        var entries = [String: iTermFileTreeEntry]()
        entries.reserveCapacity(snapshot.entryCount)
        func publish(_ path: String) {
            guard case .success(let children)? = listings[path] else { return }
            // Preserve the outline's canonical identities after an unchanged IO refresh.
            let previous = publishedRootDirectory == rootDirectory ? publishedDirectories[path] : nil
            let previousEntries = previous.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.path, $0) }) } ?? [:]
            let canonical = children.map { child -> iTermFileTreeEntry in
                guard let existing = previousEntries[child.path], existing.name == child.name,
                      existing.isDirectory == child.isDirectory, existing.isExpandable == child.isExpandable else { return child }
                return existing
            }
            directories[path] = canonical
            for child in canonical {
                entries[child.path] = child
                if child.isExpandable { publish(child.path) }
            }
        }
        publish(snapshot.rootPath)
        let result = PreparedTree(snapshot: snapshot, directories: directories, entries: entries)
        preparedTree = result
        preparedRevision = source.cacheRevision
        return result
    }

    func publishDirectory(_ children: [iTermFileTreeEntry], atPath path: String) {
        guard let rootDirectory,
              path == rootDirectory || path.hasPrefix(rootDirectory == "/" ? "/" : rootDirectory + "/") else { return }
        if publishedRootDirectory != rootDirectory { clearPublishedTree() }
        preparedTree = nil
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
        preparedTree = nil
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
