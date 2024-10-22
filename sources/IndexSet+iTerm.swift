//
//  IndexSet+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 10/22/24.
//

extension IndexSet {
    mutating func removeFirst() -> Element? {
        if let value = first {
            remove(value)
            return value
        }
        return nil
    }
}
