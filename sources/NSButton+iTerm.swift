//
//  NSButton+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/29/25.
//

import AppKit

@objc
extension NSButton {
    fileprivate static let hiddenFromActionsKey = { iTermMalloc(1) }()

    @objc
    var hiddenFromActions: Bool {
        get {
            if let obj = it_associatedObject(forKey: Self.hiddenFromActionsKey) as? NSNumber {
                return obj.boolValue
            } else {
                return false
            }
        }
        set {
            it_setAssociatedObject(NSNumber(value: newValue),
                                   forKey: Self.hiddenFromActionsKey)
        }
    }
}
