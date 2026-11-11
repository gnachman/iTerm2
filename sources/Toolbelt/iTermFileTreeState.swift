import Foundation

/// Main-thread expansion, restoration and pending-read state for a file tree.
final class iTermFileTreeState {
    let source: iTermFileTreeDataSource
    private(set) var rootDirectory: String?
    var expandedPaths = Set<String>()
    var loadingPaths = Set<String>()
    private var expansionByRoot = [String: Set<String>]()

    init(source: iTermFileTreeDataSource = iTermFileTreeDataSource()) {
        self.source = source
    }

    func setRoot(_ root: String?) {
        guard root != rootDirectory else { return }
        if let rootDirectory { expansionByRoot[rootDirectory] = expandedPaths }
        rootDirectory = root
        expandedPaths = root.flatMap { expansionByRoot[$0] } ?? []
        loadingPaths.removeAll()
        source.reset(rootPath: root)
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

    func restorableState() -> [AnyHashable: Any] {
        if let rootDirectory { expansionByRoot[rootDirectory] = expandedPaths }
        // Localization unneeded: restoration keys. Paths have explicit plist sanitizer rules.
        var state: [AnyHashable: Any] = ["ProjectFileTreeExpandedPaths": expansionByRoot.mapValues { Array($0) },
                                       "ProjectFileTreeShowHidden": source.showsHiddenFiles]
        if let rootDirectory { state["ProjectFileTreeRoot"] = rootDirectory }
        return state
    }

    func restore(from state: [AnyHashable: Any]) {
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
