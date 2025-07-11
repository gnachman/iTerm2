import Foundation
import BrowserExtensionShared

// MARK: - Base Storage Handler

/// Base class for storage handlers that eliminates code duplication
@MainActor
class BaseStorageHandler {
    
    /// Storage manager for handling operations (can be injected)
    var storageManager: BrowserExtensionStorageManager?
    
    /// Initialize with storage manager
    required init(storageManager: BrowserExtensionStorageManager?) {
        self.storageManager = storageManager
    }
    
    /// Extract string keys from AnyJSONCodable, handling both single strings and arrays
    func extractKeysForGet(from keys: AnyJSONCodable?) -> [String]? {
        guard let keys else {
            return nil
        }
        if let stringStringMap = keys.value as? [String: String] {
            return Array(stringStringMap.keys)
        }
        guard let encoded = keys.value as? String, let data = encoded.data(using: .utf8) else {
            return []
        }
        if let stringKey = try? JSONDecoder().decode(String.self, from: data) {
            return [stringKey]
        } else if let arrayKeys = try? JSONDecoder().decode([String].self, from: data) {
            return arrayKeys
        } else if let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            return Array(dict.keys)
        }

        return nil
    }

    func extractKeyToJSONMap(from obj: AnyJSONCodable?) -> [String: String] {
        guard let obj else {
            return [:]
        }
        return (obj.value as? [String: String]) ?? [:]
    }

    /// Extract string keys from AnyJSONCodable for remove operations (non-optional)
    func extractKeys(from keys: AnyJSONCodable) -> [String] {
        if let stringKey = keys.value as? String {
            return [stringKey]
        } else if let arrayKeys = keys.value as? [String] {
            return arrayKeys
        }
        
        return []
    }
    
    /// Common get operation for all storage areas
    func performGet(keys: [String]?, area: BrowserExtensionStorageArea, context: BrowserExtensionContext) async throws -> [String: String] {
        guard let storageManager = storageManager else {
            throw BrowserExtensionError.internalError("Storage manager not configured")
        }
        
        let hasUnlimitedStorage = context.hasPermission(.unlimitedStorage)
        
        let jsonStrings = try await storageManager.get(
            keys: keys,
            area: area,
            extensionId: context.browserExtension.id,
            hasUnlimitedStorage: hasUnlimitedStorage,
            contextType: context.contextType
        )
        
        return jsonStrings
    }
    
    /// Common set operation for all storage areas
    func performSet(items: [String: String], area: BrowserExtensionStorageArea, context: BrowserExtensionContext) async throws -> AnyJSONCodable {
        guard let storageManager = storageManager else {
            throw BrowserExtensionError.internalError("Storage manager not configured")
        }
        
        let hasUnlimitedStorage = context.hasPermission(.unlimitedStorage)
        
        try await storageManager.set(
            items: items,
            area: area,
            extensionId: context.browserExtension.id,
            hasUnlimitedStorage: hasUnlimitedStorage,
            contextType: context.contextType
        )
        return AnyJSONCodable(NSNull())
    }
    
    /// Common remove operation for all storage areas
    func performRemove(keys: [String], area: BrowserExtensionStorageArea, context: BrowserExtensionContext) async throws -> AnyJSONCodable {
        guard let storageManager = storageManager else {
            throw BrowserExtensionError.internalError("Storage manager not configured")
        }
        
        let hasUnlimitedStorage = context.hasPermission(.unlimitedStorage)
        
        try await storageManager.remove(
            keys: keys,
            area: area,
            extensionId: context.browserExtension.id,
            hasUnlimitedStorage: hasUnlimitedStorage,
            contextType: context.contextType
        )
        
        return AnyJSONCodable(NSNull())
    }
    
    /// Common clear operation for all storage areas
    func performClear(area: BrowserExtensionStorageArea, context: BrowserExtensionContext) async throws -> AnyJSONCodable {
        guard let storageManager = storageManager else {
            throw BrowserExtensionError.internalError("Storage manager not configured")
        }
        
        let hasUnlimitedStorage = context.hasPermission(.unlimitedStorage)
        
        try await storageManager.clear(
            area: area,
            extensionId: context.browserExtension.id,
            hasUnlimitedStorage: hasUnlimitedStorage,
            contextType: context.contextType
        )
        
        return AnyJSONCodable(NSNull())
    }
    
    /// Common setAccessLevel operation for all storage areas
    func performSetAccessLevel(details: [String: String], area: BrowserExtensionStorageArea, context: BrowserExtensionContext) async throws -> AnyJSONCodable {
        guard let storageManager = storageManager else {
            throw BrowserExtensionError.internalError("Storage manager not configured")
        }
        
        guard let accessLevelString = details["accessLevel"] else {
            throw BrowserExtensionError.internalError("Missing accessLevel in details")
        }
        guard context.contextType == .trusted else {
            throw BrowserExtensionError.internalError("Untrusted sender cannot setAccessLevel")
        }

        // Convert string to enum
        let accessLevel: BrowserExtensionStorageAccessLevel
        switch accessLevelString {
        case "TRUSTED_CONTEXTS":
            accessLevel = .trustedContexts
        case "TRUSTED_AND_UNTRUSTED_CONTEXTS":
            accessLevel = .trustedAndUntrustedContexts
        default:
            throw BrowserExtensionError.internalError("Invalid accessLevel: \(accessLevelString)")
        }
        
        try await storageManager.setStorageAccessLevel(
            accessLevel,
            area: area,
            extensionId: context.browserExtension.id
        )
        await context.router.setStorageAreaAllowedInUntrustedContexts(allowed: accessLevel == .trustedAndUntrustedContexts,
                                                                      in: area,
                                                                      extensionId: context.browserExtension.id)
        return AnyJSONCodable(NSNull())
    }
}

