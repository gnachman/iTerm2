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

    @objc
    func findBefore(location desiredLocation: Int64) -> [iTermMarkProtocol]

    @objc(enumerateFrom:)
    func enumerate(from location: Int64) -> NSEnumerator
}
@objc(iTermMarkCache)
class MarkCache: NSObject, MarkCacheReading {
    // Contains progenitors
    private var dict = [Int: iTermMarkProtocol]()
    private let sorted = SortedArray<iTermMarkProtocol> { $0 === $1 }

    // A mark might not have a location at the time the cache is created but it could pick one up
    // later. This dictionary maps line to mark for marks that didn't have locations last time
    // they were seen. Marks without locations aren't in `sorted` so range queries will fail to
    // find them. Before performing any operation on `sorted` move marks with entries out
    // of `dropped`.
    private var dropped: [Int: iTermMarkProtocol] = [:]

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
        for i in dict.keys.sorted() {
            if let object = dict[i] {
                NSLog("Line \(i): \(object.description)")
            }
        }
        NSLog("Enumerating sorted array:")
        for mark in enumerate(from: 0) {
            let object = mark as! NSObject
            let ito = mark as! IntervalTreeObject
            NSLog("\(object.description) at \(ito.entry?.interval.description ?? "(No entry)")")
        }
    }

    fileprivate init(dict: [Int: iTermMarkProtocol]) {
        self.dict = dict
        for (key, value) in dict {
            if let location = value.entry?.interval.location {
                value.cachedLocation = location
                sorted.insert(object: value, location: location)
            } else {
                dropped[key] = value
            }
        }
    }

    @objc(removeMark:onLine:)
    func remove(mark: iTermMarkProtocol, line: Int) {
        DLog("\(it_addressString): remove(mark:line:): dirty=true")
        dirty = true
        dict.removeValue(forKey: line)
        dropped.removeValue(forKey: line)
        sorted.remove(entry: .init(value: mark, location: mark.cachedLocation))
    }

    @objc(removeMarks:onLines:)
    func remove(marks: [iTermMarkProtocol], lines: [Int]) {
        DLog("\(it_addressString): remove(marks:lines:): dirty=true")
        dirty = true
        for line in lines {
            dict.removeValue(forKey: line)
            dropped.removeValue(forKey: line)
        }
        sorted.remove(entries: marks.map { .init(value: $0, location: $0.cachedLocation )})
    }

    @objc
    func removeAll() {
        DLog("\(it_addressString): removeAll(): dirty=true")
        dirty = true
        dict = [:]
        dropped = [:]
        sorted.removeAll()
    }

    @objc
    func copy(with zone: NSZone? = nil) -> Any {
        DLog("\(it_addressString): copy(): dirty=false")
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
            DLog("\(it_addressString): markCache[\(line)]=\(newValue?.description ?? "nil")")
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

    private func rescueDroppedMarks() {
        var lines = IndexSet()
        for (line, droppedMark) in dropped {
            if let location = droppedMark.entry?.interval.location {
                DLog("Rescue dropped mark \(droppedMark.description) on line \(line)")
                droppedMark.cachedLocation = location
                sorted.insert(object: droppedMark, location: location)
                lines.insert(line)
            }
        }
        for line in lines {
            dropped.removeValue(forKey: line)
        }
    }

    @objc
    func findAtOrBefore(location desiredLocation: Int64) -> [iTermMarkProtocol] {
        rescueDroppedMarks()
        return sorted.findAtOrBefore(location: desiredLocation)
    }

    @objc
    func findBefore(location desiredLocation: Int64) -> [iTermMarkProtocol] {
        rescueDroppedMarks()
        return sorted.findBefore(location: desiredLocation)
    }

    @objc(eraseUpToLocation:)
    func eraseUpTo(location: Int64) {
        DLog("Erase up to \(location)")
        rescueDroppedMarks()
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

    @objc
    func findBefore(location desiredLocation: Int64) -> [any iTermMarkProtocol] {
        return realized.findBefore(location: desiredLocation)
    }
}
