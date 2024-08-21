//
//  NSPoint+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/27/24.
//

import Foundation

extension NSPoint {
    static func -(lhs: NSPoint, rhs: NSPoint) -> NSPoint {
        return NSPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
    static func +(lhs: NSPoint, rhs: NSPoint) -> NSPoint {
        return NSPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
    static func *(lhs: NSPoint, rhs: CGFloat) -> NSPoint {
        return NSPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }
    static func /(lhs: NSPoint, rhs: CGFloat) -> NSPoint {
        return NSPoint(x: lhs.x / rhs, y: lhs.y / rhs)
    }
    static func /(lhs: NSPoint, rhs: NSSize) -> NSPoint {
        return NSPoint(x: lhs.x / rhs.width, y: lhs.y / rhs.height)
    }
    func addingY(_ dy: CGFloat) -> NSPoint {
        return NSPoint(x: x, y: y + dy)
    }
    func addingX(_ dx: CGFloat) -> NSPoint {
        return NSPoint(x: x + dx, y: y)
    }
}

extension NSPoint {
    func distance(to other: NSPoint) -> CGFloat {
        return sqrt(pow(x - other.x, 2) + pow(y - other.y, 2))
    }
}
