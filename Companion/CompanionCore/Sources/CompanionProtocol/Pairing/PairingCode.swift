//
//  PairingCode.swift
//  CompanionCore
//
//  Parses the iterm2://pair URL encoded in the QR code that the macOS app
//  displays from iTerm2 > Companion Device Settings. The phone scans this code and
//  uses the parsed values to drive the Noise XK handshake (phone = initiator).
//
//  Two modes, selected by which endpoint parameter is present and tagged by the
//  version (see docs/companion-relay-design.md):
//
//  Direct (v1): connect straight to relay=
//  iterm2://pair?v=1&proto=Noise_XK_25519_ChaChaPoly_BLAKE2s&rs=q1F3hT&pid=f7c2a1b9&relay=https://relay.example.com
//
//  Resolved (v2): fetch the shard map from resolver= and connect to the owning host
//  iterm2://pair?v=2&proto=Noise_XK_25519_ChaChaPoly_BLAKE2s&rs=q1F3hT&pid=f7c2a1b9&resolver=https://resolver.example.com/
//

import Foundation

public struct PairingCode: Equatable, Sendable, Codable {
    /// The only protocol string this build understands. Anything else means
    /// the codes were produced by a newer macOS app than this phone build.
    public static let supportedProtocol = "Noise_XK_25519_ChaChaPoly_BLAKE2s"

    /// Direct mode: the QR carries a `relay=` origin the client connects to
    /// straight, with no shard map or resolver. This is the original format;
    /// existing beta users and self-hosted single relays use it.
    public static let directVersion = 1

    /// Resolved mode: the QR carries a `resolver=` URL *instead of* a relay
    /// origin. The client fetches the shard map from the resolver, computes the
    /// owning host, and connects there. This is the mode the managed, sharded
    /// fleet uses. See docs/companion-relay-design.md.
    public static let resolvedVersion = 2

    /// The pairing-code versions this build understands. The mode is selected by
    /// which parameter is present (`relay=` -> direct, `resolver=` -> resolved)
    /// and tagged by the version, so the two coexist indefinitely.
    public static let supportedVersions: Set<Int> = [directVersion, resolvedVersion]

    /// The version tag baked into the Noise handshake prologue. This numbers the
    /// handshake binding, which is a SEPARATE concern from the QR `v=` (that one
    /// numbers the rendezvous/endpoint format). They are independent and happen
    /// to both be 1 today only by coincidence, so this is its own literal, not
    /// derived from a QR version: both endpoints must derive the identical
    /// prologue for a pairing, so letting this track a QR version bump would
    /// change the binding for resolved pairings and break the handshake against
    /// every already-paired device. Bump this only on a real handshake change.
    private static let handshakePrologueVersion = 1

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

    /// The resolver URL: the control-plane endpoint the client asks which shard
    /// host serves its room, or nil for direct mode. When present the client
    /// resolves the room through it before connecting; when absent it connects
    /// the relay= origin directly. The client hits this URL as-is (the room name
    /// travels in a request header), so unlike relayOrigin a path is allowed (the
    /// resolver may be hosted at a subpath, e.g. behind a shared CDN);
    /// userinfo/query/fragment and non-https schemes are still refused.
    /// Canonicalized at parse time.
    public let resolverURL: String?

    public init(responderStaticPublicKey: Data,
                pairingID: String,
                relayOrigin: String? = nil,
                resolverURL: String? = nil) {
        self.responderStaticPublicKey = responderStaticPublicKey
        self.pairingID = pairingID
        self.relayOrigin = relayOrigin
        self.resolverURL = resolverURL
    }

    public enum ParseError: Error, Equatable {
        /// v is not a supported version (currently 1 or 2). The user should
        /// update the iOS app.
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
        /// resolver was present but not a valid https URL (had a non-https
        /// scheme, userinfo, query, fragment, or no host). A path is allowed.
        case invalidResolver

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
            case .invalidResolver:
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

