//
//  NSSize+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/27/24.
//

import Foundation

extension NSSize {
    // MARK: - NSSize ⋆ CGFloat
    static func *(lhs: NSSize, rhs: CGFloat) -> NSSize {
        return NSSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
    static func /(lhs: NSSize, rhs: CGFloat) -> NSSize {
        return NSSize(width: lhs.width / rhs, height: lhs.height / rhs)
    }

    // MARK: - NSSize ⋆ NSSize
    static func /(lhs: NSSize, rhs: NSSize) -> NSSize {
        return NSSize(width: lhs.width / rhs.width, height: lhs.height / rhs.height)
    }
    static func +(lhs: NSSize, rhs: NSSize) -> NSSize {
        return NSSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
    static func -(lhs: NSSize, rhs: NSSize) -> NSSize {
        return NSSize(width: lhs.width - rhs.width, height: lhs.height - rhs.height)
    }
    static func -=(lhs: inout NSSize, rhs: NSSize) {
        lhs = lhs - rhs
    }
    func truncatingRemainder(dividingBy rhs: NSSize) -> NSSize {
        return NSSize(width: width.truncatingRemainder(dividingBy: rhs.width),
                      height: height.truncatingRemainder(dividingBy: rhs.height))
    }
    func map(_ closure: (CGFloat) -> (CGFloat)) -> NSSize {
        NSSize(width: closure(width), height: closure(height))
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

struct SizeZip {
    let lhs: NSSize
    let rhs: NSSize

    // Calls transform on (lhs.width,rhs.width) and then (lhs.height,rhs.height).
    func map(_ transform: (CGFloat, CGFloat) -> CGFloat) -> NSSize {
        return NSSize(
            width: transform(lhs.width, rhs.width),
            height: transform(lhs.height, rhs.height)
        )
    }
}

func zip(_ lhs: NSSize, _ rhs: NSSize) -> SizeZip {
    SizeZip(lhs: lhs, rhs: rhs)
}

