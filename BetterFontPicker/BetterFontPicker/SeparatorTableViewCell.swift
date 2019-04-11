//
//  SeparatorTableViewCell.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/7/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Foundation

class SeparatorTableViewCell: NSTableRowView {
    static let thickness = CGFloat(2)
    static let margin = CGFloat(8)
    static let height = thickness + margin * 2

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill()

        let rect = NSRect(x: 0,
                          y: retinaRound((self.bounds.size.height - SeparatorTableViewCell.thickness) / 2.0),
                          width: self.bounds.size.width,
                          height: SeparatorTableViewCell.thickness)
        if #available(macOS 10.14, *) {
            NSColor.separatorColor.set()
        } else {
            NSColor.lightGray.set()
        }
        rect.fill()
    }

    private func retinaRound(_ value: CGFloat) -> CGFloat {
        let scale = self.window?.backingScaleFactor ?? 1
        return round(value * scale) / scale
    }
}
