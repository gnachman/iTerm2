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

        // Handle permission request based on type. The handler returns
        // (decision, persist). persist is false when the decision came
        // from a system-level state (Location Services off, OS prompt
        // declined, etc.) rather than from the user explicitly choosing
        // Allow or Block in our per-site dialog. Persisting a system
        // denial would lock the site out forever even after the user
        // re-enables the system permission.
        let decision: BrowserPermissionDecision
        let persist: Bool
        switch permissionType {
        case .notification:
            (decision, persist) = await handleNotificationPermissionRequest(origin: origin)
        case .geolocation:
            (decision, persist) = await handleGeolocationPermissionRequest(origin: origin)
        case .camera:
            (decision, persist) = await handleMediaPermissionRequest(camera: true, microphone: false, origin: origin)
        case .microphone:
            (decision, persist) = await handleMediaPermissionRequest(camera: false, microphone: true, origin: origin)
        case .cameraAndMicrophone:
            (decision, persist) = await handleMediaPermissionRequest(camera: true, microphone: true, origin: origin)
        case .audioPlayback:
            it_fatalError("Client should handle it themselves")
        }

        if persist {
            await savePermissionDecision(origin: origin, permissionType: permissionType, decision: decision)
        }
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

    private func handleMediaPermissionRequest(camera: Bool, microphone: Bool, origin: String) async -> (BrowserPermissionDecision, Bool) {
        let decision: BrowserPermissionDecision
        if camera && !microphone {
            decision = await showPermissionDialog(for: .camera, origin: origin)
        } else if microphone && !camera {
            decision = await showPermissionDialog(for: .microphone, origin: origin)
        } else if camera && microphone {
            decision = await showPermissionDialog(for: .cameraAndMicrophone, origin: origin)
        } else {
            it_fatalError()
        }
        return (decision, true)
    }

    private func handleGeolocationPermissionRequest(origin: String) async -> (BrowserPermissionDecision, Bool) {
        guard let handler = iTermBrowserGeolocationHandler.instance(for: user) else {
            return (.denied, false)
        }
        switch handler.systemAuthorizationStatus {
        case .denied:
            return (.denied, false)
        case .notDetermined:
            let granted = await handler.requestAuthorization(for: origin)
            if !granted {
                return (.denied, false)
            }
        case .systemAuthorized:
            break
        }
        let decision = await showPermissionDialog(for: .geolocation, origin: origin)
        return (decision, true)
    }

    // MARK: - Notification-Specific Implementation

    private func handleNotificationPermissionRequest(origin: String) async -> (BrowserPermissionDecision, Bool) {
        // First check if system notifications are available
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .denied:
            return (.denied, false)

        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                if !granted {
                    return (.denied, false)
                }
            } catch {
                DLog("Failed to request system notification permission: \(error)")
                return (.denied, false)
            }

        case .authorized, .provisional, .ephemeral:
            break

        @unknown default:
            return (.denied, false)
        }

        let decision = await showPermissionDialog(for: .notification, origin: origin)
        return (decision, true)
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
