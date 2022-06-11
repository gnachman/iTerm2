import FileProvider
import FileProviderService

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private let fetcher: FileProviderFetcher
    private let creator: ItemCreator
    private let modifier: ItemModifier
    private let deleter: ItemDeleter
    private let manager:  NSFileProviderManager?

    lazy var service: FileProviderService = {
        return FileProviderService(self)
    }()
    
    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        fetcher = FileProviderFetcher(domain: domain)
        creator = ItemCreator(domain: domain)
        modifier = ItemModifier(domain: domain)
        deleter = ItemDeleter(domain: domain)
        manager = NSFileProviderManager(for: domain)

        super.init()
    }

    private func startTwiddling() {
        Task {
            while true {
                log("Signal change to folder2")
                let path = "/example.com/folder2"
                await Task { await RemoteService.instance.twiddle() }.value
                NSFileProviderManager(for: domain)?.signalEnumerator(for: NSFileProviderItemIdentifier(rawValue: path)) { error in
                    if let error = error {
                        log("twiddler failed with \(error)")
                    }
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func invalidate() {
        log("Extension.invalidate()")
        Task {
            await RemoteService.instance.invalidateListFiles()
        }
        Task { await SyncCache.instance.invalidate() }
    }
    
    func item(for identifier: NSFileProviderItemIdentifier,
               request: NSFileProviderRequest,
               completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        Task {
            await logging("Extension.item(for: \(identifier.rawValue))") {
                do {
                    let entry = try await remoteFile(for: identifier)
                    log("Using remote file: \(entry)")
                    // Pass it along to the item
                    let item = await FileProviderItem(entry, manager: manager)
                    log("Return \(item.terseDescription)")
                    completionHandler(item, nil)
                } catch {
                    log("Return error \(error)")
                    completionHandler(nil, error)
                }
            }
        }
        return Progress()
    }

    private func remoteFile(for identifier: NSFileProviderItemIdentifier) async throws -> RemoteFile {
        switch identifier {
        case .rootContainer, .trashContainer:
            log("Use root")
            return RemoteFile.root
        case .workingSet:
            return RemoteFile.workingSet
        default:
            log("Looking up \(identifier.rawValue) from remote service")
            return try await RemoteService.instance.lookup(identifier.rawValue)
        }
    }

    private func asyncItem(for itemIdentifier: NSFileProviderItemIdentifier,
                           request: NSFileProviderRequest) async throws -> NSFileProviderItem {
        try await withCheckedThrowingContinuation { continuation in
            _ = self.item(for: itemIdentifier, request: request) { maybeItem, maybeError in
                if let justItem = maybeItem {
                    continuation.resume(with: .success(justItem))
                    return
                }
                if let justError = maybeError {
                    continuation.resume(throwing: justError)
                }
            }
        }
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?,
                                                     NSFileProviderItem?,
                                                     Error?) -> Void) -> Progress {
        let progress = Progress()
        logging("Extension.fetchContents(for: \(itemIdentifier.description), version: \(requestedVersion.descriptionOrNil))") {
            log("Fetching item \(itemIdentifier.rawValue)")
            Task {
                do {
                    let item = try await asyncItem(for: itemIdentifier, request: request)
                    log("Fetched item \(item.terseDescription). Can now download its contents.")
                    if let size = item.documentSize??.intValue {
                        log("Set total unit count to \(size)")
                        progress.totalUnitCount = Int64(size)
                        progress.completedUnitCount = 0
                    }
                    let fetchRequest = FileProviderFetcher.FetchRequest(
                        itemIdentifier: itemIdentifier,
                        requestedVersion: requestedVersion,
                        request: request)
                    let tempURL = try await self.fetcher.fetchContents(fetchRequest,
                                                                       progress: progress)
                    completionHandler(tempURL, item, nil)
                } catch {
                    log("Failed to fetch \(itemIdentifier.rawValue): \(error)")
                    // TODO: Convert cocoa errors like:
                    // NSCocoaErrorDomain Code=4 "The file “fetch-44BF2850-96CC-4824-AD7E-0570A97A0022” doesn’t exist."
                    // To something NSFileProvider can understand.
                    completionHandler(nil, nil, error)
                }
            }
        }
        return progress
    }
    
    func createItem(basedOn itemTemplate: NSFileProviderItem,
                    fields: NSFileProviderItemFields,
                    contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?,
                                                  NSFileProviderItemFields,
                                                  Bool,
                                                  Error?) -> Void) -> Progress {
        log("Extension.createItem(basedOn: \(itemTemplate.terseDescription), fields: \(fields.description), contents: \(url.descriptionOrNil), options: \(options.description))")
        let request = ItemCreator.Request(itemTemplate: itemTemplate,
                                          fields: fields,
                                          contents: url,
                                          options: options,
                                          request: request)
        let progress = Progress()
        Task {
            do {
                let item = try await creator.create(request)
                completionHandler(item.item, item.fields, false, nil)
            } catch {
                completionHandler(nil, [], false, error)
            }
        }
        return progress
    }
    
    func modifyItem(_ item: NSFileProviderItem,
                    baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields,
                    contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?,
                                                  NSFileProviderItemFields,
                                                  Bool,
                                                  Error?) -> Void) -> Progress {
        let modifyRequest = ItemModifier.Request(item: item,
                                                 version: version,
                                                 changedFields: changedFields,
                                                 contents: newContents,
                                                 options: options,
                                                 request: request)
        Task {
            await logging("Extension.modifyItem(\(item.terseDescription), baseVersion: \(version.description), changedFields: \(changedFields.description), contents: \(newContents?.path ?? "(nil)"), options: \(options.description))") {
                do {
                    let file = try await remoteFile(for: item.itemIdentifier)
                    let update = try await modifier.modify(file, request: modifyRequest)
                    completionHandler(update.item, update.fields, update.shouldFetchContent, nil)
                } catch {
                    completionHandler(nil, [], true, error)
                }
            }
        }
        return modifyRequest.progress
    }
    
    func deleteItem(identifier: NSFileProviderItemIdentifier,
                    baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        Task {
            let request = ItemDeleter.Request(identifier: identifier,
                                              version: version,
                                              options: options,
                                              request: request)
            await logging("deleteItem(\(request))") {
                do {
                    let file = try await remoteFile(for: identifier)
                    try await deleter.delete(file, request: request)
                    completionHandler(nil)
                } catch {
                    log("Delete failed with error: \(error)")
                    completionHandler(error)
                }
            }
        }
        completionHandler(NSError(domain: NSCocoaErrorDomain,
                                  code: NSFeatureUnsupportedError,
                                  userInfo:[:]))
        return Progress()
    }
    
    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        return logging("Extension.enumerator(for: \(containerItemIdentifier.description))") {
            switch containerItemIdentifier {
            case .workingSet:
                return FileProviderEnumerator(RemoteFile.workingSetPrefix, domain: domain)
            case .rootContainer, .trashContainer:
                log("Treat as root")
                Task {
                    await WorkingSet.instance.addFolder("/",
                                                        domain: domain)
                }
                return FileProviderEnumerator("/", domain: domain)
            default:
                let path = containerItemIdentifier.rawValue
                Task {
                    await WorkingSet.instance.addFolder(path,
                                                        domain: domain)
                }
                return FileProviderEnumerator(path, domain: domain)
            }
        }
    }
}
