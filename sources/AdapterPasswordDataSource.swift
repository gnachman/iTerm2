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
                return "Could not log in: \(message)"
            case .needsAuthentication:
                return "Not authenticated."
            case .badOutput:
                return "Invalid output."
            case .canceledByUser:
                return nil
            case .handshakeFailed:
                return "Handshake failed."
            case .incompatibleProtocol:
                return "Incompatible protocol. Please update iTerm2."
            case .adapterNotFound:
                return "Adapter not found."
            case .invalidToken:
                return "Authentication failed. Log in again."
            }
        }

        var errorDescription: String {
            reason ?? "Unknown error"
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
        userAccountID = UserDefaults.standard.string(forKey: userAccountKey + identifier)
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
                    completion(.failure(AdapterError.runtime("No output from adapter")))
                    return
                }

                // Try to decode as error response first
                let decoder = JSONDecoder()
                if let errorResponse = try? decoder.decode(ErrorResponse.self, from: output.stdout) {
                    completion(.failure(AdapterError.runtime(errorResponse.error)))
                    return
                }

                if output.returnCode != 0 {
                    completion(.failure(AdapterError.runtime("Adapter returned code \(output.returnCode)")))
                    return
                }

                // Try to decode as expected response
                guard let response = try? decoder.decode(Response.self, from: output.stdout) else {
                    let outputString = String(data: output.stdout, encoding: .utf8) ?? "(non-UTF8)"
                    completion(.failure(AdapterError.badOutput))
                    DLog("Failed to decode response from adapter. Output: \(outputString)")
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

    private func requestPathToDatabase(extension: String?) -> Bool {
        if let saved = UserDefaults.standard.string(forKey: "PathToDatabase_\(identifier)") {
            pathToDatabase = saved
            return true
        }

        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.message = "Select a database file for \(identifier)"

        if let ext = `extension` {
            openPanel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        }

        let response = openPanel.runModal()
        guard response == .OK, let selectedURL = openPanel.url else {
            return false
        }

        pathToDatabase = selectedURL.path
        UserDefaults.standard.set(selectedURL.path, forKey: "PathToDatabase_\(identifier)")
        return true
    }

    private func requestPathToExecutable(_ name: String) -> Bool {
        if let saved = UserDefaults.standard.string(forKey: "PathToExecutable_\(identifier)") {
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
                return url.lastPathComponent == name
            }
        }

        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.message = "Locate the CLI for \(identifier) named \(name)"
        openPanel.allowedContentTypes = [UTType.unixExecutable]

        let delegate = AdapterCLIFinderOpenPanelDelegate(name: name)
        return withExtendedLifetime(delegate) {
            openPanel.delegate = delegate
            let response = openPanel.runModal()
            guard response == .OK, let selectedURL = openPanel.url else {
                return false
            }

            pathToExecutable = selectedURL.path
            UserDefaults.standard.set(selectedURL.path, forKey: "PathToExecutable_\(identifier)")
            return true
        }
    }

    private var standardHeader: PasswordManagerProtocol.RequestHeader {
        .init(pathToDatabase: pathToDatabase,
              pathToExecutable: pathToExecutable,
              mode: browser ? .browser : .terminal)
    }

    private func ensureAuthentication(window: NSWindow?, _ completion: @escaping (Error?) -> ()) {
        ensureHandshake { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                completion(error)
                return
            }

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
                if !requestPathToDatabase(extension: handshake.databaseExtension) {
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
        // Use runAsync because macOS 26 is buggy garbage and doesn't draw an insertion point
        // in an alert’s accessory in a sheet modal.
        ModalPasswordAlert("Enter master password for \(loginInputs.name):")
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
                loginInputs.completion(nil)
            case .failure(let error):
                if case let .runtime(description) = error as? AdapterError {
                    let loginFailed = AdapterError.loginFailed(description)
                    let selection = iTermWarning.show(withTitle: loginFailed.reason ?? description,
                                                      actions: ["Try Again", "Cancel"],
                                                      accessory: nil,
                                                      identifier: nil,
                                                      silenceable: .kiTermWarningTypePersistent,
                                                      heading: "Authentication Problem",
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
        return AnyRecipe(AsyncCommandRecipe<Void, [CommandLinePasswordDataSource.Account]>(
            inputTransformer: { [weak self] context, _, completion in
                guard let self = self else {
                    completion(.failure(AdapterError.runtime("Data source deallocated")))
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
                if let errorResponse = try? decoder.decode(ErrorResponse.self, from: output.stdout) {
                    completion(.failure(AdapterError.runtime(errorResponse.error)))
                    return
                }

                guard let response = try? decoder.decode(ListAccountsResponse.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    return
                }

                let accounts = response.accounts.map { entry in
                    CommandLinePasswordDataSource.Account(
                        identifier: CommandLinePasswordDataSource.AccountIdentifier(value: entry.identifier.accountID),
                        userName: entry.userName,
                        accountName: entry.accountName,
                        hasOTP: entry.hasOTP,
                        sendOTP: entry.hasOTP)
                }

                completion(.success(accounts))
            }))
    }

    private func makeGetPasswordRecipe() -> AnyRecipe<CommandLinePasswordDataSource.AccountIdentifier, CommandLinePasswordDataSource.Password> {
        return AnyRecipe(AsyncCommandRecipe<CommandLinePasswordDataSource.AccountIdentifier, CommandLinePasswordDataSource.Password>(
            inputTransformer: { [weak self] context, accountIdentifier, completion in
                guard let self = self else {
                    completion(.failure(AdapterError.runtime("Data source deallocated")))
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

                if let errorResponse = try? decoder.decode(ErrorResponse.self, from: output.stdout) {
                    completion(.failure(AdapterError.runtime(errorResponse.error)))
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
                    completion(.failure(AdapterError.runtime("Data source deallocated")))
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
                        completion(.failure(CommandLineRecipeError.unsupported(reason: "Adapter does not support setting passwords")))
                        return
                    }

                    let request = SetPasswordRequest(
                        header: self.standardHeader,
                        userAccountID: self.userAccountID,
                        token: self.authToken,
                        accountIdentifier: AccountIdentifierEntry(accountID: setPasswordRequest.accountIdentifier.value),
                        newPassword: setPasswordRequest.newPassword)

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

                if let errorResponse = try? decoder.decode(ErrorResponse.self, from: output.stdout) {
                    completion(.failure(AdapterError.runtime(errorResponse.error)))
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
                    completion(.failure(AdapterError.runtime("Data source deallocated")))
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
                        accountIdentifier: AccountIdentifierEntry(accountID: accountIdentifier.value))

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

                if let errorResponse = try? decoder.decode(ErrorResponse.self, from: output.stdout) {
                    completion(.failure(AdapterError.runtime(errorResponse.error)))
                    return
                }

                guard let _ = try? decoder.decode(DeleteAccountResponse.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    return
                }

                completion(.success(()))
            }))
    }

    private func makeAddAccountRecipe() -> AnyRecipe<CommandLinePasswordDataSource.AddRequest, CommandLinePasswordDataSource.AccountIdentifier> {
        return AnyRecipe(AsyncCommandRecipe<CommandLinePasswordDataSource.AddRequest, CommandLinePasswordDataSource.AccountIdentifier>(
            inputTransformer: { [weak self] context, addRequest, completion in
                guard let self = self else {
                    completion(.failure(AdapterError.runtime("Data source deallocated")))
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
                        password: addRequest.password)

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

                if let errorResponse = try? decoder.decode(ErrorResponse.self, from: output.stdout) {
                    completion(.failure(AdapterError.runtime(errorResponse.error)))
                    return
                }

                guard let response = try? decoder.decode(AddAccountResponse.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    return
                }

                completion(.success(CommandLinePasswordDataSource.AccountIdentifier(value: response.accountIdentifier.accountID)))
            }))
    }

    private lazy var _listAccountsRecipe: AnyRecipe<Void, [CommandLinePasswordDataSource.Account]> = {
        // Cache for 30 minutes like OnePasswordDataSource
        return AnyRecipe(CachingVoidRecipe(makeListAccountsRecipe(), maxAge: 30 * 60))
    }()

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
                              actions: ["OK"],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Password Manager Error",
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
        UserDefaults.standard.removeObject(forKey: "PathToDatabase_\(identifier)")
        UserDefaults.standard.removeObject(forKey: "PathToExecutable_\(identifier)")
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

    func add(userName: String,
             accountName: String,
             password: String,
             context: RecipeExecutionContext,
             completion: @escaping (PasswordManagerAccount?, Error?) -> ()) {
        standardAdd(configuration,
                    userName: userName,
                    accountName: accountName,
                    password: password,
                    context: context,
                    completion: completion)
    }

    func resetErrors() {
        // Clear authentication state to allow retry
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
        let identifier = AccountPicker.askUserToSelect(from: userAccounts.map {
            AccountPicker.Account(title: $0.name, accountID: $0.identifier)
        })
        userAccountID = identifier
        UserDefaults.standard.set(identifier, forKey: userAccountKey + identifier)
        completion()
    }
}
