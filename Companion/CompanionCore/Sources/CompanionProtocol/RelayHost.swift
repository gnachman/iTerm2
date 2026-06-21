//
//  RelayHost.swift
//  CompanionCore
//
//  The relay-host disclosure rule, shared by both pairing entry points so the
//  phone shows which relay a pairing uses whenever it is not the official
//  default. The relay removes the proximity that made a QR/link safe, so a
//  hostile pairing artifact can point the phone at an attacker's relay (or a
//  Unicode-lookalike of the official host); surfacing the host on the
//  confirmation screen lets the user notice. See docs/companion-relay-design.md.
//

import Foundation

public enum RelayHost {
    /// The relay host to surface to the user, or nil when there is nothing worth
    /// disclosing (the known default, or no usable host). A non-default host is
    /// returned in punycode so a confusable Unicode lookalike of the default
    /// cannot read as legitimate.
    public static func hostToDisclose(relayOrigin: String?, default defaultHost: String) -> String? {
        guard let relayOrigin,
              let host = URLComponents(string: relayOrigin)?.host,
              !host.isEmpty,
              host != defaultHost else {
            return nil
        }
        return Punycode.encodedHost(host)
    }
}
