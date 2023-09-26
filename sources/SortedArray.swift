//
//  SortedArray.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/24/23.
//

import Foundation

@objc
protocol iTermSortedArrayReading: AnyObject {
    func findAtOrBefore(location desiredLocation: Int64) -> [NSObject]
}

@objc(iTermSortedArray)
class iTermSortedArray: NSObject, iTermSortedArrayReading {
    private var impl: SortedArray<NSObject>
       
    @objc(initWithLocationProvider:)
    init(location: @escaping (NSObject) -> NSNumber?) {
        impl = SortedArray(location: {
            location($0)?.int64Value
        }, equals: { return NSObject.object($0, isEqualTo: $1) })
    }
    
    @objc
    func findAtOrBefore(location desiredLocation: Int64) -> [NSObject] {
        return impl.findAtOrBefore(location: desiredLocation)
    }
    
    @objc
    func insert(object: NSObject) {
        impl.insert(object: object)
    }
    
    @objc
    func remove(object: NSObject) {
        impl.remove(object: object)
    }
    
    @objc
    func removeAll() {
        impl.removeAll()
    }
}

protocol NextProviding {
    mutating func nextItem() -> Any?
}

@objc(iTermSortedArrayEnumerator)
class iTermSortedArrayEnumerator: NSEnumerator {
    private var nextProvider: NextProviding

    init(nextProvider: NextProviding) {
        self.nextProvider = nextProvider
    }

    override func nextObject() -> Any? {
        return nextProvider.nextItem()
    }
}

// Holds an array of objects in sorted order.
class SortedArray<T> {
    private var array: [T] = []

    // Converts a value to its sort key.
    private var location: (T) -> Int64?
    
    // Compares two values for equality.
    private var equals: (T, T) -> Bool
    
    init(location: @escaping (T) -> Int64?,
         equals: @escaping (T, T) -> Bool) {
        self.location = location
        self.equals = equals
    }

    func removeAll() {
        array = []
    }
    
    private func firstIndexAtOrBefore(location desiredLocation: Int64) -> Int? {
        var start = 0
        var end = array.count - 1
        var mid = -1
        var index = -1
        
        while start <= end {
            mid = (start + end) / 2
            if let midLocation = self.location(array[mid]) {
                if midLocation > desiredLocation {
                    end = mid - 1
                } else {
                    // Found it
                    start = mid + 1
                    index = mid
                }
            } else {
                end = mid - 1
            }
        }
        if index < 0 {
            return nil
        }
        // Go backward to the first with this location
        let l = location(array[index])!
        while index > 0 && index < array.count && (location(array[index - 1]) == nil || location(array[index - 1]) == l) {
            index -= 1
        }
        return index
    }

    private func firstIndexAtOrAfter(location desiredLocation: Int64) -> Int? {
        var start = 0
        var end = array.count - 1
        var mid = -1
        var index = -1

        while start <= end {
            mid = (start + end) / 2
            if let midLocation = self.location(array[mid]) {
                if midLocation < desiredLocation {
                    start = mid + 1
                } else {
                    // Found it
                    end = mid - 1
                    index = mid
                }
            } else {
                start = mid + 1
            }
        }
        if index < 0 {
            return nil
        }
        // Go backward to the first with this location
        let l = location(array[index])!
        while index > 0 && index < array.count && (location(array[index - 1]) == nil || location(array[index - 1]) == l) {
            index -= 1
        }
        return index
    }

    struct ForwardIterator: IteratorProtocol, NextProviding {      
        private let array: [T]
        private var currentIndex: Int

        init(array: [T], currentIndex: Int) {
            self.array = array
            self.currentIndex = currentIndex
        }

        mutating func next() -> T? {
            guard currentIndex < array.count else {
                return nil
            }
            defer {
                currentIndex += 1
            }
            return array[currentIndex]
        }
        
        mutating func nextItem() -> Any? {
            return next()
        }
    }

    func itemsFrom(location startLocation: Int64) -> ForwardIterator {
        let startIndex = firstIndexAtOrAfter(location: startLocation) ?? array.count
        return ForwardIterator(array: array, currentIndex: startIndex)
    }

    func findAtOrBefore(location desiredLocation: Int64) -> [T] {
        if var index = firstIndexAtOrBefore(location: desiredLocation) {
            // Add all until we get past the desired location
            var result = [T]()
            while index < array.count && (location(array[index]) ?? Int64.min) <= desiredLocation {
                if location(array[index]) != nil {
                    result.append(array[index])
                }
                index += 1
            }
            return result
        } else {
            return []
        }
    }

    func insert(object: T) {
        if let location = location(object) {
            var start = 0
            var end = array.count
            var mid: Int

            while start < end {
                mid = (start + end) / 2
                if let midLocation = self.location(array[mid]) {
                    if midLocation < location {
                        start = mid + 1
                    } else {
                        end = mid
                    }
                } else {
                    end = mid
                }
            }
            array.insert(object, at: start)
        } else {
            DLog("Declining to insert object \(object) that has a nil location")
        }
    }

    func remove(object: T) {
        if let desiredLocation = location(object), var i = firstIndexAtOrBefore(location: desiredLocation) {
            while i < array.count {
                guard let l = location(array[i]) else {
                    continue
                }
                if l > desiredLocation {
                    return
                }
                if l == desiredLocation && equals(array[i], object) {
                    array.remove(at: i)
                    return
                }
                i += 1
            }
        }
    }
}
