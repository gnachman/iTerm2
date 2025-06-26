//
//  iTermBrowserPermissionsViewHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/23/25.
//

import WebKit
import Foundation

@available(macOS 11.0, *)
@objc protocol iTermBrowserPermissionsViewHandlerDelegate: AnyObject {
    @MainActor func permissionsViewHandlerDidRevokeAllPermissions(_ handler: iTermBrowserPermissionsViewHandler, for origin: String)
}

@available(macOS 11.0, *)
@objc(iTermBrowserPermissionsViewHandler)
@MainActor
class iTermBrowserPermissionsViewHandler: NSObject, iTermBrowserPageHandler {
    static let permissionsURL = URL(string: "\(iTermBrowserSchemes.about):permissions")!
    private let user: iTermBrowserUser

    weak var delegate: iTermBrowserPermissionsViewHandlerDelegate?

    init(user: iTermBrowserUser) {
        self.user = user
    }
}

@available(macOS 11.0, *)
@MainActor
extension iTermBrowserPermissionsViewHandler {
    // MARK: - Public Interface

    func generatePermissionsHTML() -> String {
        let script = iTermBrowserTemplateLoader.loadTemplate(named: "permissions-page",
                                                             type: "js",
                                                             substitutions: [:])
        return iTermBrowserTemplateLoader.loadTemplate(named: "permissions-page",
                                                       type: "html",
                                                       substitutions: ["PERMISSIONS_SCRIPT": script])
    }
    
