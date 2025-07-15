import Foundation
@testable import WebExtensionsFramework

/// Mock storage provider for testing storage handlers
@MainActor
class MockBrowserExtensionStorageProvider: BrowserExtensionStorageProvider {
    
    // Storage: [extensionId][area][key] = jsonValue
    private var storage: [ExtensionID: [BrowserExtensionStorageArea: [String: String]]] = [:]
    
    // Storage access levels: [extensionId][area] = accessLevel
    private var accessLevels: [ExtensionID: [BrowserExtensionStorageArea: BrowserExtensionStorageAccessLevel]] = [:]
    private let defaultAccessLevels: [BrowserExtensionStorageArea: BrowserExtensionStorageAccessLevel] =
    [.local: .trustedAndUntrustedContexts,
     .sync: .trustedAndUntrustedContexts,
     .session: .trustedContexts,
     .managed: .trustedContexts
    ]

    // Track calls for verification
    var getCallCount = 0
    var setCallCount = 0
    var removeCallCount = 0
    var clearCallCount = 0
    var getUsageCallCount = 0
    
    // Last call parameters for verification
    var lastGetKeys: [String]?
    var lastGetArea: BrowserExtensionStorageArea?
    var lastGetExtensionId: ExtensionID?
    
    var lastSetItems: [String: String]?
    var lastSetArea: BrowserExtensionStorageArea?
    var lastSetExtensionId: ExtensionID?
    var lastSetHasUnlimitedStorage: Bool?
    
    // Configurable behaviors for testing
    var shouldThrowOnGet = false
    var shouldThrowOnSet = false
    var shouldThrowOnRemove = false
    var shouldThrowOnClear = false
    var shouldThrowOnSetAccessLevel = false
    var throwError: BrowserExtensionStorageProviderError?
    
    var isSessionStorageUnavailable = false
    var isSyncStorageUnavailable = false
    
    func get(keys: [String]?, area: BrowserExtensionStorageArea, extensionId: ExtensionID) async throws -> [String: String] {
        getCallCount += 1
        lastGetKeys = keys
        lastGetArea = area
        lastGetExtensionId = extensionId
        
        if shouldThrowOnGet, let error = throwError {
            throw error
        }
        
        guard let extensionStorage = storage[extensionId],
              let areaStorage = extensionStorage[area] else {
            return [:]
        }
        
        if let keys = keys {
            var result: [String: String] = [:]
            for key in keys {
                if let value = areaStorage[key] {
                    result[key] = value
                }
            }
            return result
        } else {
            return areaStorage
        }
    }
    
    func set(items: [String: String], area: BrowserExtensionStorageArea, extensionId: ExtensionID, hasUnlimitedStorage: Bool) async throws -> [String: String?] {
        setCallCount += 1
        lastSetItems = items
        lastSetArea = area
        lastSetExtensionId = extensionId
        lastSetHasUnlimitedStorage = hasUnlimitedStorage
        
        if shouldThrowOnSet, let error = throwError {
            throw error
        }
        
        // Managed storage is read-only
        if area == .managed {
            throw BrowserExtensionStorageProviderError(type: .operationNotSupported)
        }
        
        // Check quota limits (simplified for testing)
        if !hasUnlimitedStorage && area == .sync {
            let currentSize = getCurrentSize(extensionId: extensionId, area: area)
            let newSize = items.values.map { $0.count }.reduce(0, +)
            if currentSize + newSize > 100 * 1024 { // 100KB limit
                throw BrowserExtensionStorageProviderError(type: .quotaExceeded)
            }
        }
        
        // Initialize storage if needed
        if storage[extensionId] == nil {
            storage[extensionId] = [:]
        }
        if storage[extensionId]![area] == nil {
            storage[extensionId]![area] = [:]
        }
        
        // Capture original values before overwriting
        var originalValues: [String: String?] = [:]
        for key in items.keys {
            originalValues[key] = storage[extensionId]![area]![key]
        }
        
        // Store items
        for (key, value) in items {
            storage[extensionId]![area]![key] = value
        }
        
        return originalValues
    }
    
    func remove(keys: [String], area: BrowserExtensionStorageArea, extensionId: ExtensionID) async throws -> [String: String?] {
        removeCallCount += 1
        
        if shouldThrowOnRemove, let error = throwError {
            throw error
        }
        
        // Managed storage is read-only
        if area == .managed {
            throw BrowserExtensionStorageProviderError(type: .operationNotSupported)
        }
        
        
        guard let extensionStorage = storage[extensionId],
              var areaStorage = extensionStorage[area] else {
            // No storage exists, so all keys map to nil
            return keys.reduce(into: [:]) { $0[$1] = nil }
        }
        
        // Capture removed values before deleting
        var removedValues: [String: String?] = [:]
        for key in keys {
            removedValues[key] = areaStorage[key]
            areaStorage.removeValue(forKey: key)
        }
        
        storage[extensionId]![area] = areaStorage
        return removedValues
    }
    
