//
//  LocalhostEndpoint.swift
//  iTerm2
//
//  Created by George Nachman on 6/5/25.
//

import Foundation

@available(macOS 11.0, *)
class LocalhostEndpoint: SSHEndpoint {
    static let instance = LocalhostEndpoint()
    let sshIdentity: SSHIdentity = .localhost
    let homeDirectory: String? = NSHomeDirectory()

    private let fileManager = FileManager.default

    func listFiles(_ path: String, sort: FileSorting) async throws -> [RemoteFile] {
        let directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        let contents = try fileManager
            .contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .creationDateKey,
                    .isSymbolicLinkKey
                ],
                options: []
            )
        var entries: [RemoteFile] = []

        // Parent permissions
        let parentAttributes = try fileManager.attributesOfItem(atPath: directoryURL.path)
        let parentPermsInt = (parentAttributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let parentPermissions = RemoteFile.Permissions(
            r: (parentPermsInt & Int(S_IRUSR)) != 0,
            w: (parentPermsInt & Int(S_IWUSR)) != 0,
            x: (parentPermsInt & Int(S_IXUSR)) != 0
        )

        for fileURL in contents {
            let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
            let fileType = attrs[.type] as? FileAttributeType
            let isDirectory = fileType == .typeDirectory
            let isSymlink = fileType == .typeSymbolicLink

            // Size and timestamps
            let fileSize = (attrs[.size] as? NSNumber)?.intValue
            let mtime = attrs[.modificationDate] as? Date
            let ctime = attrs[.creationDate] as? Date

            // Permissions
            let permsInt = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
            let permissions = RemoteFile.Permissions(
                r: (permsInt & Int(S_IRUSR)) != 0,
                w: (permsInt & Int(S_IWUSR)) != 0,
                x: (permsInt & Int(S_IXUSR)) != 0
            )

            // Kind
            let kind: RemoteFile.Kind
            if isSymlink {
                let target = try fileManager.destinationOfSymbolicLink(atPath: fileURL.path)
                kind = .symlink(target)
            } else if isDirectory {
                kind = .folder
            } else {
                kind = .file(.init(size: fileSize))
            }

            let entry = RemoteFile(
                kind: kind,
                absolutePath: fileURL.path,
                permissions: permissions,
                parentPermissions: parentPermissions,
                ctime: ctime,
                mtime: mtime
            )
            entries.append(entry)
        }

        return entries.sorted { lhs, rhs in
            RemoteFile.lessThan(lhs, rhs, sort: sort)
        }
    }

    func cancelDownload(uniqueID: String) async throws {
    }

    func downloadChunked(remoteFile: RemoteFile,
                         progress: Progress?,
                         cancellation: Cancellation?,
                         destination: URL) async throws -> DownloadType {
        if remoteFile.kind.isFolder {
            try FileManager.default.createDirectory(at: destination,
                                                    withIntermediateDirectories: true)
            try FileManager.default.deepCopyContentsOfDirectory(
                source: URL(fileURLWithPath: remoteFile.absolutePath),
                to: destination,
                excluding: Set())
            return .directory
        }
        it_assert(remoteFile.kind.isRegularFile, "Only files can be downloaded")
        progress?.fraction = 0
        if let cancellation, cancellation.canceled {
            throw SSHEndpointException.transferCanceled
        }
        try FileManager.default.copyItem(at: URL(fileURLWithPath: remoteFile.absolutePath),
                                         to: destination)
        progress?.fraction = 1.0
        if let cancellation, cancellation.canceled {
            throw SSHEndpointException.transferCanceled
        }
        return .file
    }

    func download(_ path: String, chunk: DownloadChunk?, uniqueID uniqueIdentifier: String?) async throws -> Data {
        let fileURL = URL(fileURLWithPath: path)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        if let chunk = chunk {
            try handle.seek(toOffset: UInt64(chunk.offset))
            return try handle.read(upToCount: chunk.size) ?? Data()
        } else {
            return try Data(contentsOf: fileURL)
        }
    }

    func stat(_ path: String) async throws -> RemoteFile {
        let fileURL = URL(fileURLWithPath: path)
        let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
        let fileType = attrs[.type] as? FileAttributeType
        let isDirectory = fileType == .typeDirectory
        let isSymlink = fileType == .typeSymbolicLink

        let fileSize = (attrs[.size] as? NSNumber)?.intValue
        let mtime = attrs[.modificationDate] as? Date
        let ctime = attrs[.creationDate] as? Date

        let permsInt = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let permissions = RemoteFile.Permissions(
            r: (permsInt & Int(S_IRUSR)) != 0,
            w: (permsInt & Int(S_IWUSR)) != 0,
            x: (permsInt & Int(S_IXUSR)) != 0
        )

        // Parent permissions
        let parentPath = (path as NSString).deletingLastPathComponent
        let parentAttrs = try fileManager.attributesOfItem(atPath: parentPath)
        let parentPermsInt = (parentAttrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let parentPermissions = RemoteFile.Permissions(
            r: (parentPermsInt & Int(S_IRUSR)) != 0,
            w: (parentPermsInt & Int(S_IWUSR)) != 0,
            x: (parentPermsInt & Int(S_IXUSR)) != 0
        )

        let kind: RemoteFile.Kind
        if isSymlink {
            let target = try fileManager.destinationOfSymbolicLink(atPath: fileURL.path)
            kind = .symlink(target)
        } else if isDirectory {
            kind = .folder
        } else {
            kind = .file(.init(size: fileSize))
        }

        return RemoteFile(
            kind: kind,
            absolutePath: fileURL.path,
            permissions: permissions,
            parentPermissions: parentPermissions,
            ctime: ctime,
            mtime: mtime
        )
    }

    func delete(_ path: String, recursive: Bool) async throws {
        let fullPath = URL(fileURLWithPath: path).path
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) {
            if isDir.boolValue {
                if !recursive {
                    let contents = try fileManager.contentsOfDirectory(atPath: fullPath)
                    if !contents.isEmpty {
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTEMPTY), userInfo: nil)
                    }
                }
            }
            try fileManager.removeItem(atPath: fullPath)
        } else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT), userInfo: nil)
        }
    }

    func ln(_ source: String, _ symlink: String) async throws -> RemoteFile {
        let srcURL = URL(fileURLWithPath: source)
        let linkURL = URL(fileURLWithPath: symlink)
        try fileManager.createSymbolicLink(atPath: linkURL.path, withDestinationPath: srcURL.path)
        return try await stat(symlink)
    }

    func mv(_ file: String, newParent: String, newName: String) async throws -> RemoteFile {
        let srcURL = URL(fileURLWithPath: file)
        let destDirURL = URL(fileURLWithPath: newParent, isDirectory: true)
        let destURL = destDirURL.appendingPathComponent(newName)
        try fileManager.moveItem(at: srcURL, to: destURL)
        return try await stat(destURL.path)
    }

    func mkdir(_ file: String) async throws {
        let dirURL = URL(fileURLWithPath: file, isDirectory: true)
        try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: false, attributes: nil)
    }

    func create(_ file: String, content: Data) async throws {
        let fileURL = URL(fileURLWithPath: file)
        let directory = (file as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: directory) {
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
        }
        try content.write(to: fileURL)
    }

    func replace(_ file: String, content: Data) async throws -> RemoteFile {
        let fileURL = URL(fileURLWithPath: file)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        try await create(file, content: content)
        return try await stat(file)
    }

    func setModificationDate(_ file: String, date: Date) async throws -> RemoteFile {
        let attrs: [FileAttributeKey: Any] = [.modificationDate: date]
        try fileManager.setAttributes(attrs, ofItemAtPath: file)
        return try await stat(file)
    }

    func chmod(_ file: String, permissions: RemoteFile.Permissions) async throws -> RemoteFile {
        var rawMode = 0
        if permissions.r {
            rawMode |= Int(S_IRUSR)
        }
        if permissions.w {
            rawMode |= Int(S_IWUSR)
        }
        if permissions.x {
            rawMode |= Int(S_IXUSR)
        }
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: rawMode)], ofItemAtPath: file)
        return try await stat(file)
    }
}
