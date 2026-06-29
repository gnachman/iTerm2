// iterm2-test-adapter — Dev-only adapter that exercises every protocol extension.
//
// Persists accounts to a JSON file in /tmp so add/delete/set-password survive across invocations.
//
// Exercises:
//   - pathToDatabaseKind: .url
//   - pathToDatabasePrompt / pathToDatabasePlaceholder
//   - masterPasswordLabel
//   - persistsCredentials
//   - settingsFields (secret + non-secret, with notes, keychain persistence)
//   - customCommands (sync-down, ping)
//   - custom command request/response
//   - header.settings passthrough

import Foundation
import PasswordManagerProtocol

// MARK: - Type aliases

private typealias Proto = PasswordManagerProtocol

// MARK: - Persistent store

private struct StoredAccount: Codable {
    var uid: String
    var title: String
    var username: String
    var password: String
}

private struct Store: Codable {
    var accounts: [StoredAccount]
    var nextUID: Int
}

private let storePath = "/tmp/iterm2-test-adapter-store.json"

private let defaultAccounts: [StoredAccount] = [
    StoredAccount(uid: "test-001", title: "Example Site", username: "alice@example.com", password: "hunter2"),
    StoredAccount(uid: "test-002", title: "Work VPN", username: "bob", password: "correcthorsebatterystaple"),
    StoredAccount(uid: "test-003", title: "SSH Key Passphrase", username: "root", password: "p@ssw0rd!"),
]

private func loadStore() -> Store {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: storePath)),
          let store = try? JSONDecoder().decode(Store.self, from: data) else {
        return Store(accounts: defaultAccounts, nextUID: 4)
    }
    return store
}

private func saveStore(_ store: Store) {
    guard let data = try? JSONEncoder().encode(store) else { return }
    try? data.write(to: URL(fileURLWithPath: storePath))
}

// MARK: - I/O helpers

private func readStdin() -> Data? {
    var data = Data()
    let fd = FileHandle.standardInput.fileDescriptor
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(fd, &buffer, buffer.count)
        if n <= 0 { break }
        data.append(contentsOf: buffer[0..<n])
    }
    return data.isEmpty ? nil : data
}

private func writeOutput<T: Encodable>(_ output: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let bytes = try? encoder.encode(output),
          let json = String(data: bytes, encoding: .utf8) else { return }
    print(json)
    fflush(stdout)
}

private func writeError(_ message: String) {
    writeOutput(Proto.ErrorResponse(error: message))
}

private func requireStdin() -> Data {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }
    return data
}

// MARK: - Auth

private let validAPIKey = "test-api-key-12345"

private func decodeToken(_ token: String?) -> String? {
    guard let token = token, !token.isEmpty,
          let data = Data(base64Encoded: token),
          let key = String(data: data, encoding: .utf8) else { return nil }
    return key
}

private func requireAuth(_ token: String?) -> String {
    guard let key = decodeToken(token), key == validAPIKey else {
        writeError("Invalid or expired API key. Use: \(validAPIKey)")
        exit(1)
    }
    return key
}

// MARK: - Settings

private func settingsDescription(_ header: Proto.RequestHeader) -> String {
    guard let settings = header.settings, !settings.isEmpty else {
        return "(no settings)"
    }
    return settings.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
}

// MARK: - Handlers

private func handleHandshake() {
    let data = requireStdin()
    do {
        let request = try JSONDecoder().decode(Proto.HandshakeRequest.self, from: data)
        if request.maxProtocolVersion < 0 {
            writeError("Protocol version 0 is required")
            exit(1)
        }
        let response = Proto.HandshakeResponse(
            protocolVersion: 0,
            name: "Test Adapter",
            requiresMasterPassword: true,
            canSetPasswords: true,
            userAccounts: nil,
            needsPathToDatabase: true,
            databaseExtension: nil,
            needsPathToExecutable: nil,
            pathToDatabaseKind: .url,
            pathToDatabasePrompt: "Test Adapter: Enter a fake service URL",
            pathToDatabasePlaceholder: "http://localhost:9999",
            masterPasswordLabel: "API key",
            persistsCredentials: true,
            customCommands: [
                Proto.CustomCommand(name: "sync-down", label: "Sync Down", icon: "arrow.clockwise"),
                Proto.CustomCommand(name: "ping", label: "Ping Server", icon: "bolt.horizontal"),
            ],
            settingsFields: [
                Proto.SettingsField(key: "serverURL", label: "Server URL:", placeholder: "http://localhost:9999", isSecret: false, note: "The URL of the test server (not actually used)", persistInKeychain: false),
                Proto.SettingsField(key: "apiToken", label: "API Token:", placeholder: "Enter token", isSecret: true, note: nil, persistInKeychain: true),
                Proto.SettingsField(key: "orgName", label: "Org Name:", placeholder: "My Organization", isSecret: false, note: "Optional organization label", persistInKeychain: false),
            ])
        writeOutput(response)
    } catch {
        writeError("Failed to decode handshake: \(error.localizedDescription)")
        exit(1)
    }
}

