//
//  NSSIze+MultiCursor.swift
//  MultiCursor
//
//  Created by George Nachman on 3/31/22.
//

import AppKit

extension NSSize {
    func retinaRound(_ scale: CGFloat) -> NSSize {
        return NSSize(width: round(width * scale) / scale, height: round(height * scale) / scale)
    }
}
