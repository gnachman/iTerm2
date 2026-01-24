// Password Manager CLI for Bitwarden
//
// Protocol data structures are in the PasswordManagerProtocol module

import Foundation

// MARK: - Type Aliases

typealias HandshakeRequest = PasswordManagerProtocol.HandshakeRequest
typealias HandshakeResponse = PasswordManagerProtocol.HandshakeResponse
typealias UserAccount = PasswordManagerProtocol.UserAccount
typealias LoginRequest = PasswordManagerProtocol.LoginRequest
typealias LoginResponse = PasswordManagerProtocol.LoginResponse
typealias ListAccountsRequest = PasswordManagerProtocol.ListAccountsRequest
typealias ListAccountsResponse = PasswordManagerProtocol.ListAccountsResponse
typealias AccountIdentifier = PasswordManagerProtocol.AccountIdentifier
typealias Account = PasswordManagerProtocol.Account
typealias GetPasswordRequest = PasswordManagerProtocol.GetPasswordRequest
typealias Password = PasswordManagerProtocol.Password
typealias SetPasswordRequest = PasswordManagerProtocol.SetPasswordRequest
typealias SetPasswordResponse = PasswordManagerProtocol.SetPasswordResponse
typealias AddAccountRequest = PasswordManagerProtocol.AddAccountRequest
typealias AddAccountResponse = PasswordManagerProtocol.AddAccountResponse
typealias DeleteAccountRequest = PasswordManagerProtocol.DeleteAccountRequest
typealias DeleteAccountResponse = PasswordManagerProtocol.DeleteAccountResponse
typealias ErrorResponse = PasswordManagerProtocol.ErrorResponse

// MARK: - Bitwarden Data Structures

struct BitwardenStatus: Codable {
    var serverUrl: String?
    var lastSync: String?
    var userEmail: String?
    var userId: String?
    var status: String  // "unauthenticated", "locked", or "unlocked"
}

struct BitwardenItem: Codable {
    var id: String
    var organizationId: String?
    var folderId: String?
    var type: Int  // 1 = login, 2 = secure note, 3 = card, 4 = identity
    var name: String
    var notes: String?
    var favorite: Bool?
    var login: BitwardenLogin?
    var reprompt: Int?
    var deletedDate: String?
}

struct BitwardenLogin: Codable {
    var username: String?
    var password: String?
    var totp: String?
    var uris: [BitwardenUri]?
}

struct BitwardenUri: Codable {
    var uri: String?
    var match: Int?
}

struct BitwardenFolder: Codable {
    var id: String?
    var name: String
}

// MARK: - Helper Functions

func readStdin() -> Data? {
    var data = Data()
    let handle = FileHandle.standardInput

    let fd = handle.fileDescriptor

    var buffer = [UInt8](repeating: 0, count: 4096)

    while true {
        let bytesRead = read(fd, &buffer, buffer.count)

        if bytesRead < 0 {
            break
        } else if bytesRead == 0 {
            break
        } else {
            data.append(contentsOf: buffer[0..<bytesRead])
        }
    }

    return data.isEmpty ? nil : data
}

func writeOutput<T: Codable>(_ output: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    do {
        let data = try encoder.encode(output)
        if let json = String(data: data, encoding: .utf8) {
            print(json)
            fflush(stdout)
        }
    } catch {
        let errorResponse = ErrorResponse(error: "Failed to encode output: \(error.localizedDescription)")
        if let errorData = try? encoder.encode(errorResponse),
           let errorJson = String(data: errorData, encoding: .utf8) {
            print(errorJson)
            fflush(stdout)
        }
    }
}

func writeError(_ message: String) {
    writeOutput(ErrorResponse(error: message))
}

