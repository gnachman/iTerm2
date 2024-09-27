//
//  NSSize+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/27/24.
//

import Foundation

extension NSSize {
    static func *(lhs: NSSize, rhs: CGFloat) -> NSSize {
        return NSSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
    static func /(lhs: NSSize, rhs: CGFloat) -> NSSize {
        return NSSize(width: lhs.width / rhs, height: lhs.height / rhs)
    }
    static func /(lhs: NSSize, rhs: NSSize) -> NSSize {
        return NSSize(width: lhs.width / rhs.width, height: lhs.height / rhs.height)
    }
}

extension NSSize: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
    }
}

extension NSSize {
    func multiplied(by other: NSSize) -> NSSize {
        return NSSize(width: width * other.width, height: height * other.height)
    }
    var inverted: NSSize {
        return NSSize(width: 1.0 / width, height: 1.0 / height)
    }
}
