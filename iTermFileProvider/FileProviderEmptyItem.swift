//
//  FileProviderEmptyItem.swift
//  iTermFileProvider
//
//  Created by George Nachman on 6/7/22.
//

import Foundation
import FileProvider

class FileProviderEmptyItem: NSObject, NSFileProviderItem {
    var itemIdentifier: NSFileProviderItemIdentifier
    var parentItemIdentifier: NSFileProviderItemIdentifier
    var filename: String

    init(itemIdentifier: NSFileProviderItemIdentifier,
         parentItemIdentifier: NSFileProviderItemIdentifier,
         filename: String) {
        self.itemIdentifier = itemIdentifier
        self.parentItemIdentifier = parentItemIdentifier
        self.filename = filename
    }
}