func runCommand(_ command: String, args: [String], input: String? = nil, env: [String: String]? = nil) -> (output: String, exitCode: Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + args

    // Set environment variables if provided
    if let env = env {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env {
            environment[key] = value
        }
        process.environment = environment
    }

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    if let input = input {
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        if let data = input.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
            try? inputPipe.fileHandleForWriting.close()
        }
    }

    do {
        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        let combined = output + errorOutput

        return (combined, process.terminationStatus)
    } catch {
        return ("Failed to run command: \(error.localizedDescription)", -1)
    }
}

func runBitwardenCommand(_ path: String?, args: [String], session: String? = nil, env: [String: String]? = nil, input: String? = nil) -> (output: String, exitCode: Int32) {
    let command = path ?? "bw"
    var fullArgs = args

    // Add session if provided
    if let session = session, !session.isEmpty {
        fullArgs = ["--session", session] + fullArgs
    }

    // Ensure HOME is set - bw needs this to find its config directory
    var fullEnv = env ?? [:]
    if fullEnv["HOME"] == nil {
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            fullEnv["HOME"] = home
        } else {
            // Fallback to getting home directory from password database
            fullEnv["HOME"] = NSHomeDirectory()
        }
    }

    return runCommand(command, args: fullArgs, input: input, env: fullEnv)
}

/// Securely unlock the vault using an environment variable for the password
/// This avoids exposing the password on the command line (visible via ps)
func unlockVault(_ path: String?, password: String) -> (sessionKey: String?, error: String?) {
    let envVarName = "BW_MASTER_PASSWORD"
    let env = [envVarName: password]
    let result = runBitwardenCommand(path, args: ["unlock", "--passwordenv", envVarName, "--raw"], env: env)

    if result.exitCode != 0 {
        let errorMsg = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if errorMsg.isEmpty {
            return (nil, "Invalid master password")
        } else {
            return (nil, "Failed to unlock vault: \(errorMsg)")
        }
    }

    let sessionKey = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    return (sessionKey, nil)
}

func decodeToken(_ token: String?) -> String? {
    guard let token = token, !token.isEmpty else {
        return nil
    }

    guard let data = Data(base64Encoded: token) else {
        return nil
    }

    return String(data: data, encoding: .utf8)
}

func encodeToken(_ session: String) -> String {
    return session.data(using: .utf8)?.base64EncodedString() ?? ""
}

func modeTag(from mode: PasswordManagerProtocol.RequestHeader.Mode) -> String? {
    switch mode {
    case .terminal:
        return "iTerm2"
    case .browser:
        return nil
    }
}

func getBitwardenStatus(_ path: String?) -> BitwardenStatus? {
    let result = runBitwardenCommand(path, args: ["status"])
    guard result.exitCode == 0 else {
        return nil
    }

    let decoder = JSONDecoder()
    guard let data = result.output.data(using: .utf8),
          let status = try? decoder.decode(BitwardenStatus.self, from: data) else {
        return nil
    }

    return status
}

func getFolderId(named folderName: String, path: String?, session: String) -> String? {
    let result = runBitwardenCommand(path, args: ["list", "folders"], session: session)
    guard result.exitCode == 0 else {
        return nil
    }

    let decoder = JSONDecoder()
    guard let data = result.output.data(using: .utf8),
          let folders = try? decoder.decode([BitwardenFolder].self, from: data) else {
        return nil
    }

    return folders.first { $0.name == folderName }?.id
}

func createFolder(named folderName: String, path: String?, session: String) -> String? {
    // Create folder JSON and encode it
    let folderJson = "{\"name\":\"\(folderName)\"}"
    guard let encodedFolder = folderJson.data(using: .utf8)?.base64EncodedString() else {
        return nil
    }

    // Pass encoded JSON via stdin to avoid exposing it on command line
    let result = runBitwardenCommand(path, args: ["create", "folder"], session: session, input: encodedFolder)
    guard result.exitCode == 0 else {
        return nil
    }

    // Parse the created folder to get its ID
    let decoder = JSONDecoder()
    guard let data = result.output.data(using: .utf8),
          let folder = try? decoder.decode(BitwardenFolder.self, from: data) else {
        return nil
    }

    return folder.id
}

