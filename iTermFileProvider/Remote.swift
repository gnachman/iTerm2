import Foundation
import FileProvider

struct RemoteFile: Codable, Equatable, CustomDebugStringConvertible {
    struct FileInfo: Codable, Equatable {
        var size: Int?
    }

    struct Permissions: Codable, Equatable {
        var r: Bool = true
        var w: Bool = false
        var x: Bool = true
    }

    enum Kind: Codable, Equatable, CustomDebugStringConvertible {
        case file(FileInfo)
        case folder
        case host
        case symlink(String)

        var debugDescription: String {
            switch self {
            case .file(let info):
                if let size = info.size {
                    return "<file size=\(size)>"
                } else {
                    return "file"
                }
            case .symlink(let target):
                return "<symlink to \(target)>"
            case .folder:
                return "folder"
            case .host:
                return "host"
            }
        }
    }

    var kind: Kind
    var absolutePath: String
    var permissions: Permissions?
    var parentPermissions: Permissions?
    var ctime: Date?
    var mtime: Date?

    var name: String {
        (absolutePath as NSString).lastPathComponent
    }

    var parentAbsolutePath: String? {
        if absolutePath == "/" {
            return nil
        }
        return (absolutePath as NSString).deletingLastPathComponent
    }

    static var root: RemoteFile {
        return RemoteFile(kind: .folder,
                          absolutePath: "/",
                          permissions: Permissions(r: true, w: false, x: true),
                          parentPermissions: Permissions(r: false, w: false, x: true))
    }

    static let workingSetPrefix = ".working"
    static var workingSet: RemoteFile {
        return RemoteFile(kind: .folder,
                          absolutePath: workingSetPrefix)
    }

    var debugDescription: String {
        return "<RemoteFile: kind=\(kind) absolutePath=\(absolutePath)>"
    }
}

enum Node: CustomDebugStringConvertible {
    case folder(name: String, children: [Node])
    case file(name: String)
    case host(name: String, children: [Node])
    case symlink(name: String, target: String)

    var name: String {
        switch self {
        case .folder(name: let name, children: _),
                .file(name: let name),
                .host(name: let name, children: _),
                .symlink(name: let name, target: _):
            return name
        }
    }

    var debugDescription: String {
        switch self {
        case .folder(name: let name, children: let children):
            return "<Folder \(name) children.count=\(children.count)>"
        case .file(name: let name):
            return "<File \(name)>"
        case .host(name: let name, children: let children):
            return "<Host \(name) children.count=\(children.count)>"
        case .symlink(name: let name, target: let target):
            return "<Symlink \(name) -> \(target)>"
        }
    }

    func twiddled(_ count: Int) -> Node {
        if count == 0 {
            return self
        }
        switch self {
        case .folder(name: let name, children: let children):
            return .folder(name: name.replacingOccurrences(of: "{twiddle}",
                                                           with: String(count)),
                           children: children)
        case .file(name: let name):
            return .file(name: name.replacingOccurrences(of: "{twiddle}",
                                                         with: String(count)))
        case .symlink(name: let name, target: let target):
            return .symlink(name: name.replacingOccurrences(of: "{twiddle}",
                                                            with: String(count)),
                            target: target)
        case .host(name: let name, children: let children):
            return .host(name: name.replacingOccurrences(of: "{twiddle}",
                                                         with: String(count)),
                         children: children)
        }
    }
}