    /// Canonicalize a resolver= value to an https URL (scheme + host + optional
    /// port + optional path), or throw .invalidResolver. Like canonicalRelayOrigin
    /// it rejects non-https schemes, userinfo, query, and fragment, so the client
    /// only ever talks to a trusted host. Unlike the relay origin it PERMITS a
    /// path, so the resolver can be hosted at a subpath (e.g. behind a shared
    /// CDN). The resolver is the base URL of the static shard map on that CDN: the
    /// client reads a single short-TTL `shardmap.json` from under it (see
    /// docs/companion-relay-design.md and ShardMapLoader), so the path is preserved
    /// verbatim, trailing slash included, as the root the client resolves that
    /// relative path against. Public so the mac can
    /// validate its operator-configured resolver URL with the exact same rule the
    /// phone applies to the QR.
    public static func canonicalResolverURL(_ raw: String) throws -> String {
        guard let c = URLComponents(string: raw),
              c.scheme?.lowercased() == "https",
              let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil else {
            throw ParseError.invalidResolver
        }
        var url = "https://\(host)"
        if let port = c.port {
            url += ":\(port)"
        }
        url += c.percentEncodedPath
        return url
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
        // assumes a particular field layout.
        let versionString = value("v")
        guard let versionString, let version = Int(versionString),
              supportedVersions.contains(version) else {
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

        // The mode is exclusive: a resolved (v2) code carries a resolver and no
        // relay; a direct (v1) code carries a relay origin (which may itself be
        // absent, meaning no transport). Parse only the field the version names,
        // so a stray parameter from the other mode is ignored rather than
        // producing a self-contradictory code.
        if version == resolvedVersion {
            guard let resolverRaw = value("resolver") else {
                throw ParseError.invalidResolver
            }
            return PairingCode(responderStaticPublicKey: key,
                               pairingID: pid,
                               resolverURL: try canonicalResolverURL(resolverRaw))
        }
        let relayOrigin = try value("relay").map { try canonicalRelayOrigin($0) }
        return PairingCode(responderStaticPublicKey: key,
                           pairingID: pid,
                           relayOrigin: relayOrigin)
    }

    /// The pairing-code version this code serializes as: resolved (v2) when it
    /// carries a resolver, direct (v1) otherwise. Derived rather than stored, so
    /// the version and the mode can never disagree (and so the Codable shape is
    /// unchanged for older stored codes, which decode with resolverURL nil = v1).
    public var version: Int {
        resolverURL != nil ? Self.resolvedVersion : Self.directVersion
    }

    /// The Noise prologue both peers mix into the handshake. Binding the
    /// pairing id here means a handshake captured for one QR code cannot be
    /// replayed against a different one. Both sides derive it identically from
    /// the pid, so it never travels on the wire. The version tag is the fixed
    /// handshakePrologueVersion, NOT this code's `version`: a resolved (v2)
    /// pairing must still handshake identically to a direct one, or the two
    /// endpoints (which may build codes carrying different fields) would derive
    /// different prologues and fail (see handshakePrologueVersion).
    public func handshakePrologue() -> Data {
        Data("iterm2-companion/v\(Self.handshakePrologueVersion)/pid:\(pairingID)".utf8)
    }

    /// Reconstruct the canonical URL. Used by the macOS app to build the QR
    /// payload, and by tests to round-trip.
    public func urlString() -> String {
        var components = URLComponents()
        components.scheme = "iterm2"
        components.host = "pair"
        var items = [
            URLQueryItem(name: "v", value: String(version)),
            URLQueryItem(name: "proto", value: Self.supportedProtocol),
            URLQueryItem(name: "rs", value: responderStaticPublicKey.base64URLEncodedString()),
            URLQueryItem(name: "pid", value: pairingID)
        ]
        if let relayOrigin {
            items.append(URLQueryItem(name: "relay", value: relayOrigin))
        }
        if let resolverURL {
            items.append(URLQueryItem(name: "resolver", value: resolverURL))
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
