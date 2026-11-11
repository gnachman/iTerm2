import Foundation

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

    @objc(addDirectoryAtPath:completion:)
    func addDirectory(atPath path: String, completion: @escaping (iTermProjectDirectory?, NSError?) -> Void) {
        ioQueue.async {
            let result = Self.canonicalDirectory(path)
            DispatchQueue.main.async {
                switch result {
                case .failure(let error): completion(nil, error as NSError)
                case .success(let canonical):
                    if let existing = self.projects.first(where: { $0.rootDirectory == canonical }) {
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
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                return .failure(NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnsupportedSchemeError))
            }
            return .success(url.path)
        } catch { return .failure(error) }
    }
}
