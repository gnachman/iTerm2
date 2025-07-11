import Foundation
import BrowserExtensionShared

/// Storage change information for onChanged events
public struct BrowserExtensionStorageChange: Codable, BrowserExtensionJSONRepresentable {
    /// The old value (if any)
    public let oldValue: String?
    /// The new value (if any)
    public let newValue: String?

    public init(oldValue: String?, newValue: String?) {
        self.oldValue = oldValue
        self.newValue = newValue
    }
    
    public var browserExtensionEncodedValue: BrowserExtensionEncodedValue {
        do {
            let data = try JSONEncoder().encode(self)
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            return try .json(jsonObject)
        } catch {
            return .undefined
        }
    }
}

/// Storage area name for identifying which storage area changed
public enum BrowserExtensionStorageArea: String, Codable, CaseIterable, Hashable {
    case local = "local"
    case sync = "sync"
    case session = "session"
    case managed = "managed"
}


/// Error types for storage operations
public enum BrowserExtensionStorageError: Error, Equatable {
    case quotaExceeded(area: BrowserExtensionStorageArea)
    case invalidKey(String)
    case invalidValue(String)
    case managedStorageReadOnly
    case storageAreaNotAvailable(BrowserExtensionStorageArea)
    
    public var errorDescription: String {
        switch self {
        case .quotaExceeded(let area):
            return "Storage quota exceeded for \(area.rawValue) storage"
        case .invalidKey(let key):
            return "Invalid storage key: \(key)"
        case .invalidValue(let message):
            return "Invalid storage value: \(message)"
        case .managedStorageReadOnly:
            return "Managed storage is read-only"
        case .storageAreaNotAvailable(let area):
            return "Storage area \(area.rawValue) is not available"
        }
    }
}
