//
//  KeychainPasswordDataSource.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/19/22.
//

import AppKit

fileprivate let serviceName = "iTerm2"

// Used to store account name in label and username in account. That was a mistake.
// Now it stores username and account name in accountName and account name in label (just for looks in keychain access)
fileprivate class ModernKeychainAccount: NSObject, PasswordManagerAccount {
    private let accountNameUserNameSeparator = "\u{2002}—\u{2002}"
    let accountName: String
    let userName: String
    private var keychainAccountName: String
    private var defective: Bool

    fileprivate init(accountName: String, userName: String) {
        self.accountName = accountName
        self.userName = userName
        defective = false
        keychainAccountName = accountName + accountNameUserNameSeparator + userName
    }

    fileprivate init?(_ dict: NSDictionary) {
        if let combinedAccountName = dict[kSecAttrAccount] as? String {
            if let range = combinedAccountName.range(of: accountNameUserNameSeparator) {
                accountName = String(combinedAccountName[..<range.lowerBound])
                userName = String(combinedAccountName[range.upperBound...])
                // Code path for well formed entries in 3.5.1beta3 and later.
                keychainAccountName = accountName + accountNameUserNameSeparator + userName
                defective = false
                DLog("Well-formed modern account username=\(userName) accountName=\(accountName) combined=\(combinedAccountName)")
            } else if let label = dict[kSecAttrLabel] as? String {
                // Code path for misbegotten entries created by 3.5.0.
                // It stored username in account and accountName in label.
                // But label is part of the value, not part of the key, so it's not a good place to store the account name.
                // Unfortunately username ended up being the unique key.
                DLog("Defective modern account label=\(label) combined=\(combinedAccountName)")
                accountName = label
                userName = combinedAccountName;
                keychainAccountName = combinedAccountName
                defective = true
            } else {
                return nil
            }
        } else {
            return nil
        }
    }

    var displayString: String {
        return keychainAccountName
    }

    func fetchPassword(_ completion: (String?, String?, Error?) -> ()) {
        do {
            completion(try password(), nil, nil)
        } catch {
            completion(nil, nil, error)
        }
    }

    func set(password: String, completion: (Error?) -> ()) {
        do {
            try set(password: password)
            completion(nil)
        } catch {
            completion(error)
        }
    }

    func delete(_ completion: (Error?) -> ()) {
        do {
            try delete()
            completion(nil)
        } catch {
            completion(error)
        }
    }

    private func password() throws -> String {
        return try SSKeychain.password(forService: serviceName,
                                       account: keychainAccountName,
                                       label: accountName)
    }

    private func set(password: String) throws {
        if defective {
            // Add a well-formed entry
            let correctKeychainAccountName = userName.isEmpty ? accountName : accountName + accountNameUserNameSeparator + userName
            try SSKeychain.setPassword(password,
                                       forService: serviceName,
                                       account: correctKeychainAccountName,
                                       label: accountName)
            // Delete the defective entry
            try SSKeychain.deletePassword(forService: serviceName,
                                          account: keychainAccountName,
                                          label: accountName)
            // Update internal state to be non-defective.
            keychainAccountName = correctKeychainAccountName
            defective = false
        } else {
            try SSKeychain.setPassword(password,
                                       forService: serviceName,
                                       account: keychainAccountName,
                                       label: accountName)
        }
    }

    private func delete() throws {
        try SSKeychain.deletePassword(forService: serviceName,
                                      account: keychainAccountName,
                                      label: accountName)
    }

    func matches(filter: String) -> Bool {
        return _matches(filter: filter)
    }
}

// Stores account name and user name together in account name and makes label "iTerm2"
fileprivate class LegacyKeychainAccount: NSObject, PasswordManagerAccount {
    private let accountNameUserNameSeparator = "\u{2002}—\u{2002}"

    let accountName: String
    let userName: String
    private let keychainAccountName: String

    fileprivate init?(_ dict: NSDictionary) {
        if let combinedAccountName = dict[kSecAttrAccount] as? String,
            dict[kSecAttrLabel] as? String == "iTerm2" {
            if let range = combinedAccountName.range(of: accountNameUserNameSeparator) {
                accountName = String(combinedAccountName[..<range.lowerBound])
                userName = String(combinedAccountName[range.upperBound...])
                DLog("Two-part legacy username=\(userName) account=\(accountName) combined=\(combinedAccountName)")
            } else {
                DLog("One-part legacy combined=\(combinedAccountName), using empty username")
                accountName = combinedAccountName
                userName = ""
            }
            keychainAccountName = combinedAccountName
        } else {
            return nil
        }
    }

    var displayString: String {
        return keychainAccountName
    }

    func fetchPassword(_ completion: (String?, String?, Error?) -> ()) {
        do {
            completion(try password(), nil, nil)
        } catch {
            completion(nil, nil, error)
        }
    }

    func set(password: String, completion: (Error?) -> ()) {
        do {
            try set(password: password)
            completion(nil)
        } catch {
            completion(error)
        }
    }

    func delete(_ completion: (Error?) -> ()) {
        do {
            try delete()
            completion(nil)
        } catch {
            completion(error)
        }
    }

    private func password() throws -> String {
        return try SSKeychain.password(forService: serviceName,
                                       account: keychainAccountName)
    }

    private func set(password: String) throws {
        try SSKeychain.setPassword(password,
                                   forService: serviceName,
                                   account: keychainAccountName,
                                   error: ())
    }

    private func delete() throws {
        try SSKeychain.deletePassword(forService: serviceName,
                                      account: keychainAccountName,
                                      error: ())
    }

    func matches(filter: String) -> Bool {
        return _matches(filter: filter)
    }
}

class KeychainPasswordDataSource: NSObject, PasswordManagerDataSource {
    private var openPanel: NSOpenPanel?
    private static let keychain = KeychainPasswordDataSource()

    func fetchAccounts(_ completion: @escaping ([PasswordManagerAccount]) -> ()) {
        completion(self.accounts)
    }

    func add(userName: String, accountName: String, password: String, completion: (PasswordManagerAccount?, Error?) -> ()) {
        let account = ModernKeychainAccount(accountName: accountName, userName: userName)
        account.set(password: password) { error in
            if let error = error {
                completion(nil, error)
            } else {
                completion(account, nil)
            }
        }
    }

    func reload(_ completion: () -> ()) {
        completion()
    }

    private var accounts: [PasswordManagerAccount] {
        guard let dicts = SSKeychain.accounts(forService: serviceName) as? [NSDictionary] else {
            return []
        }
        return dicts.compactMap {
            LegacyKeychainAccount($0) ?? ModernKeychainAccount($0)
        }
    }

    var autogeneratedPasswordsOnly: Bool {
        return false
    }

    func checkAvailability() -> Bool {
        return true
    }

    func resetErrors() {
    }

    func consolidateAvailabilityChecks(_ block: () -> ()) {
        block()
    }
}