func getOrCreateFolderId(named folderName: String, path: String?, session: String) -> String? {
    if let existingId = getFolderId(named: folderName, path: path, session: session) {
        return existingId
    }
    return createFolder(named: folderName, path: path, session: session)
}

// MARK: - Command Handlers

func handleHandshake() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }

    let decoder = JSONDecoder()
    do {
        let request = try decoder.decode(HandshakeRequest.self, from: data)

        // Check protocol version compatibility
        if request.maxProtocolVersion < 0 {
            writeError("Protocol version 0 is required but not supported by client")
            exit(1)
        }

        let response = HandshakeResponse(
            protocolVersion: 0,
            name: "Bitwarden",
            requiresMasterPassword: true,
            canSetPasswords: true,
            userAccounts: nil,
            needsPathToDatabase: false,
            databaseExtension: nil,
            needsPathToExecutable: "bw"
        )

        writeOutput(response)
    } catch {
        writeError("Failed to decode handshake request: \(error.localizedDescription)")
        exit(1)
    }
}

func handleLogin() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }

    let decoder = JSONDecoder()
    do {
        let request = try decoder.decode(LoginRequest.self, from: data)
        let path = request.header.pathToExecutable

        guard let password = request.masterPassword, !password.isEmpty else {
            writeError("Master password is required")
            exit(1)
        }

        // Check Bitwarden status first
        guard let status = getBitwardenStatus(path) else {
            writeError("Failed to get Bitwarden status. Is the bw CLI installed?")
            exit(1)
        }

        var sessionKey: String

        switch status.status {
        case "unauthenticated":
            writeError("Not logged in to Bitwarden. Please run 'bw login' first to authenticate, then try again.")
            exit(1)

        case "locked":
            // Unlock the vault with the master password
            let unlockResult = unlockVault(path, password: password)
            if let error = unlockResult.error {
                writeError(error)
                exit(1)
            }
            sessionKey = unlockResult.sessionKey!

        case "unlocked":
            // Already unlocked - we need to get the current session somehow
            // The bw CLI doesn't provide a way to get the current session key
            // We'll unlock again to get a fresh session key
            let unlockResult = unlockVault(path, password: password)
            if let error = unlockResult.error {
                writeError(error)
                exit(1)
            }
            sessionKey = unlockResult.sessionKey!

        default:
            writeError("Unknown Bitwarden status: \(status.status)")
            exit(1)
        }

        // Sync the vault to ensure we have the latest data
        let syncResult = runBitwardenCommand(path, args: ["sync"], session: sessionKey)
        if syncResult.exitCode != 0 {
            // Sync failure is not fatal, but log it
            // The vault might still be usable with cached data
        }

        // Encode the session key as the token
        let token = encodeToken(sessionKey)
        let response = LoginResponse(token: token)

        writeOutput(response)
    } catch {
        writeError("Failed to decode login request: \(error.localizedDescription)")
        exit(1)
    }
}

