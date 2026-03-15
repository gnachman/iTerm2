import Foundation
import Network

/// Utility for checking if a host is a local or private network address.
/// Used to determine if an AI provider is self-hosted (no API key required).
struct PrivateIPChecker {
    /// Returns true if the host represents a local or private network address.
    /// This includes:
    /// - localhost
    /// - .local domains (Bonjour/mDNS)
    /// - IPv4 loopback (127.0.0.0/8)
    /// - IPv4 private ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
    /// - IPv4 link-local (169.254.0.0/16)
    /// - IPv6 loopback (::1)
    /// - IPv6 link-local (fe80::/10)
    /// - IPv6 unique local (fc00::/7)
    static func isLocalOrPrivate(_ host: String) -> Bool {
        if host == "localhost" {
            return true
        }
        // .local domains (Bonjour/mDNS)
        if host.hasSuffix(".local") {
            return true
        }
        // Try IPv4 first
        if let ipv4 = IPv4Address(host) {
            return isLocalOrPrivateIPv4(ipv4)
        }
        // Try IPv6
        if let ipv6 = IPv6Address(host) {
            return isLocalOrPrivateIPv6(ipv6)
        }
        return false
    }

    static func isLocalOrPrivateIPv4(_ addr: IPv4Address) -> Bool {
        let bytes = addr.rawValue
        let octet1 = bytes[0]
        let octet2 = bytes[1]
        // Loopback: 127.0.0.0/8
        if octet1 == 127 {
            return true
        }
        // Private: 10.0.0.0/8
        if octet1 == 10 {
            return true
        }
        // Private: 172.16.0.0/12
        if octet1 == 172 && octet2 >= 16 && octet2 <= 31 {
            return true
        }
        // Private: 192.168.0.0/16
        if octet1 == 192 && octet2 == 168 {
            return true
        }
        // Link-local: 169.254.0.0/16
        if octet1 == 169 && octet2 == 254 {
            return true
        }
        return false
    }

    static func isLocalOrPrivateIPv6(_ addr: IPv6Address) -> Bool {
        let bytes = addr.rawValue
        // Loopback: ::1
        if addr == IPv6Address.loopback {
            return true
        }
        // Link-local: fe80::/10 (first 10 bits are 1111111010)
        // fe80 = 11111110 10000000, febf = 11111110 10111111
        if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 {
            return true
        }
        // Unique local: fc00::/7 (first 7 bits are 1111110)
        // fc00 or fd00
        if (bytes[0] & 0xfe) == 0xfc {
            return true
        }
        return false
    }
}
