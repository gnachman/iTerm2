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
    @objc lazy var sanitizingAdapter: MarkCache = {
        return MarkCacheSanitizingAdapter(self)
    }()

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

fileprivate class MarkCacheSanitizingAdapter: MarkCache {
    private weak var source: MarkCache?
    init(_ source: MarkCache) {
        self.source = source
    }

    @objc(remove:)
    override func remove(line: Int) {
        fatalError()
    }

    @objc
    override func removeAll() {
        fatalError()
    }

    @objc
    override func copy(with zone: NSZone? = nil) -> Any {
        fatalError()
    }

    @objc
    override subscript(line: Int) -> iTermMarkProtocol? {
        get {
            guard let source = source else {
                return nil
            }
            let maybeMark: iTermMarkProtocol? = source[line]
            guard let downcast = maybeMark as? iTermMark else {
                return maybeMark
            }
            return downcast.doppelganger() as iTermMarkProtocol
        }
        set {
            fatalError()
        }
    }
}

