//
//  CompanionKeychainQuery.swift
//  CompanionCore
//
//  One builder for the base companion keychain query (a generic-password scoped
//  by service + account, and optionally by access group). Three sites - the app's
//  PhoneIdentity, its migration SecItemStore, and the NSE's NSEFetcher - used to
//  hand-build byte-identical copies of this dictionary. A future change to the
//  query shape (e.g. adding kSecUseDataProtectionKeychain) made in one but not
//  the others would silently make reads/writes hit different item identities, so
//  it lives here, shared by all three (all link CompanionProtocol).
//

import Foundation
import Security

public enum CompanionKeychainQuery {
    /// generic-password query for (service, account), scoped to `accessGroup`
    /// when non-nil. Callers add kSecReturnData / kSecMatchLimit / kSecValueData
    /// as needed for their specific read/add.
    public static func base(service: String, account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
