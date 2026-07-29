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
    /// - originURL: the server URL a pairing points at, e.g. the relay origin in
    ///   direct mode or the resolver URL in resolved mode; the host is extracted
    ///   from it and compared against `defaultHost`.
    public static func hostToDisclose(originURL: String?, default defaultHost: String) -> String? {
        guard let originURL,
              let host = URLComponents(string: originURL)?.host,
              !host.isEmpty,
              host != defaultHost else {
            return nil
        }
        return Punycode.encodedHost(host)
    }
}