actor RemoteService {
    struct ListResult: CustomDebugStringConvertible {
        var files: [RemoteFile]
        var nextPage: Data?

        var debugDescription: String {
            return "<ListResult: files=\(files) nextPage=\(nextPage?.description ?? "(nil)")>"
        }
    }

    enum FileSorting {
        case byDate
        case byName
    }

    static var instance = RemoteService()
    // page -> remaining files
    private var outstanding = [Data: [RemoteFile]]() {
        didSet {
            log("outstanding: changed to have keys: \(outstanding.keys.map { $0.stringOrHex })")
        }
    }
    private var counter = 0
    private let hardMaxCount = 1000
    private var subscriptions = Set<String>()
    private var twiddleCount = 0

    func twiddle() {
        twiddleCount += 1
    }

    func invalidateListFiles() async {
        log("Remote.invalidateListFiles()")
        outstanding.removeAll()
    }

    func list(at path: String,
              fromPage requestedPage: Data?,
              sort: FileSorting,
              pageSize: Int?) async throws -> ListResult {
        return try await logging("Remote.list(at: \(path), fromPage: \(requestedPage?.stringOrHex ?? "(nil)"))") {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            switch try node(path) {
            case .file(_), .symlink:
                log("oops, asked for a file. Returning [],nil")
                return ListResult(files: [], nextPage: nil)

            case .folder(_, children: let children), .host(name: _, children: let children):
                let page: Data
                if let requestedPage = requestedPage {
                    // Non-first page.
                    page = requestedPage
                } else {
                    page = query(children, path, sort)
                }
                return pop(page, pageSize ?? 10)
            }
        }
    }

    func lookup(_ path: String) async throws -> RemoteFile {
        try await Task.sleep(nanoseconds: 1_000_000)
        let parent: String?
        if path == "/" {
            parent = nil
        } else {
            parent = (path as NSString).deletingLastPathComponent
        }
        return entry(try node(path), parent: parent)
    }

    func subscribe(_ paths: [String]) {
        subscriptions.formUnion(paths)
    }

    func unsubscribe(_ paths: [String]) {
        subscriptions.subtract(paths)
    }

    func fetch(_ path: String) -> AsyncStream<Result<Data, Error>> {
        AsyncStream { continuation in
            Task {
                guard let node = try? self.node(path) else {
                    continuation.yield(.failure(NSFileProviderError(.noSuchItem)))
                    return
                }
                var buffer = String(repeating: node.name, count: 10).data(using: .utf8)!
                let chunkSize = 4
                log("RemoteService: Begin sending \(path) in chunks of size \(chunkSize)")
                while !buffer.isEmpty {
                    log("RemoteServce: sleep for a bit")
                    try await Task.sleep(nanoseconds: 100_000_000)
                    let count = min(buffer.count, chunkSize)
                    let chunk = buffer.prefix(count)
                    buffer.removeFirst(count)
                    log("RemoteService: yield a chunk: \(chunk.stringOrHex)")
                    continuation.yield(.success(chunk))
                }
                log("RemoteService: fetch finished")
                continuation.finish()
            }
        }
    }

    private func host(_ path: String) -> String? {
        return (path as NSString).pathComponents.dropFirst().first
    }

    private func canParticipateInSymLinks(_ path: String) -> Bool {
        return (path as NSString).pathComponents.count > 2
    }

    func delete(_ file: RemoteFile, recursive: Bool) async throws {
        guard let node = try? node(file.absolutePath) else {
            throw NSFileProviderError(.noSuchItem)
        }
        guard recursive || node.children.isEmpty else {
            throw CocoaError(.fileWriteNoPermission)
        }
        switch node {
        case .host:
            throw CocoaError(.fileWriteNoPermission)
        default:
            break
        }
        Self.files = try Self.files.remove(file.absolutePath)
    }

    // While it would be nice to prevent symlinks across hosts, it's somewhere between hard and
    // impossible to do correctly, and NSFileProvider doesn't respect errors anyway so you can't
    // prevent it. Plus you have a moral right to create broken symlinks in unix. Furthermore, although
    // it's nonsense on the remote, it's useful (albeit evanescent) locally.
    func ln(source: String, file: RemoteFile) async throws -> RemoteFile {
        return try logging("ln -s \(source) \(file.absolutePath)") {
            switch try? node(file.absolutePath) {
            case .file, .symlink:
                Self.files = try Self.files.remove(file.absolutePath)
            case .none:
                break
            case .folder, .host:
                throw NSFileProviderError(.directoryNotEmpty)
            }
            Self.files = try Self.files.add(Node.symlink(name: file.name, target: source),
                                            in: file.parentAbsolutePath!)
            return entry(try node(file.absolutePath), parent: file.parentAbsolutePath)
        }
    }

    func mv(file: RemoteFile, newParent: String, newName: String) throws -> RemoteFile {
        return try logging("mv \(file.absolutePath) \(newParent)/\(newName)") {
            let saved = Self.files
            do {
                // Remove the source file.
                let source = try node(file.absolutePath)
                Self.files = try Self.files.remove(file.absolutePath)

                // Make sure we aren't renaming on top of an existing folder or host.
                let newPath = (newParent as NSString).appendingPathComponent(newName)
                switch try? node(newPath) {
                case .file, .symlink, .none:
                    break
                case .folder, .host:
                    log("Can't rename onto \(newPath) because it's a folder or a host.")
                    throw CocoaError(.fileWriteNoPermission)
                }

                // Remove the destination. It's OK for this to fail because it doesn't exist.
                Self.files = (try? Self.files.remove(newPath)) ?? Self.files

                // Add the old node but with a new name to its (possibly) new parent.
                Self.files = try Self.files.add(source.renamed(to: newName), in: newParent)

                return entry(try node(newPath), parent: newParent)
            } catch {
                log("mv threw \(error). Restore to saved state.")
                Self.files = saved
                throw error
            }
        }
    }

    func mkdir(_ file: RemoteFile) async throws {
        return try logging("mkdir \(file.absolutePath)") {
            Self.files = try Self.files.add(Node.folder(name: file.name, children: []),
                                            in: file.parentAbsolutePath!)
        }
    }

    func create(_ file: RemoteFile, content: Data) async throws {
        return try logging("create \(file.absolutePath) < \(content.count) bytes") {
            Self.files = try Self.files.add(Node.file(name: file.name),
                                            in: file.parentAbsolutePath!)
        }
    }

    func replaceContents(_ file: RemoteFile,
                         item: NSFileProviderItem,
                         url: URL) async throws -> RemoteFile {
        return try logging("replaceContents of \(file.absolutePath) with contents of \(url.path)") {
            log("Look up \(file.absolutePath)")
            switch try node(file.absolutePath) {
            case .file(name: _):
                log("It is a file. This may be allowed.")
                break
            default:
                log("Not a file, disallowed. child=\((try? node(file.absolutePath)).debugDescriptionOrNil)")
                throw CocoaError(.fileWriteNoPermission)
            }
            guard let parent = file.parentAbsolutePath else {
                log("The file has no parent. Can't modify the root.")
                throw CocoaError(.fileWriteNoPermission)
            }
            let data = try Data(contentsOf: url)
            log("Replace contents of \(file.absolutePath) with \(data.stringOrHex)")
            log("Remove \(file.absolutePath) before replacing it")
            Self.files = try Self.files.remove(file.absolutePath)
            log("Re-add \(file.absolutePath)")
            let node = try Self.files.add(Node.file(name: file.name), in: parent)
            log("Successful completion")
            return entry(node, parent: file.parentAbsolutePath)
        }
    }

    func setModificationDate(_ file: RemoteFile, date: Date) async throws -> RemoteFile {
        log("set mtime of \(file.absolutePath) to \(date)")
        return file
    }

    func chmod(_ file: RemoteFile, permissions: RemoteFile.Permissions) async throws -> RemoteFile {
        log("chmod \(file.absolutePath) to \(permissions)")
        return file
    }
}

