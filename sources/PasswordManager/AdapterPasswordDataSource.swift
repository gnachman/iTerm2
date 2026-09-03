//
//  AdapterPasswordDataSource.swift
//  iTerm2SharedARC
//
//  Created by Claude Code on 10/21/25.
//

import Foundation
import UniformTypeIdentifiers

/// A password manager data source that communicates with an external adapter
/// using the generic password manager protocol defined in pwmplugin/Docs/spec.md
class AdapterPasswordDataSource: CommandLinePasswordDataSource {
    enum AdapterError: LocalizedError {
        case runtime(String)
        case loginFailed(String)

        case needsAuthentication
        case badOutput
        case canceledByUser
        case handshakeFailed
        case incompatibleProtocol
        case adapterNotFound
        case invalidToken

        var reason: String? {
            switch self {
            case .runtime(let message):
                return message
            case .loginFailed(let message):
                return String(format: String(localized: "AdapterPasswordDataSource_CouldNotLogIn_FORMAT", defaultValue: "Could not log in: %1$@", comment: "Formatted user-facing text in message"), message)
            case .needsAuthentication:
                return String(localized: "AdapterPasswordDataSource_NotAuthenticated", defaultValue: "Not authenticated.", comment: "User-visible message: Not authenticated.")
            case .badOutput:
                return String(localized: "AdapterPasswordDataSource_InvalidOutput", defaultValue: "Invalid output.", comment: "User-visible message: Invalid output.")
            case .canceledByUser:
                return nil
            case .handshakeFailed:
                return String(localized: "AdapterPasswordDataSource_HandshakeFailed", defaultValue: "Handshake failed.", comment: "User-visible message: Handshake failed.")
            case .incompatibleProtocol:
                return String(localized: "AdapterPasswordDataSource_IncompatibleProtocolPleaseUpdateITerm2", defaultValue: "Incompatible protocol. Please update iTerm2.", comment: "User-visible message: Incompatible protocol. Please update iTerm2.")
            case .adapterNotFound:
                return String(localized: "AdapterPasswordDataSource_AdapterNotFound", defaultValue: "Adapter not found.", comment: "User-visible message: Adapter not found.")
            case .invalidToken:
                return String(localized: "AdapterPasswordDataSource_AuthenticationFailedLogInAgain", defaultValue: "Authentication failed. Log in again.", comment: "User-visible message: Authentication failed. Log in again.")
            }
        }

        var errorDescription: String? {
            reason ?? String(localized: "AdapterPasswordDataSource_UnknownError", defaultValue: "Unknown error", comment: "User-visible message: Unknown error")
        }

        // Classifies an adapter error response. A response flagged needsAuthentication becomes
        // .needsAuthentication so the recipe recovery clears the token and re-logs in; every
        // other response is an ordinary .runtime error. Adapters that never set the flag behave
        // as before (all errors are .runtime).
        static func from(_ response: PasswordManagerProtocol.ErrorResponse) -> AdapterError {
            if response.needsAuthentication == true {
                return .needsAuthentication
            }
            return .runtime(response.error)
        }

        // Decodes and classifies an adapter error response from raw stdout, or nil when the
        // output is not an error response. Centralizes the preamble every recipe
        // outputTransformer would otherwise repeat, so error classification lives in one place.
        static func decoded(fromAdapterOutput data: Data) -> AdapterError? {
            guard let response = try? JSONDecoder().decode(PasswordManagerProtocol.ErrorResponse.self, from: data) else {
                return nil
            }
            return AdapterError.from(response)
        }
    }

    // Type aliases for protocol types
    private typealias HandshakeRequest = PasswordManagerProtocol.HandshakeRequest
    private typealias HandshakeResponse = PasswordManagerProtocol.HandshakeResponse
    private typealias UserAccount = PasswordManagerProtocol.UserAccount
    private typealias LoginRequest = PasswordManagerProtocol.LoginRequest
    private typealias LoginResponse = PasswordManagerProtocol.LoginResponse
    private typealias ListAccountsRequest = PasswordManagerProtocol.ListAccountsRequest
    private typealias ListAccountsResponse = PasswordManagerProtocol.ListAccountsResponse
    private typealias AccountEntry = PasswordManagerProtocol.Account
    private typealias AccountIdentifierEntry = PasswordManagerProtocol.AccountIdentifier
    private typealias GetPasswordRequest = PasswordManagerProtocol.GetPasswordRequest
    private typealias PasswordResponse = PasswordManagerProtocol.Password
    private typealias SetPasswordRequest = PasswordManagerProtocol.SetPasswordRequest
    private typealias SetPasswordResponse = PasswordManagerProtocol.SetPasswordResponse
    private typealias AddAccountRequest = PasswordManagerProtocol.AddAccountRequest
    private typealias AddAccountResponse = PasswordManagerProtocol.AddAccountResponse
    private typealias DeleteAccountRequest = PasswordManagerProtocol.DeleteAccountRequest
    private typealias DeleteAccountResponse = PasswordManagerProtocol.DeleteAccountResponse
    private typealias CustomCommandRequest = PasswordManagerProtocol.CustomCommandRequest
    private typealias CustomCommandResponse = PasswordManagerProtocol.CustomCommandResponse
    private typealias ErrorResponse = PasswordManagerProtocol.ErrorResponse

