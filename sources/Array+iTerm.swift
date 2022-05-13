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

