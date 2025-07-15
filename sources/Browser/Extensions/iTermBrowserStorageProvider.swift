//
//  iTermBrowserStorageProvider.swift
//  iTerm2
//
//  Created by George Nachman on 7/11/25.
//

import WebExtensionsFramework

class iTermBrowserStorageProvider: BrowserExtensionStorageProvider {
    private let _database: BrowserDatabase
    private var ephemeralDatabases = [StorageKey: BrowserDatabase]()
    private var accessLevels = [StorageKey: BrowserExtensionStorageAccessLevel]()

    private func database(area: BrowserExtensionStorageArea, extensionId: UUID) async -> BrowserDatabase? {
        switch area {
        case .session:
            let key = StorageKey(area: area, extenstionId: extensionId)
            if let existing = ephemeralDatabases[key] {
                return existing
            }
            let db = await BrowserDatabase.makeEphemeralInstance()
            ephemeralDatabases[key] = db
            return db
        case .managed:
            return nil
        case .local, .sync:
            return _database
        }
    }

    private struct StorageKey: Hashable {
        var area: BrowserExtensionStorageArea
        var extenstionId: UUID
    }

    init(database: BrowserDatabase) {
        _database = database
    }

    func get(keys: [String]?,
             area: BrowserExtensionStorageArea,
             extensionId: UUID) async throws -> [String : String] {
        guard let database = await database(area: area, extensionId: extensionId) else {
            return [:]
        }
        if let keys {
            return try await database.getKeyValueStoreEntries(area: area.rawValue,
                                                              extensionId: extensionId.uuidString,
                                                              keys: Set(keys))
        }
        return try await database.getKeyValueStoreEntries(area: area.rawValue,
                                                          extensionId: extensionId.uuidString)
    }

    func set(items: [String : String],
             area: BrowserExtensionStorageArea,
             extensionId: UUID, hasUnlimitedStorage: Bool) async throws -> [String: String?] {
        guard let database = await database(area: area, extensionId: extensionId) else {
            return [:]
        }
        let oldValues = try await database.setKeyValueStoreEntries(area: area.rawValue,
                                                                   extensionId: extensionId.uuidString,
                                                                   newValues: items)

        var result = [String: String?]()
        for key in items.keys {
            result[key] = oldValues[key]
        }
        return result
    }
    
    func remove(keys: [String],
                area: BrowserExtensionStorageArea,
                extensionId: UUID) async throws -> [String: String?] {
        guard let database = await database(area: area, extensionId: extensionId) else {
            return keys.reduce(into: [:]) { $0[$1] = nil }
        }
        
        // Remove the keys
        var result = try await database.clearKeyValueStore(area: area.rawValue,
                                                           extensionId: extensionId.uuidString,
                                                           keys: Set(keys))

        // Return original values (nil for keys that didn't exist)
        for key in keys {
            if !result.keys.contains(key) {
                result[key] = nil
            }
        }
        return result
    }
    
    func clear(area: BrowserExtensionStorageArea,
               extensionId: UUID) async throws -> [String: String] {
        guard let database = await database(area: area, extensionId: extensionId) else {
            return [:]
        }
        
        // Clear all storage
        return try await database.clearKeyValueStore(area: area.rawValue,
                                                     extensionId: extensionId.uuidString)
    }
    
    func getUsage(area: BrowserExtensionStorageArea,
                  extensionId: UUID) async throws -> (bytesUsed: Int, itemCount: Int) {
        guard let database = await database(area: area, extensionId: extensionId) else {
            return (bytesUsed: 0, itemCount: 0)
        }
        let usage = await database.keyValueUsage(area: area.rawValue, extensionId: extensionId.uuidString)
        return (bytesUsed: usage.bytesUsed, itemCount: usage.itemCount)
    }
    
    func getQuota(for area: BrowserExtensionStorageArea,
                  hasUnlimitedStorage: Bool) -> BrowserExtensionStorageQuota? {
        switch area {
        case .local, .sync:  // sync is same as local because sync is not implemented yet
            if hasUnlimitedStorage {
                return BrowserExtensionStorageQuota.unlimited
            }
            return BrowserExtensionStorageQuota.localDefault
        case .session:
            return BrowserExtensionStorageQuota.sessionDefault
        case .managed:
            return BrowserExtensionStorageQuota(maxItems: 0, maxSizeBytes: 0, maxItemSizeBytes: 0)
        }
    }
    
    func getStorageAccessLevel(area: BrowserExtensionStorageArea, extensionId: UUID) async -> BrowserExtensionStorageAccessLevel {
        if let existing = accessLevels[.init(area: area, extenstionId: extensionId)] {
            return existing
        }
        switch area {
        case .session: return .trustedContexts
        case .local, .sync: return .trustedAndUntrustedContexts
        case .managed: return .trustedContexts
        }
    }
    
    func setStorageAccessLevel(_ accessLevel: BrowserExtensionStorageAccessLevel,
                               area: BrowserExtensionStorageArea,
                               extensionId: UUID) async throws {
        accessLevels[.init(area: area, extenstionId: extensionId)] = accessLevel
    }
    

}