    private let browser: Bool
    private let adapterPath: String
    private var handshakeInfo: HandshakeResponse?
    private var authToken: String?
    private var userAccountID: String?
    private let iTermVersion: String
    private let identifier: String
    private var pathToDatabase: String?
    private var pathToExecutable: String?
    private var masterPassword: String?
    private let userAccountKey = "NoSyncAdapaterPasswordDataSource_"

    init(browser: Bool, adapterPath: String, identifier: String) {
        self.browser = browser
        self.adapterPath = adapterPath
        self.identifier = identifier
        // Get iTerm2 version
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            self.iTermVersion = version
        } else {
            self.iTermVersion = "unknown"
        }
        userAccountID = iTermUserDefaults.userDefaults().string(forKey: userAccountKey + identifier)
    }

    // MARK: - Helper Methods

    private func runAdapterCommand<Request: Encodable, Response: Decodable>(
        _ subcommand: String,
        request: Request,
        completion: @escaping (Result<Response, Error>) -> ()
    ) {
        let encoder = JSONEncoder()
        guard let inputData = try? encoder.encode(request) else {
            completion(.failure(AdapterError.badOutput))
            return
        }

        let command = CommandRequestWithInput(
            command: adapterPath,
            args: [subcommand],
            env: [:],
            input: inputData)

        command.execAsync { output, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let output = output else {
                    completion(.failure(AdapterError.runtime(String(localized: "AdapterPasswordDataSource_NoOutputFromAdapter", defaultValue: "No output from adapter", comment: "Text shown in runAdapterCommand: No output from adapter"))))
                    return
                }

                // Try to decode as error response first
                let decoder = JSONDecoder()
                if let error = AdapterError.decoded(fromAdapterOutput: output.stdout) {
                    completion(.failure(error))
                    return
                }

                if output.returnCode != 0 {
                    completion(.failure(AdapterError.runtime(String(format: String(localized: "AdapterPasswordDataSource_AdapterReturnedCode_FORMAT", defaultValue: "Adapter returned code %1$@", comment: "Formatted user-facing text in runAdapterCommand"), String(output.returnCode)))))
                    return
                }

                // Try to decode as expected response
                guard let response = try? decoder.decode(Response.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    // The adapter stdout can contain a login/session token; do not log
                    // its contents into the always-on ring. Log only the byte count.
                    RLog("Failed to decode response from adapter. Output byteCount=\(output.stdout.count)")
                    return
                }

                completion(.success(response))
            }
        }
    }

    private func ensureHandshake(_ completion: @escaping (Error?) -> ()) {
        if handshakeInfo != nil {
            completion(nil)
            return
        }

        let request = HandshakeRequest(
            iTermVersion: iTermVersion,
            minProtocolVersion: 0,
            maxProtocolVersion: 0)

        runAdapterCommand("handshake", request: request) { [weak self] (result: Result<HandshakeResponse, Error>) in
            guard let self = self else { return }

            switch result {
            case .success(let response):
                if response.protocolVersion != 0 {
                    completion(AdapterError.incompatibleProtocol)
                    return
                }
                self.handshakeInfo = response
                completion(nil)
            case .failure(let error):
                completion(error)
            }
        }
    }

    private func requestPathToDatabase(_ handshake: HandshakeResponse) -> Bool {
        if let saved = iTermUserDefaults.userDefaults().string(forKey: "PathToDatabase_\(identifier)") {
            pathToDatabase = saved
            return true
        }

        let kind = handshake.pathToDatabaseKind ?? .file
        switch kind {
        case .file:
            return requestPathToDatabaseViaFilePanel(handshake: handshake)
        case .url:
            return requestPathToDatabaseViaTextField(handshake: handshake)
        }
    }

    private func requestPathToDatabaseViaFilePanel(handshake: HandshakeResponse) -> Bool {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.message = handshakeInfo?.pathToDatabasePrompt ?? "Select a database file for \(identifier)"

        if let ext = handshake.databaseExtension {
            openPanel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        }

        let response = openPanel.runModal()
        guard response == .OK, let selectedURL = openPanel.url else {
            return false
        }

        pathToDatabase = selectedURL.path
        iTermUserDefaults.userDefaults().set(selectedURL.path, forKey: "PathToDatabase_\(identifier)")
        return true
    }

    private func requestPathToDatabaseViaTextField(handshake: HandshakeResponse) -> Bool {
        let alert = NSAlert()
        alert.messageText = handshake.pathToDatabasePrompt ?? String(format: String(localized: "AdapterPasswordDataSource_EnterDatabaseUrlFor_FORMAT", defaultValue: "Enter database URL for %1$@", comment: "Alert title in requestPathToDatabaseViaTextField"), identifier)
        alert.addButton(withTitle: String(localized: "COMMON_OK", defaultValue: "OK", comment: "Button title in requestPathToDatabaseViaTextField"))
        alert.addButton(withTitle: String(localized: "COMMON_CANCEL", defaultValue: "Cancel", comment: "Button title in requestPathToDatabaseViaTextField"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = handshake.pathToDatabasePlaceholder ?? "https://\u{2026}"
        alert.accessoryView = textField
        alert.layout()
        alert.window.makeFirstResponder(textField)

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return false
        }
        let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return false
        }

        pathToDatabase = value
        iTermUserDefaults.userDefaults().set(value, forKey: "PathToDatabase_\(identifier)")
        return true
    }

    private func requestPathToExecutable(_ name: String) -> Bool {
        if let saved = iTermUserDefaults.userDefaults().string(forKey: "PathToExecutable_\(identifier)") {
            pathToExecutable = saved
            return true
        }

        class AdapterCLIFinderOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate {
            private let name: String
            init(name: String) {
                self.name = name
            }
            func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
                if FileManager.default.itemIsDirectory(url.path) {
                    return true
                }
                if url.lastPathComponent == name {
                    return true
                }
                // NSOpenPanel may resolve symlinks before calling this delegate.
                // Homebrew’s ‘bw’ is a chain of symlinks ending at build/bw.js,
                // so accept names like bw.js as well.
                return url.deletingPathExtension().lastPathComponent == name
            }
        }

        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.message = "Locate the CLI for \(identifier) named \(name)"

        let delegate = AdapterCLIFinderOpenPanelDelegate(name: name)
        return withExtendedLifetime(delegate) {
            openPanel.delegate = delegate
            let response = openPanel.runModal()
            guard response == .OK, let selectedURL = openPanel.url else {
                return false
            }

            pathToExecutable = selectedURL.path
            iTermUserDefaults.userDefaults().set(selectedURL.path, forKey: "PathToExecutable_\(identifier)")
            return true
        }
    }

    private var standardHeader: PasswordManagerProtocol.RequestHeader {
        var header = PasswordManagerProtocol.RequestHeader(
            pathToDatabase: pathToDatabase,
            pathToExecutable: pathToExecutable,
            mode: browser ? .browser : .terminal)
        if let fields = handshakeInfo?.settingsFields, !fields.isEmpty {
            var settings = [String: String]()
            for field in fields {
                if let value = storedSettingsValue(forKey: field.key) {
                    settings[field.key] = value
                }
            }
            if !settings.isEmpty {
                header.settings = settings
            }
        }
        return header
    }

    // MARK: - Credential Persistence

    private var keychainCredentialServiceName: String {
        "iTerm2-Adapter-\(identifier)"
    }

    @discardableResult
    private func persistCredentialsToKeychain(_ password: String) -> Bool {
        return SSKeychain.setPassword(password,
                                      forService: keychainCredentialServiceName,
                                      account: identifier)
    }

    private func loadPersistedCredentials() -> String? {
        return try? SSKeychain.password(forService: keychainCredentialServiceName,
                                        account: identifier)
    }

    private func deletePersistedCredentials() {
        _ = SSKeychain.deletePassword(forService: keychainCredentialServiceName,
                                      account: identifier)
    }

    private func hydratePersistedCredentialsIfNeeded() {
        guard handshakeInfo?.persistsCredentials == true else { return }
        // migrateLegacyCredentialsIfNeeded is the single reader of the credential slot: it
        // reads the keychain and copies a persisted value into masterPassword (migrating a
        // legacy entry first if the slot is empty). No second read is needed here.
        migrateLegacyCredentialsIfNeeded()
        if pathToDatabase == nil {
            if let u = iTermUserDefaults.userDefaults().string(forKey: "PathToDatabase_\(identifier)"), !u.isEmpty {
                pathToDatabase = u
            }
        }
    }

    // MARK: - Settings Field Storage

    private func storedSettingsValue(forKey key: String) -> String? {
        guard let fields = handshakeInfo?.settingsFields else { return nil }
        guard let field = fields.first(where: { $0.key == key }) else { return nil }
        if field.persistInKeychain {
            return try? SSKeychain.password(forService: keychainCredentialServiceName, account: key)
        } else {
            return iTermUserDefaults.userDefaults().string(forKey: "AdapterSetting_\(identifier)_\(key)")
        }
    }

    private func storeSettingsValue(_ value: String, forKey key: String) {
        guard let fields = handshakeInfo?.settingsFields else { return }
        guard let field = fields.first(where: { $0.key == key }) else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if field.persistInKeychain {
            if trimmed.isEmpty {
                _ = SSKeychain.deletePassword(forService: keychainCredentialServiceName, account: key)
            } else {
                _ = SSKeychain.setPassword(trimmed, forService: keychainCredentialServiceName, account: key)
            }
        } else {
            if trimmed.isEmpty {
                iTermUserDefaults.userDefaults().removeObject(forKey: "AdapterSetting_\(identifier)_\(key)")
            } else {
                iTermUserDefaults.userDefaults().set(trimmed, forKey: "AdapterSetting_\(identifier)_\(key)")
            }
        }
    }

    private func deleteAllSettingsFieldStorage() {
        if let fields = handshakeInfo?.settingsFields {
            for field in fields {
                if field.persistInKeychain {
                    _ = SSKeychain.deletePassword(forService: keychainCredentialServiceName, account: field.key)
                } else {
                    iTermUserDefaults.userDefaults().removeObject(forKey: "AdapterSetting_\(identifier)_\(field.key)")
                }
            }
        }
        deleteOrphanedLegacyCredentials()
    }

    /// Migrate any adapter-declared legacy credential entries into the master-password
    /// slot once. Adapter-agnostic: the adapter names the legacy keychain account in its
    /// handshake (`legacyCredentialMigrations`), so no adapter specifics live here.
    ///
    /// The keychain slot itself is the check: if it already holds a value, nothing is
    /// copied. Otherwise the first available legacy entry is copied up, and the orphan is
    /// deleted only after the copy is confirmed. A failed or momentarily-locked keychain
    /// read or write can never destroy the only copy, and migration retries on the next
    /// hydrate.
    private func migrateLegacyCredentialsIfNeeded() {
        let current = loadPersistedCredentials()
        if let current, !current.isEmpty {
            if masterPassword == nil || masterPassword!.isEmpty {
                masterPassword = current
            }
            return
        }
        for migration in handshakeInfo?.legacyCredentialMigrations ?? [] {
            let account = migration.fromKeychainAccount
            guard !account.isEmpty,
                  let legacy = try? SSKeychain.password(forService: keychainCredentialServiceName,
                                                        account: account),
                  !legacy.isEmpty else {
                continue
            }
            guard persistCredentialsToKeychain(legacy) else {
                // Keep the legacy entry so migration retries on the next hydrate.
                continue
            }
            if masterPassword == nil || masterPassword!.isEmpty {
                masterPassword = legacy
            }
            _ = SSKeychain.deletePassword(forService: keychainCredentialServiceName, account: account)
            return
        }
    }

    /// Purge orphaned legacy credential entries (reset path). Does not migrate.
    private func deleteOrphanedLegacyCredentials() {
        for migration in handshakeInfo?.legacyCredentialMigrations ?? [] {
            guard !migration.fromKeychainAccount.isEmpty else { continue }
            _ = SSKeychain.deletePassword(forService: keychainCredentialServiceName,
                                          account: migration.fromKeychainAccount)
        }
    }

    private func ensureAuthentication(window: NSWindow?, _ completion: @escaping (Error?) -> ()) {
        ensureHandshake { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                completion(error)
                return
            }

            // Try to restore persisted credentials before prompting.
            self.hydratePersistedCredentialsIfNeeded()

            // If we already have a token, we're done
            if self.authToken != nil {
                completion(nil)
                return
            }

            guard let handshake = self.handshakeInfo else {
                completion(AdapterError.handshakeFailed)
                return
            }

            // Pick database first since the master password depends on which db you're using.
            if handshake.needsPathToDatabase && pathToDatabase == nil {
                if !requestPathToDatabase(handshake) {
                    completion(AdapterError.canceledByUser)
                    return
                }
            }

            if let executableName = handshake.needsPathToExecutable, pathToExecutable == nil {
                if !requestPathToExecutable(executableName) {
                    completion(AdapterError.canceledByUser)
                    return
                }
            }

            // If we restored a master password from keychain, auto-login without prompting.
            // When masterPassword is nil (e.g., first launch or requiresMasterPassword is false),
            // this falls through to the normal login() path which prompts the user.
            if handshake.persistsCredentials == true,
               let saved = self.masterPassword, !saved.isEmpty {
                let loginInputs = LoginInputs(window: window,
                                              name: handshake.name,
                                              completion: completion,
                                              requiresMasterPassword: handshake.requiresMasterPassword)
                self.completeEnsureAuthentication(masterPassword: saved, loginInputs: loginInputs)
                return
            }

            let loginInputs = LoginInputs(window: window,
                                          name: handshake.name,
                                          completion: completion,
                                          requiresMasterPassword: handshake.requiresMasterPassword)
            login(loginInputs)
        }
    }

    private func login(_ loginInputs: LoginInputs) {
        // Get master password if required
        if loginInputs.requiresMasterPassword {
            requestPassword(loginInputs)
        } else {
            completeEnsureAuthentication(masterPassword: nil, loginInputs: loginInputs)
        }
    }

    private struct LoginInputs {
        var window: NSWindow?
        var name: String
        var completion: (Error?) -> ()
        var requiresMasterPassword: Bool
    }

    private func requestPassword(_ loginInputs: LoginInputs) {
        let label = handshakeInfo?.masterPasswordLabel ?? String(localized: "AdapterPasswordDataSource_MasterPassword", defaultValue: "master password", comment: "Label text in requestPassword")
        // Use runAsync because macOS 26 is buggy garbage and doesn’t draw an insertion point
        // in an alert’s accessory in a sheet modal.
        ModalPasswordAlert(String(format: String(localized: "AdapterPasswordDataSource_EnterFor_FORMAT", defaultValue: "Enter %1$@ for %2$@:", comment: "Formatted user-facing text in requestPassword"), label, loginInputs.name))
            .runAsync(window: loginInputs.window) { [weak self] masterPassword in
                if let masterPassword {
                    self?.completeEnsureAuthentication(masterPassword: masterPassword,
                                                       loginInputs: loginInputs)
                } else {
                    loginInputs.completion(AdapterError.canceledByUser)
                    return
                }
            }
    }

    // True when a login failure reflects the service being unreachable/slow/wedged rather than a
    // rejected credential, so the caller keeps the saved key instead of discarding it. Until
    // adapters flag auth rejections structurally (ErrorResponse.needsAuthentication), this keys
    // off the adapter's connectivity/timeout/wedged-worker messages.
    private static func errorIsServiceUnavailable(_ error: Error) -> Bool {
        // A structurally-classified auth rejection is definitely NOT a service problem.
        if case AdapterError.needsAuthentication = error { return false }
        let s = ((error as? AdapterError)?.reason ?? error.localizedDescription).lowercased()
        let markers = [
            "timed out", "timeout", "never started processing", "worker appears",
            "restart your keeper commander", "could not connect", "connection refused",
            "cannot connect", "could not reach", "unreachable", "offline",
            "not running", "network connection", "did not complete the request in time",
        ]
        return markers.contains { s.contains($0) }
    }

    private func completeEnsureAuthentication(masterPassword: String?, loginInputs: LoginInputs) {
        // Perform login
        let loginRequest = LoginRequest(
            header: standardHeader,
            userAccountID: self.userAccountID,
            masterPassword: masterPassword)

        self.runAdapterCommand("login", request: loginRequest) { [weak self] (result: Result<LoginResponse, Error>) in
            guard let self = self else { return }

            switch result {
            case .success(let response):
                self.authToken = response.token
                if self.handshakeInfo?.persistsCredentials == true, let masterPassword {
                    self.masterPassword = masterPassword
                    self.persistCredentialsToKeychain(masterPassword)
                }
                loginInputs.completion(nil)
            case .failure(let error):
                // Only forget the saved key on a genuine auth rejection. A connectivity/timeout/
                // service failure (e.g. Commander wedged, down, or unreachable) leaves the key
                // valid; deleting it would force the user to re-enter it every time the service
                // hiccups. Keep it so auto-login retries once the service recovers.
                if !Self.errorIsServiceUnavailable(error) {
                    self.masterPassword = nil
                    self.deletePersistedCredentials()
                }

                if case let .runtime(description) = error as? AdapterError {
                    let loginFailed = AdapterError.loginFailed(description)
                    let selection = iTermWarning.show(withTitle: loginFailed.reason ?? description,
                                                      actions: [String(localized: "AdapterPasswordDataSource_TryAgain", defaultValue: "Try Again", comment: "Action title in completeEnsureAuthentication"), String(localized: "COMMON_CANCEL", defaultValue: "Cancel", comment: "Action title in completeEnsureAuthentication")],
                                                      accessory: nil,
                                                      identifier: nil,
                                                      silenceable: .kiTermWarningTypePersistent,
                                                      heading: String(localized: "AdapterPasswordDataSource_AuthenticationProblem", defaultValue: "Authentication Problem", comment: "Alert heading in completeEnsureAuthentication"),
                                                      window: loginInputs.window)
                    if selection == .kiTermWarningSelection0 {
                        DispatchQueue.main.async {
                            self.login(loginInputs)
                        }
                        return
                    }
                    loginInputs.completion(AdapterError.canceledByUser)
                    return
                }
                loginInputs.completion(error)
            }
        }
    }

    // MARK: - Recipe Builders

    private func makeListAccountsRecipe() -> AnyRecipe<Void, [CommandLinePasswordDataSource.Account]> {
        // Per-adapter so silencing one adapter's list warning does not silence every adapter's.
        let listWarningIdentifier = "NoSyncAdapterListWarning_\(identifier)"
        return AnyRecipe(AsyncCommandRecipe<Void, [CommandLinePasswordDataSource.Account]>(
            inputTransformer: { [weak self] context, _, completion in
                guard let self = self else {
                    completion(.failure(AdapterError.runtime(String(localized: "AdapterPasswordDataSource_DataSourceDeallocated", defaultValue: "Data source deallocated", comment: "Text shown in makeListAccountsRecipe: Data source deallocated"))))
                    return
                }

                self.ensureAuthentication(window: context.window) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    let request = ListAccountsRequest(
                        header: self.standardHeader,
                        userAccountID: self.userAccountID,
                        token: self.authToken)

                    let encoder = JSONEncoder()
                    guard let inputData = try? encoder.encode(request) else {
                        completion(.failure(AdapterError.badOutput))
                        return
                    }

                    let command = CommandRequestWithInput(
                        command: self.adapterPath,
                        args: ["list-accounts"],
                        env: [:],
                        input: inputData)

                    completion(.success(command))
                }
            },
            recovery: { [weak self] error, completion in
                // If authentication failed, clear token and retry
                if case AdapterError.needsAuthentication = error {
                    self?.authToken = nil
                    completion(nil)
                } else {
                    completion(error)
                }
            },
            outputTransformer: { output, completion in
                let decoder = JSONDecoder()

                // Check for error response
                if let error = AdapterError.decoded(fromAdapterOutput: output.stdout) {
                    completion(.failure(error))
                    return
                }

                guard let response = try? decoder.decode(ListAccountsResponse.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    return
                }

                let accounts = response.accounts.map { entry in
                    CommandLinePasswordDataSource.Account(
                        identifier: CommandLinePasswordDataSource.AccountIdentifier(value: entry.identifier.accountID,
                                                                                    sourceLabel: entry.sourceLabel),
                        userName: entry.userName,
                        accountName: entry.accountName,
                        hasOTP: entry.hasOTP,
                        sendOTP: entry.hasOTP,
                        sourceLabel: entry.sourceLabel)
                }

                if let warning = response.warning?.trimmingCharacters(in: .whitespacesAndNewlines), !warning.isEmpty {
                    DispatchQueue.main.async {
                        iTermWarning.show(withTitle: warning,
                                            actions: ["OK"],
                                            accessory: nil,
                                            identifier: listWarningIdentifier,
                                            silenceable: .kiTermWarningTypePermanentlySilenceable,
                                            heading: "Password Manager",
                                            window: nil)
                    }
                }

                completion(.success(accounts))
            }))
    }

    private func makeGetPasswordRecipe() -> AnyRecipe<CommandLinePasswordDataSource.AccountIdentifier, CommandLinePasswordDataSource.Password> {
        return AnyRecipe(AsyncCommandRecipe<CommandLinePasswordDataSource.AccountIdentifier, CommandLinePasswordDataSource.Password>(
            inputTransformer: { [weak self] context, accountIdentifier, completion in
                guard let self = self else {
                    completion(.failure(AdapterError.runtime(String(localized: "AdapterPasswordDataSource_DataSourceDeallocated", defaultValue: "Data source deallocated", comment: "Text shown in makeGetPasswordRecipe: Data source deallocated"))))
                    return
                }

                self.ensureAuthentication(window: context.window) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    let request = GetPasswordRequest(
                        header: self.standardHeader,
                        userAccountID: self.userAccountID,
                        token: self.authToken,
                        accountIdentifier: AccountIdentifierEntry(accountID: accountIdentifier.value))

                    let encoder = JSONEncoder()
                    guard let inputData = try? encoder.encode(request) else {
                        completion(.failure(AdapterError.badOutput))
                        return
                    }

                    let command = CommandRequestWithInput(
                        command: self.adapterPath,
                        args: ["get-password"],
                        env: [:],
                        input: inputData)

                    completion(.success(command))
                }
            },
            recovery: { [weak self] error, completion in
                if case AdapterError.needsAuthentication = error {
                    self?.authToken = nil
                    completion(nil)
                } else {
                    completion(error)
                }
            },
            outputTransformer: { output, completion in
                let decoder = JSONDecoder()

                if let error = AdapterError.decoded(fromAdapterOutput: output.stdout) {
                    completion(.failure(error))
                    return
                }

                guard let response = try? decoder.decode(PasswordResponse.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    return
                }

                completion(.success(CommandLinePasswordDataSource.Password(password: response.password, otp: response.otp)))
            }))
    }

    private func makeSetPasswordRecipe() -> AnyRecipe<CommandLinePasswordDataSource.SetPasswordRequest, Void> {
        return AnyRecipe(AsyncCommandRecipe<CommandLinePasswordDataSource.SetPasswordRequest, Void>(
            inputTransformer: { [weak self] context, setPasswordRequest, completion in
                guard let self = self else {
                    completion(.failure(AdapterError.runtime(String(localized: "AdapterPasswordDataSource_DataSourceDeallocated", defaultValue: "Data source deallocated", comment: "Text shown in makeSetPasswordRecipe: Data source deallocated"))))
                    return
                }

                self.ensureAuthentication(window: context.window) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    guard let handshake = self.handshakeInfo else {
                        completion(.failure(AdapterError.handshakeFailed))
                        return
                    }

                    if !handshake.canSetPasswords {
                        completion(.failure(CommandLineRecipeError.unsupported(reason: String(localized: "AdapterPasswordDataSource_AdapterDoesNotSupportSettingPasswords", defaultValue: "Adapter does not support setting passwords", comment: "Text shown in makeSetPasswordRecipe: Adapter does not support setting passwords"))))
                        return
                    }

                    let request = SetPasswordRequest(
                        header: self.standardHeader,
                        userAccountID: self.userAccountID,
                        token: self.authToken,
                        accountIdentifier: AccountIdentifierEntry(accountID: setPasswordRequest.accountIdentifier.value),
                        newPassword: setPasswordRequest.newPassword,
                        sourceLabel: setPasswordRequest.accountIdentifier.sourceLabel,
                        newAccountName: setPasswordRequest.newAccountName,
                        newUserName: setPasswordRequest.newUserName)

                    let encoder = JSONEncoder()
                    guard let inputData = try? encoder.encode(request) else {
                        completion(.failure(AdapterError.badOutput))
                        return
                    }

                    let command = CommandRequestWithInput(
                        command: self.adapterPath,
                        args: ["set-password"],
                        env: [:],
                        input: inputData)

                    completion(.success(command))
                }
            },
            recovery: { [weak self] error, completion in
                if case AdapterError.needsAuthentication = error {
                    self?.authToken = nil
                    completion(nil)
                } else {
                    completion(error)
                }
            },
            outputTransformer: { output, completion in
                let decoder = JSONDecoder()

                if let error = AdapterError.decoded(fromAdapterOutput: output.stdout) {
                    completion(.failure(error))
                    return
                }

                // Just verify we can decode the response
                guard let _ = try? decoder.decode(SetPasswordResponse.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    return
                }

                completion(.success(()))
            }))
    }

    private func makeDeleteRecipe() -> AnyRecipe<CommandLinePasswordDataSource.AccountIdentifier, Void> {
        return AnyRecipe(AsyncCommandRecipe<CommandLinePasswordDataSource.AccountIdentifier, Void>(
            inputTransformer: { [weak self] context, accountIdentifier, completion in
                guard let self = self else {
                    completion(.failure(AdapterError.runtime(String(localized: "AdapterPasswordDataSource_DataSourceDeallocated", defaultValue: "Data source deallocated", comment: "Text shown in makeDeleteRecipe: Data source deallocated"))))
                    return
                }

                self.ensureAuthentication(window: context.window) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    let request = DeleteAccountRequest(
                        header: self.standardHeader,
                        userAccountID: self.userAccountID,
                        token: self.authToken,
                        accountIdentifier: AccountIdentifierEntry(accountID: accountIdentifier.value),
                        sourceLabel: accountIdentifier.sourceLabel)

                    let encoder = JSONEncoder()
                    guard let inputData = try? encoder.encode(request) else {
                        completion(.failure(AdapterError.badOutput))
                        return
                    }

                    let command = CommandRequestWithInput(
                        command: self.adapterPath,
                        args: ["delete-account"],
                        env: [:],
                        input: inputData)

                    completion(.success(command))
                }
            },
            recovery: { [weak self] error, completion in
                if case AdapterError.needsAuthentication = error {
                    self?.authToken = nil
                    completion(nil)
                } else {
                    completion(error)
                }
            },
            outputTransformer: { output, completion in
                let decoder = JSONDecoder()

                if let error = AdapterError.decoded(fromAdapterOutput: output.stdout) {
                    completion(.failure(error))
                    return
                }

                guard let _ = try? decoder.decode(DeleteAccountResponse.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    return
                }

                // The list cache is invalidated by the shared CommandLineProvidedAccount.delete
                // completion, which owns invalidation for every data source.
                completion(.success(()))
            }))
    }

    private func makeAddAccountRecipe() -> AnyRecipe<CommandLinePasswordDataSource.AddRequest, CommandLinePasswordDataSource.AccountIdentifier> {
        return AnyRecipe(AsyncCommandRecipe<CommandLinePasswordDataSource.AddRequest, CommandLinePasswordDataSource.AccountIdentifier>(
            inputTransformer: { [weak self] context, addRequest, completion in
                guard let self = self else {
                    completion(.failure(AdapterError.runtime(String(localized: "AdapterPasswordDataSource_DataSourceDeallocated", defaultValue: "Data source deallocated", comment: "Text shown in makeAddAccountRecipe: Data source deallocated"))))
                    return
                }

                self.ensureAuthentication(window: context.window) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    let request = AddAccountRequest(
                        header: self.standardHeader,
                        userAccountID: self.userAccountID,
                        token: self.authToken,
                        userName: addRequest.userName,
                        accountName: addRequest.accountName,
                        password: addRequest.password,
                        flags: addRequest.flags.isEmpty ? nil : addRequest.flags)

                    let encoder = JSONEncoder()
                    guard let inputData = try? encoder.encode(request) else {
                        completion(.failure(AdapterError.badOutput))
                        return
                    }

                    let command = CommandRequestWithInput(
                        command: self.adapterPath,
                        args: ["add-account"],
                        env: [:],
                        input: inputData)

                    completion(.success(command))
                }
            },
            recovery: { [weak self] error, completion in
                if case AdapterError.needsAuthentication = error {
                    self?.authToken = nil
                    completion(nil)
                } else {
                    completion(error)
                }
            },
            outputTransformer: { output, completion in
                let decoder = JSONDecoder()

                if let error = AdapterError.decoded(fromAdapterOutput: output.stdout) {
                    completion(.failure(error))
                    return
                }

                guard let response = try? decoder.decode(AddAccountResponse.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    return
                }

                // The list cache is invalidated by standardAdd's completion, which owns
                // invalidation for every data source.
                completion(.success(CommandLinePasswordDataSource.AccountIdentifier(value: response.accountIdentifier.accountID)))
            }))
    }

    private lazy var _listAccountsRecipe: AnyRecipe<Void, [CommandLinePasswordDataSource.Account]> = {
        // Cache for 30 minutes like OnePasswordDataSource
        return AnyRecipe(CachingVoidRecipe(makeListAccountsRecipe(), maxAge: 30 * 60))
    }()

    fileprivate func invalidateListAccountsCache() {
        _listAccountsRecipe.invalidateRecipe()
    }

    var configuration: Configuration {
        return Configuration(
            listAccountsRecipe: _listAccountsRecipe,
            getPasswordRecipe: makeGetPasswordRecipe(),
            setPasswordRecipe: makeSetPasswordRecipe(),
            deleteRecipe: makeDeleteRecipe(),
            addAccountRecipe: makeAddAccountRecipe())
    }
}

