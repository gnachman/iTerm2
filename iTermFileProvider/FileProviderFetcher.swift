//
//  FileProviderFetcher.swift
//  FileProvider
//
//  Created by George Nachman on 6/10/22.
//

import Foundation
import FileProvider

actor FileProviderFetcher {
    private let temporaryDirectoryURL: URL
    private let domain: NSFileProviderDomain

    struct FetchRequest: CustomDebugStringConvertible {
        let itemIdentifier: NSFileProviderItemIdentifier
        let requestedVersion: NSFileProviderItemVersion?
        let request: NSFileProviderRequest

        var debugDescription: String {
            return "<FetchRequest \(itemIdentifier.rawValue)>"
        }
    }

    init(domain: NSFileProviderDomain) {
        self.domain = domain
        let manager = NSFileProviderManager(for: domain)!
        temporaryDirectoryURL = try! manager.temporaryDirectoryURL()
    }

    func fetchContents(_ request: FetchRequest,
                       progress: Progress) async throws -> URL {
        return try await logging("Fetch \(request)") {
            let path = request.itemIdentifier.rawValue
            let destination = makeTemporaryURL("fetch")
            log("Destination will be \(destination)")
            _ = try await Task {
                FileManager.default.createFile(atPath: destination.path, contents: nil)
                let handle = try FileHandle(forWritingTo: destination)
                let rs = RemoteService.instance
                let stream = await rs.fetch(path)
                log("Beginning collecting chunks")
                for await update in stream {
                    switch update {
                    case .failure(let error):
                        log("Error during fetch: \(error)")
                        throw error
                    case .success(let data):
                        log("Received \(data.count) bytes")
                        try handle.write(contentsOf: data)
                        progress.completedUnitCount += Int64(data.count)
                        log("Completed unit count is now \(progress.completedUnitCount)")
                    }
                    log("Continue for await loop")
                }
                try handle.close()
            }.value
            return destination
        }
    }

    private func makeTemporaryURL(_ purpose: String, _ ext: String? = nil) -> URL {
        var parts = [purpose, "-", UUID().uuidString]
        if let ext = ext {
            parts.append("." + ext)
        }
        let filename = parts.joined(separator: "")
        return temporaryDirectoryURL.appendingPathComponent(filename)
    }
}
