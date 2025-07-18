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
    // I don't know why but adding d here breaks a bunch of unrelated stuff.
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
    var d: String {
        descriptionOrNil
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

protocol AnyOptional {
    static var wrappedType: Any.Type { get }
}

extension Optional: AnyOptional {
    static var wrappedType: Any.Type {
        return Wrapped.self
    }
}

extension Optional where Wrapped == URL {
    var d: String {
        switch self {
        case .none:
            return "(nil)"
        case .some(let value):
            return value.absoluteString
        }
    }
}

extension Optional where Wrapped: AnyObject {
    var d: String {
        switch self {
        case .none:
            return "(nil)"
        case .some(let value):
            if let obj = value as? NSObject {
                return obj.description
            }
            let ptr = Unmanaged.passUnretained(value).toOpaque()
            return String(format: "%p", Int(bitPattern: ptr))
        }
    }
}
