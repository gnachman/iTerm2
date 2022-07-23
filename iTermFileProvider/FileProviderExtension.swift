import FileProvider
import FileProviderService

private class Counter {
    private let value = MutableAtomicObject<Int>(0)
    func next() -> Int {
        let newValue = value.mutate { oldValue in
            return oldValue + 1
        }
        return newValue - 1
    }
}

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private let fetcher: FileProviderFetcher
    private let creator: ItemCreator
    private let modifier: ItemModifier
    private let deleter: ItemDeleter
    private let manager:  NSFileProviderManager?
    private let remoteService: RemoteService!
    private let workingSet: WorkingSet
    private let counter = Counter()
    let xpcService: FileProviderService

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        xpcService = FileProviderService()
        remoteService = RemoteService(xpcService)
        fetcher = FileProviderFetcher(domain: domain, remoteService: remoteService)
        creator = ItemCreator(domain: domain, remoteService: remoteService)
        modifier = ItemModifier(domain: domain, remoteService: remoteService)
        deleter = ItemDeleter(domain: domain, remoteService: remoteService)
        manager = NSFileProviderManager(for: domain)
        workingSet = WorkingSet(remoteService: remoteService)

        super.init()

    }

    func invalidate() {
        log("Extension.invalidate()")
        Task { await SyncCache.instance.invalidate() }
    }
    
    func item(for identifier: NSFileProviderItemIdentifier,
              request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        Task {
            let reqnum = counter.next()
            await logging("[reqnum:\(reqnum)] Extension.item(for: \(identifier.rawValue))") {
                log("LIFECYCLE: Start")
                do {
                    let entry = try await remoteFile(for: identifier)
                    log("Using remote file: \(entry)")
                    // Pass it along to the item
                    let item = await FileProviderItem(entry, manager: manager)
                    log("Return \(item.terseDescription)")
                    log("LIFECYCLE: Normal completion")
                    completionHandler(item, nil)
                } catch {
                    log("Return error \(error)")
                    log("LIFECYCLE: Error completion")
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
            let result = try await remoteService.lookup(identifier.rawValue)
            log("Found \(result)")
            return result
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
        Task {
            let reqnum = counter.next()
            await logging("[reqnum: \(reqnum)] Extension.fetchContents(for: \(itemIdentifier.description), version: \(requestedVersion.descriptionOrNil))") {
                log("LIFECYCLE: Start")
                log("Fetching item \(itemIdentifier.rawValue)")
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
                    log("Fetch succeeded")
                    log("LIFECYCLE: Normal completion")
                    completionHandler(tempURL, item, nil)
                } catch {
                    log("Failed to fetch \(itemIdentifier.rawValue): \(error)")
                    // TODO: Convert cocoa errors like:
                    // NSCocoaErrorDomain Code=4 "The file “fetch-44BF2850-96CC-4824-AD7E-0570A97A0022” doesn’t exist."
                    // To something NSFileProvider can understand.
                    log("LIFECYCLE: Error completion")
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
        let progress = Progress()
        Task {
            let reqnum = counter.next()
            await logging("[reqnum: \(reqnum)] Extension.createItem(basedOn: \(itemTemplate.terseDescription), fields: \(fields.description), contents: \(url.descriptionOrNil), options: \(options.description))") {
                log("LIFECYCLE: Start")
                let request = ItemCreator.Request(itemTemplate: itemTemplate,
                                                  fields: fields,
                                                  contents: url,
                                                  options: options,
                                                  request: request)
                do {
                    let item = try await creator.create(request)
                    log("Create succeded")
                    log("LIFECYCLE: Normal completion")
                    completionHandler(item.item, item.fields, false, nil)
                } catch {
                    log("Create failed with \(error)")
                    log("LIFECYCLE: Error completion")
                    completionHandler(nil, [], false, error)
                }
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
            let reqnum = counter.next()
            await logging("[reqnum: \(reqnum)] Extension.modifyItem(\(item.terseDescription), baseVersion: \(version.description), changedFields: \(changedFields.description), contents: \(newContents?.path ?? "(nil)"), options: \(options.description))") {
                log("LIFECYCLE: Start")
                do {
                    let file = try await remoteFile(for: item.itemIdentifier)
                    let update = try await modifier.modify(file, request: modifyRequest)
                    log("Modify succeeded")
                    log("LIFECYCLE: Normal completion")
                    completionHandler(update.item, update.fields, update.shouldFetchContent, nil)
                } catch {
                    log("Modify failed with \(error)")
                    log("LIFECYCLE: Error completion")
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
            let reqnum = counter.next()
            let request = ItemDeleter.Request(identifier: identifier,
                                              version: version,
                                              options: options,
                                              request: request)
            await logging("[reqnum: \(reqnum)] Extension.deleteItem(\(request))") {
                log("LIFECYCLE: Start")
                do {
                    let file = try await remoteFile(for: identifier)
                    try await deleter.delete(file, request: request)
                    log("Delete succeeded")
                    log("LIFECYCLE: Normal completion")
                    completionHandler(nil)
                } catch {
                    log("Delete failed with error: \(error)")
                    log("LIFECYCLE: Error completion")
                    completionHandler(error)
                }
            }
        }
        return Progress()
    }
    
    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        let reqnum = counter.next()
        return logging("[reqnum: \(reqnum)] Extension.enumerator(for: \(containerItemIdentifier.description))") {
            log("LIFECYCLE: Start")
            defer {
                log("LIFECYCLE: Normal completion")
            }
            switch containerItemIdentifier {
            case .workingSet:
                return FileProviderEnumerator(RemoteFile.workingSetPrefix,
                                              domain: domain,
                                              remoteService: remoteService,
                                              workingSet: workingSet)
            case .rootContainer, .trashContainer:
                log("Treat as root")
                Task {
                    await workingSet.addFolder("/",
                                               domain: domain)
                }
                return FileProviderEnumerator("/", domain: domain,
                                              remoteService: remoteService,
                                              workingSet: workingSet)
            default:
                let path = containerItemIdentifier.rawValue
                Task {
                    await workingSet.addFolder(path,
                                               domain: domain)
                }
                return FileProviderEnumerator(path, domain: domain,
                                              remoteService: remoteService,
                                              workingSet: workingSet)
            }
        }
    }
}
