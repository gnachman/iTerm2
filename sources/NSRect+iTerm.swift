//
//  NSRect+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/27/24.
//

import Foundation

extension NSRect {
    var xRange: Range<CGFloat> {
        minX..<maxX
    }
    var yRange: Range<CGFloat> {
        minY..<maxY
    }
    func flipped(in height: CGFloat) -> NSRect {
        var flippedRect = self
        flippedRect.origin.y = height - self.origin.y - self.size.height
        return flippedRect
    }
}

extension NSRect {
    // Assumes the view is flipped
    func insetByEdgeInsets(_ insets: NSEdgeInsets) -> NSRect {
        return NSRect(origin: CGPoint(x: insets.left, y: insets.top),
                      size: CGSize(width: width - insets.left - insets.right,
                                   height: height - insets.top - insets.bottom))
    }
}

extension NSRect {
    var center: NSPoint {
        return NSPoint(x: midX, y: midY)
    }
    var minXminY: NSPoint {
        return NSPoint(x: minX, y: minY)
    }
    var minXmaxY: NSPoint {
        return  NSPoint(x: minX, y: maxY)
    }
}

extension NSRect {
    func translatedToOrigin(_ newOrigin: NSPoint) -> NSRect {
        return NSRect(origin: origin - newOrigin, size: size)
    }

    mutating func shiftY(by dy: CGFloat) {
        origin = origin.addingY(dy)
    }

    mutating func shiftX(by dx: CGFloat) {
        origin = origin.addingX(dx)
    }

    // Returns a rect with opposite-sign height, swapping minY and maxY.
    var inverted: NSRect {
        return NSRect(x: minX, y: minY + height, width: width, height: -height)
    }

    static func +(lhs: NSRect, rhs: NSPoint) -> NSRect {
        return NSRect(origin: lhs.origin + rhs, size: lhs.size)
    }

    static func *(lhs: NSRect, rhs: CGFloat) -> NSRect {
        return NSRect(origin: lhs.origin * rhs, size: lhs.size * rhs)
    }

    static func /(lhs: NSRect, rhs: NSSize) -> NSRect {
        return NSRect(origin: lhs.origin / rhs, size: lhs.size / rhs)
    }

    static func -(lhs: NSRect, rhs: NSPoint) -> NSRect {
        return NSRect(origin: lhs.origin - rhs, size: lhs.size)
    }

    static func +=(lhs: inout NSRect, rhs: NSPoint) {
        lhs = lhs + rhs
    }

    static func -=(lhs: inout NSRect, rhs: NSPoint) {
        lhs = lhs - rhs
    }

    static func *=(lhs: inout NSRect, rhs: CGFloat) {
        lhs = lhs * rhs
    }
}

extension NSRect {
    func safeInsetBy(dx: CGFloat, dy: CGFloat) -> NSRect {
        let safeDx = max(0, dx)
        let safeDy = max(0, dy)
        return NSRect(x: origin.x + safeDx,
                      y: safeDy,
                      width: max(0, size.width - dx * 2),
                      height: max(0, size.height - dy * 2))
    }
}

