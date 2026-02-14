// MARK: - Password Manager Protocol Data Structures
// These structs define the JSON protocol for communication between
// iTerm2 and password manager CLI implementations.
//
// Protocol Version: 0

import Foundation

public enum PasswordManagerProtocol {
    // MARK: - Handshake

    public struct HandshakeRequest: Codable {
        public var iTermVersion: String
        public var minProtocolVersion: Int
        public var maxProtocolVersion: Int
    }

    public struct HandshakeResponse: Codable {
        public var protocolVersion: Int
        public var name: String
        public var requiresMasterPassword: Bool
        public var canSetPasswords: Bool
        public var userAccounts: [UserAccount]?
        public var needsPathToDatabase: Bool
        public var databaseExtension: String?
        public var needsPathToExecutable: String?

        public init(protocolVersion: Int, name: String, requiresMasterPassword: Bool, canSetPasswords: Bool, userAccounts: [UserAccount]?, needsPathToDatabase: Bool, databaseExtension: String?, needsPathToExecutable: String?) {
            self.protocolVersion = protocolVersion
            self.name = name
            self.requiresMasterPassword = requiresMasterPassword
            self.canSetPasswords = canSetPasswords
            self.userAccounts = userAccounts
            self.needsPathToDatabase = needsPathToDatabase
            self.databaseExtension = databaseExtension
            self.needsPathToExecutable = needsPathToExecutable
        }
    }

    public struct RequestHeader: Codable {
        public var pathToDatabase: String?
        public var pathToExecutable: String?
        public var mode: Mode

        public enum Mode: String, Codable {
            case terminal
            case browser
        }
    }

    public struct UserAccount: Codable {
        public var name: String
        public var identifier: String
    }

    // MARK: - Login

    public struct LoginRequest: Codable {
        public var header: RequestHeader

        public var userAccountID: String?
        public var masterPassword: String?
    }

    public struct LoginResponse: Codable {
        public var token: String?

        public init(token: String?) {
            self.token = token
        }
    }

    // MARK: - List Accounts

    public struct ListAccountsRequest: Codable {
        public var header: RequestHeader

        public var userAccountID: String?
        public var token: String?
    }

    public struct ListAccountsResponse: Codable {
        public var accounts: [Account]

        public init(accounts: [Account]) {
            self.accounts = accounts
        }
    }

    public struct AccountIdentifier: Codable {
        public var accountID: String

        public init(accountID: String) {
            self.accountID = accountID
        }
    }

    public struct Account: Codable {
        public var identifier: AccountIdentifier
        public var userName: String
        public var accountName: String
        public var hasOTP: Bool

        public init(identifier: AccountIdentifier, userName: String, accountName: String, hasOTP: Bool) {
            self.identifier = identifier
            self.userName = userName
            self.accountName = accountName
            self.hasOTP = hasOTP
        }
    }

    // MARK: - Get Password

    public struct GetPasswordRequest: Codable {
        public var header: RequestHeader

        public var userAccountID: String?
        public var token: String?
        public var accountIdentifier: AccountIdentifier
    }

    public struct Password: Codable {
        public var password: String
        public var otp: String?

        public init(password: String, otp: String?) {
            self.password = password
            self.otp = otp
        }
    }

    // MARK: - Set Password

    public struct SetPasswordRequest: Codable {
        public var header: RequestHeader

        public var userAccountID: String?
        public var token: String?
        public var accountIdentifier: AccountIdentifier
        public var newPassword: String?
    }

    public struct SetPasswordResponse: Codable {
        public init() {}
    }

    // MARK: - Delete Account

    public struct DeleteAccountRequest: Codable {
        public var header: RequestHeader

        public var userAccountID: String?
        public var token: String?
        public var accountIdentifier: AccountIdentifier
    }

    public struct DeleteAccountResponse: Codable {
        public init() {}
    }

    // MARK: - Add Account

    public struct AddAccountRequest: Codable {
        public var header: RequestHeader

        public var userAccountID: String?
        public var token: String?
        public var userName: String
        public var accountName: String
        public var password: String?
    }

    public struct AddAccountResponse: Codable {
        public var accountIdentifier: AccountIdentifier

        public init(accountIdentifier: AccountIdentifier) {
            self.accountIdentifier = accountIdentifier
        }
    }

    // MARK: - Error Handling

    public struct ErrorResponse: Codable {
        public var error: String

        public init(error: String) {
            self.error = error
        }
    }
}
