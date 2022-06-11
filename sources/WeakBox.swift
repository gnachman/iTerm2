//
//  WeakBox.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/5/22.
//

import Foundation

class WeakBox<T> {
    private weak var _value: AnyObject?
    var value: T? {
        _value as? T
    }
    init(_ value: T?) {
        _value = value as AnyObject?
    }
}
