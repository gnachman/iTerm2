//
//  FileListDiff.swift
//  FileProvider
//
//  Created by George Nachman on 6/8/22.
//

import Foundation
import FileProvider

class FileListDiff {
    var before: [FileProviderItem] = []
    var after: [FileProviderItem] = []

    func add(before: [FileProviderItem]) {
        self.before.append(contentsOf: before)
    }

    func add(after: [FileProviderItem]) {
        self.after.append(contentsOf: after)
    }

    var deletions: [NSFileProviderItemIdentifier] {
        let beforeIDs = before.map { $0.itemIdentifier }
        let afterIDs = after.map { $0.itemIdentifier }
        return Array(Set(beforeIDs).subtracting(afterIDs))
    }
    
    var updates: [NSFileProviderItem] {
        let beforeIDs = before.map { $0.itemIdentifier }
        let afterIDs = after.map { $0.itemIdentifier }
        let ids = Set(afterIDs).subtracting(beforeIDs)
        return after.filter {
            ids.contains($0.itemIdentifier)
        }
    }
}


