//
//  ConductorRegistry.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/5/22.
//

import Foundation
import FileProviderService

enum SSHEndpointException: Error {
    case connectionClosed
    case fileNotFound
    case internalError  // e.g., non-decodable data from fetch
}

protocol SSHEndpoint: AnyObject {
    @available(macOS 11.0, *)
    func listFiles(_ path: String, sort: FileSorting) async throws -> [RemoteFile]

    @available(macOS 11.0, *)
    func download(_ path: String) async throws -> Data

    @available(macOS 11.0, *)
    func stat(_ path: String) async throws -> RemoteFile

    @available(macOS 11.0, *)
    func delete(_ path: String, recursive: Bool) async throws

    @available(macOS 11.0, *)
    func ln(_ source: String, _ symlink: String) async throws -> RemoteFile

    @available(macOS 11.0, *)
    func mv(_ file: String, newParent: String, newName: String) async throws -> RemoteFile

    @available(macOS 11.0, *)
    func mkdir(_ file: String) async throws

    @available(macOS 11.0, *)
    func create(_ file: String, content: Data) async throws

    @available(macOS 11.0, *)
    func replace(_ file: String, content: Data) async throws -> RemoteFile

    @available(macOS 11.0, *)
    func setModificationDate(_ file: String, date: Date) async throws -> RemoteFile

    @available(macOS 11.0, *)
    func chmod(_ file: String, permissions: RemoteFile.Permissions) async throws -> RemoteFile

    var sshIdentity: SSHIdentity { get }
}

@available(macOS 11.0, *)
public struct SSHConnectionIdentifier: Codable, Hashable, CustomDebugStringConvertible {
    public let identity: SSHIdentity
    public var name: String { identity.compactDescription }

    public var stringIdentifier: String {
        return identity.stringIdentifier
    }

    public var debugDescription: String {
        return stringIdentifier
    }

    public init(_ identity: SSHIdentity) {
        self.identity = identity
    }

    public init?(stringIdentifier string: String) {
        let parts = string.components(separatedBy: ";")
        guard parts.count == 2 else {
            return nil
        }
        guard let identity = SSHIdentity(stringIdentifier: parts[1]) else {
            return nil
        }
        self.identity = identity
    }
}