extension AdapterPasswordDataSource {
    static func showError(window: NSWindow?, error: AdapterError) {
        guard let reason = error.reason else {
            return
        }
        DispatchQueue.main.async {
            iTermWarning.show(withTitle: reason,
                              actions: [String(localized: "COMMON_OK", defaultValue: "OK", comment: "Action title in showError")],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: String(localized: "AdapterPasswordDataSource_PasswordManagerError", defaultValue: "Password Manager Error", comment: "Alert heading in showError"),
                              window: window)
        }
    }
}
// MARK: - PasswordManagerDataSource Protocol

@objc extension AdapterPasswordDataSource: PasswordManagerDataSource {
    @objc var name: String {
        identifier
    }
    @objc var canResetConfiguration: Bool { true }

    @objc func resetConfiguration() {
        pathToDatabase = nil
        pathToExecutable = nil
        authToken = nil
        masterPassword = nil
        iTermUserDefaults.userDefaults().removeObject(forKey: "PathToDatabase_\(identifier)")
        iTermUserDefaults.userDefaults().removeObject(forKey: "PathToExecutable_\(identifier)")
        deletePersistedCredentials()
        deleteAllSettingsFieldStorage()
        handshakeInfo = nil
    }

    var autogeneratedPasswordsOnly: Bool {
        return false
    }