private func handleLogin() {
    let data = requireStdin()
    do {
        let request = try JSONDecoder().decode(Proto.LoginRequest.self, from: data)
        guard let key = request.masterPassword, !key.isEmpty else {
            writeError("API key is required")
            exit(1)
        }
        guard key == validAPIKey else {
            writeError("Invalid API key. Expected: \(validAPIKey)")
            exit(1)
        }
        let token = Data(key.utf8).base64EncodedString()
        fputs("[test-adapter] login OK, settings: \(settingsDescription(request.header))\n", stderr)
        writeOutput(Proto.LoginResponse(token: token))
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleListAccounts() {
    let data = requireStdin()
    do {
        let request = try JSONDecoder().decode(Proto.ListAccountsRequest.self, from: data)
        _ = requireAuth(request.token)
        let store = loadStore()
        let protoAccounts = store.accounts.map { acct in
            Proto.Account(
                identifier: Proto.AccountIdentifier(accountID: acct.uid),
                userName: acct.username,
                accountName: acct.title,
                hasOTP: false)
        }
        fputs("[test-adapter] list-accounts: \(protoAccounts.count) accounts, settings: \(settingsDescription(request.header))\n", stderr)
        writeOutput(Proto.ListAccountsResponse(accounts: protoAccounts))
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleGetPassword() {
    let data = requireStdin()
    do {
        let request = try JSONDecoder().decode(Proto.GetPasswordRequest.self, from: data)
        _ = requireAuth(request.token)
        let store = loadStore()
        let uid = request.accountIdentifier.accountID
        guard let acct = store.accounts.first(where: { $0.uid == uid }) else {
            writeError("Account not found: \(uid)")
            exit(1)
        }
        writeOutput(Proto.Password(password: acct.password, otp: nil))
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleSetPassword() {
    let data = requireStdin()
    do {
        let request = try JSONDecoder().decode(Proto.SetPasswordRequest.self, from: data)
        _ = requireAuth(request.token)
        var store = loadStore()
        let uid = request.accountIdentifier.accountID
        guard let idx = store.accounts.firstIndex(where: { $0.uid == uid }) else {
            writeError("Account not found: \(uid)")
            exit(1)
        }
        guard let newPassword = request.newPassword, !newPassword.isEmpty else {
            writeError("Password is required")
            exit(1)
        }
        store.accounts[idx].password = newPassword
        saveStore(store)
        fputs("[test-adapter] set-password for \(uid)\n", stderr)
        writeOutput(Proto.SetPasswordResponse())
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleAddAccount() {
    let data = requireStdin()
    do {
        let request = try JSONDecoder().decode(Proto.AddAccountRequest.self, from: data)
        _ = requireAuth(request.token)
        var store = loadStore()
        let uid = "test-\(String(format: "%03d", store.nextUID))"
        store.nextUID += 1
        let acct = StoredAccount(uid: uid,
                                 title: request.accountName,
                                 username: request.userName,
                                 password: request.password ?? "")
        store.accounts.append(acct)
        saveStore(store)
        fputs("[test-adapter] add-account: \(acct.title) (\(uid))\n", stderr)
        writeOutput(Proto.AddAccountResponse(accountIdentifier: Proto.AccountIdentifier(accountID: uid)))
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleDeleteAccount() {
    let data = requireStdin()
    do {
        let request = try JSONDecoder().decode(Proto.DeleteAccountRequest.self, from: data)
        _ = requireAuth(request.token)
        var store = loadStore()
        let uid = request.accountIdentifier.accountID
        guard let idx = store.accounts.firstIndex(where: { $0.uid == uid }) else {
            writeError("Account not found: \(uid)")
            exit(1)
        }
        fputs("[test-adapter] delete-account: \(store.accounts[idx].title) (\(uid))\n", stderr)
        store.accounts.remove(at: idx)
        saveStore(store)
        writeOutput(Proto.DeleteAccountResponse())
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleCustomCommand(_ name: String) {
    let data = requireStdin()
    do {
        let request = try JSONDecoder().decode(Proto.CustomCommandRequest.self, from: data)
        _ = requireAuth(request.token)
        let store = loadStore()
        fputs("[test-adapter] custom command \(name), settings: \(settingsDescription(request.header))\n", stderr)
        switch name {
        case "sync-down":
            writeOutput(Proto.CustomCommandResponse(message: "Sync complete. \(store.accounts.count) records up to date."))
        case "ping":
            let url = request.header.settings?["serverURL"] ?? request.header.pathToDatabase ?? "(none)"
            writeOutput(Proto.CustomCommandResponse(message: "Pong! Server URL: \(url)"))
        default:
            writeError("Unknown custom command: \(name)")
            exit(1)
        }
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

// MARK: - Dispatch

private func main() {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        writeError("Usage: iterm2-test-adapter <command>")
        exit(1)
    }
    let cmd = args[1]
    switch cmd {
    case "handshake":      handleHandshake()
    case "login":          handleLogin()
    case "list-accounts":  handleListAccounts()
    case "get-password":   handleGetPassword()
    case "set-password":   handleSetPassword()
    case "add-account":    handleAddAccount()
    case "delete-account": handleDeleteAccount()
    default:               handleCustomCommand(cmd)
    }
}

main()
