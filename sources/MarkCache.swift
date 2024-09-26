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
class MarkCache: NSObject, MarkCacheReading {
    // Contains progenitors
    private var dict = [Int: iTermMarkProtocol]()
    private let sorted = SortedArray<iTermMarkProtocol> { $0 === $1 }

    @objc private(set) var dirty = false

    override var description: String {
        let dictDescription = dict.keys.sorted().map {
            "\($0)=\(type(of: dict[$0]!))"
        }.joined(separator: " ")
        return "<MarkCache: \(it_addressString) dict:\n\(dictDescription)\nsorted=\(sorted.debugDescription)>"
    }
    @objc
    override init() {
        super.init()
    }

    @objc
    func dump() {
        for mark in enumerate(from: 0) {
            let object = mark as! NSObject
            let ito = mark as! IntervalTreeObject
            NSLog("\(object.description) at \(ito.entry?.interval.description ?? "(No entry)")")
        }
    }

    fileprivate init(dict: [Int: iTermMarkProtocol]) {
        self.dict = dict
        for value in dict.values {
            if let location = value.entry?.interval.location {
                value.cachedLocation = location
                sorted.insert(object: value, location: location)
            }
        }
    }

    @objc(removeMark:onLine:)
    func remove(mark: iTermMarkProtocol, line: Int) {
        dirty = true
        dict.removeValue(forKey: line)
        sorted.remove(entry: .init(value: mark, location: mark.cachedLocation))
    }

    @objc(removeMarks:onLines:)
    func remove(marks: [iTermMarkProtocol], lines: [Int]) {
        dirty = true
        for line in lines {
            dict.removeValue(forKey: line)
        }
        sorted.remove(entries: marks.map { .init(value: $0, location: $0.cachedLocation )})
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
                if let location = newValue.entry?.interval.location {
                    newValue.cachedLocation = location
                    sorted.insert(object: newValue, location: location)
                }
            } else {
                if let mark = dict[line] {
                    sorted.remove(entry: .init(value: mark, location: mark.cachedLocation))
                }
                dict.removeValue(forKey: line)
            }
        }
    }

    @objc
    func findAtOrBefore(location desiredLocation: Int64) -> [iTermMarkProtocol] {
        return sorted.findAtOrBefore(location: desiredLocation)
    }

    @objc(eraseUpToLocation:)
    func eraseUpTo(location: Int64) {
        DLog("Erase up to \(location)")
        sorted.removeUpTo(location: location)
    }

    @objc
    func readOnlyCopy() -> ReadOnlyMarkCache {
        defer {
            dirty = false
        }
        return ReadOnlyMarkCache(progenitorDict: dict)
    }
}

// This solves the problem that new marks are created this way:
//
// 1. Construct mark, add to mutable state's interval tree, add to mutable state's mark cache.
// 2. Enqueue a side-effect to add the mark to the main thread's interval tree
// 3. Sync mutable state to readonly state. A copy of the mark cache is made. But at this time
//    doppelgangers won't have entries because the side effect from the previous step didn't execute
//    yet.
// *** At this point it is unsafe to use the main thread's mark cache because without entries in
// *** doppelgangers, it doesn't have a correct sorted list of marks.
// 4. Side effects execute and the main thread's interval tree has doppelgangers added.
// 5. Main thread makes read-only access to the mark cache.
//
// In order to defer accessing doppelgangers' entries before they are added to the main thread's
// mark cache, this placeholder keeps references to progenitors from which a good mark cache could
// be created.
@objc(iTermReadOnlyMarkCache)
class ReadOnlyMarkCache: NSObject, MarkCacheReading {
    private var dict: [Int: iTermMarkProtocol]
    private var realInstance: MarkCache?

    init(progenitorDict: [Int: iTermMarkProtocol]) {
        // Get doppelgangers right away to remove any chance of the first chance of access to the
        // mark cache being after a progenitor mutates.
        self.dict = progenitorDict.mapValues({ mark in
            if mark.isDoppelganger {
                return mark
            } else {
                return mark.doppelganger()
            }
        })
    }

    private var realized: MarkCache {
        if let realInstance {
            return realInstance
        }
        let instance = MarkCache(dict: dict)
        realInstance = instance
        return instance
    }

    override var description: String {
        realInstance?.description ?? "Unrealized"
    }

    @objc(enumerateFrom:)
    func enumerate(from location: Int64) -> NSEnumerator {
        return realized.enumerate(from: location)
    }

    @objc
    subscript(line: Int) -> iTermMarkProtocol? {
        get {
            return realized[line]
        }
        set {
            realized[line] = newValue
        }
    }

    @objc
    func findAtOrBefore(location desiredLocation: Int64) -> [iTermMarkProtocol] {
        return realized.findAtOrBefore(location: desiredLocation)
    }
}
