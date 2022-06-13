//
//  ItemCreator.swift
//  FileProvider
//
//  Created by George Nachman on 6/10/22.
//

import Foundation
import FileProvider
import FileProviderService

actor ItemCreator {
    struct Request: CustomDebugStringConvertible {
        let itemTemplate: NSFileProviderItem
        let fields: NSFileProviderItemFields
        let contents: URL?
        let options: NSFileProviderCreateItemOptions
        let request: NSFileProviderRequest
        let progress = Progress()

        var debugDescription: String {
            return "<ItemCreator.Request template=\(itemTemplate.terseDescription) fields=\(fields.description) contents=\(contents.descriptionOrNil) options=\(options.description) request=\(request.description)>"
        }
    }

    struct Item {
        let item: NSFileProviderItem
        let fields: NSFileProviderItemFields
        let shouldFetchContent: Bool
    }

    private let domain: NSFileProviderDomain
    private let manager: NSFileProviderManager
    private let remoteService: RemoteService

    init(domain: NSFileProviderDomain, remoteService: RemoteService) {
        self.domain = domain
        self.remoteService = remoteService
        manager = NSFileProviderManager(for: domain)!
    }

    func create(_ request: Request) async throws -> Item {
        try await logging("create(\(request))") {
            guard let file = RemoteFile(template: request.itemTemplate,
                                        fields: request.fields) else {
                // There isn't an appropriate exception for when we don't support a file
                // type (e.g., aliases).
                throw NSFileProviderError(.noSuchItem)
            }
            let data: Data
            if request.fields.contains(.contents), let url = request.contents {
                data = try Data(contentsOf: url, options: .alwaysMapped)
                log("content=\(data.stringOrHex)")
            } else {
                log("No content - using empty data just in case")
                data = Data()
            }
            
            switch file.kind {
            case .symlink(let target):
                _ = try await remoteService.ln(
                    source: await rebaseLocalFile(manager, path: target),
                    file: file)
            case .folder:
                try await remoteService.mkdir(file)
            case .file(_):
                request.progress.totalUnitCount = Int64(data.count)
                try await remoteService.create(file, content: data)
                request.progress.completedUnitCount = Int64(data.count)
            case .host:
                throw NSFileProviderError(.noSuchItem)  // no appropriate error exists
            }
            return Item(item: await FileProviderItem(file, manager: manager),
                        fields: [],
                        shouldFetchContent: false)
        }
    }
}


extension RemoteFile {
    init?(template: NSFileProviderItem,
          fields: NSFileProviderItemFields) {
        guard let kind = Self.kind(template, fields) else {
            return nil
        }

        self.init(kind: kind,
                  absolutePath: Self.path(template),
                  permissions: Self.permissions(template, fields),
                  ctime: Self.ctime(template, fields),
                  mtime: Self.mtime(template, fields))
    }

    private static func ctime(_ template: NSFileProviderItem,
                              _ fields: NSFileProviderItemFields) -> Date {
        if fields.contains(.creationDate),
            case let creationDate?? = template.creationDate {
            return creationDate
        }
        return Date()
    }

    private static func mtime(_ template: NSFileProviderItem,
                              _ fields: NSFileProviderItemFields) -> Date {
        if fields.contains(.contentModificationDate),
           case let modifiationDate?? = template.contentModificationDate {
            return modifiationDate
        }
        return Date()
    }

    private static func permissions(_ template: NSFileProviderItem,
                                    _ fields: NSFileProviderItemFields) -> Permissions {
        if fields.contains(.fileSystemFlags), let flags = template.fileSystemFlags {
            return Permissions(fileSystemFlags: flags)
        }
        return Permissions(r: true, w: true, x: true)
    }

    private static func path(_ template: NSFileProviderItem) -> String {
        var url = URL(fileURLWithPath: template.parentItemIdentifier.rawValue)
        url.appendPathComponent(template.filename)
        return url.path
    }

    private static func kind(_ template: NSFileProviderItem,
                             _ fields: NSFileProviderItemFields) -> Kind? {
        switch template.contentType {
        case .folder?:
            return .folder

        case .symbolicLink?:
            if fields.contains(.contents),
               case let target?? = template.symlinkTargetPath {
                return .symlink(target)
            }
            log("symlink without target not allowed")
            return nil

        case .aliasFile?:
            log("aliases not supported")
            return nil

        default:
            return .file(FileInfo(size: nil))
        }
    }
}

extension RemoteFile.Permissions {
    init(fileSystemFlags flags: NSFileProviderFileSystemFlags) {
        self.init(r: flags.contains(.userReadable),
                  w: flags.contains(.userWritable),
                  x: flags.contains(.userExecutable))
    }
}