@available(macOS 11.0, *)
@globalActor final actor ConductorRegistry: SSHFileGatewayDelegate {
    public static let shared = ConductorRegistry()
    private let sshFileGatway = SSHFileGateway()

    private var endpoints: [String: SSHEndpointProxy] = [:]

    func register(_ endpoint: SSHEndpoint) {
        log("Register endpoint \(endpoint.sshIdentity.compactDescription)")
        endpoints[endpoint.sshIdentity.stringIdentifier] = SSHEndpointProxy(endpoint)
        Task {
            await sshFileGatway.start(delegate: self)
        }
    }

    func handleSSHFileRequest(_ request: ExtensionToMainAppPayload.Event.Kind) async -> MainAppToExtensionPayload.Event.Kind {
        log("Handle SSH request \(request.debugDescription)")
        logger.debug("handleSSHFileRequest: \(request.debugDescription, privacy: .public)")
        switch request {
        case .list(path: let path, requestedPage: let requestedPage, sort: let sort, pageSize: let pageSize):
            return await list(path: path, requestedPage: requestedPage, sort: sort, pageSize: pageSize)
        case .lookup(path: let path):
            return await lookup(path: path)
        case .subscribe(paths: let paths):
            return await subscribe(paths: paths)
        case .fetch(path: let path):
            return await fetch(path: path)
        case .delete(file: let file, recursive: let recursive):
            return await delete(file: file, recursive: recursive)
        case .ln(source: let source, file: let file):
            return await ln(source: source, file: file)
        case .mv(file: let file, newParent: let newParent, newName: let newName):
            return await mv(file: file, newParent: newParent, newName: newName)
        case .mkdir(file: let file):
            return await mkdir(file: file)
        case .create(file: let file, content: let content):
            return await create(file: file, content: content)
        case .replaceContents(file: let file, url: let url):
            return await replaceContents(file: file, url: url)
        case .setModificationDate(file: let file, date: let date):
            return await setModificationDate(file: file, date: date)
        case .chmod(file: let file, permissions: let permissions):
            return await chmod(file: file, permissions: permissions)
        }
    }

    enum DataSource {
        case ssh(SSHEndpoint)
        case root([SSHEndpoint])
    }

    private func endpoint(forPath path: String) -> DataSource? {
        guard path.hasPrefix("/") else {
            return nil
        }
        let components = (path as NSString).pathComponents
        guard components.count > 1 else {
            return DataSource.root(Array(endpoints.values))
        }
        if let endpoint = endpoints[components[1]], endpoint.isValid {
            return .ssh(endpoint)
        }
        return nil
    }

    func list(path: String,
              requestedPage: Data?,
              sort: FileSorting,
              pageSize: Int?) async -> MainAppToExtensionPayload.Event.Kind {
        do {
            return .list(.success(try await listImpl(path: path,
                                                     requestedPage: requestedPage,
                                                     sort: sort,
                                                     pageSize: pageSize)))
        } catch let error as iTermFileProviderServiceError {
            return .list(.failure(error))
        } catch {
            return .list(.failure(.unknown(error.localizedDescription)))
        }
    }

    func lookup(path: String) async -> MainAppToExtensionPayload.Event.Kind {
        do {
            return .lookup(.success(try await lookupImpl(path: path)))
        } catch let error as iTermFileProviderServiceError {
            return .lookup(.failure(error))
        } catch {
            return .lookup(.failure(.unknown(error.localizedDescription)))
        }
    }

    func subscribe(paths: [String]) async -> MainAppToExtensionPayload.Event.Kind {
        await subscribeImpl(paths: paths)
        return .subscribe
    }

    func fetch(path: String) async -> MainAppToExtensionPayload.Event.Kind {
        do {
            return .fetch(.success(try await fetchImpl(path: path)))
        } catch let error as iTermFileProviderServiceError {
            return .fetch(.failure(error))
        } catch {
            return .fetch(.failure(.unknown(error.localizedDescription)))
        }
    }

    func delete(file: RemoteFile,
                recursive: Bool) async -> MainAppToExtensionPayload.Event.Kind {
        do {
            try await deleteImpl(file: file, recursive: recursive)
            return .delete(nil)
        } catch let error as iTermFileProviderServiceError {
            return .delete(error)
        } catch {
            return .delete(.unknown(error.localizedDescription))
        }
    }

    func ln(source: String,
            file: RemoteFile) async -> MainAppToExtensionPayload.Event.Kind {
        do {
            return .ln(.success(try await lnImpl(source: source, file: file)))
        } catch let error as iTermFileProviderServiceError {
            return .ln(.failure(error))
        } catch {
            return .ln(.failure(.unknown(error.localizedDescription)))
        }
    }

    func mv(file: RemoteFile,
            newParent: String,
            newName: String) async -> MainAppToExtensionPayload.Event.Kind {
        do {
            return .mv(.success(try await mvImpl(file: file, newParent: newParent, newName: newName)))
        } catch let error as iTermFileProviderServiceError {
            return .mv(.failure(error))
        } catch {
            return .mv(.failure(.unknown(error.localizedDescription)))
        }
    }

    func mkdir(file: RemoteFile) async -> MainAppToExtensionPayload.Event.Kind {
        do {
            try await mkdirImpl(file: file)
            return .mkdir(nil)
        } catch let error as iTermFileProviderServiceError {
            return .mkdir(error)
        } catch {
            return .mkdir(.unknown(error.localizedDescription))
        }
    }

    func create(file: RemoteFile,
                content: Data) async -> MainAppToExtensionPayload.Event.Kind {
        do {
            try await createImpl(file: file, content: content)
            return .create(nil)
        } catch let error as iTermFileProviderServiceError {
            return .create(error)
        } catch {
            return .create(.unknown(error.localizedDescription))
        }
    }

    func replaceContents(file: RemoteFile,
                         url: URL) async -> MainAppToExtensionPayload.Event.Kind {
        do {
            return .replaceContents(.success(try await replaceContentsImpl(file: file, url: url)))
        } catch let error as iTermFileProviderServiceError {
            return .replaceContents(.failure(error))
        } catch {
            return .replaceContents(.failure(.unknown(error.localizedDescription)))
        }
    }

    func setModificationDate(file: RemoteFile,
                             date: Date) async -> MainAppToExtensionPayload.Event.Kind {
        do {
            return .setModificationDate(.success(try await setModificationDateImpl(file: file,
                                                                                   date: date)))
        } catch let error as iTermFileProviderServiceError {
            return .setModificationDate(.failure(error))
        } catch {
            return .setModificationDate(.failure(.unknown(error.localizedDescription)))
        }
    }

    func chmod(file: RemoteFile,
               permissions: RemoteFile.Permissions) async -> MainAppToExtensionPayload.Event.Kind {
        do {
            return .chmod(.success(try await chmodImpl(file: file, permissions: permissions)))
        } catch let error as iTermFileProviderServiceError {
            return .chmod(.failure(error))
        } catch {
            return .chmod(.failure(.unknown(error.localizedDescription)))
        }
    }

    // MARK: -

    func listImpl(path: String,
                  requestedPage: Data?,
                  sort: FileSorting,
                  pageSize: Int?) async throws -> ListResult {
        try await logging("list(path: \(path), page: \(requestedPage.stringOrHex), sort: \(sort), pageSize: \(pageSize.debugDescriptionOrNil)") {
            switch self.endpoint(forPath: path) {
            case .none:
                log("No endpoint for \(path)")
                throw iTermFileProviderServiceError.notFound(path)
            case .root(let endpoints):
                log("Root requested.")
                let files = endpoints.map { endpoint in
                    RemoteFile(kind: .host,
                               absolutePath: "/" + endpoint.sshIdentity.compactDescription,
                               permissions: RemoteFile.Permissions(r: true, w: false, x: true),
                               parentPermissions: RemoteFile.Permissions(r: true, w: false, x: true),
                               ctime: nil,
                               mtime: nil)
                }
                let sorted = files.sorted { lhs, rhs in
                    return lhs.absolutePath < rhs.absolutePath
                }
                log("Return \(sorted)")
                return ListResult(files: sorted, nextPage: nil)
            case .ssh(let endpoint):
                log("File at endpoint \(endpoint) requested. Calling endpoint.listFiles")
                let files = try await endpoint.listFiles(path.removingHost, sort: sort)
                log("endpoint.listFiles returned \(files.count) items")
                let sorted = files.sorted { lhs, rhs in
                    RemoteFile.lessThan(lhs, rhs, sort: sort)
                }.map {
                    $0.addingHost(endpoint.sshIdentity.compactDescription)
                }
                log("Send \(sorted) as output of ls")
                return ListResult(files: sorted, nextPage: nil)
            }

        }
    }

    func lookupImpl(path: String) async throws -> RemoteFile {
        return try await logging("lookup(\(path))") { () async throws -> RemoteFile in
            switch self.endpoint(forPath: path) {
            case .none:
                log("No endpoint for \(path)")
                throw iTermFileProviderServiceError.notFound(path)
            case .root(_):
                log("Lookup of root requested")
                return RemoteFile(
                    kind: .folder,
                    absolutePath: "/",
                    permissions: RemoteFile.Permissions(r: true, w: false, x: true),
                    parentPermissions: RemoteFile.Permissions(r: true, w: false, x: true))
            case .ssh(let endpoint):
                log("Lookup for \(path) goes to endpoint \(endpoint)")
                let components = (path as NSString).pathComponents
                if components.count == 2 {
                    // /example.com
                    let file = try await endpoint.stat("/")
                    log("Return .hsot")
                    return RemoteFile(
                        kind: .host,
                        absolutePath: "/" + endpoint.sshIdentity.compactDescription,
                        permissions: file.permissions,
                        parentPermissions: RemoteFile.Permissions(r: true, w: false, x: true),
                        ctime: file.ctime,
                        mtime: file.mtime)
                }
                precondition(components.count > 2)
                log("Calling out to stat")
                let result = try await endpoint.stat(path.removingHost).addingHost(endpoint.sshIdentity.compactDescription)
                log("stat returned \(result)")
                return result
            }
        }
    }

    func subscribeImpl(paths: [String]) async {
        // TODO
    }

    func fetchImpl(path: String) async throws -> Data {
        return try await logging("fetch(\(path))") {
            switch self.endpoint(forPath: path) {
            case .none:
                throw iTermFileProviderServiceError.notFound(path)
            case .root(_):
                throw iTermFileProviderServiceError.notAFile(path)
            case .ssh(let endpoint):
                return try await endpoint.download(path.removingHost)
            }
        }
    }

    func deleteImpl(file: RemoteFile,
                    recursive: Bool) async throws {
        try await logging("delete(\(file), recursive: \(recursive))") {
            switch self.endpoint(forPath: file.absolutePath) {
            case .none:
                throw iTermFileProviderServiceError.notFound(file.absolutePath)
            case .root(_):
                throw iTermFileProviderServiceError.permissionDenied(file.absolutePath)
            case .ssh(let endpoint):
                try await endpoint.delete(file.absolutePath.removingHost, recursive: recursive)
            }
            throw iTermFileProviderServiceError.todo
        }
    }

    func lnImpl(source: String,
                file: RemoteFile) async throws -> RemoteFile {
        return try await logging("ln -s \(source) \(file.absolutePath)") {
            switch self.endpoint(forPath: file.absolutePath) {
            case .none:
                throw iTermFileProviderServiceError.notFound(file.absolutePath)
            case .root(_):
                throw iTermFileProviderServiceError.permissionDenied(file.absolutePath)
            case .ssh(let endpoint):
                return try await endpoint.ln(source, file.absolutePath.removingHost)
            }
        }
    }

    func mvImpl(file: RemoteFile,
                newParent: String,
                newName: String) async throws -> RemoteFile {
        return try await logging("mv \(file.absolutePath) \(newParent)/\(newName)") {
            switch self.endpoint(forPath: file.absolutePath) {
            case .none:
                throw iTermFileProviderServiceError.notFound(file.absolutePath)
            case .root(_):
                throw iTermFileProviderServiceError.permissionDenied(file.absolutePath)
            case .ssh(let endpoint):
                return try await endpoint.mv(file.absolutePath.removingHost,
                                             newParent: newParent.removingHost,
                                             newName: newName)
            }
        }
    }

    func mkdirImpl(file: RemoteFile) async throws {
        try await logging("mkdir \(file.absolutePath)") {
            switch self.endpoint(forPath: file.absolutePath) {
            case .none, .root:
                throw iTermFileProviderServiceError.permissionDenied(file.absolutePath)
            case .ssh(let endpoint):
                try await endpoint.mkdir(file.absolutePath.removingHost)
            }
        }
    }

    func createImpl(file: RemoteFile,
                    content: Data) async throws {
        try await logging("create \(file.absolutePath)") {
            switch self.endpoint(forPath: file.absolutePath) {
            case .none, .root:
                throw iTermFileProviderServiceError.permissionDenied(file.absolutePath)
            case .ssh(let endpoint):
                try await endpoint.create(file.absolutePath.removingHost, content: content)
            }
        }
    }

    func replaceContentsImpl(file: RemoteFile,
                             url: URL) async throws -> RemoteFile {
        try await logging("replace \(file.absolutePath) \(url.path)") {
            switch self.endpoint(forPath: file.absolutePath) {
            case .none, .root:
                throw iTermFileProviderServiceError.permissionDenied(file.absolutePath)
            case .ssh(let endpoint):
                guard let data = try? Data(contentsOf: url) else {
                    throw iTermFileProviderServiceError.internalError(url.path + " not readable")
                }
                return try await endpoint.replace(file.absolutePath.removingHost, content: data)
            }
        }
    }

    func setModificationDateImpl(file: RemoteFile,
                                 date: Date) async throws -> RemoteFile {
        try await logging("setModificationDate \(file.absolutePath) \(date)") {
            switch self.endpoint(forPath: file.absolutePath) {
            case .none, .root:
                throw iTermFileProviderServiceError.permissionDenied(file.absolutePath)
            case .ssh(let endpoint):
                return try await endpoint.setModificationDate(file.absolutePath.removingHost, date: date)
            }
        }
    }

    func chmodImpl(file: RemoteFile,
                   permissions: RemoteFile.Permissions) async throws -> RemoteFile {
        try await logging("chmod \(file.absolutePath) \(permissions)") {
            switch self.endpoint(forPath: file.absolutePath) {
            case .none, .root:
                throw iTermFileProviderServiceError.permissionDenied(file.absolutePath)
            case .ssh(let endpoint):
                return try await endpoint.chmod(file.absolutePath.removingHost, permissions: permissions)
            }
        }
    }
}

