//
//  VT100GridTypes+Swift.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/27/24.
//

import Foundation

extension VT100GridAbsCoordRange {
    var width: Int32 {
        max(0, end.x - start.x)
    }
    var height: Int32 {
        Int32(clamping: max(0, end.y - start.y + 1))
    }
}

extension VT100GridCoord: Comparable {
    public static func == (lhs: VT100GridCoord, rhs: VT100GridCoord) -> Bool {
        return VT100GridCoordEquals(lhs, rhs)
    }

    public static func < (lhs: VT100GridCoord, rhs: VT100GridCoord) -> Bool {
        return VT100GridCoordCompare(lhs, rhs) == .orderedAscending
    }
}

extension VT100GridCoord {
    func absolute(overflow: Int64) -> VT100GridAbsCoord {
        return VT100GridAbsCoordFromCoord(self, overflow)
    }
}

extension VT100GridCoord: Codable {
    enum CodingKeys: String, CodingKey {
        case x, y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Int32.self, forKey: .x)
        let y = try container.decode(Int32.self, forKey: .y)
        self = VT100GridCoord(x: x, y: y)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }
}

extension VT100GridAbsCoord {
    func relative(overflow: Int64) -> VT100GridCoord? {
        var ok = ObjCBool(false)
        let result = VT100GridCoordFromAbsCoord(self, overflow, &ok)
        if !ok.boolValue {
            return nil
        }
        return result
    }

    func relativeClamped(overflow: Int64) -> VT100GridCoord {
        if let coord = relative(overflow: overflow) {
            return coord
        }
        if y < overflow {
            return VT100GridCoord(x: 0, y: 0)
        }
        return VT100GridCoord(x: 0, y: Int32.max - 1)
    }
}

extension VT100GridAbsCoordRange {
    var description: String {
        VT100GridAbsCoordRangeDescription(self)
    }
}

extension VT100GridCoordRange {
    var closedRangeForY: ClosedRange<Int32> {
        min(start.y, end.y)...max(start.y, end.y)
    }
}

extension ClosedRange {
    init?(safeLowerBound lower: Bound, upperBound upper: Bound) {
        if lower <= upper {
            self = lower...upper
        } else {
            return nil
        }
    }
}

extension Range {
    init?(safeLowerBound lower: Bound, upperBound upper: Bound) {
        if lower <= upper {
            self = lower..<upper
        } else {
            return nil
        }
    }
}