    func checkAvailability() -> Bool {
        return FileManager.default.fileExists(atPath: adapterPath)
    }

    func fetchAccounts(context: RecipeExecutionContext, completion: @escaping ([PasswordManagerAccount]) -> ()) {
        return standardAccounts(context: context,
                                configuration: configuration) { maybeAccounts, maybeError in
            if let error = maybeError as? AdapterError {
                Self.showError(window: context.window, error: error)
            }
            completion(maybeAccounts ?? [])
        }
    }

    @objc var addAccountToggleDescriptions: [[String: Any]]? {
        handshakeInfo?.addAccountToggles?.map { toggle in
            var dict: [String: Any] = [
                "key": toggle.key,
                "label": toggle.label,
                "defaultValue": toggle.defaultValue
            ]
            if let note = toggle.note { dict["note"] = note }
            return dict
        }
    }

    @objc var supportsInPlaceEdit: Bool {
        handshakeInfo?.canEditInPlace ?? false
    }

    @objc var canEditPassword: Bool {
        handshakeInfo?.canSetPasswords ?? false
    }

    // Each adapter declares this in its handshake. Adapters that store the password verbatim
    // (so a blank field would persist an empty password) return true; those that omit an empty
    // password when adding (e.g. Keeper) leave it false.
    @objc var requiresPasswordForAdd: Bool {
        handshakeInfo?.requiresPasswordForAdd ?? false
    }

