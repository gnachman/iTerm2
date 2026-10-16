//
//  PasswordArchive.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/12/26.
//

import Foundation

// Saved passwords from the Keychain password manager, exported to a passphrase-encrypted
// SIGArchive (a .iterm2passwords file). The payload is JSON; the archive provides the encryption.
// Other password managers are never exported: they have their own sync and export.
enum PasswordArchiveScope: String, Codable, CaseIterable {
    case terminal
    case browser

    var isBrowser: Bool { self == .browser }

    init(browser: Bool) {
        self = browser ? .browser : .terminal
    }

    // A scope is exported or imported only while the Keychain is its password manager.
    var keychainIsActive: Bool {
        let provider = isBrowser ? PasswordManagerDataSourceProvider.forBrowser : PasswordManagerDataSourceProvider.forTerminal
        return provider.keychainEnabled
    }

    static var usingKeychain: [PasswordArchiveScope] {
        return allCases.filter { $0.keychainIsActive }
    }
}

struct PasswordArchiveEntry: Codable, Equatable {
    var scope: PasswordArchiveScope
    var accountName: String
    var userName: String
    var password: String
}

enum PasswordArchiveError: LocalizedError, Equatable {
    case notAPasswordArchive
    case wrongPassphraseOrDamaged
    case unsupportedVersion
    case malformed
    case readFailed(String)
    case writeFailed(String)
    case keychain(String)
    case readPassword(accountName: String, userName: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .notAPasswordArchive:
            return String(localized: "PasswordArchive.NotAnArchive", defaultValue: "This is not an iTerm2 passwords file.", comment: "Error shown when importing a file that is not a password export")
        case .wrongPassphraseOrDamaged:
            return String(localized: "PasswordArchive.WrongPassphrase", defaultValue: "The passphrase is incorrect, or the file is damaged.", comment: "Error shown when an encrypted password export can't be decrypted")
        case .unsupportedVersion:
            return String(localized: "PasswordArchive.UnsupportedVersion", defaultValue: "This passwords file was made by a newer version of iTerm2. Upgrade iTerm2 and try again.", comment: "Error shown when importing a password export from a newer version")
        case .malformed:
            return String(localized: "PasswordArchive.Malformed", defaultValue: "The passwords file is damaged.", comment: "Error shown when a decrypted password export can't be parsed")
        case .readFailed(let reason):
            return String(localized: "PasswordArchive.ReadFailed", defaultValue: "The passwords file could not be read: \(reason)", comment: "Error reading a password export; the placeholder is the system's reason")
        case .writeFailed(let reason):
            return String(localized: "PasswordArchive.WriteFailed", defaultValue: "The passwords file could not be saved: \(reason)", comment: "Error writing a password export; the placeholder is the system's reason")
        case .keychain(let reason):
            return String(localized: "PasswordArchive.KeychainFailed", defaultValue: "The keychain reported an error: \(reason)", comment: "Error accessing the keychain during password import or export; the placeholder is the system's reason")
        case let .readPassword(accountName, userName, reason):
            if userName.isEmpty {
                return String(localized: "PasswordArchive.ReadPasswordFailedNoUser", defaultValue: "The saved password for “\(accountName)” could not be read. \(reason)", comment: "Error exporting passwords. The first placeholder is the account name; the second is a sentence giving the reason.")
            }
            return String(localized: "PasswordArchive.ReadPasswordFailed", defaultValue: "The saved password for “\(accountName)” with user name “\(userName)” could not be read. \(reason)", comment: "Error exporting passwords. The placeholders are the account name, the user name, and a sentence giving the reason.")
        }
    }
}

enum PasswordArchive {
    static let fileExtension = "iterm2passwords"  // Localization unneeded
    private static let payloadVersion = 1

    private struct Payload: Codable {
        var version: Int
        var entries: [PasswordArchiveEntry]
    }

