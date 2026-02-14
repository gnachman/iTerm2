// Password Manager CLI for KeePassXC
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

// MARK: - Global State

var databasePath: String?
var masterPassword: String?

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

func runCommand(_ command: String, args: [String], input: String? = nil) -> (output: String, exitCode: Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + args

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
        let error = String(data: errorData, encoding: .utf8) ?? ""

        let combined = output + error

        return (combined, process.terminationStatus)
    } catch {
        return ("Failed to run command: \(error.localizedDescription)", -1)
    }
}

func runKeePassXCCommand(_ path: String?, command: String, options: [String] = [], additionalArgs: [String] = [], password: String, extraInput: String = "") -> (output: String, exitCode: Int32) {
    guard let dbPath = databasePath else {
        return ("Database path not set. ", -1)
    }
    guard let path else {
        return ("No path to keepassxc-cli was provided", -1)
    }

    // Run keepassxc-cli with password on stdin
    // Format: keepassxc-cli <command> [options] <database> [additional args]
    // Always use --quiet to suppress password prompts
    let allArgs = [command, "--quiet"] + options + [dbPath] + additionalArgs
    let input = password + "\n" + extraInput
    return runCommand(path, args: allArgs, input: input)
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

func extractDatabasePath(from header: PasswordManagerProtocol.RequestHeader) {
    guard let path = header.pathToDatabase, !path.isEmpty else {
        writeError("Database path is required in request header")
        exit(1)
    }
    databasePath = path
}

func modeTag(from mode: PasswordManagerProtocol.RequestHeader.Mode) -> String? {
    switch mode {
    case .terminal:
        return "iTerm2"
    case .browser:
        return nil
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
            name: "KeePassXC",
            requiresMasterPassword: true,
            canSetPasswords: true,
            userAccounts: nil,
            needsPathToDatabase: true,
            databaseExtension: "kdbx",
            needsPathToExecutable: "keepassxc-cli"
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

        extractDatabasePath(from: request.header)

        guard let password = request.masterPassword, !password.isEmpty else {
            writeError("Master password is required")
            exit(1)
        }

        // Verify the password by attempting to access the database
        let result = runKeePassXCCommand(request.header.pathToExecutable, command: "ls", options: [], additionalArgs: [], password: password)

        if result.exitCode != 0 {
            if result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                writeError("Invalid master password or database error.")
            } else {
                writeError("Invalid master password or database error: \(result.output)")
            }
            exit(1)
        }

        // Encode the password in the token (base64) so it can be passed to future commands
        // In a real implementation, you might want to use keychain or encrypt this
        let token = password.data(using: .utf8)?.base64EncodedString() ?? ""

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

        extractDatabasePath(from: request.header)

        // Decode the token to get the password
        guard let password = decodeToken(request.token) else {
            writeError("Invalid or missing token. Please login first.")
            exit(1)
        }

        // Call keepassxc-cli ls with --flatten and --recursive
        let result = runKeePassXCCommand(request.header.pathToExecutable, command: "ls", options: ["--flatten", "--recursive"], password: password)

        if result.exitCode != 0 {
            writeError("Failed to list accounts: \(result.output)")
            exit(1)
        }

        // Parse the output to get entry paths
        let lines = result.output.components(separatedBy: .newlines)
        let modeFolder = modeTag(from: request.header.mode)

        let entryPaths: [String]
        if let folder = modeFolder {
            // Terminal mode: filter for entries in the iTerm2 folder
            let modePrefix = folder + "/"
            entryPaths = lines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .filter { !$0.hasPrefix("Recycle Bin/") && $0 != "Recycle Bin" }
                .filter { $0.hasPrefix(modePrefix) }
                .filter { $0 != folder } // Exclude the mode folder itself
                .filter { $0 != modePrefix } // Exclude the mode folder with trailing slash
                .filter { !$0.hasSuffix("/[empty]") } // Exclude empty group entries
        } else {
            // Browser mode: get entries in the root (not in any folder)
            entryPaths = lines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .filter { !$0.hasPrefix("Recycle Bin/") && $0 != "Recycle Bin" }
                .filter { !$0.contains("/") } // Only root-level entries (no folder separator)
        }

        // Process entries in parallel batches of 4
        let batchSize = 4
        var accounts: [Account] = []

        for startIndex in stride(from: 0, to: entryPaths.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, entryPaths.count)
            let batch = Array(entryPaths[startIndex..<endIndex])

            // Create a dispatch group for parallel execution
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "com.iterm2.keepassxc-adapter", attributes: .concurrent)
            let accountsLock = NSLock()

            for entryPath in batch {
                group.enter()
                queue.async {
                    defer { group.leave() }

                    // Extract the entry name (last component of path)
                    let components = entryPath.components(separatedBy: "/")
                    let entryName = components.last ?? entryPath

                    // Get entry details using show command to extract username and check for OTP
                    let showResult = runKeePassXCCommand(request.header.pathToExecutable, command: "show", options: ["-s"], additionalArgs: [entryPath], password: password)

                    var userName = ""
                    var hasOTP = false

                    if showResult.exitCode == 0 {
                        let showLines = showResult.output.components(separatedBy: .newlines)
                        for showLine in showLines {
                            let showTrimmed = showLine.trimmingCharacters(in: .whitespaces)
                            // Parse "UserName: <username>"
                            if showTrimmed.hasPrefix("UserName: ") {
                                userName = String(showTrimmed.dropFirst("UserName: ".count))
                            }
                            // Check if TOTP exists by looking for TOTP-related attributes
                            if showTrimmed.hasPrefix("TOTP") {
                                hasOTP = true
                            }
                        }
                    }

                    let account = Account(
                        identifier: AccountIdentifier(accountID: entryPath),
                        userName: userName,
                        accountName: entryName,
                        hasOTP: hasOTP
                    )

                    accountsLock.lock()
                    accounts.append(account)
                    accountsLock.unlock()
                }
            }

            // Wait for all tasks in this batch to complete
            group.wait()
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

        extractDatabasePath(from: request.header)

        // Decode the token to get the password
        guard let password = decodeToken(request.token) else {
            writeError("Invalid or missing token. Please login first.")
            exit(1)
        }

        // Use keepassxc-cli show to get the password
        // -s shows protected attributes in clear text
        // -a password gets the password attribute
        let entryPath = request.accountIdentifier.accountID

        let result = runKeePassXCCommand(request.header.pathToExecutable, command: "show", options: ["-s", "-a", "Password"], additionalArgs: [entryPath], password: password)

        if result.exitCode != 0 {
            writeError("Failed to get password: \(result.output)")
            exit(1)
        }

        // The output is just the password value
        let passwordValue = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to get TOTP if available
        let totpResult = runKeePassXCCommand(request.header.pathToExecutable, command: "show", options: ["--totp"], additionalArgs: [entryPath], password: password)

        var otpValue: String? = nil
        if totpResult.exitCode == 0 {
            let totp = totpResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !totp.isEmpty && !totp.contains("ERROR") {
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

        extractDatabasePath(from: request.header)

        // Decode the token to get the password
        guard let password = decodeToken(request.token) else {
            writeError("Invalid or missing token. Please login first.")
            exit(1)
        }

        guard let newPassword = request.newPassword else {
            writeError("New password is required")
            exit(1)
        }

        // Use keepassxc-cli edit with -p to change the password
        let entryPath = request.accountIdentifier.accountID

        // The edit command with -p expects the new password on stdin (after the database password)
        let result = runKeePassXCCommand(request.header.pathToExecutable, command: "edit", options: ["-p"], additionalArgs: [entryPath], password: password, extraInput: newPassword + "\n" + newPassword + "\n")

        if result.exitCode != 0 {
            writeError("Failed to set password: \(result.output)")
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

        extractDatabasePath(from: request.header)

        // Decode the token to get the password
        guard let password = decodeToken(request.token) else {
            writeError("Invalid or missing token. Please login first.")
            exit(1)
        }

        // Use keepassxc-cli add to create a new entry
        // Create entry within a folder based on mode (terminal uses iTerm2 folder, browser uses root)
        let modeFolder = modeTag(from: request.header.mode)
        let entryPath: String

        if let folder = modeFolder {
            // Terminal mode: create in iTerm2 folder
            entryPath = "\(folder)/\(request.accountName)"

            // Ensure the mode folder exists
            let lsResult = runKeePassXCCommand(request.header.pathToExecutable, command: "ls", options: [], additionalArgs: [], password: password)
            if !lsResult.output.contains(folder) {
                // Create the mode folder
                let mkdirResult = runKeePassXCCommand(request.header.pathToExecutable, command: "mkdir", options: [], additionalArgs: [folder], password: password)
                if mkdirResult.exitCode != 0 {
                    writeError("Failed to create mode folder: \(mkdirResult.output)")
                    exit(1)
                }
            }
        } else {
            // Browser mode: create in root
            entryPath = request.accountName
        }

        // Check if there's an entry with the same name in the Recycle Bin
        // If so, permanently delete it first
        let recycleBinPath = "Recycle Bin/\(entryPath)"
        let checkResult = runKeePassXCCommand(request.header.pathToExecutable, command: "show", options: ["-s", "-a", "Title"], additionalArgs: [recycleBinPath], password: password)

        if checkResult.exitCode == 0 {
            // Entry exists in Recycle Bin, permanently delete it
            _ = runKeePassXCCommand(request.header.pathToExecutable, command: "rm", options: [], additionalArgs: [recycleBinPath], password: password)
        }

        // Build extra input for the add command
        var extraInput = ""
        if let entryPassword = request.password {
            // If password is provided, use -p option
            extraInput = entryPassword + "\n" + entryPassword + "\n"
        }

        let options = request.password != nil ? ["-p", "-u", request.userName] : ["-u", request.userName]

        let result = runKeePassXCCommand(request.header.pathToExecutable, command: "add", options: options, additionalArgs: [entryPath], password: password, extraInput: extraInput)

        if result.exitCode != 0 {
            writeError("Failed to add account: \(result.output)")
            exit(1)
        }

        // Return the account identifier (use the full entry path as the ID)
        let response = AddAccountResponse(accountIdentifier: AccountIdentifier(accountID: entryPath))
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

        extractDatabasePath(from: request.header)

        // Decode the token to get the password
        guard let password = decodeToken(request.token) else {
            writeError("Invalid or missing token. Please login first.")
            exit(1)
        }

        // Use keepassxc-cli rm to delete the entry
        let entryPath = request.accountIdentifier.accountID

        let result = runKeePassXCCommand(request.header.pathToExecutable, command: "rm", options: [], additionalArgs: [entryPath], password: password)

        if result.exitCode != 0 {
            writeError("Failed to delete account: \(result.output)")
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
        writeError("Usage: pwmplugin <command>")
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
