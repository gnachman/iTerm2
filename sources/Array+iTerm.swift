//
//  Array+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/19/22.
//

import Foundation

extension Array {
    func anySatisfies(_ closure: (Element) throws -> Bool) rethrows -> Bool {
        return try first { try closure($0) } != nil
    }
}

extension Array where Element: Comparable {
    func endsWith(_ other: [Element]) -> Bool {
        if other.isEmpty {
            return true
        }
        if other.count > count {
            return false
        }
        var i = count - 1
        var j = other.count - 1
        while i >= 0 && j >= 0 {
            if self[i] != other[j] {
                return false
            }
            i -= 1
            j -= 1
        }
        return true
    }
}

extension Array where Element == URL {
    var splitPaths: [[String]] {
        return map { (url: URL) -> [String] in return url.pathComponents }
    }

    var hasCommonPathPrefix: Bool {
        return splitPaths.lengthOfLongestCommonPrefix > 1
    }

    var commonPathPrefix: String {
        let components = splitPaths.longestCommonPrefix
        return components.reduce(URL(fileURLWithPath: "")) { (partialResult, component) -> URL in
            if component == "/" {
                return partialResult
            }
            return partialResult.appendingPathComponent(component)
        }.path
    }
}

@objc
extension NSArray {
    @objc var longestCommonStringPrefix: String {
        guard let converted = self as? [String] else {
            return ""
        }
        let length = converted.lengthOfLongestCommonPrefix
        if length == 0 {
            return ""
        }
        let firstStringAsCollection = AnyCollection(converted.first!)
        let subsequence = firstStringAsCollection.prefix(length)
        return String(subsequence)

    }
}

extension Array where Element: RandomAccessCollection, Element.Index == Int, Element.Element: Comparable {
    var lengthOfLongestCommonPrefix: Int {
        if isEmpty {
            return 0
        }
        var i = 0
        while true {
            let trying = i + 1
            guard allSatisfy({ $0.count >= trying }) else {
                return i
            }
            let prefix = self.first![0..<trying]
            guard allSatisfy({ $0.starts(with: prefix) }) else {
                return i
            }
            i = trying
        }
    }

    var longestCommonPrefix: [Element.Element] {
        if isEmpty {
            return []
        }
        let length = lengthOfLongestCommonPrefix
        if length == 0 {
            return []
        }
        let subsequence: Element.SubSequence = self[0][0..<length]
        return Array<Element.Element>(subsequence)
    }
}

extension Array where Element: Collection, Element.Element: Comparable {
    var lengthOfLongestCommonPrefix: Int {
        if isEmpty {
            return 0
        }
        if count == 1 {
            return self[0].count
        }
        var i = 0
        while i < 1024 {
            let trying = i + 1
            let firstCollection = AnyCollection(self.first!)
            guard allSatisfy({ AnyCollection($0).count >= trying }) else {
                return i
            }
            let prefix = firstCollection.prefix(trying)
            guard allSatisfy({ AnyCollection($0).starts(with: prefix) }) else {
                return i
            }
            i = trying
        }
        return 0
    }

    var longestCommonPrefix: [Element.Element] {
        if isEmpty {
            return []
        }
        let length = lengthOfLongestCommonPrefix
        if length == 0 {
            return []
        }
        let firstCollection = AnyCollection(self.first!)
        let subsequence = firstCollection.prefix(length)
        return Array<Element.Element>(subsequence)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? {
        if i < 0 || i >= count {
            return nil
        }
        return self[i]
    }
}

extension Array {
    func withoutDuplicates<T: Hashable>(by: (Element) -> T) -> [Element] {
        var existing = Set<T>()
        var result = [Element]()
        for element in self {
            let key = by(element)
            if !existing.contains(key) {
                result.append(element)
                existing.insert(key)
            }
        }
        return result
    }
}

extension Array {
    mutating func remove(at indexes: IndexSet) {
        self = Array(enumerated().reversed().filter { tuple in
            let (index, _) = tuple
            return !indexes.contains(index)
        }.map {
            $0.element
        }.reversed())
    }
}

extension Array {
    subscript (indexes: IndexSet) -> [Element] {
        return indexes.map { self[$0] }
    }
}

extension Array {
    func get(_ index: Index, default defaultValue: Element) -> Element {
        if index < endIndex {
            return self[index]
        }
        return defaultValue
    }
}

extension RangeReplaceableCollection where Iterator.Element: Equatable {
    mutating func removeFirst(where predicate: (Self.Element) throws -> Bool) rethrows {
        if let i = try firstIndex(where: predicate) {
            remove(at: i)
        }
    }
}
