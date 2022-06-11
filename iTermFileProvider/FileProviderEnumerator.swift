import FileProvider

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let path: String
    private let anchor = NSFileProviderSyncAnchor(Data())
    private var dataSource: CachingPaginatingDataSource
    static var enumeratedPaths = NSCountedSet()
    private let manager: NSFileProviderManager?

    init(_ path: String, domain: NSFileProviderDomain) {
        log("Enumerator(\(path)): Create enumerator for path \(path)")
        self.path = path
        manager = NSFileProviderManager(for: domain)
        dataSource = CachingPaginatingDataSource(path, domain: domain)
        Self.enumeratedPaths.add(path)
        log("Paths are now: \(Self.enumeratedPaths.allObjects.compactMap { $0 as? String }.joined(separator: ", "))")
        super.init()
    }

    deinit {
        Self.enumeratedPaths.remove(path)
        log("Enumerator(\(path)).deinit.")
        log("Paths are now: \(Self.enumeratedPaths.allObjects.compactMap { $0 as? String }.joined(separator: ", "))")
    }

    func invalidate() {
        log("Enumerator(\(path)).invalidate()")
        // Note that the job of invalidate() is to stop enumeration of items and changes but not to
        // destroy any cached state.
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver,
                        startingAt page: NSFileProviderPage) {
        Task {
            await logging("Enumerator(\(path)).enumerateItems(startingAt: \(page.description))") {
                do {
                    if path == RemoteFile.workingSetPrefix {
                        await enumerateWorkingSet(observer, page: page)
                    } else {
                        log("Make a request to the data source")
                        let nextPage = try await enumerate(path: path,
                                                           page: page,
                                                           observer: observer,
                                                           workingSet: false)
                        observer.finishEnumerating(upTo: nextPage)
                    }
                } catch {
                    log("Finish enumerating with ERROR \(error)")
                    observer.finishEnumeratingWithError(error)
                }
            }
        }
    }

    private func enumerateWorkingSet(_ observer: NSFileProviderEnumerationObserver,
                                     page startPage: NSFileProviderPage) async {
        await logging("Enumerating Working Set") {
            for entry in await WorkingSet.instance.entries {
                log("Enumerate \(entry.path) from working set")
                var nextPage: NSFileProviderPage? = startPage
                while let page = nextPage {
                    do {
                        log("Enumerating page \(page.description)")
                        switch entry.kind {
                        case .folder:
                            nextPage = try await enumerate(path: entry.path,
                                                           page: page,
                                                           observer: observer,
                                                           workingSet: true)
                        case .file:
                            let file = try await RemoteService.instance.lookup(entry.path)
                            observer.didEnumerate([await FileProviderItem(file, manager: manager)])
                        }
                    } catch {
                        log("Enumeration of \(path) failed with \(error.localizedDescription)")
                        break
                    }
                }
            }
            log("Finished enumerating working set")
            observer.finishEnumerating(upTo: nil)
        }
    }

    private func enumerate(path: String,
                           page: NSFileProviderPage,
                           observer: NSFileProviderEnumerationObserver,
                           workingSet: Bool) async throws -> NSFileProviderPage? {
        let (files, nextPage) = try await dataSource.request(
            service: RemoteService.instance,
            path: path,
            page: page,
            pageSize: observer.suggestedPageSize,
            workingSet: workingSet)
        log("For \(path), provide observer these files: \(files), nextPage=\(nextPage?.description ?? "(nil)")")
        let root = try? await manager?.getUserVisibleURL(for: .rootContainer)
        let items = files.map { FileProviderItem($0, userVisibleRoot: root) }
        log("Provide \(items.count) items with next page of \(nextPage?.description ?? "(nil)")")
        observer.didEnumerate(items)

        if self.path != RemoteFile.workingSetPrefix {
            log("If parent directory is in the working set, add these files to it.")
            let parent = (self.path as NSString).deletingLastPathComponent
            if await WorkingSet.instance.entries.contains(where: { $0.path == parent }) {
                await ensureItemsInLatestWorkingSetAnchor(items)
            }
        }
        return nextPage
    }

    // This is insane, but if you reveal the existance of an item after enumerating the working set, the system assumes that those items exist the next time it calls enumerateChanges.
    // For example:
    // enumerateChanges(working set) -> delete: [], update: [/foo] upToAnchor=1
    // enumerate(/foo): [/foo/bar]
    // currentAnchor: 2
    // At this point /foo/bar is deleted from the remote.
    // enumerateChanges(workingSet) -> delete [/foo/bar], update: [] upToAnchor=3
    //
    // If you fail to list /foo/bar as a deletion, it will live forever.
    private func ensureItemsInLatestWorkingSetAnchor(_ items: [FileProviderItem]) async {
        await dataSource.addItemsToWorkingSetAnchors(items)
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver,
                          from anchor: NSFileProviderSyncAnchor) {
        let prefix = "Enumerator(\(path)).enumerateChanges(from anchor: \(anchor.description))"
        logging(prefix) {
            _ = Task {
                do {
                    let diff = FileListDiff()
                    try await addFiles(fromAnchor: anchor, to: diff)

                    if path == RemoteFile.workingSetPrefix {
                        try await logging("Enumerating working set") {
                            for entry in await WorkingSet.instance.entries {
                                log("Working set contains \(entry.path). Will add its contents.")
                                try await addFiles(at: entry.path, to: diff)
                            }
                        }
                    } else {
                        log("Enumerating regular path \(path)")
                        try await addFiles(at: path, to: diff)
                    }
                    let newAnchor = try await publishDiffs(from: diff,
                                                           observer: observer)
                    log("Finish enumerating up to new anchor \(newAnchor)")
                    observer.finishEnumeratingChanges(upTo: newAnchor.identifier,
                                                      moreComing: false)
                    if let syncAnchor = SyncAnchor(anchor) {
                        await SyncCache.instance.expireAnchors(upTo: syncAnchor)
                    }
                } catch {
                    log("Finished with ERROR \(error)")
                    observer.finishEnumeratingWithError(error)
                }
            }
        }
    }

    private func addFiles(fromAnchor anchor: NSFileProviderSyncAnchor,
                          to diff: FileListDiff) async throws {
        guard let syncAnchor = SyncAnchor(anchor),
            let (_, before) = await dataSource.lookup(anchor: syncAnchor) else {
            throw NSFileProviderError(.syncAnchorExpired)
        }
        log("Add 'before' files from anchor \(anchor.rawValue.stringOrHex): \(before)")
        diff.add(before: Array(before))
    }

    private func addFiles(at path: String,
                          to diff: FileListDiff) async throws {
        let after = try await RemoteService.instance.list(at: path,
                                                          fromPage: nil,
                                                          sort: .byName,
                                                          pageSize: Int.max)
        log("Add 'after' files at \(path): \(after)")
        let root = try? await manager?.getUserVisibleURL(for: .rootContainer)
        diff.add(after: after.files.map { FileProviderItem($0, userVisibleRoot: root) })
    }

    private func publishDiffs(from diff: FileListDiff,
                              observer: NSFileProviderChangeObserver) async throws -> SyncAnchor {
        log("Save all the after files to a new anchor: \(diff.after.map { $0.debugDescription }.joined(separator: ", "))")
        let newAnchor = await dataSource.save(files: diff.after.map { $0.entry },
                                              workingSet: path == RemoteFile.workingSetPrefix)
        log("Computing diffs:")
        log("deletions=\(diff.deletions)")
        observer.didDeleteItems(withIdentifiers: diff.deletions)
        log("updates=\(diff.updates)")
        observer.didUpdate(diff.updates)
        return newAnchor
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        Task {
            let anchor = await dataSource.lastAnchor
            log("Enumerator.currentSyncAnchor called, returning \(anchor?.debugDescription ?? "(nil)"))")
            completionHandler(anchor?.identifier)
        }
    }
}
