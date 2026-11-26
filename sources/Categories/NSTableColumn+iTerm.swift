//
//  NSTableColumn+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/2/14.
//

import AppKit

extension NSTableColumn {
    @objc(suggestedRowHeight)
    func suggestedRowHeight() -> CGFloat {
        // A nil dataCell gives 0, as messaging nil did.
        guard let cell = dataCell as? NSObject else {
            return 0
        }
        let constrainedBounds = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)
        // dataCell is declared id, so the message goes to whatever object it
        // is, NSCell or not, as the Objective-C sent it.
        return (cell as AnyObject).cellSize(forBounds: constrainedBounds).height
    }
}
