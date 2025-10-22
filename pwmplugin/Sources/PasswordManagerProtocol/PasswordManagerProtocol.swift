// MARK: - Password Manager Protocol Data Structures
// These structs define the JSON protocol for communication between
// iTerm2 and password manager CLI implementations.
//
// Protocol Version: 0

import Foundation

enum PasswordManagerProtocol {
    // MARK: - Handshake

    struct HandshakeRequest: Codable {
        var iTermVersion: String
        var minProtocolVersion: Int
        var maxProtocolVersion: Int
    }

    struct HandshakeResponse: Codable {
        var protocolVersion: Int
        var name: String
        var requiresMasterPassword: Bool
        var canSetPasswords: Bool
        var userAccounts: [UserAccount]?
        var needsPathToDatabase: Bool
        var databaseExtension: String?
        var needsPathToExecutable: String?
    }

    struct RequestHeader: Codable {
        var pathToDatabase: String?
        var pathToExecutable: String?
        var mode: Mode

        enum Mode: String, Codable {
            case terminal
            case browser
        }
    }

    struct UserAccount: Codable {
        var name: String
        var identifier: String
    }

    // MARK: - Login

    struct LoginRequest: Codable {
        var header: RequestHeader

        var userAccountID: String?
        var masterPassword: String?
    }

    struct LoginResponse: Codable {
        var token: String?
    }

    // MARK: - List Accounts

    struct ListAccountsRequest: Codable {
        var header: RequestHeader

        var userAccountID: String?
        var token: String?
    }

    struct ListAccountsResponse: Codable {
        var accounts: [Account]
    }

    struct AccountIdentifier: Codable {
        var accountID: String
    }

    struct Account: Codable {
        var identifier: AccountIdentifier
        var userName: String
        var accountName: String
        var hasOTP: Bool
    }

    // MARK: - Get Password

    struct GetPasswordRequest: Codable {
        var header: RequestHeader

        var userAccountID: String?
        var token: String?
        var accountIdentifier: AccountIdentifier
    }

    struct Password: Codable {
        var password: String
        var otp: String?
    }

    // MARK: - Set Password

    struct SetPasswordRequest: Codable {
        var header: RequestHeader

        var userAccountID: String?
        var token: String?
        var accountIdentifier: AccountIdentifier
        var newPassword: String?
    }

    struct SetPasswordResponse: Codable {
    }

    // MARK: - Delete Account

    struct DeleteAccountRequest: Codable {
        var header: RequestHeader

        var userAccountID: String?
        var token: String?
        var accountIdentifier: AccountIdentifier
    }

    struct DeleteAccountResponse: Codable {
    }

    // MARK: - Add Account

    struct AddAccountRequest: Codable {
        var header: RequestHeader

        var userAccountID: String?
        var token: String?
        var userName: String
        var accountName: String
        var password: String?
    }

    struct AddAccountResponse: Codable {
        var accountIdentifier: AccountIdentifier
    }

    // MARK: - Error Handling

    struct ErrorResponse: Codable {
        var error: String
    }
}