    @objc func prepareAvailability(_ completion: @escaping () -> ()) { completion() }

    @objc(addUserName:accountName:password:flags:context:completion:)
    func add(userName: String,
             accountName: String,
             password: String,
             flags: [String: Bool],
             context: RecipeExecutionContext,
             completion: @escaping (PasswordManagerAccount?, Error?) -> ()) {
        standardAdd(configuration,
                    userName: userName,
                    accountName: accountName,
                    password: password,
                    flags: flags,
                    context: context,
                    completion: completion)
    }

    func resetErrors() {
        // Clear the session token to allow retry. When persistsCredentials is true,
        // the saved masterPassword will auto-login without prompting on the next attempt.
        authToken = nil
    }

    func reload(_ completion: () -> ()) {
        configuration.listAccountsRecipe.invalidateRecipe()
        completion()
    }

    func consolidateAvailabilityChecks(_ block: () -> ()) {
        // No caching of availability checks needed for adapter
        block()
    }

    func toggleShouldSendOTP(context: RecipeExecutionContext,
                             account: PasswordManagerAccount,
                             completion: @escaping (PasswordManagerAccount?, Error?) -> ()) {
        it_fatalError()
    }

    var supportsMultipleAccounts: Bool {
        handshakeInfo?.userAccounts != nil
    }

