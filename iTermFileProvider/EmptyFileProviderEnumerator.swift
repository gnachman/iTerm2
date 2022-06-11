//
//  EmptyFileProviderEnumerator.swift
//  iTermFileProvider
//
//  Created by George Nachman on 6/7/22.
//

import Foundation
import FileProvider
import FileProviderService

class EmptyFileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    func invalidate() {
        logger.debug("Extension: EmptyFileProviderEnumerator: invalidate")
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver,
                        startingAt page: NSFileProviderPage) {
        logger.debug("Extension: EmptyFileProviderEnumerator: enumerateItems: enumerate page \(page.rawValue as NSData, privacy: .public)")
        observer.didEnumerate([])
        observer.finishEnumerating(upTo: nil)
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        logger.debug("Extension: EmptyFileProviderEnumerator: enumerateChanges")
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        logger.debug("Extension: EmptyFileProviderEnumerator: currentSyncAnchor")
        completionHandler(NSFileProviderSyncAnchor(Data()))
    }
}
