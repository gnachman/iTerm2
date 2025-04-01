//
//  Optional+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/27/24.
//

import Foundation

extension Optional {
    func compactMap<T>(_ transform: (Wrapped) -> T?) -> T? {
        switch self {
        case .some(let value):
            return transform(value)
        case .none:
            return nil
        }
    }
}

public extension Optional where Wrapped: CustomDebugStringConvertible {
    var debugDescriptionOrNil: String {
        switch self {
        case .none:
            return "(nil)"
        case .some(let obj):
            return obj.debugDescription
        }
    }
}

public extension Optional where Wrapped: CustomStringConvertible {
    var descriptionOrNil: String {
        switch self {
        case .none:
            return "(nil)"
        case .some(let obj):
            return obj.description
        }
    }
}

public extension Optional where Wrapped == Data {
    var stringOrHex: String {
        switch self {
        case .some(let data):
            return data.stringOrHex
        case .none:
            return "(nil)"
        }
    }
}

// Enables easy logging of optional strings: DLog("\(maybeString.d)")
extension Optional where Wrapped: StringProtocol {
    var d: String {
        switch self {
        case .none:
            return "(nil)"
        case .some(let value):
            return String(value)
        }
    }
}

extension Optional where Wrapped: NSObject {
    var d: String {
        switch self {
        case .none:
            return "(nil)"
        case .some(let value):
            return value.description
        }
    }
}
