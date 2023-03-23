//
//  GridCoordArray.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/29/23.
//

import Foundation

// This is a performance optimization because NSValue is kinda pokey.
@objc(iTermGridCoordArray)
class GridCoordArray: NSObject {
    private var coords = [VT100GridCoord]()

    @objc var last: VT100GridCoord {
        return coords.last ?? VT100GridCoord(x: 0, y: 0)
    }

    @objc var count: Int {
        coords.count
    }

    @objc func append(coord: VT100GridCoord) {
        coords.append(coord)
    }

    @objc func append(coord: VT100GridCoord, repeating: Int) {
        for _ in 0..<repeating {
            coords.append(coord)
        }
    }

    @objc func removeFirst(_ n: Int) {
        coords.removeFirst(n)
    }

    @objc func removeLast(_ n: Int) {
        coords.removeLast(n)
    }

    @objc func removeRange(_ range: NSRange) {
        coords.removeSubrange(Range(range)!)
    }

    @objc func removeAll() {
        coords = []
    }

    @objc subscript(_ i: Int) -> VT100GridCoord {
        return coords[i]
    }

    @objc(coordAt:) func coord(at i: Int) -> VT100GridCoord {
        return coords[i]
    }

    @objc(appendContentsOfArray:) func appendContentsOfArray(_ array: GridCoordArray) {
        coords.append(contentsOf: array.coords)
    }
}
