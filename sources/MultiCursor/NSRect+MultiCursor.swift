//
//  NSRect+MultiCursor.swift
//  MultiCursor
//
//  Created by George Nachman on 3/31/22.
//

import AppKit

extension NSRect {
    var withPositiveWidth: NSRect {
        if width > 0 {
            return self
        }
        var temp = self
        temp.size.width = 1
        return temp
    }

    var terminus: NSPoint {
        return NSPoint(x: maxX, y: maxY)
    }
    var neighborBelow: NSRect {
        // A same-size rect just under us (larger Y)
        return NSRect(x: minX, y: maxY, width: width, height: height)
    }
    var neighborAbove: NSRect {
        // A same-size rect just under us (larger Y)
        return NSRect(x: minX, y: minY - height, width: width, height: height)
    }
    var maxPointWithinRect: NSPoint {
        return NSPoint(x: maxX - 1, y: maxY - 1)
    }

    func retinaRound(_ scale: CGFloat?) -> NSRect {
        return NSRect(origin: origin.retinaRound(scale ?? 1),
                      size: size.retinaRound(scale ?? 1))
    }

    init(point: NSPoint) {
        self.init(x: point.x, y: point.y, width: 0, height: 0)
    }
}

