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
    // Shared with a download through the file panel (Conductor.downloadChunked). Each
    // request is small so terminal input can be serviced between replies, and several are
    // in flight so the speed doesn't depend on one round trip per chunk (F-725).
    static let chunkSize = 4096
    static let maxRequestsInFlight = 8

    /// Reads a remote file from the start, `chunkSize` bytes per request with up to
    /// `maxRequestsInFlight` requests outstanding, and passes the data to `consume` in order.
    /// The file ends at the first reply that is empty or shorter than a chunk.
    /// `expectedSize` is how big it was when examined, if known; a file that has grown
    /// since is still read to its end. Returns false if it stopped because `isStopped`
    /// became true.
    static func fetch(expectedSize: Int?,
                      isStopped: () -> Bool,
                      fetch: @escaping (DownloadChunk) async throws -> Data,
                      consume: (Data) throws -> Void) async throws -> Bool {
        var pending = [Task<Data, Error>]()
        defer {
            // Replies still on the way after it ends or fails aren't needed. This only marks
            // the tasks canceled: their requests have already been sent and are answered anyway.
            for task in pending {
                task.cancel()
            }
        }
        var nextOffset = 0
        var received = 0
        func mayRequestMore() -> Bool {
            guard let expectedSize else {
                return true
            }
            // Requesting the chunk at the expected end lets a file that grew be noticed.
            return nextOffset <= max(expectedSize, received)
        }
        while true {
            if isStopped() {
                return false
            }
            while pending.count < maxRequestsInFlight && mayRequestMore() {
                let chunk = DownloadChunk(offset: nextOffset, size: chunkSize)
                nextOffset += chunkSize
                pending.append(Task { @MainActor in
                    try await fetch(chunk)
                })
            }
            guard !pending.isEmpty else {
                return true
            }
            let data = try await pending.removeFirst().value
            if isStopped() {
                return false
            }
            if data.isEmpty {
                return true
            }
            try consume(data)
            received += data.count
            if data.count < chunkSize {
                return true
            }
        }
    }

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
            let finished = try await fetch(expectedSize: info.size,
                                           isStopped: { fileTransfer.isStopped },
                                           fetch: { chunk in
                try await operations.fetch(remotePath, chunk)
            }, consume: { data in
                try fileHandle.write(contentsOf: data)
                if !sizeKnown {
                    fileTransfer.fileSize = fileTransfer.fileSize + data.count
                }
                fileTransfer.didTransferBytes(UInt(data.count))
            })
            // It may have been stopped during the last request.
            if !finished || fileTransfer.isStopped {
                fileTransfer.abort()
                return
            }
            fileTransfer.didFinishSuccessfully()
        } catch {
            if fileTransfer.isStopped {
                // Stopped while a request was outstanding. That's not a failure.
                fileTransfer.abort()
            } else {
                fileTransfer.fail(reason: SSHEndpointException.transferFailureReason(for: error, isDownload: true))
            }
        }
    }

    private static func downloadFolder(fileTransfer: ConductorFileTransfer,
                                       remotePath: String,
                                       fileHandle: FileHandle,
                                       operations: ConductorDownloadOperations) async {
        do {
            // Zipping a big folder can take a while, so don't start if it was stopped already.
            if fileTransfer.isStopped {
                fileTransfer.abort()
                return
            }
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
            if fileTransfer.isStopped {
                fileTransfer.abort()
                return
            }
            // Only zip() throws here. Its permission errors come from making the archive in the
            // remote home folder or from listing the folder itself, not from reading a file, so
            // they get the generic reason.
            fileTransfer.fail(reason: error.localizedDescription)
        }
    }
}