func handleListAccounts() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }

    let decoder = JSONDecoder()
    do {
        let request = try decoder.decode(ListAccountsRequest.self, from: data)
        let path = request.header.pathToExecutable

        // Decode the token to get the session key
        guard let session = decodeToken(request.token) else {
            writeError("Invalid or missing token. Please login first.")
            exit(1)
        }

        // Determine folder filtering based on mode
        let modeFolder = modeTag(from: request.header.mode)
        var listArgs = ["list", "items"]

        if let folderName = modeFolder {
            // Terminal mode: filter by iTerm2 folder
            if let folderId = getFolderId(named: folderName, path: path, session: session) {
                listArgs.append(contentsOf: ["--folderid", folderId])
            } else {
                // Folder doesn't exist yet, return empty list
                let response = ListAccountsResponse(accounts: [])
                writeOutput(response)
                return
            }
        } else {
            // Browser mode: get items in root (no folder)
            listArgs.append(contentsOf: ["--folderid", "null"])
        }

        let result = runBitwardenCommand(path, args: listArgs, session: session)

        if result.exitCode != 0 {
            writeError("Failed to list accounts: \(result.output)")
            exit(1)
        }

        // Parse the JSON output
        guard let itemsData = result.output.data(using: .utf8),
              let items = try? decoder.decode([BitwardenItem].self, from: itemsData) else {
            writeError("Failed to parse Bitwarden items")
            exit(1)
        }

        // Convert to Account format, filtering for login items only (type 1)
        // and excluding deleted items
        let accounts = items
            .filter { $0.type == 1 && $0.deletedDate == nil }
            .map { item in
                Account(
                    identifier: AccountIdentifier(accountID: item.id),
                    userName: item.login?.username ?? "",
                    accountName: item.name,
                    hasOTP: item.login?.totp != nil && !(item.login?.totp?.isEmpty ?? true)
                )
            }

        let response = ListAccountsResponse(accounts: accounts)
        writeOutput(response)
    } catch {
        writeError("Failed to decode list-accounts request: \(error.localizedDescription)")
        exit(1)
    }
}

func handleGetPassword() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }

    let decoder = JSONDecoder()
    do {
        let request = try decoder.decode(GetPasswordRequest.self, from: data)
        let path = request.header.pathToExecutable

        // Decode the token to get the session key
        guard let session = decodeToken(request.token) else {
            writeError("Invalid or missing token. Please login first.")
            exit(1)
        }

        let itemId = request.accountIdentifier.accountID

        // Get the password
        let passwordResult = runBitwardenCommand(path, args: ["get", "password", itemId], session: session)
        if passwordResult.exitCode != 0 {
            writeError("Failed to get password: \(passwordResult.output)")
            exit(1)
        }

        let passwordValue = passwordResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to get TOTP if available
        var otpValue: String? = nil
        let totpResult = runBitwardenCommand(path, args: ["get", "totp", itemId], session: session)
        if totpResult.exitCode == 0 {
            let totp = totpResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !totp.isEmpty {
                otpValue = totp
            }
        }

        let response = Password(password: passwordValue, otp: otpValue)
        writeOutput(response)
    } catch {
        writeError("Failed to decode get-password request: \(error.localizedDescription)")
        exit(1)
    }
}

func handleSetPassword() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }

    let decoder = JSONDecoder()
    do {
        let request = try decoder.decode(SetPasswordRequest.self, from: data)
        let path = request.header.pathToExecutable

        // Decode the token to get the session key
        guard let session = decodeToken(request.token) else {
            writeError("Invalid or missing token. Please login first.")
            exit(1)
        }

        guard let newPassword = request.newPassword else {
            writeError("New password is required")
            exit(1)
        }

        let itemId = request.accountIdentifier.accountID

        // First, get the current item
        let getResult = runBitwardenCommand(path, args: ["get", "item", itemId], session: session)
        if getResult.exitCode != 0 {
            writeError("Failed to get item: \(getResult.output)")
            exit(1)
        }

        // Parse and modify the item
        guard let itemData = getResult.output.data(using: .utf8),
              var item = try? JSONSerialization.jsonObject(with: itemData, options: .mutableContainers) as? [String: Any],
              var login = item["login"] as? [String: Any] else {
            writeError("Failed to parse item data")
            exit(1)
        }

        // Update the password
        login["password"] = newPassword
        item["login"] = login

        // Encode back to JSON
        guard let updatedItemData = try? JSONSerialization.data(withJSONObject: item, options: []) else {
            writeError("Failed to encode updated item")
            exit(1)
        }

        // Base64 encode for bw edit command
        let encodedItem = updatedItemData.base64EncodedString()

        // Update the item - pass encoded JSON via stdin to avoid exposing password on command line
        let editResult = runBitwardenCommand(path, args: ["edit", "item", itemId], session: session, input: encodedItem)
        if editResult.exitCode != 0 {
            writeError("Failed to set password: \(editResult.output)")
            exit(1)
        }

        let response = SetPasswordResponse()
        writeOutput(response)
    } catch {
        writeError("Failed to decode set-password request: \(error.localizedDescription)")
        exit(1)
    }
}

