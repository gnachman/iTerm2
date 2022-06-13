import FileProvider
import FileProviderService
import UniformTypeIdentifiers

extension RemoteFile {
    var itemIdentifier: NSFileProviderItemIdentifier {
        if absolutePath == Self.root.absolutePath {
            return .rootContainer
        }
        return .init(rawValue: absolutePath)
    }
}

extension RemoteFile {
    func rebased(_ manager: NSFileProviderManager?) async -> RemoteFile {
        guard let manager = manager else {
            return self
        }
        return rebased(try? await manager.getUserVisibleURL(for: .rootContainer))
    }

    func rebased(_ root: URL?) -> RemoteFile {
        guard let root = root else {
            return self
        }

        switch kind {
        case .symlink(let target):
            let rebasedTarget = rebaseRemoteFile(root, path: target)
            return RemoteFile(kind: .symlink(rebasedTarget),
                              absolutePath: absolutePath,
                              permissions: permissions,
                              parentPermissions: parentPermissions,
                              ctime: ctime,
                              mtime: mtime)
        default:
            return self
        }
    }
}

// This is a wrapper around RemoteFile that represents the item locally. Besides adding conformance
// to NSFileProviderItem, it also rewrites absolute-path symlinks to make sense based on where the
// domain is mounted.
class FileProviderItem: NSObject, NSFileProviderItem {
    let entry: RemoteFile

    init(_ entry: RemoteFile, manager: NSFileProviderManager?) async {
        self.entry = await entry.rebased(manager)
    }

    init(_ entry: RemoteFile, userVisibleRoot: URL?) {
        self.entry = entry.rebased(userVisibleRoot)
    }

    override var description: String {
        return "<FileProviderItem: \(entry)>"
    }
    
    var itemIdentifier: NSFileProviderItemIdentifier {
        entry.itemIdentifier
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        if let path = entry.parentAbsolutePath,
            path != RemoteFile.root.absolutePath {
            return .init(rawValue: path)
        }
        return .rootContainer
    }
    
    var capabilities: NSFileProviderItemCapabilities {
        var result: NSFileProviderItemCapabilities = []
        if entry.permissions?.r ?? true {
            result.formUnion([.allowsReading])
        }
        if entry.permissions?.w ?? false {
            result.formUnion([.allowsWriting, .allowsEvicting])
        }
        if entry.parentPermissions?.w ?? false {
            result.formUnion([.allowsDeleting, .allowsRenaming, .allowsReparenting])
        }
        return result
    }
    
    var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(contentVersion: "a content version".data(using: .utf8)!,
                                  metadataVersion: "a metadata version".data(using: .utf8)!)
    }
    
    var filename: String {
        return entry.name
    }

    var contentType: UTType {
        switch entry.kind {
        case .file:
            let ext = (entry.name as NSString).pathExtension
            if ext.isEmpty {
                return .data
            }
            return UTType(tag: ext,
                          tagClass: .filenameExtension,
                          conformingTo: nil) ?? .data
        case .folder, .host:
            return .folder
        case .symlink:
            return .symbolicLink
        }
    }

    var fileSystemFlags: NSFileProviderFileSystemFlags {
        switch entry.kind {
        case .file, .folder, .symlink:
            var result = NSFileProviderFileSystemFlags()
            if entry.permissions?.r ?? true {
                result.insert(NSFileProviderFileSystemFlags.userReadable)
            }
            if entry.permissions?.w ?? false {
                result.insert(NSFileProviderFileSystemFlags.userWritable)
            }
            if entry.permissions?.x ?? (entry.kind == .folder) {
                result.insert(NSFileProviderFileSystemFlags.userExecutable)
            }
            return result
        case .host:
            return [.userReadable, .userExecutable]
        }
    }

    var documentSize: NSNumber? {
        switch entry.kind {
        case .host, .folder, .symlink:
            return nil
        case .file(let info):
            return info.size as NSNumber?
        }
    }

    var creationDate: Date? {
        return entry.ctime
    }

    var contentModificationDate: Date? {
        return entry.mtime
    }

    var symlinkTargetPath: String? {
        switch entry.kind {
        case .symlink(let target):
            return target
        default:
            return  nil
        }
    }

    // TODO: Support isUploaded, isUploading, uploadingError, isDownloaded, isDownloading, downloadingError
}
