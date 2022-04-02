//
//  NSPoint+MultiCursor.swift
//  MultiCursor
//
//  Created by George Nachman on 3/31/22.
//

import AppKit

extension NSPoint {
    func retinaRound(_ scale: CGFloat) -> NSPoint {
        return NSPoint(x: round(x * scale) / scale, y: round(y * scale) / scale)
    }
}

