//
//  Conductor+SSHEndpoint.swift
//  iTerm2
//
//  Created by George Nachman on 7/1/25.
//


@available(macOS 11.0, *)
extension Conductor: SSHEndpoint {
    @MainActor
    func performFileOperation(subcommand: FileSubcommand,
                                      highPriority: Bool = false) async throws -> String {
        let (output, code) = await withCheckedContinuation { continuation in
            framerFile(subcommand, highPriority: highPriority) { content, code in
                log("File subcommand \(subcommand) finished with code \(code)")
                continuation.resume(returning: (content, code))
            }
        }
        if code < 0 {
            throw SSHEndpointException.connectionClosed
        }
        if code > 0 {
            throw SSHEndpointException.fileNotFound
        }
        return output
    }

    @objc(fetchDirectoryListingOfPath:queue:completion:)
    @MainActor
    func objcListFiles(_ path: String,
                       queue: DispatchQueue,
                       completion: @escaping ([iTermDirectoryEntry]) -> ()) {
        Task {
            do {
                let files = try await listFiles(path, sort: .byName)
                let entries = files.map {
                    var mode = mode_t(0)
                    switch $0.kind {
                    case .folder:
                        mode |= S_IFDIR
                    default:
                        break
                    }
                    if $0.permissions?.r ?? true {
                        mode |= S_IRUSR
                    }
                    if $0.permissions?.x ?? false {
                        mode |= S_IXUSR
                    }
                    return iTermDirectoryEntry(name: $0.name, mode: mode)
                }
                queue.async {
                    completion(entries)
                }
            } catch {
                DLog("\(error) for \(path)")
                queue.async {
                    completion([])
                }
            }
        }
    }

