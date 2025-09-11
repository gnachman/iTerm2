//
//  Conductor+ConductorFileTransferDelegate.swift
//  iTerm2
//
//  Created by George Nachman on 7/1/25.
//


@available(macOS 11.0, *)
@MainActor
extension Conductor: ConductorFileTransferDelegate {
    func beginDownload(fileTransfer: ConductorFileTransfer) {
        guard let path = fileTransfer.localPath() else {
            fileTransfer.fail(reason: "No local path specified")
            return
        }
        let remotePath = fileTransfer.path.path!

        FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
        guard let fileHandle = FileHandle(forUpdatingAtPath: path) else {
            fileTransfer.fail(reason: "Could not open \(path)")
            return
        }
        Task {
            await reallyBeginDownload(fileTransfer: fileTransfer,
                                      remotePath: remotePath,
                                      fileHandle: fileHandle,
                                      allowDirectories: true)
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

    @MainActor
    private func reallyBeginDownload(fileTransfer: ConductorFileTransfer,
                                     remotePath: String,
                                     fileHandle: FileHandle,
                                     allowDirectories: Bool) async {
        do {
            let info = try await stat(remotePath)
            if info.kind == .folder {
                if !allowDirectories {
                    fileTransfer.fail(reason: "Transfer of directory at \(remotePath) not allowed")
                }
                await reallyDownloadFolder(info: info,
                                           fileTransfer: fileTransfer,
                                           remotePath: remotePath,
                                           fileHandle: fileHandle)
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
            defer {
                try? fileHandle.close()
            }
            while !done {
                if fileTransfer.isStopped {
                    fileTransfer.abort()
                    return
                }
                let chunk = DownloadChunk(offset: offset, size: chunkSize)
                let data = try await download(remotePath, chunk: chunk, uniqueID: nil)
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
            fileTransfer.didFinishSuccessfully()
        } catch {
            fileTransfer.fail(reason: error.localizedDescription)
        }
    }

    @MainActor
    func downloadChunked(remoteFile: RemoteFile,
                         progress: Progress?,
                         cancellation: Cancellation?,
                         destination: URL) async throws -> DownloadType {
        DLog("Download of \(remoteFile.absolutePath) requested")
        await Conductor.downloadSemaphore.wait()
        DLog("Download of \(remoteFile.absolutePath) beginning")
        defer {
            Task {
                DLog("Download of \(remoteFile.absolutePath) completely finished")
                await Conductor.downloadSemaphore.signal()
            }
        }
        if remoteFile.kind.isFolder {
            let remoteZipPath = try await zip(remoteFile.absolutePath)
            do {
                let zipRemoteFile = try await stat(remoteZipPath)
                let localZipPath = destination.appendingPathExtension("zip")
                _ = try await downloadChunked(
                    remoteFile: zipRemoteFile,
                    progress: progress,
                    cancellation: cancellation,
                    destination: localZipPath)

                // The `destination` argument is the current directory in which unzip is run. I give
                // -d path in args so it will create destination.path if needed and then
                // unzip therein.
                try await iTermCommandRunner.unzipURL(
                    localZipPath,
                    withArguments: ["-q", "-o", "-d", destination.path],
                    destination: "/",
                    callbackQueue: .main)
                try? await rm(remoteZipPath, recursive: false)
                try? FileManager.default.removeItem(at: localZipPath)
            } catch {
                try? await rm(remoteZipPath, recursive: false)
                throw error
            }
            return .directory
        }

        it_assert(remoteFile.kind.isRegularFile, "Only files can be downloaded")

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
        while state.shouldFetchMore {
            try await state.addTask(conductor: self)
        }
        if let cancellation, cancellation.canceled {
            DLog("Download of \(remoteFile.absolutePath) throwing")
            throw SSHEndpointException.transferCanceled
        }
        DLog("Download of \(remoteFile.absolutePath) finished normally")
        try state.content.write(to: destination)
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
                        throw ConductorFileTransfer.ConductorFileTransferError("Canceled")
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
                        "Download ended prematurely (received \(content.count) of \(remoteFile.size!) byte\(remoteFile.size! == 1 ? "" : "s")")
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

    @MainActor
    private func reallyDownloadFolder(info: RemoteFile,
                                      fileTransfer: ConductorFileTransfer,
                                      remotePath: String,
                                      fileHandle: FileHandle) async {
        do {
            let remoteZipPath = try await zip(remotePath)
            fileTransfer.isZipOfFolder = true
            await reallyBeginDownload(fileTransfer: fileTransfer,
                                      remotePath: remoteZipPath,
                                      fileHandle: fileHandle,
                                      allowDirectories: false)
            try? await rm(remoteZipPath, recursive: false)
        } catch {
            fileTransfer.fail(reason: error.localizedDescription)
        }
    }

    func beginUpload(fileTransfer: ConductorFileTransfer) {
        if let data = fileTransfer.data {
            Task {
                await reallyBeginUpload(fileTransfer: fileTransfer, of: .right(data))
            }
            return
        }
        guard let path = fileTransfer.localPath() else {
            fileTransfer.fail(reason: "No local filename specified")
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
        do {
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
            var offset = 0
            while offset < data.count {
                if fileTransfer.isStopped {
                    fileTransfer.abort()
                    return
                }
                let maxChunkSize = 1024
                let chunk = data.subdata(in: offset..<min(data.count, offset + maxChunkSize))
                offset += chunk.count
                try await append(tempfile, content: chunk)
                fileTransfer.didTransferBytes(UInt(chunk.count))
            }
            // Find a good name
            var proposedName = fileTransfer.path.path!
            var remoteName: String?
            for i in 0..<100 {
                let info = try? await stat(proposedName)
                if info == nil {
                    remoteName = proposedName
                    break
                }
                proposedName = fileTransfer.path.path + " (\(i + 2))"
            }
            guard let remoteName else {
                throw ConductorFileTransfer.ConductorFileTransferError("Too many iterations to find a valid file name on remote host for upload")
            }
            fileTransfer.remoteName = remoteName
            // Rename the tempfile to the proper name
            _ = try await mv(
                tempfile,
                newParent: remoteName.deletingLastPathComponent,
                newName: remoteName.lastPathComponent)
            fileTransfer.didFinishSuccessfully()
        } catch {
            // Delete the temp file
            try? await rm(tempfile, recursive: false)
            fileTransfer.fail(reason: error.localizedDescription)
        }
    }
}
