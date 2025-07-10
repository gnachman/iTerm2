import Foundation

/// Represents a parsed match pattern for host permissions
/// Reference: Documentation/manifest-fields/host_permissions.md
public struct BrowserExtensionMatchPattern: Equatable {
    
    /// The scheme component of the match pattern
    public let scheme: Scheme
    
    /// The host component of the match pattern
    public let host: String
    
    /// The path component of the match pattern
    public let path: String
    
    /// Represents the scheme portion of a match pattern
    public enum Scheme: Equatable {
        case http
        case https
        case any  // "*" - matches http and https only
        case allURLs  // "<all_urls>" - matches ALL schemes
        case file
        case ftp
        case chromeExtension
    }
    
    /// Errors that can occur when parsing match patterns
    public enum ParseError: Error, Equatable {
        case invalidFormat
        case invalidScheme(String)
    }
    
    /// Special match pattern for all URLs
    public static let allURLs = "<all_urls>"
    
    /// Initialize a match pattern from a string
    /// - Parameter pattern: The match pattern string
    /// - Throws: ParseError if the pattern is invalid
    public init(_ pattern: String) throws {
        // Handle special case
        if pattern == Self.allURLs {
            self.scheme = .allURLs
            self.host = "*"
            self.path = "/*"
            return
        }
        
        // Match pattern format: <scheme>://<host><path>
        guard let schemeDelimiterRange = pattern.range(of: "://") else {
            throw ParseError.invalidFormat
        }
        
        let schemeString = String(pattern[..<schemeDelimiterRange.lowerBound])
        let afterScheme = String(pattern[schemeDelimiterRange.upperBound...])
        
        // Parse scheme
        switch schemeString {
        case "http":
            self.scheme = .http
        case "https":
            self.scheme = .https
        case "*":
            self.scheme = .any
        case "file":
            self.scheme = .file
        case "ftp":
            self.scheme = .ftp
        case "chrome-extension":
            self.scheme = .chromeExtension
        default:
            throw ParseError.invalidScheme(schemeString)
        }
        
        // Parse host and path
        // For file:// URLs, there might be no host
        if scheme == .file && afterScheme.hasPrefix("/") {
            self.host = ""
            self.path = afterScheme
            return
        }
        
        // Find where the path starts (first / after the host)
        if let pathStartIndex = afterScheme.firstIndex(of: "/") {
            self.host = String(afterScheme[..<pathStartIndex])
            self.path = String(afterScheme[pathStartIndex...])
        } else {
            // No path specified, assume /*
            self.host = afterScheme
            self.path = "/*"
        }
    }
    
    /// Check if this pattern matches a given URL
    /// - Parameter url: The URL to check
    /// - Returns: true if the URL matches this pattern
    public func matches(_ url: URL) -> Bool {
        // Check scheme
        if !matchesScheme(url.scheme ?? "") {
            return false
        }
        
        // Check host
        if !matchesHost(url.host ?? "") {
            return false
        }
        
        // Check port
        if !matchesPort(url.port) {
            return false
        }
        
        // Check path
        if !matchesPath(url.path) {
            return false
        }
        
        return true
    }
    
    // MARK: - Private matching helpers
    
    private func matchesScheme(_ urlScheme: String) -> Bool {
        switch scheme {
        case .http:
            return urlScheme == "http"
        case .https:
            return urlScheme == "https"
        case .any:
            // In match patterns, * only matches http and https
            return urlScheme == "http" || urlScheme == "https"
        case .allURLs:
            // <all_urls> matches ALL schemes
            return true
        case .file:
            return urlScheme == "file"
        case .ftp:
            return urlScheme == "ftp"
        case .chromeExtension:
            return urlScheme == "chrome-extension"
        }
    }
    
    private func matchesHost(_ urlHost: String) -> Bool {
        // Get the host part without port for comparison
        let patternHost = host.contains(":") ? String(host.prefix(while: { $0 != ":" })) : host
        
        // Handle special case for all hosts
        if patternHost == "*" {
            return true
        }
        
        // Handle wildcard subdomain
        if patternHost.hasPrefix("*.") {
            let baseDomain = String(patternHost.dropFirst(2))
            // Check if urlHost ends with baseDomain
            if urlHost == baseDomain {
                return false // *.example.com doesn't match example.com
            }
            return urlHost.hasSuffix("." + baseDomain)
        }
        
        // Exact match
        return patternHost == urlHost
    }
    
    private func matchesPort(_ urlPort: Int?) -> Bool {
        // If pattern has wildcard port
        if host.hasSuffix(":*") {
            return true
        }
        
        // If pattern specifies a port
        if let colonIndex = host.lastIndex(of: ":") {
            let portString = String(host[host.index(after: colonIndex)...])
            if let patternPort = Int(portString) {
                let actualPort = urlPort ?? (scheme == .https ? 443 : 80)
                return patternPort == actualPort
            }
        }
        
        return true
    }
    
    private func matchesPath(_ urlPath: String) -> Bool {
        // Handle wildcard path
        if path == "/*" {
            return true
        }
        
        // Remove trailing wildcard for prefix matching
        if path.hasSuffix("*") {
            let prefix = String(path.dropLast())
            return urlPath.hasPrefix(prefix)
        }
        
        // Exact match
        return path == urlPath
    }
    
    // MARK: - Static helpers
    
    /// Check if a string is a valid match pattern
    /// - Parameter string: The string to check
    /// - Returns: true if it's a valid match pattern
    public static func isValid(_ string: String) -> Bool {
        do {
            _ = try BrowserExtensionMatchPattern(string)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Integration with Permission Parser

extension BrowserExtensionPermissionParser {
    
    /// Check if a permission string looks like a host pattern
    /// - Parameter permission: The permission string to check
    /// - Returns: true if it looks like a host pattern that should be in host_permissions
    public static func isHostPattern(_ permission: String) -> Bool {
        return BrowserExtensionMatchPattern.isValid(permission)
    }
}

