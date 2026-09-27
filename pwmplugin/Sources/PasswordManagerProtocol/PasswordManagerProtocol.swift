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

    public struct AddAccountToggle: Codable {
        public var key: String
        public var label: String
        public var note: String?
        public var defaultValue: Bool

        public init(key: String, label: String, note: String?, defaultValue: Bool) {
            self.key = key
            self.label = label
            self.note = note
            self.defaultValue = defaultValue
        }
    }

    // Declares a pre-existing keychain entry whose value should be migrated into
    // the adapter's master-password slot. The host runs this once, adapter-agnostically:
    // if the master-password slot is empty it copies the value up, then deletes the
    // orphaned entry only after the copy is confirmed. Lets an adapter retire an old
    // credential-storage location without baking adapter specifics into the host.
    public struct LegacyCredentialMigration: Codable {
        // The keychain account name of the legacy entry, stored under the adapter's
        // own service name.
        public var fromKeychainAccount: String

        public init(fromKeychainAccount: String) {
            self.fromKeychainAccount = fromKeychainAccount
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
        public var addAccountToggles: [AddAccountToggle]?
        public var legacyCredentialMigrations: [LegacyCredentialMigration]?
        /// When true, the adapter can edit a record's fields (title/login/password) in
        /// place, preserving OTP and custom fields. The host then renames via an in-place
        /// update instead of delete-then-re-add. nil means false.
        public var canEditInPlace: Bool?
        /// When true, Add must be given a non-empty password because the adapter stores the
        /// password field verbatim (a blank field would persist an empty password). Adapters
        /// that omit an empty password when adding leave this nil/false.
        public var requiresPasswordForAdd: Bool?

        public init(protocolVersion: Int, name: String, requiresMasterPassword: Bool, canSetPasswords: Bool, userAccounts: [UserAccount]?, needsPathToDatabase: Bool, databaseExtension: String?, needsPathToExecutable: String?,
                    pathToDatabaseKind: PathKind? = nil, pathToDatabasePrompt: String? = nil, pathToDatabasePlaceholder: String? = nil, masterPasswordLabel: String? = nil, persistsCredentials: Bool? = nil, customCommands: [CustomCommand]? = nil, settingsFields: [SettingsField]? = nil, addAccountToggles: [AddAccountToggle]? = nil, legacyCredentialMigrations: [LegacyCredentialMigration]? = nil, canEditInPlace: Bool? = nil, requiresPasswordForAdd: Bool? = nil) {
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
            self.addAccountToggles = addAccountToggles
            self.legacyCredentialMigrations = legacyCredentialMigrations
            self.canEditInPlace = canEditInPlace
            self.requiresPasswordForAdd = requiresPasswordForAdd
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
        /// Non-fatal listing issue (e.g. Nested Shared Folder list failed while classic succeeded).
        public var warning: String?

        public init(accounts: [Account], warning: String? = nil) {
            self.accounts = accounts
            self.warning = warning
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
        /// Optional vault/source hint for host display formatting (e.g. "Classic", "Nested").
        /// Must not be baked into `accountName`, which is a stable identity for matching.
        public var sourceLabel: String?

        public init(identifier: AccountIdentifier,
                    userName: String,
                    accountName: String,
                    hasOTP: Bool,
                    sourceLabel: String? = nil) {
            self.identifier = identifier
            self.userName = userName
            self.accountName = accountName
            self.hasOTP = hasOTP
            self.sourceLabel = sourceLabel
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
        /// Optional vault hint from list (`Classic` / `Nested`). Opaque to the host.
        public var sourceLabel: String?
        /// Optional in-place field edits. When set, the adapter updates the record's
        /// title/login on the same record (preserving OTP and other fields) instead of
        /// only the password. nil means leave that field unchanged.
        public var newAccountName: String?
        public var newUserName: String?
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
        /// Optional vault hint from list (`Classic` / `Nested`). Opaque to the host.
        public var sourceLabel: String?
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

        public var flags: [String: Bool]?
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
        /// When true, the failure is an expired/invalid session (not a generic error). The host
        /// maps it to a re-authentication that clears the token and logs in again (silently when
        /// credentials are persisted). Adapters should set this on auth-rejection responses;
        /// nil/false is treated as an ordinary error. Backward-compatible: older adapters that
        /// never set it keep the previous behavior.
        public var needsAuthentication: Bool?

        public init(error: String, needsAuthentication: Bool? = nil) {
            self.error = error
            self.needsAuthentication = needsAuthentication
        }
    }
}
