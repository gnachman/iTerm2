// Password Manager CLI for Bitwarden
//
// Protocol data structures are in the PasswordManagerProtocol module

import Foundation
import PasswordManagerProtocol

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

struct CommandResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32

    /// The most useful text to show when the command failed: bw writes errors to stderr, but
    /// fall back to stdout in case a version prints them there.
    var errorMessage: String {
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty {
            return err
        }
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "exit status \(exitCode)" : out
    }
}

func runCommand(_ command: String, args: [String], input: String? = nil, env: [String: String]? = nil) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + args

    var environment = ProcessInfo.processInfo.environment
    for (key, value) in env ?? [:] {
        environment[key] = value
    }
    process.environment = environment

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    // Never let bw inherit our stdin. It is the pipe iTerm2 wrote the request to, already at
    // EOF, and if bw prompts for anything it would read it (or crash on it) instead.
    let inputPipe: Pipe?
    if input != nil {
        let pipe = Pipe()
        process.standardInput = pipe
        inputPipe = pipe
    } else {
        process.standardInput = FileHandle.nullDevice
        inputPipe = nil
    }

    do {
        try process.run()
    } catch {
        return CommandResult(stdout: "", stderr: "Failed to run \(command): \(error.localizedDescription)", exitCode: -1)
    }

    // Write input and drain both outputs concurrently. Doing them one after another deadlocks
    // once any of them exceeds the pipe buffer, which a large vault listing easily does.
    let group = DispatchGroup()
    var outputData = Data()
    var errorData = Data()
    DispatchQueue.global().async(group: group) {
        outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    }
    DispatchQueue.global().async(group: group) {
        errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    }
    if let inputPipe, let input {
        DispatchQueue.global().async(group: group) {
            // bw can exit without reading its input (a locked vault is checked first), so the
            // write may fail with EPIPE. SIGPIPE is ignored in main(), and this form of write
            // throws instead of raising, so that is harmless; bw’s exit status reports why.
            try? inputPipe.fileHandleForWriting.write(contentsOf: Data(input.utf8))
            try? inputPipe.fileHandleForWriting.close()
        }
    }
    group.wait()
    process.waitUntilExit()

    return CommandResult(stdout: String(data: outputData, encoding: .utf8) ?? "",
                         stderr: String(data: errorData, encoding: .utf8) ?? "",
                         exitCode: process.terminationStatus)
}

func runBitwardenCommand(_ path: String?, args: [String], session: String? = nil, env: [String: String]? = nil, input: String? = nil) -> CommandResult {
    let command = path ?? "bw"
    // --nointeraction makes bw fail with an error instead of prompting, since there is nobody
    // to answer a prompt here.
    let fullArgs = ["--nointeraction"] + args

    var fullEnv = env ?? [:]
    // Pass the session in the environment rather than with --session, which would expose it
    // to anyone who can list processes.
    if let session = session, !session.isEmpty {
        fullEnv["BW_SESSION"] = session
    }
    // Ensure HOME is set - bw needs this to find its config directory
    if fullEnv["HOME"] == nil {
        fullEnv["HOME"] = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    }

    return runCommand(command, args: fullArgs, input: input, env: fullEnv)
}

/// Whether a failed bw command means the session is no longer usable, so iTerm2 should unlock
/// again rather than show the error.
func isSessionRejection(_ result: CommandResult) -> Bool {
    let message = result.errorMessage.lowercased()
    return message.contains("vault is locked") || message.contains("master password is required")
}

/// Writes an error for a failed bw command, flagging a rejected session so iTerm2 unlocks again.
func writeBitwardenError(_ prefix: String, _ result: CommandResult) {
    writeOutput(ErrorResponse(error: "\(prefix): \(result.errorMessage)",
                              needsAuthentication: isSessionRejection(result) ? true : nil))
}

let wrongMasterPasswordMessage = "Incorrect master password."

/// Whether a failed unlock means the master password was wrong. Recent versions of bw report it
/// as a failure to decrypt the key with the password; older ones say “Invalid master password.”
func isWrongMasterPassword(_ result: CommandResult) -> Bool {
    let message = result.errorMessage.lowercased()
    return message.contains("decryption operation failed") || message.contains("invalid master password")
}

