//
//  MacShims.swift
//  iTerm2 Companion
//
//  Same-named stand-ins for small Mac helper functions/extensions the shared
//  chat-model sources use. Behavior matches the Mac originals (see
//  SwiftDebugLogging.swift, String+iTerm.swift, Optional+iTerm.swift).
//

import Foundation

/// Mac original logs for the crash reporter; on the phone a plain fatalError
/// suffices.
func it_fatalError(_ message: @autoclosure () -> String = "",
                   file: StaticString = #file,
                   line: UInt = #line,
                   function: StaticString = #function) -> Never {
    fatalError(message(), file: file, line: line)
}

extension String {
    func truncatedWithTrailingEllipsis(to maxLength: Int) -> String {
        if count <= maxLength {
            return self
        }
        return String(prefix(maxLength - 1)) + "…"
    }
}

// Enables logging of optional strings as in the Mac sources: "\(maybe.d)".
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

extension Optional where Wrapped == String {
    static func concat(_ lhs: String?, _ rhs: String?) -> String? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case let (l?, r?):
            return l + r
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        }
    }
}

// SwiftUI list plumbing for the shared model types.
extension Message: Identifiable {
    var id: UUID { uniqueID }
}
