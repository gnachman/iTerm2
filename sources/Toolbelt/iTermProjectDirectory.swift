import Foundation
import Darwin

@objcMembers
final class iTermProjectDirectory: NSObject {
    let identifier: String
    let rootDirectory: String
    var name: String {
        let component = URL(fileURLWithPath: rootDirectory).lastPathComponent
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

    init(defaults: UserDefaults) {
        self.defaults = defaults
        super.init()
        // Loading metadata does not touch the filesystem. A missing disk is still a remembered project.
        for record in defaults.array(forKey: Self.defaultsKey) as? [[String: String]] ?? [] {
            guard let path = record["rootDirectory"], NSString(string: path).isAbsolutePath,
                  !path.contains("\0"), URL(fileURLWithPath: path).standardizedFileURL.path == path, let identifier = record["identifier"], UUID(uuidString: identifier) != nil,
                  !projects.contains(where: { $0.rootDirectory == path || $0.identifier == identifier }) else { continue }
            projects.append(iTermProjectDirectory(identifier: identifier, rootDirectory: path))
        }
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

    @nonobjc func addDirectoryIfCurrent(atPath path: String, reuseContainingProject: Bool = false, shouldAdd: @escaping () -> Bool,
                                       completion: @escaping (iTermProjectDirectory?, NSError?) -> Void) {
        let existingProjects = projects
        ioQueue.async {
            let result = Self.canonicalDirectory(path)
            var matchedProjects = [(identifier: String, depth: Int)]()
            if reuseContainingProject, case .success(let canonical) = result {
                for project in existingProjects {
                    guard case .success(let root) = Self.canonicalDirectory(project.rootDirectory),
                          canonical == root || canonical.hasPrefix(root == "/" ? "/" : root + "/") else { continue }
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
                    var existing = reuseContainingProject
                        ? self.project(containingDirectory: canonical)
                        : self.projects.first(where: { $0.rootDirectory == canonical })
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
                }
            }
        }
    }

    @objc(removeProjectWithIdentifier:)
    func removeProject(withIdentifier identifier: String) {
        guard projects.contains(where: { $0.identifier == identifier }) else { return }
        projects.removeAll { $0.identifier == identifier }
        persist()
    }

    private func persist() {
        defaults.set(projects.map { ["identifier": $0.identifier, "rootDirectory": $0.rootDirectory] }, forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: Notification.Name(Self.didChangeNotification), object: self)
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