fileprivate extension String {
    @available(macOS 11.0, *)
    var removingHost: String {
        let components = (self as NSString).pathComponents
        guard components.count > 1 else {
            // Shouldn't really happen
            log("Unexpected host \(self)")
            return "/"
        }
        // [/, example.com, foo, bar] -> "/" + [foo, bar].joined("/") == "/foo/bar"
        return "/" + components.dropFirst(2).joined(separator: "/")
    }
}

@available(macOS 11.0, *)
class SSHEndpointProxy: SSHEndpoint {
    private weak var value: SSHEndpoint?
    let sshIdentity: SSHIdentity

    init(_ endpoint: SSHEndpoint) {
        sshIdentity = endpoint.sshIdentity
        value = endpoint
    }

    var isValid: Bool {
        return value != nil
    }

    private func realEndpoint(_ path: String) throws -> SSHEndpoint {
        if let value = value {
            return value
        }
        throw iTermFileProviderServiceError.notFound(path)
    }

    @MainActor
    func listFiles(_ path: String, sort: FileSorting) async throws -> [RemoteFile] {
        return try await realEndpoint(path).listFiles(path, sort: sort)
    }

    @MainActor
    func download(_ path: String) async throws -> Data {
        return try await realEndpoint(path).download(path)
    }

    @MainActor
    func stat(_ path: String) async throws -> RemoteFile {
        return try await realEndpoint(path).stat(path)
    }

