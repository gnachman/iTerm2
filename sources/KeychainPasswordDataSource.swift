//
//  KeychainPasswordDataSource.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/19/22.
//

import AppKit

fileprivate let serviceName = "iTerm2"

// Stores account name in label
fileprivate class ModernKeychainAccount: NSObject, PasswordManagerAccount {
    private let accountNameUserNameSeparator = "\u{2002}—\u{2002}"
    let accountName: String
    let userName: String
    private let keychainAccountName: String

    fileprivate init(accountName: String, userName: String) {
        self.accountName = accountName
        self.userName = userName
        keychainAccountName = userName.isEmpty ? accountName : accountName + accountNameUserNameSeparator + userName
    }

    fileprivate init?(_ dict: NSDictionary) {
        if let accountName = dict[kSecAttrLabel] as? String {
            self.accountName = accountName
            userName = (dict[kSecAttrAccount] as? String) ?? ""
            keychainAccountName = accountName + accountNameUserNameSeparator + userName
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
                                       account: userName,
                                       label: accountName)
    }

    private func set(password: String) throws {
        try SSKeychain.setPassword(password,
                                   forService: serviceName,
                                   account: userName,
                                   label: accountName)
    }

    private func delete() throws {
        try SSKeychain.deletePassword(forService: serviceName,
                                      account: userName,
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
            } else {
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