    // `iterations` is lowered only by tests, to keep them fast.
    static func write(_ entries: [PasswordArchiveEntry],
                      to url: URL,
                      passphrase: String,
                      iterations: UInt32 = SIGArchiveEncryptionDefaultIterations) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var json = try encoder.encode(Payload(version: payloadVersion, entries: entries))
        defer {
            json.resetBytes(in: 0..<json.count)
        }
        guard let encryption = SIGArchivePassphraseEncryption(passphrase: passphrase,
                                                                cipher: SIGArchiveAESGCMCipher(),
                                                                iterations: iterations) else {
            throw PasswordArchiveError.writeFailed("Could not generate a salt")  // Localization unneeded
        }
        let builder = SIGArchiveBuilder(payloadData: json, identity: nil, encryption: encryption)
        do {
            try builder.write(to: url)
        } catch {
            throw PasswordArchiveError.writeFailed(error.localizedDescription)
        }
    }

    private static func loadReader(_ url: URL) throws -> SIGArchiveReader {
        guard let reader = SIGArchiveReader(url: url) else {
            throw PasswordArchiveError.notAPasswordArchive
        }
        do {
            try reader.load()
        } catch {
            throw PasswordArchiveError.notAPasswordArchive
        }
        guard reader.isEncrypted() else {
            throw PasswordArchiveError.notAPasswordArchive
        }
        return reader
    }

    // Throws if the file obviously isn't a passwords file, so the user isn't asked for a
    // passphrase first. Passing this doesn't mean `read` will succeed.
    static func check(_ url: URL) throws {
        _ = try loadReader(url)
    }

    // `minimumIterations` is lowered only by tests.
    static func read(from url: URL,
                     passphrase: String,
                     minimumIterations: UInt32? = nil) throws -> [PasswordArchiveEntry] {
        let reader = try loadReader(url)
        if let minimumIterations {
            reader.minimumKDFIterations = minimumIterations
        }
        var json: Data
        do {
            json = try reader.decryptedPayload(withPassphrase: passphrase, cipher: SIGArchiveAESGCMCipher())
        } catch let error as NSError where error.domain == SIGErrorDomain {
            switch SIGErrorCode(rawValue: UInt(error.code)) {
            case .decryptionFailed:
                throw PasswordArchiveError.wrongPassphraseOrDamaged
            case .versionTooNew, .unsupportedAlgorithm:
                throw PasswordArchiveError.unsupportedVersion
            case .badEncryptionParameters:
                throw PasswordArchiveError.malformed
            case .ioRead, .algorithmCreationFailed:
                // Key derivation failing is a local problem, not one with the file.
                throw PasswordArchiveError.readFailed(error.localizedDescription)
            default:
                throw PasswordArchiveError.notAPasswordArchive
            }
        }
        defer {
            json.resetBytes(in: 0..<json.count)
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: json)
        } catch {
            // A newer version might change the payload's shape. Check its version before blaming
            // the file.
            if let version = (try? JSONSerialization.jsonObject(with: json) as? [String: Any])?["version"] as? Int,
               version > payloadVersion {
                throw PasswordArchiveError.unsupportedVersion
            }
            throw PasswordArchiveError.malformed
        }
        guard payload.version <= payloadVersion else {
            throw PasswordArchiveError.unsupportedVersion
        }
        return payload.entries
    }
}

// MARK: - Storage

// What import and export need from the keychain, so the import logic can be tested without one.
protocol PasswordArchiveStore {
    func accounts(scope: PasswordArchiveScope) throws -> [PasswordArchiveStoreAccount]
    func add(_ entry: PasswordArchiveEntry) throws
}

protocol PasswordArchiveStoreAccount {
    var accountName: String { get }
    var userName: String { get }
    func password() throws -> String
    func setPassword(_ password: String) throws
}

// Reads and writes the Keychain password manager's items directly, so that one authentication
// covers both scopes. Callers must authenticate the user first.
struct KeychainPasswordArchiveStore: PasswordArchiveStore {
    private struct Account: PasswordArchiveStoreAccount {
        var account: PasswordManagerAccount

        var accountName: String { account.accountName }
        var userName: String { account.userName }

        func password() throws -> String {
            var result: Result<String, Error>?
            account.fetchPassword(context: RecipeExecutionContext(window: nil)) { password, _, error in
                if let password {
                    result = .success(password)
                } else {
                    result = .failure(error ?? PasswordArchiveError.keychain("No password"))  // Localization unneeded
                }
            }
            return try Self.unwrap(result)
        }

        func setPassword(_ password: String) throws {
            var result: Result<Void, Error>?
            account.set(context: RecipeExecutionContext(window: nil), password: password) { error in
                result = error.map { .failure($0) } ?? .success(())
            }
            try Self.unwrap(result)
        }

        // Keychain accounts complete synchronously.
        static func unwrap<T>(_ result: Result<T, Error>?) throws -> T {
            guard let result else {
                it_fatalError("Keychain account completed asynchronously")
            }
            do {
                return try result.get()
            } catch {
                throw PasswordArchiveError.keychain(error.localizedDescription)
            }
        }
    }

