//
//  SyncCache.swift
//  FileProvider
//
//  Created by George Nachman on 6/8/22.
//

import Foundation
import FileProvider

actor SyncCache {
    static let instance = SyncCache()

    private var nextVersion = 1
    private var cache: [SyncAnchor: (Bool, Set<FileProviderItem>)] = [:]
    private var lastAnchorForPath: [String: SyncAnchor] = [:]

    private init() {
    }

    var lastAnchor: SyncAnchor? {
        if nextVersion == 0 {
            return nil
        }
        return SyncAnchor(nextVersion - 1)
    }

    func reserveAnchor(path: String, workingSet: Bool) -> SyncAnchor {
        let anchor = SyncAnchor(nextVersion)
        nextVersion += 1
        cache[anchor] = (workingSet, [])
        log("SyncCache: reserved anchor \(anchor) for path \(path)")
        if !workingSet {
            log("Save anchor \(anchor) as last for \(path)")
            lastAnchorForPath[path] = anchor
        }
        return anchor
    }

    func add(items: [FileProviderItem], toAnchor anchor: SyncAnchor) {
        logging("SyncCache.add(\(items.count) items, toAnchor: \(anchor))") {
            guard let (workingSet, existingItems) = cache[anchor] else {
                log("No entry in cache for this anchor")
                return
            }
            save(anchor, workingSet: workingSet, files: existingItems + items)
        }
    }

    func lookup(anchor: SyncAnchor) -> (Bool, Set<FileProviderItem>)? {
        return cache[anchor]
    }

    func invalidate() {
        cache.removeAll()
    }

    func save(_ anchor: SyncAnchor,
              workingSet: Bool,
              files: [FileProviderItem]) {
        log("SyncCache.save(anchor: \(anchor), workingSet: \(workingSet), files: \(files))")
        cache[anchor] = (workingSet, Set(files))
    }

    func addItemsToWorkingSetAnchors(_ items: [FileProviderItem]) async {
        let keys = cache.keys.filter { key in
            cache[key]?.0 ?? false
        }
        for key in keys {
            var (_, set) = cache[key]!
            log("Add to old working-set anchor \(key.version): \(items)")
            set.formUnion(items)
            cache[key] = (true, set)
        }
    }

    func expire(anchor: SyncAnchor) {
        log("Expire anchor \(anchor)")
        cache.removeValue(forKey: anchor)
    }
    
    func expireAnchors(upTo anchor: SyncAnchor) {
        cache = cache.filter { entry in
            entry.key.version > anchor.version
        }
    }
}
