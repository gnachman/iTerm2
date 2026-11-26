//
//  iTermCompetentTableRowView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/18.
//

import AppKit

// Draws its selection dark gray in a window whose appearance is vibrant dark.
@objc(iTermCompetentTableRowView)
class iTermCompetentTableRowView: NSTableRowView {
    // No thread assertion: AppKit draws on the main thread, and these read only
    // the view and its window.
    @objc private func it_dark() -> Bool {
        return window?.appearance?.name == .vibrantDark
    }

    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none && it_dark() {
            NSColor.darkGray.set()
            // NSRectFill copies.
            dirtyRect.fill(using: .copy)
            return
        }
        super.drawSelection(in: dirtyRect)
    }
}

// Several tables make it by name for their rows.
@objc(iTermBigSurTableRowView)
class iTermBigSurTableRowView: NSTableRowView {
}