    func accounts(scope: PasswordArchiveScope) throws -> [PasswordArchiveStoreAccount] {
        var accounts: [PasswordManagerAccount]?
        KeychainPasswordDataSource(browser: scope.isBrowser).fetchAccounts(context: RecipeExecutionContext(window: nil)) {
            accounts = $0
        }
        guard let accounts else {
            it_fatalError("Keychain data source completed asynchronously")
        }
        return accounts.map { Account(account: $0) }
    }

    func add(_ entry: PasswordArchiveEntry) throws {
        var result: Result<Void, Error>?
        KeychainPasswordDataSource(browser: entry.scope.isBrowser).add(userName: entry.userName,
                                                                       accountName: entry.accountName,
                                                                       password: entry.password,
                                                                       flags: [:],
                                                                       context: RecipeExecutionContext(window: nil)) { _, error in
            result = error.map { .failure($0) } ?? .success(())
        }
        try Account.unwrap(result)
    }
}

// MARK: - Export and import logic

enum PasswordArchiveExporter {
    static func entries(scopes: [PasswordArchiveScope],
                        store: PasswordArchiveStore) throws -> [PasswordArchiveEntry] {
        return try scopes.flatMap { scope in
            try store.accounts(scope: scope).map { account in
                let password: String
                do {
                    password = try account.password()
                } catch {
                    // Name the entry so the user can find and fix it.
                    throw PasswordArchiveError.readPassword(accountName: account.accountName,
                                                            userName: account.userName,
                                                            reason: error.localizedDescription)
                }
                return PasswordArchiveEntry(scope: scope,
                                            accountName: account.accountName,
                                            userName: account.userName,
                                            password: password)
            }
        }
    }
}

// Applies imported entries to a store, asking what to do when an entry matches an existing one.
struct PasswordArchiveImporter {
    enum ConflictDecision {
        case replace
        case skip
        case alwaysReplace
        case neverReplace
        case cancel
    }

    struct Summary: Equatable {
        var added = 0
        var replaced = 0
        var skipped = 0
        // Entries whose saved password already matched. These aren't conflicts.
        var unchanged = 0
        // Entries for a scope whose password manager isn't the Keychain. Writing them to a
        // keychain store that nothing shows would be confusing.
        var notImported = 0
        var cancelled = false
        // Why the import stopped early, if it failed after possibly changing some entries.
        var failure: String?
    }

    private struct Key: Hashable {
        var scope: PasswordArchiveScope
        var accountName: String
        var userName: String
    }

    var store: PasswordArchiveStore
    var scopesUsingKeychain: Set<PasswordArchiveScope>

    // `decide` is called once per conflict until it returns alwaysReplace or neverReplace, which
    // then apply to every later conflict in this import. Throws only if it fails before changing
    // anything. A later failure stops the import and is reported in the summary, together with the
    // counts so far.
    func run(_ allEntries: [PasswordArchiveEntry],
             decide: (PasswordArchiveEntry) -> ConflictDecision) throws -> Summary {
        let entries = allEntries.filter { scopesUsingKeychain.contains($0.scope) }
        var existing = [Key: PasswordArchiveStoreAccount]()
        for scope in Set(entries.map(\.scope)) {
            for account in try store.accounts(scope: scope) {
                existing[Key(scope: scope, accountName: account.accountName, userName: account.userName)] = account
            }
        }

        var summary = Summary(notImported: allEntries.count - entries.count)
        var standingDecision: ConflictDecision?
        var addedKeys = Set<Key>()
        do {
            for entry in entries {
                let key = Key(scope: entry.scope, accountName: entry.accountName, userName: entry.userName)
                if existing[key] == nil && addedKeys.contains(key) {
                    // The file holds the same account twice. Treat the second like any other conflict.
                    existing[key] = try store.accounts(scope: entry.scope).first {
                        $0.accountName == entry.accountName && $0.userName == entry.userName
                    }
                }
                guard let account = existing[key] else {
                    try store.add(entry)
                    summary.added += 1
                    addedKeys.insert(key)
                    continue
                }
                if try account.password() == entry.password {
                    summary.unchanged += 1
                    continue
                }
                let decision = standingDecision ?? decide(entry)
                switch decision {
                case .replace, .alwaysReplace:
                    try account.setPassword(entry.password)
                    summary.replaced += 1
                case .skip, .neverReplace:
                    summary.skipped += 1
                case .cancel:
                    summary.cancelled = true
                    return summary
                }
                if decision == .alwaysReplace || decision == .neverReplace {
                    standingDecision = decision
                }
            }
        } catch {
            summary.failure = error.localizedDescription
        }
        return summary
    }
}
