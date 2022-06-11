//
//  ItemDeleter.swift
//  FileProvider
//
//  Created by George Nachman on 6/11/22.
//

import Foundation
import FileProvider

extension NSFileProviderDeleteItemOptions {
    var description: String {
        return "<Options " + [
            contains(.recursive) ? "recursive" : nil
        ].compactMap { $0 }.joined(separator: "|") + ">"
    }
}

actor ItemDeleter {
    private let domain: NSFileProviderDomain
    private let manager: NSFileProviderManager

    struct Request: CustomDebugStringConvertible {
        var identifier: NSFileProviderItemIdentifier
        var version: NSFileProviderItemVersion
        var options: NSFileProviderDeleteItemOptions
        var request: NSFileProviderRequest

        var debugDescription: String {
            return "<Request \(identifier.rawValue) version=\(version.description) options=\(options.description) request=\(request.description)>"
        }
    }

    init(domain: NSFileProviderDomain) {
        self.domain = domain
        manager = NSFileProviderManager(for: domain)!
    }

    func delete(_ file: RemoteFile, request: Request) async throws {
        try await RemoteService.instance.delete(file,
                                                recursive: request.options.contains(.recursive))
    }
}
