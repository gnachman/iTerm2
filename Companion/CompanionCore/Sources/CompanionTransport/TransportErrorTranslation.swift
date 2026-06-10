//
//  TransportErrorTranslation.swift
//  CompanionCore
//
//  Translates Network.framework errors that carry semantic meaning for callers
//  into typed TransportError cases. Lives in CompanionTransport (not
//  CompanionProtocol) so the protocol layer stays free of Network imports.
//

import Foundation
import Network
import dnssd
import CompanionProtocol

extension TransportError {
    /// Map errors the UI must react to onto typed cases; pass everything else
    /// through unchanged. Currently: Bonjour's kDNSServiceErr_NoAuth, which is
    /// how the OS reports a local network privacy denial.
    static func translating(_ error: Error) -> Error {
        if let nwError = error as? NWError,
           case .dns(let code) = nwError,
           code == DNSServiceErrorType(kDNSServiceErr_NoAuth) {
            return TransportError.localNetworkAccessDenied
        }
        return error
    }
}