// MARK: - Storage Local Handlers

class StorageLocalGetHandler: BaseStorageHandler, StorageLocalGetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageLocalGetRequest, context: BrowserExtensionContext, namespace: String?) async throws -> StringToJSONObject {
        let keys = extractKeysForGet(from: request.keys)
        let nondefaults = try await performGet(keys: keys, area: .local, context: context)
        var result = extractKeyToJSONMap(from: request.keys)
        for key in nondefaults.keys {
            result[key] = nondefaults[key]
        }
        return StringToJSONObject(result)
    }
}

class StorageLocalSetHandler: BaseStorageHandler, StorageLocalSetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageLocalSetRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        _ = try await performSet(items: request.items, area: .local, context: context)
    }
}

class StorageLocalRemoveHandler: BaseStorageHandler, StorageLocalRemoveHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageLocalRemoveRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        let keys = extractKeys(from: request.keys)
        _ = try await performRemove(keys: keys, area: .local, context: context)
    }
}

class StorageLocalClearHandler: BaseStorageHandler, StorageLocalClearHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageLocalClearRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        _ = try await performClear(area: .local, context: context)
    }
}

class StorageLocalSetAccessLevelHandler: BaseStorageHandler, StorageLocalSetAccessLevelHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageLocalSetAccessLevelRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        _ = try await performSetAccessLevel(details: request.details, area: .local, context: context)
    }
}

// MARK: - Storage Sync Handlers

class StorageSyncGetHandler: BaseStorageHandler, StorageSyncGetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageSyncGetRequest, context: BrowserExtensionContext, namespace: String?) async throws -> StringToJSONObject {
        let keys = extractKeysForGet(from: request.keys)
        return StringToJSONObject(try await performGet(keys: keys, area: .sync, context: context))
    }
}

class StorageSyncSetHandler: BaseStorageHandler, StorageSyncSetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageSyncSetRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        _ = try await performSet(items: request.items, area: .sync, context: context)
    }
}

class StorageSyncRemoveHandler: BaseStorageHandler, StorageSyncRemoveHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageSyncRemoveRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        let keys = extractKeys(from: request.keys)
        _ = try await performRemove(keys: keys, area: .sync, context: context)
    }
}

class StorageSyncClearHandler: BaseStorageHandler, StorageSyncClearHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageSyncClearRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        _ = try await performClear(area: .sync, context: context)
    }
}

class StorageSyncSetAccessLevelHandler: BaseStorageHandler, StorageSyncSetAccessLevelHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageSyncSetAccessLevelRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        _ = try await performSetAccessLevel(details: request.details, area: .sync, context: context)
    }
}

// MARK: - Storage Session Handlers

class StorageSessionGetHandler: BaseStorageHandler, StorageSessionGetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageSessionGetRequest, context: BrowserExtensionContext, namespace: String?) async throws -> StringToJSONObject {
        let keys = extractKeysForGet(from: request.keys)
        return StringToJSONObject(try await performGet(keys: keys, area: .session, context: context))
    }
}

class StorageSessionSetHandler: BaseStorageHandler, StorageSessionSetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageSessionSetRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        _ = try await performSet(items: request.items, area: .session, context: context)
    }
}

class StorageSessionRemoveHandler: BaseStorageHandler, StorageSessionRemoveHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageSessionRemoveRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        let keys = extractKeys(from: request.keys)
        _ = try await performRemove(keys: keys, area: .session, context: context)
    }
}

class StorageSessionClearHandler: BaseStorageHandler, StorageSessionClearHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageSessionClearRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        _ = try await performClear(area: .session, context: context)
    }
}

class StorageSessionSetAccessLevelHandler: BaseStorageHandler, StorageSessionSetAccessLevelHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [.storage] }
    
    @MainActor
    func handle(request: StorageSessionSetAccessLevelRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        _ = try await performSetAccessLevel(details: request.details, area: .session, context: context)
    }
}

// MARK: - Storage Managed Handlers

class StorageManagedGetHandler: BaseStorageHandler, StorageManagedGetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [] } // Managed storage doesn't require explicit permission
    
    @MainActor
    func handle(request: StorageManagedGetRequest, context: BrowserExtensionContext, namespace: String?) async throws -> StringToJSONObject {
        let keys = extractKeysForGet(from: request.keys)
        return StringToJSONObject(try await performGet(keys: keys, area: .managed, context: context))
    }
}

class StorageManagedSetHandler: BaseStorageHandler, StorageManagedSetHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [] } // Managed storage doesn't require explicit permission
    
    @MainActor
    func handle(request: StorageManagedSetRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        // Managed storage is read-only for extensions
        throw BrowserExtensionStorageError.managedStorageReadOnly
    }
}

class StorageManagedRemoveHandler: BaseStorageHandler, StorageManagedRemoveHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [] } // Managed storage doesn't require explicit permission
    
    @MainActor
    func handle(request: StorageManagedRemoveRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        // Managed storage is read-only for extensions
        throw BrowserExtensionStorageError.managedStorageReadOnly
    }
}

class StorageManagedClearHandler: BaseStorageHandler, StorageManagedClearHandlerProtocol {
    var requiredPermissions: [BrowserExtensionAPIPermission] { [] } // Managed storage doesn't require explicit permission
    
    @MainActor
    func handle(request: StorageManagedClearRequest, context: BrowserExtensionContext, namespace: String?) async throws {
        // Managed storage is read-only for extensions
        throw BrowserExtensionStorageError.managedStorageReadOnly
    }
}
