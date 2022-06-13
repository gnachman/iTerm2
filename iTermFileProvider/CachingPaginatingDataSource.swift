//
//  CachingPaginatingDataSource.swift
//  FileProvider
//
//  Created by George Nachman on 6/8/22.
//

import Foundation
import FileProvider
import FileProviderService

extension NSFileProviderPage {
    var description: String {
        switch self.rawValue as NSData {
        case NSFileProviderPage.initialPageSortedByDate:
            return "<initial page sorted by date>"
        case NSFileProviderPage.initialPageSortedByName:
            return "<initial page sorted by name>"
        default:
            if let s = String(data: rawValue, encoding: .utf8) {
                return "<page \(s)>"
            }
            return "<page 0x\(rawValue.hexified)>"
        }
    }
}

extension NSFileProviderSyncAnchor {
    var description: String {
        if let s = String(data: rawValue, encoding: .utf8) {
            return s
        }
        return rawValue.hexified
    }
}

extension NSFileProviderItem {
    var terseDescription: String {
        return "<Item \(itemIdentifier.description)>"
    }
}

extension NSFileProviderItemIdentifier {
    var description: String {
        switch self {
        case NSFileProviderItemIdentifier.rootContainer:
            return "[RootContainer]"
        case NSFileProviderItemIdentifier.trashContainer:
            return "[TrashContainer]"
        case NSFileProviderItemIdentifier.workingSet:
            return "[Working]"
        default:
            return rawValue
        }
    }
}

extension NSFileProviderItemVersion {
    open override var description: String {
        return "<version \(contentVersion.stringOrHex) \(metadataVersion.stringOrHex)>"
    }
}

extension NSFileProviderItemFields {
    var description: String {
        let values: [String?] = [
            contains(.contents) ? "contents" : nil,
            contains(.filename) ? "filename" : nil,
            contains(.parentItemIdentifier) ? "parentItemIdentifier" : nil,
            contains(.lastUsedDate) ? "lastUsedDate" : nil,
            contains(.tagData) ? "tagData" : nil,
            contains(.favoriteRank) ? "favoriteRank" : nil,
            contains(.creationDate) ? "creationDate" : nil,
            contains(.contentModificationDate) ? "contentModificationDate" : nil,
            contains(.fileSystemFlags) ? "fileSystemFlags" : nil,
            contains(.extendedAttributes) ? "extendedAttributes" : nil,
        ]
        return "<Fields " + values.compactMap { $0 }.joined(separator: "|") + ">"
    }
}

extension NSFileProviderCreateItemOptions {
    var description: String {
        return "<Options " + [
            contains(.mayAlreadyExist) ? "mayAlreadyExist": nil
        ].compactMap { $0 }.joined(separator: "|") + ">"
    }
}

