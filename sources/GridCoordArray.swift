//
//  GridCoordArray.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/29/23.
//

import Foundation

// This is a performance optimization because NSValue is kinda pokey.
@objc(iTermGridCoordArray)
class GridCoordArray: NSObject, Codable {
    private var coords = [VT100GridCoord]()

    override init() {
        super.init()
    }

    init(_ coords: [VT100GridCoord]) {
        self.coords = coords
        super.init()
    }

    private enum CodingKeys: String, CodingKey {
        case coords
    }

    required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCoords = try container.decode([VT100GridCoord].self, forKey: .coords)
        self.init(decodedCoords)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coords, forKey: .coords)
    }

    @objc override func mutableCopy() -> Any {
        return GridCoordArray(coords)
    }

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

    @objc func prepend(coord: VT100GridCoord, repeating: Int) {
        for _ in 0..<repeating {
            coords.insert(coord, at: 0)
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
        precondition(i >= 0)
        precondition(i < coords.count)
        return coords[i]
    }

    @objc(coordAt:) func coord(at i: Int) -> VT100GridCoord {
        return coords[i]
    }

    @objc(appendContentsOfArray:) func appendContentsOfArray(_ array: GridCoordArray) {
        coords.append(contentsOf: array.coords)
    }

    @objc(resizeRange:to:)
    func resizeRange(_ original: NSRange, to replacement: NSRange) {
        let subrange = Range(original)!
        var updated = coords[subrange]
        while updated.count > replacement.length {
            updated.removeLast()
        }
        while updated.count < replacement.length {
            updated.append(updated.last!)
        }
        coords.replaceSubrange(subrange, with: updated)
    }

    /// Returns the range of indices in this array where x is in [startX, endX).
    /// If no matching coordinates are found, returns NSNotFound for location.
    @objc(rangeOfIndicesWithXFrom:to:)
    func rangeOfIndices(xFrom startX: Int32, to endX: Int32) -> NSRange {
        var start = NSNotFound
        var end = 0
        for (i, coord) in coords.enumerated() {
            if coord.x >= startX && coord.x < endX {
                if start == NSNotFound {
                    start = i
                }
                end = i + 1
            }
        }
        if start == NSNotFound {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: start, length: end - start)
    }

    /// Returns the index of the first coordinate with x >= targetX, or NSNotFound.
    @objc(indexOfFirstCoordWithXGreaterOrEqual:)
    func indexOfFirstCoord(xGreaterOrEqual targetX: Int32) -> Int {
        for (i, coord) in coords.enumerated() {
            if coord.x >= targetX {
                return i
            }
        }
        return NSNotFound
    }
}

