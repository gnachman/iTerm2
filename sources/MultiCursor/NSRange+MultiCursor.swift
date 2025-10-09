//
//  NSRange+MultiCursor.swift
//  MultiCursor
//
//  Created by George Nachman on 3/31/22.
//

import Foundation

extension NSRange {
    func shifted(by delta: Int) -> NSRange {
        return NSRange(location: location + delta, length: length)
    }

    var droppingFirst: NSRange? {
        if length == 0 {
            return nil
        }
        return NSRange(location: location + 1, length: length - 1)
    }

    var droppingLast: NSRange? {
        if length == 0 {
            return nil
        }
        return NSRange(location: location, length: length - 1)
    }

    // Not inclusive of `to`
    init(from: Int, to: Int) {
        self.init(location: min(from, to), length: max(from, to) -  min(from, to))
    }
}

