//
//  ReferenceContainer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/27/24.
//

import Foundation

// Used to wrap a value type to get reference semantics.
class ReferenceContainer<T> {
    var value: T

    init(_ image: T) {
        value = image
    }
}
