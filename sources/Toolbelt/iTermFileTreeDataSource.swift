import Foundation

final class iTermFileTreeEntry: NSObject {
    let path: String
    let name: String
    let isDirectory: Bool
    let isExpandable: Bool
    init(path: String, name: String, isDirectory: Bool, isExpandable: Bool) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.isExpandable = isExpandable
    }
}

/// Main-thread lazy cache. Only the IO queue performs filesystem operations.
final class iTermFileTreeDataSource {
    typealias Listing = Result<[iTermFileTreeEntry], Error>
    /// Only this source can create snapshots. Entries come from IO or the validating restore API.
    final class CacheSnapshot {
        let rootPath: String
        let showsHiddenFiles: Bool
        let listings: [String: Listing]
        let entryCount: Int

        fileprivate init(rootPath: String, showsHiddenFiles: Bool, listings: [String: Listing], entryCount: Int) {
            self.rootPath = rootPath
            self.showsHiddenFiles = showsHiddenFiles
            self.listings = listings
            self.entryCount = entryCount
        }
    }
    private let ioQueue: DispatchQueue
    private(set) var rootPath: String?
    private(set) var generation = 0
    private(set) var cacheRevision = 0
    private var cache = [String: Listing]()
    private var snapshot: CacheSnapshot?
    private var requests = [String: (UUID, [(Listing) -> Void], DispatchWorkItem)]()
    var showsHiddenFiles = false {
        didSet { if oldValue != showsHiddenFiles { reset(rootPath: rootPath) } }
    }
    var loadedDirectoryPaths: [String] { cache.keys.sorted() }
    var cachedListings: [String: Listing] { cache }

    init(ioQueue: DispatchQueue = DispatchQueue(label: "com.iterm2.file-tree", qos: .utility)) {
        self.ioQueue = ioQueue
    }

    func cachedListing(atPath path: String) -> Listing? { cache[path] }

    /// Load remembered expansions using current directory membership, independent of outline callbacks.
    /// Descendants become candidates only after their expanded parent has been listed.
    func directoriesNeedingLoad(expandedPaths: Set<String>) -> [String] {
        guard let rootPath else { return [] }
        var needed = [String]()
        func visit(_ path: String) {
            guard let listing = cache[path] else { needed.append(path); return }
            guard case .success(let children) = listing else { return }
            for child in children where child.isExpandable && expandedPaths.contains(child.path) {
                visit(child.path)
            }
        }
        visit(rootPath)
        return needed
    }

    func reset(rootPath: String?) {
        self.rootPath = rootPath
        cache.removeAll()
        cacheDidChange()
        cancelPendingRequests()
    }

    private func cacheDidChange() {
        cacheRevision += 1
        snapshot = nil
    }

    /// Prune unreachable listings once, then share this immutable snapshot across root switches.
    func cacheSnapshot() -> CacheSnapshot? {
        if let snapshot { return snapshot }
        guard let rootPath, NSString(string: rootPath).isAbsolutePath, !rootPath.contains("\0"),
              URL(fileURLWithPath: rootPath).standardizedFileURL.path == rootPath else { return nil }
        var listings = [String: Listing]()
        var entryCount = 0
        func visit(_ path: String) {
            guard let listing = cache[path] else { return }
            listings[path] = listing
            if case .success(let children) = listing {
                entryCount += children.count
                for child in children where child.isExpandable { visit(child.path) }
            }
        }
        visit(rootPath)
        let result = CacheSnapshot(rootPath: rootPath, showsHiddenFiles: showsHiddenFiles,
                                   listings: listings, entryCount: entryCount)
        snapshot = result
        return result
    }

    /// This fast path accepts only an opaque source-created snapshot, never caller-built listings.
    func restoreCacheSnapshot(_ snapshot: CacheSnapshot) {
        guard snapshot.rootPath == rootPath, snapshot.showsHiddenFiles == showsHiddenFiles else { return }
        cache = snapshot.listings
        cacheDidChange()
        self.snapshot = snapshot
    }

    /// Obsolete reads cannot publish, but completed listings survive transient hiding.
    func cancelPendingRequests() {
        generation += 1
        let pending = Array(requests.values)
        requests.removeAll()
        for request in pending { request.2.cancel() }
        let cancellation = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        for request in pending { request.1.forEach { $0(.failure(cancellation)) } }
    }

