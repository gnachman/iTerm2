//
//  NSScrollView+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/21/21.
//

import Foundation

extension NSRect {
    // Assumes the view is flipped
    func insetByEdgeInsets(_ insets: NSEdgeInsets) -> NSRect {
        return NSRect(origin: CGPoint(x: insets.left, y: insets.top),
                      size: CGSize(width: width - insets.left - insets.right,
                                   height: height - insets.top - insets.bottom))
    }
}
extension NSScrollView {
    @objc static func scrollViewWithTableViewForToolbelt(container: NSView & NSTableViewDelegate & NSTableViewDataSource,
                                                         insets: NSEdgeInsets) -> NSScrollView {
        let frame = container.bounds.insetByEdgeInsets(insets)
        let scrollView = NSScrollView(frame: frame)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        if #available(macOS 10.16, *) {
            scrollView.borderType = .lineBorder
            scrollView.scrollerStyle = .overlay
        } else {
            scrollView.borderType = .bezelBorder
        }
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false

        _ = NSTableView.toolbeltTableView(inScrollview: scrollView, owner: container)
        return scrollView
    }
}
