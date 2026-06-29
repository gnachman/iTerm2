//
//  PTYTrackingChildWindow.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/21/22.
//

import Foundation

// A child window that moves along with the scrolling of a PTYTextView.
@objc
protocol PTYTrackingChildWindow: AnyObject {
    // Owner sets this to be notified when the window wants to be removed.
    @objc var requestRemoval: (() -> ())? { get set }

    // Owner calls this upon scrolling so the child window can adjust its position vertically.
    @objc func shiftVertically(_ delta: CGFloat)
}
