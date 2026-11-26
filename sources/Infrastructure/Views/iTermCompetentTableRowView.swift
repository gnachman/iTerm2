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
    @objc private func it_dark() -> Bool {
        return window?.appearance?.name == .vibrantDark
    }

    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none && it_dark() {
            NSColor.darkGray.set()
            dirtyRect.fill(using: .copy)
            return
        }
        super.drawSelection(in: dirtyRect)
    }
}

// An empty subclass that several tables use for their rows.
@objc(iTermBigSurTableRowView)
class iTermBigSurTableRowView: NSTableRowView {
}
