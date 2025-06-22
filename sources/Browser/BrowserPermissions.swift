//
//  BrowserPermissions.swift
//  iTerm2
//
//  Created by George Nachman on 6/22/25.
//

import Foundation

enum BrowserPermissionType: String, CaseIterable {
    case notification = "notification"
    case camera = "camera"
    case microphone = "microphone"
    case cameraAndMicrophone = "cameraAndMicrophone"
    case geolocation = "geolocation"

    var displayName: String {
        switch self {
        case .notification:
            return "Notifications"
        case .camera:
            return "Camera"
        case .microphone:
            return "Microphone"
        case .cameraAndMicrophone:
            return "Camera and Microphone"
        case .geolocation:
            return "Location"
        }
    }
}

enum BrowserPermissionDecision: String, CaseIterable {
    case granted = "granted"
    case denied = "denied"
    
    var displayName: String {
        switch self {
        case .granted:
            return "Allowed"
        case .denied:
            return "Blocked"
        }
    }
}

struct BrowserPermissions {
    var origin: String
    var permissionType: BrowserPermissionType
    var decision: BrowserPermissionDecision
    var createdAt = Date()
    var updatedAt = Date()
    
    init(origin: String, permissionType: BrowserPermissionType, decision: BrowserPermissionDecision) {
        self.origin = origin
        self.permissionType = permissionType
        self.decision = decision
    }
    
    init(origin: String, permissionType: BrowserPermissionType, decision: BrowserPermissionDecision, createdAt: Date, updatedAt: Date) {
        self.origin = origin
        self.permissionType = permissionType
        self.decision = decision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension BrowserPermissions: iTermDatabaseElement {
    enum Columns: String {
        case origin
        case permissionType
        case decision
        case createdAt
        case updatedAt
    }
    
    static func schema() -> String {
        """
        create table if not exists BrowserPermissions
            (\(Columns.origin.rawValue) text not null,
             \(Columns.permissionType.rawValue) text not null,
             \(Columns.decision.rawValue) text not null,
             \(Columns.createdAt.rawValue) integer not null,
             \(Columns.updatedAt.rawValue) integer not null,
             PRIMARY KEY (\(Columns.origin.rawValue), \(Columns.permissionType.rawValue)));
        
        CREATE INDEX IF NOT EXISTS idx_browser_permissions_origin ON BrowserPermissions(\(Columns.origin.rawValue));
        CREATE INDEX IF NOT EXISTS idx_browser_permissions_type ON BrowserPermissions(\(Columns.permissionType.rawValue));
        CREATE INDEX IF NOT EXISTS idx_browser_permissions_created ON BrowserPermissions(\(Columns.createdAt.rawValue) DESC);
        """
    }
    
    static func migrations(existingColumns: [String]) -> [Migration] {
        // Future migrations can be added here
        return []
    }

    static func tableInfoQuery() -> String {
        "PRAGMA table_info(BrowserPermissions)"
    }
    
    func removeQuery() -> (String, [Any?]) {
        ("delete from BrowserPermissions where \(Columns.origin.rawValue) = ? AND \(Columns.permissionType.rawValue) = ?", [origin, permissionType.rawValue])
    }

    func appendQuery() -> (String, [Any?]) {
        ("""
        insert or replace into BrowserPermissions 
            (\(Columns.origin.rawValue),
             \(Columns.permissionType.rawValue),
             \(Columns.decision.rawValue),
             \(Columns.createdAt.rawValue),
             \(Columns.updatedAt.rawValue))
        values (?, ?, ?, ?, ?)
        """,
         [
            origin,
            permissionType.rawValue,
            decision.rawValue,
            createdAt.timeIntervalSince1970,
            updatedAt.timeIntervalSince1970
         ])
    }

    func updateQuery() -> (String, [Any?]) {
        ("""
        update BrowserPermissions set \(Columns.decision.rawValue) = ?,
                                      \(Columns.updatedAt.rawValue) = ?
        where \(Columns.origin.rawValue) = ? AND \(Columns.permissionType.rawValue) = ?
        """,
        [
            decision.rawValue,
            updatedAt.timeIntervalSince1970,
            
            // where clause
            origin,
            permissionType.rawValue
        ])
    }

    init?(dbResultSet result: iTermDatabaseResultSet) {
        guard let origin = result.string(forColumn: Columns.origin.rawValue),
              let permissionTypeString = result.string(forColumn: Columns.permissionType.rawValue),
              let permissionType = BrowserPermissionType(rawValue: permissionTypeString),
              let decisionString = result.string(forColumn: Columns.decision.rawValue),
              let decision = BrowserPermissionDecision(rawValue: decisionString),
              let createdAt = result.date(forColumn: Columns.createdAt.rawValue),
              let updatedAt = result.date(forColumn: Columns.updatedAt.rawValue)
        else {
            return nil
        }
        
        self.origin = origin
        self.permissionType = permissionType
        self.decision = decision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Query functionality

extension BrowserPermissions {
    static func getPermissionQuery(origin: String, permissionType: BrowserPermissionType) -> (String, [Any?]) {
        ("SELECT * FROM BrowserPermissions WHERE \(Columns.origin.rawValue) = ? AND \(Columns.permissionType.rawValue) = ?", [origin, permissionType.rawValue])
    }
    
    static func getPermissionsForOriginQuery(origin: String) -> (String, [Any?]) {
        ("SELECT * FROM BrowserPermissions WHERE \(Columns.origin.rawValue) = ? ORDER BY \(Columns.createdAt.rawValue) DESC", [origin])
    }
    
    static func getPermissionsByTypeQuery(permissionType: BrowserPermissionType) -> (String, [Any?]) {
        ("SELECT * FROM BrowserPermissions WHERE \(Columns.permissionType.rawValue) = ? ORDER BY \(Columns.createdAt.rawValue) DESC", [permissionType.rawValue])
    }
    
    static func getAllPermissionsQuery() -> (String, [Any?]) {
        ("SELECT * FROM BrowserPermissions ORDER BY \(Columns.createdAt.rawValue) DESC", [])
    }
    
    static func getGrantedPermissionsQuery(permissionType: BrowserPermissionType) -> (String, [Any?]) {
        ("SELECT * FROM BrowserPermissions WHERE \(Columns.permissionType.rawValue) = ? AND \(Columns.decision.rawValue) = ? ORDER BY \(Columns.createdAt.rawValue) DESC", [permissionType.rawValue, BrowserPermissionDecision.granted.rawValue])
    }
    
    static func deletePermissionQuery(origin: String, permissionType: BrowserPermissionType) -> (String, [Any?]) {
        ("DELETE FROM BrowserPermissions WHERE \(Columns.origin.rawValue) = ? AND \(Columns.permissionType.rawValue) = ?", [origin, permissionType.rawValue])
    }
    
    static func deleteAllPermissionsForOriginQuery(origin: String) -> (String, [Any?]) {
        ("DELETE FROM BrowserPermissions WHERE \(Columns.origin.rawValue) = ?", [origin])
    }
}
