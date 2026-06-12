// iterm2-keeper-adapter — Keeper Commander Service Mode (REST v2) for iTerm2 pwmplugin protocol.

import Foundation
import PasswordManagerProtocol

private typealias HandshakeRequest = PasswordManagerProtocol.HandshakeRequest
private typealias HandshakeResponse = PasswordManagerProtocol.HandshakeResponse
private typealias LoginRequest = PasswordManagerProtocol.LoginRequest
private typealias LoginResponse = PasswordManagerProtocol.LoginResponse
private typealias ListAccountsRequest = PasswordManagerProtocol.ListAccountsRequest
private typealias ListAccountsResponse = PasswordManagerProtocol.ListAccountsResponse
private typealias GetPasswordRequest = PasswordManagerProtocol.GetPasswordRequest
private typealias SetPasswordRequest = PasswordManagerProtocol.SetPasswordRequest
private typealias SetPasswordResponse = PasswordManagerProtocol.SetPasswordResponse
private typealias AddAccountRequest = PasswordManagerProtocol.AddAccountRequest
private typealias AddAccountResponse = PasswordManagerProtocol.AddAccountResponse
private typealias DeleteAccountRequest = PasswordManagerProtocol.DeleteAccountRequest
private typealias DeleteAccountResponse = PasswordManagerProtocol.DeleteAccountResponse
private typealias CustomCommandRequest = PasswordManagerProtocol.CustomCommandRequest
private typealias CustomCommandResponse = PasswordManagerProtocol.CustomCommandResponse
private typealias ErrorResponse = PasswordManagerProtocol.ErrorResponse

private func readStdin() -> Data? {
    var data = Data()
    let handle = FileHandle.standardInput
    let fd = handle.fileDescriptor
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
    guard let bytes = try? encoder.encode(output), let json = String(data: bytes, encoding: .utf8) else { return }
    print(json)
    fflush(stdout)
}

private func writeError(_ message: String) {
    writeOutput(ErrorResponse(error: message))
}

private func handleHandshake() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }
    do {
        let request = try JSONDecoder().decode(HandshakeRequest.self, from: data)
        if request.maxProtocolVersion < 0 {
            writeError("Protocol version 0 is required")
            exit(1)
        }
        let response = HandshakeResponse(
            protocolVersion: 0,
            name: "Keeper Security",
            requiresMasterPassword: true,
            canSetPasswords: true,
            userAccounts: nil,
            needsPathToDatabase: true,
            databaseExtension: nil,
            needsPathToExecutable: nil,
            pathToDatabaseKind: .url,
            pathToDatabasePrompt: "Keeper Commander Service Mode API URL",
            pathToDatabasePlaceholder: "http://127.0.0.1:8900/api/v2",
            masterPasswordLabel: "API key",
            persistsCredentials: true,
            customCommands: [
                PasswordManagerProtocol.CustomCommand(name: "sync-down",
                                                      label: "Sync Down",
                                                      icon: "arrow.clockwise")
            ],
            settingsFields: [
                PasswordManagerProtocol.SettingsField(
                    key: "serviceURL",
                    label: "API URL:",
                    placeholder: "http://127.0.0.1:8900/api/v2",
                    isSecret: false,
                    note: "Note: Append /api/v2 in your API URL",
                    persistInKeychain: false),
                PasswordManagerProtocol.SettingsField(
                    key: "apiKey",
                    label: "API key:",
                    placeholder: "Enter Keeper Commander API key",
                    isSecret: true,
                    note: nil,
                    persistInKeychain: true),
            ])
        writeOutput(response)
    } catch {
        writeError("Failed to decode handshake: \(error.localizedDescription)")
        exit(1)
    }
}

private func apiKey(fromHeader header: PasswordManagerProtocol.RequestHeader,
                    token: String?,
                    masterPassword: String?) throws -> String {
    if let key = masterPassword?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
        return key
    }
    if let key = decodeToken(token)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
        return key
    }
    if let key = header.settings?["apiKey"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
        return key
    }
    throw KeeperClientError.message("Invalid or missing API key")
}

