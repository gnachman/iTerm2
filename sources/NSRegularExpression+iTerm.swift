//
//  NSRegularExpression+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/14/22.
//

import Foundation

struct RegexCache {
    fileprivate static var instance = RegexCache()
    private var cache: [String: Result<NSRegularExpression, Error>] = [:]

    mutating func get(_ pattern: String) throws -> NSRegularExpression? {
        if let result = cache[pattern] {
            switch result {
            case .success(let value):
                return value
            case .failure(let error):
                throw error
            }
        }
        do {
            let cached = try NSRegularExpression(pattern: pattern)
            cache[pattern] = .success(cached)
            return cached
        } catch {
            cache[pattern] = .failure(error)
            throw error
        }
    }
}

extension String {
    func matches(regex: String) -> Bool {
        guard let compiled = try! RegexCache.instance.get(regex) else {
            return false
        }
        return compiled.numberOfMatches(in: self, range: NSRange(location: 0, length: count)) > 0
    }

    func captureGroups(regex: String) -> [NSRange] {
        guard let compiled = try! RegexCache.instance.get(regex) else {
            return []
        }
        guard let match = compiled.firstMatch(in: self, range: NSRange(location: 0, length: count)) else {
            return []
        }
        return (0..<match.numberOfRanges).map {
            match.range(at: $0)
        }
    }
}
