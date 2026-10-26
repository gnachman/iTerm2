//
//  NSRegularExpression+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/14/22.
//

import Foundation

// Any thread.
final class RegexCache {
    static let instance = RegexCache()
    private let cache = MutableAtomicObject([String: Result<NSRegularExpression, Error>]())

    func get(_ pattern: String) throws -> NSRegularExpression? {
        let result = cache.access { $0[pattern] } ?? compile(pattern)
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    // Compiled outside the lock. Two threads may both compile a new pattern; either result is fine.
    private func compile(_ pattern: String) -> Result<NSRegularExpression, Error> {
        let result: Result<NSRegularExpression, Error>
        do {
            result = .success(try NSRegularExpression(pattern: pattern))
        } catch {
            result = .failure(error)
        }
        cache.mutableAccess { $0[pattern] = result }
        return result
    }
}

extension String {
    func matches(regex: String) -> Bool {
        guard let compiled = try! RegexCache.instance.get(regex) else {
            return false
        }
        return compiled.numberOfMatches(in: self, range: NSRange(location: 0, length: utf16.count)) > 0
    }

    func captureGroups(regex: String) -> [NSRange] {
        guard let compiled = try! RegexCache.instance.get(regex) else {
            return []
        }
        guard let match = compiled.firstMatch(in: self, range: NSRange(location: 0, length: utf16.count)) else {
            return []
        }
        return (0..<match.numberOfRanges).map {
            match.range(at: $0)
        }
    }
}
