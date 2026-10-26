//
//  ConductorDownload.swift
//  iTerm2
//
//  Created by George Nachman on 10/26/26.
//

import Foundation

/// The remote file operations a download needs. Conductor supplies the real ones and tests
/// supply fakes.
@MainActor
struct ConductorDownloadOperations {
    var stat: (String) async throws -> RemoteFile
    var zip: (String) async throws -> SSHRemoteZipReply
    var fetch: (String, DownloadChunk) async throws -> Data
    var rm: (String) async throws -> Void
}

/// A download started with ConductorFileTransfer.download(), such as from “Download using
/// SSH Integration” in the context menu. It is saved to a hidden file in the Downloads folder,
/// which is renamed when the download finishes. A folder is zipped on the remote host and the
/// archive is downloaded.
@MainActor
enum ConductorDownload {
    static func run(fileTransfer: ConductorFileTransfer,
                    operations: ConductorDownloadOperations) async {
        guard let path = fileTransfer.localPath() else {
            fileTransfer.fail(reason: String(localized: "ConductorFileTransfer.NoLocalPath",
                                              defaultValue: "There is no local file to save the download to.",
                                              comment: "Error shown when an SSH Integration download has no local file to save to"))
            return
        }
        let remotePath = fileTransfer.path.path!

        FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
        guard let fileHandle = FileHandle(forUpdatingAtPath: path) else {
            fileTransfer.fail(reason: String(localized: "ConductorFileTransfer.CouldNotOpen",
                                              defaultValue: "Could not open “\(path)” for writing.",
                                              comment: "Error shown when the local file for an SSH Integration download cannot be opened; the argument is its path"))
            return
        }
        defer {
            try? fileHandle.close()
        }
        await download(fileTransfer: fileTransfer,
                       remotePath: remotePath,
                       fileHandle: fileHandle,
                       allowDirectories: true,
                       operations: operations)
    }

    private static func download(fileTransfer: ConductorFileTransfer,
                                 remotePath: String,
                                 fileHandle: FileHandle,
                                 allowDirectories: Bool,
                                 operations: ConductorDownloadOperations) async {
        do {
            let info = try await operations.stat(remotePath)
            if info.kind == .folder {
                if !allowDirectories {
                    fileTransfer.fail(reason: String(localized: "ConductorFileTransfer.FolderNotAllowed",
                                                      defaultValue: "“\(remotePath)” is a folder and can’t be downloaded here.",
                                                      comment: "Error shown when an SSH Integration download unexpectedly names a folder; the argument is the remote path"))
                    return
                }
                await downloadFolder(fileTransfer: fileTransfer,
                                     remotePath: remotePath,
                                     fileHandle: fileHandle,
                                     operations: operations)
                return
            }
            let sizeKnown: Bool
            if let size = info.size {
                sizeKnown = true
                fileTransfer.fileSize = size
            } else {
                sizeKnown = false
            }
            var done = false
            var offset = 0

            let chunkSize = 1024
            while !done {
                if fileTransfer.isStopped {
                    fileTransfer.abort()
                    return
                }
                let chunk = DownloadChunk(offset: offset, size: chunkSize)
                let data = try await operations.fetch(remotePath, chunk)
                if data.isEmpty {
                    done = true
                } else {
                    try fileHandle.write(contentsOf: data)
                    if !sizeKnown {
                        fileTransfer.fileSize = fileTransfer.fileSize + data.count
                    }
                    fileTransfer.didTransferBytes(UInt(data.count))
                    offset += data.count
                }
            }
            // It may have been stopped during the last request.
            if fileTransfer.isStopped {
                fileTransfer.abort()
                return
            }
            fileTransfer.didFinishSuccessfully()
        } catch {
            fileTransfer.fail(reason: SSHEndpointException.transferFailureReason(for: error, isDownload: true))
        }
    }

    private static func downloadFolder(fileTransfer: ConductorFileTransfer,
                                       remotePath: String,
                                       fileHandle: FileHandle,
                                       operations: ConductorDownloadOperations) async {
        do {
            let zipReply = try await operations.zip(remotePath)
            let remoteZipPath = zipReply.path
            fileTransfer.isZipOfFolder = true
            // Finish, but say what couldn't be read and was left out (F-721).
            fileTransfer.completionNote = zipReply.skippedItemsNote
            await download(fileTransfer: fileTransfer,
                           remotePath: remoteZipPath,
                           fileHandle: fileHandle,
                           allowDirectories: false,
                           operations: operations)
            try? await operations.rm(remoteZipPath)
        } catch {
            // Only zip() throws here. Its permission errors come from making the archive in the
            // remote home folder or from listing the folder itself, not from reading a file, so
            // they get the generic reason.
            fileTransfer.fail(reason: error.localizedDescription)
        }
    }
}
