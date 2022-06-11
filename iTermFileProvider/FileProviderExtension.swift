//
//  FileProviderExtension.swift
//  iTermFileProvider
//
//  Created by George Nachman on 6/4/22.
//

import FileProvider
import os.log
import FileProviderService

let logger = Logger(subsystem: "com.googlecode.iterm2.FileProvider", category: "extension")

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension, SSHConnectionProviding, FileListingProvider {
    let domain: NSFileProviderDomain
    var root: RootListFileProviderItem? = nil
    lazy var service: FileProviderService = {
        logger.debug("Extension: Create FileProviderService")
        return FileProviderService(self)
    }()

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
        logger.debug("Extension: init")
    }
    
    func invalidate() {
        logger.debug("Extension: invalidate")
        // TODO: cleanup any resources
    }
    
    func item(for identifier: NSFileProviderItemIdentifier,
              request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        logger.debug("Extension: item(forIdentifier:\(identifier.rawValue, privacy: .public)), request: \(request, privacy: .public)")

        switch identifier {
        case RootListFileProviderItem.itemIdentifier, .rootContainer:
            logger.debug("Extension: Root item requested. Fetching connections.")
            do {
                return try getConnections { result in
                    switch result {
                    case .failure(let error):
                        logger.debug("Extension: Failed to get connections. Return error from item(for:,request:)")
                        logger.debug("Extension: item(\(identifier.rawValue, privacy: .public)): return error \(error.localizedDescription, privacy: .public)")
                        completionHandler(nil, error)
                        return
                    case .success(let connections):
                        logger.debug("Extension: Got \(connections.count, privacy: .public) connections")
                        let item = RootListFileProviderItem(connections)
                        logger.debug("Extension: item(\(identifier.rawValue, privacy: .public)): return item \(item.debugDescription, privacy: .public)")
                        completionHandler(item, nil)
                    }
                }
            } catch {
                logger.error("Extension: item(\(identifier.rawValue, privacy: .public)): getConnections threw \(error.localizedDescription, privacy: .public): return serverUnreachable")
                completionHandler(nil, NSFileProviderError(.serverUnreachable))
                return Progress()
            }
        case .trashContainer, .workingSet:
            logger.debug("Extension: item(\(identifier.rawValue, privacy: .public)): returning empty item")
            completionHandler(FileProviderEmptyItem(itemIdentifier: identifier,
                                                    parentItemIdentifier: RootListFileProviderItem.itemIdentifier,
                                                    filename: "trash"),
                              nil)
            return Progress()

        default:
            if let sshFileItem = SSHFileItem(identifier: identifier) {
                logger.debug("Extension: item(\(identifier.rawValue, privacy: .public)): return \(sshFileItem.debugDescription, privacy: .public)")
                completionHandler(sshFileItem, nil)
            } else {
                logger.debug("Extension: item(\(identifier.rawValue, privacy: .public)): failed to build an SSHFileItem for this identifier. return error noSuchItem")
                completionHandler(nil, NSFileProviderError(.noSuchItem))
            }
            return Progress()
        }
    }

    func getConnections(_ completionHandler: @escaping (Result<[SSHConnectionIdentifier], Error>) -> ()) throws -> Progress {
        logger.debug("Extension: getConnections")
        var canceled = false
        try service.sendRequest(.listConnections) { generic in
            logger.debug("Extension: getConnections callback with \(generic.debugDescription, privacy: .public)")
            if canceled {
                logger.debug("Extension: getConnections: Request for connections was canceled")
                return
            }
            guard case let .connectionList(connections) = generic else {
                logger.debug("Extension: getConnections: bogus response: \(generic.debugDescription, privacy: .public)")
                let error = NSFileProviderError(.noSuchItem)
                completionHandler(.failure(error))
                return
            }
            logger.debug("Extension: getConnections: Got list of connections successfully")
            completionHandler(.success(connections))
        }
        let progress = Progress(totalUnitCount: 1)
        progress.cancellationHandler = {
            logger.debug("Extension: getConnections: cancellation handler called")
            canceled = true
            completionHandler(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        }
        return progress
    }

    func listFiles(_ path: SSHFilePath) async throws -> [SSHListFilesItem] {
        logger.debug("Extension: listFiles(\(path.debugDescription, privacy: .public))")

        let result: [SSHListFilesItem] = try await withCheckedThrowingContinuation { continuation in
            do {
                try service.sendRequest(.listFiles(connection: path.connection, path: path.path.path), handler: { generic in
                    logger.debug("Extension: listFiles: Callback run with \(generic.debugDescription, privacy: .public)")
                    guard case let .fileList(result) = generic else {
                        logger.debug("Extension: listFiles: bogus response: \(generic.debugDescription, privacy: .public)")
                        let error = NSFileProviderError(.noSuchItem)
                        continuation.resume(with: .failure(error))
                        return
                    }
                    logger.debug("Extension: listFiles: Got list of files successfully")
                    switch result {
                    case .success(let items):
                        continuation.resume(with: .success(items))
                    case .failure(let fetchError):
                        switch fetchError {
                        case .disconnected:
                            continuation.resume(with: .failure(NSFileProviderError(.serverUnreachable)))
                        case .fileNotFound:
                            let error = NSError.fileProviderErrorForNonExistentItem(
                                withIdentifier: NSFileProviderItemIdentifier(sshFilePath: path))
                            continuation.resume(with: .failure(error))
                        case .accessDenied:
                            continuation.resume(with: .success([]))
                        case .other:
                            continuation.resume(with: .failure(NSFileProviderError(.serverUnreachable)))
                        }
                    }
                })
            } catch {
                continuation.resume(with: .failure(error))
            }
        }
        logger.debug("Extension: listFiles(\(path.debugDescription, privacy: .public)) returning \(result, privacy: .public)")
        return result
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        logger.debug("Extension: fetchContents(for: \(itemIdentifier.rawValue, privacy: .public), version: \(requestedVersion.debugDescription, privacy: .public), request: \(request.debugDescription, privacy: .public)")
        logger.debug("Extension: Return unsupported")
        completionHandler(nil, nil, NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo:[:]))
        return Progress()
    }
    
    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?, options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        logger.debug("Extension: FileProviderExtension: createItem called")

        completionHandler(itemTemplate, [], false, nil)
        return Progress()
    }
    
    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        logger.debug("Extension: modifyItem called")
        
        completionHandler(nil, [], false, NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo:[:]))
        return Progress()
    }
    
    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        logger.debug("Extension: deleteItem called")
        
        completionHandler(NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo:[:]))
        return Progress()
    }
    
    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        logger.debug("Extension: enumerator(for: \(containerItemIdentifier.rawValue, privacy: .public)")
        switch containerItemIdentifier {
        case NSFileProviderItemIdentifier.rootContainer, RootListFileProviderItem.itemIdentifier:
            logger.debug("Extension: enumerator(for: \(containerItemIdentifier.rawValue, privacy: .public): Return root list file provider enumerator")
            return RootListFileProviderEnumerator(self)

        case NSFileProviderItemIdentifier.workingSet, NSFileProviderItemIdentifier.trashContainer:
            logger.debug("Extension: enumerator(for: \(containerItemIdentifier.rawValue, privacy: .public): Return empty enumerator")
            return EmptyFileProviderEnumerator()

        default:
            logger.debug("Extension: enumerator(for: \(containerItemIdentifier.rawValue, privacy: .public): Return file provider enumerator")
            guard let container = SSHFileItem(identifier: containerItemIdentifier) else {
                logger.error("Extension: enumerator(for: \(containerItemIdentifier.rawValue, privacy: .public): Could not make parent item for identifier \(containerItemIdentifier.rawValue, privacy: .public). THROW .noSuchItem")
//                throw NSError.fileProviderErrorForNonExistentItem(withIdentifier: containerItemIdentifier)
                throw NSFileProviderError(.noSuchItem)
            }
            return FileProviderEnumerator(container: container,
                                          fileListingProvider: self)
        }
    }
}

extension FileProviderExtension: NSFileProviderServicing {
    public func supportedServiceSources(for itemIdentifier: NSFileProviderItemIdentifier,
                                        completionHandler: @escaping ([NSFileProviderServiceSource]?, Error?) -> Void) -> Progress {
        logger.debug("Extension: supportedServiceSources(for: \(itemIdentifier.rawValue, privacy: .public)")
        completionHandler([service], nil)
        let progress = Progress()
        progress.cancellationHandler = { completionHandler(nil, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) }
        return progress
    }
}
