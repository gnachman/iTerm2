//
//  NSScrollView+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/21/21.
//

import Foundation

extension NSScrollView {
    @objc static func scrollViewWithTableViewForToolbelt(container: NSView & NSTableViewDelegate & NSTableViewDataSource,
                                                         insets: NSEdgeInsets) -> NSScrollView {
        return scrollViewWithTableViewForToolbelt(container: container, insets: insets, rowHeight: 0)
    }

    @objc static func scrollViewWithTableViewForToolbelt(container: NSView & NSTableViewDelegate & NSTableViewDataSource,
                                                         insets: NSEdgeInsets,
                                                         rowHeight: CGFloat) -> NSScrollView {
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

        _ = NSTableView.toolbeltTableView(inScrollview: scrollView,
                                          fixedRowHeight: rowHeight,
                                          owner: container)
        return scrollView
    }
}

extension NSScrollView {
    var distanceToTop: CGFloat {
        get {
            guard let documentView else {
                return 0
            }
            return documentView.bounds.height - contentView.bounds.maxY
        }
        set {
            guard let documentView else {
                return
            }
            var bounds = contentView.bounds
            let newOrigin = documentView.bounds.height - newValue - contentView.bounds.height
            bounds.origin.y = newOrigin
            contentView.bounds = bounds
        }
    }
}

