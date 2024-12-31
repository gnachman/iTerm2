//
//  NSString+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 12/31/24.
//

import AppKit

fileprivate class StringSizeCache {
    static let instance: StringSizeCache = StringSizeCache()
    struct Key: Hashable {
        var string: NSString
        var attributes: NSDictionary
    }
    private var dict = LRUDictionary<Key, CGSize>(maximumSize: 1024)

    func fetch(for key: Key) -> CGSize? {
        return dict[key]
    }

    func insert(key: Key, value: CGSize) {
        _ = dict.insert(key: key, value: value, cost: 1)
    }
}

@objc
extension NSString {
    @objc(it_cachingSizeWithAttributes:)
    func it_cachingSize(attributes: NSDictionary) -> CGSize {
        let cache = StringSizeCache.instance
        let key = StringSizeCache.Key(string: self, attributes: attributes)
        if let size = cache.fetch(for: key) {
            return size
        }
        let size = size(withAttributes: (attributes as! [NSAttributedString.Key: Any]))
        cache.insert(key: key, value: size)
        return size
    }
}
