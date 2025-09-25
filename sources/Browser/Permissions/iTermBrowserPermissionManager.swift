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
@MainActor
class iTermBrowserPermissionManager: NSObject {
    private let user: iTermBrowserUser

    init(user: iTermBrowserUser) {
        self.user = user
    }
}

@available(macOS 11.0, *)
@MainActor
extension iTermBrowserPermissionManager {
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
        case .geolocation:
            decision = await handleGeolocationPermissionRequest(origin: origin)
        case .camera:
            decision = await handleMediaPermissionRequest(camera: true, microphone: false, origin: origin)
        case .microphone:
            decision = await handleMediaPermissionRequest(camera: false, microphone: true, origin: origin)
        case .cameraAndMicrophone:
            decision = await handleMediaPermissionRequest(camera: true, microphone: true, origin: origin)
        case .audioPlayback:
            it_fatalError("Client should handle it themselves")
        }
        
        await savePermissionDecision(origin: origin, permissionType: permissionType, decision: decision)
        return decision
    }
    
    func getPermissionDecision(for permissionType: BrowserPermissionType, origin: String) async -> BrowserPermissionDecision? {
        guard let database = await BrowserDatabase.instance(for: user) else {
            return nil
        }
        
        let permission = await database.getPermission(origin: origin, permissionType: permissionType)
        return permission?.decision
    }
    
    func revokePermission(for permissionType: BrowserPermissionType, origin: String) async -> Bool {
        guard let database = await BrowserDatabase.instance(for: user) else {
            return false
        }
        
        return await database.revokePermission(origin: origin, permissionType: permissionType)
    }
    
    func revokeAllPermissions(for origin: String) async -> Bool {
        guard let database = await BrowserDatabase.instance(for: user) else {
            return false
        }
        
        return await database.revokeAllPermissions(for: origin)
    }
    
    func getAllPermissions() async -> [BrowserPermissions] {
        guard let database = await BrowserDatabase.instance(for: user) else {
            return []
        }
        
        return await database.getAllPermissions()
    }
    
    // MARK: - iTermBrowserWebView Integration

    @available(macOS 12.0, *)
    func handleMediaCapturePermissionRequest(
        from webView: iTermBrowserWebView,
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
    
    func savePermissionDecision(origin: String, permissionType: BrowserPermissionType, decision: BrowserPermissionDecision) async {
        guard let database = await BrowserDatabase.instance(for: user) else {
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

    func resetPermission(origin: String, permissionType: BrowserPermissionType) async {
        guard let database = await BrowserDatabase.instance(for: user) else {
            DLog("Could not reset permission: database unavailable")
            return
        }

        await database.resetPermission(origin: origin, permissionType: permissionType)
        DLog("Reset \(permissionType) for \(origin)")
    }

    // MARK: - Private Helper Methods

    // MARK: - Geolocation-Specific Implementation

    private func handleMediaPermissionRequest(camera: Bool, microphone: Bool, origin: String) async -> BrowserPermissionDecision {
        if camera && !microphone {
            return await showPermissionDialog(for: .camera, origin: origin)
        } else if microphone && !camera {
            return await showPermissionDialog(for: .microphone, origin: origin)
        } else if camera && microphone {
            return await showPermissionDialog(for: .cameraAndMicrophone, origin: origin)
        } else {
            it_fatalError()
        }
    }

    private func handleGeolocationPermissionRequest(origin: String) async -> BrowserPermissionDecision {
        guard let handler = iTermBrowserGeolocationHandler.instance(for: user) else {
            return .denied
        }
        switch handler.systemAuthorizationStatus {
        case .denied:
            return .denied
        case .notDetermined:
            let granted = await handler.requestAuthorization(for: origin)
            if !granted {
                return .denied
            }
        case .systemAuthorized:
            break
        }
        // Show website permission dialog
        return await showPermissionDialog(for: .geolocation, origin: origin)
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
    
    // MARK: - Tab Reloading for Permission Revocation
    
    static let permissionRevokedNotification = NSNotification.Name("iTermBrowserPermissionRevoked")
    static let permissionRevokedOriginKey = "origin"
    
    static func notifyPermissionRevoked(for origin: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: permissionRevokedNotification,
                object: nil,
                userInfo: [permissionRevokedOriginKey: origin]
            )
        }
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
