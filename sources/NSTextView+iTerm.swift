//
//  NSTextView+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/17/21.
//

import Foundation

extension NSTextView {
    @objc func it_scrollCursorToVisible() {
        guard let location = selectedRanges.first?.rangeValue.location else {
            return
        }
        scrollRangeToVisible(NSRange(location: location, length: 0))
    }
}
