import Foundation

/// Storage access levels for local, sync, and session storage areas
public enum BrowserExtensionStorageAccessLevel {
    /// Only accessible from trusted contexts (background scripts, extension pages)
    case trustedContexts
    
    /// Accessible from both trusted and untrusted contexts (content scripts in web pages)
    case trustedAndUntrustedContexts
}

/// Context type for storage operations
public enum BrowserExtensionStorageContextType {
    /// Trusted contexts: background scripts, extension pages (popup, options, etc.)
    case trusted
    
    /// Untrusted contexts: content scripts running in web pages
    case untrusted
}

/// Storage quota information
public struct BrowserExtensionStorageQuota {
    /// Maximum number of items allowed, or nil for unlimited
    public let maxItems: Int?
    
    /// Maximum total size in bytes, or nil for unlimited
    public let maxSizeBytes: Int?
    
    /// Maximum size per item in bytes, or nil for unlimited
    public let maxItemSizeBytes: Int?
    
    public init(maxItems: Int? = nil, maxSizeBytes: Int? = nil, maxItemSizeBytes: Int? = nil) {
        self.maxItems = maxItems
        self.maxSizeBytes = maxSizeBytes
        self.maxItemSizeBytes = maxItemSizeBytes
    }
    
    /// Default quotas for storage areas (when extension doesn't have unlimitedStorage permission)
    public static let localDefault = BrowserExtensionStorageQuota(
        maxItems: nil,
        maxSizeBytes: 10 * 1024 * 1024, // 10MB
        maxItemSizeBytes: nil
    )
    
    public static let syncDefault = BrowserExtensionStorageQuota(
        maxItems: 512,
        maxSizeBytes: 100 * 1024, // 100KB
        maxItemSizeBytes: 8 * 1024 // 8KB
    )
    
    public static let sessionDefault = BrowserExtensionStorageQuota(
        maxItems: nil,
        maxSizeBytes: 10 * 1024 * 1024, // 10MB
        maxItemSizeBytes: nil
    )

    public static let unlimited = BrowserExtensionStorageQuota(
        maxItems: nil,
        maxSizeBytes: nil,
        maxItemSizeBytes: nil
    )
}

/// Error type that storage providers can throw to communicate specific failures
public struct BrowserExtensionStorageProviderError: Error {
    /// The type of error that occurred
    public let type: ErrorType
    
    /// Additional context about the error
    public let message: String?
    
    /// The key(s) involved in the operation that failed, if applicable
    public let keys: [String]?
    
    public init(type: ErrorType, message: String? = nil, keys: [String]? = nil) {
        self.type = type
        self.message = message
        self.keys = keys
    }
    
    public enum ErrorType {
        /// The storage quota for this area has been exceeded
        case quotaExceeded
        
        /// The key contains invalid characters or is too long
        case invalidKey
        
        /// The value could not be serialized or is too large
        case invalidValue
        
        /// Lacking permission for what you tried to do
        case permissionDenied

        /// A general storage backend error (e.g., database error)
        case backendError
        
        /// The operation is not supported for this storage area
        case operationNotSupported
    }
}

/// Protocol that clients must implement to provide storage capabilities to the extension framework
@MainActor
public protocol BrowserExtensionStorageProvider: AnyObject {
    
    /// Get values for the specified keys from storage
    /// - Parameters:
    ///   - keys: The keys to retrieve. If nil or empty, return all stored items.
    ///   - area: The storage area to retrieve from
    ///   - extensionId: The extension requesting the data
    /// - Returns: A dictionary of key-value pairs. Values are JSON strings.
    /// - Throws: BrowserExtensionStorageProviderError if the operation fails
    func get(keys: [String]?, area: BrowserExtensionStorageArea, extensionId: ExtensionID) async throws -> [String: String]
    
    /// Set values in storage and return original values for change detection
    /// - Parameters:
    ///   - items: Dictionary of key-value pairs to store. Values are JSON strings.
    ///   - area: The storage area to store in
    ///   - extensionId: The extension storing the data
    ///   - hasUnlimitedStorage: Whether the extension has the unlimitedStorage permission
    /// - Returns: Dictionary mapping each key to its original value (nil if key didn't exist)
    /// - Throws: BrowserExtensionStorageProviderError if the operation fails
    func set(items: [String: String], area: BrowserExtensionStorageArea, extensionId: ExtensionID, hasUnlimitedStorage: Bool) async throws -> [String: String?]
    
    /// Remove items from storage and return removed values for change detection
    /// - Parameters:
    ///   - keys: The keys to remove
    ///   - area: The storage area to remove from
    ///   - extensionId: The extension requesting removal
    /// - Returns: Dictionary mapping each key to its removed value (nil if key didn't exist)
    /// - Throws: BrowserExtensionStorageProviderError if the operation fails
    func remove(keys: [String], area: BrowserExtensionStorageArea, extensionId: ExtensionID) async throws -> [String: String?]
    
    /// Clear all items from storage and return removed values for change detection
    /// - Parameters:
    ///   - area: The storage area to clear
    ///   - extensionId: The extension requesting the clear
    /// - Returns: Dictionary of all removed key-value pairs
    /// - Throws: BrowserExtensionStorageProviderError if the operation fails
    func clear(area: BrowserExtensionStorageArea, extensionId: ExtensionID) async throws -> [String: String]
    
    /// Get the current storage usage information
    /// - Parameters:
    ///   - area: The storage area to check
    ///   - extensionId: The extension to check usage for
    /// - Returns: Current bytes used and item count
    /// - Throws: BrowserExtensionStorageProviderError if the operation fails
    func getUsage(area: BrowserExtensionStorageArea, extensionId: ExtensionID) async throws -> (bytesUsed: Int, itemCount: Int)
    
    
    /// Get quota information for a storage area
    /// - Parameters:
    ///   - area: The storage area to get quota for
    ///   - hasUnlimitedStorage: Whether the extension has the unlimitedStorage permission
    /// - Returns: The quota limits for the area, or nil to use framework defaults
    func getQuota(for area: BrowserExtensionStorageArea, hasUnlimitedStorage: Bool) -> BrowserExtensionStorageQuota?
    
    /// Get the current storage access level for an extension and area
    /// - Parameters:
    ///   - area: The storage area to check
    ///   - extensionId: The extension to check
    /// - Returns: The current access level (defaults to trustedContexts)
    func getStorageAccessLevel(area: BrowserExtensionStorageArea, extensionId: ExtensionID) async -> BrowserExtensionStorageAccessLevel
    
    /// Set the storage access level for an extension and area
    /// - Parameters:
    ///   - accessLevel: The access level to set
    ///   - area: The storage area to configure (local, sync, or session; not managed)
    ///   - extensionId: The extension to configure
    /// - Throws: BrowserExtensionStorageProviderError if the operation fails
    func setStorageAccessLevel(_ accessLevel: BrowserExtensionStorageAccessLevel, area: BrowserExtensionStorageArea, extensionId: ExtensionID) async throws
}
