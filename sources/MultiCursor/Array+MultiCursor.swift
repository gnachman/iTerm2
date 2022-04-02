//
//  Array+MultiCursor.swift
//  MultiCursor
//
//  Created by George Nachman on 4/1/22.
//

import Foundation

extension Array where Element: Equatable {
    var uniq: [Element] {
        return enumerated().filter { tuple in
            let (i, value) = tuple
            if i > 0 && self[i - 1] == value {
                return false
            }
            return true
        }.map {
            $0.1
        }
    }
}