    @MainActor
    func delete(_ path: String, recursive: Bool) async throws {
        return try await realEndpoint(path).delete(path, recursive: recursive)
    }

    @MainActor
    func ln(_ source: String, _ symlink: String) async throws -> RemoteFile {
        return try await realEndpoint(symlink).ln(source, symlink)
    }

    @MainActor
    func mv(_ file: String, newParent: String, newName: String) async throws -> RemoteFile {
        return try await realEndpoint(file).mv(file, newParent: newParent, newName: newName)
    }

    @MainActor
    func mkdir(_ file: String) async throws {
        return try await realEndpoint(file).mkdir(file)
    }

    @MainActor
    func create(_ file: String, content: Data) async throws {
        return try await realEndpoint(file).create(file, content: content)
    }

    @MainActor
    func replace(_ file: String, content: Data) async throws -> RemoteFile {
        return try await realEndpoint(file).replace(file, content: content)
    }

    @MainActor
    func setModificationDate(_ file: String, date: Date) async throws -> RemoteFile {
        return try await realEndpoint(file).setModificationDate(file, date: date)
    }

    @MainActor
    func chmod(_ file: String, permissions: RemoteFile.Permissions) async throws -> RemoteFile {
        return try await realEndpoint(file).chmod(file, permissions: permissions)
    }
}

@available(macOS 11.0, *)
extension RemoteFile {
    func addingHost(_ host: String) -> RemoteFile {
        return RemoteFile(kind: kind,
                          absolutePath: "/" + host + absolutePath,
                          permissions: permissions,
                          parentPermissions: parentPermissions,
                          ctime: ctime,
                          mtime: mtime)
    }
}
