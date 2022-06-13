//
//  NSFileProviderPage+Additions.swift
//  FileProvider
//
//  Created by George Nachman on 6/8/22.
//

import Foundation
import FileProvider
import FileProviderService

extension NSFileProviderPage {
    var remoteServiceFileSorting: FileSorting? {
        switch rawValue as NSData {
        case NSFileProviderPage.initialPageSortedByName:
            return .byName
        case  NSFileProviderPage.initialPageSortedByDate:
            return .byDate
        default:
            return nil
        }
    }
}