    /// Restore only canonical paths reachable through expandable cached parents.
    /// The caller supplies a snapshot made with the current hidden-file mode after resetting.
    func restoreCachedListings(_ listings: [String: Listing]) {
        cache.removeAll()
        cacheDidChange()
        guard let rootPath, NSString(string: rootPath).isAbsolutePath, !rootPath.contains("\0"),
              URL(fileURLWithPath: rootPath).standardizedFileURL.path == rootPath else { return }
        func restore(_ path: String) {
            guard let listing = listings[path] else { return }
            switch listing {
            case .failure:
                cache[path] = listing
            case .success(let children):
                let prefix = path == "/" ? "/" : path + "/"
                guard Set(children.map(\.path)).count == children.count,
                      children.allSatisfy({ child in
                    !child.name.isEmpty && child.name != "." && child.name != ".." &&
                        !child.name.contains("/") && !child.name.contains("\0") &&
                        child.path == prefix + child.name &&
                        (!child.isExpandable || child.isDirectory) &&
                        (showsHiddenFiles || !child.name.hasPrefix("."))
                }) else { return }
                cache[path] = listing
                for child in children where child.isExpandable { restore(child.path) }
            }
        }
        restore(rootPath)
    }

    func invalidate(directoryPaths paths: Set<String>) {
        for path in paths {
            if cache.removeValue(forKey: path) != nil { cacheDidChange() }
            if let request = requests.removeValue(forKey: path) {
                request.2.cancel()
                let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
                request.1.forEach { $0(.failure(error)) }
            }
        }
    }

    func loadDirectory(atPath path: String, completion: @escaping (Listing) -> Void) {
        guard let rootPath, path == rootPath || path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/"),
              URL(fileURLWithPath: path).standardizedFileURL.path == path else {
            completion(.failure(NSError(domain: NSCocoaErrorDomain, code: NSFileReadInvalidFileNameError)))
            return
        }
        if let cached = cache[path] { completion(cached); return }
        if requests[path] != nil { requests[path]?.1.append(completion); return }
        let token = UUID()
        let generation = self.generation
        let hidden = showsHiddenFiles
        let work = DispatchWorkItem { [weak self] in
            let result = Self.list(path: path, showsHiddenFiles: hidden)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation, self.requests[path]?.0 == token,
                      let pending = self.requests.removeValue(forKey: path) else { return }
                self.cache[path] = result
                self.cacheDidChange()
                if case .success(let children) = result { self.reconcileDescendants(of: path, children: children) }
                pending.1.forEach { $0(result) }
            }
        }
        requests[path] = (token, [completion], work)
        ioQueue.async(execute: work)
    }

    /// A successful parent listing is authoritative, including when a child failed before it.
    private func reconcileDescendants(of path: String, children: [iTermFileTreeEntry]) {
        let childPaths = Set(children.filter(\.isExpandable).map(\.path))
        let prefix = path == "/" ? "/" : path + "/"
        let tracked = Set(cache.keys).union(requests.keys)
        let obsolete = tracked.filter { descendant in
            guard descendant != path, descendant.hasPrefix(prefix) else { return false }
            let name = descendant.dropFirst(prefix.count).split(separator: "/").first.map(String.init) ?? ""
            return !childPaths.contains(prefix + name)
        }
        invalidate(directoryPaths: obsolete)
    }

    private static func list(path: String, showsHiddenFiles: Bool) -> Listing {
        do {
            let url = URL(fileURLWithPath: path)
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey]
            let parentValues = try url.resourceValues(forKeys: keys)
            guard parentValues.isDirectory == true, parentValues.isSymbolicLink != true,
                  parentValues.isPackage != true else {
                return .failure(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError))
            }
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [])
            var entries = [iTermFileTreeEntry]()
            for child in urls {
                let values = try child.resourceValues(forKeys: keys)
                if !showsHiddenFiles && (values.isHidden == true || child.lastPathComponent.hasPrefix(".")) { continue }
                let directory = values.isDirectory == true
                // Foundation can return /private/var URLs for a /var root. Preserve the
                // parent spelling so every cached identity remains rooted in rootPath.
                let childPath = (path as NSString).appendingPathComponent(child.lastPathComponent)
                entries.append(iTermFileTreeEntry(path: childPath, name: child.lastPathComponent,
                                                  isDirectory: directory,
                                                  isExpandable: directory && values.isPackage != true && values.isSymbolicLink != true))
            }
            return .success(entries.sorted {
                if $0.isExpandable != $1.isExpandable { return $0.isExpandable }
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
            })
        } catch { return .failure(error) }
    }
}
