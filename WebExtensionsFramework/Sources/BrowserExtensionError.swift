import Foundation

/// Runtime errors that occur in the native extension code
public enum BrowserExtensionError: Error, LocalizedError, Equatable {
    case noMessageReceiver
    case messagePortClosed  
    case extensionContextInvalidated
    case unknownAPI(String)
    case internalError(String)
    
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