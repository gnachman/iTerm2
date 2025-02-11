//
//  IndexSet+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 10/22/24.
//

extension IndexSet {
    init(ranges: [Range<Int>]) {
        self.init()
        for range in ranges {
            insert(integersIn: range)
        }
    }

    mutating func removeFirst() -> Element? {
        if let value = first {
            remove(value)
            return value
        }
        return nil
    }

    var enumeratedDescription: String {
        map { String($0) }.joined(separator: ", ")
    }
}

