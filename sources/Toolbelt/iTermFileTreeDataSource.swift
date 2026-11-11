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
    private let ioQueue: DispatchQueue
    private(set) var rootPath: String?
    private(set) var generation = 0
    private var cache = [String: Listing]()
    private var requests = [String: (UUID, [(Listing) -> Void])]()
    var showsHiddenFiles = false {
        didSet { if oldValue != showsHiddenFiles { reset(rootPath: rootPath) } }
    }
    var loadedDirectoryPaths: [String] { cache.keys.sorted() }

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
        generation += 1
        self.rootPath = rootPath
        cache.removeAll()
        let pending = requests.values.flatMap { $0.1 }
        requests.removeAll()
        let cancellation = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        for completion in pending { completion(.failure(cancellation)) }
    }

    func invalidate(directoryPaths paths: Set<String>) {
        for path in paths {
            cache.removeValue(forKey: path)
            if let request = requests.removeValue(forKey: path) {
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
        requests[path] = (token, [completion])
        ioQueue.async {
            let result = Self.list(path: path, showsHiddenFiles: hidden)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation, self.requests[path]?.0 == token,
                      let pending = self.requests.removeValue(forKey: path) else { return }
                self.cache[path] = result
                if case .success(let children) = result { self.reconcileDescendants(of: path, children: children) }
                pending.1.forEach { $0(result) }
            }
        }
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
