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

    public enum PathKind: String, Codable {
        case file
        case url
    }

    // Custom commands are added to the ... menu of the password manager.
    public struct CustomCommand: Codable {
        public var name: String
        public var label: String
        public var icon: String?

        public init(name: String, label: String, icon: String?) {
            self.name = name
            self.label = label
            self.icon = icon
        }
    }

    // A custom setting for your adapter.
    public struct SettingsField: Codable {
        public var key: String
        public var label: String

        // Value to show in text field when it is empty
        public var placeholder: String?

        // Use a password text field?
        public var isSecret: Bool

        // Additional info shown below text field
        public var note: String?

        // Save this in keychain? If false, it just goes in user defaults.
        public var persistInKeychain: Bool

        public init(key: String, label: String, placeholder: String?, isSecret: Bool, note: String?, persistInKeychain: Bool) {
            self.key = key
            self.label = label
            self.placeholder = placeholder
            self.isSecret = isSecret
            self.note = note
            self.persistInKeychain = persistInKeychain
        }
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

        // Protocol extensions (v0 optional fields)
        // Defaults to .file if not set
        public var pathToDatabaseKind: PathKind?
        public var pathToDatabasePrompt: String?
        public var pathToDatabasePlaceholder: String?
        public var masterPasswordLabel: String?
        public var persistsCredentials: Bool?
        public var customCommands: [CustomCommand]?
        public var settingsFields: [SettingsField]?

        public init(protocolVersion: Int, name: String, requiresMasterPassword: Bool, canSetPasswords: Bool, userAccounts: [UserAccount]?, needsPathToDatabase: Bool, databaseExtension: String?, needsPathToExecutable: String?,
                    pathToDatabaseKind: PathKind? = nil, pathToDatabasePrompt: String? = nil, pathToDatabasePlaceholder: String? = nil, masterPasswordLabel: String? = nil, persistsCredentials: Bool? = nil, customCommands: [CustomCommand]? = nil, settingsFields: [SettingsField]? = nil) {
            self.protocolVersion = protocolVersion
            self.name = name
            self.requiresMasterPassword = requiresMasterPassword
            self.canSetPasswords = canSetPasswords
            self.userAccounts = userAccounts
            self.needsPathToDatabase = needsPathToDatabase
            self.databaseExtension = databaseExtension
            self.needsPathToExecutable = needsPathToExecutable
            self.pathToDatabaseKind = pathToDatabaseKind
            self.pathToDatabasePrompt = pathToDatabasePrompt
            self.pathToDatabasePlaceholder = pathToDatabasePlaceholder
            self.masterPasswordLabel = masterPasswordLabel
            self.persistsCredentials = persistsCredentials
            self.customCommands = customCommands
            self.settingsFields = settingsFields
        }
    }

    public struct RequestHeader: Codable {
        public var pathToDatabase: String?
        public var pathToExecutable: String?
        public var mode: Mode
        public var settings: [String: String]?

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

    // MARK: - Custom Commands

    public struct CustomCommandRequest: Codable {
        public var header: RequestHeader
        public var userAccountID: String?
        public var token: String?
        public var commandName: String
    }

    public struct CustomCommandResponse: Codable {
        public var message: String?

        public init(message: String?) {
            self.message = message
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
