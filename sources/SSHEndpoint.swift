//
//  SSHEndpoint.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/25.
//

protocol SSHEndpoint: AnyObject {
    @available(macOS 11.0, *)
    @MainActor
    func listFiles(_ path: String, sort: FileSorting) async throws -> [RemoteFile]

    @available(macOS 11.0, *)
    @MainActor
    func download(_ path: String, chunk: DownloadChunk?) async throws -> Data

    @available(macOS 11.0, *)
    @MainActor
    func stat(_ path: String) async throws -> RemoteFile

    @available(macOS 11.0, *)
    @MainActor
    func delete(_ path: String, recursive: Bool) async throws

    @available(macOS 11.0, *)
    @MainActor
    func ln(_ source: String, _ symlink: String) async throws -> RemoteFile

    @available(macOS 11.0, *)
    @MainActor
    func mv(_ file: String, newParent: String, newName: String) async throws -> RemoteFile

    @available(macOS 11.0, *)
    @MainActor
    func mkdir(_ file: String) async throws

    @available(macOS 11.0, *)
    @MainActor
    func create(_ file: String, content: Data) async throws

    @available(macOS 11.0, *)
    @MainActor
    func replace(_ file: String, content: Data) async throws -> RemoteFile

    @available(macOS 11.0, *)
    @MainActor
    func setModificationDate(_ file: String, date: Date) async throws -> RemoteFile

    @available(macOS 11.0, *)
    @MainActor
    func chmod(_ file: String, permissions: RemoteFile.Permissions) async throws -> RemoteFile

    var sshIdentity: SSHIdentity { get }

    var homeDirectory: String? { get }
}

public struct RemoteFile: Codable, Equatable, CustomDebugStringConvertible {
    public struct FileInfo: Codable, Equatable {
        public var size: Int?

        public init(size: Int? = nil) {
            self.size = size
        }
    }

    public struct Permissions: Codable, Equatable {
        public var r: Bool = true
        public var w: Bool = false
        public var x: Bool = true

        public init(r: Bool = true,
                    w: Bool = false,
                    x: Bool = true) {
            self.r = r
            self.w = w
            self.x = x
        }
    }

    public enum Kind: Codable, Equatable, CustomDebugStringConvertible {
        case file(FileInfo)
        case folder
        case host
        case symlink(String)

        public var debugDescription: String {
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

    public var kind: Kind
    public var absolutePath: String
    public var permissions: Permissions?
    public var parentPermissions: Permissions?
    public var ctime: Date?
    public var mtime: Date?
    public var size: Int? {
        switch kind {
        case .file(let fileInfo):
            return fileInfo.size
        case .folder, .host, .symlink:
            return nil
        }
    }
    public static let workingSetPrefix = ".working"
    public static var workingSet: RemoteFile {
        return RemoteFile(kind: .folder,
                          absolutePath: workingSetPrefix)
    }

    public static func lessThan(_ lhs: RemoteFile, _ rhs: RemoteFile, sort: FileSorting) -> Bool {
        switch sort {
        case .byName:
            return lhs.absolutePath < rhs.absolutePath
        case .byDate:
            return (lhs.mtime ?? Date.distantPast) < (rhs.mtime ?? Date.distantPast)
        }
    }

    public init(kind: Kind,
                absolutePath: String,
                permissions: Permissions? = nil,
                parentPermissions: Permissions? = nil,
                ctime: Date? = nil,
                mtime: Date? = nil) {
        self.kind = kind
        self.absolutePath = absolutePath
        self.permissions = permissions
        self.parentPermissions = parentPermissions
        self.ctime = ctime
        self.mtime = mtime
    }

    public var debugDescription: String {
        return "<RemoteFile: kind=\(kind) absolutePath=\(absolutePath)>"
    }

    public static var root: RemoteFile {
        return RemoteFile(kind: .folder,
                          absolutePath: "/",
                          permissions: Permissions(r: true, w: false, x: true),
                          parentPermissions: Permissions(r: false, w: false, x: true))
    }

    public var name: String {
        (absolutePath as NSString).lastPathComponent
    }

    public var parentAbsolutePath: String? {
        if absolutePath == "/" {
            return nil
        }
        return (absolutePath as NSString).deletingLastPathComponent
    }
}

extension RemoteFile {
    var directoryEntry: iTermDirectoryEntry {
        var mode = mode_t(0)
        switch kind {
        case .folder:
            mode |= S_IFDIR
        default:
            break
        }
        if permissions?.r ?? true {
            mode |= S_IRUSR
        }
        if permissions?.x ?? false {
            mode |= S_IXUSR
        }
        return iTermDirectoryEntry(name: name, mode: mode)
    }
}

public enum FileSorting: Codable {
    case byDate
    case byName
}

struct DownloadChunk: Codable, Equatable {
    var offset: Int
    var size: Int
}

