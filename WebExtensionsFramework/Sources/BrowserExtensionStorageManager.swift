import Foundation
import BrowserExtensionShared

/// Manages storage operations for browser extensions
@MainActor
public class BrowserExtensionStorageManager {
    
    /// The storage provider that handles persistence
    public var storageProvider: BrowserExtensionStorageProvider?
    
    /// Router for broadcasting onChanged events
    public var router: BrowserExtensionRouter?
    
    /// Logger for debugging storage operations
    private let logger: BrowserExtensionLogger
    
    public init(logger: BrowserExtensionLogger) {
        self.logger = logger
    }
    
    /// Get values from storage
    /// - Parameters:
    ///   - keys: Keys to retrieve, or nil for all keys
    ///   - area: Storage area to retrieve from
    ///   - extensionId: Extension requesting the data
    ///   - hasUnlimitedStorage: Whether extension has unlimited storage permission
    ///   - contextType: Trusted or untrusted context
    /// - Returns: Dictionary of key-value pairs (values are JSON strings)
    public func get(keys: [String]?, area: BrowserExtensionStorageArea, extensionId: UUID, hasUnlimitedStorage: Bool, contextType: BrowserExtensionStorageContextType) async throws -> [String: String] {
        guard let provider = storageProvider else {
            throw BrowserExtensionError.internalError("Storage provider not configured")
        }
        
        // Check access control before proceeding
        try await validateStorageAccess(area: area, extensionId: extensionId, contextType: contextType)
        
        do {
            return try await provider.get(keys: keys, area: area, extensionId: extensionId)
        } catch let error as BrowserExtensionStorageProviderError {
            throw mapProviderError(error, area: area)
        }
    }
    
    /// Set values in storage
    /// - Parameters:
    ///   - items: Key-value pairs to store (values are JSON strings)
    ///   - area: Storage area to store in
    ///   - extensionId: Extension storing the data
    ///   - hasUnlimitedStorage: Whether extension has unlimited storage permission
    ///   - contextType: Trusted or untrusted context
    public func set(items: [String: String], area: BrowserExtensionStorageArea, extensionId: UUID, hasUnlimitedStorage: Bool, contextType: BrowserExtensionStorageContextType) async throws {
        guard let provider = storageProvider else {
            throw BrowserExtensionError.internalError("Storage provider not configured")
        }
        
        // Check access control before proceeding
        try await validateStorageAccess(area: area, extensionId: extensionId, contextType: contextType)
        
        do {
            // Get original values atomically from provider
            let originalValues = try await provider.set(items: items, area: area, extensionId: extensionId, hasUnlimitedStorage: hasUnlimitedStorage)
            
            // Compare and prepare changes for onChanged events
            var changes: [String: BrowserExtensionStorageChange] = [:]
            for (key, newValue) in items {
                let oldValue: String? = if originalValues.keys.contains(key) {
                    originalValues[key]!
                } else {
                    nil
                }

                // Only fire event if value actually changed
                if oldValue != newValue {
                    let change = BrowserExtensionStorageChange(
                        oldValue: oldValue,
                        newValue: newValue)
                    changes[key] = change
                }
            }
            
            // Fire onChanged event if there were actual changes
            if !changes.isEmpty {
                await fireOnChangedEvent(changes: changes, area: area, extensionId: extensionId)
            }
            
        } catch let error as BrowserExtensionStorageProviderError {
            throw mapProviderError(error, area: area)
        }
    }
    
    /// Remove keys from storage
    /// - Parameters:
    ///   - keys: Keys to remove
    ///   - area: Storage area to remove from
    ///   - extensionId: Extension requesting removal
    ///   - hasUnlimitedStorage: Whether extension has unlimited storage permission
    ///   - contextType: Trusted or untrusted context
    public func remove(keys: [String], area: BrowserExtensionStorageArea, extensionId: UUID, hasUnlimitedStorage: Bool, contextType: BrowserExtensionStorageContextType) async throws {
        guard let provider = storageProvider else {
            throw BrowserExtensionError.internalError("Storage provider not configured")
        }
        
        // Check access control before proceeding
        try await validateStorageAccess(area: area, extensionId: extensionId, contextType: contextType)
        
        do {
            // Get removed values atomically from provider
            let removedValues = try await provider.remove(keys: keys, area: area, extensionId: extensionId)
            
            // Prepare changes for onChanged events (removed items have nil newValue)
            var changes: [String: BrowserExtensionStorageChange] = [:]
            for (key, oldValue) in removedValues {
                // Only fire event if key actually existed
                if let oldValue = oldValue {
                    changes[key] = BrowserExtensionStorageChange(
                        oldValue: oldValue,
                        newValue: nil
                    )
                }
            }
            
            // Fire onChanged event if there were actual removals
            if !changes.isEmpty {
                await fireOnChangedEvent(changes: changes, area: area, extensionId: extensionId)
            }
            
        } catch let error as BrowserExtensionStorageProviderError {
            throw mapProviderError(error, area: area)
        }
    }
    
