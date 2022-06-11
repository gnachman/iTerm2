//
//  SyncAnchor.swift
//  FileProvider
//
//  Created by George Nachman on 6/8/22.
//

import Foundation
import FileProvider

struct SyncAnchor: Hashable, CustomDebugStringConvertible {
    var version: Int
    var identifier: NSFileProviderSyncAnchor {
        NSFileProviderSyncAnchor(String(version).data(using: .utf8)!)
    }

    init(_ version: Int) {
        self.version = version
    }

    init?(_ external: NSFileProviderSyncAnchor) {
        guard let s = String(data: external.rawValue, encoding: .utf8),
              let i = Int(s) else {
            return nil
        }
        version = i
    }

    var debugDescription: String {
        return "<SyncAnchor version=\(version)>"
    }
}
