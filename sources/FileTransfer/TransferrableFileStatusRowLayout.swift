//
//  TransferrableFileStatusRowLayout.swift
//  iTerm2
//
//  Created by George Nachman on 10/26/26.
//

import AppKit

/// Splits the bottom row of a file in the Downloads or Uploads menu between the status (on
/// the left, such as “Finished”) and the size (on the right, such as “1.2 MB of 20 MB”).
/// Each was drawn across the whole row, so a long status ran into the size or was drawn over
/// it, as with German “Abgeschlossen, einige Objekte ausgelassen” (F-723). The size keeps its
/// natural width, so it stays readable, and the status gets what is left and truncates.
@objc(iTermTransferrableFileStatusRowLayout)
final class TransferrableFileStatusRowLayout: NSObject {
    /// Space between the status and the size.
    @objc static let gap: CGFloat = 8

    /// The status always keeps at least this fraction of the row, so an unusually long size
    /// can't squeeze it out entirely.
    static let minimumStatusFraction: CGFloat = 1.0 / 3.0

    @objc let statusRect: NSRect
    @objc let sizeRect: NSRect

    /// `statusWidth` and `sizeWidth` are the widths the two strings need when drawn in full.
    @objc init(rowRect: NSRect, statusWidth: CGFloat, sizeWidth: CGFloat) {
        let rowWidth = max(0, rowRect.width)
        let neededStatusWidth = max(0, ceil(statusWidth))
        let neededSizeWidth = max(0, ceil(sizeWidth))

        let sizeWidth: CGFloat
        let statusWidth: CGFloat
        if neededSizeWidth == 0 {
            sizeWidth = 0
            statusWidth = rowWidth
        } else if neededStatusWidth == 0 {
            sizeWidth = rowWidth
            statusWidth = 0
        } else {
            let gap = Self.gap
            let maximumSizeWidth = max(0, rowWidth - gap - rowWidth * Self.minimumStatusFraction)
            sizeWidth = min(neededSizeWidth, maximumSizeWidth)
            statusWidth = max(0, rowWidth - sizeWidth - gap)
        }
        statusRect = NSRect(x: rowRect.minX,
                            y: rowRect.minY,
                            width: statusWidth,
                            height: rowRect.height)
        sizeRect = NSRect(x: rowRect.minX + rowWidth - sizeWidth,
                          y: rowRect.minY,
                          width: sizeWidth,
                          height: rowRect.height)
        super.init()
    }
}