extension Node {
    var children: [Node] {
        switch self {
        case .file, .symlink:
            return []
        case .host(name: _, children: let children), .folder(name: _, children: let children):
            return children
        }
    }
    func renamed(to name: String) -> Node {
        switch self {
        case .file(name: _):
            return .file(name: name)
        case .host(name: _, children: let children):
            return .host(name: name, children: children)
        case .folder(name: _, children: let children):
            return .folder(name: name, children: children)
        case .symlink(name: _, target: let target):
            return .symlink(name: name, target: target)
        }
    }

    func child(named: String) -> (Node, [Node])? {
        switch self {
        case .file, .symlink:
            return nil
        case let .host(name: _, children: children), let .folder(name: _, children: children):
            if let child = children.first(where: { $0.name == named }) {
                return (child, children.filter { $0.name != named })
            } else {
                return nil
            }
        }
    }

    func remove(_ path: String) throws -> Node {
        let adjustedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let parts = (adjustedPath as NSString).pathComponents
        precondition(parts.count > 0)
        let next = parts.first!
        guard let (child, siblings) = child(named: next) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        if parts.count > 1 {
            // modifying some descendant
            let modifiedChild = try child.remove(parts.dropFirst().joined(separator: "/"))
            switch self {
            case .file, .symlink:
                throw CocoaError(.fileWriteFileExists)
            case let .host(name: name, children: _):
                return .host(name: name, children: siblings + [modifiedChild].compactMap { $0 })
            case let .folder(name: name, children: _):
                return .folder(name: name, children: siblings + [modifiedChild].compactMap { $0 })
            }
        } else {
            // modify myself
            // This throws if the node has children or is a host.
            switch self {
            case .file, .symlink:
                throw CocoaError(.fileWriteFileExists)
            case let .host(name: name, children: _):
                return .host(name: name, children: siblings)
            case let .folder(name: name, children: _):
                return .folder(name: name, children: siblings)
            }
        }
    }

