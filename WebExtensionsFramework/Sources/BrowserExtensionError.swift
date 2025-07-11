import Foundation

/// Runtime errors that occur in the native extension code
public enum BrowserExtensionError: Error, LocalizedError, Equatable {
    case noMessageReceiver
    case messagePortClosed  
    case extensionContextInvalidated
    case unknownAPI(String)
    case internalError(String)
    case insufficientPermissions(String)
    case quotaExceeded
    case valueError(String)
    case permissionDenied
    case notAvailable

    public var errorDescription: String? {
        switch self {
        case .noMessageReceiver:
            return "Could not establish connection. Receiving end does not exist."
        case .messagePortClosed:
            return "The message port closed before a response was received."
        case .extensionContextInvalidated:
            return "Extension context invalidated."
        case .unknownAPI(let api):
            return "Unknown API: \(api)"
        case .internalError(let message):
            return "Internal error: \(message)"
        case .insufficientPermissions(let permission):
            return "This extension does not have permission to use \(permission). Add \"\(permission)\" to the \"permissions\" array in the manifest."
        case .quotaExceeded:
            return "Quota exceeded"
        case .valueError(let message):
            return "Value error: \(message)"
        case .permissionDenied:
            return "Permission denied"
        case .notAvailable:
            return "Operation not available"
        }
    }
}

/// Error information that can be passed back to JavaScript
public struct BrowserExtensionErrorInfo: Codable {
    public let message: String
    
    public init(from error: Error) {
        if let extensionError = error as? BrowserExtensionError {
            self.message = extensionError.errorDescription ?? "Unknown error"
        } else {
            self.message = error.localizedDescription
        }
    }
    
    public init(message: String) {
        self.message = message
    }
}
