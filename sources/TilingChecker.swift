//
//  TilingChecker.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/10/23.
//

import Foundation

// Check if a collections of rects tile (completely cover) another rect.
@objc(iTermTilingChecker)
class TilingChecker: NSObject {
    private var rects: [NSRect] = []

    @objc(addRect:)
    func add(rect: NSRect) {
        rects.append(rect)
    }

    @objc(tilesFrame:)
    func tiles(frame: NSRect) -> Bool {
        var checker = RectArithmetic(frame)
        for rect in rects {
            checker.subtract(rect)
        }
        return checker.isEmpty
    }
}

struct RectArithmetic {
    private var frames: [NSRect]
    var isEmpty: Bool { frames.isEmpty }

    init(_ frame: NSRect) {
        frames = [frame]
    }

    // Return lhs - rhs
    private func difference(_ lhs: NSRect?, _ rhs: NSRect?) -> [NSRect] {
        guard let lhs else {
            return []
        }
        guard let rhs else {
            return [lhs]
        }
        let left = sliceLeft(lhs, rhs.minX)
        let right = sliceRight(lhs, rhs.maxX)
        let above = sliceAbove(lhs, rhs.minY)
        let below = sliceBelow(lhs, rhs.maxY)

        let aboveParts = difference(above, left).flatMap { difference($0, right) }
        let belowParts = difference(below, left).flatMap { difference($0, right) }

        return ([left, right] + aboveParts + belowParts).compactMap { $0 }
    }

    private func splitHorizontally(_ rect: NSRect, _ coord: CGFloat) -> (NSRect?, NSRect?) {
        if coord <= rect.minX {
            return (nil, rect)
        }
        if coord >= rect.maxX {
            return (rect, nil)
        }
        return (NSRect(x: rect.minX, y: rect.minY, width: coord - rect.minX, height: rect.height),
                NSRect(x: coord, y: rect.minY, width: rect.maxX - coord, height: rect.height))
    }

    private func splitVertically(_ rect: NSRect, _ coord: CGFloat) -> (NSRect?, NSRect?) {
        if coord <= rect.minY {
            return (nil, rect)
        }
        if coord >= rect.maxY {
            return (rect, nil)
        }
        return (NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: coord - rect.minY),
                NSRect(x: rect.minX, y: coord, width: rect.width, height: rect.maxY - coord))
    }

    private func sliceLeft(_ rect: NSRect, _ coord: CGFloat) -> NSRect? {
        let (before, _) = splitHorizontally(rect, coord)
        return before
    }

    private func sliceRight(_ rect: NSRect, _ coord: CGFloat) -> NSRect? {
        let (_, after) = splitHorizontally(rect, coord)
        return after
    }

    private func sliceAbove(_ rect: NSRect, _ coord: CGFloat) -> NSRect? {
        let (before, _) = splitVertically(rect, coord)
        return before
    }

    private func sliceBelow(_ rect: NSRect, _ coord: CGFloat) -> NSRect? {
        let (_, after) = splitVertically(rect, coord)
        return after
    }

    mutating func subtract(_ rect: NSRect) {
        frames = frames.flatMap { frame in
            difference(frame, rect)
        }
    }
}

