import Foundation
import FileProvider
import FileProviderService

fileprivate extension Error {
    var asSystemFileProviderError: NSFileProviderError {
        if let error = self as? NSFileProviderError {
            return error
        }
        switch self as? iTermFileProviderServiceError {
        case .none, .disconnected, .unknown, .internalError:
            return NSFileProviderError(.serverUnreachable)
        case .notFound, .notAFile, .permissionDenied:
            return NSFileProviderError(.noSuchItem)
        }
    }
}

// Methods called by file provider. Proxies requests over XPC to the main app.
actor RemoteService {
    private let xpcService: FileProviderService
    init(_ xpcService: FileProviderService) {
        self.xpcService = xpcService
    }

    // List files at a location.
    func list(at path: String,
              fromPage requestedPage: Data?,
              sort: FileSorting,
              pageSize: Int?) async throws -> ListResult {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try xpcService.sendRequest(.list(path: path,
                                                 requestedPage: requestedPage,
                                                 sort: sort,
                                                 pageSize: pageSize), handler: { response in
                    switch response {
                    case .list(.success(let result)):
                        continuation.resume(with: .success(result))
                    case .list(.failure(let error)):
                        continuation.resume(with: .failure(error.asSystemFileProviderError))
                    default:
                        log("Unexpected response \(response)")
                        continuation.resume(with: .failure(NSFileProviderError(.noSuchItem)))
                    }
                })
            } catch {
                continuation.resume(with: .failure(error.asSystemFileProviderError))
            }
        }
    }

    // Get metadata about a single file.
    func lookup(_ path: String) async throws -> RemoteFile {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try xpcService.sendRequest(.lookup(path: path), handler: { response in
                    switch response {
                    case .lookup(.success(let result)):
                        continuation.resume(with: .success(result))
                    case .lookup(.failure(let error)):
                        continuation.resume(with: .failure(error.asSystemFileProviderError))
                    default:
                        log("Unexpected response \(response)")
                        continuation.resume(with: .failure(NSFileProviderError(.noSuchItem)))
                    }
                })
            } catch {
                continuation.resume(with: .failure(error.asSystemFileProviderError))
            }
        }
    }

    // Request that the file provider be signaled when any of these paths change.
    func subscribe(_ paths: [String]) {
        try? xpcService.sendRequest(.subscribe(paths: paths)) { _ in }
    }

    // Get the content of a single file.
    func fetch(_ path: String) -> AsyncStream<Result<Data, Error>> {
        AsyncStream { stream in
            Task {
                do {
                    try xpcService.sendRequest(.fetch(path: path), handler: { response in
                        switch response {
                        case .fetch(.success(let data)):
                            stream.yield(.success(data))
                            stream.finish()
                        case .fetch(.failure(let error)):
                            stream.yield(.failure(error.asSystemFileProviderError))
                        default:
                            log("Unexpected response \(response)")
                            stream.yield(.failure(NSFileProviderError(.noSuchItem)))
                        }
                    })
                } catch {
                    stream.yield(.failure(error.asSystemFileProviderError))
                }
            }
        }
    }

    // Delete a file, folder, or symlink.
    func delete(_ file: RemoteFile, recursive: Bool) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try xpcService.sendRequest(.delete(file: file, recursive: recursive), handler: { response in
                    switch response {
                    case .delete(let error):
                        if let error = error {
                            continuation.resume(with: .failure(error.asSystemFileProviderError))
                        } else {
                            continuation.resume(with: .success(()))
                        }
                    default:
                        log("Unexpected response \(response)")
                        continuation.resume(with: .failure(NSFileProviderError(.noSuchItem)))
                    }
                })
            } catch {
                continuation.resume(with: .failure(error.asSystemFileProviderError))
            }
        }
    }

    // Create a symlink.
    func ln(source: String, file: RemoteFile) async throws -> RemoteFile {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try xpcService.sendRequest(.ln(source: source, file: file), handler: { response in
                    switch response {
                    case .ln(.success(let result)):
                        continuation.resume(with: .success(result))
                    case .ln(.failure(let error)):
                        continuation.resume(with: .failure(error.asSystemFileProviderError))
                    default:
                        log("Unexpected response \(response)")
                        continuation.resume(with: .failure(NSFileProviderError(.noSuchItem)))
                    }
                })
            } catch {
                continuation.resume(with: .failure(error.asSystemFileProviderError))
            }
        }
    }

    // Rename and reparent a file, folder or symlink.
    func mv(file: RemoteFile, newParent: String, newName: String) async throws -> RemoteFile {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try xpcService.sendRequest(.mv(file: file, newParent: newParent, newName: newName), handler: { response in
                    switch response {
                    case .mv(.success(let result)):
                        continuation.resume(with: .success(result))
                    case .mv(.failure(let error)):
                        continuation.resume(with: .failure(error.asSystemFileProviderError))
                    default:
                        log("Unexpected response \(response)")
                        continuation.resume(with: .failure(NSFileProviderError(.noSuchItem)))
                    }
                })
            } catch {
                continuation.resume(with: .failure(error.asSystemFileProviderError))
            }
        }
    }

    // Create a directory.
    func mkdir(_ file: RemoteFile) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try xpcService.sendRequest(.mkdir(file: file), handler: { response in
                    switch response {
                    case .mkdir(let error):
                        if let error = error {
                            continuation.resume(with: .failure(error.asSystemFileProviderError))
                        } else {
                            continuation.resume(with: .success(()))
                        }
                    default:
                        log("Unexpected response \(response)")
                        continuation.resume(with: .failure(NSFileProviderError(.noSuchItem)))
                    }
                })
            } catch {
                continuation.resume(with: .failure(error.asSystemFileProviderError))
            }
        }
    }

    // Create a file and give it contents.
    func create(_ file: RemoteFile, content: Data) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try xpcService.sendRequest(.create(file: file, content: content), handler: { response in
                    switch response {
                    case .create(let error):
                        if let error = error {
                            continuation.resume(with: .failure(error.asSystemFileProviderError))
                        } else {
                            continuation.resume(with: .success(()))
                        }
                    default:
                        log("Unexpected response \(response)")
                        continuation.resume(with: .failure(NSFileProviderError(.noSuchItem)))
                    }
                })
            } catch {
                continuation.resume(with: .failure(error.asSystemFileProviderError))
            }
        }
    }

    // Replace the contents of a file.
    func replaceContents(_ file: RemoteFile,
                         item: NSFileProviderItem,
                         url: URL) async throws -> RemoteFile {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let data = try Data(contentsOf: url)
                try xpcService.sendRequest(.replaceContents(file: file, contents: data), handler: { response in
                    switch response {
                    case .replaceContents(.success(let result)):
                        continuation.resume(with: .success(result))
                    case .replaceContents(.failure(let error)):
                        continuation.resume(with: .failure(error.asSystemFileProviderError))
                    default:
                        log("Unexpected response \(response)")
                        continuation.resume(with: .failure(NSFileProviderError(.noSuchItem)))
                    }
                })
            } catch {
                continuation.resume(with: .failure(error.asSystemFileProviderError))
            }
        }
    }

    // Change the mtime of a file or folder
    func setModificationDate(_ file: RemoteFile, date: Date) async throws -> RemoteFile {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try xpcService.sendRequest(.setModificationDate(file: file, date: date), handler: { response in
                    switch response {
                    case .setModificationDate(.success(let result)):
                        continuation.resume(with: .success(result))
                    case .setModificationDate(.failure(let error)):
                        continuation.resume(with: .failure(error.asSystemFileProviderError))
                    default:
                        log("Unexpected response \(response)")
                        continuation.resume(with: .failure(NSFileProviderError(.noSuchItem)))
                    }
                })
            } catch {
                continuation.resume(with: .failure(error.asSystemFileProviderError))
            }
        }
    }

    // Change permissions of a file, folder, or symlink.
    func chmod(_ file: RemoteFile, permissions: RemoteFile.Permissions) async throws -> RemoteFile {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try xpcService.sendRequest(.chmod(file: file, permissions: permissions), handler: { response in
                    switch response {
                    case .chmod(.success(let result)):
                        continuation.resume(with: .success(result))
                    case .chmod(.failure(let error)):
                        continuation.resume(with: .failure(error.asSystemFileProviderError))
                    default:
                        log("Unexpected response \(response)")
                        continuation.resume(with: .failure(NSFileProviderError(.noSuchItem)))
                    }
                })
            } catch {
                continuation.resume(with: .failure(error.asSystemFileProviderError))
            }
        }
    }
}