    func switchAccount(completion: @escaping () -> ()) {
        let userAccounts = handshakeInfo?.userAccounts ?? []
        let pickedAccountID = AccountPicker.askUserToSelect(from: userAccounts.map {
            AccountPicker.Account(title: $0.name, accountID: $0.identifier)
        })
        userAccountID = pickedAccountID
        iTermUserDefaults.userDefaults().set(pickedAccountID, forKey: userAccountKey + identifier)
        completion()
    }
}

// MARK: - AdapterCapabilities

extension AdapterPasswordDataSource: AdapterCapabilities {
    @objc var hasSettingsFields: Bool {
        !(handshakeInfo?.settingsFields ?? []).isEmpty
    }

    @objc var settingsFieldDescriptions: [[String: Any]]? {
        handshakeInfo?.settingsFields?.map { field in
            var dict: [String: Any] = [
                "key": field.key,
                "label": field.label,
                "isSecret": field.isSecret,
                "persistInKeychain": field.persistInKeychain
            ]
            if let p = field.placeholder { dict["placeholder"] = p }
            if let n = field.note { dict["note"] = n }
            return dict
        }
    }

    @objc var customCommandDescriptions: [[String: String]]? {
        handshakeInfo?.customCommands?.map { cmd in
            var dict: [String: String] = ["name": cmd.name, "label": cmd.label]
            if let icon = cmd.icon { dict["icon"] = icon }
            return dict
        }
    }

