//
//  Box.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2025.
//

import Foundation

/// A reference-type wrapper for value types.
///
/// Use this to avoid copy-on-write overhead when storing value types inside
/// enum associated values or other structs where extracting creates copies
/// that share underlying storage.
///
/// Example:
/// ```swift
/// enum State {
///     case processing(Box<[Item]>)
/// }
///
/// case .processing(let box):
///     box.value.append(item)  // No CoW - box owns the array uniquely
/// ```
final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