    @MainActor
    func listFiles(_ path: String, sort: FileSorting) async throws -> [RemoteFile] {
        return try await logging("listFiles")  {
            guard let pathData = path.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(path)
            }
            log("perform file operation to list \(path)")
            let json = try await performFileOperation(subcommand: .ls(path: pathData,
                                                                      sorting: sort))
            log("file operation completed with \(json.count) characters")
            guard let jsonData = json.data(using: .utf8) else {
                throw iTermFileProviderServiceError.internalError("Server returned garbage")
            }
            let decoder = JSONDecoder()
            return try iTermFileProviderServiceError.wrap {
                return try decoder.decode([RemoteFile].self, from: jsonData)
            }
        }
    }

    @MainActor
    func download(_ path: String, chunk: DownloadChunk?, uniqueID: String?) async throws -> Data {
        return try await logging("download \(path) \(String(describing: chunk))") {
            guard let pathData = path.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(path)
            }
            log("perform file operation to download \(path) with uniqueID \(uniqueID.d)")
            let b64: String = try await performFileOperation(subcommand: .fetch(path: pathData,
                                                                                chunk: chunk,
                                                                                uniqueID: uniqueID))
            log("file operation completed with \(b64.count) characters")
            guard let data = Data(base64Encoded: b64) else {
                throw iTermFileProviderServiceError.internalError("Server returned garbage")
            }
            return data
        }
    }

    @MainActor
    func cancelDownload(uniqueID: String) async throws {
        DLog("Want to cancel downloads with unique ID \(uniqueID)")
        cancelEnqueuedRequests { command in
            switch command {
            case .framerFile(let sub):
                switch sub {
                case .fetch(path: let path, chunk: let chunk, uniqueID: uniqueID):
                    DLog("Canceling fetch of \(path) with unique ID \(uniqueID)")
                    chunk?.performanceOperationCounter?.complete(.queued)
                    return true
                default:
                    return false
                }
            default:
                return false
            }
        }
    }

    @MainActor
    func zip(_ path: String) async throws -> String {
        return try await logging("zip \(path)") {
            guard let pathData = path.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(path)
            }
            log("perform file operation to zip \(path)")
            return try await performFileOperation(subcommand: .zip(path: pathData))
        }
    }

    func remoteFile(_ json: String) throws -> RemoteFile {
        log("file operation completed with \(json.count) characters")
        guard let jsonData = json.data(using: .utf8) else {
            throw iTermFileProviderServiceError.internalError("Server returned garbage")
        }
        let decoder = JSONDecoder()
        return try iTermFileProviderServiceError.wrap {
            return try decoder.decode(RemoteFile.self, from: jsonData)
        }
    }

    @objc
    @MainActor
    func stat(_ path: String,
              queue: DispatchQueue,
              completion: @escaping (Int32, UnsafePointer<stat>?) -> ()) {
        Task {
            do {
                let rf = try await stat(path)
                queue.async {
                    var sb = rf.toStat()
                    completion(0, &sb)
                }
            } catch {
                queue.async {
                    completion(1, nil)
                }
            }
        }
    }

    @MainActor
    func stat(_ path: String) async throws -> RemoteFile {
        return try await stat(path, highPriority: false)
    }

    @MainActor
    func stat(_ path: String, highPriority: Bool = false) async throws -> RemoteFile {
        return try await logging("stat \(path)") {
            guard let pathData = path.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(path)
            }
            log("perform file operation to stat \(path)")
            let json = try await performFileOperation(subcommand: .stat(path: pathData),
                                                      highPriority: highPriority)
            let result = try remoteFile(json)
            log("finished")
            return result
        }
    }

    @MainActor
    func suggestions(_ requestInputs: SuggestionRequest.Inputs) async throws -> [String] {
        log("Request suggestions for inputs \(requestInputs)")
        return try await logging("suggestions \(requestInputs)") {
            cancelEnqueuedRequests { request in
                switch request {
                case .framerFile(let sub):
                    switch sub {
                    case .fetchSuggestions:
                        return true
                    default:
                        return false
                    }
                default:
                    return false
                }
            }
            let json = try await performFileOperation(subcommand: .fetchSuggestions(request: requestInputs),
                                                      highPriority: true)
            log("Suggestions for \(requestInputs) are: \(json)")
            guard let data = json.data(using: .utf8) else {
                return []
            }
            return try JSONDecoder().decode([String].self, from: data)
        }
    }

    @MainActor
    func delete(_ path: String, recursive: Bool) async throws {
        try await logging("delete \(path) recursive=\(recursive)") {
            guard let pathData = path.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(path)
            }
            log("perform file operation to delete \(path)")
            _ = try await performFileOperation(subcommand: .rm(path: pathData, recursive: recursive))
            log("finished")
        }
    }

    @MainActor
    func ln(_ source: String, _ symlink: String) async throws -> RemoteFile {
        try await logging("ln -s \(source) \(symlink)") {
            guard let sourceData = source.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(source)
            }
            guard let symlinkData = symlink.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(symlink)
            }
            log("perform file operation to make a symlink")
            let json = try await performFileOperation(subcommand: .ln(source: sourceData,
                                                                      symlink: symlinkData))
            let result = try remoteFile(json)
            log("finished")
            return result
        }
    }

    @MainActor
    func mv(_ source: String, newParent: String, newName: String) async throws -> RemoteFile {
        let dest = newParent.appending(pathComponent: newName)
        return try await logging("mv \(source) \(dest)") {
            guard let sourceData = source.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(source)
            }
            guard let destData = dest.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(newName)
            }
            log("perform file operation to make a symlink")
            let json = try await performFileOperation(subcommand: .mv(source: sourceData,
                                                                      dest: destData))
            let result = try remoteFile(json)
            log("finished")
            return result
        }
    }

    @MainActor
    func rm(_ file: String, recursive: Bool) async throws {
        try await logging("rm \(recursive ? "-rf " : "-f") \(file)") {
            log("perform file operation to unlink")
            guard let fileData = file.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(file)
            }
            _ = try await performFileOperation(subcommand: .rm(path: fileData,
                                                               recursive: recursive))
        }
    }

    @MainActor
    func mkdir(_ path: String) async throws {
        try await logging("mkdir \(path)") {
            guard let pathData = path.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(path)
            }
            log("perform file operation to mkdir \(path)")
            _ = try await performFileOperation(subcommand: .mkdir(path: pathData))
            log("finished")
        }
    }


    func create(file: String, content: Data, completion: @escaping (Error?) -> ()) {
        Task {
            do {
                try await create(file, content: content)
                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
    @MainActor
    func create(_ file: String, content: Data) async throws {
        try await logging("create \(file) length=\(content.count) bytes") {
            guard let pathData = file.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(file)
            }
            log("perform file operation to create \(file)")
            _ = try await performFileOperation(subcommand: .create(path: pathData, content: content))
            log("finished")
        }
    }

    @MainActor
    func append(_ file: String, content: Data) async throws {
        try await logging("append \(file) length=\(content.count) bytes") {
            guard let pathData = file.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(file)
            }
            log("perform file operation to append \(file)")
            _ = try await performFileOperation(subcommand: .append(path: pathData, content: content))
            log("finished")
        }
    }

    // This is just create + stat
    @MainActor
    func replace(_ file: String, content: Data) async throws -> RemoteFile {
        try await logging("replace \(file) length=\(content.count) bytes") {
            guard let pathData = file.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(file)
            }
            log("perform file operation to replace \(file)")
            let json = try await performFileOperation(subcommand: .create(path: pathData, content: content))
            let result = try remoteFile(json)
            log("finished")
            return result
        }
    }

    @MainActor
    func setModificationDate(_ file: String, date: Date) async throws -> RemoteFile {
        try await logging("utime \(file) \(date)") {
            guard let pathData = file.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(file)
            }
            log("perform file operation to utime \(file)")
            let json = try await performFileOperation(subcommand: .utime(path: pathData,
                                                                         date: date))
            let result = try remoteFile(json)
            log("finished")
            return result
        }
    }

    @MainActor
    func chmod(_ file: String, permissions: RemoteFile.Permissions) async throws -> RemoteFile {
        try await logging("utime \(file) \(permissions)") {
            guard let pathData = file.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(file)
            }
            log("perform file operation to chmod \(file)")
            let json = try await performFileOperation(subcommand: .chmod(path: pathData,
                                                                         r: permissions.r,
                                                                         w: permissions.w,
                                                                         x: permissions.x))
            let result = try remoteFile(json)
            log("finished")
            return result
        }
    }

    @available(macOS 11.0, *)
    @MainActor
    func search(_ basedir: String,
                query: String,
                cancellation: Cancellation) async throws -> AsyncThrowingStream<RemoteFile, Error> {
        currentSearch?.cancellation.cancel()
        return try await logging("search \(basedir) \(query)") {
            let id = try await performFileOperation(subcommand: .search(.start(query: query.lossyData,
                                                                               baseDirectory: basedir.lossyData)))
            cancellation.impl = { [weak self] in
                Task { @MainActor in
                    try? await self?.performFileOperation(subcommand: .search(.stop(id: id)))
                }
            }
            return AsyncThrowingStream<RemoteFile, Error> { continuation in
                DLog("Begin new search with id \(id) and query \(query)")
                currentSearch = Search(id: id,
                                       query: query,
                                       continuation: continuation,
                                       cancellation: cancellation)
            }
        }
    }
}

extension RemoteFile {
    /// Converts a `RemoteFile` instance into a Unix-like `struct stat`.
    func toStat() -> stat {
        var fileStat = stat()

        var fileType: mode_t = 0
        switch self.kind {
        case .file:
            fileType = S_IFREG   // Regular file.
        case .folder:
            fileType = S_IFDIR   // Directory.
        case .symlink:
            fileType = S_IFLNK   // Symlink.
        case .host:
            // There is no direct mapping for "host" in POSIX;
            // here we default to treating it like a regular file.
            fileType = S_IFREG
        }

        // Calculate permission bits based on our Permissions type.
        var permissionBits: mode_t = 0
        if let perms = self.permissions {
            if perms.r {
                permissionBits |= S_IRUSR
            }
            if perms.w {
                permissionBits |= S_IWUSR
            }
            if perms.x {
                permissionBits |= S_IXUSR
            }
        }
        // Combine type and permission bits.
        fileStat.st_mode = fileType | permissionBits

        // File size: use the wrapped file info for files, or 0 for directories and others.
        let sizeValue = self.size ?? 0
        fileStat.st_size = off_t(sizeValue)

        return fileStat
    }
}