/// Securely unlock the vault using an environment variable for the password
/// This avoids exposing the password on the command line (visible via ps)
func unlockVault(_ path: String?, password: String) -> (sessionKey: String?, error: String?) {
    let envVarName = "BW_MASTER_PASSWORD"
    let env = [envVarName: password]
    let result = runBitwardenCommand(path, args: ["unlock", "--passwordenv", envVarName, "--raw"], env: env)

    if result.exitCode != 0 {
        if isWrongMasterPassword(result) {
            return (nil, wrongMasterPasswordMessage)
        }
        return (nil, "Failed to unlock vault: \(result.errorMessage)")
    }

    let sessionKey = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if sessionKey.isEmpty {
        return (nil, "Failed to unlock vault: bw did not return a session key")
    }
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

func getBitwardenStatus(_ path: String?) -> Result<BitwardenStatus, BitwardenError> {
    let result = runBitwardenCommand(path, args: ["status"])
    guard result.exitCode == 0 else {
        return .failure(BitwardenError(result.errorMessage))
    }
    guard let status = try? JSONDecoder().decode(BitwardenStatus.self, from: Data(result.stdout.utf8)) else {
        return .failure(BitwardenError("Could not understand the output of “bw status”"))
    }
    return .success(status)
}

struct BitwardenError: Error {
    var message: String
    var result: CommandResult?

    init(_ message: String, result: CommandResult? = nil) {
        self.message = message
        self.result = result
    }
}

enum FolderLookup {
    case found(String)
    case missing
}

func getFolderId(named folderName: String, path: String?, session: String) -> Result<FolderLookup, BitwardenError> {
    let result = runBitwardenCommand(path, args: ["list", "folders"], session: session)
    guard result.exitCode == 0 else {
        return .failure(BitwardenError("Failed to list folders", result: result))
    }
    guard let folders = try? JSONDecoder().decode([BitwardenFolder].self, from: Data(result.stdout.utf8)) else {
        return .failure(BitwardenError("Could not understand the folder list from bw"))
    }
    if let id = folders.first(where: { $0.name == folderName })?.id, !id.isEmpty {
        return .success(.found(id))
    }
    return .success(.missing)
}

func createFolder(named folderName: String, path: String?, session: String) -> Result<String, BitwardenError> {
    guard let folderData = try? JSONSerialization.data(withJSONObject: ["name": folderName]) else {
        return .failure(BitwardenError("Failed to encode folder"))
    }
    // Pass encoded JSON via stdin to avoid exposing it on command line
    let result = runBitwardenCommand(path, args: ["create", "folder"], session: session,
                                     input: folderData.base64EncodedString())
    guard result.exitCode == 0 else {
        return .failure(BitwardenError("Failed to create folder “\(folderName)”", result: result))
    }
    guard let folder = try? JSONDecoder().decode(BitwardenFolder.self, from: Data(result.stdout.utf8)),
          let id = folder.id else {
        return .failure(BitwardenError("Could not understand the new folder from bw"))
    }
    return .success(id)
}

func getOrCreateFolderId(named folderName: String, path: String?, session: String) -> Result<String, BitwardenError> {
    switch getFolderId(named: folderName, path: path, session: session) {
    case .failure(let error):
        return .failure(error)
    case .success(.found(let id)):
        return .success(id)
    case .success(.missing):
        return createFolder(named: folderName, path: path, session: session)
    }
}

/// Writes an error response for `error`, flagging a rejected session so iTerm2 unlocks again.
func writeBitwardenError(_ error: BitwardenError) {
    if let result = error.result {
        writeBitwardenError(error.message, result)
    } else {
        writeError(error.message)
    }
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
        let status: BitwardenStatus
        switch getBitwardenStatus(path) {
        case .success(let value):
            status = value
        case .failure(let error):
            writeError("Failed to get Bitwarden status: \(error.message)")
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
                // A wrong password is flagged so iTerm2 asks for it again.
                writeOutput(ErrorResponse(error: error,
                                          needsAuthentication: error == wrongMasterPasswordMessage ? true : nil))
                exit(1)
            }
            sessionKey = unlockResult.sessionKey!

        case "unlocked":
            // Already unlocked - we need to get the current session somehow
            // The bw CLI doesn't provide a way to get the current session key
            // We'll unlock again to get a fresh session key
            let unlockResult = unlockVault(path, password: password)
            if let error = unlockResult.error {
                // A wrong password is flagged so iTerm2 asks for it again.
                writeOutput(ErrorResponse(error: error,
                                          needsAuthentication: error == wrongMasterPasswordMessage ? true : nil))
                exit(1)
            }
            sessionKey = unlockResult.sessionKey!

        default:
            writeError("Unknown Bitwarden status: \(status.status)")
            exit(1)
        }

        // Sync the vault to ensure we have the latest data. A sync failure is not fatal (offline,
        // the cached vault still works). Note that sync succeeds even with an invalid session,
        // so it can’t be used to check the session.
        _ = runBitwardenCommand(path, args: ["sync"], session: sessionKey)

        // Make sure bw accepts the session it just issued, using a command that needs it. If it
        // doesn’t, nothing else will work, and logging in again won’t help either, so say so
        // now rather than failing on the next command.
        let checkResult = runBitwardenCommand(path, args: ["list", "folders"], session: sessionKey)
        if checkResult.exitCode != 0 && isSessionRejection(checkResult) {
            writeError("The Bitwarden CLI unlocked the vault but then rejected its own session (\(checkResult.errorMessage)). This usually means its saved state is damaged. In a terminal, run “bw logout” and then “bw login”, and make sure the Bitwarden CLI is up to date.")
            exit(1)
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
            switch getFolderId(named: folderName, path: path, session: session) {
            case .failure(let error):
                writeBitwardenError(error)
                exit(1)
            case .success(.found(let folderId)):
                listArgs.append(contentsOf: ["--folderid", folderId])
            case .success(.missing):
                // Nothing has been added from iTerm2 yet. Say why the list is empty.
                let warning = "iTerm2 shows only Bitwarden items in a folder named “\(folderName)”, and your vault has no such folder yet. Items you add from iTerm2 are saved there, or you can move existing items into it."
                writeOutput(ListAccountsResponse(accounts: [], warning: warning))
                return
            }
        } else {
            // Browser mode: get items in root (no folder)
            listArgs.append(contentsOf: ["--folderid", "null"])
        }

        let result = runBitwardenCommand(path, args: listArgs, session: session)

        if result.exitCode != 0 {
            writeBitwardenError("Failed to list accounts", result)
            exit(1)
        }

        // Parse the JSON output
        guard let items = try? decoder.decode([BitwardenItem].self, from: Data(result.stdout.utf8)) else {
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
            writeBitwardenError("Failed to get password", passwordResult)
            exit(1)
        }

        let passwordValue = passwordResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to get TOTP if available
        var otpValue: String? = nil
        let totpResult = runBitwardenCommand(path, args: ["get", "totp", itemId], session: session)
        if totpResult.exitCode == 0 {
            let totp = totpResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
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
            writeBitwardenError("Failed to get item", getResult)
            exit(1)
        }

        // Parse and modify the item
        guard let itemData = getResult.stdout.data(using: .utf8),
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
            writeBitwardenError("Failed to set password", editResult)
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
            switch getOrCreateFolderId(named: folderName, path: path, session: session) {
            case .success(let id):
                folderId = id
            case .failure(let error):
                writeBitwardenError(error)
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
            writeBitwardenError("Failed to add account", createResult)
            exit(1)
        }

        // Parse the created item to get its ID
        guard let createdItemData = createResult.stdout.data(using: .utf8),
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
            writeBitwardenError("Failed to delete account", deleteResult)
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
    // Writing to a bw that exited early must fail with EPIPE, not kill the adapter before it
    // can report bw’s error.
    signal(SIGPIPE, SIG_IGN)

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
