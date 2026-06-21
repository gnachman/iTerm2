//
//  PairingCode.swift
//  CompanionCore
//
//  Parses the iterm2://pair URL encoded in the QR code that the macOS app
//  displays from iTerm2 > Companion Device Settings. The phone scans this code and
//  uses the parsed values to drive the Noise XK handshake (phone = initiator).
//
//  Example:
//  iterm2://pair?v=1&proto=Noise_XK_25519_ChaChaPoly_BLAKE2s&rs=q1F3hT&pid=f7c2a1b90e3d5a86
//

import Foundation

public struct PairingCode: Equatable, Sendable {
    /// The only protocol string this build understands. Anything else means
    /// the codes were produced by a newer macOS app than this phone build.
    public static let supportedProtocol = "Noise_XK_25519_ChaChaPoly_BLAKE2s"

    /// The only pairing-code version this build understands.
    public static let supportedVersion = 1

    /// Responder (mac) static public key. X25519, exactly 32 bytes.
    public let responderStaticPublicKey: Data

    /// Pairing / session id. Opaque to the phone; echoed to the transport so
    /// the mac can associate the connection with the QR code it displayed.
    public let pairingID: String

    /// The relay origin (scheme + host + optional port, e.g.
    /// "https://relay.example.com") this pairing uses to reach the peer, or nil
    /// if none is configured (in which case the pairing cannot connect, the
    /// relay is the only transport). Canonicalized at parse time: https only, no
    /// userinfo/path/query/fragment.
    public let relayOrigin: String?

    public init(responderStaticPublicKey: Data,
                pairingID: String,
                relayOrigin: String? = nil) {
        self.responderStaticPublicKey = responderStaticPublicKey
        self.pairingID = pairingID
        self.relayOrigin = relayOrigin
    }

    public enum ParseError: Error, Equatable {
        /// v != 1. The user should update the iOS app.
        case unsupportedVersion(found: String?)
        /// proto != supportedProtocol. The user should update the iOS app.
        case unsupportedProtocol(found: String?)
        /// rs was missing, not valid base64url, or not exactly 32 bytes.
        case invalidResponderKey
        /// The URL was not a well-formed iterm2://pair code.
        case malformedURL
        /// pid was missing or empty.
        case missingPairingID
        /// relay was present but not a bare https origin (had a non-https
        /// scheme, userinfo, path, query, fragment, or no host).
        case invalidRelay

        /// A user-facing message. Phrased per the product spec so version and
        /// protocol mismatches steer the user to update the app, while size or
        /// shape problems report the code itself as invalid.
        public var userMessage: String {
            switch self {
            case .unsupportedVersion:
                return "Upgrade the iOS app to the newest version to scan this code"
            case .unsupportedProtocol:
                return "Upgrade the iOS app to the newest version to scan this code"
            case .invalidResponderKey:
                return "This QR code is invalid"
            case .malformedURL:
                return "This QR code is not an iTerm2 pairing code"
            case .missingPairingID:
                return "This QR code is invalid"
            case .invalidRelay:
                return "This QR code is invalid"
            }
        }
    }

    /// Canonicalize a relay= value to a bare https origin (scheme + host +
    /// optional port), or throw .invalidRelay. Rejects non-https schemes,
    /// userinfo, non-empty path, query, and fragment, so the phone can only
    /// ever build endpoint paths against a trusted origin. Public so the mac
    /// can validate its operator-configured relay origin with the exact same
    /// rule the phone applies when parsing the QR, guaranteeing both ends agree.
    public static func canonicalRelayOrigin(_ raw: String) throws -> String {
        guard let c = URLComponents(string: raw),
              c.scheme?.lowercased() == "https",
              let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/" else {
            throw ParseError.invalidRelay
        }
        var origin = "https://\(host)"
        if let port = c.port {
            origin += ":\(port)"
        }
        return origin
    }

    /// Parse a scanned string. Returns the validated code or throws ParseError
    /// with a user-facing message.
    public static func parse(_ string: String) throws -> PairingCode {
        guard let components = URLComponents(string: string),
              components.scheme == "iterm2",
              components.host == "pair" else {
            throw ParseError.malformedURL
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        // Validate version before anything else so an unknown future shape is
        // reported as "update the app" rather than a more specific error that
        // assumes the v1 field layout.
        let versionString = value("v")
        guard let versionString, Int(versionString) == supportedVersion else {
            throw ParseError.unsupportedVersion(found: versionString)
        }

        let protocolString = value("proto")
        guard protocolString == supportedProtocol else {
            throw ParseError.unsupportedProtocol(found: protocolString)
        }

        guard let rs = value("rs"),
              let key = Data(base64URLEncoded: rs) else {
            throw ParseError.invalidResponderKey
        }
        guard key.count == 32 else {
            throw ParseError.invalidResponderKey
        }

        guard let pid = value("pid"), !pid.isEmpty else {
            throw ParseError.missingPairingID
        }

        let relayOrigin = try value("relay").map { try canonicalRelayOrigin($0) }

        return PairingCode(responderStaticPublicKey: key,
                           pairingID: pid,
                           relayOrigin: relayOrigin)
    }

    /// The Noise prologue both peers mix into the handshake. Binding the
    /// pairing id here means a handshake captured for one QR code cannot be
    /// replayed against a different one. Both sides derive it identically from
    /// the pid, so it never travels on the wire.
    public func handshakePrologue() -> Data {
        Data("iterm2-companion/v\(Self.supportedVersion)/pid:\(pairingID)".utf8)
    }

    /// Reconstruct the canonical URL. Used by the macOS app to build the QR
    /// payload, and by tests to round-trip.
    public func urlString() -> String {
        var components = URLComponents()
        components.scheme = "iterm2"
        components.host = "pair"
        var items = [
            URLQueryItem(name: "v", value: String(Self.supportedVersion)),
            URLQueryItem(name: "proto", value: Self.supportedProtocol),
            URLQueryItem(name: "rs", value: responderStaticPublicKey.base64URLEncodedString()),
            URLQueryItem(name: "pid", value: pairingID)
        ]
        if let relayOrigin {
            items.append(URLQueryItem(name: "relay", value: relayOrigin))
        }
        components.queryItems = items
        return components.string ?? ""
    }
}

extension Data {
    /// Decode base64url (RFC 4648 section 5: '-' and '_' substitutions, padding
    /// optional). Returns nil if the input is not valid base64url.
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Restore the padding that base64url usually omits.
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else {
            return nil
        }
        self = data
    }

    /// Encode as base64url without padding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