    func add(_ node: Node, in path: String) throws -> Node {
        let adjustedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let parts = (adjustedPath as NSString).pathComponents
        if let next = parts.first {
            guard let (child, siblings) = child(named: next) else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            let modifiedChild = try child.add(node,
                                          in: parts.dropFirst().joined(separator: "/"))
            switch self {
            case .file, .symlink:
                throw CocoaError(.fileWriteFileExists)
            case let .host(name: name, children: _):
                return .host(name: name, children: siblings + [modifiedChild])
            case let .folder(name: name, children: _):
                return .folder(name: name, children: siblings + [modifiedChild])
            }
        }
        switch self {
        case .file, .symlink:
            throw CocoaError(.fileWriteFileExists)
        case let .host(name: name, children: children):
            if children.contains(where: { $0.name == node.name }) {
                throw CocoaError(.fileWriteFileExists)
            }
            return Node.host(name: name, children: children + [node])
        case let .folder(name: name, children: children):
            if children.contains(where: { $0.name == node.name }) {
                throw CocoaError(.fileWriteFileExists)
            }
            return Node.folder(name: name, children: children + [node])
        }
    }
}
extension RemoteService {
    private static var files = Node.folder(
        name: "Root",
        children: [
            Node.host(name: "example.com",
                      children: [
                        Node.folder(name: "folder1",
                                    children:
                                        (0..<100).map {
                                            Node.file(name: "File \($0)")
                                        }),
                        Node.folder(name: "folder2",
                                    children: [
                                        .file(name: "Chuck"),
                                        .file(name: "Dave {twiddle}")]),
                        Node.symlink(name: "my_symlink",
                                     target: "/example.com/folder2/Chuck")
                      ])
        ])




    private func makePage() -> Data {
        defer {
            counter += 1
        }
        return String(counter).data(using: .utf8)!
    }

    private func query(_ children: [Node],
                       _ path: String,
                       _ sort: FileSorting) -> Data {
        // First page. Build the full list of results. In real life this would happen asynchronously.
        let entries = children.map {
            entry($0.twiddled(twiddleCount), parent: path)
        }.sorted { lhs, rhs in
            switch sort {
            case .byName:
                return lhs.name < rhs.name
            case .byDate:
                let ltime = lhs.mtime ?? Date.distantPast
                let rtime = rhs.mtime ?? Date.distantPast
                return ltime < rtime
            }
        }
        let page = makePage()
        log("query for \(path) returned \(entries). It will be assigned the initial page \(page.stringOrHex)")
        if !entries.isEmpty {
            log("outstanding: set outstanding[\(page.stringOrHex)] = \(entries)")
            outstanding[page] = entries
        }
        return page
    }