func handleAddAccount() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }

    let decoder = JSONDecoder()
    do {
        let request = try decoder.decode(AddAccountRequest.self, from: data)
        let path = request.header.pathToExecutable

        // Decode the token to get the session key
        guard let session = decodeToken(request.token) else {
            writeError("Invalid or missing token. Please login first.")
            exit(1)
        }

        // Determine folder based on mode
        let modeFolder = modeTag(from: request.header.mode)
        var folderId: String? = nil

        if let folderName = modeFolder {
            // Terminal mode: create in iTerm2 folder
            folderId = getOrCreateFolderId(named: folderName, path: path, session: session)
            if folderId == nil {
                writeError("Failed to create or find folder: \(folderName)")
                exit(1)
            }
        }
        // Browser mode: folderId stays nil (root)

        // Build the item JSON
        var itemDict: [String: Any] = [
            "type": 1,  // Login type
            "name": request.accountName,
            "login": [
                "username": request.userName,
                "password": request.password ?? ""
            ] as [String: Any]
        ]

        if let folderId = folderId {
            itemDict["folderId"] = folderId
        }

        // Encode the item
        guard let itemData = try? JSONSerialization.data(withJSONObject: itemDict, options: []) else {
            writeError("Failed to encode item data")
            exit(1)
        }

        let encodedItem = itemData.base64EncodedString()

        // Create the item - pass encoded JSON via stdin to avoid exposing password on command line
        let createResult = runBitwardenCommand(path, args: ["create", "item"], session: session, input: encodedItem)
        if createResult.exitCode != 0 {
            writeError("Failed to add account: \(createResult.output)")
            exit(1)
        }

        // Parse the created item to get its ID
        guard let createdItemData = createResult.output.data(using: .utf8),
              let createdItem = try? decoder.decode(BitwardenItem.self, from: createdItemData) else {
            writeError("Failed to parse created item response")
            exit(1)
        }

        let response = AddAccountResponse(accountIdentifier: AccountIdentifier(accountID: createdItem.id))
        writeOutput(response)
    } catch {
        writeError("Failed to decode add-account request: \(error.localizedDescription)")
        exit(1)
    }
}

func handleDeleteAccount() {
    guard let data = readStdin() else {
        writeError("No input provided")
        exit(1)
    }

    let decoder = JSONDecoder()
    do {
        let request = try decoder.decode(DeleteAccountRequest.self, from: data)
        let path = request.header.pathToExecutable

        // Decode the token to get the session key
        guard let session = decodeToken(request.token) else {
            writeError("Invalid or missing token. Please login first.")
            exit(1)
        }

        let itemId = request.accountIdentifier.accountID

        // Delete the item (soft delete by default, moves to trash)
        let deleteResult = runBitwardenCommand(path, args: ["delete", "item", itemId], session: session)
        if deleteResult.exitCode != 0 {
            writeError("Failed to delete account: \(deleteResult.output)")
            exit(1)
        }

        let response = DeleteAccountResponse()
        writeOutput(response)
    } catch {
        writeError("Failed to decode delete-account request: \(error.localizedDescription)")
        exit(1)
    }
}

// MARK: - Main

func main() {
    let args = CommandLine.arguments

    guard args.count >= 2 else {
        writeError("Usage: iterm2-bitwarden-adapter <command>")
        exit(1)
    }

    let command = args[1]

    switch command {
    case "handshake":
        handleHandshake()
    case "login":
        handleLogin()
    case "list-accounts":
        handleListAccounts()
    case "get-password":
        handleGetPassword()
    case "set-password":
        handleSetPassword()
    case "add-account":
        handleAddAccount()
    case "delete-account":
        handleDeleteAccount()
    default:
        writeError("Unknown command: \(command)")
        exit(1)
    }
}

main()
