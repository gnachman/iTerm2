//
//  iTermLargeContent.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/18/26.
//

import Foundation

private let kLazyMarkerKey = "__lazy"
private let kLazyRowIDKey = "__lazy_rowid"

/// Protocol for fetching large content data on demand.
/// iTermGraphDatabase conforms to this protocol.
@objc(iTermLargeContentProvider)
protocol LargeContentProvider {
    /// Load large content data for a given metadata dictionary.
    /// - Parameter metadata: Dictionary containing rowid and other info needed to fetch data
    /// - Returns: The large content dictionary, or nil if unavailable
    func loadLargeContent(withMetadata metadata: [AnyHashable: Any]) -> [AnyHashable: Any]?
}

/// Helper class for creating and parsing large content metadata.
@objcMembers
class iTermLargeContentMetadata: NSObject {
    /// Key used for large content nodes in graph encoding.
    @objc static let largeContentKey = "__large_content"

    /// Check if metadata represents deferred large content.
    @objc(isLargeContentMetadata:)
    static func isLargeContentMetadata(_ dict: [AnyHashable: Any]) -> Bool {
        (dict[kLazyMarkerKey] as? Bool) ?? false
    }

    /// Create metadata for lazy loading.
    @objc(metadataForRowID:)
    static func metadata(forRowID rowid: NSNumber?) -> [AnyHashable: Any] {
        [kLazyMarkerKey: true, kLazyRowIDKey: rowid ?? 0]
    }

    /// Extract rowid from metadata.
    @objc(rowidFromMetadata:)
    static func rowid(from metadata: [AnyHashable: Any]) -> NSNumber? {
        metadata[kLazyRowIDKey] as? NSNumber
    }
}
