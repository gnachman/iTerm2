//
//  iTermMachineIdentity.swift
//  iTerm2SharedARC
//
//  Evaluates the OSC 7 ?machineID=<version>:<value> token that shell integration
//  attaches to its file URL. The token lets us decide whether the reporting shell
//  runs on this same machine (and therefore shares our filesystem) by comparing a
//  machine identity both sides compute independently, instead of matching
//  hostnames (which break for VPN / Tailscale / mDNS names that don't equal any of
//  this machine's local names).
//
//  Version 1's value is HMAC-SHA256(fixed key, macOS kern.bootsessionuuid) as
//  lowercase hex: a per-boot identity shared by every process on this running
//  kernel. We send the HMAC rather than the raw bootsessionuuid only so the raw
//  per-boot UUID isn't echoed on the wire. The key is fixed and public, so the
//  token is NOT unforgeable - any static token echoed in OSC 7 can be replayed.
//

import Foundation
import CryptoKit

@objc(iTermMachineIdentity)
class iTermMachineIdentity: NSObject {
    // Locality asserted by a machineID token, or .Unknown to mean "no assertion;
    // fall back to hostname comparison". Rules:
    //   nil / malformed / unknown version         -> Unknown (fall back)
    //   known version, value == our value          -> Localhost
    //   known version, value empty or mismatched   -> Remote
    // An unknown version deliberately falls back rather than asserting Remote: a
    // future algorithm on a genuinely local Mac talking to an older iTerm should
    // still be detectable by hostname rather than forced to "remote".
    @objc(localityForMachineIDToken:)
    static func locality(forToken token: String?) -> VT100RemoteHostLocality {
        guard let token else {
            return .unknown
        }
        // Split on the FIRST colon only: "<version>:<value>". Current values (a
        // UUID) contain no colon, but delimiting only the version prefix keeps the
        // format open to future values that might.
        guard let colon = token.firstIndex(of: ":"),
              let version = Int(token[token.startIndex..<colon]) else {
            return .unknown
        }
        let value = String(token[token.index(after: colon)...])
        guard let ours = localValue(forVersion: version), !ours.isEmpty else {
            // We don't implement this version (or couldn't compute our own value),
            // so we can't verify. Fall back to hostname comparison.
            return .unknown
        }
        if value.isEmpty {
            // A positive "not this machine" assertion (e.g. a non-Darwin shell).
            return .remote
        }
        return value.caseInsensitiveCompare(ours) == .orderedSame ? .localhost : .remote
    }

    // Not a secret (see the file header). Distinct from KittyDnDMachineID.hmacKey
    // so the two machine-identity namespaces can't produce colliding tokens.
    private static let hmacKey = "iterm2-osc7-machine-id"

    // This machine's identity for a given algorithm version, or nil if we can't
    // compute it. Only version 1 is defined. Version 0 is reserved: shell
    // integration sends "0:" when the report is ours but the identity couldn't be
    // computed, so nil here yields .unknown (hostname fallback) while the OSC 7
    // still counts as first-party for prompt ownership.
    private static func localValue(forVersion version: Int) -> String? {
        switch version {
        case 1:
            return version1Value()
        default:
            return nil
        }
    }

    // HMAC-SHA256(hmacKey, message) as lowercase hex, matching `openssl dgst
    // -sha256 -hmac` and Python's hmac.hexdigest() that the shell scripts use.
    private static func hmacHex(_ message: String) -> String {
        let key = SymmetricKey(data: Data(hmacKey.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return code.map { String(format: "%02x", $0) }.joined()
    }

    // Testing: the full version-1 token ("1:<hmac>") this machine would match, so
    // tests can feed a token that classifies as .localhost without duplicating the
    // key or the HMAC.
    @objc(it_localVersion1TokenForTesting)
    static func localVersion1TokenForTesting() -> String? {
        guard let value = localValue(forVersion: 1) else {
            return nil
        }
        return "1:\(value)"
    }

    // kern.bootsessionuuid is fixed for the life of the process, so both the
    // syscall and the HMAC over it happen once. This is on the path of every OSC 7
    // report (roughly once per prompt in every session), so neither should repeat.
    // Lazy `let` initialization makes this thread-safe without a lock.
    private static let realBootSessionUUID: String? = sysctlString("kern.bootsessionuuid")
    private static let realVersion1Value: String? = realBootSessionUUID.flatMap {
        $0.isEmpty ? nil : hmacHex($0)
    }

    private static func version1Value() -> String? {
        // Testing override so localhost detection can be exercised without
        // rebooting. Mirrors fakeFullyQualifiedDomainName: read live so a change
        // takes effect for hosts reported afterward. Only this debug path pays for
        // an HMAC per report.
        let fake = iTermAdvancedSettingsModel.fakeBootSessionUUID()
        if let fake, !fake.isEmpty {
            return hmacHex(fake)
        }
        return realVersion1Value
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: buffer)
    }
}