private func handleLogin() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }
    do {
        let request = try JSONDecoder().decode(LoginRequest.self, from: data)
        let baseURL = try extractServiceURL(from: request.header)
        let key = try apiKey(fromHeader: request.header, token: nil, masterPassword: request.masterPassword)
        let client = KeeperCommanderClient(baseURL: baseURL)
        _ = try listAccountsRecords(apiKey: key, client: client)
        let token = Data(key.utf8).base64EncodedString()
        writeOutput(LoginResponse(token: token))
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleListAccounts() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }
    do {
        let request = try JSONDecoder().decode(ListAccountsRequest.self, from: data)
        let baseURL = try extractServiceURL(from: request.header)
        let apiKey = try apiKey(fromHeader: request.header, token: request.token, masterPassword: nil)
        let client = KeeperCommanderClient(baseURL: baseURL)
        let accounts = try listAccountsRecords(apiKey: apiKey, client: client)
        writeOutput(ListAccountsResponse(accounts: accounts))
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleGetPassword() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }
    do {
        let request = try JSONDecoder().decode(GetPasswordRequest.self, from: data)
        let baseURL = try extractServiceURL(from: request.header)
        let apiKey = try apiKey(fromHeader: request.header, token: request.token, masterPassword: nil)
        let client = KeeperCommanderClient(baseURL: baseURL)
        let uid = request.accountIdentifier.accountID
        let pwd = try getPassword(apiKey: apiKey, recordUid: uid, client: client)
        writeOutput(pwd)
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleSetPassword() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }
    do {
        let request = try JSONDecoder().decode(SetPasswordRequest.self, from: data)
        let baseURL = try extractServiceURL(from: request.header)
        let apiKey = try apiKey(fromHeader: request.header, token: request.token, masterPassword: nil)
        let client = KeeperCommanderClient(baseURL: baseURL)
        let uid = request.accountIdentifier.accountID
        try setPassword(apiKey: apiKey, recordUid: uid, newPassword: request.newPassword, client: client)
        writeOutput(SetPasswordResponse())
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleAddAccount() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }
    do {
        let request = try JSONDecoder().decode(AddAccountRequest.self, from: data)
        let baseURL = try extractServiceURL(from: request.header)
        let apiKey = try apiKey(fromHeader: request.header, token: request.token, masterPassword: nil)
        let client = KeeperCommanderClient(baseURL: baseURL)
        let uid = try addRecord(
            apiKey: apiKey,
            userName: request.userName,
            accountName: request.accountName,
            password: request.password,
            client: client)
        writeOutput(AddAccountResponse(accountIdentifier: PasswordManagerProtocol.AccountIdentifier(accountID: uid)))
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleDeleteAccount() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }
    do {
        let request = try JSONDecoder().decode(DeleteAccountRequest.self, from: data)
        let baseURL = try extractServiceURL(from: request.header)
        let apiKey = try apiKey(fromHeader: request.header, token: request.token, masterPassword: nil)
        let client = KeeperCommanderClient(baseURL: baseURL)
        try deleteRecord(apiKey: apiKey, recordUid: request.accountIdentifier.accountID, client: client)
        writeOutput(DeleteAccountResponse())
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleCustomCommand(_ commandName: String) {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }
    do {
        let request = try JSONDecoder().decode(CustomCommandRequest.self, from: data)
        let baseURL = try extractServiceURL(from: request.header)
        let apiKey = try apiKey(fromHeader: request.header, token: request.token, masterPassword: nil)
        switch commandName {
        case "sync-down":
            let client = KeeperCommanderClient(baseURL: baseURL)
            _ = try client.executeCommand(apiKey: apiKey, command: "sync-down")
            writeOutput(CustomCommandResponse(message: "Sync completed"))
        default:
            writeError("Unknown command: \(commandName)")
            exit(1)
        }
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func mainDispatch() {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        writeError("Usage: iterm2-keeper-adapter <command>")
        exit(1)
    }
    let cmd = args[1]
    switch cmd {
    case "handshake": handleHandshake()
    case "login": handleLogin()
    case "list-accounts": handleListAccounts()
    case "get-password": handleGetPassword()
    case "set-password": handleSetPassword()
    case "add-account": handleAddAccount()
    case "delete-account": handleDeleteAccount()
    default:
        handleCustomCommand(cmd)
    }
}

mainDispatch()
