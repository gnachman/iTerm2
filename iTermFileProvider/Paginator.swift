//
//  Paginator.swift
//  FileProvider
//
//  Created by George Nachman on 6/8/22.
//

import Foundation
import FileProvider
import FileProviderService

struct Paginator {
    private let path: String
    private let sorting: FileSorting?
    private var service: RemoteService
    private(set) var page: Page
    private let pageSize: Int?

    // A better data type for NSFileProviderPage
    enum Page: CustomDebugStringConvertible {
        case first(FileSorting)
        case later(Data)
        case finished

        var hasMore: Bool {
            switch self {
            case .first(_), .later(_):
                return true
            case .finished:
                return false
            }
        }
        var data: Data? {
            switch self {
            case .first(_), .finished:
                return nil
            case .later(let data):
                return data
            }
        }

        var fileProviderPage: NSFileProviderPage? {
            switch self {
            case .first(.byName):
                return NSFileProviderPage(NSFileProviderPage.initialPageSortedByName as Data)
            case .first(.byDate):
                return NSFileProviderPage(NSFileProviderPage.initialPageSortedByDate as Data)
            case .later(let data):
                return NSFileProviderPage(rawValue: data)
            case .finished:
                return nil
            }
        }

        init(page: NSFileProviderPage) {
            switch page.rawValue as NSData {
            case NSFileProviderPage.initialPageSortedByName:
                self = .first(.byName)
            case  NSFileProviderPage.initialPageSortedByDate:
                self = .first(.byDate)
            default:
                self = .later(page.rawValue as Data)
            }
        }

        var debugDescription: String {
            switch self {
            case .first(.byName):
                return "firstByName"
            case .first(.byDate):
                return "firstByDate"
            case .later(let data):
                return "later(\(data.stringOrHex))"
            case .finished:
                return "finished"
            }
        }

        var description: String {
            return debugDescription
        }
    }

    init(service: RemoteService,
         path: String,
         page: NSFileProviderPage,
         pageSize: Int?) {
        self.service = service
        self.path = path
        self.pageSize = pageSize
        self.sorting = page.remoteServiceFileSorting
        self.page = Page(page: page)
    }

    mutating func get() async throws -> [RemoteFile] {
        precondition(hasMore)
        return try await logging("Paginator.get") {
            log("Request from service: path=\(path), page=\(page.debugDescription), sorting=\(String(describing: sorting)), pageSize=\(String(describing: pageSize)))")
            let result = try await service.list(at: path,
                                                fromPage: page.data,
                                                sort: sorting ?? .byName,
                                                pageSize: pageSize)
            log("result is \(result)")
            if let data = result.nextPage {
                log("set page to .later")
                page = .later(data)
            } else {
                log("set page to .finished")
                page = .finished
            }
            return result.files
        }
    }

    var hasMore: Bool {
        log("Paginator: hasMore returning \(page.hasMore)")
        return page.hasMore
    }
}