    func clear(area: BrowserExtensionStorageArea, extensionId: ExtensionID) async throws -> [String: String] {
        clearCallCount += 1
        
        if shouldThrowOnClear, let error = throwError {
            throw error
        }
        
        // Managed storage is read-only
        if area == .managed {
            throw BrowserExtensionStorageProviderError(type: .operationNotSupported)
        }
        
        
        // Capture all values before clearing
        let clearedValues = storage[extensionId]?[area] ?? [:]
        
        if storage[extensionId] != nil {
            storage[extensionId]![area] = [:]
        }
        
        return clearedValues
    }
    
    func getUsage(area: BrowserExtensionStorageArea, extensionId: ExtensionID) async throws -> (bytesUsed: Int, itemCount: Int) {
        getUsageCallCount += 1
        
        guard let extensionStorage = storage[extensionId],
              let areaStorage = extensionStorage[area] else {
            return (bytesUsed: 0, itemCount: 0)
        }
        
        let bytesUsed = areaStorage.values.map { $0.count }.reduce(0, +)
        return (bytesUsed: bytesUsed, itemCount: areaStorage.count)
    }
    
    
    func getQuota(for area: BrowserExtensionStorageArea, hasUnlimitedStorage: Bool) -> BrowserExtensionStorageQuota? {
        if hasUnlimitedStorage {
            return .unlimited
        }
        
        switch area {
        case .local:
            return .localDefault
        case .sync:
            return .syncDefault
        case .session:
            return .sessionDefault
        case .managed:
            return nil // No quota for managed storage
        }
    }
    
    func getStorageAccessLevel(area: BrowserExtensionStorageArea, extensionId: ExtensionID) async -> BrowserExtensionStorageAccessLevel {
        return accessLevels[extensionId]?[area] ?? defaultAccessLevels[area] ?? .trustedContexts
    }
    
    func setStorageAccessLevel(_ accessLevel: BrowserExtensionStorageAccessLevel, area: BrowserExtensionStorageArea, extensionId: ExtensionID) async throws {
        if shouldThrowOnSetAccessLevel, let error = throwError {
            throw error
        }
        if accessLevels[extensionId] == nil {
            accessLevels[extensionId] = [:]
        }
        accessLevels[extensionId]![area] = accessLevel
    }
    
    // Helper methods for testing
    func reset() {
        storage.removeAll()
        accessLevels.removeAll()
        getCallCount = 0
        setCallCount = 0
        removeCallCount = 0
        clearCallCount = 0
        getUsageCallCount = 0
        
        shouldThrowOnGet = false
        shouldThrowOnSet = false
        shouldThrowOnRemove = false
        shouldThrowOnClear = false
        shouldThrowOnSetAccessLevel = false
        throwError = nil
        
        isSessionStorageUnavailable = false
        isSyncStorageUnavailable = false
    }
    
    func setStorageData(_ data: [String: String], area: BrowserExtensionStorageArea, extensionId: ExtensionID) {
        if storage[extensionId] == nil {
            storage[extensionId] = [:]
        }
        storage[extensionId]![area] = data
    }
    
    private func getCurrentSize(extensionId: ExtensionID, area: BrowserExtensionStorageArea) -> Int {
        guard let extensionStorage = storage[extensionId],
              let areaStorage = extensionStorage[area] else {
            return 0
        }
        return areaStorage.values.map { $0.count }.reduce(0, +)
    }
    
    // MARK: - Additional Testing Methods
    
    /// Clear all storage data for a specific extension
    func clearStorageData(for extensionId: ExtensionID) {
        storage.removeValue(forKey: extensionId)
        accessLevels.removeValue(forKey: extensionId)
    }
    
    /// Corrupt storage data for testing error scenarios
    func corruptData(for extensionId: ExtensionID) {
        // Simulate corruption by setting invalid JSON or missing data
        if storage[extensionId] == nil {
            storage[extensionId] = [:]
        }
        
        // Add corrupted data that would cause JSON parsing errors
        storage[extensionId]![.local] = ["__corrupted__": "invalid_json_data{"]
        storage[extensionId]![.sync] = ["__corrupted__": "invalid_json_data{"]
        storage[extensionId]![.session] = ["__corrupted__": "invalid_json_data{"]
        
        // Force errors on future operations
        shouldThrowOnGet = true
        shouldThrowOnSet = true
        throwError = BrowserExtensionStorageProviderError(type: .backendError)
    }
}
