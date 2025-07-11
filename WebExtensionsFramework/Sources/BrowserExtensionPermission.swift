import Foundation

/// Represents a parsed permission from the manifest
public enum BrowserExtensionPermission: Equatable {
    /// API permission (e.g., "storage", "tabs", "cookies")
    case api(BrowserExtensionAPIPermission)
    /// Unknown permission (for forward compatibility)
    case unknown(String)
}

/// Known API permissions
public enum BrowserExtensionAPIPermission: String, CaseIterable {
    // Core APIs
    case activeTab
    case alarms
    case bookmarks
    case browsingData
    case clipboardRead
    case clipboardWrite
    case contentSettings
    case contextMenus
    case cookies
    case debugger
    case declarativeContent
    case declarativeNetRequest
    case declarativeNetRequestFeedback
    case declarativeNetRequestWithHostAccess
    case declarativeWebRequest
    case desktopCapture
    case devtools
    case downloads
    case downloadsBeta = "downloads.beta"
    case downloadShelf = "downloads.shelf"
    case downloadUI = "downloads.ui"
    case enterprise_deviceAttributes = "enterprise.deviceAttributes"
    case enterprise_hardwarePlatform = "enterprise.hardwarePlatform"
    case enterprise_networkingAttributes = "enterprise.networkingAttributes"
    case enterprise_platformKeys = "enterprise.platformKeys"
    case experimental
    case fileBrowserHandler
    case fileSystemProvider
    case fontSettings
    case gcm
    case geolocation
    case history
    case identity
    case identityEmail = "identity.email"
    case idle
    case loginState
    case management
    case nativeMessaging
    case notifications
    case offscreen
    case pageCapture
    case platformKeys
    case power
    case printerProvider
    case printing
    case printingMetrics
    case privacy
    case processes
    case proxy
    case readingList
    case runtime
    case scripting
    case search
    case sessions
    case sidePanel
    case storage
    case system_cpu = "system.cpu"
    case system_display = "system.display"
    case system_memory = "system.memory"
    case system_storage = "system.storage"
    case tabCapture
    case tabGroups
    case tabs
    case topSites
    case tts
    case ttsEngine
    case unlimitedStorage
    case vpnProvider
    case wallpaper
    case webAuthenticationProxy
    case webNavigation
    case webRequest
    case webRequestBlocking
    case webRequestFilterResponse_extraHeaders = "webRequestFilterResponse.extraHeaders"
}

/// Parser for browser extension permissions
public struct BrowserExtensionPermissionParser {
    
    /// Parse a permission string into a BrowserExtensionPermission
    /// - Parameter permission: The permission string from the manifest
    /// - Returns: A parsed permission
    public static func parse(_ permission: String) -> BrowserExtensionPermission {
        if let apiPermission = BrowserExtensionAPIPermission(rawValue: permission) {
            return .api(apiPermission)
        } else {
            return .unknown(permission)
        }
    }
    
    /// Parse an array of permission strings
    /// - Parameter permissions: Array of permission strings from the manifest
    /// - Returns: Array of parsed permissions
    public static func parse(_ permissions: [String]) -> [BrowserExtensionPermission] {
        return permissions.map { parse($0) }
    }
    
    /// Check if a permission string is a known API permission
    /// - Parameter permission: The permission string to check
    /// - Returns: true if it's a known API permission
    public static func isKnownPermission(_ permission: String) -> Bool {
        return BrowserExtensionAPIPermission(rawValue: permission) != nil
    }
    
    /// Get all known API permission strings
    /// - Returns: Array of all known permission strings
    public static var allKnownPermissions: [String] {
        return BrowserExtensionAPIPermission.allCases.map { $0.rawValue }
    }
}

/// Extension to make working with manifest permissions easier
extension ExtensionManifest {
    
    /// Get parsed permissions
    public var parsedPermissions: [BrowserExtensionPermission]? {
        return permissions.map { BrowserExtensionPermissionParser.parse($0) }
    }
    
    /// Check if the manifest has a specific API permission
    /// - Parameter permission: The API permission to check for
    /// - Returns: true if the permission is present
    public func hasPermission(_ permission: BrowserExtensionAPIPermission) -> Bool {
        guard let permissions = permissions else { return false }
        return permissions.contains(permission.rawValue)
    }
    
    /// Get all unknown permissions (useful for debugging)
    public var unknownPermissions: [String]? {
        guard let parsed = parsedPermissions else { return nil }
        return parsed.compactMap { permission in
            if case .unknown(let value) = permission {
                return value
            }
            return nil
        }
    }
}
