//
//  ItemModifier.swift
//  FileProvider
//
//  Created by George Nachman on 6/10/22.
//

import Foundation
import FileProvider
import FileProviderService

actor ItemModifier {
    private let domain: NSFileProviderDomain
    private let manager: NSFileProviderManager
    private let remoteService: RemoteService

    struct Request {
        let item: NSFileProviderItem
        let version: NSFileProviderItemVersion
        let changedFields: NSFileProviderItemFields
        let contents: URL?
        let options: NSFileProviderModifyItemOptions
        let request: NSFileProviderRequest
        let progress = Progress()
    }

    struct Output {
        var item: NSFileProviderItem?
        var fields: NSFileProviderItemFields
        var shouldFetchContent: Bool
    }

    init(domain: NSFileProviderDomain, remoteService: RemoteService) {
        self.domain = domain
        self.remoteService = remoteService
        manager = NSFileProviderManager(for: domain)!
    }

    func modify(_ remoteFile: RemoteFile, request: Request) async throws -> Output {
        if request.changedFields.contains(.contents), let url = request.contents {
            let updated = try await replaceContents(remoteFile,
                                                    item: request.item,
                                                    url: url)
            return Output(item: await FileProviderItem(updated, manager: manager),
                          fields: request.changedFields.removing(.contents),
                          shouldFetchContent: true)
        }
        if request.changedFields.contains(.parentItemIdentifier) ||
            request.changedFields.contains(.filename) {
            try await manager.waitForChanges(below: request.item.itemIdentifier)
            let updated = try await remoteService.mv(
                file: remoteFile,
                newParent: request.item.parentItemIdentifier.rawValue,
                newName: request.item.filename)
            return Output(item: await FileProviderItem(updated, manager: manager),
                          fields: request.changedFields.removing(.parentItemIdentifier).removing(.filename),
                          shouldFetchContent: false)
        }
        if request.changedFields.contains(.contentModificationDate),
           case let date?? = request.item.contentModificationDate {
            let updated = try await remoteService.setModificationDate(remoteFile, date: date)
            return Output(item: await FileProviderItem(updated, manager: manager),
                          fields: request.changedFields.removing(.contentModificationDate),
                          shouldFetchContent: false)
        }
        if request.changedFields.contains(.fileSystemFlags),
           case let flags? = request.item.fileSystemFlags {
            let updated = try await remoteService.chmod(
                remoteFile,
                permissions: RemoteFile.Permissions(fileSystemFlags: flags))
            return Output(item: await FileProviderItem(updated, manager: manager),
                          fields: request.changedFields.removing(.fileSystemFlags),
                          shouldFetchContent: false)
        }
        return Output(item: nil, fields: request.changedFields, shouldFetchContent: true)
    }

    func replaceContents(_ remoteFile: RemoteFile, item: NSFileProviderItem, url: URL?) async throws -> RemoteFile {
        switch remoteFile.kind {
        case .folder, .host:
            throw CocoaError(.fileWriteInvalidFileName)
        case .file(_):
            guard let url = url else {
                throw NSFileProviderError(.noSuchItem)
            }
            return try await remoteService.replaceContents(remoteFile,
                                                                    item: item,
                                                                    url: url)
        case .symlink(_):
            guard case let target?? = item.symlinkTargetPath else {
                throw CocoaError(.fileWriteInvalidFileName)
            }

            return try await remoteService.ln(source: await rebaseLocalFile(manager,
                                                                            path: target),
                                              file: remoteFile)
        }
    }
}

extension OptionSet {
    func removing(_ element: Element) -> Self {
        var temp = self
        temp.remove(element)
        return temp
    }
}
