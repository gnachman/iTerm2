//
//  BrowserPermissions.swift
//  iTerm2
//
//  Created by George Nachman on 6/22/25.
//

import Foundation

enum BrowserPermissionType: String, CaseIterable, Hashable {
    case notification = "notification"
    case camera = "camera"
    case microphone = "microphone"
    case cameraAndMicrophone = "cameraAndMicrophone"
    case geolocation = "geolocation"
    case audioPlayback = "audioPlayback"

    var displayName: String {
        switch self {
        case .notification:
            return String(localized: "BrowserPermissions.Notifications", defaultValue: "Notifications", comment: "Name of the notifications permission")
        case .camera:
            return String(localized: "BrowserPermissions.Camera", defaultValue: "Camera", comment: "Name of the camera permission")
        case .microphone:
            return String(localized: "BrowserPermissions.Microphone", defaultValue: "Microphone", comment: "Name of the microphone permission")
        case .cameraAndMicrophone:
            return String(localized: "BrowserPermissions.CameraAndMicrophone", defaultValue: "Camera and Microphone", comment: "Name of the combined camera and microphone permission")
        case .geolocation:
            return String(localized: "BrowserPermissions.Location", defaultValue: "Location", comment: "Name of the geolocation permission")
        case .audioPlayback:
            return String(localized: "BrowserPermissions.AudioPlayback", defaultValue: "Audio Playback", comment: "Name of the audio playback permission")
        }
    }

    // A complete localized dialog title per permission type. We do not compose "Allow" with the
    // noun at runtime because that word order and grammar differ by language.
    var permissionDialogTitle: String {
        switch self {
        case .notification:
            return String(localized: "BrowserPermissions.AllowNotifications", defaultValue: "Allow Notifications", comment: "Title of the dialog asking to allow website notifications")
        case .camera:
            return String(localized: "BrowserPermissions.AllowCamera", defaultValue: "Allow Camera", comment: "Title of the dialog asking to allow camera access")
        case .microphone:
            return String(localized: "BrowserPermissions.AllowMicrophone", defaultValue: "Allow Microphone", comment: "Title of the dialog asking to allow microphone access")
        case .cameraAndMicrophone:
            return String(localized: "BrowserPermissions.AllowCameraAndMicrophone", defaultValue: "Allow Camera and Microphone", comment: "Title of the dialog asking to allow camera and microphone access")
        case .geolocation:
            return String(localized: "BrowserPermissions.AllowLocation", defaultValue: "Allow Location", comment: "Title of the dialog asking to allow location access")
        case .audioPlayback:
            return String(localized: "BrowserPermissions.AllowAudioPlayback", defaultValue: "Allow Audio Playback", comment: "Title of the dialog asking to allow audio playback")
        }
    }

    // A complete localized request message per permission type. The origin is a self-contained value
    // (a hostname), so interpolating it is safe; the capability noun is not composed at runtime.
    func accessRequestMessage(forOrigin origin: String) -> String {
        switch self {
        case .notification:
            return String(localized: "BrowserPermissions.NotificationRequest", defaultValue: "The website \(origin) wants to send you notifications.", comment: "Message asking to allow a website to send notifications; the placeholder is a hostname")
        case .camera:
            return String(localized: "BrowserPermissions.CameraRequest", defaultValue: "The website \(origin) wants to use your camera.", comment: "Message asking to allow a website to use the camera; the placeholder is a hostname")
        case .microphone:
            return String(localized: "BrowserPermissions.MicrophoneRequest", defaultValue: "The website \(origin) wants to use your microphone.", comment: "Message asking to allow a website to use the microphone; the placeholder is a hostname")
        case .cameraAndMicrophone:
            return String(localized: "BrowserPermissions.CameraAndMicrophoneRequest", defaultValue: "The website \(origin) wants to use your camera and microphone.", comment: "Message asking to allow a website to use the camera and microphone; the placeholder is a hostname")
        case .geolocation:
            return String(localized: "BrowserPermissions.LocationRequest", defaultValue: "The website \(origin) wants to know your location.", comment: "Message asking to allow a website to access location; the placeholder is a hostname")
        case .audioPlayback:
            return String(localized: "BrowserPermissions.AudioPlaybackRequest", defaultValue: "The website \(origin) wants to play audio.", comment: "Message asking to allow a website to play audio; the placeholder is a hostname")
        }
    }
}

enum BrowserPermissionDecision: String, CaseIterable {
    case granted = "granted"
    case denied = "denied"
    
    var displayName: String {
        switch self {
        case .granted:
            return String(localized: "BrowserPermissions.Allowed", defaultValue: "Allowed", comment: "Permission decision: granted")
        case .denied:
            return String(localized: "BrowserPermissions.Blocked", defaultValue: "Blocked", comment: "Permission decision: denied")
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