    func start(urlSchemeTask: WKURLSchemeTask, url: URL) {
        let htmlToServe = generatePermissionsHTML()
        
        guard let data = htmlToServe.data(using: .utf8) else {
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserPermissionsViewHandler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode HTML"]))
            return
        }
        
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    func handlePermissionMessage(_ message: [String: Any], webView: WKWebView) async {
        DLog("Permission message received: \(message)")

        guard let action = message["action"] as? String else {
            DLog("No action in permission message")
            return
        }
        
        switch action {
        case "loadPermissions":
            DLog("Handling permission action: \(action)")
            let offset = message["offset"] as? Int ?? 0
            let limit = message["limit"] as? Int ?? 50
            let searchQuery = message["searchQuery"] as? String ?? ""
            let permissionTypeFilter = message["permissionTypeFilter"] as? String ?? ""
            let statusFilter = message["statusFilter"] as? String ?? ""
            await loadPermissions(offset: offset,
                                 limit: limit,
                                 searchQuery: searchQuery,
                                 permissionTypeFilter: permissionTypeFilter,
                                 statusFilter: statusFilter,
                                 webView: webView)

        case "revokePermission":
            if let origin = message["origin"] as? String,
               let permissionTypeString = message["permissionType"] as? String,
               let permissionType = BrowserPermissionType(rawValue: permissionTypeString) {
                await revokePermission(origin: origin, permissionType: permissionType, webView: webView)
            }

        case "revokeAllPermissions":
            if let origin = message["origin"] as? String {
                await revokeAllPermissions(for: origin, webView: webView)
            }

        case "clearAllPermissions":
            await clearAllPermissions(webView: webView)
            
        default:
            DLog("Unknown permission action: \(action)")
        }
    }
    
    // MARK: - Private Implementation
    
    private func loadPermissions(offset: Int, limit: Int, searchQuery: String, permissionTypeFilter: String, statusFilter: String, webView: WKWebView) async {
        DLog("Loading permissions: offset=\(offset), limit=\(limit), query='\(searchQuery)', typeFilter='\(permissionTypeFilter)', statusFilter='\(statusFilter)'")
        
        guard let database = await BrowserDatabase.instance(for: user) else {
            DLog("Failed to get database instance")
            await sendPermissions([], hasMore: false, to: webView)
            return
        }
        
        DLog("Got database instance, querying permissions...")
        
        var permissions = await database.getAllPermissions()
        
        // Apply filters
        if !permissionTypeFilter.isEmpty {
            if let filterType = BrowserPermissionType(rawValue: permissionTypeFilter) {
                permissions = permissions.filter { $0.permissionType == filterType }
            }
        }
        
        if !statusFilter.isEmpty {
            if let filterDecision = BrowserPermissionDecision(rawValue: statusFilter) {
                permissions = permissions.filter { $0.decision == filterDecision }
            }
        }
        
        // Apply search query
        if !searchQuery.isEmpty {
            let lowercaseQuery = searchQuery.lowercased()
            permissions = permissions.filter { permission in
                permission.origin.lowercased().contains(lowercaseQuery) ||
                permission.permissionType.displayName.lowercased().contains(lowercaseQuery)
            }
        }
        
        // Sort by creation date (newest first)
        permissions.sort { $0.createdAt > $1.createdAt }
        
        // Apply pagination
        let startIndex = offset
        let endIndex = min(startIndex + limit, permissions.count)
        let hasMore = endIndex < permissions.count
        let paginatedPermissions = Array(permissions[startIndex..<endIndex])
        
        DLog("Found \(permissions.count) total permissions, returning \(paginatedPermissions.count)")
        
        // Convert to data format for JavaScript
        let permissionsData: [[String: Any]] = paginatedPermissions.map { permission in
            [
                "origin": permission.origin,
                "permissionType": permission.permissionType.rawValue,
                "decision": permission.decision.rawValue,
                "createdAt": permission.createdAt.timeIntervalSince1970,
                "updatedAt": permission.updatedAt.timeIntervalSince1970
            ]
        }
        
        await sendPermissions(permissionsData, hasMore: hasMore, to: webView)
    }
    
    private func revokePermission(origin: String, permissionType: BrowserPermissionType, webView: WKWebView) async {
        guard let database = await BrowserDatabase.instance(for: user) else { return }

        let success = await database.revokePermission(origin: origin, permissionType: permissionType)
        if success {
            // Notify all browser instances to reload tabs containing this origin
            iTermBrowserPermissionManager.notifyPermissionRevoked(for: origin)
            
            await sendPermissionRevokedConfirmation(origin: origin, permissionType: permissionType, to: webView)
        }
    }
    
    private func revokeAllPermissions(for origin: String, webView: WKWebView) async {
        guard let database = await BrowserDatabase.instance(for: user) else { return }

        let success = await database.revokeAllPermissions(for: origin)
        if success {
            // Notify all browser instances to reload tabs containing this origin
            iTermBrowserPermissionManager.notifyPermissionRevoked(for: origin)
            
            delegate?.permissionsViewHandlerDidRevokeAllPermissions(self, for: origin)
            await sendAllPermissionsRevokedConfirmation(origin: origin, to: webView)
        }
    }
    
    private func clearAllPermissions(webView: WKWebView) async {
        guard let database = await BrowserDatabase.instance(for: user) else { return }
        
        // Get all permissions to revoke them properly
        let allPermissions = await database.getAllPermissions()
        
        // Group by origin for efficient delegation and notification
        let origins = Set(allPermissions.map { $0.origin })
        
        // Revoke all permissions (this will delete them from the database)
        for origin in origins {
            _ = await database.revokeAllPermissions(for: origin)
            
            // Notify all browser instances to reload tabs containing this origin
            iTermBrowserPermissionManager.notifyPermissionRevoked(for: origin)
            
            delegate?.permissionsViewHandlerDidRevokeAllPermissions(self, for: origin)
        }
        
        await sendAllPermissionsClearedConfirmation(to: webView)
    }
    
    @MainActor
    private func sendPermissions(_ permissions: [[String: Any]], hasMore: Bool, to webView: WKWebView) async {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: [
                "permissions": permissions,
                "hasMore": hasMore
            ], options: [])

            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let script = "window.onPermissionsLoaded && window.onPermissionsLoaded(\(jsonString)); 1"
                do {
                    let result = try await webView.evaluateJavaScript(script)
                    DLog("JavaScript executed successfully: \(String(describing: result))")
                } catch {
                    DLog("Failed to execute JavaScript: \(error)")
                }
            }
        } catch {
            DLog("Failed to serialize permissions: \(error)")
        }
    }
    
    @MainActor
    private func sendPermissionRevokedConfirmation(origin: String, permissionType: BrowserPermissionType, to webView: WKWebView) async {
        let script = "window.onPermissionRevoked && window.onPermissionRevoked('\(origin.replacingOccurrences(of: "'", with: "\\'"))', '\(permissionType.rawValue.replacingOccurrences(of: "'", with: "\\'"))'); 1"
        do {
            let result = try await webView.evaluateJavaScript(script)
            DLog("JavaScript executed successfully: \(String(describing: result))")
        } catch {
            DLog("Failed to execute JavaScript: \(error)")
        }
    }
    
    @MainActor
    private func sendAllPermissionsRevokedConfirmation(origin: String, to webView: WKWebView) async {
        let script = "window.onAllPermissionsRevoked && window.onAllPermissionsRevoked('\(origin.replacingOccurrences(of: "'", with: "\\'"))'); 1"
        do {
            let result = try await webView.evaluateJavaScript(script)
            DLog("JavaScript executed successfully: \(String(describing: result))")
        } catch {
            DLog("Failed to execute JavaScript: \(error)")
        }
    }
    
    @MainActor
    private func sendAllPermissionsClearedConfirmation(to webView: WKWebView) async {
        let script = "window.onAllPermissionsCleared && window.onAllPermissionsCleared(); 1"
        do {
            let result = try await webView.evaluateJavaScript(script)
            DLog("JavaScript executed successfully: \(String(describing: result))")
        } catch {
            DLog("Failed to execute JavaScript: \(error)")
        }
    }
    
    // MARK: - iTermBrowserPageHandler Protocol
    
    func injectJavaScript(into webView: WKWebView) {
        // Permissions pages don't need JavaScript injection beyond what's in the HTML
    }
    
    func resetState() {
        // Permissions handler doesn't maintain state that needs resetting
    }
}