    private static let builtInSubcommands: Set<String> = [
        "handshake", "login", "list-accounts", "get-password",
        "set-password", "add-account", "delete-account"
    ]

    @objc func runCustomCommand(_ name: String, window: NSWindow?, completion: @escaping (String?, Error?) -> Void) {
        if Self.builtInSubcommands.contains(name) {
            completion(nil, AdapterError.runtime("Cannot run built-in subcommand \u{201c}\(name)\u{201d} as a custom command"))
            return
        }
        ensureAuthentication(window: window) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                completion(nil, error)
                return
            }
            let request = CustomCommandRequest(
                header: self.standardHeader,
                userAccountID: self.userAccountID,
                token: self.authToken,
                commandName: name)
            self.runAdapterCommand(name, request: request) { [weak self] (result: Result<CustomCommandResponse, Error>) in
                switch result {
                case .success(let response):
                    self?.invalidateListAccountsCache()
                    completion(response.message, nil)
                case .failure(let error):
                    completion(nil, error)
                }
            }
        }
    }

    @objc func settingsValue(forKey key: String) -> String? {
        return storedSettingsValue(forKey: key)
    }

    @objc func setSettingsValue(_ value: String, forKey key: String) {
        guard handshakeInfo?.settingsFields?.contains(where: { $0.key == key }) == true else { return }
        // storeSettingsValue trims before persisting, so storedSettingsValue returns a trimmed
        // string; compare against the trimmed input too, or a re-save that only differs in
        // surrounding whitespace would look like a change.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = storedSettingsValue(forKey: key)
        storeSettingsValue(value, forKey: key)
        // A changed setting (e.g. service URL) can change reachability; clear the session so it
        // re-logs in. Do this only on an actual change: the settings sheet re-saves every field
        // on OK, and clearing the live token for an unchanged value forces a needless re-login.
        if previous != trimmed {
            authToken = nil
        }
    }
}