    /// Clear all data from storage area
    /// - Parameters:
    ///   - area: Storage area to clear
    ///   - extensionId: Extension requesting the clear
    ///   - hasUnlimitedStorage: Whether extension has unlimited storage permission
    ///   - contextType: Trusted or untrusted context
    public func clear(area: BrowserExtensionStorageArea, extensionId: UUID, hasUnlimitedStorage: Bool, contextType: BrowserExtensionStorageContextType) async throws {
        guard let provider = storageProvider else {
            throw BrowserExtensionError.internalError("Storage provider not configured")
        }
        
        // Check access control before proceeding
        try await validateStorageAccess(area: area, extensionId: extensionId, contextType: contextType)
        
        do {
            // Get cleared values atomically from provider
            let clearedValues = try await provider.clear(area: area, extensionId: extensionId)
            
            // Prepare changes for onChanged events (cleared items have nil newValue)
            var changes: [String: BrowserExtensionStorageChange] = [:]
            for (key, oldValue) in clearedValues {
                changes[key] = BrowserExtensionStorageChange(
                    oldValue: oldValue,
                    newValue: nil
                )
            }
            
            // Fire onChanged event if there were items to clear
            if !changes.isEmpty {
                await fireOnChangedEvent(changes: changes, area: area, extensionId: extensionId)
            }
            
        } catch let error as BrowserExtensionStorageProviderError {
            throw mapProviderError(error, area: area)
        }
    }
    
    /// Get storage usage information
    /// - Parameters:
    ///   - area: Storage area to check
    ///   - extensionId: Extension to check usage for
    ///   - hasUnlimitedStorage: Whether extension has unlimited storage permission
    ///   - contextType: Trusted or untrusted context
    /// - Returns: Bytes used and item count
    public func getUsage(area: BrowserExtensionStorageArea, extensionId: UUID, hasUnlimitedStorage: Bool, contextType: BrowserExtensionStorageContextType) async throws -> (bytesUsed: Int, itemCount: Int) {
        guard let provider = storageProvider else {
            throw BrowserExtensionError.internalError("Storage provider not configured")
        }
        
        // Check access control before proceeding
        try await validateStorageAccess(area: area, extensionId: extensionId, contextType: contextType)
        
        do {
            return try await provider.getUsage(area: area, extensionId: extensionId)
        } catch let error as BrowserExtensionStorageProviderError {
            throw mapProviderError(error, area: area)
        }
    }
    
    /// Set storage access level for a specific area
    /// - Parameters:
    ///   - accessLevel: Access level to set
    ///   - area: Storage area to configure (local, sync, or session; not managed)
    ///   - extensionId: Extension to configure
    public func setStorageAccessLevel(_ accessLevel: BrowserExtensionStorageAccessLevel, area: BrowserExtensionStorageArea, extensionId: UUID) async throws {
        guard let provider = storageProvider else {
            throw BrowserExtensionError.internalError("Storage provider not configured")
        }
        
        // Managed storage cannot have its access level changed
        if area == .managed {
            throw BrowserExtensionStorageError.managedStorageReadOnly
        }
        
        do {
            try await provider.setStorageAccessLevel(accessLevel, area: area, extensionId: extensionId)
        } catch let error as BrowserExtensionStorageProviderError {
            throw mapProviderError(error, area: area)
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Validate that the given context type has access to the storage area
    /// - Parameters:
    ///   - area: The storage area being accessed
    ///   - extensionId: The extension requesting access
    ///   - contextType: Whether this is from a trusted or untrusted context
    /// - Throws: BrowserExtensionStorageError if access is denied
    private func validateStorageAccess(area: BrowserExtensionStorageArea, extensionId: UUID, contextType: BrowserExtensionStorageContextType) async throws {
        // Check access control based on storage area
        switch area {
        case .local, .sync, .session:
            // These areas have configurable access levels
            guard let provider = storageProvider else {
                throw BrowserExtensionError.internalError("Storage provider not configured")
            }
            
            let accessLevel = await provider.getStorageAccessLevel(area: area, extensionId: extensionId)
            
            // Check if untrusted context is trying to access trusted-only storage
            if accessLevel == .trustedContexts && contextType == .untrusted {
                throw BrowserExtensionStorageError.storageAreaNotAvailable(area)
            }
            
        case .managed:
            // Managed storage has no access restrictions - always accessible
            break
        }
    }
    
    /// Fire onChanged events to registered listeners
    /// - Parameters:
    ///   - changes: Dictionary of key to change information.
    ///   - area: The storage area that changed
    ///   - extensionId: The extension whose storage changed
    private func fireOnChangedEvent(changes: [String: BrowserExtensionStorageChange], area: BrowserExtensionStorageArea, extensionId: UUID) async {
        guard let router = router else {
            logger.error("No router configured - skipping onChanged event for extension \(extensionId)", 
                        file: #file, line: #line, function: #function)
            return
        }
        
        logger.debug("Firing storage onChanged event for extension \(extensionId) in area \(area.rawValue): \(changes.keys.joined(separator: ", "))", 
                    file: #file, line: #line, function: #function)

        let encodedChanges = String(data: try! JSONEncoder().encode(changes), encoding: .utf8)!
        // Broadcast the onChanged event using the router
        await router.broadcastEvent(
            functionName: "__EXT_fireStorageChanged__",
            arguments: [encodedChanges, area.rawValue.asJSONFragment],
            extensionId: extensionId.uuidString
        )
    }
    
    /// Maps storage provider errors to framework errors
    private func mapProviderError(_ error: BrowserExtensionStorageProviderError, area: BrowserExtensionStorageArea) -> BrowserExtensionError {
        switch error.type {
        case .quotaExceeded:
            return .quotaExceeded
        case .invalidKey:
            return .valueError("Invalid key \(error.keys?.first ?? "unknown")")
        case .invalidValue:
            return .valueError("Invalid value \(error.message ?? "Invalid value")")
        case .permissionDenied:
            return .permissionDenied
        case .operationNotSupported:
            return .notAvailable
        case .backendError:
            return .internalError("Storage error")
        }
    }
}