extension NSFileProviderModifyItemOptions {
    var description: String {
        return "<Options " + [
            contains(.mayAlreadyExist) ? "mayAlreadyExist": nil
        ].compactMap { $0 }.joined(separator: "|") + ">"
    }
}
actor CachingPaginatingDataSource {
    private let path: String
    private var outstandingPages = Set<Data>()
    private var anchors = [AnchorKey: SyncAnchor]()
    private var manager: NSFileProviderManager?

    private struct AnchorKey: Hashable, CustomDebugStringConvertible {
        var path: String
        var nextPage: Data?

        var debugDescription: String {
            return "<AnchorKey path=\(path) nextPage=\(nextPage?.stringOrHex ?? "(nil)")>"
        }
    }

    private struct Request {
        private var paginator: Paginator

        var hasMore: Bool {
            paginator.hasMore
        }

        var page: Data? {
            return paginator.page.data
        }

        mutating func get() async throws -> ([RemoteFile], NSFileProviderPage?) {
            let files = try await paginator.get()
            return (files, paginator.page.fileProviderPage)
        }

        init(service: RemoteService,
             path: String,
             page: NSFileProviderPage,
             pageSize: Int?) {
            paginator = Paginator(service: service,
                                  path: path,
                                  page: page,
                                  pageSize: pageSize)
        }
    }

    init(_ path: String, domain: NSFileProviderDomain) {
        self.path = path
        manager = NSFileProviderManager(for: domain)
    }

    func request(service: RemoteService,
                 path: String,
                 page: NSFileProviderPage,
                 pageSize: Int?,
                 workingSet: Bool) async throws -> ([RemoteFile], NSFileProviderPage?) {
        let descr = "CPDS(\(path)).request(path: \(path), page: \(page.description), pageSize: \(String(describing: pageSize))"
        return try await logging(descr) { () async throws -> ([RemoteFile], NSFileProviderPage?) in
            let task = Task { () async throws -> ([RemoteFile], NSFileProviderPage?) in
                return try await self.reallyRequest(service: service,
                                                    path: path,
                                                    page: page,
                                                    pageSize: pageSize,
                                                    workingSet: workingSet)
            }
            return try await task.value
        }
    }

    private func reallyRequest(service: RemoteService,
                               path: String,
                               page: NSFileProviderPage,
                               pageSize: Int?,
                               workingSet: Bool) async throws -> ([RemoteFile], NSFileProviderPage?) {
        let anchorKey = AnchorKey(path: path, nextPage: page.rawValue)
        log("Anchor key is \(anchorKey)")
        var request = Request(service: service,
                       path: path,
                       page: page,
                       pageSize: pageSize)
        log("Making async request")
        let (files, nextPage) = try await request.get()

        let anchor = await anchor(for: anchorKey, workingSet: workingSet)
        log("Anchor is \(anchor)")
        Task {
            log("Result has files=\(files), nextPage=\(nextPage?.description ?? "(nil)"). Add to cache with anchor \(anchor)")
            let root = try? await manager?.getUserVisibleURL(for: .rootContainer)
            await SyncCache.instance.add(items: files.map { FileProviderItem($0, userVisibleRoot: root) },
                                         toAnchor: anchor)
        }

        self.outstandingPages.insert(page.rawValue)
        log("Add \(page.description) to outstanding pages. It now contains \(self.outstandingPages.map { $0.stringOrHex })")
        // Replace anchor with new one
        let oldAnchorKey = AnchorKey(path: path, nextPage: page.rawValue)
        let newAnchorKey = AnchorKey(path: path, nextPage: nextPage?.rawValue)
        log("Replace old anchor key \(oldAnchorKey) with new anchor key \(newAnchorKey)")
        self.anchors.removeValue(forKey: oldAnchorKey)
        self.anchors[newAnchorKey] = anchor
        if let page = request.page {
            outstandingPages.remove(page)
            log("Remove \(page.stringOrHex) from the cache's outstanding pages. It now contains \(self.outstandingPages.map { $0.stringOrHex })")
        }
        log("Return files=\(files), nextPage=\(nextPage?.description ?? "(nil)")")
        return (files, nextPage)
    }

    private func anchor(for anchorKey: AnchorKey,
                        workingSet: Bool) async -> SyncAnchor {
        if let anchor = anchors[anchorKey] {
            return anchor
        }
        return await Task {
            await SyncCache.instance.reserveAnchor(path: anchorKey.path,
                                                   workingSet: workingSet)
        }.value
    }

    func save(files: [RemoteFile], workingSet: Bool) async -> SyncAnchor {
        return await logging("CPDS(\(path)).save(path: \(path))") {
            let anchor = await SyncCache.instance.reserveAnchor(path: path,
                                                                workingSet: workingSet)
            let key = AnchorKey(path: path, nextPage: nil)
            log("anchors[\(key)] = \(anchor)")
            await Task { anchors[key] = anchor }.value
            let root = try? await manager?.getUserVisibleURL(for: .rootContainer)
            await SyncCache.instance.save(anchor,
                                          workingSet: workingSet,
                                          files: files.map {
                FileProviderItem($0, userVisibleRoot: root)
            })
            return anchor
        }
    }

    func lookup(anchor: SyncAnchor) async -> (Bool, Set<FileProviderItem>)? {
        if anchor.version == 0 {
            return (false, [])
        }
        let result = await Task { await SyncCache.instance.lookup(anchor: anchor) }.value
        log("CPDS(\(path)).lookup(anchor: \(anchor) returning \(String(describing: result))")
        return result
    }

    var lastAnchor: SyncAnchor? {
        get async {
            let value = await Task { await SyncCache.instance.lastAnchor }.value
            log("CPDS(\(path)).lastAnchor returning \(value?.debugDescription ?? "(nil)")")
            return value
        }
    }

    func addItemsToWorkingSetAnchors(_ items: [FileProviderItem]) async {
        await SyncCache.instance.addItemsToWorkingSetAnchors(items)
    }

    func expire(anchor: SyncAnchor) async {
        await SyncCache.instance.expire(anchor: anchor)
    }
}

