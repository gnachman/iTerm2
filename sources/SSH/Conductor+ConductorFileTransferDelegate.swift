//
//  Conductor+ConductorFileTransferDelegate.swift
//  iTerm2
//
//  Created by George Nachman on 7/1/25.
//


@MainActor
extension Conductor: ConductorFileTransferDelegate {
    func beginDownload(fileTransfer: ConductorFileTransfer) {
        let operations = ConductorDownloadOperations(
            stat: { path in try await self.stat(path) },
            zip: { path in try await self.zip(path) },
            fetch: { path, chunk in try await self.download(path, chunk: chunk, uniqueID: nil) },
            rm: { path in try await self.rm(path, recursive: false) })
        Task {
            await ConductorDownload.run(fileTransfer: fileTransfer, operations: operations)
        }
    }

    @MainActor
    func stream(remotePath: String) -> AsyncThrowingStream<Data, Error> {
        return AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    try await yieldChunks(remotePath: remotePath,
                                          continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                producer.cancel()
            }
        }
    }

    private func yieldChunks(remotePath: String,
                             continuation: AsyncThrowingStream<Data, any Error>.Continuation) async throws {
        let info = try await stat(remotePath)
        if info.kind == .folder {
            continuation.finish(
                throwing: ConductorFileTransfer.ConductorFileTransferError(
                    "Streaming downloads do not support folders"))
            return
        }
        var done = false
        var offset = 0

        let chunkSize = 1024
        while !done {
            let chunk = DownloadChunk(offset: offset, size: chunkSize)
            let data = try await download(remotePath, chunk: chunk, uniqueID: nil)
            if data.isEmpty {
                done = true
            } else {
                continuation.yield(data)
                offset += data.count
            }
        }
        continuation.finish()
    }

    enum DownloadOrViewChoice {
        case download
        case ask
    }

    /// Whether to ask the user to download or view a file that could be shown in the
    /// browser. A folder is downloaded. So is a file that can't be examined: the download
    /// fails and reports why (such as a name in older output whose path was built from a
    /// different working directory), rather than nothing happening (F-960).
    static func downloadOrViewChoice(path: String,
                                     stat: (String) async throws -> RemoteFile) async -> DownloadOrViewChoice {
        do {
            let info = try await stat(path)
            return info.kind.isFolder ? .download : .ask
        } catch {
            iTerm2SharedARC.DLog("stat \(path) failed with \(error); download it so the failure is reported")
            return .download
        }
    }

    // The remote zip command's archive holds the folder itself (`folderName/…`), which is what a
    // download saved as a .zip file needs. Here the folder's contents go directly in
    // `destination`, which is the folder, so it isn't nested one level too deep (F-921). Items
    // already in `destination` with the same name are replaced and others are kept.
    static func unzipFolderArchive(_ zipURL: URL,
                                   folderName: String,
                                   to destination: URL) async throws {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".iTerm2.\(UUID().uuidString)")
        defer {
            try? fileManager.removeItem(at: staging)
        }
        // unzip creates the -d folder but not its parent. The `destination` argument is just
        // the directory it runs in.
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        // The framer adds only files, so an empty folder's archive has no entries: just its
        // 22-byte end of central directory record. unzip fails on that.
        let emptyArchiveSize = 22
        let endOfCentralDirectorySignature = Data([0x50, 0x4b, 0x05, 0x06])
        if let size = (try? fileManager.attributesOfItem(atPath: zipURL.path))?[.size] as? Int,
           size == emptyArchiveSize,
           let contents = try? Data(contentsOf: zipURL),
           contents.starts(with: endOfCentralDirectorySignature) {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            return
        }
        try await iTermCommandRunner.unzipURL(
            zipURL,
            withArguments: ["-q", "-o", "-d", staging.path],
            destination: "/",
            callbackQueue: .main)
        let unzippedFolder = staging.appendingPathComponent(folderName)
        var isDirectory = ObjCBool(false)
        let foundFolder = fileManager.fileExists(atPath: unzippedFolder.path,
                                                 isDirectory: &isDirectory) && isDirectory.boolValue
        // Only when the archive's folder isn't named `folderName`, which shouldn't happen.
        let source = foundFolder ? unzippedFolder : staging
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in try fileManager.contentsOfDirectory(atPath: source.path) {
            let target = destination.appendingPathComponent(name)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: source.appendingPathComponent(name), to: target)
        }
    }

    @MainActor
    func downloadChunked(remoteFile: RemoteFile,
                         progress: Progress?,
                         cancellation: Cancellation?,
                         destination: URL) async throws -> DownloadType {
        return try await downloadChunked(remoteFile: remoteFile,
                                         progress: progress,
                                         cancellation: cancellation,
                                         destination: destination,
                                         completionNote: nil)
    }

    // `completionNote` is shown with the finished notification, such as what a folder's
    // archive left out (F-721).
    @MainActor
    private func downloadChunked(remoteFile: RemoteFile,
                                 progress: Progress?,
                                 cancellation: Cancellation?,
                                 destination: URL,
                                 completionNote: String?) async throws -> DownloadType {
        RLog("Download of \(remoteFile.absolutePath) requested")
        await Conductor.downloadSemaphore.wait()
        RLog("Download of \(remoteFile.absolutePath) beginning")
        defer {
            Task {
                RLog("Download of \(remoteFile.absolutePath) completely finished")
                await Conductor.downloadSemaphore.signal()
            }
        }
        if remoteFile.kind.isFolder {
            let zipReply = try await zip(remoteFile.absolutePath)
            let remoteZipPath = zipReply.path
            do {
                let zipRemoteFile = try await stat(remoteZipPath)
                let localZipPath = destination.appendingPathExtension("zip")
                _ = try await downloadChunked(
                    remoteFile: zipRemoteFile,
                    progress: progress,
                    cancellation: cancellation,
                    destination: localZipPath,
                    completionNote: zipReply.skippedItemsNote)

                try await Self.unzipFolderArchive(localZipPath,
                                                  folderName: remoteFile.absolutePath.lastPathComponent,
                                                  to: destination)
                try? await rm(remoteZipPath, recursive: false)
                try? FileManager.default.removeItem(at: localZipPath)
            } catch {
                try? await rm(remoteZipPath, recursive: false)
                throw error
            }
            return .directory
        }

        guard remoteFile.kind.isRegularFile else {
            throw ConductorFileTransfer.ConductorFileTransferError(
                String(localized: "ConductorFileTransfer.NotRegularFile",
                       defaultValue: "“\(remoteFile.absolutePath)” on \(sshIdentity.displayName) is not a regular file.",
                       comment: "Error shown when an SSH Integration download is not a regular file; the first argument is the remote path and the second is the host"))
        }

        let scpPath = SCPPath()
        scpPath.path = remoteFile.absolutePath
        scpPath.hostname = sshIdentity.hostname
        scpPath.username = sshIdentity.username
        let fileTransfer = ConductorFileTransfer(path: scpPath,
                                                 localPath: nil,
                                                 data: nil,
                                                 delegate: self)
        if let size = remoteFile.size {
            fileTransfer.fileSize = size
        }
        if !fileTransfer.downloadChunked() {
            return .file
        }

        let chunkSize = 4096
        progress?.fraction = 0
        let state = DownloadState(remoteFile: remoteFile,
                                  chunkSize: chunkSize,
                                  cancellation: cancellation,
                                  progress: progress,
                                  fileTransfer: fileTransfer,
                                  conductor: self)
        do {
            while state.shouldFetchMore {
                try await state.addTask(conductor: self)
            }
            if let cancellation, cancellation.canceled {
                RLog("Download of \(remoteFile.absolutePath) throwing")
                throw SSHEndpointException.transferCanceled
            }
            RLog("Download of \(remoteFile.absolutePath) finished normally")
            try state.content.write(to: destination)
        } catch {
            // The Downloads menu lists the transfer until it is told how it ended (F-714). A
            // canceled one was already told it stopped; one stopped from the menu is told now.
            if fileTransfer.isStopped {
                if cancellation?.canceled != true {
                    fileTransfer.abort()
                }
            } else if cancellation?.canceled != true {
                fileTransfer.fail(reason: SSHEndpointException.transferFailureReason(for: error, isDownload: true))
            }
            throw error
        }
        fileTransfer.completionNote = completionNote
        fileTransfer.didFinishChunkedDownload(to: destination)
        return .file
    }

    @MainActor
    class DownloadState {
        var remoteFile: RemoteFile
        var offset = 0
        var chunkSize: Int
        var counter = PerformanceCounter<DownloadOp>()
        var cancellation: Cancellation?
        var progress: Progress?
        var content = Data()
        var fileTransfer: ConductorFileTransfer

        private struct Pending {
            var uniqueID: String
            var offset: Int
            var task: Task<Data, Error>
        }
        private var tasks = [Pending]()

        init(remoteFile: RemoteFile,
             chunkSize: Int,
             cancellation: Cancellation?,
             progress: Progress?,
             fileTransfer: ConductorFileTransfer,
             conductor: Conductor) {
            self.remoteFile = remoteFile
            self.chunkSize = chunkSize
            self.cancellation = cancellation
            self.progress = progress
            self.fileTransfer = fileTransfer

            cancellation?.impl = { [weak self, weak conductor] in
                conductor?.DLog("Cancellation requested")
                Task { @MainActor in
                    self?.fileTransfer.abort()
                    guard let self, let conductor else {
                        conductor?.DLog("Already dealloced")
                        return
                    }
                    for pending in self.tasks {
                        try? await conductor.cancelDownload(uniqueID: pending.uniqueID)
                    }
                }
            }
        }

        var shouldFetchMore: Bool {
            if cancellation?.canceled == true {
                return false
            }
            return offset < remoteFile.size!
        }

        func addTask(conductor: Conductor) async throws {
            let taskOffset = offset
            offset += chunkSize
            let uniqueID = UUID().uuidString
            let pending = Pending(
                uniqueID: uniqueID,
                offset: taskOffset,
                task: Task { @MainActor in
                    if fileTransfer.isStopped {
                        throw SSHEndpointException.transferCanceled
                    }
                    let data = try await conductor.downloadOneChunk(
                        remoteFile: remoteFile,
                        offset: taskOffset,
                        chunkSize: chunkSize,
                        uniqueID: uniqueID,
                        counter: counter)
                    counter.perform(.post) {
                        if data.isEmpty {
                            progress?.fraction = 1.0
                        } else {
                            progress?.fraction = min(1.0, max(0, Double(offset) / Double(remoteFile.size!)))
                        }
                        fileTransfer.didTransferBytes(UInt(data.count))
                    }
                    return data
                })
            tasks.append(pending)
            let maxConcurrency = 8
            while tasks.count >= maxConcurrency || (!tasks.isEmpty && !shouldFetchMore) {
                if fileTransfer.isStopped {
                    cancellation?.cancel()
                }
                if cancellation?.canceled == true {
                    break
                }
                let result = try await tasks.removeFirst().task.value
                content.append(result)
                if result.isEmpty && !tasks.isEmpty {
                    throw ConductorFileTransfer.ConductorFileTransferError(
                        String(localized: "Conductor.DownloadEndedPrematurely", defaultValue: "Download ended prematurely (received \(content.count) of \(remoteFile.size!) bytes)", comment: "Download error; first placeholder is the number of bytes received, second is the total size in bytes"))
                }
            }
        }
    }

    @MainActor
    private func downloadOneChunk(remoteFile: RemoteFile,
                                  offset: Int,
                                  chunkSize: Int,
                                  uniqueID: String,
                                  counter: PerformanceCounter<DownloadOp>) async throws -> Data {
        let poc = counter.start([.queued, .sent, .transferring])
        let chunk = DownloadChunk(offset: offset,
                                  size: chunkSize,
                                  performanceOperationCounter: poc)

        DLog("Send request to download from offset \(offset)")
        let data = try await download(remoteFile.absolutePath,
                                      chunk: chunk,
                                      uniqueID: uniqueID)
        DLog("Finished request to download from offset \(offset)")
        poc.complete(.transferring)

        // counter.log()
        return data
    }

    func beginUpload(fileTransfer: ConductorFileTransfer) {
        if let data = fileTransfer.data {
            Task {
                await reallyBeginUpload(fileTransfer: fileTransfer, of: .right(data))
            }
            return
        }
        guard let path = fileTransfer.localPath() else {
            fileTransfer.fail(reason: String(localized: "ConductorFileTransfer.NoLocalFile",
                                              defaultValue: "No file was chosen to upload.",
                                              comment: "Error shown when an SSH Integration upload has no local file"))
            return
        }
        Task {
            await reallyBeginUpload(fileTransfer: fileTransfer,
                                    of: .left(path))
        }
    }

    @MainActor
    private func reallyBeginUpload(fileTransfer: ConductorFileTransfer,
                                   of choice: Either<String, Data>) async {
        let tempfile = fileTransfer.path.path + ".uploading-\(UUID().uuidString)"
        var renamedPath: String?
        func checkCancellation() throws {
            if fileTransfer.isStopped {
                throw CancellationError()
            }
        }
        do {
            try checkCancellation()
            let data = try choice.handle { path in
                let fileURL = URL(fileURLWithPath: path)
                return try Data(contentsOf: fileURL)
            } right: { data in
                data
            }
            // Make an empty file and then upload chunks so we don't monopolize the connection.
            try await create(tempfile,
                             content: Data())
            fileTransfer.fileSize = data.count
            try await ConductorUpload.send(data, checkCancellation: checkCancellation) { chunk in
                try await self.append(tempfile, content: chunk)
            } didTransfer: { count in
                fileTransfer.didTransferBytes(UInt(count))
            }
            // Find a good name. The claim keeps a concurrent upload of a file with the same name
            // from choosing it too; it is released once the rename has put the file there.
            let remoteName = try await uploadNameReservations.reserve(base: fileTransfer.path.path!) { proposedName in
                // A failed check must not read as “free”: that would overwrite an existing file.
                let exists = try await ConductorUpload.remotePathExists(proposedName) { path in
                    _ = try await self.stat(path)
                }
                try checkCancellation()
                return exists
            }
            guard let remoteName else {
                throw ConductorFileTransfer.ConductorFileTransferError(
                    String(localized: "ConductorFileTransfer.NoFreeRemoteName",
                           defaultValue: "Could not find an unused file name on the remote host for the upload.",
                           comment: "Error shown when an SSH Integration upload cannot find a file name that is not already taken on the remote host"))
            }
            defer {
                uploadNameReservations.release(remoteName)
            }
            fileTransfer.remoteName = remoteName
            // Rename the tempfile to the proper name
            _ = try await mv(
                tempfile,
                newParent: remoteName.deletingLastPathComponent,
                newName: remoteName.lastPathComponent)
            renamedPath = remoteName
            try checkCancellation()
            fileTransfer.didFinishSuccessfully()
        } catch {
            // Delete the temp file
            try? await rm(tempfile, recursive: false)
            if fileTransfer.isStopped {
                if let renamedPath {
                    try? await rm(renamedPath, recursive: false)
                }
                fileTransfer.abort()
            } else {
                fileTransfer.fail(reason: SSHEndpointException.transferFailureReason(for: error, isDownload: false))
            }
        }
    }
}
