//
//  RootListFileProviderEnumerator.swift
//  iTermFileProvider
//
//  Created by George Nachman on 6/7/22.
//

import Foundation
import FileProvider
import FileProviderService

class RootListFileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let connectionProvider: SSHConnectionProviding
    private var states: [Int: [SSHConnectionIdentifier]] = [:]
    private var anchorNumber = Int(arc4random())

    init(_ connectionProvider: SSHConnectionProviding) {
        logger.debug("Extension: RootListFileProviderEnumerator: init")
        self.connectionProvider = connectionProvider
        super.init()
    }

    func invalidate() {
        states = [:]
        logger.debug("Extension: RootListFileProviderEnumerator: invalidate")
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver,
                        startingAt page: NSFileProviderPage) {
        logger.debug("Extension: RootListFileProviderEnumerator: enumerateItems: enumerate page \(page.rawValue as NSData, privacy: .public)")

        do {
            try fetchAndUpdate { result in
                switch result {
                case .failure(let error):
                    logger.debug("Extension: RootListFileProviderEnumerator: enumerateItems: report error")
                    observer.finishEnumeratingWithError(error)
                    return
                case .success(let connections):
                    let items = connections.map {
                        ConnectionRootFileProviderItem($0)
                    }
                    logger.debug("Extension: RootListFileProviderEnumerator: enumerateItems: provide \(items.count) items")
                    observer.didEnumerate(items)
                }
                logger.debug("Extension: RootListFileProviderEnumerator: enumerateItems: finishEnumerating")
                observer.finishEnumerating(upTo: nil)
            }
        } catch {
            logger.debug("Extension: RootListFileProviderEnumerator: enumerateItems: fail with serverUnreachable because caught \(error.localizedDescription, privacy: .public)")
            observer.finishEnumeratingWithError(NSFileProviderError(.serverUnreachable))
        }
    }

    private func fetchAndUpdate(_ completionHandler: @escaping (Result<[SSHConnectionIdentifier], Error>) -> ()) throws {
        logger.debug("Extension: RootListFileProviderEnumerator: fetchAndUpdate: request connections")
        _ = try connectionProvider.getConnections { result in
            switch result {
            case .failure(let error):
                logger.debug("Extension: RootListFileProviderEnumerator: fetchAndUpdate: request connections failed with \(error.localizedDescription, privacy: .public)")
                break
            case .success(let connections):
                logger.debug("Extension: RootListFileProviderEnumerator: fetchAndUpdate: request connections succeeded with \(connections.count) results")
                self.anchorNumber += 1
                self.states[self.anchorNumber] = connections
            }
            completionHandler(result)
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        do {
            logger.debug("Extension: RootListFileProviderEnumerator: enumerateChanges: fetchAndUpdate")
            try fetchAndUpdate { result in
                switch result {
                case .failure(let error):
                    logger.debug("Extension: RootListFileProviderEnumerator: enumerateChanges: fetchAndUpdate: failed with \(error.localizedDescription, privacy: .public)")
                    observer.finishEnumeratingWithError(error)
                    return
                case .success(let connections):
                    logger.debug("Extension: RootListFileProviderEnumerator: enumerateChanges: fetchAndUpdate: succeeded with \(connections.count) values")
                    let previous = self.states[anchor.intValue ?? -1] ?? []
                    let idsBefore = Set(previous.map { $0.stringIdentifier })
                    let idsAfter = Set(connections.map { $0.stringIdentifier })
                    let deletions = idsBefore.subtracting(idsAfter)
                    let updates = idsAfter.subtracting(idsBefore)

                    observer.didDeleteItems(withIdentifiers: deletions.map { uuid in
                        logger.debug("Extension: RootListFileProviderEnumerator: enumerateChanges: fetchAndUpdate: report deletion of \(uuid, privacy: .public)")
                        let item = previous.first { $0.stringIdentifier == uuid }
                        return ConnectionRootFileProviderItem(item!).itemIdentifier
                    })
                    observer.didUpdate(updates.map { uuid in
                        logger.debug("Extension: RootListFileProviderEnumerator: enumerateChanges: fetchAndUpdate: report update of \(uuid, privacy: .public)")
                        let item = connections.first { $0.stringIdentifier == uuid }
                        return ConnectionRootFileProviderItem(item!)
                    })
                    observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(int: self.anchorNumber),
                                                      moreComing: false)
                }
            }
        } catch {
            logger.debug("Extension: RootListFileProviderEnumerator: enumerateChanges: serverUnreachable")
            observer.finishEnumeratingWithError(NSFileProviderError(.serverUnreachable))
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        logger.debug("Extension: RootListFileProviderEnumerator: currentSyncAnchor returns \(String(self.anchorNumber), privacy: .public)")
        completionHandler(NSFileProviderSyncAnchor(int: anchorNumber))
    }
}

extension NSFileProviderSyncAnchor {
    init(int: Int) {
        self.init("\(int)".data(using: .utf8)!)
    }

    var intValue: Int? {
        guard let string = String(data: rawValue, encoding: .utf8) else {
            return nil
        }
        return Int(string)
    }
}
