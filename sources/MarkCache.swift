//
//  MarkCache.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/27/22.
//

import Foundation

@objc(iTermMarkCacheReading)
protocol MarkCacheReading: AnyObject {
    @objc
    subscript(line: Int) -> iTermMarkProtocol? {
        get
    }
}

@objc(iTermMarkCache)
class MarkCache: NSObject, NSCopying, MarkCacheReading {
    private var dict = [Int: iTermMarkProtocol]()
    @objc private(set) var dirty = false

    @objc
    override init() {
        super.init()
    }

    private init(dict: [Int: iTermMarkProtocol]) {
        self.dict = dict.mapValues({ value in
            value.doppelganger() as! iTermMarkProtocol
        })
    }

    @objc(remove:)
    func remove(line: Int) {
        dirty = true
        dict.removeValue(forKey: line)
    }

    @objc
    func removeAll() {
        dirty = true
        dict = [:]
    }

    @objc
    func copy(with zone: NSZone? = nil) -> Any {
        dirty = false
        return MarkCache(dict: dict)
    }

    @objc
    subscript(line: Int) -> iTermMarkProtocol? {
        get {
            return dict[line]
        }
        set {
            dirty = true
            if let newValue = newValue {
                dict[line] = newValue
            } else {
                dict.removeValue(forKey: line)
            }
        }
    }
}
