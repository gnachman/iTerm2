//
//  iTermServerDeleter.swift
//  iTerm2
//
//  Created by George Nachman on 7/11/22.
//

import Foundation

@objc
class iTermServerName: NSObject {
    @objc static var name: String {
        if let versionNumber = Bundle(for: Self.self).infoDictionary?[kCFBundleVersionKey as String] as? String {
            return "iTermServer-\(versionNumber)"
        }
        return "iTermServer-nil"
    }
}

@objc
@available(macOS 10.15, *)
class iTermServerDeleter: NSObject {
    static var started = false
    @objc static func deleteDisusedServers(in folders: [String],
                                           provider: ProcessCollectionProvider) {
        if started {
            return
        }
        started = true
        let instance = iTermServerDeleter(folders, provider: provider)
        Task {
            instance.delete()
        }
    }

    private let folders: [String]
    private let provider: ProcessCollectionProvider

    init(_ folders: [String], provider: ProcessCollectionProvider) {
        self.folders = folders
        self.provider = provider
    }

    func delete() {
        let files = folders.flatMap { folder -> [String] in
            let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: folder),
                                                            includingPropertiesForKeys: nil,
                                                            options: [
                                                                .skipsSubdirectoryDescendants,
                                                                .skipsPackageDescendants,
                                                                .skipsHiddenFiles
                                                            ]) { _, _ in return false }
            var result = [String]()
            let mine = iTermServerName.name
            while let url = enumerator?.nextObject() as? URL {
                let filename = url.lastPathComponent
                guard filename.hasPrefix("iTermServer-") else {
                    continue
                }
                if filename == mine {
                    continue
                }
                result.append(url.path)
            }
            return result
        }
        let inuse = Set(provider.processIDs.compactMap { pid in
            provider.info(forProcessID: pid)?.executable
        })
        let toremove = Set(files).subtracting(Set(inuse))
        for file in toremove {
            do {
                try FileManager.default.removeItem(atPath: file)
            } catch {
                DLog("Failed to delete \(file): \(error)")
            }
        }
    }
}

extension String {
    func appendingPathComponent(_ component: String) -> String {
        return (self as NSString).appendingPathComponent(component) as String
    }
}
