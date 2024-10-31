//
//  VT100GridCoordTypes.swift
//  iTerm2
//
//  Created by George Nachman on 11/11/24.
//

@objc(VT100GridCoordSet)
class VT100GridCoordSet: NSObject {
    fileprivate var rows = [Int32: IndexSet]()
    fileprivate var rowSet = IndexSet()

    @objc(containsCoord:)
    func contains(_ coord: VT100GridCoord) -> Bool {
        return rows[coord.y]?.contains(Int(coord.x)) ?? false
    }

    @objc(enumerateCoords:)
    func enumerateCoords(_ closure: (VT100GridCoord, UnsafeMutablePointer<ObjCBool>) -> ()) {
        var stop = ObjCBool(false)
        for row in rowSet {
            for x in rows[Int32(row)]! {
                closure(VT100GridCoord(x: Int32(x),
                                       y: Int32(row)),
                        &stop)
                if stop.boolValue {
                    return
                }
            }
        }
    }

    @objc(enumerateRangesForWidth:block:)
    func enumerateRanges(width: Int32,
                         _ closure: (VT100GridCoordRange, UnsafeMutablePointer<ObjCBool>) -> ()) {
        var stop = ObjCBool(false)
        for row in rowSet {
            for range in rows[Int32(row)]!.rangeView {
                guard let min = range.min(), let max = range.max() else {
                    continue
                }
                closure(VT100GridCoordRange(
                    start: VT100GridCoord(x: Int32(min),
                                          y: Int32(row)),
                    end: VT100GridCoord(x: Int32(max) + 1,
                                        y: Int32(row))),
                        &stop)
                if stop.boolValue {
                    return
                }
            }
        }
    }
}

@objc(VT100MutableGridCoordSet)
class VT100MutableGridCoordSet: VT100GridCoordSet {
    @objc(insert:)
    func insert(coord: VT100GridCoord) {
        rows[coord.y, default: IndexSet()].insert(Int(coord.x))
        rowSet.insert(Int(coord.y))
    }
}
