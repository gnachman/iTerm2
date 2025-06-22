//
//  iTermBrowserPermissionManager.swift
//  iTerm2
//
//  Created by George Nachman on 6/22/25.
//

import Foundation
import UserNotifications
import WebKit

@available(macOS 11.0, *)
class iTermBrowserPermissionManager: NSObject {
    static let shared = iTermBrowserPermissionManager()
    
    // MARK: - Permission Management
    
    func requestPermission(for permissionType: BrowserPermissionType, origin: String) async -> BrowserPermissionDecision {
        // Check if we already have a decision for this origin and permission type
        if let existingDecision = await getPermissionDecision(for: permissionType, origin: origin) {
            return existingDecision
        }
        
        // Handle permission request based on type
        let decision: BrowserPermissionDecision
        switch permissionType {
        case .notification:
            decision = await handleNotificationPermissionRequest(origin: origin)
        case .geolocation, .camera, .microphone, .cameraAndMicrophone:
            // For now, deny these permissions but with logging for future implementation
            DLog("Permission request for \(permissionType.rawValue) from \(origin) - currently not supported, denying")
            decision = .denied
        }
        
        await savePermissionDecision(origin: origin, permissionType: permissionType, decision: decision)
        return decision
    }
    
    func getPermissionDecision(for permissionType: BrowserPermissionType, origin: String) async -> BrowserPermissionDecision? {
        guard let database = await BrowserDatabase.instance else {
            return nil
        }
        
        let permission = await database.getPermission(origin: origin, permissionType: permissionType)
        return permission?.decision
    }
    
    func revokePermission(for permissionType: BrowserPermissionType, origin: String) async -> Bool {
        guard let database = await BrowserDatabase.instance else {
            return false
        }
        
        return await database.revokePermission(origin: origin, permissionType: permissionType)
    }
    
    func revokeAllPermissions(for origin: String) async -> Bool {
        guard let database = await BrowserDatabase.instance else {
            return false
        }
        
        return await database.revokeAllPermissions(for: origin)
    }
    
    func getAllPermissions() async -> [BrowserPermissions] {
        guard let database = await BrowserDatabase.instance else {
            return []
        }
        
        return await database.getAllPermissions()
    }
    
    // MARK: - WKWebView Integration
    
    @available(macOS 12.0, *)
    func handleMediaCapturePermissionRequest(
        from webView: WKWebView,
        origin: WKSecurityOrigin,
        frame: WKFrameInfo,
        type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        let originString = Self.normalizeOrigin(from: origin)
        let browserPermissionType: BrowserPermissionType
        
        switch type {
        case .camera:
            browserPermissionType = .camera
        case .microphone:
            browserPermissionType = .microphone
        case .cameraAndMicrophone:
            browserPermissionType = .cameraAndMicrophone
        @unknown default:
            return .deny
        }
        
        let decision = await requestPermission(for: browserPermissionType, origin: originString)
        return decision == .granted ? .grant : .deny
    }
    
    // MARK: - Private Helper Methods
    
    private func savePermissionDecision(origin: String, permissionType: BrowserPermissionType, decision: BrowserPermissionDecision) async {
        guard let database = await BrowserDatabase.instance else {
            DLog("Could not save permission: database unavailable")
            return
        }
        
        let success = await database.savePermission(origin: origin, permissionType: permissionType, decision: decision)
        
        if success {
            DLog("Saved permission: \(permissionType.rawValue) for \(origin) = \(decision.rawValue)")
        } else {
            DLog("Failed to save permission to database")
        }
    }
    
    // MARK: - Notification-Specific Implementation
    
    private func handleNotificationPermissionRequest(origin: String) async -> BrowserPermissionDecision {
        // First check if system notifications are available
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .denied:
            // System notifications are denied, so we can't grant web notifications
            return .denied
            
        case .notDetermined:
            // Request system permission first
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                if !granted {
                    return .denied
                }
            } catch {
                DLog("Failed to request system notification permission: \(error)")
                return .denied
            }
            
        case .authorized, .provisional, .ephemeral:
            // System permission is available, continue to website permission
            break
            
        @unknown default:
            return .denied
        }
        
        // Show website permission dialog
        return await showPermissionDialog(for: .notification, origin: origin)
    }
    
    @MainActor
    private func showPermissionDialog(for permissionType: BrowserPermissionType, origin: String) async -> BrowserPermissionDecision {
        let alert = NSAlert()
        alert.messageText = "Allow \(permissionType.displayName)"
        alert.informativeText = "The website \(origin) wants to access \(permissionType.displayName.lowercased())."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Block")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .granted : .denied
    }
    
    // MARK: - Origin Utilities
    
    static func normalizeOrigin(from url: URL) -> String {
        let scheme = url.scheme ?? "https"
        let host = url.host ?? ""
        let port = url.port
        return buildOriginString(scheme: scheme, host: host, port: port)
    }
    
    static func normalizeOrigin(from origin: WKSecurityOrigin) -> String {
        let scheme = origin.protocol
        let host = origin.host
        let port = origin.port == 0 ? nil : Int(origin.port)
        return buildOriginString(scheme: scheme, host: host, port: port)
    }
    
    private static func buildOriginString(scheme: String, host: String, port: Int?) -> String {
        if let port = port, port != 80 && port != 443 {
            return "\(scheme)://\(host):\(port)"
        } else {
            return "\(scheme)://\(host)"
        }
    }
}
