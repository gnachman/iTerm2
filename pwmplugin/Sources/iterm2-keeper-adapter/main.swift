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
private typealias GetUsernameResponse = PasswordManagerProtocol.GetUsernameResponse
private typealias SetPasswordRequest = PasswordManagerProtocol.SetPasswordRequest
private typealias SetPasswordResponse = PasswordManagerProtocol.SetPasswordResponse
private typealias AddAccountRequest = PasswordManagerProtocol.AddAccountRequest
private typealias AddAccountResponse = PasswordManagerProtocol.AddAccountResponse
private typealias DeleteAccountRequest = PasswordManagerProtocol.DeleteAccountRequest
private typealias DeleteAccountResponse = PasswordManagerProtocol.DeleteAccountResponse
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

private struct KeeperSyncRequest: Codable {
    let header: PasswordManagerProtocol.RequestHeader
    let token: String?
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
            needsPathToExecutable: nil)
        writeOutput(response)
    } catch {
        writeError("Failed to decode handshake: \(error.localizedDescription)")
        exit(1)
    }
}

private func handleLogin() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }
    do {
        let request = try JSONDecoder().decode(LoginRequest.self, from: data)
        let baseURL = try extractServiceURL(from: request.header)
        guard let key = request.masterPassword, !key.isEmpty else {
            writeError("API key is required")
            exit(1)
        }
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
        guard let apiKey = decodeToken(request.token) else {
            writeError("Invalid or missing token")
            exit(1)
        }
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
        guard let apiKey = decodeToken(request.token) else {
            writeError("Invalid or missing token")
            exit(1)
        }
        let client = KeeperCommanderClient(baseURL: baseURL)
        let uid = request.accountIdentifier.accountID
        let pwd = try getPassword(apiKey: apiKey, recordUid: uid, client: client)
        writeOutput(pwd)
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleGetUsername() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }
    do {
        let request = try JSONDecoder().decode(GetPasswordRequest.self, from: data)
        let baseURL = try extractServiceURL(from: request.header)
        guard let apiKey = decodeToken(request.token) else {
            writeError("Invalid or missing token")
            exit(1)
        }
        let client = KeeperCommanderClient(baseURL: baseURL)
        let uid = request.accountIdentifier.accountID
        let login = try getLogin(apiKey: apiKey, recordUid: uid, client: client)
        writeOutput(GetUsernameResponse(userName: login))
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
        guard let apiKey = decodeToken(request.token) else {
            writeError("Invalid or missing token")
            exit(1)
        }
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
        guard let apiKey = decodeToken(request.token) else {
            writeError("Invalid or missing token")
            exit(1)
        }
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
        guard let apiKey = decodeToken(request.token) else {
            writeError("Invalid or missing token")
            exit(1)
        }
        let client = KeeperCommanderClient(baseURL: baseURL)
        try deleteRecord(apiKey: apiKey, recordUid: request.accountIdentifier.accountID, client: client)
        writeOutput(DeleteAccountResponse())
    } catch {
        writeError(error.localizedDescription)
        exit(1)
    }
}

private func handleKeeperSyncDown() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }
    do {
        let request = try JSONDecoder().decode(KeeperSyncRequest.self, from: data)
        let baseURL = try extractServiceURL(from: request.header)
        guard let apiKey = decodeToken(request.token), !apiKey.isEmpty else {
            writeError("Invalid or missing token")
            exit(1)
        }
        let client = KeeperCommanderClient(baseURL: baseURL)
        _ = try client.executeCommand(apiKey: apiKey, command: "sync-down")
        writeOutput(LoginResponse(token: nil))
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
    case "get-username": handleGetUsername()
    case "set-password": handleSetPassword()
    case "add-account": handleAddAccount()
    case "delete-account": handleDeleteAccount()
    case "keeper-sync-down": handleKeeperSyncDown()
    default:
        writeError("Unknown command: \(cmd)")
        exit(1)
    }
}

mainDispatch()
