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

    @objc
    func findAtOrBefore(location desiredLocation: Int64) -> [iTermMarkProtocol]

    @objc(enumerateFrom:)
    func enumerate(from location: Int64) -> NSEnumerator
}

@objc(iTermMarkCache)
class MarkCache: NSObject, NSCopying, MarkCacheReading {
    private var dict = [Int: iTermMarkProtocol]()
    private let sorted = SortedArray<iTermMarkProtocol>(location: { mark in
        mark.entry?.interval.location
    }, equals: { lhs, rhs in
        lhs === rhs
    })

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
        for value in dict.values {
            sorted.insert(object: value)
        }
    }

    @objc(removeMark:onLine:)
    func remove(mark: iTermMarkProtocol, line: Int) {
        dirty = true
        dict.removeValue(forKey: line)
        sorted.remove(object: mark)
    }

    @objc
    func removeAll() {
        dirty = true
        dict = [:]
        sorted.removeAll()
    }

    @objc
    func copy(with zone: NSZone? = nil) -> Any {
        dirty = false
        return MarkCache(dict: dict)
    }

    @objc(enumerateFrom:)
    func enumerate(from location: Int64) -> NSEnumerator {
        return iTermSortedArrayEnumerator(nextProvider: sorted.itemsFrom(location: location))
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
                sorted.insert(object: newValue)
            } else {
                if let mark = dict[line] {
                    sorted.remove(object: mark)
                }
                dict.removeValue(forKey: line)
            }
        }
    }

    @objc
    func findAtOrBefore(location desiredLocation: Int64) -> [iTermMarkProtocol] {
        return sorted.findAtOrBefore(location: desiredLocation)
    }
}

fileprivate class MarkCacheSanitizingAdapter: MarkCache {
    private weak var source: MarkCache?
    init(_ source: MarkCache) {
        self.source = source
    }

    @objc(removeMark:onLine:)
    override func remove(mark: iTermMarkProtocol, line: Int) {
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

