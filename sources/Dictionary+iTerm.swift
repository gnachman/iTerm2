//
//  Dictionary+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 6/10/25.
//

extension Dictionary {
    mutating func getOrCreate(
        for key: Key,
        using factory: () -> Value) -> Value {
        if let existing = self[key] {
            return existing
        }
        let newValue = factory()
        self[key] = newValue
        return newValue
    }
}
