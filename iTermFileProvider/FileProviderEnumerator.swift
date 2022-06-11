//
//  FileProviderEnumerator.swift
//  iTermFileProvider
//
//  Created by George Nachman on 6/4/22.
//

import FileProvider
import FileProviderService

protocol FileListingProvider {
    func listFiles(_ path: SSHFilePath) async throws -> [SSHListFilesItem]
}

protocol SSHConnectionProviding {
    func getConnections(_ completionHandler: @escaping (Result<[SSHConnectionIdentifier], Error>) -> ()) throws -> Progress
}

extension NSFileProviderItemIdentifier {
    var sshFilePath: SSHFilePath? {
        return SSHFilePath(rawValue)
    }

    init(sshFilePath: SSHFilePath) {
        self.init(rawValue: sshFilePath.stringIdentifier)
    }
}

class SSHFileItem: NSObject, NSFileProviderItem {
    var parentItemIdentifier: NSFileProviderItemIdentifier
    let sshFilePath: SSHFilePath

    init?(parentItemIdentifier: NSFileProviderItemIdentifier,
          connection: SSHConnectionIdentifier,
          filename: String) {
        let base: FilePath
        if parentItemIdentifier == NSFileProviderItemIdentifier.rootContainer {
            base = FilePath.root
        } else if parentItemIdentifier == NSFileProviderItemIdentifier.trashContainer ||
                    parentItemIdentifier == NSFileProviderItemIdentifier.workingSet {
            return nil
        } else if let parentFilePath = SSHFilePath(parentItemIdentifier.rawValue),
                  parentFilePath.connection == connection {
            base = parentFilePath.path
        } else {
            return nil
        }

        self.parentItemIdentifier = parentItemIdentifier
        sshFilePath = SSHFilePath(connection: connection,
                                  path: base.appendingPathComponent(filename))
    }

    // This assumes the parent item identifier is for a file, not root/trash/working set.
    init(parentItemIdentifier: NSFileProviderItemIdentifier,
         listFileItem: SSHListFilesItem) {
        self.parentItemIdentifier = parentItemIdentifier
        let parentSSHFilePath = parentItemIdentifier.sshFilePath!
        self.sshFilePath = SSHFilePath(
            connection: parentSSHFilePath.connection,
            path: parentSSHFilePath.path.appendingPathComponent(
                listFileItem.path))
    }

    init?(identifier: NSFileProviderItemIdentifier) {
        if identifier == NSFileProviderItemIdentifier.rootContainer ||
            identifier == NSFileProviderItemIdentifier.trashContainer ||
            identifier == NSFileProviderItemIdentifier.workingSet {
            return nil
        }
        guard let path = identifier.sshFilePath else {
            return nil
        }
        parentItemIdentifier = path.parentIdentifier
        sshFilePath = path
    }

    override var debugDescription: String {
        "<SSHFileItem parent=\(parentItemIdentifier.rawValue) sshFilePath=\(sshFilePath)>"
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        return NSFileProviderItemIdentifier(rawValue: sshFilePath.appendingPathComponent(filename).stringIdentifier)
    }

    var filename: String { sshFilePath.path.lastPathComponent }
}

// Enumerates a directory on an ssh server.
class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let fileListingProvider: FileListingProvider
    private let container: SSHFileItem
    private var anchor: NSFileProviderSyncAnchor {
        NSFileProviderSyncAnchor(int: currentVersion)
    }
    private var versions: [NSFileProviderSyncAnchor: [SSHFileItem]] = [:]
    private var currentVersion = 0

    // Enumerates files within container.
    init(container: SSHFileItem,
         fileListingProvider: FileListingProvider) {
        logger.debug("Extension: FileProviderEnumerator\(container, privacy: .public): init")
        self.container = container
        self.fileListingProvider = fileListingProvider
        super.init()
    }

    func invalidate() {
        logger.debug("Extension: FileProviderEnumerator\(self.container, privacy: .public): invalidate")
        // TODO: perform invalidation of server connection if necessary
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        logger.debug("Extension: FileProviderEnumerator\(self.container, privacy: .public): enumerate at \(page.rawValue, privacy: .public)")
        Task {
            do {
                let sshItems = try await fetch()
                logger.debug("Extension: FileProviderEnumerator\(self.container, privacy: .public): enumerate\(page.rawValue, privacy: .public) returning \(sshItems)")
                observer.didEnumerate(sshItems)
                // TODO: Support pagination
                observer.finishEnumerating(upTo: nil)
            } catch let error as NSFileProviderError {
                logger.error(("Extension: FileProviderEnumerator\(self.container, privacy: .public): enumerate\(page.rawValue, privacy: .public) failed with \(error.localizedDescription, privacy: .public)"))
                observer.finishEnumeratingWithError(error)
            } catch {
                logger.error(("Extension: FileProviderEnumerator\(self.container, privacy: .public): enumerate\(page.rawValue, privacy: .public) failed with non-file provide error \(error.localizedDescription, privacy: .public)"))
                observer.finishEnumeratingWithError(NSFileProviderError(.serverUnreachable))
            }
        }
        observer.finishEnumerating(upTo: nil)
    }

    private func fetch() async throws -> [SSHFileItem] {
        let items = try await fileListingProvider.listFiles(container.sshFilePath)
        let sshFileItems = items.map { item in
            return SSHFileItem(parentItemIdentifier: container.itemIdentifier,
                               listFileItem: item)
        }
        currentVersion += 1
        versions[anchor] = sshFileItems
        return sshFileItems
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver,
                          from anchor: NSFileProviderSyncAnchor) {
        logger.debug("Extension: FileProviderEnumerator\(self.container, privacy: .public): enumerateChanges versus anchor \(anchor.rawValue)")
        Task {
            do {
                guard let previousItems = versions[anchor] else {
                    observer.finishEnumeratingWithError(NSFileProviderError(.versionNoLongerAvailable))
                    return
                }
                let sshItems = try await fetch()
                let previous = Set(previousItems)
                let current = Set(sshItems)
                observer.didDeleteItems(withIdentifiers: previous.subtracting(current).map { $0.itemIdentifier })
                observer.didUpdate(Array(current.subtracting(previous)))
                observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
            } catch let error as NSFileProviderError {
                observer.finishEnumeratingWithError(error)
            } catch {
                observer.finishEnumeratingWithError(NSFileProviderError(.serverUnreachable))
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(anchor)
    }
}