    private func pop(_ page: Data,
                     _ maxCount: Int) -> ListResult {
        return logging("Remote.pop(page: \(page.stringOrHex)") {
            guard let remaining = outstanding[page] else {
                // Invalid page requested.
                log("outstanding; Invalid page requested. Known pages: \(self.outstanding.keys.map { $0.stringOrHex })")
                return ListResult(files: [], nextPage: nil)
            }

            // Will return the first results of this known page.
            let nextPage: Data?
            let count = min(maxCount, remaining.count, hardMaxCount)
            let files = remaining[0..<count]

            // Invalidate the page
            log("Removing the page I just got results for")
            log("outstanding: remove \(page.stringOrHex)")
            outstanding.removeValue(forKey: page)

            if remaining.count <= count {
                // This was the last page.
                log("This was the last page")
                nextPage = nil
            } else {
                // This was not the last page. Make a new one.
                let p = makePage()
                nextPage = p
                log("outstanding: Save \(remaining.count - count) items to page \(p.stringOrHex)")
                outstanding[p] = Array(remaining[count...])
            }
            log("Return \(files.count) files for this page. Next page will be \(nextPage?.stringOrHex ?? "(nil)")")
            return ListResult(files: Array(files),
                              nextPage: nextPage)
        }
    }

    private func node(_ path: String) throws -> Node {
        var components = (path as NSString).pathComponents.dropFirst()
        var current: Node? = Self.files
        while !components.isEmpty {
            switch current {
            case .file(name: _), .symlink:
                throw NSFileProviderError(.noSuchItem)
            case .folder(name: _, children: let children), .host(name: _, children: let children):
                current = children.first { $0.name == components.first }
            case .none:
                break
            }
            components.removeFirst()
        }
        guard let current = current else {
            throw NSFileProviderError(.noSuchItem)
        }
        return current.twiddled(twiddleCount)
    }

    private func permissions(path: String?) -> RemoteFile.Permissions {
        guard let path = path else {
            // No parent is the root
            return RemoteFile.Permissions(r: true, w: false, x: true)
        }

        let count = (path as NSString).pathComponents.count
        if count <= 1 {
            // Root is readonly so you can't delete its children.
            return RemoteFile.Permissions(r: true, w: false, x: true)
        }
        // For simplicity make all folders including roots of hosts writable.
        return RemoteFile.Permissions(r: true, w: true, x: true)
    }

    private func entry(_ node: Node, parent: String?) -> RemoteFile {
        switch node {
        case .file(name: let name):
            return RemoteFile(
                kind: .file(RemoteFile.FileInfo(size: name.count * 1024)),
                absolutePath: ((parent ?? "/") as NSString).appendingPathComponent(name),
                permissions: RemoteFile.Permissions(r: true, w: true, x: false),
                parentPermissions: permissions(path: parent),
                mtime: Date())
        case .symlink(name: let name, target: let target):
            return RemoteFile(
                kind: .symlink(target),
                absolutePath: ((parent ?? "/") as NSString).appendingPathComponent(name),
                permissions: RemoteFile.Permissions(r: true, w: true, x: false),
                parentPermissions: permissions(path: parent),
                mtime: Date())
        case .folder(name: let name, children: _):
            return RemoteFile(
                kind: .folder,
                absolutePath: ((parent ?? "/") as NSString).appendingPathComponent(name),
                permissions: RemoteFile.Permissions(r: true, w: true, x: true),
                parentPermissions: permissions(path: parent),
                mtime: Date())
        case .host(name: let name, children: _):
            return RemoteFile(
                kind: .folder,
                absolutePath: ((parent ?? "/") as NSString).appendingPathComponent(name),
                permissions: RemoteFile.Permissions(r: true, w: true, x: true),
                parentPermissions: permissions(path: parent),
                mtime: Date())
        }
    }
}
